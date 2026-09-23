//! The public command admits the complete fresh-restore corpus before adapter spawn.
use std::{path::Path, process::Command};

#[test]
fn public_mvp_run_requires_admission_and_an_explicit_adapter() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let output = Command::new(env!("CARGO_BIN_EXE_morphir"))
        .env("MORPHIR_LOG_FILE", "false")
        .env("MORPHIR_NO_BANNER", "true")
        .args(["mck", "package", "mvp-run", "--source"])
        .arg(root)
        .args(["--adapter", "/missing-mvp-adapter"])
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1));
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(
        stdout.contains("MVP local Library: 0 pass, 0 fail, 70 kit-error"),
        "{stdout}"
    );

    let empty = tempfile::tempdir().unwrap();
    let output = Command::new(env!("CARGO_BIN_EXE_morphir"))
        .env("MORPHIR_LOG_FILE", "false")
        .env("MORPHIR_NO_BANNER", "true")
        .args(["mck", "package", "mvp-run", "--source"])
        .arg(empty.path())
        .args(["--adapter", "/missing-mvp-adapter"])
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1));
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("mvp-cases.json"), "{stderr}");
}

#[test]
fn public_mvp_report_is_written_checked_and_rendered_offline() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let temp = tempfile::tempdir().unwrap();
    let json = temp.path().join("report.json");
    let html = temp.path().join("report.html");
    let run = Command::new(env!("CARGO_BIN_EXE_morphir"))
        .env("MORPHIR_LOG_FILE", "false")
        .env("MORPHIR_NO_BANNER", "true")
        .args(["mck", "package", "mvp-run", "--source"])
        .arg(&root)
        .args(["--adapter", "/missing-mvp-adapter", "--report"])
        .arg(&json)
        .output()
        .unwrap();
    assert_eq!(run.status.code(), Some(1));
    let report: serde_json::Value = serde_json::from_slice(&std::fs::read(&json).unwrap()).unwrap();
    assert_eq!(report["contractVersion"], "0.1.0-draft.1");
    assert_eq!(report["records"].as_array().unwrap().len(), 70);

    let check = Command::new(env!("CARGO_BIN_EXE_morphir"))
        .env("MORPHIR_LOG_FILE", "false")
        .env("MORPHIR_NO_BANNER", "true")
        .args(["mck", "package", "mvp-report", "check"])
        .arg(&json)
        .args(["--source"])
        .arg(&root)
        .output()
        .unwrap();
    assert_eq!(check.status.code(), Some(1));

    let render = Command::new(env!("CARGO_BIN_EXE_morphir"))
        .env("MORPHIR_LOG_FILE", "false")
        .env("MORPHIR_NO_BANNER", "true")
        .args(["mck", "package", "mvp-report", "render"])
        .arg(&json)
        .args(["--output"])
        .arg(&html)
        .output()
        .unwrap();
    assert_eq!(
        render.status.code(),
        Some(0),
        "{}",
        String::from_utf8_lossy(&render.stderr)
    );
    assert!(
        std::fs::read_to_string(&html)
            .unwrap()
            .contains("70 required cases")
    );
}
