//! Child of installed_mck::processes. Real Run/host/Node/FD/command ownership.
//! Package/source census is explicitly synthetic unit DATA. No measurement is
//! finalized, and no consumer business hook or source/package role qualifies.
#![cfg(all(target_os = "macos", target_arch = "aarch64"))]

use super::super::{RunningHost, fixture};
use super::*;
use morphir_mck::{
    transport::Limits,
    workbench::{
        RunConfiguration,
        model_originals::installed::{
            ConsumerProcessCommand, InstalledClientAction, InstalledClientAdapter,
            InstalledClientMeasurements, InstalledCommand, InstalledProcessPurpose, data,
        },
        run_configured_with_installed_client_adapter,
    },
};
use serde_json::{Value, json};
use sha2::{Digest as _, Sha256};
use std::{
    ffi::{OsStr, OsString},
    io::Read as _,
    path::{Path, PathBuf},
};

const CASES: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/src/commands/ui/model_originals/capture/installed_host_tests/fixtures/cases24.json"
));
const CHECKER: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/src/commands/ui/model_originals/capture/installed_host_tests/fixtures/checker-policy.json"
));
const PEER: &str = include_str!("terminal-peer.cjs");
const WAIT: Duration = Duration::from_secs(10);
const MARKER: &[u8] = b"reference-control-close-retained\n";
const NODE_LENGTH: u64 = 122_503_472;
const NODE_SHA: [u8; 32] = [
    0xb4, 0x68, 0xfb, 0x9c, 0x67, 0x42, 0x7c, 0x9d, 0x3a, 0xec, 0x07, 0xee, 0x11, 0x05, 0xe6, 0x30,
    0x20, 0x92, 0x3a, 0x63, 0x1a, 0x9a, 0x2a, 0x00, 0xbe, 0xb7, 0x1a, 0x7b, 0xa3, 0x76, 0x8b, 0xfd,
];

#[derive(Clone, Copy)]
enum Case {
    Healthy,
    OuterTail,
    HelperTail,
}
impl Case {
    fn selector(self) -> &'static str {
        match self {
            Self::Healthy => "none",
            Self::OuterTail => "outer",
            Self::HelperTail => "helper",
        }
    }
}

fn configuration() -> RunConfiguration {
    // Existing tail-test component limits, plus the explicit opt-in. The two
    // endpoint buffers use this test's 128KiB Limits, not a changed policy.
    RunConfiguration::from_json(&json!({
        "kind":"model-originals-installed-client",
        "checker":serde_json::from_str::<Value>(CHECKER).unwrap(),
        "observation":{"source":{"attempts":8192,"readCalls":8192,"returnedBytes":67108864,"files":16},"workers":{"attempts":64,"updates":8192},"host":{"updates":8192}},
        "privateRecord":{"retainedBytes":67108864},
        "installedObservation":{"rpcFrames":"checker-capture","retainedBytes":16777216,"stdoutPrefixBytes":1048576,"stderrPrefixBytes":1048576,"snapshotReadBytes":16777216,"byteVisits":67108864,"records":8192},
        "consumerObservation":{"mode":"operation-port","version":"0.1.0-draft.1"}
    }).to_string()).unwrap()
}

fn hash_node(program: &Path) -> (u64, [u8; 32]) {
    let file = std::fs::File::open(program).unwrap();
    let metadata = file.metadata().unwrap();
    assert!(
        metadata.is_file(),
        "selected Node must be an actual regular file"
    );
    assert_eq!(metadata.len(), NODE_LENGTH);
    let mut file = file.take(NODE_LENGTH + 1);
    let mut buffer = [0u8; 65536];
    let mut count = 0u64;
    let mut hash = Sha256::new();
    loop {
        let n = file.read(&mut buffer).unwrap();
        if n == 0 {
            break;
        }
        count = count.checked_add(n as u64).unwrap();
        hash.update(&buffer[..n]);
    }
    (count, hash.finalize().into())
}

struct Unit {
    entry: PathBuf,
    arguments: Vec<OsString>,
    implementation: data::ImplementationObservation,
}
fn unit(run: &mut InstalledClientRun<'_>, node: &Path, directory: &Path) -> Unit {
    let package = run
        .command_path(directory, "terminal-unit-package")
        .unwrap();
    let entry = run.command_path(&package, "bin/morphir.js").unwrap();
    let helper = run
        .command_path(&package, "build-provider/originals.mjs")
        .unwrap();
    let launch = run.command_path(directory, "terminal-unit-launch").unwrap();
    let connection = run
        .command_path(directory, "terminal-unit-connection")
        .unwrap();
    let source = run.command_path(directory, "terminal-unit-source").unwrap();
    let project = run
        .command_path(directory, "terminal-unit-project")
        .unwrap();
    let Some(InstalledClientAction::Run {
        command: InstalledCommand::Publish,
        arguments,
    }) = run.actions().nth(8)
    else {
        panic!("genuine canonical Publish source required");
    };
    // Same closed source-derived resolver as the maintained Node launch path.
    // No expected/oracle operand enters this unit association.
    let resolved = (0..arguments.len() + 3).map(|index| {
        if index == 0 {
            return entry.as_os_str();
        }
        let index = index - 1;
        if index == arguments.len() {
            return OsStr::new("--originals-helper");
        }
        if index > arguments.len() {
            return helper.as_os_str();
        }
        match arguments[index].as_str() {
            "$launchFile" => launch.as_os_str(),
            "$connectionFile" => connection.as_os_str(),
            "$sourceSelectionFile" => source.as_os_str(),
            "$projectSelectionFile" => project.as_os_str(),
            "$destination" => OsStr::new("destination"),
            "$verifiedNodeRuntime" => node.as_os_str(),
            literal if !literal.starts_with('$') => OsStr::new(literal),
            _ => panic!("unexpected compiled operand in closed TEST fixture"),
        }
    });
    let arguments = run.copy_command_arguments(resolved).unwrap();
    let implementation = data::ImplementationObservation::Observed {
        before_action: data::Natural::new(2).unwrap(),
        launch: data::LaunchObservation::NodePackage {
            entry: run.observation_operand(entry.as_os_str()).unwrap(),
        },
        runtime: data::RuntimeObservation {
            program: run.observation_operand(node.as_os_str()).unwrap(),
            byte_length: data::Natural::new(NODE_LENGTH).unwrap(),
            sha256: data::ContentSha256::new(NODE_SHA),
            version: data::VersionObservation::Unobserved {},
        },
        command_paths: data::CommandPaths {
            launch_file: run.observation_operand(launch.as_os_str()).unwrap(),
            connection_file: run.observation_operand(connection.as_os_str()).unwrap(),
            source_selection_file: run.observation_operand(source.as_os_str()).unwrap(),
            project_selection_file: run.observation_operand(project.as_os_str()).unwrap(),
            destination: run.observation_operand(OsStr::new("destination")).unwrap(),
        },
        package: data::PackageCensus {
            root: run.observation_operand(package.as_os_str()).unwrap(),
            entries: data::Items::new(Vec::new()).unwrap(),
            sha256: data::ContentSha256::new([0; 32]),
        },
        source: data::SourceAssociation {
            root: run.observation_operand(directory.as_os_str()).unwrap(),
            head: run
                .observation_text("0000000000000000000000000000000000000000")
                .unwrap(),
            object_format: data::ObjectFormat::Sha1,
            tracked_status: data::TrackedStatus::Unchanged,
            entries: data::Items::new(Vec::new()).unwrap(),
            sha256: data::ContentSha256::new([0; 32]),
        },
        metadata_tools: data::Items::new(Vec::new()).unwrap(),
    };
    Unit {
        entry,
        arguments,
        implementation,
    }
}

#[derive(Debug, PartialEq, Eq)]
enum CommandReturn {
    Finished,
    Refused,
    Missing,
}
struct UiTerminalEvidence {
    returned: CommandReturn,
    framing_report: bool,
}
struct Probe {
    node: PathBuf,
    case: Case,
    entered: bool,
    returned: Option<CommandReturn>,
}
impl InstalledClientAdapter for Probe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        self.entered = true;
        assert_eq!(
            run.source().case_id(),
            "single-file-explicit-companion-preserves-opaque-bytes"
        );
        let returned = tokio::runtime::Handle::current().block_on(async {
            let end = Instant::now() + WAIT;
            let interrupted = AtomicBool::new(false);
            let fixture = fixture::Fixture::materialize(&mut run, end, &interrupted).unwrap();
            let mut host = RunningHost::start(&mut run, &fixture, end, &interrupted)
                .await
                .unwrap();
            run.bind_consumer_window(end.into_std()).unwrap();
            let unit = unit(&mut run, &self.node, &fixture.base);
            std::fs::create_dir_all(unit.entry.parent().unwrap()).unwrap();
            std::fs::write(&unit.entry, PEER).unwrap();
            let environment = [(
                run.copy_command_operand(OsStr::new("MORPHIR_TEST_TERMINAL_TAIL"))
                    .unwrap(),
                run.copy_command_operand(OsStr::new(self.case.selector()))
                    .unwrap(),
            )];
            let (prepared, ports) = run
                .prepare_consumer_operation(
                    ConsumerProcessCommand {
                        purpose: InstalledProcessPurpose::Canonical {
                            action_index: 8,
                            command: InstalledCommand::Publish,
                        },
                        program: &self.node,
                        arguments: &unit.arguments,
                        directory: &fixture.base,
                        environment: &environment,
                        limits: Limits {
                            max_frame: 131072,
                            stderr_capture: 1024,
                            ..Limits::DEFAULT
                        },
                    },
                    end.into_std(),
                    &unit.implementation,
                )
                .unwrap();
            let process = run.spawn_prepared_consumer_process(prepared).unwrap();
            let mut command = Command::operation(process, ports);
            // Real production collection/advance ACKs both Close, then waits
            // for actual child exit, consuming reap and reader completion.
            // No terminal read occurs in this setup; any tail stays queued.
            let setup = async {
                let Command::Operation(operation) = &mut command else {
                    unreachable!()
                };
                loop {
                    if Instant::now() >= end {
                        return Err("setup reached original end");
                    }
                    operation
                        .advance_observed(&mut run, &mut host.runtime.events)
                        .map_err(|_| "actual process advancement failed")?;
                    if [
                        ConsumerProducerRole::Outer,
                        ConsumerProducerRole::TransferHelper,
                    ]
                    .into_iter()
                    .any(|role| {
                        operation.ports.transport_state(role) != ConsumerTransportState::Closed
                    }) {
                        operation
                            .collect(&mut run)
                            .map_err(|_| "actual Open/Close exchange failed")?;
                    }
                    if matches!(operation.process, Some(OperationProcess::Finished(_)))
                        && [
                            ConsumerProducerRole::Outer,
                            ConsumerProducerRole::TransferHelper,
                        ]
                        .into_iter()
                        .all(|role| {
                            operation.ports.transport_state(role) == ConsumerTransportState::Closed
                        })
                    {
                        break;
                    }
                    tokio::time::sleep_until(end.min(Instant::now() + Duration::from_millis(1)))
                        .await;
                }
                Ok::<_, &'static str>(())
            }
            .await;
            let outcome = if setup.is_ok() {
                Some(
                    command
                        .execute(&mut run, &mut host.runtime.events, end, &interrupted)
                        .await,
                )
            } else {
                None
            };
            // Finished-before-execute is a genuine setup premise, so OLD UI
            // returns Ok despite queued extra bytes. Cleanup happens on RED too.
            let process_cleanup = command.terminate(end).await;
            let host_cleanup = host.stop(end).await;
            let actual_finished = match &command {
                Command::Operation(operation) => match operation.process.as_ref() {
                    Some(OperationProcess::Finished(finished)) => Some(finished),
                    _ => None,
                },
                _ => None,
            };
            let process_ok = actual_finished.is_some_and(|finished| {
                finished.outcome().status().code() == Some(0)
                    && finished.outcome().first_fault().is_none()
                    && finished.outcome().stdout() == MARKER
                    && finished.outcome().stderr().is_empty()
            });
            let returned = match outcome.as_ref() {
                Some(Ok(_)) => CommandReturn::Finished,
                Some(Err(InstalledAdapterError::ObservationIncomplete)) => CommandReturn::Refused,
                Some(Err(InstalledAdapterError::Cancelled)) | None => CommandReturn::Missing,
            };
            let joined = host.runtime.listener.is_none()
                && matches!(
                    host.runtime.socket_cleanup,
                    super::super::super::socket_tasks::SocketCleanup::Joined
                )
                && host.runtime.cleanup.retained_handles() == 0;
            drop(outcome);
            drop(command);
            drop(host);
            drop(unit);
            drop(fixture);
            assert!(setup.is_ok(), "{setup:?}");
            assert!(process_cleanup.is_ok() && host_cleanup.is_ok());
            assert!(
                process_ok && joined,
                "real child/readers/host must finish before terminal assertions"
            );
            returned
        });
        self.returned = Some(returned);
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}

async fn exercise(case: Case) -> UiTerminalEvidence {
    let node = PathBuf::from(
        std::env::var_os("MORPHIR_MCK_INSTALLED_NODE").expect("explicit selected Node required"),
    )
    .canonicalize()
    .unwrap();
    let before = hash_node(&node);
    assert_eq!(before, (NODE_LENGTH, NODE_SHA));
    let kit = tempfile::tempdir().unwrap();
    std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
    let mut probe = Probe {
        node: node.clone(),
        case,
        entered: false,
        returned: None,
    };
    let report = tokio::task::block_in_place(|| {
        run_configured_with_installed_client_adapter(kit.path(), &configuration(), &mut probe)
    })
    .unwrap();
    assert!(probe.entered, "complete24 genuine callback required");
    let raw = report.to_json();
    assert!(!report.qualified());
    assert!(!raw.contains("client-process-measured"));
    let report: Value = serde_json::from_str(&raw).unwrap();
    let framing_report = report["errors"][0]["phase"] == "installed-consumer"
        && report["errors"][0]["code"] == "framing";
    assert_eq!(hash_node(&node), before);
    UiTerminalEvidence {
        returned: probe
            .returned
            .expect("actual cleanup completed before evidence"),
        framing_report,
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
#[ignore = "requires selected Node b468; actual UI transport only"]
async fn actual_ui_healthy_close_and_postexit_eof_returns_finished() {
    let evidence = exercise(Case::Healthy).await;
    assert_eq!(evidence.returned, CommandReturn::Finished);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
#[ignore = "requires selected Node b468; actual UI transport only"]
async fn actual_ui_postclose_tail_for_either_role_refuses_after_child_and_readers_finish() {
    // Both actual children and hosts are joined before an intended RED, so
    // the first role's rejection assertion cannot skip the other real setup.
    let outer = exercise(Case::OuterTail).await;
    let helper = exercise(Case::HelperTail).await;
    for evidence in [outer, helper] {
        assert_eq!(evidence.returned, CommandReturn::Refused);
        assert!(
            evidence.framing_report,
            "exact installed-consumer/framing required"
        );
    }
}
