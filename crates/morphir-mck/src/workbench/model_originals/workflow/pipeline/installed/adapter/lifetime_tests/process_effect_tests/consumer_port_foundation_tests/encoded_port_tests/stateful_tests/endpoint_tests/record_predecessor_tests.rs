//! Actual raw process-owner completion and public port revocation.
//! No SDK fault latch, simulated fault, business fact or report qualification.
//! Child of existing stateful_tests::endpoint_tests.
use super::*;
use crate::transport::process::ProcessFault;
use crate::workbench::model_originals::workflow::pipeline::{
    RunFault, installed::adapter::processes::consumer::record::ConsumerRecordCompletion,
};

#[derive(Clone, Copy)]
enum Case {
    MatchingProcessFault,
    UnrelatedProcessFault,
    PublicRevoke,
}
struct Probe {
    case: Case,
    entered: bool,
    owner: std::sync::Arc<TestGateOwner>,
}

fn finish_raw(
    mut process: RunningInstalledProcess,
    end: Instant,
    late: &mut bool,
) -> FinishedInstalledProcess {
    let mut containing = false;
    loop {
        containing |= matches!(
            process.advance(),
            ProcessProgress::Faulted(_) | ProcessProgress::ExitObserved(_)
        );
        if Instant::now() >= end {
            *late = true;
            containing = true;
        }
        if containing {
            let _ = process.request_termination();
            let _ = process.reap_retained();
        }
        match process.try_finish() {
            InstalledProcessFinish::Finished(finished) => return finished,
            InstalledProcessFinish::Pending(same) => process = same,
        }
        std::thread::sleep(Duration::from_millis(1));
    }
}

impl InstalledClientAdapter for Probe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        assert!(!self.entered);
        self.entered = true;
        let end = Instant::now() + Duration::from_secs(10);
        activate(&mut run, &self.owner, end);
        let directory = tempfile::tempdir().unwrap();
        let program = PathBuf::from(
            std::env::var_os("MORPHIR_MCK_REPORT_PEER_BIN")
                .expect("existing explicitly built actual MEP peer required"),
        );
        let marker = directory.path().join("actual-registered-entry");
        let arguments = [
            OsString::from("--adapter"),
            OsString::from("installed-process-effect-marker"),
            marker.as_os_str().to_owned(),
        ];
        let purpose = InstalledProcessPurpose::Canonical {
            action_index: 8,
            command: InstalledCommand::Publish,
        };
        let limits = Limits {
            max_frame: if matches!(self.case, Case::MatchingProcessFault) {
                1
            } else {
                64
            },
            stderr_capture: 64,
            ..Limits::DEFAULT
        };
        let (prepared, mut ports) = run
            .prepare_consumer_process(
                ConsumerProcessCommand {
                    purpose,
                    program: &program,
                    arguments: &arguments,
                    directory: directory.path(),
                    environment: &[],
                    limits,
                },
                end,
            )
            .unwrap();
        let ordinal = prepared.test_process_ordinal();
        let process = run.spawn_prepared_consumer_process(prepared).unwrap();
        let mut late = false;
        // Public raw owner only. In particular, never call Run.advance_consumer_process.
        let registered = finish_raw(process, end, &mut late);
        let registered_fault = registered.outcome().first_fault().copied();
        let registered_purpose = registered.purpose();
        let mut unrelated = None;
        let mut unrelated_marker = None;
        let actual = if matches!(self.case, Case::UnrelatedProcessFault) {
            let other_marker = directory.path().join("actual-unrelated-entry");
            let other_arguments = [
                OsString::from("--adapter"),
                OsString::from("installed-process-effect-marker"),
                other_marker.as_os_str().to_owned(),
            ];
            let other = run
                .spawn_process(
                    purpose,
                    &program,
                    other_arguments.iter().map(OsString::as_os_str),
                    directory.path(),
                    &[],
                    Limits {
                        max_frame: 1,
                        stderr_capture: 64,
                        ..Limits::DEFAULT
                    },
                )
                .unwrap();
            let other = finish_raw(other, end, &mut late);
            unrelated = Some((
                other.description.ordinal,
                other.purpose(),
                other.outcome().first_fault().copied(),
            ));
            unrelated_marker = Some(other_marker);
            drop(registered);
            other
        } else {
            registered
        };
        if matches!(self.case, Case::PublicRevoke) {
            ports.revoke();
        }
        let healthy_attempt_before_record = run.attempt.ready().is_ok();
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
        let result = run.record_consumer_process(ports, actual);
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
        // All actual children/readers are joined; rejected endpoints are dropped
        // and successful records retain only their SAME resolved ownership.
        assert!(
            !late,
            "unexpected late containment cannot count as same-end success"
        );
        assert!(
            healthy_attempt_before_record,
            "raw owner/revoke must reach the actual unlatched predecessor"
        );
        assert_eq!(registered_purpose, purpose);
        assert_eq!(
            std::fs::read(marker).unwrap(),
            b"installed-process-effect-entry-v1\n"
        );
        assert!(eof);
        assert_eq!(run.installed_observation_usage(), before);
        assert_eq!(run.decode.usage(), decode_before);
        match self.case {
            Case::MatchingProcessFault => {
                assert_eq!(registered_fault, Some(ProcessFault::StdoutLimit));
                assert_eq!(
                    rejection, None,
                    "matching actual faulted Finished must retain Interrupted evidence before healthy-drain validation"
                );
                assert!(matches!(
                    run.attempt.ready(),
                    Err(RunFault::InstalledProcessFault(ProcessFault::StdoutLimit))
                ));
                let record = run.test_consumer_record().unwrap();
                assert_eq!(record.process_ordinal(), ordinal);
                assert_eq!(record.completion(), ConsumerRecordCompletion::Interrupted);
            }
            Case::PublicRevoke => {
                assert_eq!(registered_fault, None);
                assert_eq!(
                    rejection, None,
                    "actual public revoke is Abandoned interruption, not invented missing-frame Framing"
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
            }
            Case::UnrelatedProcessFault => {
                assert_eq!(registered_fault, None);
                let (other_ordinal, other_purpose, other_fault) = unrelated.unwrap();
                assert_ne!(other_ordinal, ordinal);
                assert_eq!(other_purpose, purpose);
                assert_eq!(other_fault, Some(ProcessFault::StdoutLimit));
                assert_eq!(
                    std::fs::read(unrelated_marker.unwrap()).unwrap(),
                    b"installed-process-effect-entry-v1\n"
                );
                assert_eq!(rejection, Some(ConsumerCodecError::Association));
                assert!(matches!(
                    run.attempt.ready(),
                    Err(RunFault::InstalledConsumer(ConsumerCodecError::Association))
                ));
                assert!(run.test_consumer_record().is_none());
            }
        }
        assert!(
            run.revoker.consumer_fault(),
            "neither Interrupted export nor identity refusal restores authority"
        );
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
fn exercise(case: Case) {
    let mut probe = Probe {
        case,
        entered: false,
        owner: std::sync::Arc::new(TestGateOwner {
            gate: InvocationGate::dormant(),
        }),
    };
    with_policy(&mut probe);
    assert!(probe.entered, "actual full24 invocation required");
}
#[test]
fn matching_raw_finished_stdout_fault_precedes_healthy_drain_requirement() {
    exercise(Case::MatchingProcessFault);
}
#[test]
fn unrelated_actual_faulted_finished_is_refused_before_importing_its_fault() {
    exercise(Case::UnrelatedProcessFault);
}
#[test]
fn actual_public_revoke_precedes_healthy_drain_requirement() {
    exercise(Case::PublicRevoke);
}

mod source_closure_tests;
