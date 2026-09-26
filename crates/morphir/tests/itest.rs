use serde_json::{Value, json};
use std::{fs, process::Command};

fn code(id: &str, source: &str, profile: Value) -> Value {
    json!({"id":id,"cell_type":"code","source":source,"metadata":{"morphir":profile},"outputs":[],"execution_count":null})
}

fn scenario() -> Value {
    json!({"nbformat":4,"nbformat_minor":5,"metadata":{"morphir":{"version":1,"itest":{
        "title":"Invalid CLI option","description":"The actual CLI rejects an unknown option with exit code 2.",
        "tags":["area:cli","kind:negative"],"provider":"rego"
    }}},"cells":[
        {"id":"purpose","cell_type":"markdown","metadata":{},"source":"# Argument validation"},
        code("command", "morphir --not-a-real-option", json!({"itest":{"kind":"command","name":"Reject unknown option","timeout_seconds":10,"captures":[]}})),
        code("assert", "package cli_test\nimport rego.v1\ntest_exit if { input.exitCode == 2 }\n",json!({"itest":{"kind":"assertion","command":"command","entrypoints":["data.cli_test.test_exit"]}}))
    ]})
}

fn write_scenario(root: &std::path::Path, notebook: &Value) {
    fs::create_dir_all(root).unwrap();
    fs::write(
        root.join("scenario.ipynb"),
        serde_json::to_vec_pretty(notebook).unwrap(),
    )
    .unwrap();
}

fn run(root: &std::path::Path, args: &[&str]) -> std::process::Output {
    let home = tempfile::tempdir().unwrap();
    // Each run writes its own suite reports, so parallel tests never share one report file.
    let reports = tempfile::tempdir().unwrap();
    Command::new(env!("CARGO_BIN_EXE_morphir"))
        .arg("itest")
        .arg(root)
        .args(args)
        .env("MORPHIR_HOME", home.path())
        .env("MORPHIR_LOG_FILE", "false")
        .env("MORPHIR_BDD_OUT", reports.path())
        .output()
        .unwrap()
}

const MARKDOWN: &str = r#"---
version: 1
title: Compile disk Elm from Markdown
description: Compile disk inputs, preserve inline file contents and capture v3 IR.
tags: [language:elm, suite:offline]
provider: rego
---

# Compile an ordinary project

## Compile types

This unmarked command is documentation and must never execute:

```sh
morphir --not-a-real-option
```

```yaml morphir:file
id: extra
path: extra.txt
```

```text
inline addition
```

```yaml morphir:command
id: compile
name: Compile on-disk source
timeout_seconds: 30
stdout_json: true
captures:
  - {name: ir, path: installed/morphir-ir.json, format: json}
  - {name: extra, path: extra.txt, format: text}
  - {name: scenario, path: scenarios.md, format: exists}
```

This command compiles the disk file. Prose between paired fences is allowed.

```sh
morphir compile --input Example.elm --extension morphir-elm-native --package-name examples/markdown --output installed --json
```

```yaml morphir:assertion
id: compiled
command: compile
entrypoints: [data.markdown_test.compiles]
```

```rego
package markdown_test
import rego.v1

compiles if {
    input.exitCode == 0
    input.stdoutJson.success == true
    input.artifacts.ir.value.formatVersion == 3
    input.artifacts.extra.value == "inline addition\n"
    input.artifacts.scenario.kind == "missing"
}
```
"#;

#[test]
#[cfg_attr(
    not(feature = "rego"),
    ignore = "requires the rego feature: this scenario asserts through Rego, and the evaluator is compiled out by --no-default-features"
)]
fn itest_markdown_drives_cli_with_disk_and_inline_files() {
    let temp = tempfile::tempdir().unwrap();
    let example = temp.path().join("elm/markdown");
    fs::create_dir_all(&example).unwrap();
    let source = "module Example exposing (Name)\n\ntype alias Name = String\n";
    fs::write(example.join("Example.elm"), source).unwrap();
    fs::write(example.join("scenarios.md"), MARKDOWN).unwrap();
    for args in [
        vec!["--list"],
        vec!["--filter", "elm", "--tag", "suite:offline"],
    ] {
        let output = run(temp.path(), &args);
        assert!(
            output.status.success(),
            "stdout={} stderr={}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(String::from_utf8_lossy(&output.stdout).contains("elm/markdown#compile-types"));
    }
    assert_eq!(
        fs::read_to_string(example.join("Example.elm")).unwrap(),
        source
    );
    assert!(!example.join("extra.txt").exists());
    assert!(!example.join("installed").exists());
    let wrong = MARKDOWN.replace("input.exitCode == 0", "input.exitCode == 99");
    fs::write(example.join("scenarios.md"), wrong).unwrap();
    let output = run(temp.path(), &["--filter", "elm"]);
    assert!(!output.status.success());
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("FAIL elm/markdown#compile-types\n")
            && stderr.contains("morphir [\"compile\", \"--input\", \"Example.elm\"")
            && stderr.contains("data.markdown_test.compiles"),
        "{stderr}"
    );
}

#[test]
#[cfg_attr(
    not(feature = "rego"),
    ignore = "requires the rego feature: this scenario asserts through Rego, and the evaluator is compiled out by --no-default-features"
)]
fn itest_markdown_headings_are_independent_selectable_scenarios() {
    let temp = tempfile::tempdir().unwrap();
    // IDs and file paths may be reused in a different scenario.
    let first = MARKDOWN.replace("## Compile types", "## First run {#first}");
    let second = MARKDOWN
        .split("## Compile types")
        .nth(1)
        .unwrap()
        .replace("inline addition", "second scenario");
    fs::write(
        temp.path().join("scenarios.md"),
        format!("{first}\n## Second run\n{second}"),
    )
    .unwrap();
    fs::write(
        temp.path().join("Example.elm"),
        "module Example exposing (Name)\ntype alias Name = String\n",
    )
    .unwrap();
    let output = run(temp.path(), &[]);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("2 passed; 0 failed"), "{stdout}");
    for id in [".#first", ".#second-run"] {
        let output = run(temp.path(), &["--filter", id]);
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(
            String::from_utf8_lossy(&output.stdout).contains("1 passed; 0 failed; 1 not selected")
        );
    }
    assert!(!temp.path().join("extra.txt").exists());
}

#[test]
fn itest_rejects_two_scenario_documents_in_one_directory() {
    let temp = tempfile::tempdir().unwrap();
    write_scenario(temp.path(), &scenario());
    fs::write(temp.path().join("scenarios.md"), MARKDOWN).unwrap();
    let output = run(temp.path(), &["--list"]);
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("multiple scenario documents"));
}

/// A `scenarios.md` document with one section whose Rego policy rejects an unknown CLI option
/// with exit code 2, tagged `area:cli` and `kind:negative` as the removed notebook fixture was.
const REJECT_UNKNOWN_OPTION: &str = "---\nversion: 1\ntitle: Invalid CLI option\ndescription: The actual CLI rejects an unknown option with exit code 2.\ntags: [area:cli, kind:negative]\nprovider: rego\n---\n## Reject\n```yaml morphir:command\nid: command\nname: Reject unknown option\ntimeout_seconds: 10\n```\n```sh\nmorphir --not-a-real-option\n```\n```yaml morphir:assertion\nid: assert\ncommand: command\nentrypoints: [data.cli_test.test_exit]\n```\n```rego\npackage cli_test\nimport rego.v1\ntest_exit if { input.exitCode == 2 }\n```\n";

#[test]
#[cfg_attr(
    not(feature = "rego"),
    ignore = "requires the rego feature: this scenario asserts through Rego, and the evaluator is compiled out by --no-default-features"
)]
fn itest_lists_filters_and_drives_real_cli_commands() {
    let temp = tempfile::tempdir().unwrap();
    let example = temp.path().join("cli/errors");
    fs::create_dir_all(&example).unwrap();
    fs::write(example.join("scenarios.md"), REJECT_UNKNOWN_OPTION).unwrap();
    for args in [
        vec!["--list", "--tag", "area:cli"],
        vec!["--filter", "cli", "--tag", "kind:negative"],
    ] {
        let output = run(temp.path(), &args);
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(String::from_utf8_lossy(&output.stdout).contains("cli/errors"));
    }
    // A tag no scenario has is an empty selection, which fails the run.
    let output = run(temp.path(), &["--tag", "missing"]);
    assert!(
        !output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stdout)
    );
    assert!(
        String::from_utf8_lossy(&output.stderr).contains("no scenarios match tags [\"missing\"]"),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(!example.join(".morphir").exists());
}

#[test]
#[cfg_attr(
    not(feature = "rego"),
    ignore = "requires the rego feature: this scenario asserts through Rego, and the evaluator is compiled out by --no-default-features"
)]
fn itest_distinguishes_search_root_from_a_directory_named_root() {
    let temp = tempfile::tempdir().unwrap();
    fs::write(temp.path().join("scenarios.md"), VERSION_MD).unwrap();
    fs::create_dir_all(temp.path().join("root")).unwrap();
    fs::write(temp.path().join("root/scenarios.md"), VERSION_MD).unwrap();
    for (filter, other) in [("root", "."), (".", "root")] {
        let output = run(temp.path(), &["--filter", filter]);
        let stdout = String::from_utf8_lossy(&output.stdout);
        assert!(
            output.status.success(),
            "stdout={stdout} stderr={}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(
            stdout.contains(&format!("PASS {filter}#first:")),
            "{stdout}"
        );
        assert!(
            stdout.contains(&format!("PASS {filter}#second:")),
            "{stdout}"
        );
        assert!(!stdout.contains(&format!("PASS {other}#")), "{stdout}");
        assert!(
            stdout.contains("2 passed; 0 failed; 2 not selected"),
            "{stdout}"
        );
    }
    let output = run(temp.path(), &["--list"]);
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(output.status.success());
    assert!(
        stdout.lines().any(|line| line.starts_with(".#first:")),
        "{stdout}"
    );
    assert!(
        stdout.lines().any(|line| line.starts_with("root#first:")),
        "{stdout}"
    );
}

#[test]
#[cfg_attr(
    not(feature = "rego"),
    ignore = "requires the rego feature: this scenario asserts through Rego, and the evaluator is compiled out by --no-default-features"
)]
fn itest_runs_the_checked_in_offline_examples_and_failure_fixture() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let temp = tempfile::tempdir().unwrap();
    for suite in [
        root.join("examples"),
        root.join("crates/morphir/tests/fixtures/itest"),
    ] {
        let output = Command::new(env!("CARGO_BIN_EXE_morphir"))
            .arg("itest")
            .arg(&suite)
            .args(["--tag", "suite:offline"])
            .env("MORPHIR_HOME", temp.path().join("home"))
            .env("MORPHIR_OUT_DIR", temp.path().join("wrong-out"))
            .env("MORPHIR_BDD_OUT", temp.path().join("reports"))
            .env("MORPHIR_LOG_FILE", "false")
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "stdout={} stderr={}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        let expected = if suite == root.join("examples") {
            18
        } else {
            1
        };
        assert!(
            String::from_utf8_lossy(&output.stdout)
                .contains(&format!("{expected} passed; 0 failed")),
            "expected {expected} passing scenarios, got {}",
            String::from_utf8_lossy(&output.stdout)
        );
        assert!(!temp.path().join("wrong-out").exists());
    }
}

#[test]
fn itest_fails_on_wrong_undefined_or_invalid_assertions_and_reports_case() {
    for policy in [
        "package cli_test\nimport rego.v1\ntest_exit if { input.exitCode == 99 }",
        "package cli_test\nimport rego.v1\ntest_exit if { input.missing == null }",
        "package cli_test\ntest_exit := 42",
        "package cli_test\ntest_exit if {",
    ] {
        let temp = tempfile::tempdir().unwrap();
        fs::write(
            temp.path().join("scenarios.md"),
            format!(
                "---\nversion: 1\ntitle: Invalid CLI option\ndescription: The actual CLI rejects an unknown option with exit code 2.\ntags: [area:cli, kind:negative]\nprovider: rego\n---\n## Reject\n```yaml morphir:command\nid: command\nname: Reject unknown option\ntimeout_seconds: 10\n```\n```sh\nmorphir --not-a-real-option\n```\n```yaml morphir:assertion\nid: assert\ncommand: command\nentrypoints: [data.cli_test.test_exit]\n```\n```rego\n{policy}\n```\n"
            ),
        )
        .unwrap();
        let output = run(temp.path(), &[]);
        let (stdout, stderr) = text(&output);
        assert!(!output.status.success(), "{policy}: {stdout}");
        for expected in [
            "FAIL .#reject\n",
            "command 1: morphir [\"--not-a-real-option\"]\nexit: Some(2)\nstdout:\n",
            "\nstderr:\n",
            "data.cli_test.test_exit",
        ] {
            assert!(
                stderr.contains(expected),
                "{policy}: missing {expected:?}: {stderr}"
            );
        }
        assert!(!stderr.contains("Step panicked"), "{stderr}");
        assert_eq!(stdout, "0 passed; 1 failed; 0 not selected\n");
    }
}

/// A `scenarios.md` document with an inline workspace: its only input is the overlay
/// `.morphir/morphir.toml` file, so neither the example directory's own `morphir.toml` nor the
/// caller's configuration can reach the command it runs.
const INLINE_CONFIG: &str = "---\nversion: 1\ntitle: Isolated config\ndescription: An inline workspace ignores neighboring disk files and the caller's configuration.\ntags: [area:cli]\nprovider: rego\nworkspace: {kind: inline}\n---\n## Show config\n```yaml morphir:file\nid: config\npath: .morphir/morphir.toml\n```\n```toml\n[project]\nname = 'isolated'\nversion = '1.0.0'\nsource_directory = 'src'\n```\n```yaml morphir:command\nid: command\nname: Show config\ntimeout_seconds: 10\n```\n```sh\nmorphir config show --json\n```\n```yaml morphir:assertion\nid: assert\ncommand: command\nentrypoints: [data.cli_test.test_exit]\n```\n```rego\npackage cli_test\nimport rego.v1\ntest_exit if { input.exitCode == 0 }\n```\n";

#[test]
#[cfg_attr(
    not(feature = "rego"),
    ignore = "requires the rego feature: this scenario asserts through Rego, and the evaluator is compiled out by --no-default-features"
)]
fn itest_ignores_callers_configuration_with_an_inline_workspace() {
    let temp = tempfile::tempdir().unwrap();
    let example = temp.path().join("suite");
    let config = temp.path().join("user-config/morphir");
    fs::create_dir_all(&config).unwrap();
    fs::write(config.join("morphir.toml"), "invalid TOML {{{").unwrap();
    fs::create_dir_all(&example).unwrap();
    fs::write(example.join("scenarios.md"), INLINE_CONFIG).unwrap();
    // An inline workspace deliberately excludes neighboring project files.
    fs::write(example.join("morphir.toml"), "invalid TOML {{{").unwrap();
    let output = Command::new(env!("CARGO_BIN_EXE_morphir"))
        .arg("itest")
        .arg(&example)
        .env("XDG_CONFIG_HOME", temp.path().join("user-config"))
        .env("APPDATA", temp.path().join("user-config"))
        .env("MORPHIR_HOME", temp.path().join("outer-home"))
        .env("MORPHIR_LOG_FILE", "false")
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
}

/// A `scenarios.md` document that compiles a disk Elm file and combines it with the section's own
/// `morphir:file` overlay, with `__WORKSPACE__` standing for an optional `workspace:` frontmatter
/// line.
const DISK_WORKSPACE_WITH_OVERLAY: &str = "---\nversion: 1\ntitle: Compile disk source with an overlay file\ndescription: A disk workspace combines with its section's own overlay file.\ntags: [suite:offline]\nprovider: rego\n__WORKSPACE__---\n## Compile\n```yaml morphir:file\nid: extra\npath: extra.txt\n```\n```text\nnotebook addition\n```\n```yaml morphir:command\nid: compile\nname: Compile disk source with an overlay file\ntimeout_seconds: 30\ncaptures:\n  - {name: ir, path: installed/morphir-ir.json, format: json}\n  - {name: extra, path: extra.txt, format: text}\n  - {name: binary, path: binary.dat, format: exists}\n```\n```sh\nmorphir compile --input Example.elm --extension morphir-elm-native --package-name examples/disk --output installed --json\n```\n```yaml morphir:assertion\nid: compiled\ncommand: compile\nentrypoints: [data.disk_test.ok]\n```\n```rego\npackage disk_test\nimport rego.v1\nok if {\n    input.exitCode == 0\n    input.artifacts.ir.value.formatVersion == 3\n    input.artifacts.extra.value == \"notebook addition\\n\"\n    input.artifacts.binary.kind == \"file\"\n}\n```\n";

#[test]
#[cfg_attr(
    not(feature = "rego"),
    ignore = "requires the rego feature: this scenario asserts through Rego, and the evaluator is compiled out by --no-default-features"
)]
fn itest_copies_disk_workspaces_and_combines_overlay_files() {
    for workspace in [None, Some("project")] {
        let temp = tempfile::tempdir().unwrap();
        let project = workspace.map_or_else(|| temp.path().to_owned(), |p| temp.path().join(p));
        fs::create_dir_all(&project).unwrap();
        let source = "module Example exposing (Amount)\n\ntype alias Amount = Int\n";
        fs::write(project.join("Example.elm"), source).unwrap();
        fs::write(project.join("binary.dat"), [0, 255, 1]).unwrap();
        let workspace_line = match workspace {
            Some(path) => {
                // Only the selected directory is a workspace input.
                fs::write(temp.path().join("morphir.toml"), "invalid TOML {{{").unwrap();
                format!("workspace: {{kind: directory, path: {path}}}\n")
            }
            None => String::new(),
        };
        let text = DISK_WORKSPACE_WITH_OVERLAY.replace("__WORKSPACE__", &workspace_line);
        fs::write(temp.path().join("scenarios.md"), text).unwrap();
        let output = run(temp.path(), &[]);
        assert!(
            output.status.success(),
            "stdout={} stderr={}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        assert_eq!(
            fs::read_to_string(project.join("Example.elm")).unwrap(),
            source
        );
        assert!(!project.join("installed").exists());
        assert!(!project.join("extra.txt").exists());
        assert!(!project.join(".morphir").exists());
    }
}

/// A `scenarios.md` document with a `morphir:file` overlay at `__PATH__`, in a directory
/// workspace (the default), that never runs its command: materialization fails first whenever the
/// overlay path collides with a disk file.
const OVERLAY_AT_PATH: &str = "---\nversion: 1\ntitle: Overlay collision\ndescription: An overlay file must not collide with a disk file.\ntags: [area:files]\nprovider: rego\n---\n## Reject\n```yaml morphir:file\nid: extra\npath: __PATH__\n```\n```text\nnotebook contents\n```\n```yaml morphir:command\nid: command\nname: Reject unknown option\ntimeout_seconds: 10\n```\n```sh\nmorphir --not-a-real-option\n```\n```yaml morphir:assertion\nid: assert\ncommand: command\nentrypoints: [data.cli_test.test_exit]\n```\n```rego\npackage cli_test\nimport rego.v1\ntest_exit if { input.exitCode == 2 }\n```\n";

#[test]
fn itest_rejects_collisions_between_disk_and_overlay_files() {
    for path in ["extra.txt", "EXTRA.txt", "extra.txt/nested"] {
        let temp = tempfile::tempdir().unwrap();
        let text = OVERLAY_AT_PATH.replace("__PATH__", path);
        fs::write(temp.path().join("scenarios.md"), text).unwrap();
        fs::write(temp.path().join("extra.txt"), "disk contents").unwrap();
        let output = run(temp.path(), &[]);
        assert!(!output.status.success(), "accepted conflicting {path}");
        assert!(
            String::from_utf8_lossy(&output.stderr).contains("conflicting workspace path"),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert_eq!(
            fs::read_to_string(temp.path().join("extra.txt")).unwrap(),
            "disk contents"
        );
    }
}

#[test]
fn itest_rejects_configuration_above_the_temporary_workspace() {
    let temp = tempfile::tempdir().unwrap();
    let temporary_root = temp.path().join("tmp");
    fs::create_dir_all(&temporary_root).unwrap();
    let suite = temp.path().join("suite");
    fs::create_dir_all(&suite).unwrap();
    fs::write(suite.join("scenarios.md"), VERSION_MD).unwrap();
    // An ancestor can supply a project or enclosing workspace even though the
    // scenario's own home and output directory have been isolated.
    fs::write(
        temp.path().join("morphir.toml"),
        "[workspace]\nmembers = ['*']\n",
    )
    .unwrap();
    let output = Command::new(env!("CARGO_BIN_EXE_morphir"))
        .arg("itest")
        .arg(&suite)
        .env("TMPDIR", &temporary_root)
        .env("TEMP", &temporary_root)
        .env("TMP", &temporary_root)
        .env("MORPHIR_HOME", temp.path().join("outer-home"))
        .env("MORPHIR_BDD_OUT", temp.path().join("reports"))
        .env("MORPHIR_LOG_FILE", "false")
        .output()
        .unwrap();
    assert!(
        !output.status.success(),
        "contaminated temporary ancestors were accepted"
    );
    assert!(
        String::from_utf8_lossy(&output.stderr).contains("temporary ancestor configuration"),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
}

fn assert_golden_output(output: &std::process::Output, success: bool, diagnostic: &str) {
    let text = format!(
        "{}\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(output.status.success(), success, "{text}");
    assert!(text.contains(diagnostic), "missing {diagnostic:?}: {text}");
}

#[test]
fn itest_golden_whole_file_lines_and_markers() {
    for (actual, expected, select) in [
        ("héllo\nworld\n", "héllo\nworld\n", "select: {kind: all}\n"),
        (
            "ignored\nhéllo\nworld",
            "héllo\nworld",
            "select: {kind: lines, start: 2, end: 3}\n",
        ),
        (
            "ignored<start>héllo\nworld<end>ignored",
            "héllo\nworld",
            "select: {kind: between, start: \"<start>\", end: \"<end>\"}\n",
        ),
        ("", "", "select: {kind: all}\n"),
    ] {
        let root = tempfile::tempdir().unwrap();
        fs::write(root.path().join("actual.txt"), actual).unwrap();
        // `expected.txt` on disk, not an inline fence, so a selection with no trailing newline
        // (the `lines` and `between` cases above) is exact.
        fs::write(root.path().join("expected.txt"), expected).unwrap();
        let golden = format!("actual: actual.txt\nexpected_file: expected.txt\n{select}");
        fs::write(
            root.path().join("scenarios.md"),
            golden_md("morphir --version", &golden, None),
        )
        .unwrap();
        assert_golden_output(&run(root.path(), &[]), true, "1 passed");
    }
}

/// An itest run inside a Rust project writes no suite reports into it: with no `MORPHIR_BDD_OUT`
/// the reports go to a temporary directory that the run removes.
#[test]
fn itest_writes_no_suite_reports_into_the_project_it_runs_in() {
    let project = tempfile::tempdir().unwrap();
    fs::write(project.path().join("Cargo.lock"), "version = 3\n").unwrap();
    let root = project.path().join("examples");
    fs::create_dir_all(&root).unwrap();
    fs::write(root.join("actual.txt"), "same\n").unwrap();
    fs::write(root.join("expected.txt"), "same\n").unwrap();
    fs::write(
        root.join("scenarios.md"),
        golden_md(
            "morphir --version",
            "actual: actual.txt\nexpected_file: expected.txt\n",
            None,
        ),
    )
    .unwrap();
    let home = tempfile::tempdir().unwrap();
    let output = Command::new(env!("CARGO_BIN_EXE_morphir"))
        .current_dir(project.path())
        .arg("itest")
        .arg(&root)
        .env("MORPHIR_HOME", home.path())
        .env("MORPHIR_LOG_FILE", "false")
        .env_remove("MORPHIR_BDD_OUT")
        .output()
        .unwrap();
    assert_golden_output(&output, true, "1 passed");
    assert!(
        !project.path().join(".dev").exists(),
        "itest wrote into the project: {:?}",
        fs::read_dir(project.path().join(".dev")).map(|d| d.count())
    );
}

/// `--report-dir` keeps the suite reports in the directory it names, creating it, and wins over
/// `MORPHIR_BDD_OUT`.
#[test]
fn itest_report_dir_keeps_the_suite_reports_and_wins_over_the_environment() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().join("examples");
    fs::create_dir_all(&root).unwrap();
    fs::write(root.join("outline.feature"), OUTLINE).unwrap();
    let chosen = temp.path().join("reports/itest");
    let ignored = temp.path().join("from-environment");
    let output = Command::new(env!("CARGO_BIN_EXE_morphir"))
        .arg("itest")
        .arg(&root)
        .arg("--report-dir")
        .arg(&chosen)
        .env("MORPHIR_HOME", temp.path().join("home"))
        .env("MORPHIR_LOG_FILE", "false")
        .env("MORPHIR_BDD_OUT", &ignored)
        .output()
        .unwrap();
    let (stdout, stderr) = text(&output);
    assert!(output.status.success(), "stdout={stdout} stderr={stderr}");
    for report in ["itest.json", "itest.xml"] {
        assert!(chosen.join(report).is_file(), "{report}: {stderr}");
    }
    assert!(!ignored.exists(), "MORPHIR_BDD_OUT was used");
}

#[test]
fn itest_golden_expected_file_and_explicit_line_endings() {
    let root = tempfile::tempdir().unwrap();
    fs::write(root.path().join("actual.txt"), "héllo\r\nworld\r\n").unwrap();
    fs::write(root.path().join("expected.txt"), "héllo\nworld\n").unwrap();
    let golden = "actual: actual.txt\nexpected_file: expected.txt\n";
    fs::write(
        root.path().join("scenarios.md"),
        golden_md("morphir --version", golden, None),
    )
    .unwrap();
    assert_golden_output(&run(root.path(), &[]), false, "golden mismatch");
    let golden = "actual: actual.txt\nexpected_file: expected.txt\nline_endings: lf\n";
    fs::write(
        root.path().join("scenarios.md"),
        golden_md("morphir --version", golden, None),
    )
    .unwrap();
    assert_golden_output(&run(root.path(), &[]), true, "1 passed");
}

#[test]
fn itest_golden_mismatch_has_diff_and_final_newline_is_significant() {
    let root = tempfile::tempdir().unwrap();
    fs::write(root.path().join("actual.txt"), "wrong\n").unwrap();
    fs::write(
        root.path().join("scenarios.md"),
        golden_md("morphir --version", "actual: actual.txt\n", Some("right\n")),
    )
    .unwrap();
    let output = run(root.path(), &[]);
    for diagnostic in ["golden mismatch", "actual.txt", "-right", "+wrong"] {
        assert_golden_output(&output, false, diagnostic);
    }
    fs::write(root.path().join("actual.txt"), "right").unwrap();
    assert_golden_output(&run(root.path(), &[]), false, "No newline");
}

#[test]
fn itest_golden_invalid_or_missing_inputs_fail() {
    // Every golden metadata fence needs a following source fence, so a case with no
    // `expected_file` supplies an empty inline one.
    for (golden, body, actual, diagnostic) in [
        (
            "actual: actual.txt\nselect: {kind: lines, start: 0, end: 1}\n",
            Some(""),
            Some("a\n"),
            "line",
        ),
        (
            "actual: actual.txt\nselect: {kind: lines, start: 2, end: 3}\n",
            Some(""),
            Some("a\n"),
            "line",
        ),
        (
            "actual: actual.txt\nselect: {kind: between, start: \"[\", end: \"]\"}\n",
            Some(""),
            Some("[a][b]"),
            "marker",
        ),
        (
            "actual: actual.txt\nexpected_file: missing.txt\n",
            None,
            Some("a"),
            "missing.txt",
        ),
        ("actual: actual.txt\n", Some(""), None, "actual.txt"),
    ] {
        let root = tempfile::tempdir().unwrap();
        fs::write(
            root.path().join("scenarios.md"),
            golden_md("morphir --version", golden, body),
        )
        .unwrap();
        if let Some(actual) = actual {
            fs::write(root.path().join("actual.txt"), actual).unwrap();
        }
        assert_golden_output(&run(root.path(), &[]), false, diagnostic);
    }
}

#[test]
#[cfg_attr(
    not(feature = "rego"),
    ignore = "requires the rego feature: this scenario asserts through Rego, and the evaluator is compiled out by --no-default-features"
)]
fn itest_golden_markdown_inline_and_file_expectations() {
    let root = tempfile::tempdir().unwrap();
    fs::write(
        root.path().join("actual.txt"),
        "before\nSTART\nhéllo\nEND\nafter\n",
    )
    .unwrap();
    fs::write(root.path().join("expected.txt"), "héllo\n").unwrap();
    fs::write(
        root.path().join("scenarios.md"),
        r#"---
version: 1
title: Golden text
description: Assert exact selected contents through the CLI evaluator.
tags: [suite:offline]
provider: rego
---
## Match spans
```yaml morphir:command
id: run
name: Observe files
timeout_seconds: 10
```
```sh
morphir --version
```
```yaml morphir:golden
id: lines
command: run
actual: actual.txt
select: {kind: lines, start: 3, end: 3}
```
Prose may separate the expected content from its metadata.
```text
héllo
```
```yaml morphir:golden
id: markers
command: run
actual: actual.txt
expected_file: expected.txt
select: {kind: between, start: "START\n", end: "END"}
```
This disk golden needs no source fence.
"#,
    )
    .unwrap();
    assert_golden_output(&run(root.path(), &[]), true, "1 passed");
    fs::write(root.path().join("expected.txt"), "wrong\n").unwrap();
    assert_golden_output(&run(root.path(), &[]), false, "golden mismatch");
}

/// A `scenarios.md` document with one section: the command `command`, then a golden check whose
/// metadata lines (after `id` and `command`) are `golden`, then `body` as its inline expectation.
fn golden_md(command: &str, golden: &str, body: Option<&str>) -> String {
    let mut text = format!(
        "---\nversion: 1\ntitle: Golden\ndescription: Golden checks.\ntags: [suite:offline]\nprovider: rego\n---\n## Check\n```yaml morphir:command\nid: run\nname: Observe files\ntimeout_seconds: 30\n```\n```sh\n{command}\n```\n```yaml morphir:golden\nid: golden\ncommand: run\n{golden}```\n"
    );
    if let Some(body) = body {
        text.push_str(&format!("```text\n{body}```\n"));
    }
    text
}

#[test]
fn itest_golden_cannot_mask_a_failed_command() {
    let root = tempfile::tempdir().unwrap();
    fs::write(root.path().join("actual.txt"), "same\n").unwrap();
    fs::write(root.path().join("expected.txt"), "same\n").unwrap();
    let golden = "actual: actual.txt\nexpected_file: expected.txt\n";
    fs::write(
        root.path().join("scenarios.md"),
        golden_md("morphir --version", golden, None),
    )
    .unwrap();
    assert_golden_output(&run(root.path(), &[]), true, "1 passed");
    fs::write(
        root.path().join("scenarios.md"),
        golden_md("morphir --not-a-real-option", golden, None),
    )
    .unwrap();
    let output = run(root.path(), &[]);
    assert_golden_output(&output, false, "exit: Some(2)");
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains(
            "golden \"expected.txt\": command 1 (morphir [\"--not-a-real-option\"]) exited with Some(2), not 0"
        ),
        "{stderr}"
    );
}

/// A `scenarios.md` document with one golden check whose metadata is `__GOLDEN__` (after `id`) and
/// whose inline source fence is `__SOURCE__`, checked with `--list` alone, before any command
/// would run.
const GOLDEN_METADATA: &str = "---\nversion: 1\ntitle: Golden metadata\ndescription: Golden metadata is checked before any command runs.\ntags: [suite:offline]\nprovider: rego\n---\n## Check\n```yaml morphir:command\nid: run\nname: Observe files\ntimeout_seconds: 10\n```\n```sh\nmorphir --version\n```\n```yaml morphir:golden\nid: golden\n__GOLDEN__```\n```text\n__SOURCE__```\n";

#[test]
fn itest_golden_rejects_invalid_metadata_before_execution() {
    for (golden, source, diagnostic) in [
        ("command: run\nactual: ../outside.txt\n", "", "path"),
        (
            "command: run\nactual: actual.txt\nexpected_file: ../outside.txt\n",
            "",
            "path",
        ),
        // The CLI's error report can wrap a long line, so the diagnostic is the referenced
        // command id, not the surrounding prose (`itest_refuses_a_notebook_scenario_and_names_the_conversion`
        // below strips that wrapping the same way for a longer message).
        ("command: later\nactual: actual.txt\n", "", "\"later\""),
        (
            "command: run\nactual: actual.txt\nselect: {kind: all, unexpected: true}\n",
            "",
            "`unexpected`",
        ),
        (
            "command: run\nactual: actual.txt\nline_endings: trim\n",
            "",
            "`trim`",
        ),
    ] {
        let root = tempfile::tempdir().unwrap();
        let text = GOLDEN_METADATA
            .replace("__GOLDEN__", golden)
            .replace("__SOURCE__", source);
        fs::write(root.path().join("scenarios.md"), text).unwrap();
        assert_golden_output(&run(root.path(), &["--list"]), false, diagnostic);
    }
}

#[cfg(unix)]
#[test]
fn itest_golden_rejects_symlinked_expected_files_even_in_inline_workspaces() {
    let root = tempfile::tempdir().unwrap();
    let outside = tempfile::NamedTempFile::new().unwrap();
    std::os::unix::fs::symlink(outside.path(), root.path().join("expected.txt")).unwrap();
    fs::write(root.path().join("actual.txt"), "").unwrap();
    let text = golden_md(
        "morphir --version",
        "actual: actual.txt\nexpected_file: expected.txt\n",
        None,
    )
    .replace(
        "provider: rego\n",
        "provider: rego\nworkspace: {kind: inline}\n",
    );
    fs::write(root.path().join("scenarios.md"), text).unwrap();
    let output = run(root.path(), &[]);
    assert_golden_output(&output, false, "assertion traverses a symlink");
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("load expectation before commands"),
        "{stderr}"
    );
}

#[test]
#[cfg_attr(
    not(feature = "rego"),
    ignore = "requires the rego feature: this scenario asserts through Rego, and the evaluator is compiled out by --no-default-features"
)]
fn itest_golden_freezes_expected_files_before_cli_commands() {
    let root = tempfile::tempdir().unwrap();
    fs::write(
        root.path().join("Example.elm"),
        "module Example exposing (Name)\n\ntype alias Name = String\n",
    )
    .unwrap();
    let expected_dir = root.path().join("expected");
    fs::create_dir_all(expected_dir.join("compile.dest")).unwrap();
    fs::write(
        expected_dir.join("compile.dest/morphir-ir.json"),
        "authored expectation\n",
    )
    .unwrap();
    // A trusted CLI command can write outside its copied workspace. Deliberately
    // overwrite the author's expectation to prove it was frozen before execution.
    let command = format!(
        "morphir compile --input Example.elm --extension morphir-elm-native --package-name examples/frozen --out-dir {} --output installed --json",
        shell_words::quote(expected_dir.to_str().unwrap())
    );
    fs::write(
        root.path().join("scenarios.md"),
        golden_md(
            &command,
            "actual: installed/morphir-ir.json\nexpected_file: expected/compile.dest/morphir-ir.json\n",
            None,
        ),
    )
    .unwrap();
    let output = run(root.path(), &[]);
    assert_golden_output(&output, false, "-authored expectation");
    let installed: Value = serde_json::from_str(
        &fs::read_to_string(expected_dir.join("compile.dest/morphir-ir.json")).unwrap(),
    )
    .unwrap();
    assert!(installed.get("formatVersion").is_some());
}

#[test]
fn itest_golden_rejects_a_null_expected_file() {
    let root = tempfile::tempdir().unwrap();
    fs::write(
        root.path().join("scenarios.md"),
        r#"---
version: 1
title: Missing expectation
description: Null cannot silently select an empty inline expectation.
tags: [suite:offline]
provider: rego
---
## No accidental pass
```yaml morphir:command
id: run
name: Observe files
timeout_seconds: 10
```
```sh
morphir --version
```
```yaml morphir:golden
id: empty
command: run
actual: actual.txt
expected_file:
```
```text
This text must never be silently ignored as an expectation.
```
"#,
    )
    .unwrap();
    assert_golden_output(&run(root.path(), &["--list"]), false, "expected a string");
}

/// The checked-in `examples` directory.
fn examples() -> std::path::PathBuf {
    std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../examples")
}

fn text(output: &std::process::Output) -> (String, String) {
    (
        String::from_utf8_lossy(&output.stdout).into_owned(),
        String::from_utf8_lossy(&output.stderr).into_owned(),
    )
}

/// A `scenarios.md` document with two sections that each run `morphir --version`.
const VERSION_MD: &str = r#"---
version: 1
title: Version
description: Report the version.
tags: [suite:offline]
provider: rego
---
## First
```yaml morphir:command
id: first
name: First version
timeout_seconds: 30
```
```sh
morphir --version
```
```yaml morphir:assertion
id: first-ok
command: first
entrypoints: [data.version_test.ok]
```
```rego
package version_test
import rego.v1
ok if { input.exitCode == 0 }
```
## Second
```yaml morphir:command
id: second
name: Second version
timeout_seconds: 30
```
```sh
morphir --version
```
```yaml morphir:assertion
id: second-ok
command: second
entrypoints: [data.version_test.ok]
```
```rego
package version_test
import rego.v1
ok if { input.exitCode == 0 }
```
"#;

/// A `.feature` document whose Feature description holds `fence` as its `yaml itest` fence.
fn feature_with_itest_fence(fence: &str) -> String {
    format!(
        "@suite:offline\nFeature: Materialize\n  ```yaml itest\n{fence}  ```\n\n  Scenario: Version\n    When I run \"morphir --version\"\n"
    )
}

#[test]
fn itest_list_matches_the_recorded_fixture() {
    let fixture = include_str!("fixtures/itest-list.txt");
    let output = run(&examples(), &["--list"]);
    let (stdout, stderr) = text(&output);
    // Byte for byte the output recorded before Part C, with one intended change: the notebook
    // `elm/single-file` had no section, and its `.feature.md` scenario is
    // `elm/single-file#compile-and-install`, with the same title, tags and description.
    assert_eq!(stdout, fixture, "stderr={stderr}");
    assert!(output.status.success(), "stderr={stderr}");
}

#[test]
fn itest_refuses_a_notebook_scenario_and_names_the_conversion() {
    let temp = tempfile::tempdir().unwrap();
    write_scenario(&temp.path().join("cli/old"), &scenario());
    fs::write(temp.path().join("scenarios.md"), VERSION_MD).unwrap();
    let notebook = temp.path().join("cli/old/scenario.ipynb");
    let reason = format!(
        "notebook scenarios are no longer supported; convert {} to scenarios.feature.md",
        notebook.display()
    );
    // `--list` gives the reason as the command's error, which the error report may wrap.
    let output = run(temp.path(), &["--list"]);
    let (stdout, stderr) = text(&output);
    assert!(!output.status.success(), "stdout={stdout}");
    let unwrapped = |text: &str| -> String {
        text.chars()
            .filter(|c| !c.is_whitespace() && *c != '│')
            .collect()
    };
    assert!(unwrapped(&stderr).contains(&unwrapped(&reason)), "{stderr}");
    // A run gives a FAIL line for the notebook's directory, whatever the tags select.
    let output = run(temp.path(), &["--tag", "suite:none"]);
    let (stdout, stderr) = text(&output);
    assert!(!output.status.success(), "stdout={stdout}");
    assert!(
        stderr.contains(&format!("FAIL cli/old\n{reason}")),
        "{stderr}"
    );
    assert_eq!(stdout, "0 passed; 1 failed; 2 not selected\n", "{stderr}");
}

#[test]
fn itest_tag_that_selects_nothing_is_an_error() {
    let temp = tempfile::tempdir().unwrap();
    fs::write(temp.path().join("scenarios.md"), VERSION_MD).unwrap();
    let output = run(temp.path(), &["--tag", "suite:none"]);
    let (stdout, stderr) = text(&output);
    assert!(!output.status.success(), "stdout={stdout} stderr={stderr}");
    assert!(stdout.is_empty(), "stdout={stdout}");
    assert!(
        stderr.contains("no scenarios match tags [\"suite:none\"]"),
        "{stderr}"
    );
}

#[test]
#[cfg_attr(
    not(feature = "rego"),
    ignore = "requires the rego feature: this scenario asserts through Rego, and the evaluator is compiled out by --no-default-features"
)]
fn itest_runs_scenarios_md_sections_and_counts_the_ones_it_skips() {
    let temp = tempfile::tempdir().unwrap();
    fs::write(temp.path().join("scenarios.md"), VERSION_MD).unwrap();
    let output = run(temp.path(), &["--filter", ".#second"]);
    let (stdout, stderr) = text(&output);
    assert!(output.status.success(), "stdout={stdout} stderr={stderr}");
    assert_eq!(
        stdout, "PASS .#second: Second (1 steps)\n1 passed; 0 failed; 1 not selected\n",
        "{stderr}"
    );
}

#[test]
fn itest_fails_a_scenario_whose_workspace_directory_is_missing() {
    let temp = tempfile::tempdir().unwrap();
    let example = temp.path().join("cli/missing");
    fs::create_dir_all(&example).unwrap();
    fs::write(
        example.join("scenarios.feature"),
        feature_with_itest_fence("  workspace: {kind: directory, path: absent}\n"),
    )
    .unwrap();
    let output = run(temp.path(), &[]);
    let (stdout, stderr) = text(&output);
    assert!(!output.status.success(), "stdout={stdout} stderr={stderr}");
    assert!(stderr.contains("FAIL cli/missing#version\n"), "{stderr}");
    assert!(
        stderr.contains("workspace source must be a real directory"),
        "{stderr}"
    );
    assert_eq!(stdout, "0 passed; 1 failed; 0 not selected\n");
}

#[test]
fn itest_fails_a_scenario_whose_workspace_does_not_materialize() {
    let temp = tempfile::tempdir().unwrap();
    fs::write(temp.path().join("morphir.json"), "{}\n").unwrap();
    fs::write(
        temp.path().join("scenarios.feature"),
        feature_with_itest_fence("  files:\n    - {path: morphir.json, content: \"{}\"}\n"),
    )
    .unwrap();
    let output = run(temp.path(), &[]);
    let (stdout, stderr) = text(&output);
    assert!(!output.status.success(), "stdout={stdout} stderr={stderr}");
    assert!(stderr.contains("FAIL .#version\n"), "{stderr}");
    assert!(
        stderr.contains("duplicate or conflicting workspace path"),
        "{stderr}"
    );
    assert_eq!(stdout, "0 passed; 1 failed; 0 not selected\n");
}

#[test]
#[cfg_attr(
    not(feature = "rego"),
    ignore = "requires the rego feature: this scenario asserts through Rego, and the evaluator is compiled out by --no-default-features"
)]
fn itest_fails_a_scenarios_md_the_reader_refuses_and_runs_the_rest() {
    let temp = tempfile::tempdir().unwrap();
    let good = temp.path().join("cli/good");
    fs::create_dir_all(&good).unwrap();
    fs::write(good.join("scenarios.md"), VERSION_MD).unwrap();
    // The second section's assertion checks the first command after the second one ran: the
    // reader refuses that order rather than regroup the steps.
    let refused = VERSION_MD.to_owned()
        + "```yaml morphir:assertion\nid: late\ncommand: first\nentrypoints: [data.t.ok]\n```\n```rego\npackage t\nimport rego.v1\nok if { true }\n```\n";
    let bad = temp.path().join("cli/refused");
    fs::create_dir_all(&bad).unwrap();
    fs::write(bad.join("scenarios.md"), refused).unwrap();
    let output = run(temp.path(), &[]);
    let (stdout, stderr) = text(&output);
    assert!(!output.status.success(), "stdout={stdout} stderr={stderr}");
    assert!(stderr.contains("FAIL cli/refused\n"), "{stderr}");
    assert!(stderr.contains("which is not the last command"), "{stderr}");
    // The reason names the document once, not once from the suite and again from the reader.
    let document = bad.join("scenarios.md").display().to_string();
    assert_eq!(stderr.matches(&document).count(), 1, "{stderr}");
    assert!(
        stdout.contains("PASS cli/good#first: First (1 steps)\n"),
        "{stdout}"
    );
    assert!(
        stdout.ends_with("2 passed; 1 failed; 0 not selected\n"),
        "{stdout}"
    );
    // `--list` gives the same reason as an error, which the terminal report may wrap, so count
    // the directory part of the path.
    let listed = run(temp.path(), &["--list"]);
    let (_, stderr) = text(&listed);
    assert!(!listed.status.success(), "{stderr}");
    // Join the report's wrapped lines: where they break depends on the temporary path's length.
    let unwrapped = stderr
        .split_whitespace()
        .filter(|word| *word != "│")
        .collect::<Vec<_>>()
        .join(" ");
    assert!(unwrapped.contains("checks command \"first\""), "{stderr}");
    assert_eq!(stderr.matches("/cli/refused/").count(), 1, "{stderr}");
}

#[test]
fn itest_fails_every_selected_scenario_when_a_temporary_ancestor_has_configuration() {
    let temp = tempfile::tempdir().unwrap();
    let temporary_root = temp.path().join("tmp");
    fs::create_dir_all(&temporary_root).unwrap();
    let suite = temp.path().join("suite");
    fs::create_dir_all(&suite).unwrap();
    fs::write(suite.join("scenarios.md"), VERSION_MD).unwrap();
    fs::write(
        temp.path().join("morphir.toml"),
        "[workspace]\nmembers = ['*']\n",
    )
    .unwrap();
    let output = Command::new(env!("CARGO_BIN_EXE_morphir"))
        .arg("itest")
        .arg(&suite)
        .args(["--filter", ".#first"])
        .env("TMPDIR", &temporary_root)
        .env("TEMP", &temporary_root)
        .env("TMP", &temporary_root)
        .env("MORPHIR_HOME", temp.path().join("outer-home"))
        .env("MORPHIR_BDD_OUT", temp.path().join("reports"))
        .env("MORPHIR_LOG_FILE", "false")
        .output()
        .unwrap();
    let (stdout, stderr) = text(&output);
    assert!(!output.status.success(), "stdout={stdout} stderr={stderr}");
    assert!(
        stderr.contains("FAIL .#first\nitest cannot isolate temporary ancestor configuration at"),
        "{stderr}"
    );
    assert!(!stderr.contains("FAIL .#second"), "{stderr}");
    assert_eq!(stdout, "0 passed; 1 failed; 1 not selected\n");
}

/// A `.feature` document with one outline of two rows, `Row 1` and `Row 2`.
const OUTLINE: &str = "Feature: Outline\n  Scenario Outline: Row <n>\n    When I run \"morphir --version\"\n\n    Examples:\n      | n |\n      | 1 |\n      | 2 |\n";

#[test]
fn itest_counts_every_outline_row_when_a_temporary_ancestor_has_configuration() {
    let temp = tempfile::tempdir().unwrap();
    let temporary_root = temp.path().join("tmp");
    fs::create_dir_all(&temporary_root).unwrap();
    let suite = temp.path().join("suite");
    fs::create_dir_all(&suite).unwrap();
    fs::write(suite.join("outline.feature"), OUTLINE).unwrap();
    fs::write(
        temp.path().join("morphir.toml"),
        "[workspace]\nmembers = ['*']\n",
    )
    .unwrap();
    let output = Command::new(env!("CARGO_BIN_EXE_morphir"))
        .arg("itest")
        .arg(&suite)
        .env("TMPDIR", &temporary_root)
        .env("TEMP", &temporary_root)
        .env("TMP", &temporary_root)
        .env("MORPHIR_HOME", temp.path().join("outer-home"))
        .env("MORPHIR_BDD_OUT", temp.path().join("reports"))
        .env("MORPHIR_LOG_FILE", "false")
        .output()
        .unwrap();
    let (stdout, stderr) = text(&output);
    assert!(!output.status.success(), "stdout={stdout} stderr={stderr}");
    assert!(stderr.contains("FAIL .#row-n\n"), "{stderr}");
    assert_eq!(stdout, "0 passed; 2 failed; 0 not selected\n", "{stderr}");
}

/// The suite expands an outline's `<n>` in each row's name, so each row runs as `Row 1` or
/// `Row 2`; the rows must still run, and report, under the outline's listed id `.#row-n`.
#[test]
fn itest_runs_and_reports_every_outline_row_under_the_outline_id() {
    let temp = tempfile::tempdir().unwrap();
    fs::write(temp.path().join("outline.feature"), OUTLINE).unwrap();
    let output = run(temp.path(), &["--list"]);
    let (stdout, stderr) = text(&output);
    assert!(output.status.success(), "stdout={stdout} stderr={stderr}");
    assert!(stdout.starts_with(".#row-n: Row <n> []\n"), "{stdout}");
    for args in [&[][..], &["--filter", ".#row-n"][..]] {
        let output = run(temp.path(), args);
        let (stdout, stderr) = text(&output);
        assert!(
            output.status.success(),
            "{args:?}: stdout={stdout} stderr={stderr}"
        );
        assert!(
            stdout.contains("PASS .#row-n: Row 1 (1 steps)\n"),
            "{stdout}"
        );
        assert!(
            stdout.contains("PASS .#row-n: Row 2 (1 steps)\n"),
            "{stdout}"
        );
        assert!(
            stdout.ends_with("2 passed; 0 failed; 0 not selected\n"),
            "{args:?}: {stdout}"
        );
    }
}

#[test]
fn itest_ignores_suite_file_errors_under_excluded_directories() {
    let temp = tempfile::tempdir().unwrap();
    fs::write(temp.path().join("scenarios.md"), VERSION_MD).unwrap();
    fs::create_dir_all(temp.path().join("node_modules/pkg")).unwrap();
    fs::write(
        temp.path().join("node_modules/pkg/broken.feature"),
        "this is not Gherkin\n",
    )
    .unwrap();
    let output = run(temp.path(), &["--filter", ".#first"]);
    let (stdout, stderr) = text(&output);
    assert!(output.status.success(), "stdout={stdout} stderr={stderr}");
    assert!(!stderr.contains("FAIL"), "{stderr}");
    assert!(
        stdout.ends_with("1 passed; 0 failed; 1 not selected\n"),
        "{stdout}"
    );
}

#[test]
fn itest_refuses_a_missing_search_root() {
    let temp = tempfile::tempdir().unwrap();
    let missing = temp.path().join("absent");
    let output = run(&missing, &[]);
    let (stdout, stderr) = text(&output);
    assert!(!output.status.success(), "stdout={stdout} stderr={stderr}");
    assert!(stderr.contains("absent"), "{stderr}");
    assert!(!stdout.contains("passed"), "{stdout}");
}

#[test]
#[cfg_attr(
    not(feature = "rego"),
    ignore = "requires the rego feature: this scenario asserts through Rego, and the evaluator is compiled out by --no-default-features"
)]
fn itest_filter_runs_one_example_section() {
    let output = run(&examples(), &["--filter", "cli/migrate#classic-to-v4"]);
    let (stdout, stderr) = text(&output);
    assert!(output.status.success(), "stdout={stdout} stderr={stderr}");
    assert_eq!(
        stdout,
        "PASS cli/migrate#classic-to-v4: Convert Classic JSON to V4 YAML (1 steps)\n\
         1 passed; 0 failed; 25 not selected\n",
        "{stderr}"
    );
}

mod itest_runner {
    use morphir::commands::itest::steps::{ItestDirs, ItestRunner};
    use morphir_bdd::steps::cli::{CliProgram, CliRequest, CliRunner};
    use morphir_gherkin::extension::Context;
    use std::{fs, path::Path, time::Duration};

    /// A scenario context that holds only `ItestDirs` for a prepared temporary root.
    fn context(root: &Path) -> Context {
        fs::create_dir_all(root.join("project")).unwrap();
        let mut context = Context::default();
        context.insert(ItestDirs::new(root));
        context
    }

    #[tokio::test]
    async fn itest_runner_runs_morphir_with_per_step_logs() {
        let temp = tempfile::tempdir().unwrap();
        let context = context(temp.path());
        let program = CliProgram {
            name: "morphir".into(),
            path: env!("CARGO_BIN_EXE_morphir").into(),
        };
        let args = vec!["--version".to_owned()];
        let output = ItestRunner
            .run(CliRequest {
                program: &program,
                args: &args,
                timeout: None,
                context: &context,
            })
            .await
            .unwrap();
        assert_eq!(output.status, Some(0), "stderr={}", output.stderr);
        assert!(
            output.stdout.contains(env!("CARGO_PKG_VERSION")),
            "stdout={}",
            output.stdout
        );
        assert!(temp.path().join("step-1/stdout.log").is_file());
        assert!(temp.path().join("step-1/stderr.log").is_file());

        // A second command in the same scenario gets the next step directory.
        ItestRunner
            .run(CliRequest {
                program: &program,
                args: &args,
                timeout: Some(Duration::from_secs(30)),
                context: &context,
            })
            .await
            .unwrap();
        assert!(temp.path().join("step-2/stdout.log").is_file());
    }

    #[tokio::test]
    async fn itest_runner_needs_itest_dirs() {
        let program = CliProgram {
            name: "morphir".into(),
            path: env!("CARGO_BIN_EXE_morphir").into(),
        };
        let error = ItestRunner
            .run(CliRequest {
                program: &program,
                args: &[],
                timeout: None,
                context: &Context::default(),
            })
            .await
            .unwrap_err();
        assert!(error.contains("MaterializeExample"), "{error}");
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn itest_runner_isolates_the_morphir_home() {
        let temp = tempfile::tempdir().unwrap();
        let context = context(temp.path());
        let program = CliProgram {
            name: "sh".into(),
            path: "/bin/sh".into(),
        };
        let args = vec![
            "-c".to_owned(),
            "echo $MORPHIR_HOME; echo $MORPHIR_LOG_FILE; pwd".to_owned(),
        ];
        let output = ItestRunner
            .run(CliRequest {
                program: &program,
                args: &args,
                timeout: None,
                context: &context,
            })
            .await
            .unwrap();
        let lines: Vec<_> = output.stdout.lines().collect();
        assert_eq!(
            lines[0],
            temp.path().join("home").display().to_string(),
            "stdout={}",
            output.stdout
        );
        assert_eq!(lines[1], "false");
        assert_eq!(
            Path::new(lines[2]).canonicalize().unwrap(),
            temp.path().join("project").canonicalize().unwrap()
        );
    }

    #[tokio::test]
    async fn itest_runner_records_the_command_number_and_timeout() {
        let temp = tempfile::tempdir().unwrap();
        let context = context(temp.path());
        let dirs = context.get::<ItestDirs>().unwrap().clone();
        let program = CliProgram {
            name: "morphir".into(),
            path: env!("CARGO_BIN_EXE_morphir").into(),
        };
        let args = vec!["--version".to_owned()];

        ItestRunner
            .run(CliRequest {
                program: &program,
                args: &args,
                timeout: None,
                context: &context,
            })
            .await
            .unwrap();
        assert_eq!(dirs.command.load(std::sync::atomic::Ordering::SeqCst), 1);
        assert_eq!(*dirs.last_timeout.lock().unwrap(), None);

        // A timed `When I run` records its own timeout for the policy step to reuse.
        ItestRunner
            .run(CliRequest {
                program: &program,
                args: &args,
                timeout: Some(Duration::from_secs(42)),
                context: &context,
            })
            .await
            .unwrap();
        assert_eq!(dirs.command.load(std::sync::atomic::Ordering::SeqCst), 2);
        assert_eq!(
            *dirs.last_timeout.lock().unwrap(),
            Some(Duration::from_secs(42))
        );
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn itest_runner_times_out() {
        let temp = tempfile::tempdir().unwrap();
        let context = context(temp.path());
        let program = CliProgram {
            name: "sh".into(),
            path: "/bin/sh".into(),
        };
        let args = vec!["-c".to_owned(), "sleep 30".to_owned()];
        let error = ItestRunner
            .run(CliRequest {
                program: &program,
                args: &args,
                timeout: Some(Duration::from_millis(200)),
                context: &context,
            })
            .await
            .unwrap_err();
        assert!(error.contains("timed out after"), "{error}");
    }
}
