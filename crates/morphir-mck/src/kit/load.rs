//! Loads a kit: every top-level `*.md` of the kit directory except README.md,
//! in name order. Cross-file checks (an id in two files, a `text` fence whose
//! fixture cannot be used) live here; per-file checks live in the case parser.
//!
//! [`load_feature_kit`] loads the same directory's `.feature` twins with the
//! same cross-file checks, sharing [`load_generic`] with [`load_kit`].

use std::collections::{BTreeMap, HashMap};
use std::io;

use morphir_gherkin::NodePath;

use super::gherkin::lower::{FenceRef, lower};
use super::hash::{ContentDigest, content_hash};
use super::source::{KIT_PATH, KitSource};
use super::syntax::case::{KitCase, KitError, KitFence, ParsedFile, parse_kit_file};
use super::syntax::info_string::Language;
use super::syntax::text::utf16_cmp;

#[derive(Debug, Clone)]
pub struct Kit {
    pub cases: Vec<KitCase>,
    /// Fixed linked-metadata reference cases admitted for authoring checks.
    /// These are not executable IR adapter cases.
    pub metadata_reference_cases: usize,
    pub errors: Vec<KitError>,
    /// The case files, as repository-relative paths in load order.
    pub files: Vec<String>,
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
/// and decodes each, turns its text into cases with `parse`, and folds the errors, including an
/// id owned by two files becoming an error against the second. Shared by [`load_kit`] (`*.md`,
/// [`parse_kit_file`]) and [`load_feature_kit`] (`*.feature`, [`lower`]), which differ only in
/// which files they select and how they turn one file's text into cases.
fn load_generic(
    source: KitSource,
    what: &str,
    is_target: impl Fn(&str) -> bool,
    empty_is_error: bool,
    mut parse: impl FnMut(&str, &str) -> ParsedFile,
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
        let parsed = parse(&display, text);
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

pub fn load_kit(source: KitSource) -> io::Result<Kit> {
    load_generic(source, "*.md", is_case_file, true, |display, text| {
        parse_kit_file(display, text)
    })
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

/// A kit of `.feature` case files: every top-level `*.feature` of the kit directory, in name
/// order, with the same cross-file checks [`load_kit`] runs (an id in two files, a `text`
/// fixture that cannot be used), and cases in the same order `load_kit` gives for their Markdown
/// twins. Unlike `load_kit`, a source with no `.feature` files is not an error: during the parity
/// window a kit directory may not carry the generated twins yet.
pub struct FeatureKit {
    pub kit: Kit,
    /// Each case file's step-to-fence map, as [`lower`] gives it. Keyed by the same path
    /// [`KitCase::file`] carries for that file's cases: `spec/ir/mck/<topic>.feature` for the
    /// embedded or a map-sourced kit, or the real file's path for a directory source.
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
        false,
        |display, text| {
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
            fences.insert(display.to_owned(), lowered.fences);
            lowered.parsed
        },
    )?;
    Ok(FeatureKit { kit, fences })
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

    /// `corpusHash`: the identity the TypeScript driver's `kit.lock.json` recorded.
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
        load_kit(KitSource::map("test kit", files)).unwrap()
    }

    /// A kit whose files are raw bytes, for content no `&str` can hold.
    fn kit_of_bytes(files: &[(&str, &[u8])]) -> Kit {
        let files = files
            .iter()
            .map(|(p, b)| ((*p).to_owned(), Cow::Owned(b.to_vec())))
            .collect();
        load_kit(KitSource::map("test kit", files)).unwrap()
    }

    fn source_of(files: &[(&str, &str)]) -> KitSource {
        let files = files
            .iter()
            .map(|(p, t)| ((*p).to_owned(), Cow::Owned(t.as_bytes().to_vec())))
            .collect();
        KitSource::map("test kit", files)
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

    /// The round trip again, through the loaders this time: a map source with a Markdown case
    /// file and its `.feature` twin gives equal cases from `load_kit` and `load_feature_kit`.
    /// README.md and a nested file are ignored by both, whichever extension they carry.
    #[test]
    fn load_kit_and_load_feature_kit_agree_on_a_markdown_file_and_its_feature_twin() {
        let markdown = "## values-0001: v\n\n```yaml canonical\na: 1\n```\n\n```json canonical\n{ \"a\": 1 }\n```\n";
        let md_only = kit(&[("spec/ir/mck/values.md", markdown)]);
        assert_eq!(md_only.errors, vec![]);
        let title = super::super::gherkin::convert::feature_title("values", markdown);
        let description = super::super::gherkin::convert::feature_description(markdown);
        let feature_text =
            super::super::gherkin::convert::convert(&title, &description, &md_only.cases);

        let source = source_of(&[
            ("spec/ir/mck/values.md", markdown),
            ("spec/ir/mck/values.feature", &feature_text),
            ("spec/ir/mck/README.md", "# not a case file\n"),
            ("spec/ir/mck/documents/nested.md", "## nested-0001: n\n"),
            (
                "spec/ir/mck/documents/nested.feature",
                "Feature: nested\n\n  Scenario: nested-0001 n\n    Then a reader of JSON accepts 1\n",
            ),
        ]);
        let md = load_kit(source.clone()).unwrap();
        let feature = load_feature_kit(source).unwrap();
        assert_eq!(md.errors, vec![]);
        assert_eq!(feature.kit.errors, vec![]);
        assert_eq!(md.files, vec!["spec/ir/mck/values.md"]);
        assert_eq!(feature.kit.files, vec!["spec/ir/mck/values.feature"]);

        assert_eq!(md.cases.len(), feature.kit.cases.len());
        for (md_case, feature_case) in md.cases.iter().zip(&feature.kit.cases) {
            assert_eq!(
                (
                    md_case.id.as_str(),
                    md_case.topic.as_str(),
                    md_case.number,
                    md_case.title.as_str(),
                    md_case.node.as_deref(),
                    md_case.version,
                    md_case.status,
                    md_case.compare,
                    &md_case.prose,
                ),
                (
                    feature_case.id.as_str(),
                    feature_case.topic.as_str(),
                    feature_case.number,
                    feature_case.title.as_str(),
                    feature_case.node.as_deref(),
                    feature_case.version,
                    feature_case.status,
                    feature_case.compare,
                    &feature_case.prose,
                ),
                "cases must agree except for `file` and `line`, which differ by format"
            );
            let md_fences: Vec<_> = md_case
                .fences
                .iter()
                .map(|f| (f.info.language, f.info.role, f.body.as_str()))
                .collect();
            let feature_fences: Vec<_> = feature_case
                .fences
                .iter()
                .map(|f| (f.info.language, f.info.role, f.body.as_str()))
                .collect();
            assert_eq!(md_fences, feature_fences);
        }
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

        let kit = load_kit(KitSource::directory(&kit_dir, None)).unwrap();
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

    /// The repository's own kit, against the frozen baseline: 120 cases in 8
    /// files with no errors, and the 15-file legacy corpus set.
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

        #[derive(serde::Deserialize)]
        struct Inventory {
            paths: Vec<String>,
        }
        let raw = include_str!("../../../../spec/mck/baseline/corpus-inventory.json");
        let inventory: Inventory =
            serde_json::from_str(raw.trim_start_matches('\u{FEFF}')).unwrap();
        let files = kit.corpus_files().unwrap().unwrap();
        for path in &inventory.paths {
            assert!(
                files.contains_key(path),
                "baseline path {path} left the corpus"
            );
        }
    }
}
