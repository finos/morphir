//! Lowers a `.feature` case file into the engine's kit cases, so a `.feature`
//! case runs through the same engine, and gives the same report records, as
//! its Markdown twin.
//!
//! - **Cases:** a scenario whose name starts with `<topic>-<NNNN> ` belongs to
//!   that case, and consecutive scenarios with the same id form one case. The
//!   first scenario's name gives the title, and its description gives the
//!   prose.
//! - **Tags:** feature, rule and scenario tags merge, and the more specific
//!   tag wins. `@node:<Kind>`, `@version:<n>`, `@compare:attributes` and
//!   `@pending` set the case's heading keys. On an Examples block they are an
//!   error.
//! - **Description:** the feature's description is the file's introduction.
//! - **Fences:** each data step gives one fence, in step order, with an
//!   outline's rows expanded block by block and row by row. A tree check step
//!   gives no fence.
//! - **Checks:** the Markdown parser's per-case checks run on each lowered
//!   case, at the step's or the scenario's line.
//!
//! [`LoweredFile::fences`] maps each data step, as morphir-bdd names it at run
//! time, to its fence.

use std::collections::{HashMap, HashSet};

use morphir_gherkin::{
    Description, DescriptionBlock, Document, NodePath, Scenario, Segment, StepArgument, Tag,
};

use super::vocabulary::{Body, KitStep, parse_step};
use crate::kit::syntax::case::{
    CaseId, Compare, KitCase, KitError, KitFence, ParsedFile, Status, case_errors,
};
use crate::kit::syntax::info_string::{FenceInfo, Language, Role};
use crate::schema::is_node_kind;

/// Where a step's fence is: the case and the fence index in that case.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct FenceRef {
    /// The case's index in `LoweredFile.parsed.cases`.
    pub case: usize,
    /// The fence's index in that case's `fences`.
    pub fence: usize,
}

/// A lowered case file: the cases in file order, the errors (with the file and line of the step
/// or tag that caused them), and a map from each data step to its fence.
pub struct LoweredFile {
    /// The cases and the errors.
    pub parsed: ParsedFile,
    /// Key: (the scenario's node path, or its Examples block's path for an outline row; the
    /// outline row, `None` for a plain scenario; the step's source line). The key matches
    /// morphir-bdd's `ScenarioRef` fields and `gherkin::Step::position.line`.
    pub fences: HashMap<(NodePath, Option<usize>, usize), FenceRef>,
    /// The feature's description: the file's introduction, its paragraphs joined by a blank
    /// line, as the converter's `feature_description` gives it for a Markdown file.
    pub description: String,
}

/// Lowers one `.feature` case file. `file` is its repository-relative path, as `KitCase.file`.
pub fn lower(file: &str, doc: &Document) -> LoweredFile {
    let mut lowering = Lowering {
        file,
        file_topic: feature_topic(file),
        seen: HashSet::new(),
        draft: None,
        cases: Vec::new(),
        errors: Vec::new(),
        fences: HashMap::new(),
    };
    let mut description = String::new();
    if let Some(feature) = &doc.feature {
        description = prose(&feature.description).join("\n\n");
        let feature_tags = lowering.tags(&feature.tags);
        if let Some(background) = &feature.background {
            lowering.fail(
                background.position.line,
                "a kit case file may not have a background".to_owned(),
            );
        }
        let feature_path = NodePath::feature();
        // Each scenario with the tags around it: the feature's, then its rule's over them.
        let mut scenarios: Vec<(NodePath, &Scenario, CaseTags)> = feature
            .scenarios
            .iter()
            .enumerate()
            .map(|(i, s)| {
                let path = feature_path.push(Segment::Scenario(i));
                (path, s, feature_tags.clone())
            })
            .collect();
        for (r, rule) in feature.rules.iter().enumerate() {
            if let Some(background) = &rule.background {
                lowering.fail(
                    background.position.line,
                    "a kit case file may not have a background".to_owned(),
                );
            }
            let rule_tags = lowering.tags(&rule.tags).over(&feature_tags);
            let rule_path = feature_path.push(Segment::Rule(r));
            scenarios.extend(rule.scenarios.iter().enumerate().map(|(i, s)| {
                let path = rule_path.push(Segment::Scenario(i));
                (path, s, rule_tags.clone())
            }));
        }
        for (path, scenario, outer_tags) in scenarios {
            lowering.scenario(&outer_tags, &path, scenario);
        }
    }
    lowering.finish();
    let mut seen = HashSet::new();
    let errors = lowering
        .errors
        .into_iter()
        .filter(|e| seen.insert((e.line, e.message.clone())))
        .collect();
    LoweredFile {
        parsed: ParsedFile {
            cases: lowering.cases,
            errors,
        },
        fences: lowering.fences,
        description,
    }
}

/// The file's topic: its base name without `.feature` (or `.feature.md`).
fn feature_topic(file: &str) -> &str {
    let base = file.rsplit(['/', '\\']).next().unwrap_or(file);
    base.strip_suffix(".feature.md")
        .or_else(|| base.strip_suffix(".feature"))
        .unwrap_or(base)
}

/// The heading keys that tags on one node set. `None` means the node does not set that key.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
struct CaseTags {
    node: Option<String>,
    version: Option<i64>,
    compare: Option<Compare>,
    pending: bool,
}

impl CaseTags {
    /// These tags over `outer`: a key set here wins.
    fn over(&self, outer: &Self) -> Self {
        Self {
            node: self.node.clone().or_else(|| outer.node.clone()),
            version: self.version.or(outer.version),
            compare: self.compare.or(outer.compare),
            pending: self.pending || outer.pending,
        }
    }
}

/// Whether `tag` is one of the kit's own: `@pending`, or a tag in the `node`, `version` or
/// `compare` namespace.
fn is_kit_tag(tag: &Tag) -> bool {
    tag.name == "pending" || matches!(tag.namespaced(), Some(("node" | "version" | "compare", _)))
}

/// A scenario name's case id and title: `<topic>-<NNNN> <title>`.
struct CaseName<'a> {
    topic: &'a str,
    digits: &'a str,
    title: &'a str,
}

/// `^([a-z][a-z0-9-]*)-(\d{4}) (.+)$`
fn case_name(name: &str) -> Option<CaseName<'_>> {
    let (id, title) = name.split_once(' ')?;
    let (topic, digits) = id.split_at_checked(id.len().checked_sub(5)?)?;
    let digits = digits
        .strip_prefix('-')
        .filter(|d| d.bytes().all(|b| b.is_ascii_digit()))?;
    let topic_ok = topic.starts_with(|c: char| c.is_ascii_lowercase())
        && topic
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-');
    (topic_ok && !title.trim().is_empty()).then_some(CaseName {
        topic,
        digits,
        title,
    })
}

struct Lowering<'a> {
    file: &'a str,
    file_topic: &'a str,
    seen: HashSet<String>,
    /// The case being built, and the merged tags of its first scenario.
    draft: Option<(KitCase, CaseTags)>,
    cases: Vec<KitCase>,
    errors: Vec<KitError>,
    fences: HashMap<(NodePath, Option<usize>, usize), FenceRef>,
}

impl Lowering<'_> {
    fn fail(&mut self, line: usize, message: String) {
        self.errors.push(KitError {
            file: self.file.to_owned(),
            line,
            message,
        });
    }

    /// Reads the heading-key tags of one node. Tags outside the `node`, `version` and `compare`
    /// namespaces, other than `@pending`, are not the kit's and are ignored.
    fn tags(&mut self, tags: &[Tag]) -> CaseTags {
        let mut out = CaseTags::default();
        for tag in tags {
            let line = tag.position.line;
            if tag.name == "pending" {
                out.pending = true;
                continue;
            }
            match tag.namespaced() {
                Some(("node", kind)) if is_node_kind(kind) => out.node = Some(kind.to_owned()),
                Some(("node", kind)) => self.fail(line, format!("unknown node kind \"{kind}\"")),
                Some(("version", value)) => match value.parse::<i64>() {
                    Ok(version) => out.version = Some(version),
                    Err(_) => {
                        self.fail(line, format!("version must be an integer, got \"{value}\""))
                    }
                },
                Some(("compare", "attributes")) => out.compare = Some(Compare::Attributes),
                Some(("compare", value)) => {
                    self.fail(line, format!("compare must be attributes, got \"{value}\""))
                }
                _ => {}
            }
        }
        out
    }

    /// Runs the per-case checks on the case being built, and adds it to the cases.
    fn finish(&mut self) {
        let Some((case, _)) = self.draft.take() else {
            return;
        };
        for (line, message) in case_errors(&case) {
            self.fail(line, message);
        }
        self.cases.push(case);
    }

    /// Lowers one scenario. `outer_tags` are the merged tags of its feature and rule.
    fn scenario(&mut self, outer_tags: &CaseTags, path: &NodePath, scenario: &Scenario) {
        let line = scenario.position.line;
        let Some(name) = case_name(&scenario.name) else {
            self.fail(
                line,
                format!(
                    "malformed case id in scenario name \"{}\"; expected \"<topic>-<NNNN> <title>\"",
                    scenario.name
                ),
            );
            return;
        };
        let tags = self.tags(&scenario.tags).over(outer_tags);
        let id = format!("{}-{}", name.topic, name.digits);
        match &self.draft {
            Some((case, first)) if case.id.as_str() == id => {
                if *first != tags {
                    let message = format!("scenario tags differ from the first scenario of {id}");
                    self.fail(line, message);
                }
            }
            _ => self.open_case(&name, &id, tags, line, &scenario.description),
        }
        if scenario.examples.is_empty() {
            for step in &scenario.steps {
                let key = (path.clone(), None, step.position.line);
                self.step(key, &step.text, step.argument.as_ref());
            }
            return;
        }
        for (e, examples) in scenario.examples.iter().enumerate() {
            for tag in examples.tags.iter().filter(|tag| is_kit_tag(tag)) {
                let message = format!("the kit tag @{} may not sit on an Examples block", tag.name);
                self.fail(tag.position.line, message);
            }
            let Some((header, rows)) = examples
                .table
                .as_ref()
                .and_then(|table| table.rows.split_first())
            else {
                continue;
            };
            let examples_path = path.push(Segment::Examples(e));
            for (r, row) in rows.iter().enumerate() {
                for step in &scenario.steps {
                    let step_line = step.position.line;
                    let text = match substitute(&step.text, header, row, true) {
                        Ok(text) => text,
                        Err(message) => {
                            self.fail(step_line, message);
                            continue;
                        }
                    };
                    let argument = step.argument.as_ref().map(|argument| match argument {
                        StepArgument::DocString(doc) => {
                            let mut doc = doc.clone();
                            doc.body = substitute(&doc.body, header, row, false)
                                .unwrap_or_else(|_| doc.body.clone());
                            StepArgument::DocString(doc)
                        }
                        StepArgument::Table(table) => StepArgument::Table(table.clone()),
                    });
                    let key = (examples_path.clone(), Some(r), step_line);
                    self.step(key, &text, argument.as_ref());
                }
            }
        }
    }

    fn open_case(
        &mut self,
        name: &CaseName<'_>,
        id: &str,
        tags: CaseTags,
        line: usize,
        description: &Description,
    ) {
        self.finish();
        if name.topic != self.file_topic {
            self.fail(
                line,
                format!(
                    "topic \"{}\" does not match file topic \"{}\"",
                    name.topic, self.file_topic
                ),
            );
        }
        if !self.seen.insert(id.to_owned()) {
            self.fail(line, format!("duplicate case id \"{id}\""));
        }
        let case = KitCase {
            id: CaseId::from_parts(name.topic, name.digits),
            topic: name.topic.to_owned(),
            number: name.digits.parse().unwrap_or(0),
            title: name.title.to_owned(),
            node: tags.node.clone(),
            version: tags.version,
            status: if tags.pending {
                Status::Pending
            } else {
                Status::Active
            },
            compare: tags.compare.unwrap_or(Compare::Stripped),
            prose: prose(description),
            fences: Vec::new(),
            file: self.file.to_owned(),
            line,
        };
        self.draft = Some((case, tags));
    }

    /// Lowers one step, already expanded for an outline row, into a fence of the case being built.
    fn step(
        &mut self,
        key: (NodePath, Option<usize>, usize),
        text: &str,
        argument: Option<&StepArgument>,
    ) {
        let line = key.2;
        let doc_string = match argument {
            Some(StepArgument::Table(_)) => {
                self.fail(line, "a kit step takes no data table".to_owned());
                return;
            }
            Some(StepArgument::DocString(doc)) => Some((&doc.content_type, doc.body.as_str())),
            None => None,
        };
        let step = match parse_step(text, doc_string) {
            None => return self.fail(line, "not a kit step".to_owned()),
            Some(Err(message)) => return self.fail(line, message),
            Some(Ok(KitStep::TreeCheck { .. })) => return,
            Some(Ok(step)) => step,
        };
        let (info, body) = match fence_of(step) {
            Ok(fence) => fence,
            Err(message) => return self.fail(line, message),
        };
        let case_index = self.cases.len();
        let Some((case, _)) = self.draft.as_mut() else {
            return;
        };
        let index = case.fences.len();
        case.fences.push(KitFence {
            info,
            body,
            line,
            index,
        });
        self.fences.insert(
            key,
            FenceRef {
                case: case_index,
                fence: index,
            },
        );
    }
}

/// The fence body a step's document gives: an inline document gains its line break; a doc
/// string's text is the body unchanged.
fn body_text(body: Body) -> String {
    match body {
        Body::Inline(inline) => inline + "\n",
        Body::DocString { text, .. } => text,
    }
}

/// The fence info and body of a data step. A tree check has no fence and is not passed here.
fn fence_of(step: KitStep) -> Result<(FenceInfo, String), String> {
    let no_keys: [(&str, String); 0] = [];
    Ok(match step {
        KitStep::Canonical { format, body } => (
            FenceInfo::from_parts(format.language(), Role::Canonical, no_keys),
            body_text(body),
        ),
        KitStep::Accepted {
            format,
            body,
            warning,
        } => (
            FenceInfo::from_parts(
                format.language(),
                Role::Accepted,
                warning.map(|warning| ("warning", warning)),
            ),
            body_text(body),
        ),
        KitStep::Rejected {
            format,
            body,
            diagnostic,
        } => (
            FenceInfo::from_parts(
                format.language(),
                Role::Rejected,
                [("diagnostic", diagnostic)],
            ),
            body_text(body),
        ),
        KitStep::ReadsAs { format, body, node } => (
            FenceInfo::from_parts(format.language(), Role::Rejected, [("expect", node)]),
            body_text(body),
        ),
        KitStep::TreeFile {
            path,
            set,
            read_only,
            body,
        } => {
            let language = tree_file_language(&body)?;
            let mut keys = vec![("path", path)];
            keys.extend(set.map(|set| ("set", set)));
            if read_only {
                keys.push(("mode", "read".to_owned()));
            }
            (
                FenceInfo::from_parts(language, Role::File, keys),
                body_text(body),
            )
        }
        KitStep::TreeCheck { .. } => unreachable!("a tree check has no fence"),
    })
}

/// A tree file's language: its doc string's content type, which must name one.
fn tree_file_language(body: &Body) -> Result<Language, String> {
    let content_type = match body {
        Body::DocString {
            content_type: Some(content_type),
            ..
        } => content_type.as_str(),
        _ => {
            return Err(
                "a tree file's doc string needs a content type: yaml, json or text".to_owned(),
            );
        }
    };
    [Language::Yaml, Language::Json, Language::Text]
        .into_iter()
        .find(|language| language.as_str() == content_type)
        .ok_or_else(|| {
            format!("tree file content type \"{content_type}\" is not yaml, json or text")
        })
}

/// `text` with each `<name>` placeholder replaced by the row's cell in the column `name`. A
/// placeholder is `<`, a name with no whitespace and no `<`, and `>`. In `strict` mode a
/// placeholder that names no column is an error; otherwise it stays as written.
fn substitute(
    text: &str,
    header: &[String],
    row: &[String],
    strict: bool,
) -> Result<String, String> {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(open) = rest.find('<') {
        out.push_str(&rest[..open]);
        let after = &rest[open + 1..];
        let name = after.find('>').map(|close| &after[..close]).filter(|name| {
            !name.is_empty() && !name.contains(|c: char| c.is_whitespace() || c == '<')
        });
        match name {
            Some(name) => {
                match header.iter().position(|column| column == name) {
                    Some(column) => out.push_str(row.get(column).map_or("", String::as_str)),
                    None if strict => return Err(format!("unknown placeholder <{name}>")),
                    None => {
                        out.push('<');
                        out.push_str(name);
                        out.push('>');
                    }
                }
                rest = &after[name.len() + 1..];
            }
            None => {
                out.push('<');
                rest = after;
            }
        }
    }
    out.push_str(rest);
    Ok(out)
}

/// A case's prose from its first scenario's description, as the Markdown parser gives it: one
/// entry per run of consecutive non-blank lines. Prose blocks on adjacent lines join into one
/// entry, fences are illustrations and are left out, and the description's common indent is
/// removed from every line.
fn prose(description: &Description) -> Vec<String> {
    let mut paragraphs: Vec<(usize, String)> = Vec::new();
    let mut last_line: Option<usize> = None;
    for block in &description.blocks {
        let DescriptionBlock::Prose(block) = block else {
            last_line = None;
            continue;
        };
        let text = block.markdown.trim_end_matches(['\n', '\r']);
        let start = block.position.line;
        let end = start + text.matches('\n').count();
        match paragraphs.last_mut() {
            Some((_, paragraph)) if last_line.is_some_and(|last| last + 1 == start) => {
                paragraph.push('\n');
                paragraph.push_str(text);
            }
            _ => paragraphs.push((start, text.to_owned())),
        }
        last_line = Some(end);
    }
    let indent = paragraphs
        .iter()
        .flat_map(|(_, text)| text.lines())
        .filter(|line| !line.trim().is_empty())
        .map(|line| line.len() - line.trim_start_matches(' ').len())
        .min()
        .unwrap_or(0);
    paragraphs
        .into_iter()
        .map(|(_, text)| {
            text.split('\n')
                .map(|line| {
                    let removable = line.len() - line.trim_start_matches(' ').len();
                    &line[removable.min(indent)..]
                })
                .collect::<Vec<_>>()
                .join("\n")
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use morphir_gherkin::{Segment, read_str};

    use super::*;
    use crate::kit::syntax::case::{Compare, Status};
    use crate::kit::{Language, Role};

    const FILE: &str = "spec/ir/mck/values.feature";

    fn lowered(text: &str) -> LoweredFile {
        let (doc, _) = read_str(FILE, text).expect("the text reads");
        lower(FILE, &doc)
    }

    fn errors(file: &LoweredFile) -> Vec<(usize, String)> {
        file.parsed
            .errors
            .iter()
            .map(|e| {
                assert_eq!(e.file, FILE);
                (e.line, e.message.clone())
            })
            .collect()
    }

    const VALUES_0003_FEATURE: &str = r#"@node:Value
Feature: Values

  Scenario Outline: values-0003 Reference shorthand
    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling                                  |
      | YAML   | Reference: morphir/SDK:basics#add         |
      | JSON   | { "Reference": "morphir/SDK:basics#add" } |

  Scenario: values-0003 Reference shorthand
    Then a reader of JSON accepts "morphir/SDK:basics#add"
"#;

    #[test]
    fn values_0003_lowers_to_one_case_with_three_fences() {
        let file = lowered(VALUES_0003_FEATURE);
        assert_eq!(errors(&file), vec![]);
        let [case] = file.parsed.cases.as_slice() else {
            panic!("expected one case, got {:?}", file.parsed.cases)
        };
        assert_eq!(
            (case.id.as_str(), case.topic.as_str(), case.number),
            ("values-0003", "values", 3)
        );
        assert_eq!(
            (case.title.as_str(), case.node.as_deref(), case.status),
            ("Reference shorthand", Some("Value"), Status::Active)
        );
        assert_eq!((case.file.as_str(), case.line), (FILE, 4));
        let fences: Vec<_> = case
            .fences
            .iter()
            .map(|f| (f.info.language, f.info.role, f.body.as_str(), f.index))
            .collect();
        assert_eq!(
            fences,
            vec![
                (
                    Language::Yaml,
                    Role::Canonical,
                    "Reference: morphir/SDK:basics#add\n",
                    0
                ),
                (
                    Language::Json,
                    Role::Canonical,
                    "{ \"Reference\": \"morphir/SDK:basics#add\" }\n",
                    1
                ),
                (
                    Language::Json,
                    Role::Accepted,
                    "\"morphir/SDK:basics#add\"\n",
                    2
                ),
            ]
        );
    }

    #[test]
    fn each_outline_row_maps_to_its_fence() {
        let file = lowered(VALUES_0003_FEATURE);
        let examples = |scenario| {
            NodePath::from_segments(&[
                Segment::Feature,
                Segment::Scenario(scenario),
                Segment::Examples(0),
            ])
        };
        let expected = HashMap::from([
            ((examples(0), Some(0), 5), FenceRef { case: 0, fence: 0 }),
            ((examples(0), Some(1), 5), FenceRef { case: 0, fence: 1 }),
            (
                (
                    NodePath::from_segments(&[Segment::Feature, Segment::Scenario(1)]),
                    None,
                    13,
                ),
                FenceRef { case: 0, fence: 2 },
            ),
        ]);
        assert_eq!(file.fences, expected);
    }

    #[test]
    fn a_bad_tag_a_foreign_step_and_a_second_canonical_are_errors_at_their_lines() {
        let text = r#"@node:Foo
Feature: Values

  Scenario: values-0001 Bad
    Then its canonical YAML spelling is a: 1
    And its canonical YAML spelling is b: 2
    And I run "morphir x"
"#;
        let mut found = errors(&lowered(text));
        found.sort();
        assert_eq!(
            found,
            vec![
                (1, "unknown node kind \"Foo\"".to_owned()),
                (
                    6,
                    "more than one canonical yaml fence in values-0001".to_owned()
                ),
                (7, "not a kit step".to_owned()),
            ]
        );
    }

    #[test]
    fn a_doc_string_step_and_tree_files_lower_to_fences_with_their_keys() {
        let text = r#"Feature: Document tree

  @node:Distribution @version:3
  Scenario: document-tree-0001 A tree
    A case's prose.

    Second paragraph,
    two lines.

    Then its canonical YAML spelling is:
      """yaml
      a: 1
        b: 2
      """
    Given the read-only tree file "manifest" in set "meta":
      """json
      { "x": 1 }
      """
    Then the "meta" tree reads back as the canonical form
"#;
        let path = "spec/ir/mck/document-tree.feature";
        let (doc, _) = read_str(path, text).expect("the text reads");
        let file = lower(path, &doc);
        assert_eq!(file.parsed.errors, vec![]);
        let case = &file.parsed.cases[0];
        assert_eq!(
            (case.node.as_deref(), case.version),
            (Some("Distribution"), Some(3))
        );
        assert_eq!(
            case.prose,
            vec!["A case's prose.", "Second paragraph,\ntwo lines."]
        );
        let [canonical, tree] = case.fences.as_slice() else {
            panic!("expected two fences, got {:?}", case.fences)
        };
        assert_eq!(canonical.body, "a: 1\n  b: 2\n");
        assert_eq!(
            (tree.info.language, tree.info.role, tree.body.as_str()),
            (Language::Json, Role::File, "{ \"x\": 1 }\n")
        );
        assert_eq!(
            tree.info.keys().collect::<Vec<_>>(),
            vec![("mode", "read"), ("path", "manifest"), ("set", "meta")]
        );
        let scenario = NodePath::from_segments(&[Segment::Feature, Segment::Scenario(0)]);
        assert_eq!(
            file.fences.get(&(scenario, None, 15)),
            Some(&FenceRef { case: 0, fence: 1 })
        );
    }

    #[test]
    fn scenario_tags_win_over_feature_tags_and_pending_is_kept() {
        let text = r#"@node:Value @version:4
Feature: Values

  @version:3 @pending
  Scenario: values-0001 Undecided
    Then a reader of JSON rejects 1 with bad_thing
"#;
        let file = lowered(text);
        assert_eq!(errors(&file), vec![]);
        let case = &file.parsed.cases[0];
        assert_eq!(
            (case.node.as_deref(), case.version, case.status),
            (Some("Value"), Some(3), Status::Pending)
        );
    }

    #[test]
    fn rule_tags_sit_between_feature_and_scenario_tags() {
        let text = r#"@node:Value @version:4
Feature: Values

  @version:3 @compare:attributes
  Rule: Version 3

    @compare:attributes
    Scenario: values-0001 From the rule
      Then its canonical YAML spelling is a: 1

    @version:2
    Scenario: values-0002 From the scenario
      Then its canonical YAML spelling is a: 1
"#;
        let file = lowered(text);
        assert_eq!(errors(&file), vec![]);
        let keys: Vec<_> = file
            .parsed
            .cases
            .iter()
            .map(|c| (c.node.as_deref(), c.version, c.compare))
            .collect();
        assert_eq!(
            keys,
            vec![
                (Some("Value"), Some(3), Compare::Attributes),
                (Some("Value"), Some(2), Compare::Attributes),
            ]
        );
        let rule_scenario =
            NodePath::from_segments(&[Segment::Feature, Segment::Rule(0), Segment::Scenario(0)]);
        assert_eq!(
            file.fences.get(&(rule_scenario, None, 9)),
            Some(&FenceRef { case: 0, fence: 0 })
        );
    }

    #[test]
    fn a_kit_tag_on_an_examples_block_is_an_error() {
        let text = r#"Feature: Values

  Scenario Outline: values-0001 Outline
    Then its canonical <format> spelling is <spelling>

    @pending @spelling
    Examples:
      | format | spelling |
      | YAML   | a: 1     |
"#;
        assert_eq!(
            errors(&lowered(text)),
            vec![(
                6,
                "the kit tag @pending may not sit on an Examples block".to_owned()
            )]
        );
    }

    #[test]
    fn the_feature_description_is_kept() {
        let text = "Feature: Values\n  First,\n  two lines.\n\n  Second.\n\n  Scenario: values-0001 x\n    Then its canonical YAML spelling is a: 1\n";
        assert_eq!(lowered(text).description, "First,\ntwo lines.\n\nSecond.");
    }

    #[test]
    fn an_unknown_placeholder_is_an_error() {
        let text = r#"Feature: Values

  Scenario Outline: values-0001 Outline
    Then its canonical <format> spelling is <spellnig>

    Examples:
      | format | spelling |
      | YAML   | a: 1     |
"#;
        assert_eq!(
            errors(&lowered(text)),
            vec![
                (4, "unknown placeholder <spellnig>".to_owned()),
                (3, "case has no data fences (values-0001)".to_owned())
            ]
        );
    }
}
