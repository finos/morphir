//! The actual CLI uses explicit caller policy for the existing selected runner.
use std::path::Path;
use std::process::{Command, Output};

const CONTROLS: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls"
);

fn command(action: &str) -> Command {
    let mut command = Command::new(env!("CARGO_BIN_EXE_morphir"));
    command
        .env("MORPHIR_LOG_FILE", "false")
        .env("MORPHIR_NO_BANNER", "true")
        .env_remove("MORPHIR_LOG_DIR")
        .args(["mck", "workbench", action]);
    command
}

fn kit(root: &Path, name: &str) -> std::path::PathBuf {
    let kit = root.join("kit");
    std::fs::create_dir(&kit).unwrap();
    std::fs::copy(Path::new(CONTROLS).join(name), kit.join("cases.json")).unwrap();
    kit
}

fn diagnostics(output: &Output) -> String {
    format!(
        "{}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    )
}

#[test]
fn selected_cli_requires_explicit_validated_policy_without_fabricating_a_report() {
    let temp = tempfile::tempdir().unwrap();
    let kit = kit(temp.path(), "cases.json");
    let report = temp.path().join("report.json");
    let output = command("run")
        .arg("--kit")
        .arg(&kit)
        .arg("--adapter")
        .arg(temp.path().join("absent-adapter"))
        .arg("--report")
        .arg(&report)
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1), "{}", diagnostics(&output));
    assert!(diagnostics(&output).contains("explicit checker policy"));
    assert!(!report.exists());

    let policy = temp.path().join("policy.json");
    std::fs::write(&policy, r#"{"kind":"model-originals","unknown":0}"#).unwrap();
    let output = command("run")
        .arg("--kit")
        .arg(&kit)
        .arg("--adapter")
        .arg(temp.path().join("absent-adapter"))
        .arg("--report")
        .arg(&report)
        .arg("--checker-policy")
        .arg(policy)
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1), "{}", diagnostics(&output));
    assert!(diagnostics(&output).contains("policy"));
    assert!(!report.exists());
}

#[test]
fn selected_cli_prepares_actual_source_before_the_adapter_factory() {
    let temp = tempfile::tempdir().unwrap();
    let kit = kit(temp.path(), "source-forged-cases.json");
    let report = temp.path().join("report.json");
    let policy = temp.path().join("policy.json");
    std::fs::copy(
        Path::new(CONTROLS).join("explicit-test-policy.json"),
        &policy,
    )
    .unwrap();
    let output = command("run")
        .arg("--kit")
        .arg(kit)
        .arg("--adapter")
        .arg(temp.path().join("absent-adapter"))
        .arg("--report")
        .arg(&report)
        .arg("--checker-policy")
        .arg(policy)
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1), "{}", diagnostics(&output));
    assert!(
        diagnostics(&output).contains("source"),
        "{}",
        diagnostics(&output)
    );
    assert!(!report.exists());
}

#[test]
fn selected_cli_saved_failure_replay_is_consistent_but_never_qualified() {
    let temp = tempfile::tempdir().unwrap();
    let kit = kit(temp.path(), "cases.json");
    let report = temp.path().join("report.json");
    let policy = temp.path().join("policy.json");
    std::fs::copy(
        Path::new(CONTROLS)
            .with_file_name("pipeline_negotiation_controls")
            .join("honest-unqualified-negotiated-report.json"),
        &report,
    )
    .unwrap();
    std::fs::copy(
        Path::new(CONTROLS).join("explicit-test-policy.json"),
        &policy,
    )
    .unwrap();
    let output = command("check")
        .arg("--kit")
        .arg(&kit)
        .arg("--report")
        .arg(&report)
        .arg("--checker-policy")
        .arg(policy)
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1), "{}", diagnostics(&output));
    assert!(
        String::from_utf8_lossy(&output.stdout).contains("not qualified"),
        "{}",
        diagnostics(&output)
    );
    let output = command("check")
        .arg("--kit")
        .arg(kit)
        .arg("--report")
        .arg(report)
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1), "{}", diagnostics(&output));
    assert!(diagnostics(&output).contains("explicit checker policy"));
}
