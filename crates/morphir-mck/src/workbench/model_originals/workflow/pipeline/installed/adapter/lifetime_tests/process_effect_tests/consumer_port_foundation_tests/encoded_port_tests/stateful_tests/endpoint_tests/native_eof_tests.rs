//! Real endpoint EOF, SYNTHETIC unit launch/completion DATA only.
//! Unused is an endpoint result, never helper absence, wait/join or effect proof.
use super::*;

#[derive(Clone, Copy)]
enum Completion {
    NotAttempted,
    LaunchFailed,
    Started,
}
fn outer_close(completion: Completion, sequence: u64) -> Vec<u8> {
    let helper = match completion {
        Completion::NotAttempted => r#"{"kind":"not-attempted"}"#,
        Completion::LaunchFailed => {
            r#"{"kind":"launch-failed","stage":"preparation","stdout":{"kind":"not-created"},"stderr":{"kind":"not-created"}}"#
        }
        Completion::Started => {
            r#"{"kind":"started","wait":{"kind":"waited","rawStatus":"0"},"stdout":{"kind":"owned","read":{"kind":"complete","byteLength":"0"},"disposal":{"kind":"disposed"}},"stderr":{"kind":"owned","read":{"kind":"complete","byteLength":"0"},"disposal":{"kind":"disposed"}}}"#
        }
    };
    framed(format!(r#"{{"kind":"close","version":"0.1.0-draft.1","sequence":{sequence},"attemptedHooks":0,"startedFactFrames":0,"retainedBusinessFacts":0,"helper":{helper}}}"#).as_bytes())
}
fn end_producer_writes(peer: BorrowedFd<'_>) {
    // A test-only temporary descriptor for the SAME socket, not another
    // endpoint or a child process. Shutdown produces a genuine read0 at the
    // collector while retaining the original peer's read side for no-ACK proof.
    let same = std::os::unix::net::UnixStream::from(peer.try_clone_to_owned().unwrap());
    same.shutdown(std::net::Shutdown::Write).unwrap();
}
fn no_helper_ack(peer: BorrowedFd<'_>) -> bool {
    matches!(
        rustix::io::read(peer, &mut [0u8; 1]),
        Ok(0) | Err(rustix::io::Errno::AGAIN)
    )
}

#[derive(Clone, Copy)]
enum Scenario {
    Resolve {
        completion: Completion,
        outer_first: bool,
    },
    WaitingThenStarted,
    StartedMissingClose,
    PartialHeader,
    PartialBody,
    PartialHeaderAfterClose,
    PartialBodyAfterClose,
    NodeEof,
    Deadline,
}
struct EofProbe {
    scenario: Scenario,
    entered: bool,
    owner: std::sync::Arc<TestGateOwner>,
}
impl InstalledClientAdapter for EofProbe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        self.entered = true;
        let end = Instant::now()
            + Duration::from_secs(if matches!(self.scenario, Scenario::Deadline) {
                2
            } else {
                10
            });
        activate(&mut run, &self.owner, end);
        let program = std::env::current_exe().unwrap().canonicalize().unwrap();
        let directory = tempfile::tempdir().unwrap();
        let strategy = if matches!(self.scenario, Scenario::NodeEof) {
            FixtureStrategy::NodePackage
        } else {
            FixtureStrategy::NativeExecutable
        };
        let unit = Unit::new(&mut run, &program, directory.path(), strategy);
        let (prepared, mut ports) = unit.prepare(&mut run, end);
        let outer = prepared.test_child_handle(ConsumerProducerRole::Outer);
        let helper = prepared.test_child_handle(ConsumerProducerRole::TransferHelper);
        let outer_role = ConsumerProducerRole::Outer;
        let helper_role = ConsumerProducerRole::TransferHelper;

        if matches!(
            self.scenario,
            Scenario::PartialHeader
                | Scenario::PartialBody
                | Scenario::PartialHeaderAfterClose
                | Scenario::PartialBodyAfterClose
                | Scenario::NodeEof
        ) {
            if matches!(
                self.scenario,
                Scenario::PartialHeaderAfterClose | Scenario::PartialBodyAfterClose
            ) {
                send(outer, &framed(OPEN));
                let mut open = receive(&mut run, &mut ports, outer_role);
                complete_ack(&mut run, &mut ports, &mut open, outer, 0);
                send(outer, &outer_close(Completion::NotAttempted, 1));
                let mut close = receive(&mut run, &mut ports, outer_role);
                complete_ack(&mut run, &mut ports, &mut close, outer, 1);
            }
            match self.scenario {
                Scenario::PartialHeader | Scenario::PartialHeaderAfterClose => {
                    send(helper, &[0, 0])
                }
                Scenario::PartialBody | Scenario::PartialBodyAfterClose => {
                    let open = framed(OPEN);
                    send(helper, &open[..9]);
                }
                Scenario::NodeEof => {}
                _ => unreachable!(),
            }
            end_producer_writes(helper);
            let first = run.poll_consumer_frame(&mut ports, helper_role);
            let first_pending = matches!(&first, Ok(ConsumerReceiveProgress::Pending));
            let error = match self.scenario {
                Scenario::NodeEof => first.err(),
                _ => run.poll_consumer_frame(&mut ports, helper_role).err(),
            };
            let empty = run.test_consumer_cache(helper_role).is_empty();
            let no_ack = no_helper_ack(helper);
            let repeated = run.poll_consumer_frame(&mut ports, helper_role).err();
            drop(prepared);
            drop(ports);
            if !matches!(self.scenario, Scenario::NodeEof) {
                assert!(
                    first_pending,
                    "partial real header/body must remain the SAME prefix"
                );
            }
            assert_eq!(error, Some(ConsumerCodecError::Framing));
            assert_eq!(repeated, Some(ConsumerCodecError::PriorFault));
            assert!(
                empty && no_ack,
                "EOF cannot fabricate a helper frame or ACK"
            );
            return Err(InstalledAdapterError::ObservationIncomplete);
        }

        let outer_first = matches!(
            self.scenario,
            Scenario::Resolve {
                outer_first: true,
                ..
            }
        );
        if outer_first {
            send(outer, &framed(OPEN));
            let mut open = receive(&mut run, &mut ports, outer_role);
            complete_ack(&mut run, &mut ports, &mut open, outer, 0);
            let Scenario::Resolve { completion, .. } = self.scenario else {
                unreachable!()
            };
            let closing = outer_close(completion, 1);
            send(outer, &closing);
            let mut close = receive(&mut run, &mut ports, outer_role);
            complete_ack(&mut run, &mut ports, &mut close, outer, 1);
            // DATA alone does not establish the unused physical endpoint.
            let before_eof = matches!(
                run.poll_consumer_frame(&mut ports, helper_role),
                Ok(ConsumerReceiveProgress::Pending)
            );
            end_producer_writes(helper);
            let unused = matches!(
                run.poll_consumer_frame(&mut ports, helper_role),
                Ok(ConsumerReceiveProgress::Unused)
            );
            let cache = run.test_consumer_cache(outer_role);
            let exact_outer = cache.len() == 2
                && cache[0].literal_utf8().as_bytes() == OPEN
                && cache[1].literal_utf8().as_bytes() == &closing[4..];
            let empty = run.test_consumer_cache(helper_role).is_empty();
            let no_ack = no_helper_ack(helper);
            let healthy = run.visit_observation_bytes(0).is_ok();
            drop(prepared);
            drop(ports);
            assert!(
                before_eof,
                "Outer metadata alone cannot fabricate physical helper EOF"
            );
            assert!(unused && exact_outer && empty && no_ack && healthy);
            return Err(InstalledAdapterError::ObservationIncomplete);
        }
        if !matches!(self.scenario, Scenario::StartedMissingClose) {
            end_producer_writes(helper);
            let waiting = matches!(
                run.poll_consumer_frame(&mut ports, helper_role),
                Ok(ConsumerReceiveProgress::AwaitingAssociation)
            );
            let empty = run.test_consumer_cache(helper_role).is_empty();
            let no_ack = no_helper_ack(helper);
            if !waiting || !empty || !no_ack {
                drop(prepared);
                drop(ports);
                assert!(
                    waiting,
                    "native empty EOF must await SAME Outer, not infer no helper"
                );
                assert!(empty && no_ack);
                return Err(InstalledAdapterError::ObservationIncomplete);
            }
            // A helper-side EOF must not stop servicing the independent Outer.
            let outer_pending = outer_first
                || matches!(
                    run.poll_consumer_frame(&mut ports, outer_role),
                    Ok(ConsumerReceiveProgress::Pending)
                );
            if !outer_pending {
                drop(prepared);
                drop(ports);
                assert!(
                    outer_pending,
                    "helper EOF cannot poison an incomplete Outer frame"
                );
                return Err(InstalledAdapterError::ObservationIncomplete);
            }
        }
        if !outer_first {
            send(outer, &framed(OPEN));
            let mut open = receive(&mut run, &mut ports, outer_role);
            complete_ack(&mut run, &mut ports, &mut open, outer, 0);
        }

        match self.scenario {
            Scenario::Resolve { completion, .. } => {
                let close = outer_close(completion, 1);
                send(outer, &close);
                let mut closing = receive(&mut run, &mut ports, outer_role);
                // Even cached Close is not yet the required ACK-completed Close.
                let before_ack = matches!(
                    run.poll_consumer_frame(&mut ports, helper_role),
                    Ok(ConsumerReceiveProgress::AwaitingAssociation)
                );
                complete_ack(&mut run, &mut ports, &mut closing, outer, 1);
                let unused = matches!(
                    run.poll_consumer_frame(&mut ports, helper_role),
                    Ok(ConsumerReceiveProgress::Unused)
                );
                let cache = run.test_consumer_cache(outer_role);
                let exact_outer = cache.len() == 2
                    && cache[0].literal_utf8().as_bytes() == OPEN
                    && cache[1].literal_utf8().as_bytes() == &close[4..];
                let empty = run.test_consumer_cache(helper_role).is_empty();
                let no_ack = no_helper_ack(helper);
                let still_healthy = run.visit_observation_bytes(0).is_ok();
                drop(prepared);
                drop(ports);
                assert!(
                    before_ack,
                    "retained but unACKed Close cannot resolve helper EOF"
                );
                assert!(
                    unused,
                    "matching no-helper completion resolves only the unused endpoint"
                );
                assert!(exact_outer && empty && no_ack && still_healthy);
            }
            Scenario::WaitingThenStarted | Scenario::StartedMissingClose => {
                let started = unit.helper_started(&mut run);
                send(outer, &started);
                let mut launch = receive(&mut run, &mut ports, outer_role);
                complete_ack(&mut run, &mut ports, &mut launch, outer, 1);
                if matches!(self.scenario, Scenario::StartedMissingClose) {
                    send(helper, &framed(OPEN));
                    let mut open = receive(&mut run, &mut ports, helper_role);
                    complete_ack(&mut run, &mut ports, &mut open, helper, 0);
                    let close = outer_close(Completion::Started, 2);
                    send(outer, &close);
                    let mut closing = receive(&mut run, &mut ports, outer_role);
                    complete_ack(&mut run, &mut ports, &mut closing, outer, 2);
                    end_producer_writes(helper);
                }
                let error = run.poll_consumer_frame(&mut ports, helper_role).err();
                let count = run.test_consumer_cache(helper_role).len();
                let exact_open = !matches!(self.scenario, Scenario::StartedMissingClose)
                    || run
                        .test_consumer_cache(helper_role)
                        .first()
                        .is_some_and(|event| event.literal_utf8().as_bytes() == OPEN);
                let no_ack = no_helper_ack(helper);
                let repeated = run.poll_consumer_frame(&mut ports, helper_role).err();
                drop(prepared);
                drop(ports);
                assert_eq!(error, Some(ConsumerCodecError::Framing));
                assert_eq!(repeated, Some(ConsumerCodecError::PriorFault));
                assert_eq!(
                    count,
                    usize::from(matches!(self.scenario, Scenario::StartedMissingClose))
                );
                assert!(
                    no_ack,
                    "Started never permits a fabricated helper Close/ACK"
                );
                assert!(
                    exact_open,
                    "the actual helper Open survives refusal unchanged"
                );
            }
            Scenario::Deadline => {
                assert!(
                    Instant::now() < end,
                    "waiting premise precedes original end"
                );
                std::thread::sleep(
                    end.saturating_duration_since(Instant::now()) + Duration::from_millis(1),
                );
                let error = run.poll_consumer_frame(&mut ports, helper_role).err();
                let empty = run.test_consumer_cache(helper_role).is_empty();
                let no_ack = no_helper_ack(helper);
                let repeated = run.poll_consumer_frame(&mut ports, helper_role).err();
                drop(prepared);
                drop(ports);
                assert_eq!(error, Some(ConsumerCodecError::Expired));
                assert_eq!(repeated, Some(ConsumerCodecError::PriorFault));
                assert!(empty && no_ack, "EOF does not reset the original end");
            }
            _ => unreachable!(),
        }
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}

fn exercise_eof(scenario: Scenario) {
    let mut probe = EofProbe {
        scenario,
        entered: false,
        owner: std::sync::Arc::new(TestGateOwner {
            gate: InvocationGate::dormant(),
        }),
    };
    with_policy(&mut probe);
    assert!(probe.entered, "genuine full24 callback executes");
}
#[test]
fn native_empty_helper_eof_waits_for_same_acked_not_attempted_close_in_either_poll_order() {
    for outer_first in [false, true] {
        exercise_eof(Scenario::Resolve {
            completion: Completion::NotAttempted,
            outer_first,
        });
    }
}
#[test]
fn native_empty_helper_eof_can_resolve_after_same_acked_launch_failed_close() {
    exercise_eof(Scenario::Resolve {
        completion: Completion::LaunchFailed,
        outer_first: false,
    });
}
#[test]
fn native_pending_empty_eof_cannot_hide_a_later_actual_helper_started_frame() {
    exercise_eof(Scenario::WaitingThenStarted);
}
#[test]
fn native_started_helper_eof_without_helper_close_stays_framing_failure() {
    exercise_eof(Scenario::StartedMissingClose);
}
#[test]
fn native_partial_header_or_body_eof_is_never_an_unused_endpoint() {
    exercise_eof(Scenario::PartialHeader);
    exercise_eof(Scenario::PartialBody);
    exercise_eof(Scenario::PartialHeaderAfterClose);
    exercise_eof(Scenario::PartialBodyAfterClose);
}
#[test]
fn node_in_process_helper_eof_is_not_a_native_unused_endpoint() {
    exercise_eof(Scenario::NodeEof);
}
#[test]
fn native_empty_eof_wait_preserves_original_deadline() {
    exercise_eof(Scenario::Deadline);
}
