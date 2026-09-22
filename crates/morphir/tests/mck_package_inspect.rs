//! Definition inspection must not turn incomplete restore definitions into passes.
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use serde_json::Value;

fn source() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn inspect(source: &Path, contract: &str) -> Output {
    Command::new(env!("CARGO_BIN_EXE_morphir"))
        .env("MORPHIR_LOG_FILE", "false")
        .env("MORPHIR_NO_BANNER", "true")
        .args(["mck", "package", "inspect", "--source"])
        .arg(source)
        .args(["--contract", contract])
        .output()
        .unwrap()
}

#[test]
fn inspection_reports_pending_definitions_without_execution_claims() {
    let output = inspect(&source(), "0.1.0-draft.3");
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let summary: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(summary["kind"], "definition-summary");
    assert_eq!(summary["caseCount"], 54);
    assert_eq!(summary["boundAssetCount"], 6);
    assert_eq!(summary["pendingAssetCount"], 121);
    assert_eq!(summary["errors"], serde_json::json!([]));
    for execution_field in ["records", "kitHash", "passed", "testee"] {
        assert!(summary.get(execution_field).is_none());
    }
}

#[test]
fn invalid_source_returns_failed_inspection_with_diagnostics() {
    let empty = tempfile::tempdir().unwrap();
    let output = inspect(empty.path(), "0.1.0-draft.3");
    assert_eq!(output.status.code(), Some(1));
    let summary: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(summary["kind"], "definition-summary");
    assert!(!summary["errors"].as_array().unwrap().is_empty());
    assert!(summary.get("kitHash").is_none());
}

#[test]
fn inspection_rejects_other_contracts_as_usage_errors() {
    for contract in ["0.1.0-draft.1", "0.1.0-draft.2", "0.1.0", "future"] {
        let output = inspect(&source(), contract);
        assert_eq!(output.status.code(), Some(2));
        assert!(String::from_utf8_lossy(&output.stderr).contains(contract));
    }
}
