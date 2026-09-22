//! Installed-process coverage for the fresh local Library MVP.

use std::path::Path;
use std::process::{Command, Output};

#[path = "../../morphir-mck/tests/support/package_mvp.rs"]
#[allow(dead_code)]
mod fixture;

fn source() -> std::path::PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn initialize(directory: &Path, prepared: &fixture::Prepared) -> Output {
    morphir(
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
    )
}

fn restore(directory: &Path, prepared: &fixture::Prepared) -> Output {
    morphir(
        directory,
        &[
            "package",
            "restore",
            "--policy",
            prepared.policy.to_str().unwrap(),
            "--lock",
            prepared.lock.to_str().unwrap(),
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
    )
}

fn success(output: Output) -> serde_json::Value {
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    serde_json::from_slice(&output.stdout).expect("one JSON result on stdout")
}

fn diagnostic_text(output: &Output) -> String {
    // Miette wraps human diagnostics and decorates continuation lines. Compare
    // the frozen wording independently of terminal width and box drawing.
    String::from_utf8_lossy(&output.stderr)
        .replace(['│', '×'], " ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
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

#[test]
fn package_help_exposes_trust_initialization_and_restore() {
    let workspace = tempfile::tempdir().unwrap();
    for args in [
        vec!["package", "--help"],
        vec!["package", "trust", "init", "--help"],
        vec!["package", "restore", "--help"],
    ] {
        let output = morphir(workspace.path(), &args);
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
    }
    let output = morphir(workspace.path(), &["package", "restore", "--help"]);
    let help = String::from_utf8(output.stdout).unwrap();
    assert!(help.contains("--assurance"), "{help}");
    assert!(help.contains("--lock"), "{help}");
    assert!(help.contains("--registry"), "{help}");
}

#[test]
fn unsupported_assurance_is_rejected_before_opening_package_inputs() {
    let workspace = tempfile::tempdir().unwrap();
    let output = morphir(
        workspace.path(),
        &[
            "package",
            "restore",
            "--policy",
            "absent-policy.json",
            "--lock",
            "absent.lock",
            "--registry",
            "absent-registry",
            "--state",
            "state",
            "--output",
            "restored",
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
    assert!(!workspace.path().join("restored").exists());
}

#[test]
fn fresh_restore_is_consumed_by_another_project_and_replay_preserves_the_lock() {
    let source = source();
    let corpus = fixture::load(&source);
    let case = corpus
        .cases
        .iter()
        .find(|case| case.setup == fixture::Setup::Fresh)
        .unwrap();
    let workspace = tempfile::tempdir().unwrap();
    let mut prepared = fixture::prepare(&source, workspace.path(), case);
    let consumer = workspace.path().join("consumer");
    std::fs::create_dir_all(&consumer).unwrap();
    std::fs::write(
        consumer.join("morphir.toml"),
        "[project]\nname = \"examples/library-consumer\"\nversion = \"0.1.0\"\n",
    )
    .unwrap();
    let lock_before = std::fs::read(&prepared.lock).unwrap();
    let initialized = success(initialize(workspace.path(), &prepared));
    assert_eq!(initialized["profile"], "local-library-mvp");
    let result = success(restore(workspace.path(), &prepared));
    assert_eq!(result["profile"], "local-library-mvp");
    assert_eq!(result["profileVersion"], "0.1.0-draft.1");
    assert_eq!(result["packages"].as_array().unwrap().len(), 2);
    assert_eq!(std::fs::read(&prepared.lock).unwrap(), lock_before);

    let library = prepared
        .output
        .join("example.com/finance/eligibility/1.2.0/ir.json");
    let generated = success(morphir(
        &consumer,
        &[
            "gleam",
            "--json",
            "generate",
            "--input",
            library.to_str().unwrap(),
            "--output",
            "generated",
        ],
    ));
    assert_eq!(generated["success"], true);
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

    // A second fresh authorization must work through timestamp equality without
    // overwriting the first destination or rewriting the lock.
    prepared.output = consumer.join("replayed");
    success(restore(workspace.path(), &prepared));
    assert_eq!(std::fs::read(&prepared.lock).unwrap(), lock_before);
    assert_eq!(
        std::fs::read(
            prepared
                .output
                .join("example.com/finance/eligibility/1.2.0/ir.json")
        )
        .unwrap(),
        std::fs::read(library).unwrap()
    );
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
fn frozen_mvp_cases_execute_through_the_real_cli() {
    let source = source();
    let corpus = fixture::load(&source);
    assert_eq!(corpus.profile, fixture::PROFILE);
    for case in &corpus.cases {
        let workspace = tempfile::tempdir().unwrap();
        let prepared = fixture::prepare(&source, workspace.path(), case);
        let lock_before = std::fs::read(&prepared.lock).unwrap();
        let registry_before = inventory(&prepared.registry);
        if prepared.initialize {
            success(initialize(workspace.path(), &prepared));
        }
        fixture::after_initialize(case, &prepared);
        let output = restore(workspace.path(), &prepared);
        match case.expected {
            fixture::Expected::Restored => {
                let result = success(output);
                let expected = corpus.invariants["successLibraries"].as_array().unwrap();
                let packages = result["packages"].as_array().unwrap();
                assert_eq!(packages.len(), expected.len(), "{}", case.id);
                for library in expected {
                    let matches: Vec<_> = packages
                        .iter()
                        .filter(|package| {
                            package["release"]["packagePath"] == library["packagePath"]
                                && package["release"]["version"] == library["version"]
                        })
                        .collect();
                    assert_eq!(matches.len(), 1, "{}: {library}", case.id);
                    let path = prepared
                        .output
                        .join(matches[0]["directory"].as_str().unwrap());
                    let manifest: serde_json::Value =
                        serde_json::from_slice(&std::fs::read(path.join("manifest.json")).unwrap())
                            .unwrap();
                    assert_eq!(manifest["ir"]["packageName"], library["irPackageName"]);
                    let ir: serde_json::Value =
                        serde_json::from_slice(&std::fs::read(path.join("ir.json")).unwrap())
                            .unwrap();
                    assert_eq!(
                        ir["distribution"]["Library"]["packageName"],
                        library["irPackageName"]
                    );
                }
            }
            fixture::Expected::Refused => {
                assert_eq!(
                    output.status.code(),
                    Some(1),
                    "{}: {}",
                    case.id,
                    String::from_utf8_lossy(&output.stderr)
                );
                let diagnostic = case
                    .diagnostic
                    .as_ref()
                    .expect("each rejection fixes a diagnostic category");
                assert!(
                    diagnostic_text(&output).contains(diagnostic),
                    "{}: {}",
                    case.id,
                    String::from_utf8_lossy(&output.stderr)
                );
                if case.setup == fixture::Setup::OccupiedOutput {
                    assert_eq!(
                        inventory(&prepared.output),
                        [("sentinel.txt".into(), fixture::SENTINEL.to_vec())].into()
                    );
                } else {
                    assert!(!prepared.output.exists(), "{} exposed output", case.id);
                }
            }
        }
        assert_eq!(
            std::fs::read(&prepared.lock).unwrap(),
            lock_before,
            "{} changed lock",
            case.id
        );
        assert_eq!(
            inventory(&prepared.registry),
            registry_before,
            "{} changed registry",
            case.id
        );
    }
}

#[test]
fn failed_restore_remains_unresolved_in_the_next_cli_process() {
    let source = source();
    let corpus = fixture::load(&source);
    let case = corpus
        .cases
        .iter()
        .find(|case| case.setup == fixture::Setup::TamperedSignature)
        .unwrap();
    let workspace = tempfile::tempdir().unwrap();
    let prepared = fixture::prepare(&source, workspace.path(), case);
    success(initialize(workspace.path(), &prepared));
    let failed = restore(workspace.path(), &prepared);
    assert_eq!(failed.status.code(), Some(1));
    assert!(diagnostic_text(&failed).contains(case.diagnostic.as_ref().unwrap()));
    // Repairing registry input must not silently reconcile a failed operation.
    // Each invocation is a new process using the same established trust state.
    for name in ["timestamp.json", "1.timestamp.json"] {
        std::fs::copy(
            source
                .join(fixture::PATH)
                .join("signed/registry/metadata")
                .join(name),
            prepared.registry.join("metadata").join(name),
        )
        .unwrap();
    }
    let retry = restore(workspace.path(), &prepared);
    assert_eq!(retry.status.code(), Some(1));
    assert!(
        String::from_utf8_lossy(&retry.stderr).contains("unresolved"),
        "{}",
        String::from_utf8_lossy(&retry.stderr)
    );
    assert!(!prepared.output.exists());
    let reinitialize = initialize(workspace.path(), &prepared);
    assert_eq!(
        reinitialize.status.code(),
        Some(1),
        "existing trust state must not be reset"
    );
}
