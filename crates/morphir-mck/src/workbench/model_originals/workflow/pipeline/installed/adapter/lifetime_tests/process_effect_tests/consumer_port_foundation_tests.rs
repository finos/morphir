//! Prospective raw-I/O foundation controls through a genuine compiled Run.
//! The actual MEP test peer is not a production helper or consumer-fact producer.
//! Test-only borrowed handles inspect real endpoints, never issue authority.
use super::*;
use crate::workbench::model_originals::workflow::pipeline::installed::adapter::processes::{
    ConsumerProcessCommand, ConsumerProducerRole, InstalledConsumerPorts,
    PreparedInstalledConsumerProcess,
};

#[derive(Clone, Copy)]
enum Scenario {
    RoundTrip,
    DropPrepared,
    SpawnFailure,
    ZeroStorage,
    LegacyDisabled,
    WrongAction,
    Expired,
    CallbackRevoked,
    Unbound,
    Rebind,
    DropBeforeClaim,
    DropAfterClaim,
}
struct FoundationProbe {
    owner: std::sync::Arc<TestGateOwner>,
    program: PathBuf,
    directory: PathBuf,
    marker: PathBuf,
    scenario: Scenario,
    entered: bool,
    escaped: Option<(PreparedInstalledConsumerProcess, InstalledConsumerPorts)>,
}
fn eof(handle: std::os::fd::BorrowedFd<'_>) -> bool {
    let observed = rustix::io::read(handle, &mut [0u8; 1]);
    if !matches!(observed, Ok(0)) {
        eprintln!("[DEBUG-consumer-eof] actual single read: {observed:?}");
    }
    matches!(observed, Ok(0))
}
fn parent_flags(handle: std::os::fd::BorrowedFd<'_>) -> bool {
    use std::os::fd::AsRawFd as _;
    unsafe extern "C" {
        fn fcntl(fd: i32, operation: i32, ...) -> i32;
    }
    // Read-only SDK F_GETFD/F_GETFL on the exact live borrowed endpoint.
    let descriptor = unsafe { fcntl(handle.as_raw_fd(), 1) };
    let status = unsafe { fcntl(handle.as_raw_fd(), 3) };
    descriptor >= 0 && descriptor & 1 != 0 && status >= 0 && status & 4 != 0
}
fn isolated_roles(
    prepared: &PreparedInstalledConsumerProcess,
    ports: &InstalledConsumerPorts,
) -> bool {
    let mut byte = [0u8; 1];
    for (role, other, value) in [
        (
            ConsumerProducerRole::Outer,
            ConsumerProducerRole::TransferHelper,
            b'A',
        ),
        (
            ConsumerProducerRole::TransferHelper,
            ConsumerProducerRole::Outer,
            b'B',
        ),
    ] {
        if !matches!(
            rustix::io::write(ports.test_parent_handle(role), &[value]),
            Ok(1)
        ) || !matches!(
            rustix::io::read(prepared.test_child_handle(other), &mut byte),
            Err(rustix::io::Errno::AGAIN)
        ) || !matches!(
            rustix::io::read(prepared.test_child_handle(role), &mut byte),
            Ok(1)
        ) || byte != [value]
        {
            return false;
        }
    }
    true
}
fn exchange(handle: std::os::fd::BorrowedFd<'_>, expected: u8, response: u8, end: Instant) -> bool {
    let mut byte = [0u8; 1];
    loop {
        match rustix::io::read(handle, &mut byte) {
            Ok(1) => break,
            Err(rustix::io::Errno::AGAIN | rustix::io::Errno::INTR) => {}
            _ => return false,
        }
        if Instant::now() >= end {
            return false;
        }
        std::thread::sleep(Duration::from_millis(1));
    }
    if byte != [expected] {
        return false;
    }
    loop {
        match rustix::io::write(handle, &[response]) {
            Ok(1) => return true,
            Err(rustix::io::Errno::AGAIN | rustix::io::Errno::INTR) => {}
            _ => return false,
        }
        if Instant::now() >= end {
            return false;
        }
        std::thread::sleep(Duration::from_millis(1));
    }
}
impl InstalledClientAdapter for FoundationProbe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        assert!(!self.entered);
        self.entered = true;
        let projection: std::sync::Arc<dyn InvocationGateSource> = self.owner.clone();
        let _token = run
            .issue_host_observation(std::sync::Arc::downgrade(&projection))
            .unwrap();
        assert!(matches!(
            run.actions().nth(8),
            Some(InstalledClientAction::Run {
                command: InstalledCommand::Publish,
                ..
            })
        ));
        let arguments = [
            OsString::from("--adapter"),
            OsString::from("installed-consumer-port-foundation"),
            self.marker.as_os_str().to_owned(),
        ];
        let program = if matches!(self.scenario, Scenario::SpawnFailure) {
            self.directory.join("actual-missing-executable")
        } else {
            self.program.clone()
        };
        let purpose = if matches!(self.scenario, Scenario::WrongAction) {
            InstalledProcessPurpose::Canonical {
                action_index: 2,
                command: InstalledCommand::Connect,
            }
        } else {
            InstalledProcessPurpose::Canonical {
                action_index: 8,
                command: InstalledCommand::Publish,
            }
        };
        let end = if matches!(self.scenario, Scenario::Expired) {
            Instant::now() - Duration::from_millis(1)
        } else {
            Instant::now() + Duration::from_secs(10)
        };
        if !matches!(self.scenario, Scenario::LegacyDisabled | Scenario::Unbound) {
            let binding = run.bind_consumer_window(end);
            if matches!(self.scenario, Scenario::Expired) {
                assert!(binding.is_err(), "expired original end cannot bind");
                assert!(!self.marker.exists());
                return Err(InstalledAdapterError::ObservationIncomplete);
            }
            binding.expect("one source-backed original callback end binds before effects");
            if matches!(self.scenario, Scenario::Rebind) {
                assert!(
                    run.bind_consumer_window(end + Duration::from_secs(1))
                        .is_err(),
                    "later caller cannot replace or extend the bound end"
                );
                assert!(!self.marker.exists());
                return Err(InstalledAdapterError::ObservationIncomplete);
            }
        }
        let result = run.prepare_consumer_process(
            ConsumerProcessCommand {
                purpose,
                program: &program,
                arguments: &arguments,
                directory: &self.directory,
                environment: &[],
                limits: Limits {
                    max_frame: 131072,
                    stderr_capture: 128,
                    ..Limits::DEFAULT
                },
            },
            end,
        );
        match self.scenario {
            Scenario::LegacyDisabled
            | Scenario::WrongAction
            | Scenario::Expired
            | Scenario::Unbound
            | Scenario::ZeroStorage => {
                let refused = result.is_err();
                drop(result);
                assert!(
                    refused,
                    "invalid selection/purpose/end or real storage permission must refuse preparation"
                );
                assert!(!self.marker.exists());
                if matches!(self.scenario, Scenario::ZeroStorage) {
                    let fault = match run.receiving.ready() {
                        Err(fault) => *fault,
                        Ok(()) => panic!("real cumulative receiving fault required"),
                    };
                    assert!(matches!(
                        fault,
                        InstalledObservationError::Resource {
                            kind: InstalledObservationResource::RetainedBytes,
                            ..
                        }
                    ));
                    assert_eq!(run.installed_observation_usage().retained_bytes(), 0);
                    let used = run.installed_observation_usage();
                    let retried = run.prepare_consumer_process(
                        ConsumerProcessCommand {
                            purpose,
                            program: &program,
                            arguments: &arguments,
                            directory: &self.directory,
                            environment: &[],
                            limits: Limits {
                                max_frame: 131072,
                                stderr_capture: 128,
                                ..Limits::DEFAULT
                            },
                        },
                        end,
                    );
                    assert!(retried.is_err());
                    drop(retried);
                    assert_eq!(run.receiving.ready().err(), Some(&fault));
                    assert_eq!(run.installed_observation_usage(), used);
                }
            }
            _ => {
                let (prepared, ports) = result
                    .expect("explicit source-issued Publish prepares actual funded role endpoints");
                let isolated = isolated_roles(&prepared, &ports);
                let flags = [
                    ConsumerProducerRole::Outer,
                    ConsumerProducerRole::TransferHelper,
                ]
                .into_iter()
                .all(|role| {
                    parent_flags(prepared.test_child_handle(role))
                        && parent_flags(ports.test_parent_handle(role))
                });
                if !isolated || !flags {
                    drop(prepared);
                    drop(ports);
                    panic!(
                        "actual independent parent/child endpoints must be CLOEXEC and nonblocking"
                    );
                }
                if matches!(
                    self.scenario,
                    Scenario::DropBeforeClaim | Scenario::DropAfterClaim
                ) {
                    let after_claim = matches!(self.scenario, Scenario::DropAfterClaim);
                    let result = if after_claim {
                        run.test_spawn_after_consumer_claim(prepared, || drop(ports))
                    } else {
                        drop(ports);
                        run.spawn_prepared_consumer_process(prepared)
                    };
                    let actual_child = result.is_ok();
                    if let Ok(process) = result {
                        drop(actual_finish(process));
                    }
                    assert_eq!(
                        actual_child, after_claim,
                        "post-claim collector loss must preserve actual returned child ownership"
                    );
                    assert!(matches!(
                        run.receiving.ready(),
                        Err(InstalledObservationError::Abandoned)
                    ));
                    assert!(
                        run.prepare_snapshot_read(1).is_err(),
                        "same observer fault stays sticky after actual cleanup"
                    );
                    if !after_claim {
                        assert!(!self.marker.exists());
                    }
                    return Err(InstalledAdapterError::ObservationIncomplete);
                }
                if matches!(self.scenario, Scenario::CallbackRevoked) {
                    self.escaped = Some((prepared, ports));
                    return Err(InstalledAdapterError::ObservationIncomplete);
                }
                if matches!(self.scenario, Scenario::DropPrepared) {
                    drop(prepared);
                    let closed = eof(ports.test_parent_handle(ConsumerProducerRole::Outer))
                        && eof(ports.test_parent_handle(ConsumerProducerRole::TransferHelper));
                    drop(ports);
                    assert!(
                        closed,
                        "both unused child ends must close while actual collector ends remain owned"
                    );
                    assert!(!self.marker.exists());
                } else {
                    match run.spawn_prepared_consumer_process(prepared) {
                        Err(error) => {
                            let closed = eof(ports.test_parent_handle(ConsumerProducerRole::Outer))
                                && eof(
                                    ports.test_parent_handle(ConsumerProducerRole::TransferHelper)
                                );
                            drop(ports);
                            assert!(matches!(self.scenario, Scenario::SpawnFailure));
                            assert_eq!(error, InstalledAdapterError::ObservationIncomplete);
                            assert!(
                                closed,
                                "failed spawn closes every untransferred child-end copy"
                            );
                            assert!(!self.marker.exists());
                        }
                        Ok(mut process) => {
                            let exchanged = exchange(
                                ports.test_parent_handle(ConsumerProducerRole::Outer),
                                b'O',
                                b'o',
                                end,
                            ) && exchange(
                                ports.test_parent_handle(ConsumerProducerRole::TransferHelper),
                                b'H',
                                b'h',
                                end,
                            );
                            if !exchanged {
                                let _ = process.request_termination();
                            }
                            let finished = actual_finish(process);
                            let status = finished.outcome().status().code();
                            let fault = finished.outcome().first_fault().copied();
                            let output = finished.outcome().stdout().to_vec();
                            drop(finished);
                            let no_parent_child_copy =
                                eof(ports.test_parent_handle(ConsumerProducerRole::Outer))
                                    && eof(ports
                                        .test_parent_handle(ConsumerProducerRole::TransferHelper));
                            drop(ports);
                            assert!(matches!(self.scenario, Scenario::RoundTrip));
                            assert!(
                                exchanged,
                                "both SAME actual role endpoints must exchange bytes independently"
                            );
                            assert_eq!(status, Some(0));
                            assert!(
                                no_parent_child_copy,
                                "genuine child close must reach EOF with collector owners still alive"
                            );
                            assert_eq!(fault, None);
                            assert_eq!(output, b"consumer-port-entry-v1\n");
                            assert_eq!(std::fs::read(&self.marker).unwrap(), b"both-owned\n");
                        }
                    }
                }
            }
        }
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
fn foundation_policy() -> serde_json::Value {
    let mut policy: serde_json::Value = serde_json::from_str(include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/src/workbench/installed_borrowed_controls/installed-policy.json"
    )))
    .unwrap();
    // Same explicit positive peer permissions as effect_configuration. The
    // borrowed-copy seed's 10/6-byte prefixes cannot reserve this real child.
    // This is a test caller policy, never a selected production default.
    policy["privateRecord"] = serde_json::json!({"retainedBytes":67108864});
    policy["installedObservation"] = serde_json::json!({
        "rpcFrames":"checker-capture", "retainedBytes":16777216,
        "stdoutPrefixBytes":131072, "stderrPrefixBytes":128,
        "snapshotReadBytes":16777216, "byteVisits":67108864, "records":8192
    });
    policy
}
/// Explicit operation-record scenarios retain their existing headroom and
/// additionally prepay the one full report destination and its bounded work.
/// Other foundation callers keep their original, deliberately smaller policy.
fn funded_operation_record_policy() -> serde_json::Value {
    funded_consumer_policy(Limits {
        max_frame: 65536,
        stderr_capture: 64,
        ..Limits::DEFAULT
    })
}
fn funded_consumer_policy(limits: Limits) -> serde_json::Value {
    let mut policy = foundation_policy();
    let r = usize::try_from(policy["checker"]["decode"]["savedBytes"].as_u64().unwrap())
        .unwrap()
        .min(crate::workbench::MAX_REPORT_BYTES);
    let d = crate::json::strict::requested_serializer_io_storage_bound().unwrap();
    let retained = r.checked_add(d).unwrap();
    let work = limits
        .max_frame
        .checked_add(limits.stderr_capture)
        .unwrap()
        .checked_add(r.checked_mul(8).unwrap())
        .unwrap()
        .checked_add(20)
        .unwrap()
        .checked_add(d)
        .unwrap();
    let retained = policy["installedObservation"]["retainedBytes"]
        .as_u64()
        .unwrap()
        .checked_add(u64::try_from(retained).unwrap())
        .unwrap();
    let visits = policy["installedObservation"]["byteVisits"]
        .as_u64()
        .unwrap()
        .checked_add(u64::try_from(work).unwrap())
        .unwrap();
    policy["installedObservation"]["retainedBytes"] = retained.into();
    policy["installedObservation"]["byteVisits"] = visits.into();
    policy
}
fn exercise_foundation(scenario: Scenario) {
    let kit = tempfile::tempdir().unwrap();
    std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
    let mut policy = match scenario {
        Scenario::RoundTrip
        | Scenario::DropPrepared
        | Scenario::SpawnFailure
        | Scenario::CallbackRevoked
        | Scenario::DropBeforeClaim
        | Scenario::DropAfterClaim => funded_consumer_policy(Limits {
            max_frame: 131072,
            stderr_capture: 128,
            ..Limits::DEFAULT
        }),
        _ => foundation_policy(),
    };
    if !matches!(scenario, Scenario::LegacyDisabled) {
        policy["consumerObservation"] =
            serde_json::json!({"mode":"operation-port","version":"0.1.0-draft.1"});
    }
    if matches!(scenario, Scenario::ZeroStorage) {
        policy["installedObservation"]["retainedBytes"] = 0.into();
    }
    let configuration = RunConfiguration::from_json(&policy.to_string()).unwrap();
    let mut probe = FoundationProbe {
        owner: std::sync::Arc::new(TestGateOwner {
            gate: InvocationGate::dormant(),
        }),
        program: PathBuf::from(
            std::env::var_os("MORPHIR_MCK_REPORT_PEER_BIN")
                .expect("explicit fresh actual MEP peer required"),
        )
        .canonicalize()
        .unwrap(),
        directory: kit.path().canonicalize().unwrap(),
        marker: kit.path().join("actual-consumer-ports.marker"),
        scenario,
        entered: false,
        escaped: None,
    };
    let report =
        run_configured_with_installed_client_adapter(kit.path(), &configuration, &mut probe)
            .unwrap();
    let escaped = probe.escaped.take();
    if let Some((prepared, ports)) = escaped {
        let revoked = eof(prepared.test_child_handle(ConsumerProducerRole::Outer))
            && eof(prepared.test_child_handle(ConsumerProducerRole::TransferHelper));
        drop(prepared);
        drop(ports);
        assert!(
            revoked,
            "external canonical callback revoker must close both actual peer directions"
        );
    }
    assert!(probe.entered, "genuine complete24 callback must execute");
    assert!(!report.qualified());
}
#[test]
fn consumer_ports_real_publish_peer_exchanges_both_owned_roles_and_joins() {
    exercise_foundation(Scenario::RoundTrip);
}
#[test]
fn consumer_ports_unused_prepared_and_failed_spawn_close_child_copies() {
    for scenario in [Scenario::DropPrepared, Scenario::SpawnFailure] {
        exercise_foundation(scenario);
    }
}
#[test]
fn consumer_ports_zero_storage_is_real_preparation_refusal() {
    exercise_foundation(Scenario::ZeroStorage);
}
#[test]
fn consumer_ports_legacy_wrong_action_and_expired_end_cannot_prepare() {
    for scenario in [
        Scenario::LegacyDisabled,
        Scenario::WrongAction,
        Scenario::Expired,
        Scenario::Unbound,
        Scenario::Rebind,
    ] {
        exercise_foundation(scenario);
    }
}
#[test]
fn consumer_ports_external_callback_revocation_reaches_owned_peers() {
    exercise_foundation(Scenario::CallbackRevoked);
}

// Additive independent refusal controls; original foundation bodies unchanged.
mod encoded_port_tests;
mod supplemental;
#[test]
fn collector_drop_before_claim_refuses_actual_spawn() {
    exercise_foundation(Scenario::DropBeforeClaim);
}
#[test]
fn collector_drop_after_claim_preserves_actual_child_and_reader_joins() {
    exercise_foundation(Scenario::DropAfterClaim);
}

mod deadline_tests;
