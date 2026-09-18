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
    Command::new(env!("CARGO_BIN_EXE_morphir"))
        .arg("itest")
        .arg(root)
        .args(args)
        .env("MORPHIR_HOME", root.join("outer-home"))
        .env("MORPHIR_LOG_FILE", "false")
        .output()
        .unwrap()
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
fn itest_runs_the_checked_in_elm_example_and_failure_fixture() {
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
        assert!(String::from_utf8_lossy(&output.stdout).contains("1 passed; 0 failed"));
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
    notebook["cells"][1]["source"] = json!("morphir config show --json");
    notebook["cells"][2]["source"] =
        json!("package cli_test\nimport rego.v1\ntest_exit if { input.exitCode == 0 }");
    notebook["cells"].as_array_mut().unwrap().push(code(
        "config",
        "[project]\nname = 'isolated'\nversion = '1.0.0'\nsource_directory = 'src'\n",
        json!({"file":{"path":".morphir/morphir.toml","language":"toml"}}),
    ));
    write_scenario(&example, &notebook);
    // Neighboring files are deliberately not workspace inputs.
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
