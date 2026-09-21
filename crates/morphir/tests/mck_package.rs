//! Package commands through real subprocesses, including a deliberately limited adapter.
use std::io::{BufRead, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use serde_json::{Value, json};

const ADAPTER: &str = "--package-test-adapter";

fn kit() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/package/mck")
}

fn command() -> Command {
    let mut command = Command::new(env!("CARGO_BIN_EXE_morphir"));
    command
        .env("MORPHIR_LOG_FILE", "false")
        .env_remove("MORPHIR_LOG_DIR")
        .env_remove("MORPHIR_OUT_DIR")
        .args(["mck", "package", "run"]);
    command
}

fn limited_adapter(contract: &str, mode: &str) {
    for line in std::io::stdin().lock().lines().map_while(Result::ok) {
        let request: Value = serde_json::from_str(&line).unwrap();
        match request["op"].as_str().unwrap() {
            "exit" => std::process::exit(if mode == "bad-exit" { 7 } else { 0 }),
            "capabilities" => {
                let mut response = json!({
                    "id": request["id"], "suite": "package", "contractVersion": contract,
                    "implementation": "limited-testee", "implementationVersion": "1",
                    "operations": []
                });
                if contract == "0.1.0-draft.2" {
                    response["profiles"] = json!(["flat-library"]);
                }
                if mode == "stalled-input" {
                    response["operations"] = json!(["normalize"]);
                }
                let mut stdout = std::io::stdout().lock();
                writeln!(stdout, "{response}").unwrap();
                stdout.flush().unwrap();
                if mode == "stalled-input" {
                    // Bound a failing test without a watchdog or orphaned process.
                    std::thread::sleep(std::time::Duration::from_secs(4));
                    return;
                }
            }
            other => panic!("unsupported operation must never be sent: {other}"),
        }
    }
}

fn run_limited(contract: &str, mode: &str, report: &Path) -> Output {
    command()
        .arg("--kit")
        .arg(kit())
        .args(["--contract", contract, "--adapter"])
        .arg(std::env::current_exe().unwrap())
        .args([
            "--adapter-arg",
            ADAPTER,
            "--adapter-arg",
            contract,
            "--adapter-arg",
            mode,
        ])
        .arg("--report")
        .arg(report)
        .output()
        .unwrap()
}

fn read_report(path: &Path) -> Value {
    serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap()
}

fn required_adapter_is_a_usage_error() {
    let work = tempfile::tempdir().unwrap();
    let report = work.path().join("never.json");
    let output = command()
        .arg("--kit")
        .arg(kit())
        .arg("--report")
        .arg(&report)
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&output.stderr).contains("--adapter"));
    assert!(!report.exists());
}

fn unknown_contract_is_a_usage_error() {
    let output = command()
        .arg("--kit")
        .arg(kit())
        .args(["--adapter", "must-not-start", "--contract", "0.1.0-draft.3"])
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&output.stderr).contains("0.1.0-draft.3"));
}

fn all_required_skips_fail_and_preserve_report_contracts() {
    for (contract, count) in [("0.1.0-draft.1", 80), ("0.1.0-draft.2", 78)] {
        let work = tempfile::tempdir().unwrap();
        let path = work.path().join("nested/report.json");
        let output = run_limited(contract, "normal", &path);
        assert_eq!(
            output.status.code(),
            Some(1),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let report = read_report(&path);
        assert_eq!(report["suite"], "package");
        assert_eq!(report["contractVersion"], contract);
        assert_eq!(report["kit"]["formatVersion"], contract);
        assert_eq!(
            report["testee"]["implementation"], "limited-testee",
            "{report}"
        );
        let records = report["records"].as_array().unwrap();
        assert_eq!(records.len(), count);
        assert!(records.iter().all(|r| r["result"] == "skipped"));
    }
}

fn invalid_corpus_does_not_start_adapter() {
    let work = tempfile::tempdir().unwrap();
    let report = work.path().join("report.json");
    let marker = work.path().join("started");
    let output = command()
        .arg("--kit")
        .arg(work.path())
        .arg("--adapter")
        .arg(std::env::current_exe().unwrap())
        .args(["--adapter-arg", "--mark-started", "--adapter-arg"])
        .arg(&marker)
        .arg("--report")
        .arg(&report)
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert!(!marker.exists());
    assert_eq!(read_report(&report)["records"][0]["result"], "kit-error");
}

fn shutdown_failure_is_recorded() {
    let work = tempfile::tempdir().unwrap();
    let path = work.path().join("report.json");
    let output = run_limited("0.1.0-draft.1", "bad-exit", &path);
    assert_eq!(output.status.code(), Some(1));
    let report = read_report(&path);
    let last = report["records"].as_array().unwrap().last().unwrap();
    assert_eq!(last["caseId"], "package-adapter-close");
    assert_eq!(last["result"], "kit-error");
}

fn copy_tree(source: &Path, target: &Path) {
    std::fs::create_dir_all(target).unwrap();
    for entry in std::fs::read_dir(source).unwrap() {
        let entry = entry.unwrap();
        let target = target.join(entry.file_name());
        if entry.file_type().unwrap().is_dir() {
            copy_tree(&entry.path(), &target);
        } else {
            std::fs::copy(entry.path(), target).unwrap();
        }
    }
}

fn stalled_request_write_is_a_bounded_kit_error() {
    let work = tempfile::tempdir().unwrap();
    copy_tree(kit().parent().unwrap(), work.path());
    let vectors = work.path().join("mck/digest-vectors.json");
    let mut value: Value = serde_json::from_slice(&std::fs::read(&vectors).unwrap()).unwrap();
    value["cases"][0]["input"] = json!(" ".repeat(2 * 1024 * 1024) + "{}");
    std::fs::write(vectors, serde_json::to_vec(&value).unwrap()).unwrap();
    let report = work.path().join("report.json");
    let started = std::time::Instant::now();
    let output = command()
        .arg("--kit")
        .arg(work.path().join("mck"))
        .arg("--adapter")
        .arg(std::env::current_exe().unwrap())
        .args([
            "--adapter-arg",
            ADAPTER,
            "--adapter-arg",
            "0.1.0-draft.1",
            "--adapter-arg",
            "stalled-input",
            "--timeout",
            "500",
            "--session-timeout",
            "2000",
        ])
        .arg("--report")
        .arg(&report)
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1));
    let report = read_report(&report);
    assert!(
        report["records"].as_array().unwrap().iter().any(|record| {
            record["operation"] == "normalize"
                && record["result"] == "kit-error"
                && record["message"]
                    .as_str()
                    .is_some_and(|message| message.contains("timed out"))
        }),
        "{report}"
    );
    assert!(started.elapsed() < std::time::Duration::from_secs(3));
}

fn main() {
    let args: Vec<_> = std::env::args().collect();
    if args.get(1).map(String::as_str) == Some(ADAPTER) {
        limited_adapter(&args[2], &args[3]);
        return;
    }
    if args.get(1).map(String::as_str) == Some("--mark-started") {
        std::fs::write(&args[2], "started").unwrap();
        return;
    }
    let tests: &[(&str, fn())] = &[
        (
            "required_adapter_is_a_usage_error",
            required_adapter_is_a_usage_error,
        ),
        (
            "unknown_contract_is_a_usage_error",
            unknown_contract_is_a_usage_error,
        ),
        (
            "all_required_skips_fail_and_preserve_report_contracts",
            all_required_skips_fail_and_preserve_report_contracts,
        ),
        (
            "invalid_corpus_does_not_start_adapter",
            invalid_corpus_does_not_start_adapter,
        ),
        ("shutdown_failure_is_recorded", shutdown_failure_is_recorded),
        (
            "stalled_request_write_is_a_bounded_kit_error",
            stalled_request_write_is_a_bounded_kit_error,
        ),
    ];
    let mut failures = 0;
    for (name, test) in tests {
        let success = std::panic::catch_unwind(test).is_ok();
        println!("test {name} ... {}", if success { "ok" } else { "FAILED" });
        failures += usize::from(!success);
    }
    assert_eq!(failures, 0, "{failures} package CLI tests failed");
}
