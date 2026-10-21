//! Actual external consumer52 and independent actual UI host per control.
//! Explicit inputs only. No replacement producer, synthetic association or SUT build.
use super::*;
use crate::commands::ui::installed_mck::InstalledWorkbenchAdapter;
use installed_launch::{InstalledLaunch, InstalledTarget};
use morphir_mck::workbench::{ConsumerObservationSelection, OperationPortRevision};
use serde_json::{Value, json};

const CASES: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../morphir-mck/src/workbench/model_originals/workflow/pipeline/installed_client_controls/cases24.json"
));
const SOURCE52: &str = "52adc3bc7278de8ce49632518c52ec6196828368";

#[derive(Clone, Copy)]
enum Target {
    Node,
    Native,
}
fn input(name: &str) -> PathBuf {
    let path = PathBuf::from(
        std::env::var_os(name)
            .unwrap_or_else(|| panic!("explicit actual52 input required: {name}")),
    );
    assert!(path.is_absolute(), "{name} must be absolute");
    path
}
struct Actual52 {
    root: tempfile::TempDir,
    kit: PathBuf,
    configuration: RunConfiguration,
    policy_text: String,
    launch: Option<InstalledLaunch>,
}
impl Actual52 {
    fn prepare(target: Target) -> Self {
        let root = tempfile::tempdir().unwrap();
        let kit = root.path().join("kit");
        std::fs::create_dir(&kit).unwrap();
        std::fs::write(kit.join("cases.json"), CASES).unwrap();
        let policy_text = std::fs::read_to_string(input("MORPHIR_MCK_INSTALLED_POLICY")).unwrap();
        let configuration = RunConfiguration::from_json(&policy_text).unwrap();
        assert_eq!(
            configuration.consumer_observation(),
            ConsumerObservationSelection::OperationPort(OperationPortRevision::Draft1)
        );
        let args = RunArgs {
            kit: kit.clone(),
            adapter: "builtin:morphir-workbench".into(),
            adapter_args: Vec::new(),
            report: root.path().join("report.json"),
            checker_policy: None,
            installed_client_target: Some(match target {
                Target::Node => InstalledTarget::Node,
                Target::Native => InstalledTarget::Native,
            }),
            installed_client_package: Some(input("MORPHIR_MCK_INSTALLED_PACKAGE")),
            installed_client_node: Some(input("MORPHIR_MCK_INSTALLED_NODE")),
            installed_client_program: match target {
                Target::Node => None,
                Target::Native => Some(input("MORPHIR_MCK_INSTALLED_NATIVE")),
            },
            installed_client_source_checkout: Some(input("MORPHIR_MCK_INSTALLED_SOURCE_CHECKOUT")),
            timeout: 10_000,
            session_timeout: 60_000,
        };
        let WorkbenchLaunch::InstalledClient(launch) =
            WorkbenchLaunch::select(&args, configuration.execution_mode()).unwrap()
        else {
            panic!("actual installed selection")
        };
        Self {
            root,
            kit,
            configuration,
            policy_text,
            launch: Some(launch),
        }
    }
    fn adapter(&mut self) -> InstalledWorkbenchAdapter {
        InstalledWorkbenchAdapter::new(
            self.launch.take().unwrap(),
            Limits {
                request_timeout: Duration::from_secs(10),
                session_timeout: Duration::from_secs(60),
                ..Limits::DEFAULT
            },
            Arc::new(AtomicBool::new(false)),
        )
    }
    fn run(&self, adapter: &mut InstalledWorkbenchAdapter) -> Report {
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(4)
            .enable_all()
            .build()
            .unwrap();
        let report = runtime.block_on(async {
            tokio::task::block_in_place(|| {
                run_configured_with_installed_client_adapter(
                    &self.kit,
                    &self.configuration,
                    adapter,
                )
            })
            .unwrap()
        });
        // The real adapter has returned after actual process/readers and host
        // cleanup. Report assertions never use Drop as completion evidence.
        assert!(!report.qualified());
        assert_eq!(std::fs::read(self.kit.join("cases.json")).unwrap(), CASES);
        assert_eq!(
            RunConfiguration::from_json(&self.policy_text)
                .unwrap()
                .consumer_observation(),
            self.configuration.consumer_observation()
        );
        std::fs::write(self.root.path().join("report.json"), report.to_json()).unwrap();
        report
    }
}
fn frames<'a>(record: &'a Value, role: &str) -> &'a Vec<Value> {
    let endpoints = record["endpoints"].as_array().unwrap();
    assert_eq!(endpoints.len(), 2);
    let found = endpoints
        .iter()
        .filter(|row| row["role"] == role)
        .collect::<Vec<_>>();
    assert_eq!(found.len(), 1);
    found[0]["frames"].as_array().unwrap()
}
fn fact<'a>(record: &'a Value, kind: &str) -> (&'a Value, Value) {
    let rows = [frames(record, "outer"), frames(record, "transfer-helper")];
    let found = rows
        .into_iter()
        .flatten()
        .filter_map(|row| {
            let body: Value = serde_json::from_str(row["literal"].as_str().unwrap()).unwrap();
            (body["kind"] == "fact" && body["fact"]["kind"] == kind).then_some((row, body))
        })
        .collect::<Vec<_>>();
    assert_eq!(found.len(), 1, "actual retained unique {kind}");
    found.into_iter().next().unwrap()
}

#[path = "operation_record_tests/actual52_healthy_tests.rs"]
mod actual52_healthy_tests;
#[path = "operation_record_tests/saved_operation_mutations.rs"]
mod saved_operation_mutations;

#[path = "operation_record_tests/actual52_ack_loss_tests.rs"]
mod actual52_ack_loss_tests;

#[path = "operation_record_tests/actual52_report_export.rs"]
mod actual52_report_export;
#[path = "operation_record_tests/partial_context_tests.rs"]
mod partial_context_tests;
