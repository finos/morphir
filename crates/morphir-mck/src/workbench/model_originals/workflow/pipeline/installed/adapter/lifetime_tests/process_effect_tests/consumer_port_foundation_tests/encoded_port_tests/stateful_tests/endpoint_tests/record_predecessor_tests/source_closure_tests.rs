//! SAME source gate closure, distinct from port revocation or process failure.
//! Actual raw process/readers, no SDK latch or source/consumer qualification.
use super::*;

struct SourceClosedProbe {
    entered: bool,
    owner: std::sync::Arc<TestGateOwner>,
}
impl InstalledClientAdapter for SourceClosedProbe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        self.entered = true;
        let end = Instant::now() + Duration::from_secs(10);
        activate(&mut run, &self.owner, end);
        let directory = tempfile::tempdir().unwrap();
        let marker = directory.path().join("actual-source-closure-entry");
        let program = PathBuf::from(
            std::env::var_os("MORPHIR_MCK_REPORT_PEER_BIN")
                .expect("explicit actual MEP peer required"),
        );
        let arguments = [
            OsString::from("--adapter"),
            OsString::from("installed-process-effect-marker"),
            marker.as_os_str().to_owned(),
        ];
        let (prepared, ports) = run
            .prepare_consumer_process(
                ConsumerProcessCommand {
                    purpose: InstalledProcessPurpose::Canonical {
                        action_index: 8,
                        command: InstalledCommand::Publish,
                    },
                    program: &program,
                    arguments: &arguments,
                    directory: directory.path(),
                    environment: &[],
                    limits: Limits {
                        max_frame: 64,
                        stderr_capture: 64,
                        ..Limits::DEFAULT
                    },
                },
                end,
            )
            .unwrap();
        let ordinal = prepared.test_process_ordinal();
        let process = run.spawn_prepared_consumer_process(prepared).unwrap();
        let mut late = false;
        let finished = finish_raw(process, end, &mut late);
        let actual_fault = finished.outcome().first_fault().copied();
        let actual_status = finished.outcome().status().code();
        self.owner.gate.test_revoke_source();
        let source_closed = self.owner.gate.while_open(|| ()).is_err();
        let ports_still_not_revoked = !run.revoker.consumer_fault();
        let healthy_attempt = run.attempt.ready().is_ok();
        let eof = [
            ConsumerProducerRole::Outer,
            ConsumerProducerRole::TransferHelper,
        ]
        .into_iter()
        .all(|role| {
            matches!(
                rustix::io::read(ports.test_parent_handle(role), &mut [0u8; 1]),
                Ok(0)
            )
        });
        let before = run.installed_observation_usage();
        let decode_before = run.decode.usage();
        let result = run.record_consumer_process(ports, finished);
        let rejection = match result {
            Ok(()) => None,
            Err(rejected) => {
                let fault = rejected.fault();
                let (mut same_ports, same_finished) = rejected.into_parts();
                same_ports.revoke();
                drop(same_finished);
                drop(same_ports);
                Some(fault)
            }
        };
        // Actual child/readers settled and rejected peers dropped before RED.
        assert!(!late);
        assert_eq!(actual_fault, None);
        assert_eq!(actual_status, Some(0));
        assert_eq!(
            std::fs::read(marker).unwrap(),
            b"installed-process-effect-entry-v1\n"
        );
        assert!(eof && source_closed && ports_still_not_revoked && healthy_attempt);
        assert_eq!(run.installed_observation_usage(), before);
        assert_eq!(run.decode.usage(), decode_before);
        assert_eq!(
            rejection, None,
            "actual source gate closure must retain Interrupted/Abandoned before healthy-drain validation"
        );
        assert!(matches!(
            run.attempt.ready(),
            Err(RunFault::InstalledObservation(
                InstalledObservationError::Abandoned
            ))
        ));
        let record = run.test_consumer_record().unwrap();
        assert_eq!(record.process_ordinal(), ordinal);
        assert_eq!(record.completion(), ConsumerRecordCompletion::Interrupted);
        assert!(run.revoker.consumer_fault());
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
#[test]
fn same_source_gate_closure_is_interruption_before_healthy_drain() {
    let mut probe = SourceClosedProbe {
        entered: false,
        owner: std::sync::Arc::new(TestGateOwner {
            gate: InvocationGate::dormant(),
        }),
    };
    with_policy(&mut probe);
    assert!(probe.entered, "genuine full24 callback required");
}
