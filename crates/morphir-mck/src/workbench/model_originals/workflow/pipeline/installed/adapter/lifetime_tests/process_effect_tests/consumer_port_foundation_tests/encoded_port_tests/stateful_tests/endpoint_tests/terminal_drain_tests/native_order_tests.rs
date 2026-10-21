//! Actual Outer EOF before the independently polled native helper EOF.
use super::*;

struct NativeOrderProbe {
    owner: std::sync::Arc<TestGateOwner>,
    entered: bool,
}
impl InstalledClientAdapter for NativeOrderProbe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        self.entered = true;
        let end = Instant::now() + Duration::from_secs(10);
        activate(&mut run, &self.owner, end);
        let directory = tempfile::tempdir().unwrap();
        let program = std::env::current_exe().unwrap().canonicalize().unwrap();
        let (prepared, mut ports) = prepare_unit_ports(
            &mut run,
            &program,
            directory.path(),
            end,
            FixtureStrategy::NativeExecutable,
        );
        let outer = prepared.test_child_handle(ConsumerProducerRole::Outer);
        let helper = prepared.test_child_handle(ConsumerProducerRole::TransferHelper);
        send(outer, &framed(OPEN));
        let mut opened = receive(&mut run, &mut ports, ConsumerProducerRole::Outer);
        complete_ack(&mut run, &mut ports, &mut opened, outer, 0);
        send(outer, &framed(br#"{"kind":"close","version":"0.1.0-draft.1","sequence":1,"attemptedHooks":0,"startedFactFrames":0,"retainedBusinessFacts":0,"helper":{"kind":"not-attempted"}}"#));
        let mut closed = receive(&mut run, &mut ports, ConsumerProducerRole::Outer);
        complete_ack(&mut run, &mut ports, &mut closed, outer, 1);
        end_writes(outer);
        let outer_drained_first = run.drain_consumer_frames(&mut ports);
        let logical_outer = ports.transport_state(ConsumerProducerRole::Outer);
        let helper_still_open = matches!(
            run.poll_consumer_frame(&mut ports, ConsumerProducerRole::TransferHelper),
            Ok(ConsumerReceiveProgress::Pending)
        );
        end_writes(helper);
        let unused = matches!(
            run.poll_consumer_frame(&mut ports, ConsumerProducerRole::TransferHelper),
            Ok(ConsumerReceiveProgress::Unused)
        );
        let complete = run.drain_consumer_frames(&mut ports);
        let cache = run.test_consumer_cache(ConsumerProducerRole::Outer).len() == 2
            && run
                .test_consumer_cache(ConsumerProducerRole::TransferHelper)
                .is_empty();
        let no_helper_ack = matches!(
            rustix::io::read(helper, &mut [0u8; 1]),
            Err(rustix::io::Errno::AGAIN)
        );
        drop(prepared);
        drop(ports);
        assert_eq!(outer_drained_first, Ok(ConsumerDrainProgress::Pending));
        assert_eq!(logical_outer, ConsumerTransportState::Closed);
        assert!(helper_still_open);
        assert!(
            unused,
            "real helper EOF resolves after Outer actual EOF was already retained"
        );
        assert_eq!(complete, Ok(ConsumerDrainProgress::Complete));
        assert!(cache && no_helper_ack);
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
#[test]
fn native_helper_unused_resolves_after_outer_was_physically_drained_first() {
    let mut probe = NativeOrderProbe {
        owner: std::sync::Arc::new(TestGateOwner {
            gate: InvocationGate::dormant(),
        }),
        entered: false,
    };
    with_policy(&mut probe);
    assert!(probe.entered);
}
