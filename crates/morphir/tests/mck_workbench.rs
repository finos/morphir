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

#[test]
fn invocation_report_requires_operation_specific_suite_projection() {
    let root = tempfile::tempdir().unwrap();
    let kit = root.path().join("kit");
    std::fs::create_dir(&kit).unwrap();
    let suite = json!({"profile":"morphir-invocations-v1","calls":[{"id":"c","entry":"demo:main#id","arguments":[]}]});
    std::fs::write(kit.join("cases.json"),json!({"formatVersion":"0.1.0-draft.3","cases":[{"id":"invoke","operation":"validate-invocations","format":"json","input":{"suite":suite,"manifest":{"entries":[{"name":"demo:main#id","inputs":[],"output":{"type":"unit"}}],"definitions":[]}},"expected":{"status":"ok","value":suite}}]}).to_string()).unwrap();
    let hash = morphir_mck::workbench::load(&kit)
        .unwrap()
        .corpus_hash()
        .to_owned();
    let mut saved = json!({"formatVersion":"0.1.0-draft.3","suite":"workbench","corpusHash":hash,"capabilities":{"suite":"workbench","contractVersion":"0.1.0-draft.3","binding":"transcript","language":"fixture","operations":["validate-invocations"],"formats":["json"]},"records":[{"caseId":"invoke","operation":"validate-invocations","format":"json","result":"pass","observed":{"status":"ok","value":suite}}],"errors":[],"qualified":true});
    let report = root.path().join("report.json");
    std::fs::write(&report, saved.to_string()).unwrap();
    let result = check(&kit, &report);
    assert_eq!(
        result.status.code(),
        Some(0),
        "{}",
        String::from_utf8_lossy(&result.stderr)
    );
    saved["records"][0]["observed"]["value"] = json!({"type":"unit"});
    std::fs::write(&report, saved.to_string()).unwrap();
    let result = check(&kit, &report);
    assert_eq!(result.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&result.stderr).contains("invocation projection"));
}

#[test]
fn terminal_report_retains_cleanup_and_rejects_value_or_operation_substitution() {
    let root = tempfile::tempdir().unwrap();
    let kit = root.path().join("kit");
    std::fs::create_dir(&kit).unwrap();
    let suite = json!({"profile":"morphir-invocations-v1","calls":[{"id":"c","entry":"run","arguments":[]}]});
    let outcomes = json!({"contractVersion":"0.1.0-draft.5","calls":[{"id":"c","outcome":{"status":"cancelled"}}],"cleanup":{"stage":"cleanup","code":"provider.dispose","message":"Disposal failed"},"extensions":null});
    std::fs::write(kit.join("cases.json"),json!({"formatVersion":"0.1.0-draft.5","cases":[{"id":"terminal","operation":"validate-outcomes","format":"json","input":{"suite":suite,"manifest":{"entries":[{"name":"run","inputs":[],"output":{"type":"unit"}}],"definitions":[]},"outcomes":outcomes},"expected":{"status":"ok","value":outcomes}}]}).to_string()).unwrap();
    let hash = morphir_mck::workbench::load(&kit)
        .unwrap()
        .corpus_hash()
        .to_owned();
    // A saved fixed transcript checks CLI evidence handling, not an implementation.
    let saved = json!({"formatVersion":"0.1.0-draft.5","suite":"workbench","corpusHash":hash,"capabilities":{"suite":"workbench","contractVersion":"0.1.0-draft.5","binding":"transcript","language":"fixture","operations":["validate-outcomes"],"formats":["json"]},"records":[{"caseId":"terminal","operation":"validate-outcomes","format":"json","result":"pass","observed":{"status":"ok","value":outcomes}}],"errors":[],"qualified":true});
    let report = root.path().join("report.json");
    std::fs::write(&report, saved.to_string()).unwrap();
    let admitted = check(&kit, &report);
    assert_eq!(
        admitted.status.code(),
        Some(0),
        "{}",
        String::from_utf8_lossy(&admitted.stderr)
    );
    for change in ["cleanup", "value", "operation"] {
        let mut forged = saved.clone();
        match change {
            "cleanup" => forged["records"][0]["observed"]["value"]["cleanup"] = json!(null),
            "value" => forged["records"][0]["observed"]["value"] = json!({"type":"unit"}),
            "operation" => forged["records"][0]["operation"] = json!("validate-output"),
            _ => unreachable!(),
        }
        std::fs::write(&report, forged.to_string()).unwrap();
        assert_eq!(check(&kit, &report).status.code(), Some(1));
    }
}

#[test]
fn job_trace_report_is_checked_through_the_existing_workbench_command() {
    let root = tempfile::tempdir().unwrap();
    let kit = root.path().join("kit");
    std::fs::create_dir(&kit).unwrap();
    std::fs::write(
        kit.join("cases.json"),
        json!({"formatVersion":"0.1.0-draft.6","cases":[{
            "id":"negative-json","operation":"reduce-job","format":"json","input":null,
            "expected":{"status":"invalid","code":"workbench.invalid_job_trace"}
        }]})
        .to_string(),
    )
    .unwrap();
    let hash = morphir_mck::workbench::load(&kit)
        .unwrap()
        .corpus_hash()
        .to_owned();
    let saved = json!({"formatVersion":"0.1.0-draft.6","suite":"workbench","corpusHash":hash,
        "capabilities":{"suite":"workbench","contractVersion":"0.1.0-draft.6",
            "binding":"fixed-transcript","language":"fixture","operations":["reduce-job"],"formats":["json"]},
        "records":[{"caseId":"negative-json","operation":"reduce-job","format":"json","result":"pass",
            "observed":{"status":"invalid","code":"workbench.invalid_job_trace"}}],"errors":[],"qualified":true});
    let report = root.path().join("report.json");
    std::fs::write(&report, saved.to_string()).unwrap();
    let admitted = check(&kit, &report);
    assert_eq!(
        admitted.status.code(),
        Some(0),
        "{}",
        String::from_utf8_lossy(&admitted.stderr)
    );
    for field in ["operation", "format", "code"] {
        let mut forged = saved.clone();
        match field {
            "operation" => forged["records"][0]["operation"] = json!("validate-outcomes"),
            "format" => forged["records"][0]["format"] = json!("ion-text"),
            "code" => forged["records"][0]["observed"]["code"] = json!("workbench.job_receipt"),
            _ => unreachable!(),
        }
        std::fs::write(&report, forged.to_string()).unwrap();
        assert_eq!(check(&kit, &report).status.code(), Some(1), "{field}");
    }
}

#[test]
fn native_frame_reports_use_shared_run_and_independent_check() {
    let root = tempfile::tempdir().unwrap();
    let kit = root.path().join("kit");
    std::fs::create_dir(&kit).unwrap();
    std::fs::write(
        kit.join("cases.json"),
        json!({"formatVersion":"0.1.0-draft.7","cases":[{
        "id":"frame","operation":"validate-native-frame","format":"json",
        "input":{"encoding":"utf8","source":"{}"},
        "expected":{"status":"invalid","code":"native.frame.shape"}}]})
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
    assert_eq!(saved["formatVersion"], "0.1.0-draft.7");
    assert_eq!(saved["records"][0]["operation"], "validate-native-frame");
    assert_eq!(check(&kit, &report).status.code(), Some(1));
    saved["capabilities"] = json!({"suite":"workbench","contractVersion":"0.1.0-draft.7",
        "binding":"transcript","language":"test","operations":["validate-native-frame"],"formats":["json"]});
    saved["errors"] = json!([]);
    saved["qualified"] = json!(true);
    saved["records"][0]["result"] = json!("pass");
    saved["records"][0]["observed"] = json!({"status":"invalid","code":"native.frame.shape"});
    std::fs::write(&report, saved.to_string()).unwrap();
    assert_eq!(check(&kit, &report).status.code(), Some(0));
    for change in ["operation", "code", "projection", "hash", "capabilities"] {
        let mut forged = saved.clone();
        match change {
            "operation" => forged["records"][0]["operation"] = json!("reduce-job"),
            "code" => forged["records"][0]["observed"]["code"] = json!("native.frame.unknown"),
            "projection" => {
                forged["records"][0]["observed"] =
                    json!({"status":"ok","value":{"frameAccepted":true}})
            }
            "hash" => forged["corpusHash"] = json!("0".repeat(64)),
            "capabilities" => forged["capabilities"]["contractVersion"] = json!("0.1.0-draft.6"),
            _ => unreachable!(),
        }
        std::fs::write(&report, forged.to_string()).unwrap();
        assert_eq!(check(&kit, &report).status.code(), Some(1), "{change}");
    }
}

#[test]
fn native_frame_private_number_objects_reject_before_adapter_spawn() {
    let root = tempfile::tempdir().unwrap();
    let kit = root.path().join("kit");
    std::fs::create_dir(&kit).unwrap();
    std::fs::write(kit.join("cases.json"),r#"{"formatVersion":"0.1.0-draft.7","cases":[{"id":"frame","operation":"validate-native-frame","format":"json","input":{"encoding":"utf8","source":"{}","generate":{"prefix":{"repeat":" ","count":{"$serde_json::private::Number":"1"}}}},"expected":{"status":"ok","value":{"frameAccepted":true}}}]}"#).unwrap();
    let report = root.path().join("report.json");
    let result = command("run")
        .arg("--kit")
        .arg(&kit)
        .arg("--adapter")
        .arg(root.path().join("absent"))
        .arg("--report")
        .arg(&report)
        .output()
        .unwrap();
    assert_eq!(result.status.code(), Some(1));
    assert!(
        !report.exists(),
        "invalid corpus must fail before creating an adapter-error report"
    );
    assert!(String::from_utf8_lossy(&result.stderr).contains("native frame corpus shape"));
}

#[test]
fn native_frame_check_rejects_literal_object_success_marker() {
    let root = tempfile::tempdir().unwrap();
    let kit = root.path().join("kit");
    std::fs::create_dir(&kit).unwrap();
    std::fs::write(kit.join("cases.json"),json!({"formatVersion":"0.1.0-draft.7","cases":[{
        "id":"frame","operation":"validate-native-frame","format":"json",
        "input":{"encoding":"utf8","source":"{}"},"expected":{"status":"ok","value":{"frameAccepted":true}}}]}).to_string()).unwrap();
    let hash = morphir_mck::workbench::load(&kit)
        .unwrap()
        .corpus_hash()
        .to_owned();
    let mut saved = json!({"formatVersion":"0.1.0-draft.7","suite":"workbench","corpusHash":hash,
        "capabilities":{"suite":"workbench","contractVersion":"0.1.0-draft.7","binding":"transcript","language":"test","operations":["validate-native-frame"],"formats":["json"]},
        "records":[{"caseId":"frame","operation":"validate-native-frame","format":"json","result":"pass","observed":{"status":"ok","value":{"frameAccepted":true}}}],"errors":[],"qualified":true});
    let report = root.path().join("report.json");
    std::fs::write(&report, saved.to_string()).unwrap();
    assert_eq!(check(&kit, &report).status.code(), Some(0));
    saved["records"][0]["observed"]["value"]["frameAccepted"] =
        json!({"$serde_json::private::RawValue":"true"});
    std::fs::write(&report, saved.to_string()).unwrap();
    let rejected = check(&kit, &report);
    assert_eq!(rejected.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&rejected.stderr).contains("native frame report shape"));
}

#[test]
fn native_reply_cli_preserves_failure_evidence_and_rechecks_effects_and_literal_shapes() {
    let root = tempfile::tempdir().unwrap();
    let kit = root.path().join("kit");
    std::fs::create_dir(&kit).unwrap();
    let corpus = json!({"formatVersion":"0.1.0-draft.8","cases":[{
        "id":"reply","operation":"validate-native-reply","format":"json",
        "input":{"expectedOperation":"job.submit","expectedSession":"session","encoding":"utf8","source":"opaque"},
        "expected":{"status":"ok","value":{"replyAccepted":true,"ok":false,"error":{"code":"unavailable","effect":"unknown"}}}}]});
    std::fs::write(kit.join("cases.json"), corpus.to_string()).unwrap();
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
    let text = std::fs::read_to_string(&report).unwrap();
    let failure = morphir_mck::workbench::Report::from_json(&text).unwrap();
    morphir_mck::workbench::check_report(&kit, &failure).unwrap();
    assert!(!failure.qualified);
    assert_eq!(check(&kit, &report).status.code(), Some(1));
    let mut saved: Value = serde_json::from_str(&text).unwrap();
    saved["capabilities"] = json!({"suite":"workbench","contractVersion":"0.1.0-draft.8",
        "binding":"transcript","language":"test","operations":["validate-native-reply"],"formats":["json"]});
    saved["errors"] = json!([]);
    saved["qualified"] = json!(true);
    saved["records"][0]["result"] = json!("pass");
    saved["records"][0]["observed"] = corpus["cases"][0]["expected"].clone();
    std::fs::write(&report, saved.to_string()).unwrap();
    assert_eq!(check(&kit, &report).status.code(), Some(0));
    for change in ["effect", "private", "version", "hash"] {
        let mut forged = saved.clone();
        match change {
            "effect" => {
                forged["records"][0]["observed"]["value"]["error"]["effect"] = json!("none")
            }
            "private" => {
                forged["records"][0]["observed"]["value"] = json!({"$serde_json::private::RawValue":corpus["cases"][0]["expected"]["value"].to_string()})
            }
            "version" => forged["formatVersion"] = json!("0.1.0-draft.9"),
            "hash" => forged["corpusHash"] = json!("0".repeat(64)),
            _ => unreachable!(),
        }
        std::fs::write(&report, forged.to_string()).unwrap();
        assert_eq!(check(&kit, &report).status.code(), Some(1), "{change}");
    }
    let mut invalid = corpus;
    invalid["cases"][0]["input"]["generate"] =
        json!({"prefix":{"repeat":" ","count":{"$serde_json::private::Number":"1"}}});
    std::fs::write(kit.join("cases.json"), invalid.to_string()).unwrap();
    std::fs::remove_file(&report).unwrap();
    let rejected = command("run")
        .arg("--kit")
        .arg(&kit)
        .arg("--adapter")
        .arg(root.path().join("absent"))
        .arg("--report")
        .arg(&report)
        .output()
        .unwrap();
    assert_eq!(rejected.status.code(), Some(1));
    assert!(
        !report.exists(),
        "invalid corpus must reject before adapter spawn"
    );
    assert!(String::from_utf8_lossy(&rejected.stderr).contains("native reply corpus"));
}

#[test]
fn native_client_cli_saves_failure_evidence_and_rejects_invalid_fixtures_before_spawn() {
    let root = tempfile::tempdir().unwrap();
    let kit = root.path().join("kit");
    std::fs::create_dir(&kit).unwrap();
    let mut published: Value = serde_json::from_str(include_str!(
        "../../../spec/workbench/mck/draft.9/cases.json"
    ))
    .unwrap();
    let first = published["cases"][0].clone();
    published["cases"] = json!([first]);
    std::fs::write(kit.join("cases.json"), published.to_string()).unwrap();
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
    let failure =
        morphir_mck::workbench::Report::from_json(&std::fs::read_to_string(&report).unwrap())
            .unwrap();
    morphir_mck::workbench::check_report(&kit, &failure).unwrap();
    assert!(!failure.qualified);
    assert_eq!(check(&kit, &report).status.code(), Some(1));
    published["cases"][0]["input"]["invocations"][0]["held"] =
        json!({"$serde_json::private::RawValue":"false"});
    std::fs::write(kit.join("cases.json"), published.to_string()).unwrap();
    std::fs::remove_file(&report).unwrap();
    let rejected = command("run")
        .arg("--kit")
        .arg(&kit)
        .arg("--adapter")
        .arg(root.path().join("absent"))
        .arg("--report")
        .arg(&report)
        .output()
        .unwrap();
    assert_eq!(rejected.status.code(), Some(1));
    assert!(!report.exists());
    assert!(String::from_utf8_lossy(&rejected.stderr).contains("native client corpus"));
}
