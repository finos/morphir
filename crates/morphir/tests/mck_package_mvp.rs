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
        stdout.contains("MVP local Library: 0 pass, 0 fail, 29 kit-error"),
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
