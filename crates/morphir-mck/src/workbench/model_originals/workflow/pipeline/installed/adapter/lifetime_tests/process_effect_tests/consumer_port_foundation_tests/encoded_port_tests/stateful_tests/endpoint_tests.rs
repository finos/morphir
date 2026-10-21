//! Actual owned Unix endpoints in explicitly SYNTHETIC unit associations.
//! No child, consumer, deadline ABI, business-hook cleanup or report qualification.
use super::*;
use crate::workbench::model_originals::workflow::pipeline::installed::adapter::processes::consumer::wire::ConsumerPendingAck;
use std::num::NonZeroUsize;

const OPEN: &[u8] = br#"{"kind":"open","version":"0.1.0-draft.1","sequence":0}"#;
fn retained(sequence: u64) -> Vec<u8> {
    framed(
        format!(r#"{{"kind":"retained","version":"0.1.0-draft.1","sequence":{sequence}}}"#)
            .as_bytes(),
    )
}
fn commit(sequence: u64) -> Vec<u8> {
    framed(format!(r#"{{"kind":"fact","version":"0.1.0-draft.1","sequence":{sequence},"fact":{{"kind":"destination-commit-finished","path":{{"kind":"unix-bytes","bytes":{{"kind":"utf8","text":"/unit-output"}}}},"policy":"create","outcome":"returned"}}}}"#).as_bytes())
}
fn send(fd: BorrowedFd<'_>, bytes: &[u8]) {
    assert_eq!(rustix::io::write(fd, bytes).unwrap(), bytes.len());
}
fn take_exact(fd: BorrowedFd<'_>, expected: &[u8]) {
    let mut bytes = [0u8; 256];
    assert!(expected.len() <= bytes.len());
    let mut at = 0;
    while at < expected.len() {
        let n = rustix::io::read(fd, &mut bytes[at..expected.len()]).unwrap();
        assert!(n > 0, "real endpoint must supply the retained ACK");
        at += n;
    }
    assert_eq!(&bytes[..at], expected);
    no_ack(fd);
}
fn no_ack_or_closed(fd: BorrowedFd<'_>) {
    assert!(matches!(
        rustix::io::read(fd, &mut [0u8; 1]),
        Ok(0) | Err(rustix::io::Errno::AGAIN)
    ));
}
fn receive(
    run: &mut InstalledClientRun<'_>,
    ports: &mut InstalledConsumerPorts,
    role: ConsumerProducerRole,
) -> ConsumerPendingAck {
    match run.poll_consumer_frame(ports, role).unwrap() {
        ConsumerReceiveProgress::Retained(ticket) => ticket,
        _ => panic!("complete actual frame must yield its sole retained ACK ticket"),
    }
}
fn complete_ack(
    run: &mut InstalledClientRun<'_>,
    ports: &mut InstalledConsumerPorts,
    ticket: &mut ConsumerPendingAck,
    fd: BorrowedFd<'_>,
    sequence: u64,
) {
    assert!(matches!(
        run.write_consumer_ack(ports, ticket).unwrap(),
        ConsumerAckProgress::Complete
    ));
    take_exact(fd, &retained(sequence));
}

#[derive(Clone, Copy)]
enum EndpointCase {
    PartialAck,
    Routes,
    Duplicate,
    ForeignControl,
    Outstanding,
    Sequence(u64),
    Poison,
    Expired,
}
struct EndpointProbe {
    which: EndpointCase,
    entered: bool,
    owner: std::sync::Arc<TestGateOwner>,
}
fn activate(run: &mut InstalledClientRun<'_>, owner: &std::sync::Arc<TestGateOwner>, end: Instant) {
    let projection: std::sync::Arc<dyn InvocationGateSource> = owner.clone();
    let _token = run
        .issue_host_observation(std::sync::Arc::downgrade(&projection))
        .unwrap();
    run.bind_consumer_window(end).unwrap();
}
impl InstalledClientAdapter for EndpointProbe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        assert!(!self.entered);
        self.entered = true;
        let end = Instant::now()
            + Duration::from_secs(if matches!(self.which, EndpointCase::Expired) {
                2
            } else {
                10
            });
        activate(&mut run, &self.owner, end);
        let program = std::env::current_exe().unwrap().canonicalize().unwrap();
        let directory = tempfile::tempdir().unwrap();
        let (prepared, mut ports) = prepare_unit_ports(
            &mut run,
            &program,
            directory.path(),
            end,
            FixtureStrategy::NodePackage,
        );
        let outer = prepared.test_child_handle(ConsumerProducerRole::Outer);
        let helper = prepared.test_child_handle(ConsumerProducerRole::TransferHelper);
        if let EndpointCase::Sequence(sequence) = self.which {
            send(outer, &framed(OPEN));
            let mut first = receive(&mut run, &mut ports, ConsumerProducerRole::Outer);
            complete_ack(&mut run, &mut ports, &mut first, outer, 0);
            send(outer, &commit(sequence));
            assert_eq!(
                run.poll_consumer_frame(&mut ports, ConsumerProducerRole::Outer)
                    .err(),
                Some(ConsumerCodecError::Sequence)
            );
            assert_eq!(
                run.test_consumer_cache(ConsumerProducerRole::Outer).len(),
                1
            );
            assert_eq!(
                run.poll_consumer_frame(&mut ports, ConsumerProducerRole::Outer)
                    .err(),
                Some(ConsumerCodecError::PriorFault)
            );
            no_ack_or_closed(outer);
        } else if matches!(self.which, EndpointCase::Poison) {
            let release = vectors().into_iter().find(|v| v.name == "release").unwrap();
            send(outer, &unhex(&release.wire_hex));
            send(outer, &framed(OPEN));
            assert_eq!(
                run.poll_consumer_frame(&mut ports, ConsumerProducerRole::Outer)
                    .err(),
                Some(ConsumerCodecError::Role)
            );
            let usage = run.installed_observation_usage();
            assert_eq!(
                run.poll_consumer_frame(&mut ports, ConsumerProducerRole::Outer)
                    .err(),
                Some(ConsumerCodecError::PriorFault)
            );
            assert_eq!(run.installed_observation_usage(), usage);
            assert!(
                run.test_consumer_cache(ConsumerProducerRole::Outer)
                    .is_empty()
            );
            no_ack_or_closed(outer);
        } else {
            send(outer, &framed(OPEN));
            let mut ticket = receive(&mut run, &mut ports, ConsumerProducerRole::Outer);
            assert_eq!(
                run.test_consumer_cache(ConsumerProducerRole::Outer)
                    .last()
                    .unwrap()
                    .literal_utf8(),
                std::str::from_utf8(OPEN).unwrap()
            );
            no_ack(outer);
            match self.which {
                EndpointCase::PartialAck => {
                    // Fill the actual collector->producer socket, not a fake
                    // writer. Stack bytes are test-only, not business DATA.
                    let filler = [0x5au8; 4096];
                    let mut filled = 0usize;
                    loop {
                        assert!(
                            filled < 16 * 1024 * 1024,
                            "bounded saturation premise must reach actual WouldBlock"
                        );
                        match rustix::io::write(
                            ports.test_parent_handle(ConsumerProducerRole::Outer),
                            &filler,
                        ) {
                            Ok(n) => {
                                assert!(n > 0);
                                filled += n;
                            }
                            Err(rustix::io::Errno::AGAIN) => break,
                            other => panic!("actual socket saturation failed: {other:?}"),
                        }
                    }
                    assert!(filled > 0);
                    assert!(matches!(
                        run.write_consumer_ack(&mut ports, &mut ticket).unwrap(),
                        ConsumerAckProgress::Pending
                    ));
                    let mut remaining = filled;
                    let mut bytes = [0; 4096];
                    while remaining > 0 {
                        let limit = remaining.min(bytes.len());
                        let n = rustix::io::read(outer, &mut bytes[..limit]).unwrap();
                        assert!(n > 0);
                        assert!(bytes[..n].iter().all(|byte| *byte == 0x5a));
                        remaining -= n;
                    }
                    no_ack(outer);
                    let expected = retained(0);
                    assert!(matches!(
                        run.test_write_consumer_ack_capped(
                            &mut ports,
                            &mut ticket,
                            NonZeroUsize::new(3).unwrap()
                        )
                        .unwrap(),
                        ConsumerAckProgress::Pending
                    ));
                    take_exact(outer, &expected[..3]);
                    assert!(matches!(
                        run.write_consumer_ack(&mut ports, &mut ticket).unwrap(),
                        ConsumerAckProgress::Complete
                    ));
                    take_exact(outer, &expected[3..]);
                    assert_eq!(
                        run.test_consumer_cache(ConsumerProducerRole::Outer).len(),
                        1
                    );
                }
                EndpointCase::Routes => {
                    send(helper, &framed(OPEN));
                    let mut helper_ticket =
                        receive(&mut run, &mut ports, ConsumerProducerRole::TransferHelper);
                    no_ack(outer);
                    no_ack(helper);
                    complete_ack(&mut run, &mut ports, &mut ticket, outer, 0);
                    no_ack(helper);
                    complete_ack(&mut run, &mut ports, &mut helper_ticket, helper, 0);
                    no_ack(outer);
                }
                EndpointCase::Duplicate => {
                    complete_ack(&mut run, &mut ports, &mut ticket, outer, 0);
                    assert_eq!(
                        run.write_consumer_ack(&mut ports, &mut ticket).err(),
                        Some(ConsumerCodecError::Ticket)
                    );
                    no_ack_or_closed(outer);
                    assert_eq!(
                        run.poll_consumer_frame(&mut ports, ConsumerProducerRole::Outer)
                            .err(),
                        Some(ConsumerCodecError::PriorFault)
                    );
                    assert_eq!(
                        run.test_consumer_cache(ConsumerProducerRole::Outer).len(),
                        1
                    );
                }
                EndpointCase::ForeignControl => {
                    let mut foreign = ForeignProbe {
                        ticket: &mut ticket,
                        entered: false,
                        owner: std::sync::Arc::new(TestGateOwner {
                            gate: InvocationGate::dormant(),
                        }),
                    };
                    with_policy(&mut foreign);
                    assert!(foreign.entered);
                    no_ack(outer);
                    // Rejection poisons target Run only. The genuine source
                    // ticket still completes through its original live owner.
                    complete_ack(&mut run, &mut ports, &mut ticket, outer, 0);
                }
                EndpointCase::Outstanding => {
                    send(outer, &commit(1));
                    assert_eq!(
                        run.poll_consumer_frame(&mut ports, ConsumerProducerRole::Outer)
                            .err(),
                        Some(ConsumerCodecError::Outstanding)
                    );
                    assert_eq!(
                        run.test_consumer_cache(ConsumerProducerRole::Outer).len(),
                        1
                    );
                    assert_eq!(
                        run.write_consumer_ack(&mut ports, &mut ticket).err(),
                        Some(ConsumerCodecError::PriorFault)
                    );
                    no_ack_or_closed(outer);
                }
                EndpointCase::Expired => {
                    assert!(
                        Instant::now() < end,
                        "actual complete frame must be cached before expiry"
                    );
                    std::thread::sleep(
                        end.saturating_duration_since(Instant::now()) + Duration::from_millis(1),
                    );
                    assert!(Instant::now() >= end);
                    assert_eq!(
                        run.write_consumer_ack(&mut ports, &mut ticket).err(),
                        Some(ConsumerCodecError::Expired)
                    );
                    assert_eq!(
                        run.test_consumer_cache(ConsumerProducerRole::Outer).len(),
                        1
                    );
                    assert_eq!(
                        run.test_consumer_cache(ConsumerProducerRole::Outer)[0].literal_utf8(),
                        std::str::from_utf8(OPEN).unwrap()
                    );
                    assert_eq!(
                        run.poll_consumer_frame(&mut ports, ConsumerProducerRole::Outer)
                            .err(),
                        Some(ConsumerCodecError::PriorFault)
                    );
                    no_ack_or_closed(outer);
                }
                _ => unreachable!(),
            }
        }
        drop(prepared);
        drop(ports);
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
struct ForeignProbe<'a> {
    ticket: &'a mut ConsumerPendingAck,
    entered: bool,
    owner: std::sync::Arc<TestGateOwner>,
}
impl InstalledClientAdapter for ForeignProbe<'_> {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        self.entered = true;
        let end = Instant::now() + Duration::from_secs(10);
        activate(&mut run, &self.owner, end);
        let program = std::env::current_exe().unwrap().canonicalize().unwrap();
        let directory = tempfile::tempdir().unwrap();
        let (prepared, mut ports) = prepare_unit_ports(
            &mut run,
            &program,
            directory.path(),
            end,
            FixtureStrategy::NodePackage,
        );
        let outer = prepared.test_child_handle(ConsumerProducerRole::Outer);
        send(outer, &framed(OPEN));
        let mut own_ticket = receive(&mut run, &mut ports, ConsumerProducerRole::Outer);
        assert_eq!(
            run.write_consumer_ack(&mut ports, self.ticket).err(),
            Some(ConsumerCodecError::Ticket)
        );
        no_ack_or_closed(outer);
        no_ack_or_closed(prepared.test_child_handle(ConsumerProducerRole::TransferHelper));
        assert_eq!(
            run.write_consumer_ack(&mut ports, &mut own_ticket).err(),
            Some(ConsumerCodecError::PriorFault)
        );
        drop(prepared);
        drop(ports);
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
fn with_policy(adapter: &mut impl InstalledClientAdapter) {
    let kit = tempfile::tempdir().unwrap();
    std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
    let mut policy = foundation_policy();
    policy["consumerObservation"] =
        serde_json::json!({"mode":"operation-port","version":"0.1.0-draft.1"});
    let report = run_configured_with_installed_client_adapter(
        kit.path(),
        &RunConfiguration::from_json(&policy.to_string()).unwrap(),
        adapter,
    )
    .unwrap();
    assert!(!report.qualified());
}
fn exercise_endpoint(which: EndpointCase) {
    let mut probe = EndpointProbe {
        which,
        entered: false,
        owner: std::sync::Arc::new(TestGateOwner {
            gate: InvocationGate::dormant(),
        }),
    };
    with_policy(&mut probe);
    assert!(probe.entered, "genuine full24 callback must execute");
}
#[test]
fn actual_ack_wouldblock_and_capped_partial_write_retain_same_cursor() {
    exercise_endpoint(EndpointCase::PartialAck);
}
#[test]
fn genuine_outer_helper_tickets_route_only_to_actual_owned_endpoints() {
    exercise_endpoint(EndpointCase::Routes);
}
#[test]
fn completed_ticket_replay_refuses_before_another_ack_byte() {
    exercise_endpoint(EndpointCase::Duplicate);
}
#[test]
fn foreign_live_control_ticket_refuses_without_consuming_source_ticket() {
    exercise_endpoint(EndpointCase::ForeignControl);
}
#[test]
fn same_role_cannot_receive_second_frame_while_ticket_is_outstanding() {
    exercise_endpoint(EndpointCase::Outstanding);
}
#[test]
fn actual_duplicate_and_gap_sequences_poison_without_cache_replacement() {
    for sequence in [0, 2] {
        exercise_endpoint(EndpointCase::Sequence(sequence));
    }
}
#[test]
fn physical_role_fault_is_sticky_and_later_valid_frame_cannot_resync() {
    exercise_endpoint(EndpointCase::Poison);
}
#[test]
fn real_deadline_after_cache_before_ack_refuses_without_erasing_cached_frame() {
    exercise_endpoint(EndpointCase::Expired);
}

mod business_state_tests;
mod close_forms_tests;

mod argument_copy_tests;
mod native_eof_tests;

mod byte_buffer_tests;

mod process_fault_tests;

mod terminal_drain_tests;

mod record_predecessor_tests;
