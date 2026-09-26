//! Loads the kit's top-level `.feature` files in name order. Cross-file checks
//! (duplicate IDs and missing text fixtures) live here.

use std::collections::{BTreeMap, HashMap};
use std::io;

use morphir_gherkin::NodePath;

use super::gherkin::lower::{FenceRef, lower};
use super::hash::{ContentDigest, content_hash};
use super::source::{KIT_PATH, KitSource};
#[cfg(test)]
use super::syntax::case::parse_kit_file;
use super::syntax::case::{KitCase, KitError, KitFence, ParsedFile};
use super::syntax::info_string::Language;
use super::syntax::text::utf16_cmp;

/// A loaded kit: its cases, the problems found while loading, its case files and their source.
#[derive(Debug, Clone)]
pub struct Kit {
    /// Every case of every case file, in load order.
    pub cases: Vec<KitCase>,
    /// Fixed linked-metadata reference cases admitted for authoring checks.
    /// These are not executable IR adapter cases.
    pub metadata_reference_cases: usize,
    /// Every problem found while loading, per file and across files.
    pub errors: Vec<KitError>,
    /// The case files, as repository-relative paths in load order.
    pub files: Vec<String>,
    /// Where the kit's files were read from.
    pub source: KitSource,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Profile {
    Json,
    Yaml,
}

impl Profile {
    pub fn of_path(path: &str) -> Option<Self> {
        if path.ends_with(".json") {
            Some(Self::Json)
        } else if path.ends_with(".yaml") || path.ends_with(".yml") {
            Some(Self::Yaml)
        } else {
            None
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResolvedText {
    pub path: String,
    pub profile: Profile,
    pub content: String,
}

#[cfg(test)]
fn is_case_file(path: &str) -> bool {
    path.strip_prefix(KIT_PATH)
        .and_then(|rest| rest.strip_prefix('/'))
        .is_some_and(|name| !name.contains('/') && name.ends_with(".md") && name != "README.md")
}

/// Whether `path` is a top-level `.feature` case file of the kit directory.
fn is_feature_file(path: &str) -> bool {
    path.strip_prefix(KIT_PATH)
        .and_then(|rest| rest.strip_prefix('/'))
        .is_some_and(|name| !name.contains('/') && name.ends_with(".feature"))
}

fn decode(bytes: &[u8]) -> Result<&str, &'static str> {
    match std::str::from_utf8(bytes) {
        Ok(text) if text.starts_with('\u{FEFF}') => Err("starts with a byte-order mark"),
        Ok(text) => Ok(text),
        Err(_) => Err("is not valid UTF-8"),
    }
}

/// Loads every top-level file under the kit source that `is_target` accepts, in name order: reads
/// and decodes each, turns its text into cases with `parse(file, display, text)`, and folds the
/// errors, including an id owned by two files becoming an error against the second. `file` is the
/// file's repository-relative path (as `Kit.files` carries it); `display` is what the source
/// wants named in messages (the same path for a map source, the real filesystem path for a
/// directory source). The production caller selects `.feature` files and
/// lowers them into cases. Unit tests also exercise the historical parser.
fn load_generic(
    source: KitSource,
    what: &str,
    is_target: impl Fn(&str) -> bool,
    empty_is_error: bool,
    mut parse: impl FnMut(&str, &str, &str) -> ParsedFile,
) -> io::Result<Kit> {
    let mut files: Vec<String> = source
        .list()?
        .into_iter()
        .filter(|p| is_target(p))
        .collect();
    files.sort_by(|a, b| utf16_cmp(a, b));
    if files.is_empty() && empty_is_error {
        let label = source.label();
        let errors = vec![KitError {
            message: format!("no MCK case files ({what}) in {label}"),
            file: label,
            line: 0,
        }];
        return Ok(Kit {
            cases: Vec::new(),
            metadata_reference_cases: 0,
            errors,
            files,
            source,
        });
    }

    let mut cases = Vec::new();
    let mut errors = Vec::new();
    let mut owner: HashMap<String, String> = HashMap::new();
    for file in &files {
        let display = source.display(file);
        // A listed file that cannot be read is an error, never an empty file:
        // its cases would silently vanish from the kit.
        let bytes = match source.read(file) {
            Ok(Some(bytes)) => bytes,
            Ok(None) => {
                errors.push(KitError {
                    file: display,
                    line: 0,
                    message: "case file cannot be read: it is not a regular file inside the kit"
                        .to_owned(),
                });
                continue;
            }
            Err(error) => {
                errors.push(KitError {
                    file: display,
                    line: 0,
                    message: format!("case file cannot be read: {error}"),
                });
                continue;
            }
        };
        // A case file may open with a byte-order mark, which the tokenizer
        // strips; only undecodable bytes are refused.
        let Ok(text) = std::str::from_utf8(&bytes) else {
            errors.push(KitError {
                file: display,
                line: 0,
                message: "case file is not valid UTF-8".to_owned(),
            });
            continue;
        };
        let parsed = parse(file, &display, text);
        errors.extend(parsed.errors);
        for case in parsed.cases {
            let first = owner
                .entry(case.id.as_str().to_owned())
                .or_insert_with(|| case.file.clone());
            if *first != case.file {
                errors.push(KitError {
                    file: case.file.clone(),
                    line: case.line,
                    message: format!(
                        "duplicate case id \"{}\" across files (first in {first})",
                        case.id
                    ),
                });
            }
            cases.push(case);
        }
    }

    let metadata_reference_cases = match crate::metadata::admit(&source) {
        Ok(Some(count)) => count,
        Ok(None) => 0,
        Err(message) => {
            errors.push(KitError {
                file: source.display("spec/ir/mck/metadata-contract-draft.json"),
                line: 0,
                message,
            });
            0
        }
    };

    let mut kit = Kit {
        cases,
        metadata_reference_cases,
        errors,
        files,
        source,
    };
    let fixtures = kit.fixture_errors();
    kit.errors.extend(fixtures);
    Ok(kit)
}

#[cfg(test)]
pub fn load_markdown_kit(source: KitSource) -> io::Result<Kit> {
    load_generic(
        source,
        "*.md",
        is_case_file,
        true,
        |_file, display, text| parse_kit_file(display, text),
    )
}

/// A `morphir_gherkin::ReadError` as a `KitError`, at the file and line it names: a syntax error
/// keeps its position, everything else (an I/O error that cannot happen for text already in
/// memory, or a path this loader never hands it) is reported at line 0.
fn feature_read_error(display: &str, error: morphir_gherkin::ReadError) -> KitError {
    match error {
        morphir_gherkin::ReadError::Syntax {
            position, message, ..
        } => KitError {
            file: display.to_owned(),
            line: position.line,
            message,
        },
        other => KitError {
            file: display.to_owned(),
            line: 0,
            message: other.to_string(),
        },
    }
}

/// A kit of top-level `.feature` case files, in name order, with duplicate-ID
/// and external-fixture checks. A kit with no feature files is an error.
pub struct FeatureKit {
    /// The `.feature` cases, errors and files.
    pub kit: Kit,
    /// Each case file's step-to-fence map, as [`lower`] gives it. Keyed by the file's
    /// repository-relative path (`spec/ir/mck/<topic>.feature`, matching `Kit.files` and
    /// [`KIT_PATH`]), whichever `KitSource` variant loaded the kit — unlike `KitCase.file`, this
    /// key is never the real filesystem path of a directory-sourced kit, so a caller with only a
    /// case's repository-relative file name (Task B5's lookup) can still find its fences.
    pub fences: HashMap<String, FileFences>,
}

/// One case file's step-to-fence map, as [`lower`] gives it in `LoweredFile::fences`.
pub type FileFences = HashMap<(NodePath, Option<usize>, usize), FenceRef>;

/// Loads the kit's `.feature` case files: see [`FeatureKit`].
pub fn load_feature_kit(source: KitSource) -> io::Result<FeatureKit> {
    let mut fences = HashMap::new();
    let kit = load_generic(
        source,
        "*.feature",
        is_feature_file,
        true,
        |file, display, text| {
            let doc = match morphir_gherkin::read_str(display, text) {
                Ok((doc, _)) => doc,
                Err(error) => {
                    return ParsedFile {
                        cases: Vec::new(),
                        errors: vec![feature_read_error(display, error)],
                    };
                }
            };
            let lowered = lower(display, &doc);
            fences.insert(file.to_owned(), lowered.fences);
            lowered.parsed
        },
    )?;
    Ok(FeatureKit { kit, fences })
}

/// Load the executable compatibility kit from its Gherkin case files.
pub fn load_kit(source: KitSource) -> io::Result<Kit> {
    load_feature_kit(source).map(|feature| feature.kit)
}

impl Kit {
    /// The fixture a `text` fence names, confined to the kit source.
    pub fn resolve_text(&self, fence: &KitFence) -> Result<ResolvedText, String> {
        let target = fence.text_target();
        let Some(profile) = Profile::of_path(target) else {
            return Err(format!(
                "text fence names {target}, which is neither .json nor .yaml"
            ));
        };
        let bytes = match self.source.read(target) {
            Ok(bytes) => bytes,
            Err(error) => {
                return Err(format!(
                    "text fence names {target}, which cannot be read: {error}"
                ));
            }
        };
        let Some(bytes) = bytes else {
            return Err(format!(
                "text fence names {target}, which is not in the kit source ({})",
                self.source.label()
            ));
        };
        match decode(&bytes) {
            Ok(content) => Ok(ResolvedText {
                path: target.to_owned(),
                profile,
                content: content.to_owned(),
            }),
            Err(problem) => Err(format!("text fence names {target}, which {problem}")),
        }
    }

    fn text_fences(&self) -> impl Iterator<Item = (&KitCase, &KitFence)> {
        self.cases
            .iter()
            .flat_map(|case| case.fences.iter().map(move |fence| (case, fence)))
            .filter(|(_, fence)| fence.info.language == Language::Text)
    }

    fn fixture_errors(&self) -> Vec<KitError> {
        self.text_fences()
            .filter_map(|(case, fence)| {
                let message = self.resolve_text(fence).err()?;
                Some(KitError {
                    file: case.file.clone(),
                    line: fence.line,
                    message,
                })
            })
            .collect()
    }

    /// The legacy corpus set: every file under the kit directory plus every
    /// fixture a `text` fence names. `None` when the kit has errors, because a
    /// broken kit has no identity worth recording.
    pub fn corpus_files(&self) -> io::Result<Option<BTreeMap<String, Vec<u8>>>> {
        if !self.errors.is_empty() {
            return Ok(None);
        }
        let mut files = BTreeMap::new();
        let targets = self
            .text_fences()
            .map(|(_, fence)| fence.text_target().to_owned());
        for path in self.source.list()?.into_iter().chain(targets) {
            let Some(bytes) = self.source.read(&path)? else {
                return Err(io::Error::new(
                    io::ErrorKind::NotFound,
                    format!("{path} disappeared while hashing the kit"),
                ));
            };
            files.insert(path, bytes.into_owned());
        }
        Ok(Some(files))
    }

    /// `corpusHash`: the identity of the current feature kit and its fixtures.
    pub fn corpus_hash(&self) -> io::Result<Option<ContentDigest>> {
        Ok(self
            .corpus_files()?
            .map(|files| content_hash(files.iter().map(|(p, b)| (p.as_str(), b.as_slice())))))
    }
}

#[cfg(test)]
mod tests {
    use std::borrow::Cow;

    use super::*;

    fn kit(files: &[(&str, &str)]) -> Kit {
        let files = files
            .iter()
            .map(|(p, t)| ((*p).to_owned(), Cow::Owned(t.as_bytes().to_vec())))
            .collect();
        load_markdown_kit(KitSource::map("test kit", files)).unwrap()
    }

    /// A kit whose files are raw bytes, for content no `&str` can hold.
    fn kit_of_bytes(files: &[(&str, &[u8])]) -> Kit {
        let files = files
            .iter()
            .map(|(p, b)| ((*p).to_owned(), Cow::Owned(b.to_vec())))
            .collect();
        load_markdown_kit(KitSource::map("test kit", files)).unwrap()
    }

    const CASE: &str = "```yaml canonical\na: 1\n```\n";

    #[test]
    fn loads_top_level_case_files_in_name_order_and_skips_the_readme() {
        let kit = kit(&[
            (
                "spec/ir/mck/values.md",
                &format!("## values-0001: v\n{CASE}"),
            ),
            ("spec/ir/mck/README.md", "## not-a-case\n"),
            ("spec/ir/mck/documents/nested.md", "## nested-0001: n\n"),
            ("spec/ir/mck/types.md", &format!("## types-0001: t\n{CASE}")),
        ]);
        assert_eq!(kit.errors, vec![]);
        assert_eq!(
            kit.files,
            vec!["spec/ir/mck/types.md", "spec/ir/mck/values.md"]
        );
        let ids: Vec<_> = kit.cases.iter().map(|c| c.id.as_str()).collect();
        assert_eq!(ids, vec!["types-0001", "values-0001"]);
    }

    /// A listed case file the source cannot hand over must fail the check: an
    /// empty stand-in would parse cleanly and its cases would silently vanish.
    #[cfg(unix)]
    #[test]
    fn a_listed_case_file_that_cannot_be_read_is_a_kit_error() {
        use std::os::unix::fs::PermissionsExt;

        let repo = tempfile::tempdir().unwrap();
        let kit_dir = repo.path().join(KIT_PATH);
        std::fs::create_dir_all(&kit_dir).unwrap();
        std::fs::write(
            kit_dir.join("types.md"),
            format!("## types-0001: t\n{CASE}"),
        )
        .unwrap();
        let locked = kit_dir.join("values.md");
        std::fs::write(&locked, format!("## values-0001: v\n{CASE}")).unwrap();
        std::fs::set_permissions(&locked, std::fs::Permissions::from_mode(0o000)).unwrap();
        if std::fs::read(&locked).is_ok() {
            return; // running as root: permissions do not bind
        }

        let kit = load_markdown_kit(KitSource::directory(&kit_dir, None)).unwrap();
        std::fs::set_permissions(&locked, std::fs::Permissions::from_mode(0o644)).unwrap();
        assert_eq!(kit.cases.len(), 1);
        assert_eq!(kit.errors.len(), 1, "{:?}", kit.errors);
        assert!(
            kit.errors[0]
                .message
                .starts_with("case file cannot be read: "),
            "{:?}",
            kit.errors
        );
    }

    #[test]
    fn a_kit_without_case_files_is_an_error() {
        let kit = kit(&[("spec/ir/mck/README.md", "")]);
        assert_eq!(kit.errors.len(), 1);
        assert_eq!(
            kit.errors[0].message,
            "no MCK case files (*.md) in test kit"
        );
        assert_eq!(
            (kit.errors[0].file.as_str(), kit.errors[0].line),
            ("test kit", 0)
        );
    }

    #[test]
    fn an_id_in_two_files_is_reported_against_the_second() {
        // The per-file topic rule fires too; the cross-file rule is the one under test.
        let kit = kit(&[
            ("spec/ir/mck/a.md", &format!("## a-0001: first\n{CASE}")),
            ("spec/ir/mck/b.md", &format!("## a-0001: second\n{CASE}")),
        ]);
        let messages: Vec<_> = kit.errors.iter().map(|e| e.message.as_str()).collect();
        assert!(
            messages
                .contains(&"duplicate case id \"a-0001\" across files (first in spec/ir/mck/a.md)"),
            "{messages:?}"
        );
    }

    /// Departure 12: the old driver replaced undecodable bytes with U+FFFD and
    /// carried on, so a corrupt file could be read as a case that passes. Both
    /// a case file and a fixture are refused instead.
    #[test]
    fn undecodable_bytes_are_a_kit_error_in_a_case_file_and_in_a_fixture() {
        const INVALID: &[u8] = b"## types-0001: t\n```yaml canonical\na: \xff\n```\n";
        let kit = kit_of_bytes(&[("spec/ir/mck/types.md", INVALID)]);
        assert_eq!(
            kit.errors
                .iter()
                .map(|e| (e.file.as_str(), e.line, e.message.as_str()))
                .collect::<Vec<_>>(),
            vec![("spec/ir/mck/types.md", 0, "case file is not valid UTF-8")],
            "an undecodable case file is refused, not read lossily"
        );
        assert_eq!(kit.cases, vec![], "no case survives an undecodable file");

        let kit = kit_of_bytes(&[
            (
                "spec/ir/mck/types.md",
                b"## types-0001: t\n```text canonical\n\n  website/x.json  \n```\n",
            ),
            ("website/x.json", b"{\"a\": \"\xff\"}"),
        ]);
        assert_eq!(
            kit.errors
                .iter()
                .map(|e| (e.line, e.message.as_str()))
                .collect::<Vec<_>>(),
            vec![(
                2,
                "text fence names website/x.json, which is not valid UTF-8"
            )],
            "reported at the fence's line, like every other fixture fault"
        );
    }

    #[test]
    fn text_fences_resolve_inside_the_source_and_fail_the_check_otherwise() {
        let case =
            |target: &str| format!("## types-0001: t\n```text canonical\n\n  {target}  \n```\n");
        let good = kit(&[
            ("spec/ir/mck/types.md", &case("website/x.json")),
            ("website/x.json", "{}"),
        ]);
        assert_eq!(good.errors, vec![]);
        let resolved = good.resolve_text(&good.cases[0].fences[0]).unwrap();
        assert_eq!(
            (
                resolved.path.as_str(),
                resolved.profile,
                resolved.content.as_str()
            ),
            ("website/x.json", Profile::Json, "{}")
        );

        let message = |k: Kit| {
            k.errors
                .into_iter()
                .map(|e| (e.line, e.message))
                .collect::<Vec<_>>()
        };
        assert_eq!(
            message(kit(&[(
                "spec/ir/mck/types.md",
                &case("website/missing.yaml")
            )])),
            vec![(
                2,
                "text fence names website/missing.yaml, which is not in the kit source (test kit)"
                    .to_owned()
            )]
        );
        assert_eq!(
            message(kit(&[("spec/ir/mck/types.md", &case("website/x.toml"))])),
            vec![(
                2,
                "text fence names website/x.toml, which is neither .json nor .yaml".to_owned()
            )]
        );
        assert_eq!(
            message(kit(&[
                ("spec/ir/mck/types.md", &case("website/x.json")),
                ("website/x.json", "\u{FEFF}{}")
            ])),
            vec![(
                2,
                "text fence names website/x.json, which starts with a byte-order mark".to_owned()
            )]
        );
    }

    #[test]
    fn corpus_hash_covers_kit_files_and_fixtures_and_refuses_a_broken_kit() {
        let case = "## types-0001: t\n```text canonical\nwebsite/x.json\n```\n";
        let good = kit(&[
            ("spec/ir/mck/types.md", case),
            ("spec/ir/mck/README.md", "r"),
            ("website/x.json", "{}"),
            ("website/unused.json", "{}"),
        ]);
        let files = good.corpus_files().unwrap().unwrap();
        assert_eq!(
            files.keys().collect::<Vec<_>>(),
            vec![
                "spec/ir/mck/README.md",
                "spec/ir/mck/types.md",
                "website/x.json"
            ]
        );
        assert!(good.corpus_hash().unwrap().is_some());

        let broken = kit(&[("spec/ir/mck/types.md", "## types-1: bad\n")]);
        assert_eq!(broken.corpus_hash().unwrap(), None);
    }

    /// The repository's Gherkin kit has every case in a `.feature` file.
    #[test]
    fn the_checkout_kit_matches_the_baseline_inventory() {
        let kit_dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/ir/mck");
        let kit = load_kit(KitSource::directory(&kit_dir, None)).unwrap();
        assert_eq!(kit.errors, vec![]);
        assert!(
            kit.files.len() >= 8,
            "the corpus only grows: {}",
            kit.files.len()
        );
        assert!(
            kit.cases.len() >= 120,
            "the corpus only grows: {}",
            kit.cases.len()
        );

        assert!(kit.files.iter().all(|path| path.ends_with(".feature")));
    }

    /// Ruling R-B5: `FeatureKit.fences` is keyed by the repository-relative path, not the real
    /// filesystem path a `KitSource::directory` kit's cases carry as `file` (`--kit DIR` is
    /// always a directory source), so a caller holding only a case's repository-relative file
    /// name can still find its fences.
    #[test]
    fn feature_kit_fences_are_keyed_by_the_repository_relative_path_for_a_directory_source() {
        let kit_dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/ir/mck");
        let feature = load_feature_kit(KitSource::directory(&kit_dir, None)).unwrap();
        assert_eq!(feature.kit.errors, vec![]);
        let mut keys: Vec<&str> = feature.fences.keys().map(String::as_str).collect();
        keys.sort_unstable();
        assert_eq!(keys.len(), 8, "{keys:?}");
        for key in &keys {
            assert!(
                key.starts_with("spec/ir/mck/") && key.ends_with(".feature"),
                "{key}"
            );
        }
    }

    /// `load_kit` and `load_feature_kit` give the same sequence of case ids over the checkout's
    /// own kit, not only over a small hand-built fixture.
    #[test]
    fn load_kit_and_load_feature_kit_give_the_same_case_id_sequence_over_the_checkout_kit() {
        let kit_dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/ir/mck");
        let md = load_kit(KitSource::directory(&kit_dir, None)).unwrap();
        let feature = load_feature_kit(KitSource::directory(&kit_dir, None)).unwrap();
        assert_eq!(md.errors, vec![]);
        assert_eq!(feature.kit.errors, vec![]);
        let md_ids: Vec<&str> = md.cases.iter().map(|c| c.id.as_str()).collect();
        let feature_ids: Vec<&str> = feature.kit.cases.iter().map(|c| c.id.as_str()).collect();
        assert_eq!(md_ids, feature_ids);
    }
}
