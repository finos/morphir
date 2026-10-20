//! Ignored ACTUAL installed SUT qualification controls, not ordinary unit tests.
//! Explicit inputs select processes, never case/expected/verdict or authority.
use morphir_mck::workbench::{
    Report, RunConfiguration, WorkbenchExecutionMode, check_report_configured,
};
use serde_json::{Value, json};
use std::{
    fs,
    io::Read,
    path::{Path, PathBuf},
    process::{Child, Command, ExitStatus, Stdio},
    time::{Duration, Instant},
};

const CASES: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../morphir-mck/src/workbench/model_originals/workflow/pipeline/installed_client_controls/cases24.json"
));
const ID: &str = "single-file-explicit-companion-preserves-opaque-bytes";
const WAIT: Duration = Duration::from_secs(90);
const LOG_LIMIT: u64 = 1_048_576;

#[derive(Clone, Copy)]
enum Target {
    Node,
    Native,
}
fn explicit_path(name: &str) -> PathBuf {
    let path = PathBuf::from(std::env::var_os(name).unwrap_or_else(|| {
        panic!("manually selected qualification requires explicit absolute {name}")
    }));
    assert!(path.is_absolute(), "{name} must be absolute: {path:?}");
    path
}
struct Inputs {
    package: PathBuf,
    node: PathBuf,
    source: PathBuf,
    native: Option<PathBuf>,
    policy: PathBuf,
}
impl Inputs {
    fn from_environment(target: Target) -> Self {
        Self {
            package: explicit_path("MORPHIR_MCK_INSTALLED_PACKAGE"),
            node: explicit_path("MORPHIR_MCK_INSTALLED_NODE"),
            source: explicit_path("MORPHIR_MCK_INSTALLED_SOURCE_CHECKOUT"),
            native: match target {
                Target::Node => None,
                Target::Native => Some(explicit_path("MORPHIR_MCK_INSTALLED_NATIVE")),
            },
            policy: explicit_path("MORPHIR_MCK_INSTALLED_POLICY"),
        }
    }
}
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
fn execute(mut command: Command, root: &Path, name: &str) -> Output {
    let stdout = root.join(format!("{name}.stdout"));
    let stderr = root.join(format!("{name}.stderr"));
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
            owner.0.take(); // Actual direct child reaped; never signal reused PID.
            break status;
        }
        assert!(Instant::now() < deadline, "actual parent CLI exceeded90s");
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
    policy_text: String,
    configuration: RunConfiguration,
}
impl Setup {
    fn new(inputs: &Inputs) -> Self {
        let root = tempfile::tempdir().unwrap();
        let kit = root.path().join("kit");
        fs::create_dir(&kit).unwrap();
        fs::create_dir(root.path().join("home")).unwrap();
        fs::write(kit.join("cases.json"), CASES).unwrap();
        // Caller owns the finite policy. No positive default, hidden budget
        // adjustment or tiny unit-policy rewrite is installed by these tests.
        let policy_text = bounded_text(
            &inputs.policy,
            morphir_mck::workbench::MAX_REPORT_BYTES as u64,
        );
        let configuration = RunConfiguration::from_json(&policy_text).unwrap();
        assert_eq!(
            configuration.execution_mode(),
            WorkbenchExecutionMode::InstalledOriginals
        );
        let policy = root.path().join("explicit-installed-policy.json");
        fs::write(&policy, &policy_text).unwrap();
        Self {
            root,
            kit,
            policy,
            policy_text,
            configuration,
        }
    }
    fn command(&self, action: &str, report: &Path) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_morphir"));
        command
            .current_dir(self.root.path())
            .env("MORPHIR_LOG_FILE", "false")
            .env("MORPHIR_NO_BANNER", "true")
            .env("MORPHIR_HOME", self.root.path().join("home"))
            .env_remove("MORPHIR_LOG_DIR")
            .env_remove("MORPHIR_OUT_DIR")
            .env_remove("MORPHIR_CONNECTED_HELPER")
            .env_remove("MORPHIR_ORIGINALS_HELPER")
            .args(["mck", "workbench", action])
            .arg("--kit")
            .arg(&self.kit)
            .arg("--checker-policy")
            .arg(&self.policy)
            .arg("--report")
            .arg(report);
        command
    }
    fn run(&self, inputs: &Inputs, target: Target, report: &Path) -> Command {
        let mut command = self.command("run", report);
        command
            .args(["--adapter", "builtin:morphir-workbench"])
            .args(["--timeout", "10000", "--session-timeout", "60000"])
            .arg("--installed-client-target")
            .arg(match target {
                Target::Node => "node",
                Target::Native => "native",
            })
            .arg("--installed-client-package")
            .arg(&inputs.package)
            .arg("--installed-client-node")
            .arg(&inputs.node)
            .arg("--installed-client-source-checkout")
            .arg(&inputs.source);
        if let Some(native) = &inputs.native {
            command.arg("--installed-client-program").arg(native);
        }
        command
    }
}
fn corrupt_actual_destination(measured: &mut Value) {
    let entries = measured["records"][0]["evidence"]["measurement"]["destination"]["rawEntries"]
        .as_array_mut()
        .unwrap();
    let file = entries
        .iter_mut()
        .find(|entry| entry["kind"] == "file")
        .unwrap();
    match file["bytes"]["kind"].as_str().unwrap() {
        "utf8" => {
            let mut text = file["bytes"]["text"].as_str().unwrap().to_owned();
            text.push('#');
            file["bytes"]["text"] = text.into();
        }
        "hex" => {
            let mut hex = file["bytes"]["hex"].as_str().unwrap().to_owned();
            assert!(hex.len() >= 2);
            let replacement = if &hex[..2] == "00" { "01" } else { "00" };
            hex.replace_range(..2, replacement);
            file["bytes"]["hex"] = hex.into();
        }
        other => panic!("actual observed bytes must be retained literal, got {other}"),
    }
}
fn qualify(target: Target) {
    let inputs = Inputs::from_environment(target); // Missing input FAILS, never skips.
    let setup = Setup::new(&inputs);
    let path = setup.root.path().join("actual-installed-report.json");
    let output = execute(setup.run(&inputs, target, &path), setup.root.path(), "live");
    assert_eq!(output.status.code(), Some(1), "{}", output.stderr);
    assert!(output.stdout.contains("not qualified"), "{}", output.stdout);
    let raw = bounded_text(&path, morphir_mck::workbench::MAX_REPORT_BYTES as u64);
    let report = Report::from_json(&raw).unwrap();
    check_report_configured(&setup.kit, &report, &setup.configuration).unwrap();
    assert!(!report.qualified());
    let measured: Value = serde_json::from_str(&raw).unwrap();
    assert_eq!(measured["qualified"], false);
    assert!(measured["capabilities"].is_null());
    assert!(measured["negotiation"].is_null());
    assert_eq!(measured["errors"].as_array().unwrap().len(), 1);
    assert_eq!(measured["errors"][0]["phase"], "observation");
    assert_eq!(measured["errors"][0]["code"], "expected-blocked");
    let rows = measured["records"].as_array().unwrap();
    assert_eq!(rows.len(), 24);
    let source: Value = serde_json::from_slice(CASES).unwrap();
    assert_eq!(
        rows.iter()
            .map(|row| row["caseId"].as_str().unwrap())
            .collect::<Vec<_>>(),
        source["cases"]
            .as_array()
            .unwrap()
            .iter()
            .map(|case| case["id"].as_str().unwrap())
            .collect::<Vec<_>>()
    );
    assert_eq!(rows[0]["caseId"], ID);
    assert_eq!(rows[0]["evidence"]["kind"], "client-process-measured");
    assert_eq!(
        rows[0]["evidence"]["verdict"],
        json!({"kind":"failed","failureIndex":0})
    );
    for row in &rows[1..] {
        assert_eq!(
            row["evidence"],
            json!({"kind":"not-attempted","priorFailureIndex":0})
        );
    }
    let facts = &rows[0]["evidence"]["measurement"];
    let processes = facts["processes"].as_array().unwrap();
    assert_eq!(processes.len(), 3);
    for (process, (index, command)) in
        processes
            .iter()
            .zip([(2, "connect"), (5, "list"), (8, "publish")])
    {
        assert_eq!(process["actionIndex"], index);
        assert_eq!(process["command"], command);
        assert_eq!(
            process["completion"],
            json!({"kind":"finished","exit":{"kind":"code","value":0}})
        );
    }
    let events = facts["host"]["events"].as_array().unwrap();
    for kind in [
        "authenticated-connection",
        "received-text",
        "prepared-send",
        "send-outcome",
    ] {
        assert!(
            events.iter().any(|event| event["event"]["kind"] == kind),
            "actual host event {kind}"
        );
    }
    assert_eq!(
        events
            .iter()
            .filter(|event| event["event"]["kind"] == "ready-record-adopted")
            .count(),
        1
    );
    let requests = events
        .iter()
        .filter(|event| event["event"]["kind"] == "received-text")
        .map(|event| {
            serde_json::from_str::<Value>(event["event"]["payload"].as_str().unwrap()).unwrap()
        })
        .collect::<Vec<_>>();
    for method in [
        "morphir.model-originals.capture",
        "morphir.model-originals.inventory",
        "morphir.model-originals.read",
        "morphir.model-originals.release",
    ] {
        assert!(
            requests.iter().any(|request| request["method"] == method),
            "actual installed RPC {method}"
        );
    }
    assert_eq!(facts["destination"]["coverage"], "complete");
    assert_eq!(facts["destination"]["afterAction"], 8);
    assert!(!facts["destination"]["files"].as_array().unwrap().is_empty());
    for field in [
        "dynamicCommit",
        "dynamicScratchCleanup",
        "clientReleaseAcceptance",
    ] {
        assert_eq!(facts[field], "unobserved");
    }
    // The shared checker above owns exact bytes/ownership/frame correlations.
    // These integration assertions do not implement a second comparator.
    let replay = execute(setup.command("check", &path), setup.root.path(), "replay");
    assert_eq!(replay.status.code(), Some(1), "{}", replay.stderr);
    assert!(replay.stdout.contains("not qualified"));
    let mut tampered = measured;
    corrupt_actual_destination(&mut tampered); // Only AFTER live source-bound check.
    let forged = Report::from_json(&tampered.to_string()).unwrap();
    assert!(check_report_configured(&setup.kit, &forged, &setup.configuration).is_err());
    let bad = setup.root.path().join("destination-tampered.json");
    fs::write(&bad, tampered.to_string()).unwrap();
    let refused = execute(setup.command("check", &bad), setup.root.path(), "tamper");
    assert_eq!(refused.status.code(), Some(1));
    assert!(
        refused.stderr.contains("saved first failure differs"),
        "{}",
        refused.stderr
    );
    assert_eq!(fs::read(setup.kit.join("cases.json")).unwrap(), CASES);
    assert_eq!(
        fs::read_to_string(&setup.policy).unwrap(),
        setup.policy_text
    );
    assert_eq!(fs::read_to_string(&path).unwrap(), raw);
}

#[test]
#[ignore = "requires explicit installed package/Node/source/policy and actual configured runner"]
fn actual_installed_node_runs_canonical_three_commands_and_saved_replay_refuses_tamper() {
    qualify(Target::Node);
}

#[test]
#[ignore = "requires explicit installed package/Node/native/source/policy and actual configured runner"]
fn actual_installed_native_runs_canonical_three_commands_and_saved_replay_refuses_tamper() {
    qualify(Target::Native);
}
