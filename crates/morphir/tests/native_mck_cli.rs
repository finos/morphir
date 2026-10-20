//! Actual compiled CLI/native host controls. No authored successful observation.
use morphir_mck::workbench::{Report, RunConfiguration, check_report_configured};
use serde_json::{Value, json};
use std::{
    fs,
    io::Read,
    path::{Path, PathBuf},
    process::{Child, Command, ExitStatus, Stdio},
    time::{Duration, Instant},
};
const CASES: &[u8] = include_bytes!("native_mck_cli_fixtures/cases24.json");
const POLICY: &str = include_str!("native_mck_cli_fixtures/native-policy.json");
const CURRENT: &str = include_str!("native_mck_cli_fixtures/current-policy.json");
const ID: &str = "explicit-empty-companion-declaration-is-complete";
const WAIT: Duration = Duration::from_secs(90);
const LOG_LIMIT: u64 = 1_048_576;
struct Process(Option<Child>);
impl Drop for Process {
    fn drop(&mut self) {
        if let Some(mut child) = self.0.take() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}
struct Output {
    status: ExitStatus,
    stdout: String,
    stderr: String,
}
fn bounded_text(path: &Path, limit: u64) -> String {
    let mut bytes = Vec::new();
    fs::File::open(path)
        .unwrap()
        .take(limit + 1)
        .read_to_end(&mut bytes)
        .unwrap();
    assert!(bytes.len() as u64 <= limit, "bounded actual CLI output");
    String::from_utf8(bytes).unwrap()
}
fn execute(mut command: Command, directory: &Path, name: &str) -> Output {
    let stdout = directory.join(format!("{name}.stdout"));
    let stderr = directory.join(format!("{name}.stderr"));
    let mut owner = Process(Some(
        command
            .stdout(Stdio::from(fs::File::create_new(&stdout).unwrap()))
            .stderr(Stdio::from(fs::File::create_new(&stderr).unwrap()))
            .spawn()
            .unwrap(),
    ));
    let deadline = Instant::now() + WAIT;
    let status = loop {
        if let Some(status) = owner.0.as_mut().unwrap().try_wait().unwrap() {
            owner.0.take(); // The real child was reaped; never kill a reused PID.
            break status;
        }
        assert!(
            Instant::now() < deadline,
            "actual CLI exceeded90s; owned child killed/reaped"
        );
        std::thread::sleep(Duration::from_millis(10));
    };
    Output {
        status,
        stdout: bounded_text(&stdout, LOG_LIMIT),
        stderr: bounded_text(&stderr, LOG_LIMIT),
    }
}
struct Setup {
    root: tempfile::TempDir,
    kit: PathBuf,
    policy: PathBuf,
}
impl Setup {
    fn new() -> Self {
        let root = tempfile::tempdir().unwrap();
        let kit = root.path().join("kit");
        fs::create_dir(&kit).unwrap();
        fs::create_dir(root.path().join("home")).unwrap();
        fs::write(kit.join("cases.json"), CASES).unwrap();
        let policy = root.path().join("native-policy.json");
        fs::write(&policy, POLICY).unwrap();
        Self { root, kit, policy }
    }
    fn command(&self, action: &str) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_morphir"));
        command
            .current_dir(self.root.path())
            .env("MORPHIR_LOG_FILE", "false")
            .env("MORPHIR_NO_BANNER", "true")
            .env("MORPHIR_HOME", self.root.path().join("home"))
            .env_remove("MORPHIR_LOG_DIR")
            .env_remove("MORPHIR_OUT_DIR")
            .args(["mck", "workbench", action])
            .arg("--kit")
            .arg(&self.kit);
        command
    }
    fn run(&self, report: &Path) -> Command {
        let mut command = self.command("run");
        command
            .args(["--adapter", "builtin:morphir-workbench"])
            .arg("--checker-policy")
            .arg(&self.policy)
            .arg("--report")
            .arg(report);
        command
    }
    fn check(&self, report: &Path) -> Command {
        let mut command = self.command("check");
        command
            .arg("--checker-policy")
            .arg(&self.policy)
            .arg("--report")
            .arg(report);
        command
    }
}

#[test]
fn actual_builtin_native_first_case_checks_all_original_leaves_and_saved_replay_rejects_tamper() {
    let setup = Setup::new();
    let path = setup.root.path().join("actual-native-report.json");
    let output = execute(setup.run(&path), setup.root.path(), "live");
    assert_eq!(output.status.code(), Some(1), "{}", output.stderr);
    assert!(output.stdout.contains("not qualified"));
    let raw = bounded_text(&path, morphir_mck::workbench::MAX_REPORT_BYTES as u64);
    let report = Report::from_json(&raw).unwrap();
    let configuration = RunConfiguration::from_json(POLICY).unwrap();
    assert!(report.as_historical().is_none());
    assert!(
        !report.qualified(),
        "first42 checks cannot qualify all175 roles"
    );
    // SAME checker rebinds all24 reviewed cases and recomputes the full42
    // first-row predicates. This test does not implement their comparison.
    check_report_configured(&setup.kit, &report, &configuration).unwrap();
    let measured: Value = serde_json::from_str(&raw).unwrap();
    assert_eq!(measured["qualified"], false);
    assert!(measured["capabilities"].is_null());
    assert!(measured["negotiation"].is_null());
    let rows = measured["records"].as_array().unwrap();
    assert_eq!(rows.len(), 24);
    let expected: Value = serde_json::from_slice(CASES).unwrap();
    assert_eq!(
        rows.iter()
            .map(|r| r["caseId"].as_str().unwrap())
            .collect::<Vec<_>>(),
        expected["cases"]
            .as_array()
            .unwrap()
            .iter()
            .map(|r| r["id"].as_str().unwrap())
            .collect::<Vec<_>>()
    );
    assert_eq!(rows[0]["caseId"], ID);
    assert_eq!(rows[0]["evidence"]["kind"], "native-measured");
    assert_eq!(rows[0]["evidence"]["verdict"], json!({"kind":"checked"}));
    let first = &rows[0]["evidence"]["measurement"];
    assert_eq!(
        first["profile"],
        "morphir/mck/model-originals-native-server-measurements"
    );
    assert_eq!(first["privateRecord"]["byteLength"], "237");
    assert_eq!(
        first["privateRecord"]["sha256"],
        "8002319afb380077c229776ede0d60eb8634ae49308b74420461b34a59f626d1"
    );
    let last = first["checkpoints"].as_array().unwrap().last().unwrap();
    assert_eq!(last["name"], "all-owned-work-exited");
    assert_eq!(last["source"]["kind"], "sealed-complete");
    assert_eq!(last["source"]["counts"]["ambient"]["attempts"], "0");
    assert_eq!(last["workers"]["kind"], "joined-cleanup");
    assert_eq!(last["workers"]["counts"]["scheduled"], "1");
    assert_eq!(last["workers"]["counts"]["joinedOk"], "1");
    assert_eq!(last["workers"]["counts"]["ownedHandles"], "0");
    assert_eq!(last["workers"]["counts"]["droppedUnjoined"], "0");
    assert_eq!(rows[1]["evidence"]["kind"], "attempt-failed");
    for row in &rows[2..] {
        assert_eq!(
            row["evidence"],
            json!({"kind":"not-attempted","priorFailureIndex":0})
        );
    }
    let replay = execute(setup.check(&path), setup.root.path(), "replay");
    assert_eq!(replay.status.code(), Some(1), "{}", replay.stderr);
    assert!(replay.stdout.contains("not qualified"));
    // Mutations apply only AFTER actual live producer execution and validation.
    // All opaque raw transport payloads remain string values in this DATA.
    let mut tampered = measured.clone();
    let last = tampered["records"][0]["evidence"]["measurement"]["checkpoints"]
        .as_array_mut()
        .unwrap()
        .last_mut()
        .unwrap();
    last["source"]["counts"]["ambient"]["attempts"] = json!("1");
    let forged = Report::from_json(&tampered.to_string()).unwrap();
    assert!(check_report_configured(&setup.kit, &forged, &configuration).is_err());
    let bad = setup.root.path().join("ambient-tampered.json");
    fs::write(&bad, tampered.to_string()).unwrap();
    let refused = execute(setup.check(&bad), setup.root.path(), "tamper");
    assert_eq!(refused.status.code(), Some(1));
    assert!(
        refused.stderr.contains("forged native factual verdict"),
        "{}",
        refused.stderr
    );
    let mut qualification = measured;
    qualification["qualified"] = json!(true);
    let forged = Report::from_json(&qualification.to_string()).unwrap();
    assert!(check_report_configured(&setup.kit, &forged, &configuration).is_err());
    assert_eq!(fs::read(setup.kit.join("cases.json")).unwrap(), CASES);
    assert_eq!(
        fs::read_to_string(&path).unwrap(),
        raw,
        "replay never replaces live evidence"
    );
}

#[test]
fn builtin_native_adapter_refuses_external_arguments_without_publishing_report() {
    let setup = Setup::new();
    let report = setup.root.path().join("must-not-exist.json");
    let mut command = setup.run(&report);
    command.args(["--adapter-arg", "literal-must-not-reach-a-native-producer"]);
    let output = execute(command, setup.root.path(), "args");
    assert_eq!(output.status.code(), Some(2), "{}", output.stderr);
    assert!(!report.exists());
}

#[test]
fn builtin_native_adapter_requires_explicit_native_checker_configuration() {
    let setup = Setup::new();
    for (index, policy) in [None, Some(r#"{"kind":"historical"}"#), Some(CURRENT)]
        .into_iter()
        .enumerate()
    {
        let report = setup.root.path().join(format!("invalid-mode-{index}.json"));
        let mut command = setup.command("run");
        command
            .args(["--adapter", "builtin:morphir-workbench"])
            .arg("--report")
            .arg(&report);
        if let Some(raw) = policy {
            let policy = setup
                .root
                .path()
                .join(format!("invalid-policy-{index}.json"));
            fs::write(&policy, raw).unwrap();
            command.arg("--checker-policy").arg(policy);
        }
        let output = execute(command, setup.root.path(), &format!("mode-{index}"));
        assert_eq!(output.status.code(), Some(2), "{}", output.stderr);
        assert!(!report.exists());
    }
}
