//! Turns one MCK case file into cases. An H2 opens a case; its fences are the
//! data; everything else under it is prose. Every structural rule from the
//! kit's README is enforced here and reported as a `KitError` with a line, so
//! the check command can print `file:line: message`.

use std::collections::{BTreeMap, BTreeSet, HashSet};
use std::fmt;

use super::info_string::{FenceInfo, InfoError, Language, Role, parse_info_string, set_label};
use super::markdown::{Block, tokenize};
use super::text::{
    is_js_blank, js_parse_int, js_tokens, js_trim, js_trim_start, lazy_prefix, split_lines,
};

/// A case identifier, `<topic>-<NNNN>`. Only the parser constructs one.
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct CaseId(String);

impl CaseId {
    pub fn as_str(&self) -> &str {
        &self.0
    }

    /// The id `<topic>-<digits>`, for a case read from another format than
    /// Markdown (the `.feature` lowering). `digits` is the case's four digits.
    pub(crate) fn from_parts(topic: &str, digits: &str) -> Self {
        Self(format!("{topic}-{digits}"))
    }
}

impl fmt::Display for CaseId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Status {
    Active,
    Pending,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Compare {
    Stripped,
    Attributes,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KitFence {
    pub info: FenceInfo,
    pub body: String,
    pub line: usize,
    pub index: usize,
}

impl KitFence {
    /// The repository-relative path a `text` fence names: its first non-blank line.
    pub fn text_target(&self) -> &str {
        split_lines(&self.body)
            .into_iter()
            .find(|l| !is_js_blank(l))
            .map_or("", js_trim)
    }

    /// A `text` fence names a file rather than embedding data; for counting
    /// canonicals it belongs to the profile of the named file's extension.
    fn profile(&self) -> &'static str {
        if self.info.language != Language::Text {
            return self.info.language.as_str();
        }
        let path = self.text_target();
        if path.ends_with(".json") {
            "json"
        } else if path.ends_with(".yaml") || path.ends_with(".yml") {
            "yaml"
        } else {
            "text"
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KitCase {
    pub id: CaseId,
    pub topic: String,
    pub number: u16,
    pub title: String,
    pub node: Option<String>,
    pub version: Option<i64>,
    pub status: Status,
    pub compare: Compare,
    pub prose: Vec<String>,
    pub fences: Vec<KitFence>,
    pub file: String,
    pub line: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KitError {
    pub file: String,
    pub line: usize,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ParsedFile {
    pub cases: Vec<KitCase>,
    pub errors: Vec<KitError>,
}

const HEADING_KEYS: [&str; 4] = ["node", "version", "status", "compare"];

/// The file's topic: its base name without `.md`. Accepts either separator so
/// an operating-system path from a Windows checkout works.
pub fn topic_of(file: &str) -> &str {
    let base = file.rsplit(['/', '\\']).next().unwrap_or(file);
    base.strip_suffix(".md").unwrap_or(base)
}

struct CaseHeading<'a> {
    topic: &'a str,
    digits: &'a str,
    title: &'a str,
    keys: &'a str,
}

/// `^([a-z][a-z0-9-]*)-(\d{4}): (.+?)(?:\s*\{([^}]*)\})?\s*$`
fn case_heading(text: &str) -> Option<CaseHeading<'_>> {
    // The topic class excludes ':', so "-NNNN" can only be the last five
    // characters of the leading [a-z0-9-] run.
    let run = text
        .find(|c: char| !(c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-'))
        .unwrap_or(text.len());
    let rest = text[run..].strip_prefix(": ")?;
    let (topic, number) = text[..run].split_at_checked(run.checked_sub(5)?)?;
    let digits = number
        .strip_prefix('-')
        .filter(|d| d.bytes().all(|b| b.is_ascii_digit()))?;
    if !topic.starts_with(|c: char| c.is_ascii_lowercase()) {
        return None;
    }
    let (title, keys) = lazy_prefix(rest, |tail| {
        let braced = js_trim_start(tail).strip_prefix('{').and_then(|inner| {
            let (keys, after) = inner.split_once('}')?;
            is_js_blank(after).then_some(keys)
        });
        braced.or_else(|| is_js_blank(tail).then_some(""))
    })?;
    Some(CaseHeading {
        topic,
        digits,
        title,
        keys,
    })
}

struct Parser<'a> {
    file: &'a str,
    file_topic: &'a str,
    seen: HashSet<String>,
    draft: Option<KitCase>,
    out: ParsedFile,
}

impl Parser<'_> {
    fn fail(&mut self, line: usize, message: String) {
        self.out.errors.push(KitError {
            file: self.file.to_owned(),
            line,
            message,
        });
    }

    fn finish(&mut self) {
        let Some(current) = self.draft.take() else {
            return;
        };
        for (line, message) in case_errors(&current) {
            self.fail(line, message);
        }
        self.out.cases.push(current);
    }

    fn open_case(&mut self, text: &str, line: usize) {
        self.finish();
        let Some(heading) = case_heading(text) else {
            self.fail(
                line,
                format!(
                    "malformed case id in heading \"{text}\"; expected \"<topic>-<NNNN>: <title>\""
                ),
            );
            return;
        };
        let id = format!("{}-{}", heading.topic, heading.digits);
        if heading.topic != self.file_topic {
            self.fail(
                line,
                format!(
                    "topic \"{}\" does not match file topic \"{}\"",
                    heading.topic, self.file_topic
                ),
            );
        }
        if !self.seen.insert(id.clone()) {
            self.fail(line, format!("duplicate case id \"{id}\""));
        }

        let mut next = KitCase {
            id: CaseId(id),
            topic: heading.topic.to_owned(),
            number: heading.digits.parse().unwrap_or(0),
            title: heading.title.to_owned(),
            node: None,
            version: None,
            status: Status::Active,
            compare: Compare::Stripped,
            prose: Vec::new(),
            fences: Vec::new(),
            file: self.file.to_owned(),
            line,
        };
        for token in js_tokens(heading.keys) {
            let (key, value) = token
                .split_once('=')
                .filter(|(key, _)| !key.is_empty())
                .unwrap_or((token, ""));
            if !HEADING_KEYS.contains(&key) {
                self.fail(line, format!("unknown heading key \"{key}\""));
                continue;
            }
            match key {
                "node" => next.node = Some(value.to_owned()),
                "version" => match js_parse_int(value) {
                    Some(version) => next.version = Some(version),
                    None => self.fail(line, format!("version must be an integer, got \"{value}\"")),
                },
                "status" if value == "pending" => next.status = Status::Pending,
                "status" => self.fail(line, format!("status must be pending, got \"{value}\"")),
                "compare" if value == "attributes" => next.compare = Compare::Attributes,
                _ => self.fail(line, format!("compare must be attributes, got \"{value}\"")),
            }
        }
        self.draft = Some(next);
    }

    fn block(&mut self, block: Block) {
        match block {
            Block::FrontMatter { .. } => {}
            Block::Heading {
                level: 2,
                text,
                line,
            } => self.open_case(&text, line),
            Block::Heading { level, text, .. } => {
                if let Some(draft) = self.draft.as_mut().filter(|_| level > 2) {
                    draft.prose.push(text);
                }
            }
            Block::Prose { text, .. } => {
                if let Some(draft) = self.draft.as_mut() {
                    draft.prose.push(text);
                }
            }
            Block::Fence {
                info,
                body,
                line,
                closed,
            } => match parse_info_string(&info) {
                Err(InfoError::NotADataFence(_)) => {}
                Err(error) => self.fail(line, error.to_string()),
                Ok(_) if self.draft.is_none() => {
                    self.fail(line, "data fence before the first case".to_owned())
                }
                Ok(_) if !closed => self.fail(line, "unterminated fence".to_owned()),
                Ok(info) => {
                    if let Some(draft) = self.draft.as_mut() {
                        let index = draft.fences.len();
                        draft.fences.push(KitFence {
                            info,
                            body,
                            line,
                            index,
                        });
                    }
                }
            },
        }
    }
}

/// The per-case structural checks every case file format shares: at most one
/// canonical fence per profile, a set's own rules (one mode, no repeated
/// path), what a pending case may carry, and that an active case has data and
/// a canonical fence where it needs one. Each error is a line and a message;
/// the line is a fence's line or the case's line.
pub(crate) fn case_errors(case: &KitCase) -> Vec<(usize, String)> {
    let mut errors = Vec::new();

    let mut canonicals: BTreeMap<&str, usize> = BTreeMap::new();
    for fence in case
        .fences
        .iter()
        .filter(|f| f.info.role == Role::Canonical)
    {
        let count = canonicals.entry(fence.profile()).or_default();
        *count += 1;
        if *count == 2 {
            errors.push((
                fence.line,
                format!(
                    "more than one canonical {} fence in {}",
                    fence.profile(),
                    case.id
                ),
            ));
        }
    }

    // A set's own rules. `mode=read` is a property of the set, not of one
    // file in it: the runner either runs the write half for the whole set
    // or for none of it, so a set that says both is a kit error rather
    // than a silent choice. A repeated path is a kit error too, because
    // the tree a set denotes is a map from logical path to text.
    let mut modes: BTreeMap<&str, Option<&str>> = BTreeMap::new();
    let mut paths: BTreeMap<&str, BTreeSet<&str>> = BTreeMap::new();
    for fence in case.fences.iter().filter(|f| f.info.role == Role::File) {
        let set = fence.info.set();
        let mode = fence.info.key("mode");
        if *modes.entry(set).or_insert(mode) != mode {
            errors.push((
                fence.line,
                format!("set {} mixes mode=read and default fences", set_label(set)),
            ));
        }
        let logical = fence.info.key("path").unwrap_or("");
        if !paths.entry(set).or_default().insert(logical) {
            errors.push((
                fence.line,
                format!("set {} repeats path {logical}", set_label(set)),
            ));
        }
    }

    match case.status {
        Status::Pending => {
            if let Some(bad) = case.fences.iter().find(|f| f.info.role != Role::Rejected) {
                errors.push((
                    bad.line,
                    format!(
                        "pending case may not carry canonical, accepted, or file fences ({})",
                        case.id
                    ),
                ));
            }
        }
        Status::Active => {
            let accepted_or_file = case
                .fences
                .iter()
                .any(|f| matches!(f.info.role, Role::Accepted | Role::File));
            if canonicals.is_empty() && accepted_or_file {
                errors.push((
                    case.line,
                    format!("active case has no canonical fence ({})", case.id),
                ));
            } else if case.fences.is_empty() {
                errors.push((case.line, format!("case has no data fences ({})", case.id)));
            }
        }
    }

    errors
}

pub fn parse_kit_file(file: &str, source: &str) -> ParsedFile {
    let mut parser = Parser {
        file,
        file_topic: topic_of(file),
        seen: HashSet::new(),
        draft: None,
        out: ParsedFile::default(),
    };
    for block in tokenize(source) {
        parser.block(block);
    }
    parser.finish();
    parser.out
}

#[cfg(test)]
mod tests {
    use super::*;

    const FILE: &str = "spec/ir/mck/types.md";

    fn messages(file: &str, source: &str) -> Vec<String> {
        parse_kit_file(file, source)
            .errors
            .into_iter()
            .map(|e| e.message)
            .collect()
    }

    #[test]
    fn topic_of_strips_directory_and_extension() {
        assert_eq!(
            topic_of("spec/ir/mck/patterns-and-literals.md"),
            "patterns-and-literals"
        );
        assert_eq!(topic_of("C:\\repo\\spec\\ir\\mck\\types.md"), "types");
    }

    #[test]
    fn parses_cases_keys_prose_and_fences() {
        let good = [
            "# Types",
            "",
            "## types-0001: Unit type {node=Type version=4}",
            "Prose line.",
            "```yaml canonical",
            "Unit: {}",
            "```",
            "```json accepted",
            "{ \"Unit\": {} }",
            "```",
            "",
            "## types-0002: Undecided thing {node=Type status=pending}",
            "Why it is pending.",
            "```json rejected diagnostic=ambiguous_shorthand",
            "[1]",
            "```",
        ]
        .join("\n");
        let ParsedFile { cases, errors } = parse_kit_file(FILE, &good);
        assert_eq!(errors, vec![]);
        let [first, second] = cases.as_slice() else {
            panic!("expected two cases")
        };
        assert_eq!(first.id.as_str(), "types-0001");
        assert_eq!(
            (first.topic.as_str(), first.number, first.title.as_str()),
            ("types", 1, "Unit type")
        );
        assert_eq!(
            (first.node.as_deref(), first.version),
            (Some("Type"), Some(4))
        );
        assert_eq!(
            (first.status, first.compare),
            (Status::Active, Compare::Stripped)
        );
        assert_eq!(first.prose, vec!["Prose line."]);
        assert_eq!((first.file.as_str(), first.line), (FILE, 3));
        let fences: Vec<_> = first
            .fences
            .iter()
            .map(|f| (f.info.role, f.info.language, f.index))
            .collect();
        assert_eq!(
            fences,
            vec![
                (Role::Canonical, Language::Yaml, 0),
                (Role::Accepted, Language::Json, 1)
            ]
        );
        assert_eq!(
            (second.id.as_str(), second.status, second.version),
            ("types-0002", Status::Pending, None)
        );
    }

    #[test]
    fn reports_structural_errors() {
        let table = [
            ("## types-1: bad id", "malformed case id"),
            (
                "## values-0001: wrong topic",
                "topic \"values\" does not match file topic \"types\"",
            ),
            (
                "## types-0001: dup\n```yaml canonical\na: 1\n```\n## types-0001: dup again\n```yaml canonical\na: 1\n```",
                "duplicate case id \"types-0001\"",
            ),
            (
                "## types-0001: keys {bogus=1}\n```yaml canonical\na: 1\n```",
                "unknown heading key \"bogus\"",
            ),
            (
                "## types-0001: keys {status=done}\n```yaml canonical\na: 1\n```",
                "status must be pending",
            ),
            (
                "## types-0001: keys {compare=text}\n```yaml canonical\na: 1\n```",
                "compare must be attributes",
            ),
            (
                "## types-0001: keys {version=four}\n```yaml canonical\na: 1\n```",
                "version must be an integer, got \"four\"",
            ),
            (
                "```yaml canonical\na: 1\n```",
                "data fence before the first case",
            ),
            (
                "## types-0001: two\n```yaml canonical\na: 1\n```\n```yaml canonical\na: 1\n```",
                "more than one canonical yaml fence",
            ),
            (
                "## types-0001: pending with data {status=pending}\n```yaml canonical\na: 1\n```",
                "pending case may not carry canonical",
            ),
            (
                "## types-0001: nothing\nprose only",
                "case has no data fences",
            ),
            (
                "## types-0001: bad fence\n```yaml canonical\na: 1\n```\n```yaml rejected\na: 1\n```",
                "rejected needs exactly one",
            ),
            (
                "## types-0001: open\n```yaml canonical\na: 1\n",
                "unterminated fence",
            ),
            (
                "## types-0001: accepted only\n```json accepted\n1\n```",
                "active case has no canonical fence",
            ),
        ];
        for (source, expected) in table {
            let joined = messages(FILE, source).join("\n");
            assert!(
                joined.contains(expected),
                "{source:?} reported {joined:?}, expected {expected:?}"
            );
        }
    }

    #[test]
    fn illustrative_fences_without_a_role_are_ignored() {
        let parsed = parse_kit_file(
            FILE,
            "## types-0001: ok\n```ts\nconst x = 1\n```\n```yaml canonical\na: 1\n```",
        );
        assert_eq!(parsed.errors, vec![]);
        assert_eq!(parsed.cases[0].fences.len(), 1);
    }

    #[test]
    fn a_heading_key_block_with_no_space_before_the_brace_parses() {
        let parsed = parse_kit_file(
            FILE,
            "## types-0001: Tight{node=Type compare=attributes}\n```yaml canonical\na: 1\n```",
        );
        assert_eq!(parsed.errors, vec![]);
        let case = &parsed.cases[0];
        assert_eq!(
            (case.title.as_str(), case.node.as_deref(), case.compare),
            ("Tight", Some("Type"), Compare::Attributes)
        );
    }

    #[test]
    fn braces_inside_a_title_belong_to_the_title() {
        let parsed = parse_kit_file(
            FILE,
            "## types-0001: Record {a} shape {node=Type}\n```yaml canonical\na: 1\n```",
        );
        assert_eq!(parsed.errors, vec![]);
        assert_eq!(parsed.cases[0].title, "Record {a} shape");
    }

    /// A pending case shows the spellings under discussion as illustrations,
    /// which are not data, so it may have no data fence at all. The corpus
    /// relies on this (versions-0002); only an active case must carry data.
    #[test]
    fn a_pending_case_may_carry_only_illustrations() {
        let source = "## types-0001: undecided {status=pending}\nWhy.\n```yaml\nmaybe: this\n```\n";
        let parsed = parse_kit_file(FILE, source);
        assert_eq!(parsed.errors, vec![]);
        assert_eq!(
            (parsed.cases[0].status, parsed.cases[0].fences.len()),
            (Status::Pending, 0)
        );
    }

    #[test]
    fn a_rejection_only_active_case_is_legal() {
        let parsed = parse_kit_file(
            FILE,
            "## types-0001: reject only\n```json rejected diagnostic=x\n1\n```",
        );
        assert_eq!(parsed.errors, vec![]);
        assert_eq!(parsed.cases[0].status, Status::Active);
    }

    fn tree_case(title: &str, fences: &[&str]) -> String {
        let mut lines = vec![
            format!("## document-tree-0001: {title}"),
            "```yaml canonical".into(),
            "a: 1".into(),
            "```".into(),
        ];
        for (n, info) in fences.iter().enumerate() {
            lines.extend([format!("```{info}"), format!("a: {n}"), "```".into()]);
        }
        lines.join("\n")
    }

    #[test]
    fn mode_read_is_all_or_nothing_within_a_set_and_independent_between_sets() {
        let mixed = tree_case(
            "modes",
            &[
                "yaml file path=manifest set=meta mode=read",
                "yaml file path=pkg/a/b/m/module set=meta",
            ],
        );
        assert_eq!(
            messages("document-tree.md", &mixed),
            vec!["set meta mixes mode=read and default fences"]
        );

        let uniform = tree_case(
            "modes",
            &[
                "yaml file path=manifest set=meta mode=read",
                "yaml file path=pkg/a/b/m/module set=meta mode=read",
                "yaml file path=manifest set=plain",
            ],
        );
        assert_eq!(messages("document-tree.md", &uniform), Vec::<String>::new());
    }

    #[test]
    fn a_set_that_repeats_a_logical_path_is_an_error_and_another_set_may_reuse_it() {
        let repeated = tree_case(
            "paths",
            &[
                "yaml file path=manifest set=s",
                "yaml file path=manifest set=s",
            ],
        );
        assert_eq!(
            messages("document-tree.md", &repeated),
            vec!["set s repeats path manifest"]
        );
        let two_sets = tree_case(
            "paths",
            &[
                "yaml file path=manifest set=s",
                "yaml file path=manifest set=t",
            ],
        );
        assert_eq!(
            messages("document-tree.md", &two_sets),
            Vec::<String>::new()
        );
    }

    #[test]
    fn the_anonymous_set_is_named_unnamed() {
        let source = tree_case(
            "anonymous",
            &["yaml file path=manifest", "yaml file path=manifest"],
        );
        assert_eq!(
            messages("document-tree.md", &source),
            vec!["set (unnamed) repeats path manifest"]
        );
    }

    #[test]
    fn canonical_count_is_per_profile_not_per_language() {
        let dupe = "## types-0001: dupe profile\n```json canonical\n{ \"a\": 1 }\n```\n```text canonical\nx.json\n```";
        assert!(
            messages(FILE, dupe)
                .join("\n")
                .contains("more than one canonical json fence")
        );
        let distinct = "## types-0001: distinct profiles\n```yaml canonical\na: 1\n```\n```text canonical\nx.json\n```";
        assert_eq!(messages(FILE, distinct), Vec::<String>::new());
    }
}
