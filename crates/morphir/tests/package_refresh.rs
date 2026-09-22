//! Real-process acceptance for explicit metadata-only registry refresh.
use std::path::Path;
use std::process::{Command, Output};

#[path = "../../morphir-mck/tests/support/package_refresh.rs"]
#[allow(dead_code)]
mod refresh_fixture;
use refresh_fixture::mvp as fixture;

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
    serde_json::from_slice(&output.stdout).expect("one JSON receipt")
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

fn refresh(directory: &Path, prepared: &fixture::Prepared) -> Output {
    morphir(
        directory,
        &[
            "package",
            "refresh",
            "--policy",
            prepared.policy.to_str().unwrap(),
            "--registry",
            prepared.registry.to_str().unwrap(),
            "--state",
            prepared.state.to_str().unwrap(),
            "--assurance",
            "portable",
            "--json",
        ],
    )
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
fn refresh_help_describes_metadata_inputs_without_package_outputs() {
    let directory = tempfile::tempdir().unwrap();
    let output = morphir(directory.path(), &["package", "refresh", "--help"]);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let help = String::from_utf8(output.stdout).unwrap();
    for flag in ["--policy", "--registry", "--state", "--assurance", "--json"] {
        assert!(help.contains(flag), "{help}");
    }
    for flag in ["--lock", "--output", "--root"] {
        assert!(!help.contains(flag), "{help}");
    }
}

#[test]
fn unsupported_refresh_assurance_refuses_before_io() {
    let directory = tempfile::tempdir().unwrap();
    let output = morphir(
        directory.path(),
        &[
            "package",
            "refresh",
            "--policy",
            "missing.json",
            "--registry",
            "missing-registry",
            "--state",
            "state",
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
    assert!(!directory.path().join("state").exists());
}

#[test]
fn refresh_repeats_without_reading_locks_or_exposing_packages() {
    let source = source();
    let corpus = fixture::load(&source);
    let case = corpus
        .cases
        .iter()
        .find(|case| case.setup == fixture::Setup::Fresh)
        .unwrap();
    let directory = tempfile::tempdir().unwrap();
    let prepared = fixture::prepare(&source, directory.path(), case);
    // Refresh accepts no lock input and must not interpret a coincident local file.
    std::fs::write(&prepared.lock, b"deliberately invalid package lock\n").unwrap();
    let lock = std::fs::read(&prepared.lock).unwrap();
    let registry = inventory(&prepared.registry);
    initialize(directory.path(), &prepared);
    let first = success(refresh(directory.path(), &prepared));
    let expected: serde_json::Value = serde_json::from_slice(
        &std::fs::read(source.join(refresh_fixture::EXPECTED_RECEIPT)).unwrap(),
    )
    .unwrap();
    assert_eq!(first, expected);
    assert_eq!(success(refresh(directory.path(), &prepared)), first);
    assert_eq!(std::fs::read(&prepared.lock).unwrap(), lock);
    assert_eq!(inventory(&prepared.registry), registry);
    assert!(!prepared.output.exists());
}

#[test]
fn fixed_refresh_cases_preserve_inputs_and_do_not_authorize_damaged_packages() {
    let source = source();
    let corpus = refresh_fixture::load(&source);
    let expected: serde_json::Value = serde_json::from_slice(
        &std::fs::read(source.join(refresh_fixture::EXPECTED_RECEIPT)).unwrap(),
    )
    .unwrap();
    for case in &corpus.cases {
        let directory = tempfile::tempdir().unwrap();
        let prepared = refresh_fixture::prepare(&source, directory.path(), case);
        let lock = std::fs::read(&prepared.lock).unwrap();
        let registry = inventory(&prepared.registry);
        if prepared.initialize {
            initialize(directory.path(), &prepared);
        }
        refresh_fixture::after_initialize(case, &prepared);
        let output = refresh(directory.path(), &prepared);
        match case.expected {
            refresh_fixture::Expected::Refreshed => {
                assert_eq!(success(output), expected, "{}", case.id);
                if case.setup != refresh_fixture::Setup::Fresh {
                    let restore = morphir(
                        directory.path(),
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
                    );
                    assert_eq!(
                        restore.status.code(),
                        Some(1),
                        "{}: refresh cannot authorize damaged packages",
                        case.id
                    );
                    assert!(
                        restore.stdout.is_empty(),
                        "{} exposed a success receipt",
                        case.id
                    );
                }
            }
            refresh_fixture::Expected::Refused => {
                let error = String::from_utf8_lossy(&output.stderr)
                    .replace(['│', '×'], " ")
                    .split_whitespace()
                    .collect::<Vec<_>>()
                    .join(" ");
                assert_eq!(output.status.code(), Some(1), "{}: {error}", case.id);
                assert!(
                    error.contains(case.diagnostic.as_ref().unwrap()),
                    "{}: {error}",
                    case.id
                );
                assert!(
                    output.stdout.is_empty(),
                    "{} exposed a success receipt",
                    case.id
                );
            }
        }
        assert_eq!(
            std::fs::read(&prepared.lock).unwrap(),
            lock,
            "{} changed lock",
            case.id
        );
        assert_eq!(
            inventory(&prepared.registry),
            registry,
            "{} changed registry",
            case.id
        );
        assert!(!prepared.output.exists(), "{} exposed packages", case.id);
    }
}

#[test]
fn failed_refresh_remains_refused_after_signature_repair_in_a_new_process() {
    let source = source();
    let corpus = refresh_fixture::load(&source);
    let case = corpus
        .cases
        .iter()
        .find(|case| case.setup == refresh_fixture::Setup::TamperedSignature)
        .unwrap();
    let directory = tempfile::tempdir().unwrap();
    let prepared = refresh_fixture::prepare(&source, directory.path(), case);
    initialize(directory.path(), &prepared);
    assert_eq!(refresh(directory.path(), &prepared).status.code(), Some(1));
    for file in ["timestamp.json", "1.timestamp.json"] {
        std::fs::copy(
            source
                .join(fixture::PATH)
                .join("signed/registry/metadata")
                .join(file),
            prepared.registry.join("metadata").join(file),
        )
        .unwrap();
    }
    let retry = refresh(directory.path(), &prepared);
    assert_eq!(retry.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&retry.stderr).contains("unresolved"));
    assert!(retry.stdout.is_empty());
    assert!(!prepared.output.exists());
}
