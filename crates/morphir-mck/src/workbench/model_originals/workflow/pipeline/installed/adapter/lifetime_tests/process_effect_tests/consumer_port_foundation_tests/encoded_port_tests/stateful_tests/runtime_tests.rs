//! Actual selected Node reference transport. NOT consumer or report evidence.
//! Child of stateful_tests, reusing its explicitly SYNTHETIC association fixture.
use super::*;
use sha2::{Digest as _, Sha256};
use std::io::Read as _;

const SELECTED_SHA: [u8; 32] = [
    0xb4, 0x68, 0xfb, 0x9c, 0x67, 0x42, 0x7c, 0x9d, 0x3a, 0xec, 0x07, 0xee, 0x11, 0x05, 0xe6, 0x30,
    0x20, 0x92, 0x3a, 0x63, 0x1a, 0x9a, 0x2a, 0x00, 0xbe, 0xb7, 0x1a, 0x7b, 0xa3, 0x76, 0x8b, 0xfd,
];
const SELECTED_LENGTH: u64 = 122_503_472;
fn hash_file(program: &Path) -> (u64, [u8; 32]) {
    let mut file = std::fs::File::open(program).unwrap();
    let mut buffer = [0u8; 65536];
    let mut bytes = 0u64;
    let mut hash = Sha256::new();
    loop {
        let count = file.read(&mut buffer).unwrap();
        if count == 0 {
            break;
        }
        bytes = bytes.checked_add(count as u64).unwrap();
        hash.update(&buffer[..count]);
    }
    (bytes, hash.finalize().into())
}
#[derive(Clone, Copy)]
enum Scenario {
    Complete,
    AckLost,
    WrongHash,
    WrongLength,
    WrongProgram,
    ReservedKey(&'static str),
}
struct RuntimeProbe {
    owner: std::sync::Arc<TestGateOwner>,
    node: PathBuf,
    scenario: Scenario,
    entered: bool,
}
impl InstalledClientAdapter for RuntimeProbe {
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
        let end = Instant::now()
            + if matches!(self.scenario, Scenario::AckLost) {
                Duration::from_millis(500)
            } else {
                Duration::from_secs(10)
            };
        run.bind_consumer_window(end).unwrap();
        let directory = tempfile::tempdir().unwrap();
        let mut unit = Unit::new(
            &mut run,
            &self.node,
            directory.path(),
            FixtureStrategy::NodePackage,
        );
        let data::ImplementationObservation::Observed { runtime, .. } = &mut unit.implementation
        else {
            unreachable!()
        };
        runtime.byte_length = data::Natural(SELECTED_LENGTH);
        runtime.sha256 = data::ContentSha256::new(SELECTED_SHA);
        match self.scenario {
            Scenario::WrongHash => runtime.sha256 = data::ContentSha256::new([0; 32]),
            Scenario::WrongLength => runtime.byte_length = data::Natural(SELECTED_LENGTH - 1),
            Scenario::WrongProgram => {
                runtime.program = run
                    .observation_operand(std::env::current_exe().unwrap().as_os_str())
                    .unwrap()
            }
            Scenario::Complete | Scenario::AckLost | Scenario::ReservedKey(_) => {}
        }
        let entry = Path::new(&unit.arguments[0]);
        std::fs::create_dir_all(entry.parent().unwrap()).unwrap();
        std::fs::write(entry, include_str!("reference-producer.cjs")).unwrap();
        let environment = if let Scenario::ReservedKey(key) = self.scenario {
            Some((
                run.copy_command_operand(OsStr::new(key)).unwrap(),
                run.copy_command_operand(OsStr::new("caller-collision"))
                    .unwrap(),
            ))
        } else {
            None
        };
        let usage_before = run.installed_observation_usage();
        let prepared = run.prepare_clocked_observed_consumer_process(
            ConsumerProcessCommand {
                environment: environment.as_slice(),
                ..unit.command()
            },
            end,
            &unit.implementation,
        );
        if matches!(
            self.scenario,
            Scenario::WrongHash
                | Scenario::WrongLength
                | Scenario::WrongProgram
                | Scenario::ReservedKey(_)
        ) {
            let fault = prepared.err();
            let usage_after = run.installed_observation_usage();
            let registered =
                !matches!(run.revoker.consumer_ports, ConsumerRegistration::Unprepared);
            // No endpoint owner exists, and this branch has never spawned.
            assert_eq!(
                fault,
                Some(if matches!(self.scenario, Scenario::ReservedKey(_)) {
                    ConsumerCodecError::Association
                } else {
                    ConsumerCodecError::ClockBasis
                })
            );
            assert_eq!(usage_after.retained_bytes(), usage_before.retained_bytes());
            assert_eq!(usage_after.records(), usage_before.records());
            assert!(!registered);
            return Err(InstalledAdapterError::ObservationIncomplete);
        }
        let (prepared, mut ports) = prepared.unwrap();
        let mut process = run.spawn_prepared_consumer_process(prepared).unwrap();
        let mut first = None;
        while Instant::now() < end {
            match run.poll_consumer_frame(&mut ports, ConsumerProducerRole::Outer) {
                Ok(ConsumerReceiveProgress::Pending) => {
                    std::thread::sleep(Duration::from_millis(1))
                }
                Ok(ConsumerReceiveProgress::Retained(ticket)) => {
                    first = Some(ticket);
                    break;
                }
                _ => break,
            }
        }
        let open_retained =
            first.is_some() && run.test_consumer_cache(ConsumerProducerRole::Outer).len() == 1;
        let mut delivery_fault = None;
        if matches!(self.scenario, Scenario::Complete) && first.is_some() {
            // A queued Node timer cannot supply this ACK. The SAME process is
            // still synchronously waiting on its real nonblocking descriptor.
            std::thread::sleep(Duration::from_millis(25));
            while let Some(ticket) = first.as_mut() {
                match run.write_consumer_ack(&mut ports, ticket) {
                    Ok(ConsumerAckProgress::Complete) => {
                        first = None;
                    }
                    Ok(ConsumerAckProgress::Pending) if Instant::now() < end => {}
                    result => {
                        delivery_fault = result.err();
                        break;
                    }
                }
            }
            while Instant::now() < end
                && delivery_fault.is_none()
                && [
                    ConsumerProducerRole::Outer,
                    ConsumerProducerRole::TransferHelper,
                ]
                .iter()
                .any(|role| run.test_consumer_cache(*role).len() < 2)
            {
                for role in [
                    ConsumerProducerRole::Outer,
                    ConsumerProducerRole::TransferHelper,
                ] {
                    if run.test_consumer_cache(role).len() == 2 {
                        continue;
                    }
                    match run.poll_consumer_frame(&mut ports, role) {
                        Ok(ConsumerReceiveProgress::Pending) => {}
                        Ok(ConsumerReceiveProgress::Retained(mut ticket)) => loop {
                            match run.write_consumer_ack(&mut ports, &mut ticket) {
                                Ok(ConsumerAckProgress::Complete) => break,
                                Ok(ConsumerAckProgress::Pending) if Instant::now() < end => {}
                                result => {
                                    delivery_fault = result.err();
                                    break;
                                }
                            }
                        },
                        Ok(ConsumerReceiveProgress::AwaitingAssociation) => {
                            delivery_fault = Some(ConsumerCodecError::Association);
                        }
                        Ok(ConsumerReceiveProgress::Unused) => {
                            panic!("Node reference endpoints must each send Open and Close");
                        }
                        Err(error) => {
                            delivery_fault = Some(error);
                        }
                    }
                }
                std::thread::sleep(Duration::from_millis(1));
            }
        }
        // ACK-loss intentionally keeps the original ticket and actual endpoint
        // alive. No parent revocation supplies the child's clock expiry.
        let finished = if matches!(self.scenario, Scenario::AckLost) && open_retained {
            actual_finish(process)
        } else {
            if !open_retained || delivery_fault.is_some() || Instant::now() >= end {
                let _ = process.request_termination();
            }
            actual_finish(process)
        };
        let status = finished.outcome().status().code();
        let stdout = finished.outcome().stdout().to_vec();
        let stderr = finished.outcome().stderr().to_vec();
        let process_fault = finished.outcome().first_fault().copied();
        let lengths = [
            run.test_consumer_cache(ConsumerProducerRole::Outer).len(),
            run.test_consumer_cache(ConsumerProducerRole::TransferHelper)
                .len(),
        ];
        let mut trailing = [0u8; 256];
        let after_loss = if matches!(self.scenario, Scenario::AckLost) {
            Some(rustix::io::read(
                ports.test_parent_handle(ConsumerProducerRole::Outer),
                &mut trailing,
            ))
        } else {
            None
        };
        drop(first);
        drop(finished);
        drop(ports);
        // All new assertions follow actual child/reader joins and endpoint drop.
        assert!(
            open_retained,
            "actual selected Node must publish Open before its fixed end"
        );
        assert_eq!(process_fault, None);
        if matches!(self.scenario, Scenario::Complete) {
            assert_eq!(delivery_fault, None);
            assert_eq!(lengths, [2, 2]);
            assert_eq!(status, Some(0));
            assert_eq!(stdout, b"reference-control-close-retained\n");
            assert!(stderr.is_empty());
        } else {
            assert_eq!(status, Some(2));
            assert!(stdout.is_empty());
            assert_eq!(stderr, b"reference-delivery-fault\n");
            assert_eq!(lengths, [1, 0]);
            assert_eq!(
                after_loss,
                Some(Ok(0)),
                "no FaultedClose or later bytes after lost ACK"
            );
        }
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
fn exercise_runtime(scenario: Scenario) {
    let node = PathBuf::from(
        std::env::var_os("MORPHIR_MCK_INSTALLED_NODE").expect("explicit selected Node required"),
    )
    .canonicalize()
    .unwrap();
    let before = hash_file(&node);
    assert_eq!(before, (SELECTED_LENGTH, SELECTED_SHA));
    let kit = tempfile::tempdir().unwrap();
    std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
    let mut policy = foundation_policy();
    policy["consumerObservation"] =
        serde_json::json!({"mode":"operation-port","version":"0.1.0-draft.1"});
    let mut probe = RuntimeProbe {
        owner: std::sync::Arc::new(TestGateOwner {
            gate: InvocationGate::dormant(),
        }),
        node: node.clone(),
        scenario,
        entered: false,
    };
    let report = run_configured_with_installed_client_adapter(
        kit.path(),
        &RunConfiguration::from_json(&policy.to_string()).unwrap(),
        &mut probe,
    )
    .unwrap();
    assert!(probe.entered);
    assert!(!report.qualified());
    assert_eq!(hash_file(&node), before);
}
#[test]
#[ignore = "requires explicit selected Node b468; reference transport only"]
fn selected_node_synchronous_reference_uses_actual_owned_clock_metadata_and_retained_ack() {
    exercise_runtime(Scenario::Complete)
}
#[test]
#[ignore = "requires explicit selected Node b468; reference transport only"]
fn selected_node_lost_ack_expires_at_original_end_without_faulted_close() {
    exercise_runtime(Scenario::AckLost)
}
#[test]
#[ignore = "requires explicit selected Node b468; basis refuses before endpoints"]
fn clocked_preparation_rejects_mismatched_observed_runtime_before_endpoint_effects() {
    for scenario in [
        Scenario::WrongHash,
        Scenario::WrongLength,
        Scenario::WrongProgram,
    ] {
        exercise_runtime(scenario);
    }
}
#[test]
#[ignore = "requires explicit selected Node b468; no caller selector overrides"]
fn clocked_preparation_rejects_every_reserved_selector_before_endpoint_effects() {
    for key in [
        "MORPHIR_PRIVATE_CONSUMER_OUTER_FD",
        "MORPHIR_PRIVATE_CONSUMER_HELPER_FD",
        "MORPHIR_PRIVATE_CONSUMER_VERSION",
        "MORPHIR_PRIVATE_CONSUMER_CLOCK_DOMAIN",
        "MORPHIR_PRIVATE_CONSUMER_CLOCK_VERSION",
        "MORPHIR_PRIVATE_CONSUMER_CLOCK_AT_NS",
        "MORPHIR_PRIVATE_CONSUMER_END_NS",
        "MORPHIR_PRIVATE_CONSUMER_TIMEBASE_NUMER",
        "MORPHIR_PRIVATE_CONSUMER_TIMEBASE_DENOM",
    ] {
        exercise_runtime(Scenario::ReservedKey(key));
    }
}
