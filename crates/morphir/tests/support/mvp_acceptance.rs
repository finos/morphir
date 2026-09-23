//! Qualify the downloaded CLI against the independent local Library MVP inventory.

use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::process::Output;

use serde_json::{Value, json};

use super::{copy_snapshot, read_json, repo, stderr, stdout};

pub(super) fn qualify(work: &Path, run: &impl Fn(&[&str]) -> Output, denied_probe: Option<&str>) {
    let source_adapter = prepared_adapter(std::env::var_os("MORPHIR_MCK_MVP_ADAPTER"));
    let adapter = work.join(format!("mvp-adapter{}", std::env::consts::EXE_SUFFIX));
    std::fs::copy(source_adapter, &adapter).expect("copy prepared MVP adapter");

    let source = work.join("mvp-source");
    std::fs::create_dir(&source).unwrap();
    std::fs::create_dir(source.join("spec")).unwrap();
    copy_snapshot(&repo().join("spec/package"), &source.join("spec/package"))
        .expect("copy the MVP source corpus");
    let source_path = source;
    let source = source_path.to_str().unwrap();
    let adapter = adapter.to_str().unwrap();
    let report = "package-mvp.json";
    let output = run(&[
        "mck",
        "package",
        "mvp-run",
        "--source",
        source,
        "--adapter",
        adapter,
        "--adapter-arg",
        "package-mvp",
        "--report",
        report,
    ]);
    retain(work, report);
    assert_eq!(
        output.status.code(),
        Some(0),
        "MVP run: {}\n{}",
        stdout(&output),
        stderr(&output)
    );
    assert!(
        stdout(&output).contains("70 pass, 0 fail, 0 kit-error"),
        "{}",
        stdout(&output)
    );
    let actual = read_json(&work.join(report));
    assert_eq!(actual["contractVersion"], "0.1.0-draft.1");
    assert_eq!(actual["profile"], "local-library-mvp:0.1.0-draft.1");
    assert_eq!(actual["records"].as_array().unwrap().len(), 70);
    assert!(
        actual["records"]
            .as_array()
            .unwrap()
            .iter()
            .all(|record| record["result"] == "pass")
    );
    assert_eq!(actual["adapterError"], Value::Null);
    let checked = run(&[
        "mck",
        "package",
        "mvp-report",
        "check",
        report,
        "--source",
        source,
    ]);
    assert_eq!(
        checked.status.code(),
        Some(0),
        "MVP report check: {}\n{}",
        stdout(&checked),
        stderr(&checked)
    );
    assert!(stdout(&checked).contains("70 required cases, all passing"));
    let rendered = run(&[
        "mck",
        "package",
        "mvp-report",
        "render",
        report,
        "--output",
        "package-mvp.html",
    ]);
    assert_eq!(
        rendered.status.code(),
        Some(0),
        "MVP report render: {}",
        stderr(&rendered)
    );
    assert!(
        std::fs::read_to_string(work.join("package-mvp.html"))
            .unwrap()
            .contains("70 required cases")
    );
    retain(work, "package-mvp.html");

    // A plausible JSON report with one result removed must fail independent inventory checking.
    let mut missing = actual.clone();
    missing["records"].as_array_mut().unwrap().pop();
    std::fs::write(
        work.join("package-mvp-missing.json"),
        serde_json::to_vec(&missing).unwrap(),
    )
    .unwrap();
    let rejected = run(&[
        "mck",
        "package",
        "mvp-report",
        "check",
        "package-mvp-missing.json",
        "--source",
        source,
    ]);
    assert_eq!(
        rejected.status.code(),
        Some(1),
        "incomplete MVP report was not rejected cleanly"
    );
    let missing_record_log = format!(
        "missing record: {}\n{}\n{}",
        rejected.status,
        stdout(&rejected),
        stderr(&rejected)
    );

    // Malformed independent input cannot fall through to adapter execution.
    std::fs::write(source_path.join("spec/package/mck/mvp-cases.json"), b"{").unwrap();
    let rejected = run(&[
        "mck",
        "package",
        "mvp-run",
        "--source",
        source,
        "--adapter",
        adapter,
        "--adapter-arg",
        "package-mvp",
        "--report",
        "package-mvp-malformed.json",
    ]);
    assert_eq!(
        rejected.status.code(),
        Some(1),
        "malformed MVP inventory was not rejected cleanly"
    );
    assert!(!work.join("package-mvp-malformed.json").exists());
    std::fs::write(
        work.join("package-mvp-negative.log"),
        format!(
            "{missing_record_log}\nmalformed inventory: {}\n{}\n{}\n",
            rejected.status,
            stdout(&rejected),
            stderr(&rejected)
        ),
    )
    .unwrap();
    retain(work, "package-mvp-negative.log");

    // The installed binary executes both user workflows, including trust, fresh
    // metadata, full-lock operations, restore and generated provider consumption.
    let examples = work.join("examples");
    std::fs::create_dir(&examples).unwrap();
    for name in ["local-library-restore", "local-library-update"] {
        copy_snapshot(
            &repo().join("examples/package").join(name),
            &examples.join(name),
        )
        .expect("copy explicit package example");
    }
    let examples = examples.to_str().unwrap();
    let mut lines = Vec::new();
    for name in ["local-library-restore", "local-library-update"] {
        let output = run(&["itest", examples, "--filter", name]);
        lines.push(format!(
            "{name}: {}\n{}\n{}",
            output.status,
            stdout(&output),
            stderr(&output)
        ));
        std::fs::write(work.join("package-examples.log"), lines.join("\n")).unwrap();
        retain(work, "package-examples.log");
        assert_eq!(
            output.status.code(),
            Some(0),
            "installed CLI {name}: {}\n{}",
            stdout(&output),
            stderr(&output)
        );
        assert!(
            stdout(&output).contains("1 passed; 0 failed"),
            "{}",
            stdout(&output)
        );
    }
    std::fs::write(
        work.join("package-mvp-runtime.json"),
        serde_json::to_vec_pretty(&json!({
            "profile": "local-library-mvp:0.1.0-draft.1",
            "reportVersion": "0.1.0-draft.1",
            "kitHash": actual["kitHash"],
            "matchingRecords": 70,
            "reportCheck": "passed",
            "reportRender": "passed",
            "missingRecordRejected": true,
            "malformedInventoryRejected": true,
            "examples": ["local-library-restore", "local-library-update"],
            "networkDenial": denied_probe,
        }))
        .unwrap(),
    )
    .unwrap();
    retain(work, "package-mvp-runtime.json");
}

fn retain(work: &Path, name: &str) {
    if let Some(directory) = std::env::var_os("MORPHIR_MCK_ACCEPTANCE_EVIDENCE") {
        let directory = PathBuf::from(directory);
        std::fs::create_dir_all(&directory).unwrap();
        if work.join(name).is_file() {
            std::fs::copy(work.join(name), directory.join(name)).unwrap();
        }
    }
}

fn prepared_adapter(path: Option<OsString>) -> PathBuf {
    let path = path
        .map(PathBuf::from)
        .expect("prepared MVP adapter is required");
    assert!(path.is_file(), "prepared MVP adapter is missing");
    path
}

pub(super) fn missing_prepared_adapter_fails_closed() {
    let failure = std::panic::catch_unwind(|| prepared_adapter(None)).unwrap_err();
    let message = failure
        .downcast_ref::<String>()
        .map(String::as_str)
        .or_else(|| failure.downcast_ref::<&str>().copied())
        .unwrap_or("");
    assert!(message.contains("prepared MVP adapter"), "{message}");
}
