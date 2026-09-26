//! Writes `.feature` text for one Markdown case file's cases: the one-off
//! converter from the kit's Markdown grammar to plain Gherkin.
//!
//! - **Feature:** the Markdown file's `# ` heading names the feature, and its
//!   introduction is the feature's description. A `@node:`, `@version:` or
//!   `@compare:` tag that every case shares goes on the feature, and only
//!   there.
//! - **Scenarios:** each case gives one or more scenarios named
//!   `<id> <title>`, in fence order. A run of at least two consecutive
//!   one-line fences of one step shape forms a scenario outline with a row per
//!   fence. The fences between such runs form a plain scenario: one step per
//!   fence, inline when the document fits, with a doc string otherwise.
//! - **Tree files:** the files of a set are `Given the tree file …:` steps in
//!   one plain scenario, and a tree check step follows the set's last file.
//! - **Prose:** the case's prose is its first scenario's description.
//!
//! [`super::lower`] reads the result back into the same cases.

use std::collections::HashMap;
use std::fmt::Write as _;

use super::vocabulary::{Body, Format, KitStep, inline_safe, parse_step, step_text};
use crate::kit::syntax::case::{Compare, KitCase, KitFence, Status};
use crate::kit::syntax::info_string::{Language, Role};
use crate::kit::syntax::markdown::{Block, tokenize};

/// The feature title for a Markdown case file: its `# ` heading, or `topic` when it has none.
pub fn feature_title(topic: &str, markdown: &str) -> String {
    tokenize(markdown)
        .into_iter()
        .find_map(|block| match block {
            Block::Heading { level: 1, text, .. } => Some(text),
            _ => None,
        })
        .unwrap_or_else(|| topic.to_owned())
}

/// The feature description for a Markdown case file: its introduction, the prose paragraphs
/// before the first case heading, joined by a blank line. It is empty when there are none.
pub fn feature_description(markdown: &str) -> String {
    tokenize(markdown)
        .into_iter()
        .take_while(|block| !matches!(block, Block::Heading { level: 2, .. }))
        .filter_map(|block| match block {
            Block::Prose { text, .. } => Some(text),
            _ => None,
        })
        .collect::<Vec<_>>()
        .join("\n\n")
}

/// Writes the `.feature` text for one Markdown case file's cases (`ParsedFile.cases`), under the
/// feature title `title` (see [`feature_title`]) and with the feature description `description`
/// (see [`feature_description`]).
pub fn convert(title: &str, description: &str, cases: &[KitCase]) -> String {
    let hoisted = Hoisted::of(cases);
    let mut out = String::new();
    let feature_tags = hoisted.tags();
    if !feature_tags.is_empty() {
        let _ = writeln!(out, "{}", feature_tags.join(" "));
    }
    let _ = writeln!(out, "Feature: {title}");
    for line in description.lines() {
        if line.is_empty() {
            out.push('\n');
        } else {
            let _ = writeln!(out, "  {line}");
        }
    }
    for case in cases {
        write_case(&mut out, case, &hoisted);
    }
    out
}

/// The tags every case of a file shares, which go on the feature.
struct Hoisted {
    node: Option<String>,
    version: Option<i64>,
    compare: bool,
}

impl Hoisted {
    fn of(cases: &[KitCase]) -> Self {
        fn shared<T: PartialEq + Clone>(values: impl IntoIterator<Item = Option<T>>) -> Option<T> {
            let mut values = values.into_iter();
            let first = values.next()??;
            values.all(|v| v.as_ref() == Some(&first)).then_some(first)
        }
        Self {
            node: shared(cases.iter().map(|c| c.node.clone())),
            version: shared(cases.iter().map(|c| c.version)),
            compare: !cases.is_empty() && cases.iter().all(|c| c.compare == Compare::Attributes),
        }
    }

    fn tags(&self) -> Vec<String> {
        let mut tags = Vec::new();
        tags.extend(self.node.iter().map(|node| format!("@node:{node}")));
        tags.extend(
            self.version
                .iter()
                .map(|version| format!("@version:{version}")),
        );
        if self.compare {
            tags.push("@compare:attributes".to_owned());
        }
        tags
    }
}

/// The tags each scenario of `case` carries: its heading keys the feature does not hold.
fn scenario_tags(case: &KitCase, hoisted: &Hoisted) -> Vec<String> {
    let mut tags = Vec::new();
    if hoisted.node.is_none()
        && let Some(node) = &case.node
    {
        tags.push(format!("@node:{node}"));
    }
    if hoisted.version.is_none()
        && let Some(version) = case.version
    {
        tags.push(format!("@version:{version}"));
    }
    if !hoisted.compare && case.compare == Compare::Attributes {
        tags.push("@compare:attributes".to_owned());
    }
    if case.status == Status::Pending {
        tags.push("@pending".to_owned());
    }
    tags
}

/// The step shape of an outline: which step it holds, and so which columns its table has.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Shape {
    Canonical,
    Accepted,
    AcceptedWithWarning,
    Rejected,
    /// A reads-as step; `an` is the article before the node kind.
    ReadsAs {
        an: bool,
    },
}

impl Shape {
    fn columns(self) -> &'static [&'static str] {
        match self {
            Self::Canonical => &["format", "spelling"],
            Self::Accepted => &["format", "input"],
            Self::AcceptedWithWarning => &["format", "input", "warning"],
            Self::Rejected => &["format", "input", "diagnostic"],
            Self::ReadsAs { .. } => &["format", "input", "node"],
        }
    }

    /// The outline's step text, with a placeholder per column.
    fn template(self) -> String {
        match self {
            Self::Canonical => "its canonical <format> spelling is <spelling>".to_owned(),
            Self::Accepted => "a reader of <format> accepts <input>".to_owned(),
            Self::AcceptedWithWarning => {
                "a reader of <format> accepts <input> with warning <warning>".to_owned()
            }
            Self::Rejected => "a reader of <format> rejects <input> with <diagnostic>".to_owned(),
            Self::ReadsAs { an } => format!(
                "a reader of <format> reads <input> as {} <node>",
                if an { "an" } else { "a" }
            ),
        }
    }

    /// The step text of one row: the template with each placeholder replaced by its cell.
    fn row_text(self, cells: &[String]) -> String {
        let mut text = self.template();
        for (column, cell) in self.columns().iter().zip(cells) {
            text = text.replace(&format!("<{column}>"), cell);
        }
        text
    }
}

/// One scenario of a case: an outline of a run of at least two one-line fences, or a plain
/// scenario of the fences between those runs.
enum Part<'a> {
    Outline(Shape, Vec<Vec<String>>),
    Plain(Vec<PlainStep<'a>>),
}

/// One step of a plain scenario: a fence with its document inline in the step text, or with a
/// doc string.
enum PlainStep<'a> {
    Inline(&'a KitFence, String),
    DocString(&'a KitFence),
}

impl<'a> PlainStep<'a> {
    fn fence(&self) -> &'a KitFence {
        match self {
            Self::Inline(fence, _) | Self::DocString(fence) => fence,
        }
    }
}

fn format_of(language: Language) -> Format {
    match language {
        Language::Yaml => Format::Yaml,
        Language::Json => Format::Json,
        Language::Text => Format::Text,
    }
}

/// The kit step a fence stands for, with `body` as its document.
fn kit_step(fence: &KitFence, body: Body) -> KitStep {
    let format = format_of(fence.info.language);
    match fence.info.role {
        Role::Canonical => KitStep::Canonical { format, body },
        Role::Accepted => KitStep::Accepted {
            format,
            body,
            warning: fence.info.key("warning").map(str::to_owned),
        },
        Role::Rejected => match fence.info.key("expect") {
            Some(node) => KitStep::ReadsAs {
                format,
                body,
                node: node.to_owned(),
            },
            None => KitStep::Rejected {
                format,
                body,
                diagnostic: fence.info.key("diagnostic").unwrap_or_default().to_owned(),
            },
        },
        Role::File => KitStep::TreeFile {
            path: fence.info.key("path").unwrap_or_default().to_owned(),
            set: fence.info.key("set").map(str::to_owned),
            read_only: fence.info.key("mode") == Some("read"),
            body,
        },
    }
}

/// Whether `cell` can sit in an examples table and in a row's step text unchanged: a `\` is an
/// escape in a Gherkin cell, and a `<name>` would read as a placeholder.
fn cell_safe(cell: &str) -> bool {
    !cell.contains(['\\', '|'])
        && !cell.split('<').skip(1).any(|after| {
            after
                .split_once('>')
                .is_some_and(|(name, _)| !name.is_empty())
        })
}

/// The outline shape and row of a fence whose body fits a table cell, or `None` for a fence
/// that needs a doc string. A row is kept only when its step text reads back as this fence.
fn inline_row(fence: &KitFence) -> Option<(Shape, Vec<String>)> {
    if fence.info.role == Role::File {
        return None;
    }
    let line = fence.body.strip_suffix('\n')?;
    if !inline_safe(line) || !cell_safe(line) {
        return None;
    }
    let step = kit_step(fence, Body::Inline(line.to_owned()));
    let word = format_of(fence.info.language).word().to_owned();
    let (shape, extra) = match &step {
        KitStep::Canonical { .. } => (Shape::Canonical, None),
        KitStep::Accepted { warning: None, .. } => (Shape::Accepted, None),
        KitStep::Accepted {
            warning: Some(warning),
            ..
        } => (Shape::AcceptedWithWarning, Some(warning.clone())),
        KitStep::Rejected { diagnostic, .. } => (Shape::Rejected, Some(diagnostic.clone())),
        KitStep::ReadsAs { node, .. } => (
            Shape::ReadsAs {
                an: node.starts_with(['A', 'E', 'I', 'O', 'U', 'a', 'e', 'i', 'o', 'u']),
            },
            Some(node.clone()),
        ),
        KitStep::TreeFile { .. } | KitStep::TreeCheck { .. } => return None,
    };
    let mut cells = vec![word, line.to_owned()];
    cells.extend(extra);
    if !cells.iter().all(|cell| cell_safe(cell)) {
        return None;
    }
    let reads_back = parse_step(&shape.row_text(&cells), None) == Some(Ok(step));
    reads_back.then_some((shape, cells))
}

/// The step text of a fence written inline in a plain scenario, when it reads back as the
/// fence.
fn inline_text(fence: &KitFence) -> Option<String> {
    let line = fence.body.strip_suffix('\n')?;
    let step = kit_step(fence, Body::Inline(line.to_owned()));
    let text = step_text(&step);
    (parse_step(&text, None) == Some(Ok(step))).then_some(text)
}

/// A case's scenarios, in fence order.
///
/// A run of at least two consecutive one-line fences of one shape is an outline. Every other
/// fence is a step of the plain scenario around it: inline when it fits, with a doc string
/// otherwise. A set's files stay in one plain scenario with its tree check, so every fence
/// from a set's first file to its last is a plain step, whatever its shape.
fn plan(case: &KitCase) -> Vec<Part<'_>> {
    let mut spans: HashMap<Option<&str>, (usize, usize)> = HashMap::new();
    for fence in case.fences.iter().filter(|f| f.info.role == Role::File) {
        spans
            .entry(fence.info.key("set"))
            .and_modify(|span| span.1 = fence.index)
            .or_insert((fence.index, fence.index));
    }
    let in_a_set = |index: usize| spans.values().any(|&(a, b)| a <= index && index <= b);
    let rows: Vec<_> = case
        .fences
        .iter()
        .map(|fence| inline_row(fence).filter(|_| !in_a_set(fence.index)))
        .collect();

    let mut parts: Vec<Part<'_>> = Vec::new();
    let mut at = 0;
    while at < case.fences.len() {
        let run = match &rows[at] {
            Some((shape, _)) => rows[at..]
                .iter()
                .take_while(|row| row.as_ref().is_some_and(|(s, _)| s == shape))
                .count(),
            None => 0,
        };
        if run >= 2 {
            let shape = rows[at].as_ref().map(|(shape, _)| *shape);
            let cells = rows[at..at + run]
                .iter()
                .filter_map(|row| row.as_ref().map(|(_, cells)| cells.clone()))
                .collect();
            parts.extend(shape.map(|shape| Part::Outline(shape, cells)));
            at += run;
            continue;
        }
        let fence = &case.fences[at];
        let step = match inline_row(fence).and_then(|_| inline_text(fence)) {
            Some(text) => PlainStep::Inline(fence, text),
            None => PlainStep::DocString(fence),
        };
        match parts.last_mut() {
            Some(Part::Plain(steps)) => steps.push(step),
            _ => parts.push(Part::Plain(vec![step])),
        }
        at += 1;
    }
    parts
}

fn write_case(out: &mut String, case: &KitCase, hoisted: &Hoisted) {
    let tags = scenario_tags(case, hoisted);
    // The index of each set's last file fence: its tree check follows it.
    let mut last_file: HashMap<Option<&str>, usize> = HashMap::new();
    for fence in case.fences.iter().filter(|f| f.info.role == Role::File) {
        last_file.insert(fence.info.key("set"), fence.index);
    }
    let parts = plan(case);
    if parts.is_empty() {
        write_header(out, &tags, "Scenario", case, true);
        return;
    }
    for (index, part) in parts.iter().enumerate() {
        match part {
            Part::Outline(shape, rows) => {
                write_header(out, &tags, "Scenario Outline", case, index == 0);
                let _ = writeln!(out, "    Then {}", shape.template());
                let _ = writeln!(out, "\n    Examples:");
                write_table(out, shape.columns(), rows);
            }
            Part::Plain(steps) => {
                write_header(out, &tags, "Scenario", case, index == 0);
                let mut previous = None;
                for step in steps {
                    let fence = step.fence();
                    let kind = if fence.info.role == Role::File {
                        "Given"
                    } else {
                        "Then"
                    };
                    match step {
                        PlainStep::Inline(_, text) => write_step(out, &mut previous, kind, text),
                        PlainStep::DocString(_) => {
                            let language = fence.info.language.as_str();
                            let step = kit_step(
                                fence,
                                Body::DocString {
                                    content_type: Some(language.to_owned()),
                                    text: fence.body.clone(),
                                },
                            );
                            write_step(out, &mut previous, kind, &step_text(&step));
                            write_doc_string(out, language, &fence.body);
                        }
                    }
                    if fence.info.role == Role::File
                        && last_file.get(&fence.info.key("set")) == Some(&fence.index)
                    {
                        let check = KitStep::TreeCheck {
                            set: fence.info.key("set").map(str::to_owned),
                        };
                        write_step(out, &mut previous, "Then", &step_text(&check));
                    }
                }
            }
        }
    }
}

/// Writes a scenario's tags and title line, and the case's prose when `with_prose` is set. The
/// prose is followed by a blank line when the scenario has steps to come.
fn write_header(
    out: &mut String,
    tags: &[String],
    keyword: &str,
    case: &KitCase,
    with_prose: bool,
) {
    out.push('\n');
    if !tags.is_empty() {
        let _ = writeln!(out, "  {}", tags.join(" "));
    }
    let _ = writeln!(out, "  {keyword}: {} {}", case.id, case.title);
    if !with_prose || case.prose.is_empty() {
        return;
    }
    for (index, paragraph) in case.prose.iter().enumerate() {
        if index > 0 {
            out.push('\n');
        }
        for line in paragraph.split('\n') {
            let _ = writeln!(out, "    {line}");
        }
    }
    if !case.fences.is_empty() {
        out.push('\n');
    }
}

/// Writes one step line. A step of the same kind as the one before it starts with `And`.
fn write_step(
    out: &mut String,
    previous: &mut Option<&'static str>,
    kind: &'static str,
    text: &str,
) {
    let keyword = if *previous == Some(kind) { "And" } else { kind };
    *previous = Some(kind);
    let _ = writeln!(out, "    {keyword} {text}");
}

/// Writes a `"""` doc string. Each line of `body` is indented to the delimiter, an empty line
/// stays empty, and a `"""` inside the body is escaped as `\"\"\"`.
fn write_doc_string(out: &mut String, content_type: &str, body: &str) {
    let _ = writeln!(out, "      \"\"\"{content_type}");
    for line in body.lines() {
        if line.is_empty() {
            out.push('\n');
        } else {
            let _ = writeln!(out, "      {}", line.replace("\"\"\"", "\\\"\\\"\\\""));
        }
    }
    let _ = writeln!(out, "      \"\"\"");
}

/// Writes an examples table: the header row, then one row per fence, each column padded to its
/// widest cell.
fn write_table(out: &mut String, columns: &[&str], rows: &[Vec<String>]) {
    let widths: Vec<usize> = (0..columns.len())
        .map(|i| {
            rows.iter()
                .map(|row| row[i].chars().count())
                .chain([columns[i].chars().count()])
                .max()
                .unwrap_or(0)
        })
        .collect();
    let mut write_row = |cells: &mut dyn Iterator<Item = &str>| {
        out.push_str("      |");
        for (cell, width) in cells.zip(&widths) {
            let _ = write!(out, " {cell:<width$} |");
        }
        out.push('\n');
    };
    write_row(&mut columns.iter().copied());
    for row in rows {
        write_row(&mut row.iter().map(String::as_str));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::kit::syntax::case::parse_kit_file;

    /// `values-0003` as `gherkin-foundation.md` shows it in Markdown.
    const VALUES_0003: &str = r#"## values-0003: Reference shorthand {node=Value}

```yaml canonical
Reference: morphir/SDK:basics#add
```

```json canonical
{ "Reference": "morphir/SDK:basics#add" }
```

```json accepted
"morphir/SDK:basics#add"
```
"#;

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
    fn values_0003_converts_to_an_outline_and_a_single_inline_step() {
        let parsed = parse_kit_file("spec/ir/mck/values.md", VALUES_0003);
        assert_eq!(parsed.errors, vec![]);
        assert_eq!(convert("Values", "", &parsed.cases), VALUES_0003_FEATURE);
    }

    #[test]
    fn a_body_that_does_not_fit_a_cell_becomes_a_doc_string_and_a_set_ends_with_its_check() {
        let markdown = r#"## document-tree-0001: Doc strings {node=Distribution}

```json rejected diagnostic=bad
{ "a": "x with y" }
```

```json accepted
"a\"b"
```

```yaml file path=manifest set=s mode=read
a: 1
```

```yaml canonical
a: 1
```
"#;
        let parsed = parse_kit_file("spec/ir/mck/document-tree.md", markdown);
        assert_eq!(parsed.errors, vec![]);
        let expected = r#"@node:Distribution
Feature: Document tree

  Scenario: document-tree-0001 Doc strings
    Then a reader of JSON rejects with bad:
      """json
      { "a": "x with y" }
      """
    And a reader of JSON accepts:
      """json
      "a\"b"
      """
    Given the read-only tree file "manifest" in set "s":
      """yaml
      a: 1
      """
    Then the "s" tree reads back as the canonical form
    And its canonical YAML spelling is a: 1
"#;
        assert_eq!(convert("Document tree", "", &parsed.cases), expected);
    }

    #[test]
    fn one_line_fences_inside_a_set_stay_in_the_set_scenario() {
        let markdown = r#"## document-tree-0001: A set around one-line fences {node=Distribution}

```yaml file path=manifest set=s
a: 1
```

```yaml canonical
a: 1
```

```json canonical
{ "a": 1 }
```

```yaml file path=module set=s
b: 2
```

```json accepted
{ "a": 1.0 }
```

```json accepted
{ "a": 1e0 }
```
"#;
        let parsed = parse_kit_file("spec/ir/mck/document-tree.md", markdown);
        assert_eq!(parsed.errors, vec![]);
        let expected = r#"@node:Distribution
Feature: Document tree

  Scenario: document-tree-0001 A set around one-line fences
    Given the tree file "manifest" in set "s":
      """yaml
      a: 1
      """
    Then its canonical YAML spelling is a: 1
    And its canonical JSON spelling is { "a": 1 }
    Given the tree file "module" in set "s":
      """yaml
      b: 2
      """
    Then the "s" tree reads back as the canonical form

  Scenario Outline: document-tree-0001 A set around one-line fences
    Then a reader of <format> accepts <input>

    Examples:
      | format | input        |
      | JSON   | { "a": 1.0 } |
      | JSON   | { "a": 1e0 } |
"#;
        assert_eq!(convert("Document tree", "", &parsed.cases), expected);
    }

    #[test]
    fn the_file_introduction_is_the_feature_description() {
        let markdown = "# Values\n\nFirst paragraph,\ntwo lines.\n\nSecond.\n\n## values-0001: x {node=Value}\n\n```yaml canonical\na: 1\n```\n";
        let description = feature_description(markdown);
        assert_eq!(description, "First paragraph,\ntwo lines.\n\nSecond.");
        let parsed = parse_kit_file("spec/ir/mck/values.md", markdown);
        let text = convert("Values", &description, &parsed.cases);
        assert!(
            text.starts_with(
                "@node:Value\nFeature: Values\n  First paragraph,\n  two lines.\n\n  Second.\n\n  Scenario:"
            ),
            "{text}"
        );
        assert_eq!(
            feature_description("# Versions\n\n## versions-0001: x\n"),
            ""
        );
    }

    #[test]
    fn the_feature_title_is_the_markdown_heading_or_the_topic() {
        assert_eq!(
            feature_title("values", "# Values\n\n## values-0001: x\n"),
            "Values"
        );
        assert_eq!(feature_title("values", "## values-0001: x\n"), "values");
    }
}
