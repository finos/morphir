//! Workspace-local incremental compile cache.
//!
//! A provider that advertises `frontend.incremental` keeps no state of its own:
//! everything it remembers between runs arrives as `CompileRequest.baseline`
//! and leaves as `CompileResult.moduleResults`. This module is where the CLI
//! keeps that memory, under
//! `<workspace>/.morphir/cache/compile/<extension-id>/<package>/`:
//!
//! - `manifest.json` records the key the results were produced under and one
//!   entry per module (status, uri, digests, dependencies).
//! - `modules/<module>.json` holds the last good [`ModuleResult`] for a module,
//!   including its IR, which is what makes a baseline entry reconstructable.
//!
//! The cache never causes a failure. A missing, unreadable, or corrupt cache is
//! simply no baseline, logged at debug level, and the run compiles from
//! scratch. Writes go to a temp file and are renamed into place, so a run that
//! dies mid-write leaves the previous cache intact rather than a half file.

use morphir_extension_sdk::{BaselineModule, CompileBaseline, ModuleResult, ModuleStatus};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, HashSet};
use std::path::{Path, PathBuf};

/// Layout version of the cache directory. A manifest written under any other
/// version is not read, which is how a layout change invalidates old caches
/// without needing to understand them.
///
/// Bumped to "2" when `CacheKey` dropped `prelude_digest`: a manifest written
/// under version "1" describes a key shape this module no longer reads, so it
/// must be ignored rather than misread.
const SCHEMA_VERSION: &str = "2";

/// Everything a baseline's reusability depends on, apart from the sources and
/// the compile context.
///
/// A result compiled under a different extension, extension version, IR
/// version, or `typesOnly` setting describes something else, so a run whose
/// key differs starts from scratch. The compile context itself — IR version,
/// `typesOnly`, prelude, and dependency interfaces — is no longer part of the
/// key: the extension computes its own digest of that context and returns it
/// as `CompileResult.context_digest`, which the manifest stores and the
/// baseline echoes back as `CompileBaseline.context_digest`. The extension is
/// the one that ignores a baseline whose context digest does not match.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CacheKey {
    /// Id of the provider that produced the results.
    pub extension_id: String,
    /// Version of that provider.
    pub extension_version: String,
    /// IR version the results were produced in.
    pub ir_version: String,
    /// Whether the compile asked for types only.
    pub types_only: bool,
}

/// One module's entry in the manifest: enough to describe the cache without
/// reading any module file.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ManifestModule {
    status: ModuleStatus,
    uri: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    source_digest: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    interface_digest: Option<String>,
    #[serde(default)]
    depends_on: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Manifest {
    schema_version: String,
    key: CacheKey,
    /// The compile context digest the extension returned with the results
    /// this manifest records, echoed back as the next baseline's
    /// `context_digest`. `None` when the provider did not supply one.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    context_digest: Option<String>,
    #[serde(default)]
    modules: BTreeMap<String, ManifestModule>,
    updated_at: String,
}

/// The cache directory for one provider's compiles of one package.
#[derive(Debug, Clone)]
pub struct CompileCache {
    root: PathBuf,
}

impl CompileCache {
    /// Open (without creating) the cache for `package` as compiled by
    /// `extension_id` inside `workspace`.
    pub fn open(workspace: &Path, extension_id: &str, package: &str) -> Self {
        let root = workspace
            .join(".morphir")
            .join("cache")
            .join("compile")
            .join(sanitise(extension_id))
            .join(sanitise(package));
        Self { root }
    }

    /// The directory this cache lives in.
    pub fn root(&self) -> &Path {
        &self.root
    }

    /// The baseline to send with the next compile, or `None` when there is
    /// nothing trustworthy to send.
    pub fn read_baseline(&self, key: &CacheKey) -> Option<CompileBaseline> {
        let manifest = self.read_manifest(key)?;
        let modules = manifest
            .modules
            .keys()
            .filter_map(|name| self.baseline_module(name))
            .collect::<Vec<_>>();
        Some(CompileBaseline {
            modules,
            context_digest: manifest.context_digest,
        })
    }

    /// Record `results`, and the compile context digest they were produced
    /// under, as the cache's new contents.
    ///
    /// Every `compiled` result is written out in full. `unchanged`, `failed`,
    /// and `blocked` results keep whatever file they already had: the first
    /// because the provider does not send back IR it reused, the other two
    /// because their last good IR is exactly what the next run needs. Modules
    /// absent from `results` are gone from the sources, so their files go too.
    ///
    /// `context_digest` is `None` when the provider does not supply one; the
    /// manifest then stores `None` and the next baseline carries none either,
    /// which the extension treats as unreusable rather than a match.
    pub fn write_results(
        &self,
        key: &CacheKey,
        context_digest: Option<String>,
        results: &[ModuleResult],
    ) -> std::io::Result<()> {
        let modules_dir = self.root.join("modules");
        std::fs::create_dir_all(&modules_dir)?;
        for result in results {
            if result.status == ModuleStatus::Compiled {
                let encoded = serde_json::to_vec_pretty(result).map_err(std::io::Error::other)?;
                write_atomically(&self.module_path(&result.name), &encoded)?;
            }
        }
        // The sweep runs before the manifest is written, so a failure here
        // leaves module files the manifest does not mention. That is harmless:
        // the key still matches, and a read only ever loads the file named by a
        // manifest entry, so an unmentioned file is invisible until a later
        // successful write removes it.
        self.remove_dropped_module_files(&modules_dir, results)?;
        let manifest = Manifest {
            schema_version: SCHEMA_VERSION.to_owned(),
            key: key.clone(),
            context_digest,
            modules: results
                .iter()
                .map(|result| {
                    (
                        result.name.clone(),
                        ManifestModule {
                            status: result.status,
                            uri: result.uri.clone(),
                            source_digest: result.source_digest.clone(),
                            interface_digest: result.interface_digest.clone(),
                            depends_on: result.depends_on.clone(),
                        },
                    )
                })
                .collect(),
            updated_at: chrono::Utc::now().to_rfc3339(),
        };
        let encoded = serde_json::to_vec_pretty(&manifest).map_err(std::io::Error::other)?;
        write_atomically(&self.manifest_path(), &encoded)
    }

    fn manifest_path(&self) -> PathBuf {
        self.root.join("manifest.json")
    }

    fn module_path(&self, module: &str) -> PathBuf {
        self.root
            .join("modules")
            .join(format!("{}.json", sanitise(module)))
    }

    /// The manifest, when one is there, readable, of this layout version, and
    /// written under the same key as the run that is asking.
    fn read_manifest(&self, key: &CacheKey) -> Option<Manifest> {
        let path = self.manifest_path();
        let bytes = match std::fs::read(&path) {
            Ok(bytes) => bytes,
            Err(error) => {
                if error.kind() != std::io::ErrorKind::NotFound {
                    tracing::debug!(
                        path = %path.display(),
                        %error,
                        "compile cache manifest could not be read; compiling without a baseline"
                    );
                }
                return None;
            }
        };
        let manifest = match serde_json::from_slice::<Manifest>(&bytes) {
            Ok(manifest) => manifest,
            Err(error) => {
                tracing::debug!(
                    path = %path.display(),
                    %error,
                    "compile cache manifest is corrupt; compiling without a baseline"
                );
                return None;
            }
        };
        if manifest.schema_version != SCHEMA_VERSION {
            tracing::debug!(
                path = %path.display(),
                found = %manifest.schema_version,
                expected = SCHEMA_VERSION,
                "compile cache manifest has another layout version; compiling without a baseline"
            );
            return None;
        }
        if &manifest.key != key {
            tracing::debug!(
                path = %path.display(),
                "compile cache was written under another key; compiling without a baseline"
            );
            return None;
        }
        Some(manifest)
    }

    /// The baseline entry for one manifest module, or `None` when its file is
    /// missing, unreadable, or does not carry what a baseline entry needs.
    ///
    /// Everything but the name comes from the module file. The manifest's copy
    /// of the digests and dependencies is there to be read by a person, not to
    /// be mixed with the file's: two sources for one field would mean a
    /// baseline that matches neither.
    fn baseline_module(&self, name: &str) -> Option<BaselineModule> {
        let path = self.module_path(name);
        let bytes = match std::fs::read(&path) {
            Ok(bytes) => bytes,
            Err(error) => {
                if error.kind() != std::io::ErrorKind::NotFound {
                    tracing::debug!(
                        path = %path.display(),
                        %error,
                        "cached module could not be read; leaving it out of the baseline"
                    );
                }
                return None;
            }
        };
        let cached = match serde_json::from_slice::<ModuleResult>(&bytes) {
            Ok(cached) => cached,
            Err(error) => {
                tracing::debug!(
                    path = %path.display(),
                    %error,
                    "cached module is corrupt; leaving it out of the baseline"
                );
                return None;
            }
        };
        Some(BaselineModule {
            name: name.to_owned(),
            uri: cached.uri,
            source_digest: cached.source_digest?,
            interface_digest: cached.interface_digest?,
            depends_on: cached.depends_on,
            ir: cached.ir?,
            frontend_state: cached.frontend_state,
        })
    }

    /// Delete the files of modules that are not in `results`. A module absent
    /// from a compile's results has no source any more, and keeping its IR
    /// would offer the next run a baseline for a module that does not exist.
    fn remove_dropped_module_files(
        &self,
        modules_dir: &Path,
        results: &[ModuleResult],
    ) -> std::io::Result<()> {
        let kept = results
            .iter()
            .map(|result| format!("{}.json", sanitise(&result.name)))
            .collect::<HashSet<_>>();
        for entry in std::fs::read_dir(modules_dir)? {
            let entry = entry?;
            if !entry.file_type()?.is_file() {
                continue;
            }
            let name = entry.file_name().to_string_lossy().into_owned();
            if name.ends_with(".json") && !kept.contains(&name) {
                std::fs::remove_file(entry.path())?;
            }
        }
        Ok(())
    }
}

/// Make `name` safe to use as one path segment: anything outside
/// `[A-Za-z0-9._-]` becomes `_`, so a module or package name cannot escape the
/// cache directory or spell something the filesystem refuses.
///
/// Replacing characters loses information — `A/B` and `A_B` flatten to the same
/// thing — so the segment ends in a short digest of the name it came from. The
/// readable part is still readable; the digest is what makes the segment the
/// name's alone.
fn sanitise(name: &str) -> String {
    let readable = name.chars().map(|character| {
        if character.is_ascii_alphanumeric() || matches!(character, '.' | '_' | '-') {
            character
        } else {
            '_'
        }
    });
    let mut hasher = Sha256::new();
    hasher.update(name.as_bytes());
    let digest = hasher.finalize();
    let mut segment: String = readable.collect();
    segment.push('-');
    for byte in &digest[..4] {
        segment.push_str(&format!("{byte:02x}"));
    }
    segment
}

/// Write `bytes` to `path` through a temp file in the same directory, so a
/// reader either sees the previous contents or the new ones, never a partial
/// file. The temp file is removed on failure rather than left behind.
fn write_atomically(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let directory = path.parent().unwrap_or_else(|| Path::new("."));
    std::fs::create_dir_all(directory)?;
    let mut temp = tempfile::NamedTempFile::new_in(directory)?;
    std::io::Write::write_all(&mut temp, bytes)?;
    temp.as_file().sync_all()?;
    temp.persist(path).map_err(|error| error.error)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use morphir_extension_sdk::ModuleStatus;
    use serde_json::json;

    fn key() -> CacheKey {
        CacheKey {
            extension_id: "morphir-elm-native".into(),
            extension_version: "0.1.0".into(),
            ir_version: "4.0.0".into(),
            types_only: false,
        }
    }

    fn context_digest() -> Option<String> {
        Some("sha256:context".into())
    }

    fn module(name: &str, status: ModuleStatus) -> ModuleResult {
        ModuleResult {
            name: name.into(),
            uri: format!("file:///src/{}.elm", name.replace('.', "/")),
            status,
            source_digest: Some(format!("sha256:source-{name}")),
            interface_digest: Some(format!("sha256:interface-{name}")),
            depends_on: vec!["My.Other".into()],
            ir: Some(json!({ "module": name })),
            frontend_state: None,
            diagnostics: Vec::new(),
        }
    }

    // Requirement: what a compile produced is what the next compile is offered.
    #[test]
    fn results_written_come_back_as_a_baseline() {
        let temp = tempfile::tempdir().unwrap();
        let cache = CompileCache::open(temp.path(), "morphir-elm-native", "example/domain");
        let mut first_result = module("My.Other", ModuleStatus::Compiled);
        first_result.frontend_state = Some(json!("typed-interface"));
        let results = vec![first_result, module("My.Types", ModuleStatus::Compiled)];

        cache
            .write_results(&key(), context_digest(), &results)
            .unwrap();
        let baseline = cache
            .read_baseline(&key())
            .expect("a baseline is available");

        assert_eq!(baseline.context_digest, context_digest());
        let names: Vec<_> = baseline
            .modules
            .iter()
            .map(|module| module.name.clone())
            .collect();
        assert_eq!(names, vec!["My.Other".to_owned(), "My.Types".to_owned()]);
        let first = &baseline.modules[0];
        assert_eq!(first.source_digest, "sha256:source-My.Other");
        assert_eq!(first.interface_digest, "sha256:interface-My.Other");
        assert_eq!(first.depends_on, vec!["My.Other".to_owned()]);
        assert_eq!(first.ir, json!({ "module": "My.Other" }));
        assert_eq!(first.frontend_state, Some(json!("typed-interface")));
    }

    // Requirement: results compiled under another key describe something else,
    // so they are not offered as a baseline for this run.
    #[test]
    fn a_key_mismatch_yields_no_baseline() {
        let temp = tempfile::tempdir().unwrap();
        let cache = CompileCache::open(temp.path(), "morphir-elm-native", "example/domain");
        cache
            .write_results(
                &key(),
                context_digest(),
                &[module("My.Other", ModuleStatus::Compiled)],
            )
            .unwrap();

        for changed in [
            CacheKey {
                extension_version: "0.2.0".into(),
                ..key()
            },
            CacheKey {
                ir_version: "3.0.0".into(),
                ..key()
            },
            CacheKey {
                types_only: true,
                ..key()
            },
        ] {
            assert!(
                cache.read_baseline(&changed).is_none(),
                "a changed key must not reuse the cache: {changed:?}"
            );
        }
    }

    // Requirement: a damaged cache is no baseline, never an error.
    #[test]
    fn a_corrupt_manifest_yields_no_baseline() {
        let temp = tempfile::tempdir().unwrap();
        let cache = CompileCache::open(temp.path(), "morphir-elm-native", "example/domain");
        cache
            .write_results(
                &key(),
                context_digest(),
                &[module("My.Other", ModuleStatus::Compiled)],
            )
            .unwrap();
        std::fs::write(cache.root().join("manifest.json"), b"{ not json").unwrap();

        assert!(cache.read_baseline(&key()).is_none());
    }

    // An empty cache directory is the ordinary first run, not a failure.
    #[test]
    fn a_missing_manifest_yields_no_baseline() {
        let temp = tempfile::tempdir().unwrap();
        let cache = CompileCache::open(temp.path(), "morphir-elm-native", "example/domain");

        assert!(cache.read_baseline(&key()).is_none());
    }

    // Requirement: a manifest entry whose module file is gone is skipped. The
    // rest of the baseline still stands, because each module's IR is its own.
    #[test]
    fn a_module_without_a_file_is_left_out_of_the_baseline() {
        let temp = tempfile::tempdir().unwrap();
        let cache = CompileCache::open(temp.path(), "morphir-elm-native", "example/domain");
        cache
            .write_results(
                &key(),
                context_digest(),
                &[
                    module("My.Other", ModuleStatus::Compiled),
                    module("My.Types", ModuleStatus::Compiled),
                ],
            )
            .unwrap();
        std::fs::remove_file(cache.module_path("My.Types")).unwrap();

        let baseline = cache
            .read_baseline(&key())
            .expect("a baseline is available");

        let names: Vec<_> = baseline
            .modules
            .iter()
            .map(|module| module.name.clone())
            .collect();
        assert_eq!(names, vec!["My.Other".to_owned()]);
    }

    // Requirement: a failed module keeps its last good file, because that is
    // the interface its dependents resolve against until it compiles again. A
    // module that is gone from the sources loses its file, because offering a
    // baseline for a module that no longer exists would resurrect it.
    #[test]
    fn dropped_modules_lose_their_files_while_failed_ones_keep_them() {
        let temp = tempfile::tempdir().unwrap();
        let cache = CompileCache::open(temp.path(), "morphir-elm-native", "example/domain");
        cache
            .write_results(
                &key(),
                context_digest(),
                &[
                    module("My.Other", ModuleStatus::Compiled),
                    module("My.Types", ModuleStatus::Compiled),
                    module("My.Gone", ModuleStatus::Compiled),
                ],
            )
            .unwrap();

        cache
            .write_results(
                &key(),
                context_digest(),
                &[
                    ModuleResult {
                        ir: None,
                        ..module("My.Other", ModuleStatus::Failed)
                    },
                    module("My.Types", ModuleStatus::Unchanged),
                ],
            )
            .unwrap();

        assert!(
            cache.module_path("My.Other").exists(),
            "a failed module keeps its last good file"
        );
        assert!(
            cache.module_path("My.Types").exists(),
            "an unchanged module keeps its file"
        );
        assert!(
            !cache.module_path("My.Gone").exists(),
            "a module absent from the results loses its file"
        );
        let baseline = cache
            .read_baseline(&key())
            .expect("a baseline is available");
        let failed = baseline
            .modules
            .iter()
            .find(|module| module.name == "My.Other")
            .expect("the failed module is still offered from its last good file");
        assert_eq!(failed.ir, json!({ "module": "My.Other" }));
    }

    // Requirement: writes are atomic and tidy. Nothing but the manifest and the
    // module files is left in the cache directory.
    #[test]
    fn writing_leaves_no_temp_file_behind() {
        let temp = tempfile::tempdir().unwrap();
        let cache = CompileCache::open(temp.path(), "morphir-elm-native", "example/domain");

        cache
            .write_results(
                &key(),
                context_digest(),
                &[module("My.Other", ModuleStatus::Compiled)],
            )
            .unwrap();
        cache
            .write_results(
                &key(),
                context_digest(),
                &[module("My.Other", ModuleStatus::Compiled)],
            )
            .unwrap();

        let root_files: Vec<_> = std::fs::read_dir(cache.root())
            .unwrap()
            .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        assert_eq!(
            root_files.iter().filter(|name| *name != "modules").count(),
            1,
            "only the manifest sits beside the modules directory: {root_files:?}"
        );
        let module_files: Vec<_> = std::fs::read_dir(cache.root().join("modules"))
            .unwrap()
            .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        assert_eq!(
            module_files,
            vec![
                cache
                    .module_path("My.Other")
                    .file_name()
                    .unwrap()
                    .to_string_lossy()
                    .into_owned()
            ]
        );
    }

    // A package or module name is not a path: it can carry separators a
    // filesystem would read as directories. Flattening those is lossy, so the
    // segment keeps a digest of the name it stands for and two names cannot
    // land on one directory.
    #[test]
    fn a_name_is_reduced_to_one_safe_path_segment() {
        assert!(
            sanitise("example/domain").starts_with("example_domain-"),
            "{}",
            sanitise("example/domain")
        );
        assert!(sanitise("../escape").starts_with(".._escape-"));
        assert!(sanitise("My.Types-1_0").starts_with("My.Types-1_0-"));
        assert_ne!(
            sanitise("A/B"),
            sanitise("A_B"),
            "two names that flatten alike must still be told apart"
        );
        assert_eq!(
            sanitise("A/B"),
            sanitise("A/B"),
            "and the segment is stable"
        );
        assert_eq!(
            sanitise("A/B").len(),
            "A_B".len() + 1 + 8,
            "the digest is eight hex characters after a dash"
        );
    }

    // Requirement: a run whose sources no longer hold any module empties the
    // cache. Keeping the previous entries would offer the next run a baseline
    // for modules that are gone, and the provider would reuse IR for source
    // that no longer exists.
    #[test]
    fn writing_empty_results_clears_the_cache() {
        let temp = tempfile::tempdir().unwrap();
        let cache = CompileCache::open(temp.path(), "morphir-elm-native", "example/domain");
        cache
            .write_results(
                &key(),
                context_digest(),
                &[
                    module("My.Other", ModuleStatus::Compiled),
                    module("My.Types", ModuleStatus::Compiled),
                ],
            )
            .unwrap();

        cache.write_results(&key(), context_digest(), &[]).unwrap();

        assert!(!cache.module_path("My.Other").exists());
        assert!(!cache.module_path("My.Types").exists());
        let baseline = cache
            .read_baseline(&key())
            .expect("an empty cache is still a readable one");
        assert!(
            baseline.modules.is_empty(),
            "nothing is offered from an emptied cache: {baseline:?}"
        );
    }

    // Requirement: the manifest is a readable record of the run, keyed and
    // timestamped, so a person can see why a baseline was or was not reused.
    #[test]
    fn the_manifest_records_the_key_and_every_module() {
        let temp = tempfile::tempdir().unwrap();
        let cache = CompileCache::open(temp.path(), "morphir-elm-native", "example/domain");

        cache
            .write_results(
                &key(),
                context_digest(),
                &[
                    module("My.Other", ModuleStatus::Compiled),
                    ModuleResult {
                        ir: None,
                        ..module("My.Types", ModuleStatus::Failed)
                    },
                ],
            )
            .unwrap();

        let manifest: serde_json::Value =
            serde_json::from_slice(&std::fs::read(cache.root().join("manifest.json")).unwrap())
                .unwrap();
        assert_eq!(manifest["schemaVersion"], "2");
        assert_eq!(manifest["key"]["extensionId"], "morphir-elm-native");
        assert_eq!(manifest["key"]["irVersion"], "4.0.0");
        assert_eq!(manifest["key"]["typesOnly"], false);
        assert!(manifest["key"].get("preludeDigest").is_none());
        assert_eq!(manifest["contextDigest"], "sha256:context");
        assert_eq!(manifest["modules"]["My.Other"]["status"], "compiled");
        assert_eq!(manifest["modules"]["My.Types"]["status"], "failed");
        assert_eq!(
            manifest["modules"]["My.Types"]["dependsOn"][0], "My.Other",
            "{manifest}"
        );
        assert!(
            manifest["updatedAt"]
                .as_str()
                .is_some_and(|value| !value.is_empty()),
            "{manifest}"
        );
    }

    // Requirement: the manifest's `contextDigest` is what the next baseline
    // carries. It is the extension, not the CLI, that decides whether a
    // baseline's context digest still matches, so the CLI's only job is to
    // store what the last result reported and hand it back unchanged.
    #[test]
    fn a_manifest_context_digest_round_trips_into_the_baseline() {
        let temp = tempfile::tempdir().unwrap();
        let cache = CompileCache::open(temp.path(), "morphir-elm-native", "example/domain");
        cache
            .write_results(
                &key(),
                Some("sha256:round-trip".into()),
                &[module("My.Other", ModuleStatus::Compiled)],
            )
            .unwrap();

        let baseline = cache
            .read_baseline(&key())
            .expect("a baseline is available");

        assert_eq!(
            baseline.context_digest.as_deref(),
            Some("sha256:round-trip")
        );
    }

    // Requirement: a provider that supplies no context digest leaves the
    // baseline with none either, rather than the CLI inventing one.
    #[test]
    fn a_missing_context_digest_carries_through_as_none() {
        let temp = tempfile::tempdir().unwrap();
        let cache = CompileCache::open(temp.path(), "morphir-elm-native", "example/domain");
        cache
            .write_results(&key(), None, &[module("My.Other", ModuleStatus::Compiled)])
            .unwrap();

        let baseline = cache
            .read_baseline(&key())
            .expect("a baseline is available");

        assert_eq!(baseline.context_digest, None);
    }
}
