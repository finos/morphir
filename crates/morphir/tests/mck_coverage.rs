//! Acceptance tests for the native IR vocabulary coverage command.

use std::path::{Path, PathBuf};
use std::process::Output;
use tempfile::TempDir;

fn morphir(args: &[&str]) -> Output {
    std::process::Command::new(env!("CARGO_BIN_EXE_morphir"))
        .env("MORPHIR_LOG_FILE", "false")
        .env_remove("MORPHIR_LOG_DIR")
        .env_remove("MORPHIR_OUT_DIR")
        .args(args)
        .output()
        .expect("morphir runs")
}

const VOCABULARY: &str = r#"{
    "vocabularyVersion": 1, "irVersion": 4, "description": "fixture",
    "nodes": ["Type"], "aliases": {}, "entries": [
        {"node":"Type", "variant":"Unit", "members":[]},
        {"node":"Type", "variant":"Function", "members":[]}
    ]
}"#;
const UNIT_CASE: &str = "## types-0001: Unit {node=Type}\n```json canonical\n{\"Unit\":{}}\n```\n";

fn repository() -> (TempDir, PathBuf) {
    let root = TempDir::new().unwrap();
    let kit = root.path().join("spec/ir/mck");
    std::fs::create_dir_all(&kit).unwrap();
    std::fs::create_dir_all(root.path().join("spec/mck")).unwrap();
    std::fs::write(kit.join("types.md"), UNIT_CASE).unwrap();
    std::fs::write(root.path().join("spec/mck/vocabulary.json"), VOCABULARY).unwrap();
    (root, kit)
}

#[test]
fn missing_variant_is_a_gap_on_stdout_and_exit_one() {
    let (_root, kit) = repository();
    let output = morphir(&["mck", "coverage", "--kit", kit.to_str().unwrap()]);
    assert_eq!(output.status.code(), Some(1), "{:?}", output);
    assert_eq!(output.stdout, b"Type/Function has no case\n");
    assert!(
        String::from_utf8_lossy(&output.stderr)
            .lines()
            .all(|line| line.starts_with("Operation ID: ")),
        "{:?}",
        output
    );
}

#[test]
fn embedded_and_repository_kits_have_complete_coverage() {
    let kit = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/ir/mck");
    for args in [
        vec!["mck", "coverage"],
        vec!["mck", "coverage", "--kit", kit.to_str().unwrap()],
    ] {
        let output = morphir(&args);
        assert_eq!(output.status.code(), Some(0), "{:?}", output);
        assert_eq!(
            output.stdout,
            b"coverage: every vocabulary entry has a case\n"
        );
        assert!(
            String::from_utf8_lossy(&output.stderr)
                .lines()
                .all(|line| line.starts_with("Operation ID: ")),
            "{:?}",
            output
        );
    }
}

#[test]
fn standalone_kit_uses_explicit_repository_root() {
    let (root, kit) = repository();
    let standalone = root.path().join("standalone");
    std::fs::rename(&kit, &standalone).unwrap();
    let output = morphir(&[
        "mck",
        "coverage",
        "--kit",
        standalone.to_str().unwrap(),
        "--repo-root",
        root.path().to_str().unwrap(),
    ]);
    assert_eq!(output.status.code(), Some(1), "{:?}", output);
    assert_eq!(output.stdout, b"Type/Function has no case\n");
    assert!(
        String::from_utf8_lossy(&output.stderr)
            .lines()
            .all(|line| line.starts_with("Operation ID: ")),
        "{:?}",
        output
    );
}

#[test]
fn missing_or_invalid_vocabulary_is_an_operational_error() {
    let (root, kit) = repository();
    for invalid in [
        "{",
        "{}",
        &VOCABULARY.replace("\"vocabularyVersion\": 1", "\"vocabularyVersion\": 2"),
    ] {
        std::fs::write(root.path().join("spec/mck/vocabulary.json"), invalid).unwrap();
        let output = morphir(&["mck", "coverage", "--kit", kit.to_str().unwrap()]);
        assert_eq!(output.status.code(), Some(1));
        assert!(output.stdout.is_empty(), "{:?}", output);
        assert!(String::from_utf8_lossy(&output.stderr).contains("spec/mck/vocabulary.json"));
    }
    std::fs::remove_file(root.path().join("spec/mck/vocabulary.json")).unwrap();
    let output = morphir(&["mck", "coverage", "--kit", kit.to_str().unwrap()]);
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());
    assert!(String::from_utf8_lossy(&output.stderr).contains("not found"));
}

#[test]
fn kit_parse_errors_are_reported_before_coverage() {
    let (_root, kit) = repository();
    std::fs::write(kit.join("types.md"), "## types-1: invalid identifier\n").unwrap();
    let output = morphir(&["mck", "coverage", "--kit", kit.to_str().unwrap()]);
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());
    assert!(!output.stderr.is_empty());
}

#[test]
fn managed_snapshot_verification_precedes_vocabulary_parsing() {
    let root = TempDir::new().unwrap();
    let snapshot = root.path().join("snapshot");
    let output = morphir(&[
        "mck",
        "kit",
        "vendor",
        "--source",
        "embedded",
        "--dest",
        snapshot.to_str().unwrap(),
    ]);
    assert_eq!(output.status.code(), Some(0), "{:?}", output);
    let clean = morphir(&["mck", "coverage", "--kit", snapshot.to_str().unwrap()]);
    assert_eq!(clean.status.code(), Some(0), "{:?}", clean);
    std::fs::write(snapshot.join("spec/mck/vocabulary.json"), "{").unwrap();
    for kit in [snapshot.clone(), snapshot.join("spec/ir/mck")] {
        let output = morphir(&["mck", "coverage", "--kit", kit.to_str().unwrap()]);
        assert_eq!(output.status.code(), Some(1), "{:?}", output);
        assert!(output.stdout.is_empty());
        let stderr = String::from_utf8_lossy(&output.stderr);
        assert!(stderr.contains("vocabulary.json"), "{stderr}");
        assert!(!stderr.contains("EOF while parsing"), "{stderr}");
    }
}

#[test]
fn malformed_arguments_are_usage_errors() {
    for args in [
        vec!["mck", "coverage", "--kit"],
        vec!["mck", "coverage", "--unknown"],
    ] {
        let output = morphir(&args);
        assert_eq!(output.status.code(), Some(2), "{:?}", output);
        assert!(output.stdout.is_empty());
    }
}
