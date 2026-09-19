//! End-to-end tests for `morphir mck check` and the `morphir mck kit`
//! commands: `status`, `vendor` and `update`.
//!
//! The contract is `spec/mck/cli-contract.md`: stdout carries the result,
//! diagnostics go to stderr, 0 is success, 1 a failed check or operational
//! error, 2 a usage error.

use std::path::{Path, PathBuf};
use std::process::Output;

use serde_json::{Value, json};
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

/// The repository root, a finos/morphir checkout.
fn repository_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn json_of(output: &Output) -> Value {
    serde_json::from_str(&stdout(output))
        .unwrap_or_else(|e| panic!("stdout is not JSON ({e}): {}", stdout(output)))
}

fn vendor_embedded(dest: &Path) -> Output {
    morphir(&[
        "mck",
        "kit",
        "vendor",
        "--source",
        "embedded",
        "--dest",
        dest.to_str().unwrap(),
        "--json",
    ])
}

#[test]
fn an_invalid_manifest_is_an_error_never_a_fallback_to_the_raw_kit() {
    let (root, kit) = repository(&[("types.md", GOOD_CASE)]);
    std::fs::write(root.path().join("mck-kit.lock.json"), "{}").unwrap();
    for args in [&["mck", "check"][..], &["mck", "kit", "status", "--kit"]] {
        let output = morphir(&[args, &[kit.to_str().unwrap()]].concat());
        assert_eq!(output.status.code(), Some(1), "{args:?}");
        assert!(
            stderr(&output).contains("mck-kit.lock.json: missing \"lockVersion\""),
            "{}",
            stderr(&output)
        );
        assert_eq!(stdout(&output), "", "{args:?}");
    }
}

#[test]
fn the_embedded_kit_vendors_offline_into_a_new_nested_directory_and_verifies() {
    let work = TempDir::new().unwrap();
    let dest = work.path().join("vendor").join("morphir-mck");
    let output = vendor_embedded(&dest);
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    let vendored = json_of(&output);
    assert_eq!(vendored["outcome"], "created");
    assert_eq!(vendored["source"], "embedded");
    assert!(
        stderr(&output).contains("-text"),
        "the .gitattributes advice goes to stderr"
    );

    // Both the snapshot root and its kit directory resolve to the managed kit.
    for kit in [dest.clone(), dest.join("spec").join("ir").join("mck")] {
        let status = morphir(&[
            "mck",
            "kit",
            "status",
            "--kit",
            kit.to_str().unwrap(),
            "--json",
        ]);
        assert_eq!(status.status.code(), Some(0), "{}", stderr(&status));
        let status = json_of(&status);
        assert_eq!(status["mode"], "vendored");
        assert_eq!(status["snapshotDigest"], vendored["snapshotDigest"]);
        assert_eq!(status["corpusHash"], vendored["corpusHash"]);
        assert_eq!(status["driverContract"], 1);
    }
    let check = morphir(&[
        "mck",
        "check",
        dest.join("spec").join("ir").join("mck").to_str().unwrap(),
    ]);
    assert_eq!(check.status.code(), Some(0), "{}", stderr(&check));

    let again = vendor_embedded(&dest);
    assert_eq!(again.status.code(), Some(0), "{}", stderr(&again));
    assert_eq!(json_of(&again)["outcome"], "unchanged");
    let update = morphir(&[
        "mck",
        "kit",
        "update",
        "--kit",
        dest.to_str().unwrap(),
        "--json",
    ]);
    assert_eq!(update.status.code(), Some(0), "{}", stderr(&update));
    assert_eq!(json_of(&update)["outcome"], "unchanged");
    assert_eq!(
        std::fs::read_dir(work.path().join("vendor"))
            .unwrap()
            .count(),
        1,
        "no staging or backup directory left"
    );
}

#[test]
fn a_checkout_vendors_with_no_revision_and_its_embedded_twin_has_the_same_corpus() {
    let work = TempDir::new().unwrap();
    let from_checkout = work.path().join("checkout");
    let output = morphir(&[
        "mck",
        "kit",
        "vendor",
        "--source",
        repository_root().to_str().unwrap(),
        "--dest",
        from_checkout.to_str().unwrap(),
        "--json",
    ]);
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    let checkout = json_of(&output);
    assert_eq!(
        (&checkout["source"], &checkout["revision"]),
        (&json!("local"), &Value::Null)
    );

    let embedded = json_of(&vendor_embedded(&work.path().join("embedded")));
    assert_eq!(checkout["corpusHash"], embedded["corpusHash"]);
    assert_eq!(
        checkout["snapshotDigest"], embedded["snapshotDigest"],
        "same bytes, same digest, whatever the source"
    );
}

#[test]
fn an_edited_snapshot_fails_check_status_and_update_naming_the_file() {
    let work = TempDir::new().unwrap();
    let dest = work.path().join("kit");
    assert_eq!(vendor_embedded(&dest).status.code(), Some(0));
    let types = dest.join("spec").join("ir").join("mck").join("types.md");
    let original = std::fs::read(&types).unwrap();
    std::fs::write(&types, [original.as_slice(), b"\n"].concat()).unwrap();
    std::fs::write(
        dest.join("spec").join("ir").join("mck").join("mine.md"),
        "## mine-0001: m\n",
    )
    .unwrap();

    for args in [
        vec![
            "mck",
            "check",
            dest.join("spec").join("ir").join("mck").to_str().unwrap(),
        ],
        vec!["mck", "kit", "status", "--kit", dest.to_str().unwrap()],
        vec!["mck", "kit", "update", "--kit", dest.to_str().unwrap()],
    ] {
        let output = morphir(&args.iter().map(|s| &**s).collect::<Vec<_>>());
        assert_eq!(output.status.code(), Some(1), "{args:?}");
        let diagnostics = stderr(&output);
        assert!(
            diagnostics.contains("altered: spec/ir/mck/types.md"),
            "{args:?}: {diagnostics}"
        );
        assert!(
            diagnostics.contains("not in the manifest: spec/ir/mck/mine.md"),
            "{args:?}: {diagnostics}"
        );
        assert_eq!(stdout(&output), "", "{args:?}");
    }
    assert!(
        std::fs::read(&types).unwrap().ends_with(b"\n\n"),
        "update left the edit alone"
    );
}

#[test]
fn a_snapshot_for_another_driver_contract_is_refused_before_use() {
    let work = TempDir::new().unwrap();
    let dest = work.path().join("kit");
    assert_eq!(vendor_embedded(&dest).status.code(), Some(0));
    let manifest = dest.join("mck-kit.lock.json");
    let text = std::fs::read_to_string(&manifest).unwrap();
    std::fs::write(&manifest, text.replace(">=1, <2", ">=2, <3")).unwrap();
    let output = morphir(&["mck", "check", dest.to_str().unwrap()]);
    assert_eq!(output.status.code(), Some(1));
    assert!(
        stderr(&output)
            .contains("supports driver contract >=2, <3; this CLI implements contract 1"),
        "{}",
        stderr(&output)
    );
}

#[test]
fn vendor_refuses_unrelated_content_and_a_wrong_expected_digest_without_writing() {
    let work = TempDir::new().unwrap();
    let busy = work.path().join("busy");
    std::fs::create_dir(&busy).unwrap();
    std::fs::write(busy.join("mine.txt"), "keep").unwrap();
    let output = vendor_embedded(&busy);
    assert_eq!(output.status.code(), Some(1));
    assert!(
        stderr(&output).contains("is not empty"),
        "{}",
        stderr(&output)
    );
    assert_eq!(std::fs::read_dir(&busy).unwrap().count(), 1);

    let dest = work.path().join("kit");
    let wrong = format!("sha256-{}", "0".repeat(64));
    let output = morphir(&[
        "mck",
        "kit",
        "vendor",
        "--source",
        "embedded",
        "--expect-digest",
        &wrong,
        "--dest",
        dest.to_str().unwrap(),
    ]);
    assert_eq!(output.status.code(), Some(1));
    assert!(
        stderr(&output).contains("nothing was written"),
        "{}",
        stderr(&output)
    );
    assert!(!dest.exists());
    assert_eq!(
        std::fs::read_dir(work.path()).unwrap().count(),
        1,
        "only the busy directory"
    );
}

#[test]
fn source_and_revision_mistakes_are_usage_errors_before_anything_happens() {
    let work = TempDir::new().unwrap();
    let dest = work.path().join("kit");
    let dest = dest.to_str().unwrap();
    let full = "a2803f2cbfbb9baffe8a939e9462b18fd5bcdda0";
    for (args, expected) in [
        (
            vec!["--source", "embedded", "--revision", full],
            "--revision applies only to --source github:finos/morphir",
        ),
        (vec!["--source", "github:finos/morphir"], "needs --revision"),
        (
            vec!["--source", "github:finos/morphir", "--revision", "a2803f2"],
            "not a full 40-character",
        ),
        (
            vec!["--source", "github:finos/morphir", "--revision", "main"],
            "branches, tags and short ids are not accepted",
        ),
        (
            vec!["--source", "github:someone/fork", "--revision", full],
            "only github:finos/morphir is supported",
        ),
        (
            vec!["--source", "embedded", "--expect-digest", "abc"],
            "--expect-digest:",
        ),
    ] {
        let output = morphir(&[&["mck", "kit", "vendor", "--dest", dest][..], &args].concat());
        assert_eq!(
            output.status.code(),
            Some(2),
            "{args:?}: {}",
            stderr(&output)
        );
        assert!(
            stderr(&output).contains(expected),
            "{args:?}: {}",
            stderr(&output)
        );
        assert_eq!(stdout(&output), "", "{args:?}");
    }
    assert_eq!(
        std::fs::read_dir(work.path()).unwrap().count(),
        0,
        "nothing was created"
    );
}

#[test]
fn update_from_a_local_snapshot_needs_its_source_named() {
    let work = TempDir::new().unwrap();
    let dest = work.path().join("kit");
    let output = morphir(&[
        "mck",
        "kit",
        "vendor",
        "--source",
        repository_root().to_str().unwrap(),
        "--dest",
        dest.to_str().unwrap(),
    ]);
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    let output = morphir(&["mck", "kit", "update", "--kit", dest.to_str().unwrap()]);
    assert_eq!(output.status.code(), Some(1));
    assert!(
        stderr(&output).contains("name it again with --source <path>"),
        "{}",
        stderr(&output)
    );

    let output = morphir(&[
        "mck",
        "kit",
        "update",
        "--kit",
        dest.to_str().unwrap(),
        "--source",
        repository_root().to_str().unwrap(),
    ]);
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    assert!(
        stdout(&output).contains("is already the snapshot"),
        "{}",
        stdout(&output)
    );
}
