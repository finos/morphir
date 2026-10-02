//! Public Workbench commands preserve failure evidence and recompute qualification.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use serde_json::{Value, json};

fn command(action: &str) -> Command {
    let mut command = Command::new(env!("CARGO_BIN_EXE_morphir"));
    command
        .env("MORPHIR_LOG_FILE", "false")
        .env("MORPHIR_NO_BANNER", "true")
        .env_remove("MORPHIR_LOG_DIR")
        .env_remove("MORPHIR_OUT_DIR")
        .args(["mck", "workbench", action]);
    command
}

fn corpus(root: &Path) -> PathBuf {
    let kit = root.join("kit");
    std::fs::create_dir(&kit).unwrap();
    std::fs::write(
        kit.join("cases.json"),
        json!({
            "formatVersion":"0.1.0-draft.1",
            "cases":[{"id":"exact-int","format":"json",
                "input":{"type":"int","value":"9007199254740993"},
                "expected":{"status":"ok","value":{"type":"int","value":"9007199254740993"}}}]
        })
        .to_string(),
    )
    .unwrap();
    kit
}

fn check(kit: &Path, report: &Path) -> Output {
    command("check")
        .arg("--kit")
        .arg(kit)
        .arg("--report")
        .arg(report)
        .output()
        .unwrap()
}

#[test]
fn missing_adapter_leaves_checkable_failure_evidence() {
    let root = tempfile::tempdir().unwrap();
    let kit = corpus(root.path());
    let report = root.path().join("nested/report.json");
    let run = command("run")
        .arg("--kit")
        .arg(&kit)
        .arg("--adapter")
        .arg(root.path().join("absent-adapter"))
        .arg("--report")
        .arg(&report)
        .output()
        .unwrap();
    assert_eq!(run.status.code(), Some(1));
    let text = std::fs::read_to_string(&report).unwrap();
    let saved = morphir_mck::workbench::Report::from_json(&text).unwrap();
    morphir_mck::workbench::check_report(&kit, &saved).unwrap();
    assert!(!saved.qualified);
    assert_eq!(saved.records.len(), 1);
    assert_eq!(check(&kit, &report).status.code(), Some(1));
    assert!(String::from_utf8_lossy(&run.stdout).contains("not qualified"));
}

#[test]
fn check_recomputes_observations_and_rejects_duplicates() {
    let root = tempfile::tempdir().unwrap();
    let kit = corpus(root.path());
    let report = root.path().join("report.json");
    let hash = morphir_mck::workbench::load(&kit)
        .unwrap()
        .corpus_hash()
        .to_string();
    let mut saved = json!({
        "formatVersion":"0.1.0-draft.1","suite":"workbench","corpusHash":hash,
        "capabilities":{"suite":"workbench","contractVersion":"0.1.0-draft.1",
            "binding":"test-transcript","language":"fixture",
            "operations":["decode-value"],"formats":["json"]},
        "records":[{"caseId":"exact-int","format":"json","result":"pass",
            "observed":{"status":"ok","value":{"type":"int","value":"9007199254740993"}}}],
        "errors":[],"qualified":true
    });
    std::fs::write(&report, saved.to_string()).unwrap();
    let good = check(&kit, &report);
    assert_eq!(
        good.status.code(),
        Some(0),
        "{}",
        String::from_utf8_lossy(&good.stderr)
    );

    saved["records"][0]["observed"]["value"]["value"] = Value::String("9007199254740992".into());
    std::fs::write(&report, saved.to_string()).unwrap();
    let forged = check(&kit, &report);
    assert_eq!(forged.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&forged.stderr).contains("forged case result"));

    let duplicate = saved.to_string().replacen("{", "{\"qualified\":true,", 1);
    std::fs::write(&report, duplicate).unwrap();
    let duplicate = check(&kit, &report);
    assert_eq!(duplicate.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&duplicate.stderr).contains("duplicate key"));
}

#[test]
fn report_output_cannot_replace_the_independent_corpus() {
    let root = tempfile::tempdir().unwrap();
    let kit = corpus(root.path());
    let path = kit.join("cases.json");
    let before = std::fs::read(&path).unwrap();
    let output = command("run")
        .arg("--kit")
        .arg(&kit)
        .arg("--adapter")
        .arg(root.path().join("absent-adapter"))
        .arg("--report")
        .arg(&path)
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(2));
    assert_eq!(std::fs::read(path).unwrap(), before);
}

#[test]
fn admission_report_retains_operation_and_rejects_forged_dispatch() {
    let root = tempfile::tempdir().unwrap();
    let kit = root.path().join("kit");
    std::fs::create_dir(&kit).unwrap();
    std::fs::write(
        kit.join("cases.json"),
        json!({"formatVersion":"0.1.0-draft.2","cases":[{
            "id":"typed-int","operation":"validate-value","format":"json",
            "input":{"value":{"type":"int","value":"7"},"type":{"type":"int"},"definitions":[]},
            "expected":{"status":"ok","value":{"type":"int","value":"7"}}
        }]})
        .to_string(),
    )
    .unwrap();
    let report = root.path().join("report.json");
    let run = command("run")
        .arg("--kit")
        .arg(&kit)
        .arg("--adapter")
        .arg(root.path().join("absent"))
        .arg("--report")
        .arg(&report)
        .output()
        .unwrap();
    assert_eq!(run.status.code(), Some(1));
    let mut saved: Value = serde_json::from_slice(&std::fs::read(&report).unwrap()).unwrap();
    assert_eq!(saved["formatVersion"], "0.1.0-draft.2");
    assert_eq!(saved["records"][0]["operation"], "validate-value");
    assert_eq!(check(&kit, &report).status.code(), Some(1));
    saved["capabilities"] = json!({"suite":"workbench","contractVersion":"0.1.0-draft.2","binding":"transcript","language":"fixture","operations":["validate-value"],"formats":["json"]});
    saved["errors"] = json!([]);
    saved["qualified"] = json!(true);
    saved["records"][0]["result"] = json!("pass");
    saved["records"][0]["observed"] = json!({"status":"ok","value":{"type":"int","value":"7"}});
    std::fs::write(&report, saved.to_string()).unwrap();
    assert_eq!(check(&kit, &report).status.code(), Some(0));
    saved["records"][0]["operation"] = json!("decode-value");
    std::fs::write(&report, saved.to_string()).unwrap();
    let forged = check(&kit, &report);
    assert_eq!(forged.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&forged.stderr).contains("identity/order"));
}
