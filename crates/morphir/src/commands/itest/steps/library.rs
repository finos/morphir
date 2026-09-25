//! The itest step library: capture, stdout-as-JSON, Rego policy and golden steps, built on
//! `morphir_bdd::Suite`.
//!
//! Every step here reads or extends the scenario's most recent command. `When I run {string}`
//! itself lives in `morphir_bdd::steps::cli`, so this module cannot hook into it directly; instead
//! each step compares the scenario's current command number ([`ItestDirs::command`]) against the
//! command number a [`LastCommand`] was last recorded under, and starts a fresh one whenever they
//! differ. That keeps a capture or `stdout is JSON` from an earlier command out of a later one's
//! observation, even though nothing runs between commands to reset them explicitly.
//!
//! The policy step (`Then the result should satisfy the policy rules {string}:`) builds the
//! observation JSON `runner::observation` builds, writes it as an evaluation request, and runs
//! `morphir eval --request <path> --json` through `steps::runner::run_isolated`, in its own
//! `policy-N` harness directory and with the timeout [`ItestDirs::last_timeout`] recorded for the
//! scenario's most recent `When I run`, as legacy itest ran an assertion. The golden steps first
//! require that command to have exited 0, then apply a `Selection` and a `LineEndings`
//! normalization to a file relative to [`ItestDirs::project`], and compare it to an inline doc
//! string or to a golden file that `MaterializeExample` froze in [`FrozenGoldens`] before the
//! first step. Every failure names the command, with its exit code, stdout and stderr.

use std::path::{Path, PathBuf};
use std::sync::atomic::Ordering;
use std::time::Duration;

use cucumber::gherkin::Step;
use cucumber::{then, when};
use morphir_bdd::steps::cli::CliProgram;
use morphir_bdd::steps::output::LastOutput;
use morphir_bdd::world::MorphirWorld;
use morphir_evaluator::{EvaluationRequest, ProviderId};
use serde_json::json;

use crate::commands::itest::golden::{self, LineEndings, Selection};
use crate::commands::itest::model;
use crate::commands::itest::reader;
use crate::commands::itest::runner::{ProcessOutput, check_report, observation};

use super::runner::run_isolated;
use super::{DEFAULT_TIMEOUT, ExampleSpec, FrozenGoldens, ItestDirs};

/// The message every step here panics with when it needs [`LastOutput`] but no command has run
/// yet, in the same style as `morphir_bdd::steps::cli`'s own message.
const NO_COMMAND: &str = "no command has run: add `When I run \"…\"` first";

/// Which captures and whether `stdout is JSON` belong to the scenario's most recent command.
///
/// Keyed by `seq`, the command number [`ItestDirs::command`] held when this was last written: a
/// step that reads or extends it first compares `seq` against the scenario's *current* command
/// number, and starts over empty whenever they differ. That is how a capture or `stdout is JSON`
/// step, which cannot hook into `When I run {string}` directly, still ends up describing only the
/// last command's output.
#[derive(Debug, Clone, Default)]
struct LastCommand {
    /// The command number ([`ItestDirs::command`]) this capture set and `stdout is JSON` flag
    /// belong to.
    seq: u64,
    /// The captures recorded for the command numbered `seq`, in the order they were requested.
    captures: Vec<model::Capture>,
    /// Whether `And stdout is JSON` was requested for the command numbered `seq`.
    stdout_json: bool,
}

/// The scenario's [`ItestDirs`], panicking with a message naming the missing processor if
/// `MaterializeExample` has not run yet.
fn dirs(world: &MorphirWorld) -> &ItestDirs {
    world.context.get::<ItestDirs>().expect(
        "no itest directories: the `MaterializeExample` processor must prepare the scenario \
         before this step",
    )
}

/// The scenario's current command number: how many `When I run` commands have run so far
/// ([`ItestDirs::command`], not [`ItestDirs::step`] — the policy step's own internal `morphir eval`
/// call must not look like a new command). Every step in this module keys its own state off this
/// number instead of the identity of a specific [`LastOutput`], since a fresh command overwrites
/// [`LastOutput`] in place rather than replacing it with a distinguishable value.
fn current_seq(world: &MorphirWorld) -> u64 {
    dirs(world).command.load(Ordering::SeqCst) as u64
}

/// The scenario's [`LastCommand`], reset to empty first if it was last written for a different
/// command than `seq`. Every capture step, the `stdout is JSON` step, and the assertion steps call
/// this before reading or extending it, so a capture from an earlier command never leaks into a
/// later one's observation.
fn last_command(world: &mut MorphirWorld, seq: u64) -> &mut LastCommand {
    let current = world
        .context
        .get::<LastCommand>()
        .map(|command| command.seq);
    if current != Some(seq) {
        world.context.insert(LastCommand {
            seq,
            captures: Vec::new(),
            stdout_json: false,
        });
    }
    world
        .context
        .get_mut::<LastCommand>()
        .expect("just inserted or already present")
}

/// The scenario's [`LastOutput`], panicking with [`NO_COMMAND`] if no command has run yet.
fn last_output(world: &MorphirWorld) -> &LastOutput {
    world.context.get::<LastOutput>().expect(NO_COMMAND)
}

/// The scenario's most recent command, laid out as legacy itest printed it:
/// `command <n>: morphir [<args>]`, then `exit:`, `stdout:` and `stderr:` sections.
fn command_diagnostics(world: &MorphirWorld) -> String {
    let dirs = dirs(world);
    let number = dirs.command.load(Ordering::SeqCst);
    let line = command_line(dirs);
    let output = last_output(world);
    format!(
        "command {number}: {line}\nexit: {:?}\nstdout:\n{}\nstderr:\n{}",
        output.status, output.stdout, output.stderr
    )
}

/// The scenario's most recent command line ([`ItestDirs::last_command_line`]).
fn command_line(dirs: &ItestDirs) -> String {
    dirs.last_command_line
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .clone()
        .unwrap_or_else(|| "(no command)".to_owned())
}

/// The evaluator provider an example's `yaml itest` fence named, or `rego` (the default
/// [`ExampleSpec::provider`]) if the example has no such fence.
fn provider(world: &MorphirWorld) -> ProviderId {
    world
        .context
        .get::<ExampleSpec>()
        .map_or(ProviderId::Rego, |spec| spec.provider)
}

/// Reads a step's doc string, panicking if the step has none.
fn doc_string(step: &Step) -> &str {
    step.docstring
        .as_deref()
        .expect("this step takes a doc string")
}

/// `And I capture {string} as {word} named {string}` pushes a [`model::Capture`] onto the
/// scenario's current [`LastCommand`].
#[when(expr = "I capture {string} as {word} named {string}")]
fn i_capture(world: &mut MorphirWorld, path: String, format: String, name: String) {
    let format = match format.as_str() {
        "json" => model::CaptureFormat::Json,
        "text" => model::CaptureFormat::Text,
        "exists" => model::CaptureFormat::Exists,
        other => panic!("unknown capture format {other:?}: expected `json`, `text` or `exists`"),
    };
    let seq = current_seq(world);
    last_command(world, seq)
        .captures
        .push(model::Capture { name, path, format });
}

/// `And stdout is JSON` sets `stdout_json` on the scenario's current [`LastCommand`].
#[when("stdout is JSON")]
fn stdout_is_json(world: &mut MorphirWorld) {
    let seq = current_seq(world);
    last_command(world, seq).stdout_json = true;
}

/// The timeout the policy step's own `morphir eval` call uses: the scenario's most recently
/// recorded [`ItestDirs::last_timeout`] (the timeout its triggering `When I run` named), or
/// [`DEFAULT_TIMEOUT`] if it named none. Legacy itest gave an assertion its command's timeout too.
fn eval_timeout(world: &MorphirWorld) -> Duration {
    dirs(world)
        .last_timeout
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .unwrap_or(DEFAULT_TIMEOUT)
}

/// Runs `morphir eval --request <path> --json` through `steps::runner::run_isolated`, the same
/// per-scenario isolation `When I run {string}` uses for every other command, but in `cwd` (the
/// policy check's own harness directory, not the project) and with `timeout` (see
/// [`eval_timeout`]), the working directory and timeout legacy itest gave an assertion.
async fn run_eval(
    world: &MorphirWorld,
    cwd: &Path,
    request_path: &Path,
    timeout: Duration,
) -> LastOutput {
    let program = world.context.get::<CliProgram>().cloned().expect(
        "no CLI program: the suite must call `Suite::cli(path)` before the policy step can run \
         `morphir eval`",
    );
    let args = [
        "eval".to_owned(),
        "--request".to_owned(),
        request_path.display().to_string(),
        "--json".to_owned(),
    ];
    run_isolated(&program, &args, dirs(world), cwd, timeout)
        .await
        .unwrap_or_else(|error| panic!("{error}"))
}

/// `Then the result should satisfy the policy rules {string}:` checks the scenario's current
/// command against a Rego policy, the doc string.
///
/// It builds the observation with `runner::observation` (from the current [`LastOutput`],
/// [`LastCommand::captures`] and [`LastCommand::stdout_json`]), writes it as an evaluation
/// request, runs it through [`run_eval`], and checks the report with `runner::check_report`
/// against `entrypoints` (a comma-and-space-separated list, the reverse of how the reader joined
/// them). A failure names the command ([`command_diagnostics`]) and the rules.
#[then(expr = "the result should satisfy the policy rules {string}:")]
async fn satisfies_the_policy_rules(world: &mut MorphirWorld, entrypoints: String, step: &Step) {
    let entrypoints: Vec<String> = entrypoints.split(", ").map(str::to_owned).collect();
    let source = doc_string(step).to_owned();
    let seq = current_seq(world);
    let command = last_command(world, seq).clone();
    let output = last_output(world).clone();
    let project = dirs(world).project.clone();
    let root = dirs(world).root.clone();
    let provider = provider(world);
    let timeout = eval_timeout(world);

    let step_model = model::Step {
        id: String::new(),
        args: Vec::new(),
        timeout_seconds: 0,
        stdout_json: command.stdout_json,
        captures: command.captures,
        assertions: Vec::new(),
    };
    let process_output = ProcessOutput {
        code: output.status,
        stdout: output.stdout,
        stderr: output.stderr,
    };
    let diagnostics = command_diagnostics(world);
    let rules = entrypoints.join(", ");
    let input = observation(&step_model, &process_output, &project)
        .unwrap_or_else(|error| panic!("{diagnostics}\npolicy rules {rules}: {error:#}"));

    let request_value = json!({
        "version": 1,
        "provider": provider,
        "program": {
            "kind": "source",
            "language": "rego",
            "modules": [{"path": "policy.rego", "source": source}],
        },
        "entrypoints": entrypoints,
        "input": input,
        "timeout_ms": u64::try_from(timeout.as_millis()).unwrap_or(u64::MAX),
    });
    let request: EvaluationRequest = serde_json::from_value(request_value)
        .unwrap_or_else(|error| panic!("invalid evaluation request: {error:#}"));

    // Named from a fresh `ItestDirs::step` id, not `seq` (the command number): a command can
    // carry more than one policy check, and `seq` alone would collide between them.
    let harness_id = dirs(world).step.fetch_add(1, Ordering::SeqCst) + 1;
    let harness = root.join(format!("policy-{harness_id}"));
    std::fs::create_dir_all(&harness).unwrap_or_else(|error| {
        panic!(
            "create policy harness directory {}: {error}",
            harness.display()
        )
    });
    let request_path = harness.join("request.json");
    std::fs::write(
        &request_path,
        serde_json::to_vec_pretty(&request).expect("serialize evaluation request"),
    )
    .unwrap_or_else(|error| {
        panic!(
            "write evaluation request {}: {error}",
            request_path.display()
        )
    });

    let evaluated = run_eval(world, &harness, &request_path, timeout).await;
    let evaluator = format!(
        "{diagnostics}\npolicy rules {rules}\nevaluator stdout:\n{}\nevaluator stderr:\n{}",
        evaluated.stdout, evaluated.stderr
    );
    if evaluated.status != Some(0) {
        panic!("{evaluator}\nevaluator failed: {:?}", evaluated.status);
    }
    check_report(&evaluated.stdout, provider, &entrypoints)
        .unwrap_or_else(|error| panic!("{evaluator}\n{error:#}"));
}

/// Parses a golden step's `<select>` text: `all`, `lines <start> to <end>`, or `between '<start>'
/// and '<end>'`. A `between` marker is escaped the way `reader::escape_marker` writes it (so the
/// whole step stays on one physical line); this reverses that with `reader::unescape_marker`.
pub fn parse_selection(text: &str) -> Result<Selection, String> {
    if text == "all" {
        return Ok(Selection::All);
    }
    if let Some(rest) = text.strip_prefix("lines ") {
        let (start, end) = rest.split_once(" to ").ok_or_else(|| {
            format!("invalid selection {text:?}: expected `lines <start> to <end>`")
        })?;
        let start: usize = start
            .trim()
            .parse()
            .map_err(|_| format!("invalid selection {text:?}: start must be a whole number"))?;
        let end: usize = end
            .trim()
            .parse()
            .map_err(|_| format!("invalid selection {text:?}: end must be a whole number"))?;
        let selection = Selection::Lines { start, end };
        selection
            .validate()
            .map_err(|error| format!("invalid selection {text:?}: {error:#}"))?;
        return Ok(selection);
    }
    if let Some(rest) = text.strip_prefix("between '") {
        let (start, rest) = take_quoted_marker(text, rest)?;
        let rest = rest.strip_prefix(" and '").ok_or_else(|| {
            format!("invalid selection {text:?}: expected `between '<start>' and '<end>'`")
        })?;
        let (end, rest) = take_quoted_marker(text, rest)?;
        if !rest.is_empty() {
            return Err(format!(
                "invalid selection {text:?}: unexpected trailing text {rest:?}"
            ));
        }
        let start = reader::unescape_marker(start)
            .map_err(|error| format!("invalid selection {text:?}: start marker: {error}"))?;
        let end = reader::unescape_marker(end)
            .map_err(|error| format!("invalid selection {text:?}: end marker: {error}"))?;
        let selection = Selection::Between { start, end };
        selection
            .validate()
            .map_err(|error| format!("invalid selection {text:?}: {error:#}"))?;
        return Ok(selection);
    }
    Err(format!(
        "invalid selection {text:?}: expected `all`, `lines <start> to <end>` or `between \
         '<start>' and '<end>'`"
    ))
}

/// Splits the escaped marker text at the start of `rest` from its closing, unescaped `'`, treating
/// a `\` as escaping whatever character follows it (as `reader::escape_marker` writes it, and as
/// `reader::unescape_marker` later reads it back). Returns the marker's own raw, still-escaped text
/// and whatever follows the closing quote. `full` is only for the error message.
fn take_quoted_marker<'a>(full: &str, rest: &'a str) -> Result<(&'a str, &'a str), String> {
    let mut chars = rest.char_indices();
    while let Some((index, ch)) = chars.next() {
        match ch {
            '\\' => {
                chars.next();
            }
            '\'' => return Ok((&rest[..index], &rest[index + 1..])),
            _ => {}
        }
    }
    Err(format!("invalid selection {full:?}: unterminated marker"))
}

/// `exact` or `LF`, exactly as `reader::format_select` writes `LineEndings`.
fn parse_line_endings(text: &str) -> LineEndings {
    match text {
        "exact" => LineEndings::Exact,
        "LF" => LineEndings::Lf,
        other => panic!("unknown line endings {other:?}: expected `exact` or `LF`"),
    }
}

/// `actual`, resolved against [`ItestDirs::project`] and checked as a portable relative path.
fn actual_path(world: &MorphirWorld, actual: &str) -> PathBuf {
    model::relative_path(actual)
        .unwrap_or_else(|error| panic!("invalid golden actual path {actual:?}: {error:#}"));
    dirs(world).project.join(actual)
}

/// Reads `path` (the file named by `relative`, for the panic message), panicking if it is missing,
/// not a regular file, or not UTF-8, with the text `runner::read_text` uses.
fn read_golden(path: &Path, relative: &str) -> String {
    if !path.is_file() {
        panic!("golden file {relative:?} is missing or is not a regular file");
    }
    std::fs::read_to_string(path)
        .unwrap_or_else(|error| panic!("read UTF-8 golden file {relative:?}: {error}"))
}

/// Panics unless the scenario's most recent command exited 0: a golden check never passes over a
/// failed command, as legacy itest's golden policy (`input.exitCode == 0`) did not. `label` names
/// the expectation: its golden file, or `inline text`.
fn require_success(world: &MorphirWorld, label: &str) {
    let status = last_output(world).status;
    if status != Some(0) {
        let dirs = dirs(world);
        panic!(
            "{}\ngolden {label:?}: command {} ({}) exited with {status:?}, not 0",
            command_diagnostics(world),
            dirs.command.load(Ordering::SeqCst),
            command_line(dirs)
        );
    }
}

/// Selects, normalizes and compares `actual`'s text (from [`ItestDirs::project`]) against
/// `expected`, after [`require_success`]. Panics with `golden::diff` on a mismatch:
/// `expected_label` is the golden file's own path, or `"inline text"`.
fn check_golden(
    world: &MorphirWorld,
    actual: &str,
    select: &str,
    line_endings: &str,
    expected: &str,
    expected_label: &str,
) {
    require_success(world, expected_label);
    let diagnostics = || command_diagnostics(world);
    let selection = parse_selection(select).unwrap_or_else(|error| panic!("{error}"));
    let line_endings = parse_line_endings(line_endings);
    let path = actual_path(world, actual);
    let actual_text = read_golden(&path, actual);
    let selected = selection.select(&actual_text).unwrap_or_else(|error| {
        panic!(
            "{}\ngolden file {actual:?}, selection {selection:?}: {error:#}",
            diagnostics()
        )
    });
    let actual_normalized = line_endings.normalize(selected);
    let expected_normalized = line_endings.normalize(expected);
    if actual_normalized != expected_normalized {
        panic!(
            "{}\ngolden mismatch: {actual:?}, selection {selection:?}, expected {expected_label:?}\n{}",
            diagnostics(),
            golden::diff(&expected_normalized, &actual_normalized)
        );
    }
}

/// The parts of a golden-file step's text:
/// `the file "<actual>" at "<select>" should match the golden file "<golden_file>" with <word>
/// line endings`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct GoldenFileStep {
    /// The file the command wrote, relative to the project.
    pub actual: String,
    /// The selection text, for [`parse_selection`].
    pub select: String,
    /// The expected file, relative to the example's directory.
    pub golden_file: String,
    /// `exact` or `LF`.
    pub line_endings: String,
}

/// Parses a golden-file step's text, or `None` when `text` is not one. This is the one reader of
/// that step's grammar: the step itself and `MaterializeExample` (which freezes the expected
/// files before the first step) both use it. A quoted value unescapes `\"` to `"` and keeps every
/// other `\` pair as written, as a cucumber `{string}` parameter does.
pub(crate) fn golden_file_step(text: &str) -> Option<GoldenFileStep> {
    let rest = text.strip_prefix("the file ")?;
    let (actual, rest) = take_quoted(rest)?;
    let rest = rest.strip_prefix(" at ")?;
    let (select, rest) = take_quoted(rest)?;
    let rest = rest.strip_prefix(" should match the golden file ")?;
    let (golden_file, rest) = take_quoted(rest)?;
    let line_endings = rest.strip_prefix(" with ")?.strip_suffix(" line endings")?;
    if line_endings.is_empty() || line_endings.contains(char::is_whitespace) {
        return None;
    }
    Some(GoldenFileStep {
        actual,
        select,
        golden_file,
        line_endings: line_endings.to_owned(),
    })
}

/// Splits a `"…"` value from the start of `text`: the value with `\"` unescaped, and what follows
/// its closing quote.
fn take_quoted(text: &str) -> Option<(String, &str)> {
    let body = text.strip_prefix('"')?;
    let mut value = String::new();
    let mut chars = body.char_indices();
    while let Some((index, ch)) = chars.next() {
        match ch {
            '\\' => match chars.next() {
                Some((_, '"')) => value.push('"'),
                Some((_, other)) => {
                    value.push('\\');
                    value.push(other);
                }
                None => return None,
            },
            '"' => return Some((value, &body[index + 1..])),
            other => value.push(other),
        }
    }
    None
}

/// `Then the file {string} at {string} should match the golden file {string} with {word} line
/// endings` compares `actual` against a golden file relative to the example's directory, as
/// [`FrozenGoldens`] holds it from before the first step. [`golden_file_step`] reads the text.
#[then(regex = r"^the file .* should match the golden file .* line endings$")]
fn matches_the_golden_file(world: &mut MorphirWorld, step: &Step) {
    let parsed = golden_file_step(&step.value)
        .unwrap_or_else(|| panic!("not a golden-file step: {:?}", step.value));
    let expected = world
        .context
        .get::<FrozenGoldens>()
        .and_then(|frozen| frozen.0.get(&parsed.golden_file))
        .cloned()
        .unwrap_or_else(|| {
            panic!(
                "golden {:?} was not read before the first step: the `MaterializeExample` \
                 processor freezes each golden file the scenario's steps name",
                parsed.golden_file
            )
        });
    check_golden(
        world,
        &parsed.actual,
        &parsed.select,
        &parsed.line_endings,
        &expected,
        &parsed.golden_file,
    );
}

/// `Then the file {string} at {string} should match with {word} line endings:` compares `actual`
/// against the step's doc string.
#[then(expr = "the file {string} at {string} should match with {word} line endings:")]
fn matches_the_doc_string(
    world: &mut MorphirWorld,
    actual: String,
    select: String,
    line_endings: String,
    step: &Step,
) {
    let expected = doc_string(step).to_owned();
    check_golden(
        world,
        &actual,
        &select,
        &line_endings,
        &expected,
        "inline text",
    );
}

/// Keeps this module's steps in a binary that links it: see
/// `morphir_bdd::steps::link`, whose own doc explains why referencing one item per module is
/// enough for the linker to keep a module's step registrations.
pub fn link() {
    std::hint::black_box(parse_selection as fn(&str) -> Result<Selection, String>);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn golden_file_step_reads_the_text_the_reader_writes() {
        assert_eq!(
            golden_file_step(
                r#"the file "out/a \"b\".txt" at "between 'x\n' and 'y'" should match the golden file "golden/a.txt" with LF line endings"#
            ),
            Some(GoldenFileStep {
                actual: r#"out/a "b".txt"#.to_owned(),
                select: r"between 'x\n' and 'y'".to_owned(),
                golden_file: "golden/a.txt".to_owned(),
                line_endings: "LF".to_owned(),
            })
        );
        for text in [
            r#"the file "a" at "all" should match with exact line endings:"#,
            r#"the file "a" at "all" should match the golden file "b" with two words line endings"#,
            r#"the file "a" at "all" should match the golden file "b"#,
            r#"I run "morphir --version""#,
        ] {
            assert_eq!(golden_file_step(text), None, "{text}");
        }
    }

    #[test]
    fn parse_selection_accepts_all() {
        assert_eq!(parse_selection("all").unwrap(), Selection::All);
    }

    #[test]
    fn parse_selection_accepts_lines() {
        assert_eq!(
            parse_selection("lines 2 to 5").unwrap(),
            Selection::Lines { start: 2, end: 5 }
        );
    }

    #[test]
    fn parse_selection_accepts_between_with_escaped_markers() {
        assert_eq!(
            parse_selection(r"between 'A\n' and 'B\n'").unwrap(),
            Selection::Between {
                start: "A\n".to_owned(),
                end: "B\n".to_owned(),
            }
        );
        // Round trips through the reader's own escaping, including a marker that itself contains
        // a backslash, a quote and a tab.
        let original = Selection::Between {
            start: "back\\slash and quote' \t".to_owned(),
            end: "end".to_owned(),
        };
        let (start, end) = match &original {
            Selection::Between { start, end } => (start, end),
            _ => unreachable!(),
        };
        let text = format!(
            "between '{}' and '{}'",
            reader::escape_marker(start),
            reader::escape_marker(end)
        );
        assert_eq!(parse_selection(&text).unwrap(), original);
    }

    #[test]
    fn parse_selection_rejects_a_reversed_line_range() {
        assert!(parse_selection("lines 5 to 2").is_err());
    }

    #[test]
    fn parse_selection_rejects_an_incomplete_between() {
        assert!(parse_selection("between 'a'").is_err());
    }

    #[test]
    fn parse_selection_rejects_unrecognized_text() {
        assert!(parse_selection("").is_err());
        assert!(parse_selection("everything").is_err());
    }

    #[test]
    fn last_command_starts_over_when_the_command_number_changes() {
        let mut world = MorphirWorld::new();

        last_command(&mut world, 1).captures.push(model::Capture {
            name: "a".to_owned(),
            path: "a.txt".to_owned(),
            format: model::CaptureFormat::Text,
        });
        last_command(&mut world, 1).stdout_json = true;
        assert_eq!(last_command(&mut world, 1).captures.len(), 1);
        assert!(last_command(&mut world, 1).stdout_json);

        // A later command's steps read `last_command` for a new `seq`: the earlier command's
        // captures and `stdout is JSON` must not leak into it.
        let second = last_command(&mut world, 2);
        assert!(second.captures.is_empty());
        assert!(!second.stdout_json);
    }

    #[test]
    fn last_command_reread_for_the_same_seq_keeps_what_was_recorded() {
        let mut world = MorphirWorld::new();

        last_command(&mut world, 7).captures.push(model::Capture {
            name: "a".to_owned(),
            path: "a.txt".to_owned(),
            format: model::CaptureFormat::Json,
        });
        // Reading `last_command` again for the same `seq` (as the policy or golden step does right
        // after a capture step) must not reset it.
        assert_eq!(last_command(&mut world, 7).captures.len(), 1);
    }

    #[test]
    fn parse_line_endings_accepts_the_two_reader_tokens() {
        assert_eq!(parse_line_endings("exact"), LineEndings::Exact);
        assert_eq!(parse_line_endings("LF"), LineEndings::Lf);
    }

    #[test]
    #[should_panic(expected = "unknown line endings")]
    fn parse_line_endings_rejects_anything_else() {
        parse_line_endings("lf");
    }

    #[test]
    fn eval_timeout_uses_the_recorded_timeout_or_falls_back_to_default() {
        let mut world = MorphirWorld::new();
        let dirs = ItestDirs::new(std::env::temp_dir());
        world.context.insert(dirs.clone());

        assert_eq!(eval_timeout(&world), DEFAULT_TIMEOUT);

        *dirs.last_timeout.lock().unwrap() = Some(Duration::from_secs(7));
        // `ItestDirs` shares `last_timeout` through an `Arc`, so mutating this clone is visible
        // through the one already inserted into `world`, the same way `ItestRunner::run` records a
        // real `When I run`'s timeout for a later policy step to read back.
        assert_eq!(eval_timeout(&world), Duration::from_secs(7));
    }

    #[test]
    fn current_seq_reads_command_not_the_shared_step_counter() {
        let mut world = MorphirWorld::new();
        let dirs = ItestDirs::new(std::env::temp_dir());
        world.context.insert(dirs.clone());

        // `step` also advances for the policy step's own internal `morphir eval` calls (see
        // `run_isolated`); `current_seq` must not follow it, or a second policy check on one
        // command would see its captures reset partway through.
        dirs.step.fetch_add(3, Ordering::SeqCst);
        assert_eq!(current_seq(&world), 0);

        dirs.command.fetch_add(1, Ordering::SeqCst);
        assert_eq!(current_seq(&world), 1);
    }
}
