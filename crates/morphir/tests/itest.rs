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
    Command::new(env!("CARGO_BIN_EXE_morphir"))
        .arg("itest")
        .arg(root)
        .args(args)
        .env("MORPHIR_HOME", home.path())
        .env("MORPHIR_LOG_FILE", "false")
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
fn itest_markdown_drives_cli_with_disk_and_inline_files() {
    let temp = tempfile::tempdir().unwrap();
    let example = temp.path().join("elm/markdown");
    fs::create_dir_all(&example).unwrap();
    let source = "module Example exposing (Name)\n\ntype alias Name = String\n";
    fs::write(example.join("Example.elm"), source).unwrap();
    fs::write(example.join("scenarios.md"), MARKDOWN).unwrap();
    write_scenario(&temp.path().join("cli/notebook"), &scenario());
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
        stderr.contains("compiled") && stderr.contains("compiles"),
        "{stderr}"
    );
}

#[test]
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

#[test]
fn itest_lists_filters_and_drives_real_cli_commands() {
    let temp = tempfile::tempdir().unwrap();
    let example = temp.path().join("cli/errors");
    write_scenario(&example, &scenario());
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
    assert!(!run(temp.path(), &["--tag", "missing"]).status.success());
    assert!(!example.join(".morphir").exists());
}

#[test]
fn itest_distinguishes_search_root_from_a_directory_named_root() {
    let temp = tempfile::tempdir().unwrap();
    write_scenario(temp.path(), &scenario());
    write_scenario(&temp.path().join("root"), &scenario());
    for (filter, other) in [("root", "."), (".", "root")] {
        let output = run(temp.path(), &["--filter", filter]);
        let stdout = String::from_utf8_lossy(&output.stdout);
        assert!(
            output.status.success(),
            "stdout={stdout} stderr={}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(stdout.contains(&format!("PASS {filter}:")), "{stdout}");
        assert!(!stdout.contains(&format!("PASS {other}:")), "{stdout}");
        assert!(
            stdout.contains("1 passed; 0 failed; 1 not selected"),
            "{stdout}"
        );
    }
    let output = run(temp.path(), &["--list"]);
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(output.status.success());
    assert!(
        stdout.lines().any(|line| line.starts_with(".:")),
        "{stdout}"
    );
    assert!(
        stdout.lines().any(|line| line.starts_with("root:")),
        "{stdout}"
    );
}

#[test]
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
            11
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
        let mut bad = scenario();
        bad["cells"][2]["source"] = json!(policy);
        write_scenario(temp.path(), &bad);
        let output = run(temp.path(), &[]);
        assert!(!output.status.success());
        let stderr = String::from_utf8_lossy(&output.stderr);
        for expected in ["Reject unknown option", "assert", "stdout:", "stderr:"] {
            assert!(stderr.contains(expected), "{stderr}");
        }
    }
}

#[test]
fn itest_ignores_callers_configuration_and_materializes_notebook_files() {
    let temp = tempfile::tempdir().unwrap();
    let example = temp.path().join("suite");
    let config = temp.path().join("user-config/morphir");
    fs::create_dir_all(&config).unwrap();
    fs::write(config.join("morphir.toml"), "invalid TOML {{{").unwrap();
    let mut notebook = scenario();
    notebook["metadata"]["morphir"]["itest"]["workspace"] = json!({"kind":"notebook"});
    notebook["cells"][1]["source"] = json!("morphir config show --json");
    notebook["cells"][2]["source"] =
        json!("package cli_test\nimport rego.v1\ntest_exit if { input.exitCode == 0 }");
    notebook["cells"].as_array_mut().unwrap().push(code(
        "config",
        "[project]\nname = 'isolated'\nversion = '1.0.0'\nsource_directory = 'src'\n",
        json!({"file":{"path":".morphir/morphir.toml","language":"toml"}}),
    ));
    write_scenario(&example, &notebook);
    // Notebook-only mode deliberately excludes neighboring project files.
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

#[test]
fn itest_copies_disk_workspaces_and_combines_optional_notebook_files() {
    for workspace in [None, Some("project")] {
        let temp = tempfile::tempdir().unwrap();
        let project = workspace.map_or_else(|| temp.path().to_owned(), |p| temp.path().join(p));
        fs::create_dir_all(&project).unwrap();
        let source = "module Example exposing (Amount)\n\ntype alias Amount = Int\n";
        fs::write(project.join("Example.elm"), source).unwrap();
        fs::write(project.join("binary.dat"), [0, 255, 1]).unwrap();
        let mut notebook = scenario();
        if let Some(path) = workspace {
            notebook["metadata"]["morphir"]["itest"]["workspace"] =
                json!({"kind":"directory","path":path});
            // Only the selected directory is a workspace input.
            fs::write(temp.path().join("morphir.toml"), "invalid TOML {{{").unwrap();
        }
        notebook["cells"][1]["source"] = json!(
            "morphir compile --input Example.elm --extension morphir-elm-native --package-name examples/disk --output installed --json"
        );
        notebook["cells"][1]["metadata"]["morphir"]["itest"]["name"] =
            json!("Compile disk source with notebook additions");
        notebook["cells"][1]["metadata"]["morphir"]["itest"]["captures"] = json!([
            {"name":"ir","path":"installed/morphir-ir.json","format":"json"},
            {"name":"extra","path":"extra.txt","format":"text"},
            {"name":"binary","path":"binary.dat","format":"exists"}
        ]);
        notebook["cells"][2]["source"] = json!(
            "package cli_test\nimport rego.v1\ntest_exit if { input.exitCode == 0; input.artifacts.ir.value.formatVersion == 3; input.artifacts.extra.value == \"notebook addition\"; input.artifacts.binary.kind == \"file\" }"
        );
        notebook["cells"].as_array_mut().unwrap().push(code(
            "extra",
            "notebook addition",
            json!({"file":{"path":"extra.txt","language":"text"}}),
        ));
        write_scenario(temp.path(), &notebook);
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

#[test]
fn itest_rejects_collisions_between_disk_and_notebook_files() {
    for path in ["extra.txt", "EXTRA.txt", "extra.txt/nested"] {
        let temp = tempfile::tempdir().unwrap();
        let mut notebook = scenario();
        notebook["cells"].as_array_mut().unwrap().push(code(
            "extra",
            "notebook contents",
            json!({"file":{"path":path,"language":"text"}}),
        ));
        write_scenario(temp.path(), &notebook);
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
    write_scenario(&suite, &scenario());
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
