//! Installed package qualification uses an explicit copy of `spec/package`.
//! This is separate from the managed IR kit's vendor/status contract.

use std::path::{Path, PathBuf};
use std::process::Output;

use serde_json::{Value, json};

use super::{ADAPTER_FLAG, copy_snapshot, read_json, repo, stderr, stdout};

struct Suite {
    name: &'static str,
    contract: &'static str,
    content_hash: &'static str,
    count: usize,
}

const SUITES: &[Suite] = &[
    Suite {
        name: "integrity",
        contract: "0.1.0-draft.1",
        content_hash: "sha256-72b6593c99af919076e59208b833771394d659838e28ee4c23554ee7f5590e23",
        count: 80,
    },
    Suite {
        name: "resolution",
        contract: "0.1.0-draft.2",
        content_hash: "sha256-8dfed22a389bd08e945b35213586b0709f2cf11f5426199bcec746007443b08b",
        count: 78,
    },
];

// Package reports have no per-record timing fields. Preserve every field other
// than these two driver metadata fields, including the order of all records.
fn stable_report(mut report: Value) -> Value {
    for key in ["driverVersion", "startedAt"] {
        report.as_object_mut().unwrap().remove(key);
    }
    report
}

pub(super) fn qualify(
    work: &Path,
    adapter: &Path,
    run: &impl Fn(&[&str]) -> Output,
    denied_probe: Option<&str>,
) {
    let corpus = std::env::var_os("MORPHIR_MCK_PACKAGE_CORPUS")
        .map(PathBuf::from)
        .unwrap_or_else(|| repo().join("spec/package"));
    copy_snapshot(&corpus, &work.join("package-corpus")).expect("copy the explicit package corpus");
    let baseline = std::env::var_os("MORPHIR_MCK_PACKAGE_BASELINE")
        .map(PathBuf::from)
        .unwrap_or_else(|| repo().join("spec/mck/baseline/package"));
    let copied_baseline = work.join("package-baseline");
    copy_snapshot(&baseline, &copied_baseline).expect("copy frozen package baseline");
    let mut runtime = json!({
        "corpusSource": "explicit-copy",
        "networkDenial": denied_probe,
    });
    for suite in SUITES {
        let replay = copied_baseline.join(format!("{}.ndjson", suite.name));
        let report_name = format!("package-{}.json", suite.name);
        let output = run(&[
            "mck",
            "package",
            "run",
            "--contract",
            suite.contract,
            "--kit",
            "package-corpus/mck",
            "--adapter",
            adapter.to_str().unwrap(),
            "--adapter-arg",
            ADAPTER_FLAG,
            "--adapter-arg",
            "replay",
            "--adapter-arg",
            replay.to_str().unwrap(),
            "--report",
            &report_name,
        ]);
        assert_eq!(
            output.status.code(),
            Some(0),
            "package {} qualification: {}\n{}",
            suite.name,
            stdout(&output),
            stderr(&output)
        );
        let actual = read_json(&work.join(&report_name));
        let expected = read_json(&copied_baseline.join(format!("{}.json", suite.name)));
        assert_eq!(actual["suite"], "package");
        assert_eq!(actual["contractVersion"], suite.contract);
        assert_eq!(actual["kit"]["formatVersion"], suite.contract);
        assert_eq!(actual["kit"]["contentHash"], suite.content_hash);
        let records = actual["records"].as_array().unwrap();
        assert_eq!(records.len(), suite.count);
        assert!(records.iter().all(|record| record["result"] == "pass"));
        assert_eq!(
            stable_report(actual),
            stable_report(expected),
            "package {} report differs from frozen evidence",
            suite.name
        );
        runtime[suite.name] = json!({
            "contractVersion": suite.contract,
            "contentHash": suite.content_hash,
            "matchingRecords": suite.count,
            "exitCode": 0,
            "reportComparison": "passed",
        });
    }
    std::fs::write(
        work.join("package-runtime.json"),
        serde_json::to_vec_pretty(&runtime).unwrap(),
    )
    .unwrap();
}

fn qualification(corpus: Option<&Path>, baseline: Option<&Path>, evidence: &Path) -> Output {
    let mut command = std::process::Command::new(std::env::current_exe().unwrap());
    command
        .env("MORPHIR_MCK_ACCEPTANCE_EVIDENCE", evidence)
        .env_remove("MORPHIR_MCK_REQUIRE_NETWORK_DENIAL")
        .env_remove("MORPHIR_MCK_PACKAGE_CORPUS")
        .env_remove("MORPHIR_MCK_PACKAGE_BASELINE")
        .arg("installed_cli_runs_vendored_kit_without_tool_runtimes");
    if let Some(path) = corpus {
        command.env("MORPHIR_MCK_PACKAGE_CORPUS", path);
    }
    if let Some(path) = baseline {
        command.env("MORPHIR_MCK_PACKAGE_BASELINE", path);
    }
    command.output().unwrap()
}

pub(super) fn missing_package_corpus_fails_qualification() {
    let work = tempfile::tempdir().unwrap();
    let evidence = work.path().join("evidence");
    let output = qualification(Some(&work.path().join("missing")), None, &evidence);
    assert!(!output.status.success(), "missing package corpus must fail");
    assert!(
        stderr(&output).contains("copy the explicit package corpus"),
        "{}",
        stderr(&output)
    );
    assert!(!evidence.join("package-runtime.json").exists());
}

pub(super) fn malformed_package_corpus_fails_qualification() {
    for (name, file) in [
        ("integrity", "mck/digest-vectors.json"),
        ("resolution", "mck/resolution-cases.json"),
    ] {
        let work = tempfile::tempdir().unwrap();
        let corpus = work.path().join("package");
        copy_snapshot(&repo().join("spec/package"), &corpus).unwrap();
        std::fs::write(corpus.join(file), "{").unwrap();
        let evidence = work.path().join("evidence");
        let output = qualification(Some(&corpus), None, &evidence);
        assert!(
            !output.status.success(),
            "malformed {name} corpus must fail"
        );
        assert!(
            stderr(&output).contains(&format!("package {name} qualification")),
            "{}",
            stderr(&output)
        );
        assert!(!evidence.join("package-runtime.json").exists());
    }
}

pub(super) fn altered_package_replay_fails_qualification() {
    for (name, count) in [("integrity", 80), ("resolution", 78)] {
        let work = tempfile::tempdir().unwrap();
        let baseline = work.path().join("baseline");
        copy_snapshot(&repo().join("spec/mck/baseline/package"), &baseline).unwrap();
        let replay = baseline.join(format!("{name}.ndjson"));
        let text = std::fs::read_to_string(&replay).unwrap();
        let mut lines: Vec<String> = text.lines().map(str::to_owned).collect();
        let request: Value = serde_json::from_str(&lines[2]).unwrap();
        let mut response: Value = serde_json::from_str(&lines[3]).unwrap();
        assert_eq!(request["dir"], "request");
        assert_eq!(response["dir"], "response");
        assert_eq!(response["message"]["id"], request["message"]["id"]);
        // Keep every request byte and the response envelope intact. A valid but
        // incorrect operation result must fail the case, not protocol parsing.
        if name == "integrity" {
            assert_eq!(request["message"]["op"], "normalize");
            assert_eq!(response["message"]["canonical"], "{}");
            response["message"]["canonical"] = json!("[]");
        } else {
            assert_eq!(request["message"]["op"], "resolve-library");
            response["message"]["graph"]["nodes"][0]["manifestDigest"] =
                json!("sha256:0000000000000000000000000000000000000000000000000000000000000001");
        }
        lines[3] = serde_json::to_string(&response).unwrap();
        std::fs::write(replay, lines.join("\n") + "\n").unwrap();
        let evidence = work.path().join("evidence");
        let output = qualification(None, Some(&baseline), &evidence);
        assert!(!output.status.success(), "altered {name} replay must fail");
        assert!(
            stderr(&output).contains(&format!("package {name} qualification")),
            "{}",
            stderr(&output)
        );
        assert!(
            stderr(&output).contains(&format!(
                "{} pass, 1 fail, 0 kit-error, 0 skipped",
                count - 1
            )),
            "the altered answer must fail exactly one case: {}",
            stderr(&output)
        );
        assert!(!evidence.join("package-runtime.json").exists());
    }
}

pub(super) fn altered_expected_package_report_fails_qualification() {
    for name in ["integrity", "resolution"] {
        let work = tempfile::tempdir().unwrap();
        let baseline = work.path().join("baseline");
        copy_snapshot(&repo().join("spec/mck/baseline/package"), &baseline).unwrap();
        let expected = baseline.join(format!("{name}.json"));
        let mut report = read_json(&expected);
        let records = report["records"].as_array_mut().unwrap();
        assert!(records.iter().all(|record| record["result"] == "pass"));
        assert_ne!(records[0]["caseId"], records[1]["caseId"]);
        records.swap(0, 1);
        std::fs::write(expected, serde_json::to_vec(&report).unwrap()).unwrap();
        let evidence = work.path().join("evidence");
        let output = qualification(None, Some(&baseline), &evidence);
        assert!(
            !output.status.success(),
            "changed expected {name} record order must fail"
        );
        assert!(
            stderr(&output).contains(&format!(
                "package {name} report differs from frozen evidence"
            )),
            "passing cases must still match the entire ordered report: {}",
            stderr(&output)
        );
        assert!(!evidence.join("package-runtime.json").exists());
    }
}

pub(super) fn installed_cli_qualification_requires_package_evidence() {
    let evidence = tempfile::tempdir().unwrap();
    let output = qualification(None, None, evidence.path());
    assert!(output.status.success(), "{}", stderr(&output));
    for name in [
        "package-integrity.json",
        "package-resolution.json",
        "package-runtime.json",
    ] {
        assert!(
            evidence.path().join(name).is_file(),
            "installed CLI qualification must export {name}"
        );
    }
    let runtime = read_json(&evidence.path().join("package-runtime.json"));
    assert_eq!(runtime["corpusSource"], "explicit-copy");
    assert_eq!(runtime["integrity"]["matchingRecords"], 80);
    assert_eq!(runtime["resolution"]["matchingRecords"], 78);
    assert_eq!(runtime["integrity"]["exitCode"], 0);
    assert_eq!(runtime["resolution"]["exitCode"], 0);
}
