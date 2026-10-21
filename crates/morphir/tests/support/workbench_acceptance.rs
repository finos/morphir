//! Installed Workbench checks use native positive controls, never binding qualification.

use std::io::{BufRead, Write};
use std::path::Path;
use std::process::Output;

use serde_json::{Value, json};
use sha2::{Digest, Sha256};

use super::{ADAPTER_FLAG, copy_snapshot, read_json, repo, stderr, stdout};

const VERSION: &str = "0.1.0-draft.29";
const CASES_SHA256: &str = "27dd83719a5a30075bb37041fe78e71e1c782a06b812fc49ab9ab83d08f07ac8";
const FRAME_BYTES: usize = 16 * 1024 * 1024;

fn sha256(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

fn write_json(path: &Path, value: &Value) {
    std::fs::write(path, serde_json::to_vec_pretty(value).unwrap()).unwrap();
}

/// A deliberately named checker control. It verifies the complete ordered
/// requests, then returns authored expectations. It does not decode models or
/// claim production adapter compatibility.
pub(super) fn adapter(mode: &str, corpus: &Path) {
    let document = read_json(corpus);
    let cases = document["cases"].as_array().unwrap();
    let mut next = 0;
    for line in std::io::stdin().lock().lines().map_while(Result::ok) {
        let request: Value = serde_json::from_str(&line).unwrap();
        let id = request["id"].as_u64().unwrap();
        let mut reply = match request["op"].as_str() {
            Some("exit") => {
                if matches!(mode, "pass" | "mismatch" | "shutdown-failure") {
                    assert_eq!(next, cases.len(), "all control inputs must be consumed");
                }
                std::process::exit(if mode == "shutdown-failure" { 7 } else { 0 });
            }
            Some("capabilities") => {
                assert_eq!(
                    request,
                    json!({"id": id, "op": "capabilities", "suite": "workbench", "contractVersion": VERSION})
                );
                json!({"id": id, "suite": "workbench", "contractVersion": VERSION,
                    "binding": "checker-positive-control-only", "language": "rust-test",
                    "operations": ["inspect-model", "export-model-original"], "formats": ["json"]})
            }
            _ => {
                let case = &cases[next];
                assert_eq!(
                    request,
                    json!({"id": id, "op": case["operation"], "suite": "workbench",
                    "contractVersion": VERSION, "format": case["format"], "input": case["input"]})
                );
                next += 1;
                if mode == "frame-overflow" {
                    let mut out = std::io::stdout().lock();
                    let _ = out.write_all(&vec![b' '; FRAME_BYTES + 1]);
                    let _ = out.write_all(b"\n");
                    let _ = out.flush();
                    return;
                }
                let mut observation = case["expected"].clone();
                if mode == "mismatch" && next == 1 {
                    observation["value"]["normalizedIr"] = json!("{}");
                }
                observation
                    .as_object_mut()
                    .unwrap()
                    .insert("id".into(), json!(id));
                observation
            }
        };
        if mode == "wrong-id" && next == 1 {
            reply["id"] = json!(id + 1);
        }
        let mut out = std::io::stdout().lock();
        writeln!(out, "{reply}").unwrap();
        out.flush().unwrap();
    }
}

pub(super) fn qualify(
    work: &Path,
    adapter: &Path,
    run: &impl Fn(&[&str]) -> Output,
    denied_probe: Option<&str>,
) {
    let evidence = work.join("workbench");
    std::fs::create_dir(&evidence).unwrap();
    let kit = evidence.join("canonical");
    copy_snapshot(&repo().join("spec/workbench/mck/draft.29"), &kit)
        .expect("copy canonical Workbench draft.29 corpus");
    copy_snapshot(
        &repo().join("spec/workbench/draft.29/schemas"),
        &evidence.join("schemas"),
    )
    .expect("copy Workbench draft.29 schemas");
    let cases = std::fs::read(kit.join("cases.json")).unwrap();
    assert_eq!(sha256(&cases), CASES_SHA256, "canonical corpus changed");
    let corpus = read_json(&kit.join("cases.json"));
    let provenance = read_json(&kit.join("provenance.json"));
    assert_eq!(corpus["formatVersion"], VERSION);
    assert_eq!(provenance["casesSha256"], CASES_SHA256);
    assert_eq!(provenance["caseCount"], 32);
    let case_ids: Vec<_> = corpus["cases"]
        .as_array()
        .unwrap()
        .iter()
        .map(|case| case["id"].clone())
        .collect();
    assert_eq!(case_ids.len(), 32);
    let run_control = |kit: &Path, report: &Path, mode: &str| {
        run(&[
            "mck",
            "workbench",
            "run",
            "--kit",
            kit.to_str().unwrap(),
            "--adapter",
            adapter.to_str().unwrap(),
            "--adapter-arg",
            ADAPTER_FLAG,
            "--adapter-arg",
            "workbench-control",
            "--adapter-arg",
            mode,
            "--adapter-arg",
            kit.join("cases.json").to_str().unwrap(),
            "--report",
            report.to_str().unwrap(),
        ])
    };
    let check = |kit: &Path, report: &Path| {
        run(&[
            "mck",
            "workbench",
            "check",
            "--kit",
            kit.to_str().unwrap(),
            "--report",
            report.to_str().unwrap(),
        ])
    };
    let report = evidence.join("report.json");
    let ran = run_control(&kit, &report, "pass");
    assert_eq!(
        ran.status.code(),
        Some(0),
        "{}\n{}",
        stdout(&ran),
        stderr(&ran)
    );
    let checked = check(&kit, &report);
    assert_eq!(checked.status.code(), Some(0), "{}", stderr(&checked));
    let original = read_json(&report);
    assert_eq!(original["formatVersion"], VERSION);
    assert_eq!(original["corpusHash"], CASES_SHA256);
    assert_eq!(original["qualified"], true);
    let records = original["records"].as_array().unwrap();
    assert_eq!(
        records
            .iter()
            .map(|record| record["caseId"].clone())
            .collect::<Vec<_>>(),
        case_ids
    );
    assert!(records.iter().all(|record| record["result"] == "pass"));

    let mut refusals = Vec::new();
    for name in [
        "tampered-normalized-ir",
        "tampered-original-bytes",
        "missing-observation",
        "incomplete-records",
        "wrong-corpus-digest",
    ] {
        let mut altered = original.clone();
        match name {
            "tampered-normalized-ir" => {
                altered["records"][0]["observed"]["value"]["normalizedIr"] = json!("{}")
            }
            "tampered-original-bytes" => {
                let value = altered["records"][1]["observed"]["value"]
                    .as_object_mut()
                    .unwrap();
                let hex = value["hex"].as_str().unwrap();
                value.insert("hex".into(), json!(format!("00{}", &hex[2..])));
            }
            "missing-observation" => {
                altered["records"][0]
                    .as_object_mut()
                    .unwrap()
                    .remove("observed");
            }
            "incomplete-records" => {
                altered["records"].as_array_mut().unwrap().pop();
            }
            "wrong-corpus-digest" => altered["corpusHash"] = json!("0".repeat(64)),
            _ => unreachable!(),
        }
        let path = evidence.join(format!("{name}.json"));
        write_json(&path, &altered);
        let refused = check(&kit, &path);
        assert_eq!(
            refused.status.code(),
            Some(1),
            "{name}: {}",
            stderr(&refused)
        );
        refusals.push(json!({"name": name, "exitCode": refused.status.code(), "stdout": stdout(&refused), "stderr": stderr(&refused)}));
    }

    let mut failures = Vec::new();
    for mode in ["mismatch", "wrong-id", "shutdown-failure", "frame-overflow"] {
        let path = evidence.join(format!("{mode}.json"));
        let failed = run_control(&kit, &path, mode);
        assert_eq!(failed.status.code(), Some(1), "{mode}: {}", stderr(&failed));
        let saved = read_json(&path);
        assert_eq!(saved["qualified"], false);
        let checked_failure = check(&kit, &path);
        assert_eq!(
            checked_failure.status.code(),
            Some(1),
            "{mode}: {}",
            stderr(&checked_failure)
        );
        // Parseable, independently rechecked failure evidence must remain valid.
        let parsed =
            morphir_mck::workbench::Report::from_json(&std::fs::read_to_string(&path).unwrap())
                .unwrap();
        morphir_mck::workbench::check_report(&kit, &parsed).unwrap();
        match mode {
            "mismatch" => {
                assert_eq!(saved["records"][0]["result"], "fail");
                assert_eq!(saved["errors"], json!([]));
            }
            "wrong-id" => assert!(saved["errors"].to_string().contains("expected id")),
            "shutdown-failure" => {
                assert!(
                    saved["records"]
                        .as_array()
                        .unwrap()
                        .iter()
                        .all(|record| record["result"] == "pass")
                );
                assert_eq!(saved["errors"][0]["phase"], "shutdown");
            }
            "frame-overflow" => assert!(
                saved["errors"]
                    .to_string()
                    .contains("adapter frame exceeds 16777216 bytes")
            ),
            _ => unreachable!(),
        }
        failures.push(json!({"mode": mode, "runExitCode": failed.status.code(), "checkExitCode": checked_failure.status.code(), "stdout": stdout(&failed), "stderr": stderr(&failed)}));
    }

    // An authored source-bound observation at exactly the 1 MiB source limit.
    // This tests the runner's byte evidence path, not any model decoder.
    let boundary_kit = evidence.join("source-boundary");
    std::fs::create_dir(&boundary_kit).unwrap();
    let source = vec![b' '; 1024 * 1024];
    let hex = "20".repeat(source.len());
    let boundary = json!({"formatVersion": VERSION, "cases": [{"id": "one-mib-original", "operation": "export-model-original", "format": "json",
        "input": {"providerId": "source-boundary", "format": "json", "source": {"hex": hex}},
        "expected": {"status": "ok", "value": {"providerId": "source-boundary", "kind": "original", "format": "json", "hex": hex,
            "byteLength": source.len(), "sha256": sha256(&source)}}}]});
    write_json(&boundary_kit.join("cases.json"), &boundary);
    let boundary_report = evidence.join("source-boundary.json");
    let boundary_run = run_control(&boundary_kit, &boundary_report, "pass");
    assert_eq!(
        boundary_run.status.code(),
        Some(0),
        "{}",
        stderr(&boundary_run)
    );
    let boundary_check = check(&boundary_kit, &boundary_report);
    assert_eq!(
        boundary_check.status.code(),
        Some(0),
        "{}",
        stderr(&boundary_check)
    );

    let version = run(&["--no-banner", "--version"]);
    assert!(version.status.success());
    write_json(
        &evidence.join("runtime.json"),
        &json!({
            "scope": "checker-positive-control-only", "bindingQualification": false,
            "runnerVersion": stdout(&version).trim(), "contractVersion": VERSION,
            "corpusSource": "explicit-copy", "corpusSha256": CASES_SHA256,
            "matchingRecords": 32, "caseOrder": case_ids, "networkDenial": denied_probe,
            "runExitCode": ran.status.code(), "reportCheckExitCode": checked.status.code(),
            "reportSha256": sha256(&std::fs::read(&report).unwrap()),
            "reportRefusals": refusals, "adapterFailures": failures,
            "sourceBoundary": {"sourceBytes": source.len(), "runExitCode": boundary_run.status.code(), "checkExitCode": boundary_check.status.code()},
            "runnerFrameBytes": FRAME_BYTES, "oversizedRunnerFrameRefused": true,
            "runtime": "native executable; empty PATH; copied corpus and embedded schemas",
            "limits": "No production adapter or live authenticated host is qualified by these controls. MoonBit adapters have separate runtime and frame limits."
        }),
    );
}

pub(super) fn installed_cli_qualification_requires_workbench_evidence() {
    let work = tempfile::tempdir().unwrap();
    let evidence = work.path().join("evidence");
    let output = std::process::Command::new(std::env::current_exe().unwrap())
        .env("MORPHIR_MCK_ACCEPTANCE_EVIDENCE", &evidence)
        .env_remove("MORPHIR_MCK_REQUIRE_NETWORK_DENIAL")
        .arg("installed_cli_runs_vendored_kit_without_tool_runtimes")
        .output()
        .unwrap();
    assert!(output.status.success(), "{}", stderr(&output));
    let receipt = read_json(&evidence.join("workbench/runtime.json"));
    assert_eq!(receipt["contractVersion"], VERSION);
    assert_eq!(receipt["matchingRecords"], 32);
    assert_eq!(receipt["reportCheckExitCode"], 0);
    assert_eq!(receipt["scope"], "checker-positive-control-only");
    assert!(
        receipt["runnerVersion"]
            .as_str()
            .unwrap()
            .starts_with("morphir ")
    );
    assert_eq!(receipt["reportRefusals"].as_array().unwrap().len(), 5);
    assert_eq!(receipt["adapterFailures"].as_array().unwrap().len(), 4);
    assert!(evidence.join("workbench/canonical/cases.json").is_file());
    assert!(
        evidence
            .join("workbench/schemas/mck-report.schema.json")
            .is_file()
    );
}
