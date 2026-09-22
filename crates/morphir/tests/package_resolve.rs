//! Real-process acceptance for authenticated resolution and complete lock output.
use std::path::Path;
use std::process::{Command, Output};

#[path = "../../morphir-mck/tests/support/package_resolve.rs"]
#[allow(dead_code)]
mod resolve_fixture;
use resolve_fixture::mvp as fixture;

const ROOT: &str = "example.com/finance/loan-rules@1.0.0";

fn source() -> std::path::PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn morphir(directory: &Path, args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_morphir"))
        .current_dir(directory)
        .env("MORPHIR_HOME", directory.join("home"))
        .env("MORPHIR_LOG_FILE", "false")
        .env_remove("MORPHIR_LOG_DIR")
        .env_remove("MORPHIR_OUT_DIR")
        .arg("--no-banner")
        .args(args)
        .output()
        .expect("Morphir runs")
}

fn success(output: Output) -> serde_json::Value {
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    serde_json::from_slice(&output.stdout).expect("one JSON result")
}

fn initialize(directory: &Path, prepared: &fixture::Prepared) {
    success(morphir(
        directory,
        &[
            "package",
            "trust",
            "init",
            "--policy",
            prepared.initialization_policy.to_str().unwrap(),
            "--root",
            prepared.root.to_str().unwrap(),
            "--state",
            prepared.state.to_str().unwrap(),
            "--json",
        ],
    ));
}

fn resolve(directory: &Path, prepared: &fixture::Prepared, root: &str, output: &Path) -> Output {
    morphir(
        directory,
        &[
            "package",
            "resolve",
            "--root",
            root,
            "--policy",
            prepared.policy.to_str().unwrap(),
            "--registry",
            prepared.registry.to_str().unwrap(),
            "--state",
            prepared.state.to_str().unwrap(),
            "--output",
            output.to_str().unwrap(),
            "--assurance",
            "portable",
            "--json",
        ],
    )
}

#[test]
fn package_resolve_help_describes_exact_root_and_new_lock_output() {
    let workspace = tempfile::tempdir().unwrap();
    let output = morphir(workspace.path(), &["package", "resolve", "--help"]);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let help = String::from_utf8(output.stdout).unwrap();
    for flag in [
        "--root",
        "--policy",
        "--registry",
        "--state",
        "--output",
        "--assurance",
    ] {
        assert!(help.contains(flag), "{help}");
    }
}

#[test]
fn malformed_root_is_rejected_before_opening_inputs() {
    let workspace = tempfile::tempdir().unwrap();
    for root in [
        "example.com/finance/loan-rules",
        "../escape@1.0.0",
        "example.com/finance/loan-rules@latest",
    ] {
        let output = morphir(
            workspace.path(),
            &[
                "package",
                "resolve",
                "--root",
                root,
                "--policy",
                "absent.json",
                "--registry",
                "absent",
                "--state",
                "state",
                "--output",
                "new.lock",
                "--assurance",
                "portable",
            ],
        );
        assert_eq!(output.status.code(), Some(2));
        let error = String::from_utf8_lossy(&output.stderr);
        assert!(
            error.contains("invalid value") && error.contains("--root"),
            "{error}"
        );
        assert!(!workspace.path().join("state").exists());
        assert!(!workspace.path().join("new.lock").exists());
    }
}

#[test]
fn unsupported_resolve_assurance_is_rejected_before_opening_inputs() {
    let workspace = tempfile::tempdir().unwrap();
    let output = morphir(
        workspace.path(),
        &[
            "package",
            "resolve",
            "--root",
            ROOT,
            "--policy",
            "absent.json",
            "--registry",
            "absent",
            "--state",
            "state",
            "--output",
            "new.lock",
            "--assurance",
            "hardened",
        ],
    );
    assert_eq!(output.status.code(), Some(2));
    let error = String::from_utf8_lossy(&output.stderr);
    assert!(
        error.contains("hardened") && error.contains("portable"),
        "{error}"
    );
    assert!(!workspace.path().join("state").exists());
    assert!(!workspace.path().join("new.lock").exists());
}

#[test]
fn resolved_lock_is_deterministic_and_restores_usable_libraries() {
    let source = source();
    let corpus = fixture::load(&source);
    let case = corpus
        .cases
        .iter()
        .find(|case| case.setup == fixture::Setup::Fresh)
        .unwrap();
    let workspace = tempfile::tempdir().unwrap();
    let prepared = fixture::prepare(&source, workspace.path(), case);
    let input_lock = std::fs::read(&prepared.lock).unwrap();
    initialize(workspace.path(), &prepared);
    let generated_lock = workspace.path().join("consumer/morphir.lock");
    let result = success(resolve(workspace.path(), &prepared, ROOT, &generated_lock));
    assert_eq!(result["profile"], "local-library-mvp");
    assert_eq!(result["profileVersion"], "0.1.0-draft.1");
    assert_eq!(
        result["graph"]["root"]["packagePath"],
        "example.com/finance/loan-rules"
    );
    assert_eq!(result["packages"].as_array().unwrap().len(), 2);
    let expected = std::fs::read(
        source
            .join(fixture::PATH)
            .join("expected/resolve.lock.json"),
    )
    .unwrap();
    assert_eq!(std::fs::read(&generated_lock).unwrap(), expected);
    let second_lock = workspace.path().join("consumer/second.lock");
    success(resolve(workspace.path(), &prepared, ROOT, &second_lock));
    assert_eq!(std::fs::read(second_lock).unwrap(), expected);
    success(morphir(
        workspace.path(),
        &[
            "package",
            "restore",
            "--policy",
            prepared.policy.to_str().unwrap(),
            "--lock",
            generated_lock.to_str().unwrap(),
            "--registry",
            prepared.registry.to_str().unwrap(),
            "--state",
            prepared.state.to_str().unwrap(),
            "--output",
            prepared.output.to_str().unwrap(),
            "--assurance",
            "portable",
            "--json",
        ],
    ));
    let consumer = workspace.path().join("consumer");
    std::fs::write(
        consumer.join("morphir.toml"),
        "[project]\nname = \"examples/library-consumer\"\nversion = \"0.1.0\"\n",
    )
    .unwrap();
    let provider = prepared
        .output
        .join("example.com/finance/eligibility/1.2.0/ir.json");
    success(morphir(
        &consumer,
        &[
            "gleam",
            "--json",
            "generate",
            "--input",
            provider.to_str().unwrap(),
            "--output",
            "generated",
        ],
    ));
    assert_eq!(
        std::fs::read(consumer.join("generated/decision.gleam")).unwrap(),
        std::fs::read(source.join(fixture::PATH).join("expected/decision.gleam")).unwrap()
    );
    let compiled = success(morphir(
        &consumer,
        &[
            "gleam",
            "--json",
            "compile",
            "--input",
            "generated",
            "--output",
            "compiled",
        ],
    ));
    assert_eq!(compiled["success"], true);
    assert_eq!(
        compiled["ir"]["distribution"]["Library"]["packageName"],
        "examples/library-consumer"
    );
    assert_eq!(std::fs::read(generated_lock).unwrap(), expected);
    assert_eq!(std::fs::read(prepared.lock).unwrap(), input_lock);
}

fn inventory(root: &Path) -> std::collections::BTreeMap<std::path::PathBuf, Vec<u8>> {
    walkdir::WalkDir::new(root)
        .into_iter()
        .map(Result::unwrap)
        .filter(|entry| entry.file_type().is_file())
        .map(|entry| {
            (
                entry.path().strip_prefix(root).unwrap().to_owned(),
                std::fs::read(entry.path()).unwrap(),
            )
        })
        .collect()
}

#[test]
fn frozen_resolve_cases_execute_without_mutating_inputs_or_exposing_failed_locks() {
    let source = source();
    let corpus = resolve_fixture::load(&source);
    assert_eq!(corpus.profile, fixture::PROFILE);
    let expected = std::fs::read(source.join(resolve_fixture::EXPECTED_LOCK)).unwrap();
    for case in &corpus.cases {
        let workspace = tempfile::tempdir().unwrap();
        let prepared = resolve_fixture::prepare(&source, workspace.path(), case);
        let before = inventory(&prepared.restore.registry);
        let input_lock = std::fs::read(&prepared.restore.lock).unwrap();
        if prepared.restore.initialize {
            initialize(workspace.path(), &prepared.restore);
        }
        resolve_fixture::after_initialize(case, &prepared);
        let result = resolve(
            workspace.path(),
            &prepared.restore,
            &prepared.root,
            &prepared.output,
        );
        match case.expected {
            resolve_fixture::Expected::Resolved => {
                let report = success(result);
                assert_eq!(
                    report["packages"].as_array().unwrap().len(),
                    2,
                    "{}",
                    case.id
                );
                assert_eq!(
                    std::fs::read(&prepared.output).unwrap(),
                    expected,
                    "{}",
                    case.id
                );
            }
            resolve_fixture::Expected::Refused => {
                let text = String::from_utf8_lossy(&result.stderr)
                    .replace(['│', '×'], " ")
                    .split_whitespace()
                    .collect::<Vec<_>>()
                    .join(" ");
                assert_eq!(result.status.code(), Some(1), "{}: {text}", case.id);
                assert!(
                    text.contains(case.diagnostic.as_ref().unwrap()),
                    "{}: {text}",
                    case.id
                );
                if case.setup == fixture::Setup::OccupiedOutput {
                    assert_eq!(std::fs::read(&prepared.output).unwrap(), fixture::SENTINEL);
                } else {
                    assert!(!prepared.output.exists(), "{} exposed a lock", case.id);
                }
            }
        }
        assert_eq!(
            inventory(&prepared.restore.registry),
            before,
            "{} changed registry",
            case.id
        );
        assert_eq!(
            std::fs::read(prepared.restore.lock).unwrap(),
            input_lock,
            "{} changed input lock",
            case.id
        );
    }
}

#[test]
fn failed_resolve_cannot_be_silently_retried_after_input_repair() {
    let source = source();
    let corpus = resolve_fixture::load(&source);
    let case = corpus
        .cases
        .iter()
        .find(|case| case.setup == fixture::Setup::TamperedContent)
        .unwrap();
    let workspace = tempfile::tempdir().unwrap();
    let prepared = resolve_fixture::prepare(&source, workspace.path(), case);
    initialize(workspace.path(), &prepared.restore);
    let failed = resolve(
        workspace.path(),
        &prepared.restore,
        &prepared.root,
        &prepared.output,
    );
    assert_eq!(failed.status.code(), Some(1));
    assert!(!prepared.output.exists());
    let lock: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&prepared.restore.lock).unwrap()).unwrap();
    let bundle = lock["acquisitions"][0]["source"]["path"].as_str().unwrap();
    std::fs::copy(
        source
            .join(fixture::PATH)
            .join("signed/registry")
            .join(bundle)
            .join("ir.json"),
        prepared.restore.registry.join(bundle).join("ir.json"),
    )
    .unwrap();
    let retry = resolve(
        workspace.path(),
        &prepared.restore,
        &prepared.root,
        &prepared.output,
    );
    assert_eq!(retry.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&retry.stderr).contains("unresolved"));
    assert!(!prepared.output.exists());
}
