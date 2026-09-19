//! End-to-end tests for `morphir mck check` and `morphir mck kit status`.
//!
//! The contract is `spec/mck/cli-contract.md`: stdout carries the result,
//! diagnostics go to stderr, 0 is success, 1 a failed check or operational
//! error, 2 a usage error.

use std::path::{Path, PathBuf};
use std::process::Output;

use serde_json::Value;
use tempfile::TempDir;

fn morphir(args: &[&str]) -> Output {
    let mut command = std::process::Command::new(env!("CARGO_BIN_EXE_morphir"));
    command.env("MORPHIR_LOG_FILE", "false");
    command.env_remove("MORPHIR_LOG_DIR");
    command.env_remove("MORPHIR_OUT_DIR");
    command.args(args).output().expect("morphir runs")
}

fn stdout(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).into_owned()
}

fn stderr(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

fn repository_kit() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/ir/mck")
}

/// A repository holding a kit at `spec/ir/mck` with the given case files.
fn repository(files: &[(&str, &str)]) -> (TempDir, PathBuf) {
    let root = TempDir::new().unwrap();
    let kit = root.path().join("spec").join("ir").join("mck");
    std::fs::create_dir_all(&kit).unwrap();
    for (name, text) in files {
        std::fs::write(kit.join(name), text).unwrap();
    }
    (root, kit)
}

const GOOD_CASE: &str = "## types-0001: Unit\n```yaml canonical\nUnit: {}\n```\n";

#[test]
fn check_accepts_the_repository_kit_and_summarises_on_stdout() {
    let output = morphir(&["mck", "check", repository_kit().to_str().unwrap()]);
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    let summary = stdout(&output);
    assert!(
        summary.trim_end().ends_with("file(s), 0 error(s)"),
        "{summary}"
    );
    assert_eq!(
        summary.lines().count(),
        1,
        "stdout carries only the summary: {summary}"
    );
}

#[test]
fn check_reports_errors_on_stderr_with_locations_and_exits_1() {
    let (_root, kit) = repository(&[(
        "types.md",
        "## types-1: bad id\n\n## types-0002: open\n```yaml canonical\na: 1\n",
    )]);
    let output = morphir(&["mck", "check", kit.to_str().unwrap()]);
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(
        stdout(&output).trim_end(),
        "1 case(s) in 1 file(s), 3 error(s)"
    );

    let diagnostics = stderr(&output);
    let file = kit.join("types.md").display().to_string();
    assert!(
        diagnostics.contains(&format!(
            "{file}:1: malformed case id in heading \"types-1: bad id\""
        )),
        "{diagnostics}"
    );
    assert!(
        diagnostics.contains(&format!("{file}:4: unterminated fence")),
        "{diagnostics}"
    );
    assert!(
        diagnostics.contains(&format!("{file}:3: case has no data fences (types-0002)")),
        "{diagnostics}"
    );
    assert!(
        !stdout(&output).contains("malformed"),
        "diagnostics stay off stdout"
    );
}

#[test]
fn check_json_is_tab_indented_machine_output_on_stdout_only() {
    let (_root, kit) = repository(&[
        ("types.md", GOOD_CASE),
        ("values.md", "## values-0001: v {status=done}\n"),
    ]);
    let output = morphir(&["mck", "check", kit.to_str().unwrap(), "--json"]);
    assert_eq!(output.status.code(), Some(1));
    let text = stdout(&output);
    assert!(text.starts_with("{\n\t\"files\": ["), "{text}");
    let payload: Value = serde_json::from_str(&text).expect("stdout is exactly one JSON document");
    assert_eq!(
        payload["files"],
        serde_json::json!(["spec/ir/mck/types.md", "spec/ir/mck/values.md"])
    );
    assert_eq!(
        payload["cases"],
        serde_json::json!(["types-0001", "values-0001"])
    );
    let messages: Vec<&str> = payload["errors"]
        .as_array()
        .unwrap()
        .iter()
        .map(|e| e["message"].as_str().unwrap())
        .collect();
    assert_eq!(
        messages,
        vec![
            "status must be pending, got \"done\"",
            "case has no data fences (values-0001)"
        ]
    );
    assert!(
        !stderr(&output).contains("status must be pending"),
        "with --json the errors are in the payload"
    );
}

#[test]
fn check_confines_text_fixtures_to_the_repository() {
    let case = |target: &str| format!("## types-0001: fixture\n```text canonical\n{target}\n```\n");
    let (root, kit) = repository(&[("types.md", &case("fixtures/a.json"))]);
    std::fs::create_dir_all(root.path().join("fixtures")).unwrap();
    std::fs::write(root.path().join("fixtures").join("a.json"), "{}").unwrap();
    assert_eq!(
        morphir(&["mck", "check", kit.to_str().unwrap()])
            .status
            .code(),
        Some(0)
    );

    let outside = root
        .path()
        .parent()
        .unwrap()
        .join("mck-outside-fixture.json");
    std::fs::write(&outside, "{}").unwrap();
    std::fs::write(kit.join("types.md"), case("../mck-outside-fixture.json")).unwrap();
    let output = morphir(&["mck", "check", kit.to_str().unwrap()]);
    std::fs::remove_file(&outside).ok();
    assert_eq!(output.status.code(), Some(1));
    assert!(
        stderr(&output).contains(
            "text fence names ../mck-outside-fixture.json, which is not in the kit source"
        ),
        "{}",
        stderr(&output)
    );
}

#[test]
fn a_missing_kit_directory_is_an_operational_error() {
    let output = morphir(&["mck", "check", "no-such-kit-directory"]);
    assert_eq!(output.status.code(), Some(1));
    assert!(
        stderr(&output).contains("error: cannot read kit no-such-kit-directory"),
        "{}",
        stderr(&output)
    );
    assert_eq!(stdout(&output), "");
}

#[test]
fn usage_errors_exit_2_before_doing_anything() {
    for args in [
        &["mck"][..],
        &["mck", "kit"],
        &["mck", "check"],
        &["mck", "check", "a", "--bogus"],
    ] {
        let output = morphir(args);
        assert_eq!(output.status.code(), Some(2), "{args:?}");
        assert_eq!(stdout(&output), "", "{args:?}: usage goes to stderr");
    }
}

#[test]
fn kit_status_identifies_the_embedded_kit_offline() {
    let output = morphir(&["mck", "kit", "status", "--json"]);
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    let status: Value = serde_json::from_str(&stdout(&output)).unwrap();
    assert_eq!(status["mode"], "embedded");
    assert_eq!(status["algorithm"], "mck-file-map-sha256/1");
    assert_eq!(status["errors"], 0);
    let hash = status["corpusHash"].as_str().unwrap();
    assert!(hash.starts_with("sha256-") && hash.len() == 71, "{hash}");
    if let Some(revision) = status["revision"].as_str() {
        assert_eq!(revision.len(), 40);
    }
}

#[test]
fn kit_status_reports_an_unedited_checkout_as_matching_and_an_edited_kit_as_modified() {
    let embedded: Value =
        serde_json::from_str(&stdout(&morphir(&["mck", "kit", "status", "--json"]))).unwrap();
    let checkout = morphir(&[
        "mck",
        "kit",
        "status",
        "--kit",
        repository_kit().to_str().unwrap(),
        "--json",
    ]);
    let checkout: Value = serde_json::from_str(&stdout(&checkout)).unwrap();
    assert_eq!(checkout["mode"], "local");
    assert_eq!(checkout["modified"], false);
    assert_eq!(checkout["corpusHash"], embedded["corpusHash"]);

    let (_root, kit) = repository(&[("types.md", GOOD_CASE)]);
    let edited = morphir(&[
        "mck",
        "kit",
        "status",
        "--kit",
        kit.to_str().unwrap(),
        "--json",
    ]);
    assert_eq!(edited.status.code(), Some(0));
    let edited: Value = serde_json::from_str(&stdout(&edited)).unwrap();
    assert_eq!(edited["modified"], true);
    assert_eq!(
        edited["revision"],
        Value::Null,
        "a modified kit never claims an upstream revision"
    );
}

#[test]
fn kit_status_fails_for_a_kit_with_errors() {
    let (_root, kit) = repository(&[("types.md", "## types-1: bad id\n")]);
    let output = morphir(&["mck", "kit", "status", "--kit", kit.to_str().unwrap()]);
    assert_eq!(output.status.code(), Some(1));
    assert!(
        stdout(&output).contains("corpus hash: none; the kit has errors"),
        "{}",
        stdout(&output)
    );
}

#[test]
fn a_managed_snapshot_is_refused_rather_than_read_as_a_raw_kit() {
    let (root, kit) = repository(&[("types.md", GOOD_CASE)]);
    std::fs::write(root.path().join("mck-kit.lock.json"), "{}").unwrap();
    for args in [&["mck", "check"][..], &["mck", "kit", "status", "--kit"]] {
        let output = morphir(&[args, &[kit.to_str().unwrap()]].concat());
        assert_eq!(output.status.code(), Some(1), "{args:?}");
        assert!(
            stderr(&output).contains("holds a managed kit snapshot (mck-kit.lock.json)"),
            "{}",
            stderr(&output)
        );
        assert_eq!(stdout(&output), "", "{args:?}");
    }
}
