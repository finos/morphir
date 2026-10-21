//! Actual selected Node transport/process retention, with SYNTHETIC association DATA.
//! Zero business facts. No installed consumer, dynamic hook or report qualification.
//! Proposed child of existing stateful_tests::runtime_tests.
use super::*;
use crate::workbench::model_originals::workflow::pipeline::RunFault;
use crate::workbench::model_originals::workflow::pipeline::installed::adapter::processes::consumer::record::{
    ConsumerAckDelivery, ConsumerRecordCompletion,
};

const LITERAL_OPEN: &str = r#"{"kind":"open","version":"0.1.0-draft.1","sequence":0}"#;
const LITERAL_HELPER_CLOSE: &str = r#"{"kind":"close","version":"0.1.0-draft.1","sequence":1,"attemptedHooks":0,"startedFactFrames":0,"retainedBusinessFacts":0,"helper":{"kind":"not-applicable"}}"#;
const LITERAL_OUTER_CLOSE: &str = r#"{"kind":"close","version":"0.1.0-draft.1","sequence":1,"attemptedHooks":0,"startedFactFrames":0,"retainedBusinessFacts":0,"helper":{"kind":"in-process"}}"#;

#[derive(Clone, Copy)]
enum RecordCase {
    Drained,
    LogicalOnly,
    InterruptedPrefix,
    UnrelatedFinished,
    RawDrop,
}

struct RecordProbe {
    owner: std::sync::Arc<TestGateOwner>,
    node: PathBuf,
    case: RecordCase,
    entered: bool,
}

fn finish_under_end(
    mut process: RunningInstalledProcess,
    end: Instant,
    exceeded_end: &mut bool,
) -> FinishedInstalledProcess {
    let mut containing = false;
    loop {
        let needs_containment = matches!(
            process.advance(),
            ProcessProgress::ExitObserved(_) | ProcessProgress::Faulted(_)
        );
        if Instant::now() >= end {
            *exceeded_end = true;
            containing = true;
        }
        containing |= needs_containment;
        if containing {
            // Cleanup only, even if an unexpected fault or expiry occurred.
            // No fresh business end; retain and settle SAME child/readers.
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

impl InstalledClientAdapter for RecordProbe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        assert!(!self.entered);
        self.entered = true;
        let end = Instant::now() + Duration::from_secs(10);
        let projection: std::sync::Arc<dyn InvocationGateSource> = self.owner.clone();
        let _token = run
            .issue_host_observation(std::sync::Arc::downgrade(&projection))
            .unwrap();
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
        let entry = Path::new(&unit.arguments[0]);
        std::fs::create_dir_all(entry.parent().unwrap()).unwrap();
        std::fs::write(entry, include_str!("../reference-producer.cjs")).unwrap();
        let mut command = unit.command();
        if matches!(self.case, RecordCase::UnrelatedFinished) {
            // Two actual children share the unchanged 131072/128 fixture pool.
            command.limits.max_frame = 65536;
            command.limits.stderr_capture = 64;
        }
        let child_limits = command.limits;
        let (prepared, mut ports) = run
            .prepare_clocked_observed_consumer_process(command, end, &unit.implementation)
            .unwrap();
        let expected_ordinal = prepared.test_process_ordinal();
        let process = run.spawn_prepared_consumer_process(prepared).unwrap();
        let mut first = None;
        let mut transport_failure = None;
        while Instant::now() < end {
            match run.poll_consumer_frame(&mut ports, ConsumerProducerRole::Outer) {
                Ok(ConsumerReceiveProgress::Retained(ticket)) => {
                    first = Some(ticket);
                    break;
                }
                Ok(ConsumerReceiveProgress::Pending) => {
                    std::thread::sleep(Duration::from_millis(1))
                }
                result => {
                    transport_failure = result.err();
                    break;
                }
            }
        }
        let open_retained = first.is_some();
        let mut injected_framing = false;
        let mut observed_ack_prefix = None;
        if matches!(self.case, RecordCase::InterruptedPrefix) && first.is_some() {
            let ticket = first.as_mut().unwrap();
            while Instant::now() < end && ticket.test_written_prefix() < 3 {
                let remaining = 3 - ticket.test_written_prefix();
                match run.test_write_consumer_ack_capped(
                    &mut ports,
                    ticket,
                    std::num::NonZeroUsize::new(remaining).unwrap(),
                ) {
                    Ok(ConsumerAckProgress::Pending) => {}
                    result => {
                        transport_failure = result.err();
                        break;
                    }
                }
                std::thread::sleep(Duration::from_millis(1));
            }
            // Pending may mean AGAIN/INTR or a short write. Observe the actual
            // SAME ticket cursor; never infer three written bytes from Pending.
            observed_ack_prefix = Some(ticket.test_written_prefix());
            // Real parent write prefix, then real refusal. Revocation unblocks
            // the actual synchronous reference; it is not a join or ACK.
            if observed_ack_prefix == Some(3) {
                let _ = run.require_consumer_close(&mut ports);
                injected_framing = matches!(
                    run.attempt.ready(),
                    Err(RunFault::InstalledConsumer(ConsumerCodecError::Framing))
                );
            }
            ports.revoke();
        } else if first.is_some() {
            let mut ticket = first.take().unwrap();
            loop {
                match run.write_consumer_ack(&mut ports, &mut ticket) {
                    Ok(ConsumerAckProgress::Complete) => break,
                    Ok(ConsumerAckProgress::Pending) if Instant::now() < end => {}
                    result => {
                        transport_failure = result.err();
                        break;
                    }
                }
            }
            while Instant::now() < end
                && transport_failure.is_none()
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
                                    transport_failure = result.err();
                                    break;
                                }
                            }
                        },
                        result => {
                            transport_failure =
                                result.err().or(Some(ConsumerCodecError::Association));
                        }
                    }
                }
                std::thread::sleep(Duration::from_millis(1));
            }
        }
        let mut process = process;
        if !open_retained || transport_failure.is_some() || Instant::now() >= end {
            ports.revoke();
            let _ = process.request_termination();
        }
        let mut settlement_exceeded_end = false;
        let finished = finish_under_end(process, end, &mut settlement_exceeded_end);
        let actual_status = finished.outcome().status().code();
        let actual_fault = finished.outcome().first_fault().copied();
        let expected_purpose = finished.purpose();
        if !matches!(
            self.case,
            RecordCase::LogicalOnly | RecordCase::InterruptedPrefix
        ) {
            loop {
                match run.drain_consumer_frames(&mut ports) {
                    Ok(ConsumerDrainProgress::Complete) => break,
                    Ok(ConsumerDrainProgress::Pending) if Instant::now() < end => {}
                    result => {
                        transport_failure = result.err();
                        break;
                    }
                }
            }
        }
        let before = run.installed_observation_usage();
        let decode_before = run.decode.usage();
        let mut unrelated_identity = None;
        let actual_for_record = if matches!(self.case, RecordCase::UnrelatedFinished) {
            let other = run
                .spawn_process(
                    expected_purpose,
                    &self.node,
                    unit.arguments.iter().map(OsString::as_os_str),
                    directory.path(),
                    &[],
                    child_limits,
                )
                .unwrap();
            // Same actual program/argv/cwd and exact Canonical Publish purpose.
            // This independently owned process has no observation endpoints.
            // Its status is not business evidence; its different ordinal is
            // the intended distinction at the consuming record boundary.
            let other = finish_under_end(other, end, &mut settlement_exceeded_end);
            unrelated_identity = Some((other.description.ordinal, other.purpose()));
            drop(finished); // SAME registered actual child has already joined.
            other
        } else {
            finished
        };
        if matches!(self.case, RecordCase::RawDrop) {
            drop(actual_for_record);
            drop(ports);
            drop(first);
            assert!(!settlement_exceeded_end);
            assert!(open_retained);
            assert_eq!(transport_failure, None);
            assert_eq!(actual_status, Some(0));
            assert_eq!(actual_fault, None);
            assert!(run.test_consumer_record().is_none());
            assert!(
                run.revoker.consumer_fault(),
                "raw Drop must not retire registration even after real child/EOF completion"
            );
            return Err(InstalledAdapterError::ObservationIncomplete);
        }
        let result = run.record_consumer_process(ports, actual_for_record);
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
        drop(first);
        // Every actual child, reader and endpoint owner has resolved before
        // intended assertions, including unexpected successful record export.
        assert!(
            !settlement_exceeded_end,
            "actual child/readers required containment beyond original end"
        );
        assert!(open_retained);
        assert_eq!(transport_failure, None);
        assert_eq!(actual_fault, None);
        if matches!(
            self.case,
            RecordCase::LogicalOnly | RecordCase::UnrelatedFinished
        ) {
            assert_eq!(
                rejection,
                Some(if matches!(self.case, RecordCase::LogicalOnly) {
                    ConsumerCodecError::Framing
                } else {
                    ConsumerCodecError::Association
                })
            );
            assert!(run.test_consumer_record().is_none());
            assert!(run.revoker.consumer_fault());
            if let Some((other, purpose)) = unrelated_identity {
                assert_eq!(purpose, expected_purpose);
                assert_ne!(other, expected_ordinal);
            }
        } else {
            assert_eq!(rejection, None);
            let record = run
                .test_consumer_record()
                .expect("actual terminal record must move into CollectedInstalled");
            assert_eq!(record.process_ordinal(), expected_ordinal);
            let outer = record.frames(ConsumerProducerRole::Outer);
            assert_eq!(outer[0].literal_utf8(), LITERAL_OPEN);
            if matches!(self.case, RecordCase::Drained) {
                assert_eq!(actual_status, Some(0));
                assert_eq!(record.completion(), ConsumerRecordCompletion::Drained);
                assert_eq!(outer.len(), 2);
                let helper = record.frames(ConsumerProducerRole::TransferHelper);
                assert_eq!(helper.len(), 2);
                for (frame, literal) in [
                    (&outer[0], LITERAL_OPEN),
                    (&outer[1], LITERAL_OUTER_CLOSE),
                    (&helper[0], LITERAL_OPEN),
                    (&helper[1], LITERAL_HELPER_CLOSE),
                ] {
                    assert_eq!(frame.literal_utf8(), literal);
                    assert!(matches!(
                        frame.delivery(),
                        ConsumerAckDelivery::Written { .. }
                    ));
                }
                assert!(
                    !run.revoker.consumer_fault(),
                    "only explicit actual terminal export retires registration"
                );
            } else {
                assert_eq!(actual_status, Some(2));
                assert_eq!(observed_ack_prefix, Some(3));
                assert!(
                    injected_framing,
                    "the exact injected first fault must be typed InstalledConsumer::Framing"
                );
                assert_eq!(record.completion(), ConsumerRecordCompletion::Interrupted);
                assert_eq!(outer.len(), 1);
                assert!(
                    record
                        .frames(ConsumerProducerRole::TransferHelper)
                        .is_empty()
                );
                assert!(matches!(
                    outer[0].delivery(),
                    ConsumerAckDelivery::Prefix { written: 3, .. }
                ));
                assert!(matches!(
                    run.attempt.ready(),
                    Err(RunFault::InstalledConsumer(ConsumerCodecError::Framing))
                ));
                assert!(run.revoker.consumer_fault());
                assert_eq!(
                    run.installed_observation_usage(),
                    before,
                    "post-fault export uses only preissued storage and moves"
                );
                assert_eq!(
                    run.decode.usage(),
                    decode_before,
                    "post-fault export cannot obtain new Decoder work"
                );
            }
        }
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}

fn exercise_record(case: RecordCase) {
    let node = PathBuf::from(
        std::env::var_os("MORPHIR_MCK_INSTALLED_NODE")
            .expect("explicit selected Node b468 required"),
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
    let mut probe = RecordProbe {
        owner: std::sync::Arc::new(TestGateOwner {
            gate: InvocationGate::dormant(),
        }),
        node: node.clone(),
        case,
        entered: false,
    };
    let report = run_configured_with_installed_client_adapter(
        kit.path(),
        &RunConfiguration::from_json(&policy.to_string()).unwrap(),
        &mut probe,
    )
    .unwrap();
    assert!(probe.entered, "genuine full24 callback must execute");
    assert!(!report.qualified());
    assert_eq!(hash_file(&node), before);
}

#[test]
#[ignore = "requires explicit selected Node b468; zero-business transport DATA only"]
fn actual_joined_drained_process_exports_literal_delivery_and_parent_association() {
    exercise_record(RecordCase::Drained);
}
#[test]
#[ignore = "requires explicit selected Node b468; cleanup precedes intended refusal"]
fn actual_finished_without_physical_drain_cannot_retire_registered_ports() {
    exercise_record(RecordCase::LogicalOnly);
}
#[test]
#[ignore = "requires explicit selected Node b468; actual partial ACK and interrupted record"]
fn actual_ack_prefix_survives_fault_and_join_without_authority_revival() {
    exercise_record(RecordCase::InterruptedPrefix);
}
#[test]
#[ignore = "requires explicit selected Node b468; independently joined unrelated actual child"]
fn same_run_unrelated_actual_finished_cannot_supply_registered_process_completion() {
    exercise_record(RecordCase::UnrelatedFinished);
}
#[test]
#[ignore = "requires explicit selected Node b468; real drain and raw Drop remain distinct"]
fn actual_finished_and_eof_do_not_make_raw_drop_a_recorded_operation() {
    exercise_record(RecordCase::RawDrop);
}
