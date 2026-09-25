//! Reads an itest `scenarios.md` file into a `morphir_gherkin::Document`.
//!
//! Each `##` section becomes a Gherkin `Scenario`, built from the typed steps
//! [`model::parse`] already gives for every notebook `markdown::parse_sections` produces from the
//! file. The lowering writes synthetic `.feature` text and hands it to
//! [`morphir_gherkin::read_str`], the simplest way to get a well-formed `Document`; positions in
//! that synthetic text are then rewritten so a step's `position` points at its own fence's line in
//! the real `scenarios.md` file (a scenario's own `position` stays at its section heading's line),
//! since `read_str` has no way to carry a foreign file's line numbers through its own parse.
//!
//! The reader is built on [`model::Step`] and [`model::Metadata`], plus each section's title, id,
//! heading line and per-cell fence lines from [`markdown::parse_sections`]. Two things fall
//! outside that typed surface, and the reader reads them directly off the section's [`Notebook`]
//! instead: overlay files (`morphir:file` cells, which `model::parse` does not surface at all) and
//! the command-order check below (which needs the cells' own file order, lost once they are
//! grouped into [`model::Step::assertions`]).

use super::golden::{LineEndings, Selection};
use super::markdown::{self, ParsedSection};
use super::model::{self, AssertionKind, ExpectedText, Metadata, Step};
use crate::notebook::Notebook;
use anyhow::{Context, Result, bail, ensure};
use morphir_gherkin::Document;
use morphir_gherkin::LineCol;
use serde_json::Value;
use std::fmt::Write as _;
use std::fs;
use std::path::Path;

/// Reads `path` as an itest `scenarios.md` file and lowers it into a `morphir_gherkin::Document`:
/// the frontmatter becomes the `Feature`, and each `##` section becomes a `Scenario`. Fits
/// `morphir_bdd::suite::Reader`, for registration through `Suite::reader("scenarios.md", …)`.
pub fn read_scenarios_md(path: &Path) -> Result<Document, String> {
    read(path).map_err(|error| format!("{error:#}"))
}

fn read(path: &Path) -> Result<Document> {
    let text = fs::read_to_string(path)
        .with_context(|| format!("scenario document {}", path.display()))?;
    let parsed = markdown::parse_sections(&text)
        .with_context(|| format!("scenario document {}", path.display()))?;
    let mut files = Vec::new();
    let mut scenarios = Vec::new();
    for section in &parsed.sections {
        check_command_order(&section.notebook, path, section)?;
        files.extend(overlay_files(&section.notebook)?);
        let (_, steps) = model::parse(&section.notebook)
            .with_context(|| format!("{}: scenario {}", path.display(), section.id))?;
        scenarios.push((section, steps));
    }
    let text = feature_text(&parsed.metadata, &files, &scenarios)?;
    // `read_str` picks Feature or Markdown-with-Gherkin by the path's extension; the real
    // `scenarios.md` extension matches neither, so a synthetic `.feature` name is used to parse,
    // then the document's own path is restored below.
    let synthetic_path = path.with_extension("feature");
    let (mut document, _source) = morphir_gherkin::read_str(synthetic_path, &text)
        .with_context(|| format!("internal error lowering {}", path.display()))?;
    document.path = path.to_owned();
    apply_source_positions(&mut document, &scenarios);
    Ok(document)
}

/// Rewrites every scenario's own `position` and every step's `position` from the synthetic
/// `.feature` text's own coordinates to the real `scenarios.md` file: a scenario's `position`
/// stays at its section heading's line, and each of its steps' `position` moves to that step's own
/// fence's line, from [`step_lines`].
fn apply_source_positions(document: &mut Document, scenarios: &[(&ParsedSection, Vec<Step>)]) {
    let Some(feature) = document.feature.as_mut() else {
        return;
    };
    for (scenario, (section, steps)) in feature.scenarios.iter_mut().zip(scenarios) {
        scenario.position = LineCol {
            line: section.line,
            col: 1,
        };
        let lines = step_lines(section, steps);
        for (step, line) in scenario.steps.iter_mut().zip(&lines) {
            step.position = LineCol {
                line: *line,
                col: 1,
            };
        }
    }
}

/// The real `scenarios.md` line of each physical Gherkin step [`write_command_step`] emits for
/// `steps`, in the same order it emits them: a command's `When`, then one line per capture and,
/// when present, `stdout is JSON` — all at the command's own metadata fence line — then one line
/// per assertion or golden, each at its own fence line.
fn step_lines(section: &ParsedSection, steps: &[Step]) -> Vec<usize> {
    let mut lines = Vec::new();
    for step in steps {
        let command_line = fence_line(section, &step.id);
        lines.push(command_line);
        for _ in &step.captures {
            lines.push(command_line);
        }
        if step.stdout_json {
            lines.push(command_line);
        }
        for assertion in &step.assertions {
            lines.push(fence_line(section, &assertion.id));
        }
    }
    lines
}

/// The line of the cell `id`'s own `yaml morphir:<role>` metadata fence, or the section heading's
/// line when the id has none recorded. The fallback should not be reachable for a well-formed
/// document (every command, assertion and golden cell is recorded), but keeps this infallible.
fn fence_line(section: &ParsedSection, id: &str) -> usize {
    section.fence_lines.get(id).copied().unwrap_or(section.line)
}

/// Fails when an assertion or golden fence's `command` is not the most recently issued command at
/// that point in the file. Grouping a step's assertions right after its own `When` (as
/// [`feature_text`] does) is only faithful to the source when this holds, so a violation is
/// reported rather than silently reordered. `model::Step::assertions` does not carry the cells'
/// own file order, so this walks the notebook's cells directly instead. The reported line is the
/// failing assertion's or golden's own fence line, not the section heading's.
fn check_command_order(notebook: &Notebook, path: &Path, section: &ParsedSection) -> Result<()> {
    let mut last_command: Option<&str> = None;
    for cell in notebook.cells() {
        let Some(role) = cell.morphir().get("itest") else {
            continue;
        };
        match role.get("kind").and_then(Value::as_str) {
            Some("command") => last_command = Some(cell.id()),
            Some(kind @ ("assertion" | "golden")) => {
                let command = role
                    .get("command")
                    .and_then(Value::as_str)
                    .unwrap_or_default();
                if last_command != Some(command) {
                    let line = fence_line(section, cell.id());
                    bail!(
                        "{}:{line}: {kind} {} checks command {command:?}, which is not the last command",
                        path.display(),
                        cell.id()
                    );
                }
            }
            _ => {}
        }
    }
    Ok(())
}

/// The `path` and `content` of every `morphir:file` cell of `notebook`, in file order.
/// `model::parse` does not surface these cells at all (they hold no `itest` role), so they are
/// read directly off the notebook.
fn overlay_files(notebook: &Notebook) -> Result<Vec<(String, String)>> {
    let mut files = Vec::new();
    for cell in notebook.cells() {
        if let Some(file) = cell.morphir().get("file") {
            let path = file
                .get("path")
                .and_then(Value::as_str)
                .with_context(|| format!("cell {}: file fence needs a path", cell.id()))?;
            files.push((path.to_owned(), cell.source().to_owned()));
        }
    }
    Ok(files)
}

/// Builds the synthetic `.feature` text for the whole document: one `Feature` from `metadata` and
/// the aggregated overlay `files`, then one `Scenario` per section of `scenarios`.
fn feature_text(
    metadata: &Metadata,
    files: &[(String, String)],
    scenarios: &[(&ParsedSection, Vec<Step>)],
) -> Result<String> {
    let mut out = String::new();
    write_tags(&mut out, &metadata.tags);
    writeln!(out, "Feature: {}", metadata.title).expect("write to String cannot fail");
    writeln!(out, "  {}", metadata.description).expect("write to String cannot fail");
    out.push('\n');
    write_itest_fence(&mut out, metadata, files);
    out.push('\n');
    for (section, steps) in scenarios {
        let step_count: usize = steps.len()
            + steps
                .iter()
                .map(|step| step.assertions.len())
                .sum::<usize>();
        writeln!(out, "  @section:{} @steps:{step_count}", section.id)
            .expect("write to String cannot fail");
        writeln!(out, "  Scenario: {}", section.title).expect("write to String cannot fail");
        for step in steps {
            write_command_step(&mut out, step)?;
        }
        out.push('\n');
    }
    Ok(out)
}

/// The Feature's `yaml itest` fence: `provider`, `workspace` (only when it differs from the
/// default `Workspace`, since an omitted `workspace` fence field already means the default), and
/// `files` (only when there are overlay files). Every string value is written as a JSON-quoted
/// scalar, never a bare or block-scalar one, so a value such as `y` cannot be misread as a
/// boolean and a multi-line file `content` still fits on one line.
fn write_itest_fence(out: &mut String, metadata: &Metadata, files: &[(String, String)]) {
    writeln!(out, "  ```yaml itest").expect("write to String cannot fail");
    writeln!(out, "  provider: {}", provider_token(metadata.provider))
        .expect("write to String cannot fail");
    if !is_default_workspace(&metadata.workspace) {
        writeln!(out, "  workspace: {}", workspace_yaml(&metadata.workspace))
            .expect("write to String cannot fail");
    }
    if !files.is_empty() {
        writeln!(out, "  files:").expect("write to String cannot fail");
        for (path, content) in files {
            writeln!(
                out,
                "    - {{path: {}, content: {}}}",
                yaml_string(path),
                yaml_string(content)
            )
            .expect("write to String cannot fail");
        }
    }
    writeln!(out, "  ```").expect("write to String cannot fail");
}

fn write_tags(out: &mut String, tags: &[String]) {
    if tags.is_empty() {
        return;
    }
    for tag in tags {
        write!(out, "@{tag} ").expect("write to String cannot fail");
    }
    out.truncate(out.trim_end().len());
    out.push('\n');
}

/// One command's steps: `When I run …`, then its captures and `stdout is JSON`, then its
/// assertions and golden checks, each as a `Then` step.
fn write_command_step(out: &mut String, step: &Step) -> Result<()> {
    let line = command_line(step)?;
    // `command_line` already guarantees `line` holds no literal `"`, and its own whitespace
    // grouping already uses `\"…\"`, so it is wrapped in a plain pair of quotes here rather than
    // through `quote`, which would double-escape those `\"` markers.
    //
    // `Role::Command::timeout_seconds` is a required field of the `yaml morphir:command` fence,
    // so a scenarios.md-derived command always has a timeout; `When I run "<cmd>"` with no
    // timeout is not reachable from this reader.
    writeln!(
        out,
        "    When I run \"{line}\" with a {} second timeout",
        step.timeout_seconds
    )
    .expect("write to String cannot fail");
    for capture in &step.captures {
        writeln!(
            out,
            "    And I capture {} as {} named {}",
            quote(&capture.path),
            capture_format_token(capture.format),
            quote(&capture.name)
        )
        .expect("write to String cannot fail");
    }
    if step.stdout_json {
        writeln!(out, "    And stdout is JSON").expect("write to String cannot fail");
    }
    for assertion in &step.assertions {
        write_assertion(out, assertion);
    }
    Ok(())
}

/// The command line `morphir <args…>`, joined with single spaces. Joining alone would lose an
/// argument's own grouping wherever it holds whitespace (`--message "a b"` would silently become
/// two arguments), so such an argument — and an empty one, which would otherwise vanish between
/// two spaces — is wrapped as `\"…\"`: `morphir-bdd`'s `split_command_line` groups a `\"` the same
/// way it groups a bare `"`. A `"` *inside* an argument cannot be represented at all:
/// `split_command_line` groups a `\"` written inside the step's outer `"…"` the same way it groups
/// a bare `"`, so there is no encoding that both closes the reader's own quoting and still
/// delivers a literal `"` to the program. None of today's examples need one, so this is reported
/// rather than guessed at.
fn command_line(step: &Step) -> Result<String> {
    let mut words = Vec::with_capacity(step.args.len() + 1);
    words.push("morphir".to_owned());
    for arg in &step.args {
        ensure!(
            !arg.contains('"'),
            "command {}: argument {arg:?} contains a literal '\"', which cannot be represented in \
             a scenarios.md-derived `When I run` step",
            step.id
        );
        if arg.is_empty() || arg.chars().any(char::is_whitespace) {
            words.push(format!("\\\"{arg}\\\""));
        } else {
            words.push(arg.clone());
        }
    }
    Ok(words.join(" "))
}

fn capture_format_token(format: model::CaptureFormat) -> &'static str {
    match format {
        model::CaptureFormat::Json => "json",
        model::CaptureFormat::Text => "text",
        model::CaptureFormat::Exists => "exists",
    }
}

fn write_assertion(out: &mut String, assertion: &model::Assertion) {
    match &assertion.kind {
        AssertionKind::Rego {
            source,
            entrypoints,
        } => {
            writeln!(
                out,
                "    Then the result should satisfy the policy rules {}:",
                quote(&entrypoints.join(", "))
            )
            .expect("write to String cannot fail");
            write_doc_string(out, Some("rego"), source);
        }
        AssertionKind::Golden(golden) => write_golden(out, golden),
    }
}

fn write_golden(out: &mut String, golden: &model::Golden) {
    let select = format_select(&golden.select);
    let endings = match golden.line_endings {
        LineEndings::Exact => "exact",
        LineEndings::Lf => "LF",
    };
    match &golden.expected {
        ExpectedText::File(file) => writeln!(
            out,
            "    Then the file {} at {} should match the golden file {} with {endings} line endings",
            quote(&golden.actual),
            quote(&select),
            quote(file)
        )
        .expect("write to String cannot fail"),
        ExpectedText::Inline(body) => {
            writeln!(
                out,
                "    Then the file {} at {} should match with {endings} line endings:",
                quote(&golden.actual),
                quote(&select)
            )
            .expect("write to String cannot fail");
            write_doc_string(out, None, body);
        }
    }
}

/// `all`, `lines <start> to <end>`, or `between '<start>' and '<end>'`. A `between` marker can
/// hold any character, including a newline (see `examples/gleam/compile-generate/scenarios.md`),
/// so each marker is escaped to keep the whole step on one line; `morphir-bdd`'s own step
/// definition (Task C3) reverses the escaping.
fn format_select(select: &Selection) -> String {
    match select {
        Selection::All => "all".to_owned(),
        Selection::Lines { start, end } => format!("lines {start} to {end}"),
        Selection::Between { start, end } => {
            format!(
                "between '{}' and '{}'",
                escape_marker(start),
                escape_marker(end)
            )
        }
    }
}

/// Escapes `\`, `'`, a newline, a carriage return and a tab in a `between` marker, so the whole
/// `<select>` fits on the step text's one physical line. `pub(super)` because Task C3's step
/// definition needs [`unescape_marker`], this escape's inverse, to recover the original marker;
/// this module is the one owner of the rule, so C3 calls it instead of copying it.
pub(super) fn escape_marker(value: &str) -> String {
    let mut escaped = String::with_capacity(value.len());
    for c in value.chars() {
        match c {
            '\\' => escaped.push_str("\\\\"),
            '\'' => escaped.push_str("\\'"),
            '\n' => escaped.push_str("\\n"),
            '\r' => escaped.push_str("\\r"),
            '\t' => escaped.push_str("\\t"),
            other => escaped.push(other),
        }
    }
    escaped
}

/// The inverse of [`escape_marker`]: turns `\\`, `\'`, `\n`, `\r` and `\t` back into the literal
/// character each stands for. `Err` for a backslash followed by anything else, including none (an
/// unfinished escape at the end of the string).
///
/// Called from `steps::library::parse_selection`, which reverses a `between` selection's own
/// escaping back into a `Selection::Between`'s markers. Kept here, next to `escape_marker`, so the
/// escaping rule has one owner instead of being copied into that step definition.
pub(super) fn unescape_marker(value: &str) -> Result<String, String> {
    let mut unescaped = String::with_capacity(value.len());
    let mut chars = value.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            unescaped.push(c);
            continue;
        }
        match chars.next() {
            Some('\\') => unescaped.push('\\'),
            Some('\'') => unescaped.push('\''),
            Some('n') => unescaped.push('\n'),
            Some('r') => unescaped.push('\r'),
            Some('t') => unescaped.push('\t'),
            Some(other) => return Err(format!("invalid marker escape '\\{other}'")),
            None => return Err("marker ends with an unfinished '\\' escape".to_owned()),
        }
    }
    Ok(unescaped)
}

/// Writes a `"""[content_type]` doc string holding `body` verbatim. The delimiter is written with
/// no indent, so the reader's own indent-stripping (`min` of the delimiter's and each body line's
/// leading whitespace) never removes any of the body's own indentation. The only escaping needed
/// is a literal `"""` inside the body, which would otherwise close the doc string early; it is
/// escaped the same way `morphir_gherkin::feature_reader` unescapes it back.
fn write_doc_string(out: &mut String, content_type: Option<&str>, body: &str) {
    out.push_str("\"\"\"");
    if let Some(content_type) = content_type {
        out.push_str(content_type);
    }
    out.push('\n');
    out.push_str(&body.replace("\"\"\"", "\\\"\\\"\\\""));
    if !body.ends_with('\n') {
        out.push('\n');
    }
    out.push_str("\"\"\"\n");
}

/// Wraps `value` as a Gherkin `"…"` step text token, escaping any `"` it holds as `\"`.
fn quote(value: &str) -> String {
    format!("\"{}\"", value.replace('"', "\\\""))
}

fn provider_token(provider: morphir_evaluator::ProviderId) -> String {
    serde_json::to_value(provider)
        .ok()
        .and_then(|value| value.as_str().map(str::to_owned))
        .unwrap_or_else(|| "rego".to_owned())
}

/// A directory workspace of `.` with no exclusions is the same default `MaterializeExample` uses
/// when a Feature description has no `yaml itest` fence at all, so it is left out of the fence
/// this reader writes.
fn is_default_workspace(workspace: &model::Workspace) -> bool {
    matches!(
        workspace,
        model::Workspace::Directory { path, exclude } if path == "." && exclude.is_empty()
    )
}

fn workspace_yaml(workspace: &model::Workspace) -> String {
    match workspace {
        model::Workspace::Directory { path, exclude } => {
            let exclude = exclude
                .iter()
                .map(|item| yaml_string(item))
                .collect::<Vec<_>>()
                .join(", ");
            format!(
                "{{kind: directory, path: {}, exclude: [{exclude}]}}",
                yaml_string(path)
            )
        }
        model::Workspace::Notebook {} => "{kind: notebook}".to_owned(),
    }
}

/// A string as a JSON-quoted YAML scalar: safe for any content, including embedded quotes,
/// newlines and control characters.
fn yaml_string(value: &str) -> String {
    serde_json::to_string(value).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::commands::itest::steps::ExampleSpec;
    use morphir_gherkin::StepArgument;
    use std::fs;

    const MIGRATE: &str = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../examples/cli/migrate/scenarios.md"
    ));

    fn scenario_step_texts(document: &Document) -> Vec<String> {
        document.feature.as_ref().unwrap().scenarios[0]
            .steps
            .iter()
            .map(|step| format!("{} {}", step.keyword.trim(), step.text))
            .collect()
    }

    #[test]
    fn lowers_cli_migrate_to_the_expected_step_list() {
        let path = Path::new(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../examples/cli/migrate/scenarios.md"
        ));
        let document = read_scenarios_md(path).unwrap();
        let feature = document.feature.as_ref().unwrap();
        assert_eq!(feature.scenarios.len(), 1);
        let scenario = &feature.scenarios[0];
        assert_eq!(
            scenario_step_texts(&document),
            [
                "When I run \"morphir migrate classic-library.json --output output.yaml --target-version v4\" with a 30 second timeout",
                "And I capture \"output.yaml\" as text named \"ir\"",
                "Then the result should satisfy the policy rules \"data.migration_test.writes_output\":",
                "Then the file \"output.yaml\" at \"all\" should match the golden file \"golden/library.v4.yaml\" with exact line endings",
            ]
        );
        let tags: Vec<_> = scenario.tags.iter().map(|tag| tag.name.as_str()).collect();
        assert!(tags.contains(&"section:classic-to-v4"), "{tags:?}");
        assert!(tags.contains(&"steps:3"), "{tags:?}");

        let policy = &scenario.steps[2];
        let Some(StepArgument::DocString(doc_string)) = &policy.argument else {
            panic!("expected a doc string on the policy step");
        };
        assert_eq!(doc_string.content_type.as_deref(), Some("rego"));
        let expected_rego = MIGRATE
            .split("```rego\n")
            .nth(1)
            .unwrap()
            .split("\n```")
            .next()
            .unwrap();
        assert_eq!(doc_string.body.trim_end(), expected_rego);

        // The heading `## Convert Classic JSON to V4 YAML {#classic-to-v4}` is on line 14 of the
        // real file; the scenario's own position stays there.
        assert_eq!(scenario.position.line, 14);
        // Each step's position is its own fence's line: the `yaml morphir:command` fence is on
        // line 16 (the command's `When` and its capture both take that line), the
        // `yaml morphir:assertion` fence is on line 28, and the `yaml morphir:golden` fence is on
        // line 45.
        let lines: Vec<usize> = scenario
            .steps
            .iter()
            .map(|step| step.position.line)
            .collect();
        assert_eq!(lines, [16, 16, 28, 45]);
    }

    #[test]
    fn every_example_scenarios_md_lowers_without_error() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../examples");
        let mut checked = 0;
        for entry in walkdir::WalkDir::new(&root) {
            let entry = entry.unwrap();
            if entry.file_name() != "scenarios.md" {
                continue;
            }
            let text = fs::read_to_string(entry.path()).unwrap();
            let expected = markdown::parse(&text)
                .unwrap_or_else(|error| panic!("{}: {error:#}", entry.path().display()));
            let document = read_scenarios_md(entry.path())
                .unwrap_or_else(|error| panic!("{}: {error}", entry.path().display()));
            let scenarios = document.feature.unwrap().scenarios;
            assert_eq!(
                scenarios.len(),
                expected.len(),
                "{}: scenario count",
                entry.path().display()
            );
            for (scenario, (section_id, notebook)) in scenarios.iter().zip(&expected) {
                let (_, steps) = model::parse(notebook).unwrap_or_else(|error| {
                    panic!(
                        "{}: scenario {section_id}: {error:#}",
                        entry.path().display()
                    )
                });
                let expected_steps: usize = steps.len()
                    + steps
                        .iter()
                        .map(|step| step.assertions.len())
                        .sum::<usize>();
                let tagged_steps: usize = scenario
                    .tags
                    .iter()
                    .find_map(|tag| match tag.namespaced() {
                        Some(("steps", n)) => n.parse::<usize>().ok(),
                        _ => None,
                    })
                    .unwrap_or_else(|| {
                        panic!(
                            "{}: scenario {section_id} has no @steps:<n> tag",
                            entry.path().display()
                        )
                    });
                assert_eq!(
                    tagged_steps,
                    expected_steps,
                    "{}: scenario {section_id}: @steps:<n>",
                    entry.path().display()
                );
            }
            checked += 1;
        }
        assert_eq!(checked, 19, "expected 19 examples/**/scenarios.md files");
    }

    fn write_scenarios_md(text: &str) -> (tempfile::TempDir, std::path::PathBuf) {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("scenarios.md");
        fs::write(&path, text).unwrap();
        (dir, path)
    }

    #[test]
    fn assertion_on_an_earlier_command_is_rejected() {
        let text = "---\n\
version: 1\n\
title: Order\n\
description: Two commands, then an assertion on the first.\n\
tags: [area:order]\n\
provider: rego\n\
---\n\
\n\
## Section\n\
\n\
```yaml morphir:command\n\
id: c1\n\
name: One\n\
timeout_seconds: 5\n\
```\n\
\n\
```sh\n\
morphir one\n\
```\n\
\n\
```yaml morphir:command\n\
id: c2\n\
name: Two\n\
timeout_seconds: 5\n\
```\n\
\n\
```sh\n\
morphir two\n\
```\n\
\n\
```yaml morphir:assertion\n\
id: a1\n\
command: c1\n\
entrypoints: [data.t.ok]\n\
```\n\
\n\
```rego\n\
package t\n\
import rego.v1\n\
ok if { true }\n\
```\n\
\n\
```yaml morphir:assertion\n\
id: a2\n\
command: c2\n\
entrypoints: [data.t.ok2]\n\
```\n\
\n\
```rego\n\
package t\n\
import rego.v1\n\
ok2 if { true }\n\
```\n";
        let (_dir, path) = write_scenarios_md(text);
        let error = read_scenarios_md(&path).unwrap_err();
        // Line 31 of `text` is `a1`'s own `yaml morphir:assertion` fence, not the section
        // heading's line (9) or `c1`'s command fence's line (11).
        assert!(
            error.contains(&format!(
                "{}:31: assertion a1 checks command \"c1\", which is not the last command",
                path.display()
            )),
            "{error}"
        );
    }

    #[test]
    fn itest_fence_carries_provider_workspace_and_overlay_files() {
        let text = "---\n\
version: 1\n\
title: Files\n\
description: Has files.\n\
tags: [area:files]\n\
provider: rego\n\
workspace: {kind: directory, path: ., exclude: [installed]}\n\
---\n\
\n\
## Section\n\
\n\
```yaml morphir:file\n\
id: src\n\
path: src/Example.txt\n\
```\n\
\n\
```text\n\
hello \"world\"\n\
line two\n\
```\n\
\n\
```yaml morphir:command\n\
id: c1\n\
name: Cmd\n\
timeout_seconds: 5\n\
```\n\
\n\
```sh\n\
morphir foo\n\
```\n\
\n\
```yaml morphir:assertion\n\
id: a1\n\
command: c1\n\
entrypoints: [data.t.ok]\n\
```\n\
\n\
```rego\n\
package t\n\
import rego.v1\n\
ok if { true }\n\
```\n";
        let (_dir, path) = write_scenarios_md(text);
        let document = read_scenarios_md(&path).unwrap();
        let fence = document
            .feature
            .as_ref()
            .unwrap()
            .description
            .fences()
            .find(|fence| fence.info.words.iter().any(|word| word == "itest"))
            .unwrap();
        let spec = ExampleSpec::parse(&fence.body).unwrap();
        assert!(matches!(
            &spec.workspace,
            model::Workspace::Directory { path, exclude }
                if path == "." && exclude == &["installed"]
        ));
        assert_eq!(spec.files.len(), 1);
        assert_eq!(spec.files[0].path, "src/Example.txt");
        assert_eq!(spec.files[0].content, "hello \"world\"\nline two\n");
    }

    #[test]
    fn golden_between_selection_escapes_embedded_newlines() {
        let text = "---\n\
version: 1\n\
title: Between\n\
description: Between selection with newline markers.\n\
tags: [area:between]\n\
provider: rego\n\
---\n\
\n\
## Section\n\
\n\
```yaml morphir:command\n\
id: c1\n\
name: Cmd\n\
timeout_seconds: 5\n\
```\n\
\n\
```sh\n\
morphir foo\n\
```\n\
\n\
```yaml morphir:golden\n\
id: g1\n\
command: c1\n\
actual: out.txt\n\
select: {kind: between, start: \"A\\n\", end: \"B\\n\"}\n\
line_endings: lf\n\
```\n\
\n\
```text\n\
middle\n\
```\n";
        let (_dir, path) = write_scenarios_md(text);
        let document = read_scenarios_md(&path).unwrap();
        let scenario = &document.feature.as_ref().unwrap().scenarios[0];
        assert_eq!(
            scenario_step_texts(&document),
            [
                "When I run \"morphir foo\" with a 5 second timeout",
                "Then the file \"out.txt\" at \"between 'A\\n' and 'B\\n'\" should match with LF line endings:",
            ]
        );
        let Some(StepArgument::DocString(doc_string)) = &scenario.steps[1].argument else {
            panic!("expected a doc string on the golden step");
        };
        assert_eq!(doc_string.content_type, None);
        assert_eq!(doc_string.body, "middle\n");
    }

    #[test]
    fn command_argument_with_a_literal_quote_is_reported() {
        let step = Step {
            id: "c1".to_owned(),
            name: "n".to_owned(),
            args: vec!["a\"b".to_owned()],
            timeout_seconds: 5,
            stdout_json: false,
            captures: Vec::new(),
            assertions: Vec::new(),
        };
        let error = command_line(&step).unwrap_err();
        assert!(format!("{error:#}").contains("literal"), "{error:#}");
    }

    #[test]
    fn whitespace_bearing_arguments_round_trip_through_split_command_line() {
        let step = Step {
            id: "c1".to_owned(),
            name: "n".to_owned(),
            args: vec![
                "--message".to_owned(),
                "a b".to_owned(),
                "--flag".to_owned(),
            ],
            timeout_seconds: 5,
            stdout_json: false,
            captures: Vec::new(),
            assertions: Vec::new(),
        };
        let line = command_line(&step).unwrap();
        // `line` is exactly what `morphir_bdd`'s cucumber `{string}` capture would hand to
        // `split_command_line`: the text between the step's own outer quotes, with any `\"`
        // marker left intact (that capture is not itself unescaped).
        let words = morphir_bdd::steps::cli::split_command_line(&line).unwrap();
        assert_eq!(words[0], "morphir");
        assert_eq!(&words[1..], step.args.as_slice());
    }

    #[test]
    fn empty_arguments_round_trip_through_split_command_line() {
        let step = Step {
            id: "c1".to_owned(),
            name: "n".to_owned(),
            args: vec!["--input".to_owned(), String::new()],
            timeout_seconds: 5,
            stdout_json: false,
            captures: Vec::new(),
            assertions: Vec::new(),
        };
        let line = command_line(&step).unwrap();
        let words = morphir_bdd::steps::cli::split_command_line(&line).unwrap();
        assert_eq!(words, ["morphir", "--input", ""]);
    }

    #[test]
    fn marker_escape_round_trips_and_rejects_a_bad_escape() {
        let original = "back\\slash quote' newline\ncarriage\rtab\t.";
        let escaped = escape_marker(original);
        assert!(!escaped.contains('\n') && !escaped.contains('\r') && !escaped.contains('\t'));
        assert_eq!(unescape_marker(&escaped).unwrap(), original);

        assert!(unescape_marker("bad \\x escape").is_err());
        assert!(unescape_marker("trailing backslash \\").is_err());
    }
}
