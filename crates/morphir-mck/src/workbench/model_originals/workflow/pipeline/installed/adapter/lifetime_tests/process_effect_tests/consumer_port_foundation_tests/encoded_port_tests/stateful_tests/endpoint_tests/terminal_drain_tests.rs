//! Actual endpoint terminal reads; SYNTHETIC unit association/completion DATA.
//! Logical Close+ACK is not physical EOF, process wait, reader join or effect.
use super::*;
use crate::workbench::model_originals::workflow::pipeline::installed::adapter::processes::consumer::wire::ConsumerDrainProgress;

const ROLES: [ConsumerProducerRole; 2] = [
    ConsumerProducerRole::Outer,
    ConsumerProducerRole::TransferHelper,
];
fn close(role: ConsumerProducerRole) -> Vec<u8> {
    let helper = match role {
        ConsumerProducerRole::Outer => "in-process",
        ConsumerProducerRole::TransferHelper => "not-applicable",
    };
    framed(format!(r#"{{"kind":"close","version":"0.1.0-draft.1","sequence":1,"attemptedHooks":0,"startedFactFrames":0,"retainedBusinessFacts":0,"helper":{{"kind":"{helper}"}}}}"#).as_bytes())
}
fn end_writes(peer: BorrowedFd<'_>) {
    // Temporary duplicate of SAME socket solely to cause real read0. The
    // original read side remains for proving no invented extra ACK bytes.
    let same = std::os::unix::net::UnixStream::from(peer.try_clone_to_owned().unwrap());
    same.shutdown(std::net::Shutdown::Write).unwrap();
}
fn finish_role(
    run: &mut InstalledClientRun<'_>,
    ports: &mut InstalledConsumerPorts,
    peer: BorrowedFd<'_>,
    role: ConsumerProducerRole,
) {
    send(peer, &framed(OPEN));
    let mut opened = receive(run, ports, role);
    complete_ack(run, ports, &mut opened, peer, 0);
    send(peer, &close(role));
    let mut closed = receive(run, ports, role);
    complete_ack(run, ports, &mut closed, peer, 1);
}

#[derive(Clone, Copy)]
enum Case {
    WaitForBoth,
    Extra(ConsumerProducerRole, bool),
    NativeUnused,
    Deadline,
}
struct Probe {
    case: Case,
    entered: bool,
    owner: std::sync::Arc<TestGateOwner>,
}
impl InstalledClientAdapter for Probe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        self.entered = true;
        let end = Instant::now()
            + Duration::from_secs(if matches!(self.case, Case::Deadline) {
                2
            } else {
                10
            });
        activate(&mut run, &self.owner, end);
        let directory = tempfile::tempdir().unwrap();
        let program = std::env::current_exe().unwrap().canonicalize().unwrap();
        let strategy = if matches!(self.case, Case::NativeUnused) {
            FixtureStrategy::NativeExecutable
        } else {
            FixtureStrategy::NodePackage
        };
        let (prepared, mut ports) =
            prepare_unit_ports(&mut run, &program, directory.path(), end, strategy);
        let outer = prepared.test_child_handle(ConsumerProducerRole::Outer);
        let helper = prepared.test_child_handle(ConsumerProducerRole::TransferHelper);
        if matches!(self.case, Case::NativeUnused) {
            send(outer, &framed(OPEN));
            let mut opened = receive(&mut run, &mut ports, ConsumerProducerRole::Outer);
            complete_ack(&mut run, &mut ports, &mut opened, outer, 0);
            let no_helper = framed(br#"{"kind":"close","version":"0.1.0-draft.1","sequence":1,"attemptedHooks":0,"startedFactFrames":0,"retainedBusinessFacts":0,"helper":{"kind":"not-attempted"}}"#);
            send(outer, &no_helper);
            let mut closed = receive(&mut run, &mut ports, ConsumerProducerRole::Outer);
            complete_ack(&mut run, &mut ports, &mut closed, outer, 1);
            end_writes(helper);
            let actual_unused = matches!(
                run.poll_consumer_frame(&mut ports, ConsumerProducerRole::TransferHelper),
                Ok(ConsumerReceiveProgress::Unused)
            );
            let before_outer_eof = run.drain_consumer_frames(&mut ports);
            end_writes(outer);
            let after_outer_eof = run.drain_consumer_frames(&mut ports);
            let retained = run.test_consumer_cache(ConsumerProducerRole::Outer).len() == 2
                && run
                    .test_consumer_cache(ConsumerProducerRole::TransferHelper)
                    .is_empty();
            let no_helper_ack = matches!(
                rustix::io::read(helper, &mut [0u8; 1]),
                Err(rustix::io::Errno::AGAIN)
            );
            drop(prepared);
            drop(ports);
            assert!(actual_unused);
            assert_eq!(before_outer_eof, Ok(ConsumerDrainProgress::Pending));
            assert_eq!(after_outer_eof, Ok(ConsumerDrainProgress::Complete));
            assert!(
                retained && no_helper_ack,
                "native unused EOF must not fabricate helper frames or ACKs"
            );
            return Err(InstalledAdapterError::ObservationIncomplete);
        }
        for (role, peer) in [(ROLES[0], outer), (ROLES[1], helper)] {
            finish_role(&mut run, &mut ports, peer, role);
        }
        let logical_closed = ROLES
            .into_iter()
            .all(|role| ports.transport_state(role) == ConsumerTransportState::Closed);
        match self.case {
            Case::WaitForBoth => {
                let before = run.drain_consumer_frames(&mut ports);
                end_writes(outer);
                let one_eof = run.drain_consumer_frames(&mut ports);
                end_writes(helper);
                let both_eof = run.drain_consumer_frames(&mut ports);
                let usage = run.installed_observation_usage();
                let again = run.drain_consumer_frames(&mut ports);
                let no_more_io = run.installed_observation_usage() == usage;
                let no_ack = [outer, helper].into_iter().all(|fd| {
                    matches!(
                        rustix::io::read(fd, &mut [0u8; 1]),
                        Err(rustix::io::Errno::AGAIN)
                    )
                });
                let cached = ROLES
                    .into_iter()
                    .all(|role| run.test_consumer_cache(role).len() == 2);
                drop(prepared);
                drop(ports);
                assert!(logical_closed);
                assert_eq!(
                    before,
                    Ok(ConsumerDrainProgress::Pending),
                    "ACKed Close cannot prove EOF while writer stays open"
                );
                assert_eq!(one_eof, Ok(ConsumerDrainProgress::Pending));
                assert_eq!(both_eof, Ok(ConsumerDrainProgress::Complete));
                assert_eq!(again, Ok(ConsumerDrainProgress::Complete));
                assert!(no_more_io && no_ack && cached);
            }
            Case::Extra(role, full_frame) => {
                let peer = prepared.test_child_handle(role);
                let tail = if full_frame { framed(OPEN) } else { vec![0x7b] };
                send(peer, &tail);
                let first = run.drain_consumer_frames(&mut ports);
                let usage = run.installed_observation_usage();
                let repeated = run.drain_consumer_frames(&mut ports);
                let sticky = run.installed_observation_usage() == usage;
                let no_ack = [outer, helper].into_iter().all(|fd| {
                    matches!(
                        rustix::io::read(fd, &mut [0u8; 1]),
                        Ok(0) | Err(rustix::io::Errno::AGAIN)
                    )
                });
                let cached = ROLES
                    .into_iter()
                    .all(|role| run.test_consumer_cache(role).len() == 2);
                drop(prepared);
                drop(ports);
                assert!(logical_closed);
                assert_eq!(
                    first,
                    Err(ConsumerCodecError::Framing),
                    "even one actual byte after ACKed Close must refuse"
                );
                assert_eq!(repeated, Err(ConsumerCodecError::PriorFault));
                assert!(sticky && no_ack && cached);
            }
            Case::Deadline => {
                let before = run.drain_consumer_frames(&mut ports);
                std::thread::sleep(
                    end.saturating_duration_since(Instant::now()) + Duration::from_millis(20),
                );
                let expired = run.drain_consumer_frames(&mut ports);
                let usage = run.installed_observation_usage();
                let again = run.drain_consumer_frames(&mut ports);
                let sticky = run.installed_observation_usage() == usage;
                drop(prepared);
                drop(ports);
                assert!(logical_closed);
                assert_eq!(before, Ok(ConsumerDrainProgress::Pending));
                assert_eq!(expired, Err(ConsumerCodecError::Expired));
                assert_eq!(again, Err(ConsumerCodecError::PriorFault));
                assert!(
                    sticky,
                    "terminal drain never resets or extends the original bound end"
                );
            }
            Case::NativeUnused => unreachable!(),
        }
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
    assert!(probe.entered, "genuine complete24 callback must execute");
}
#[test]
fn acked_closes_stay_pending_until_both_actual_endpoint_eofs() {
    exercise(Case::WaitForBoth);
}
#[test]
fn any_actual_trailing_byte_or_frame_after_close_refuses_without_ack_or_cache_growth() {
    for role in ROLES {
        for full_frame in [false, true] {
            exercise(Case::Extra(role, full_frame));
        }
    }
}
#[test]
fn native_unused_is_already_real_eof_but_outer_still_requires_its_own_eof() {
    exercise(Case::NativeUnused);
}
#[test]
fn terminal_eof_wait_uses_same_original_deadline_and_sticky_fault() {
    exercise(Case::Deadline);
}

mod native_order_tests;
