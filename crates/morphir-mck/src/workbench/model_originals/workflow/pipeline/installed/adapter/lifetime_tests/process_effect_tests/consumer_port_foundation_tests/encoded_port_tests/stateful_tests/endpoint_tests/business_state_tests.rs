//! Stateful structural controls on real owned endpoints, SYNTHETIC unit DATA.
//! No process, C hook, application-effect, healthy business result or report proof.
use super::*;

#[derive(Clone, Copy)]
enum Hook {
    Release,
    Commit,
    Cleanup,
}
impl Hook {
    fn role(self) -> ConsumerProducerRole {
        match self {
            Self::Release => ConsumerProducerRole::TransferHelper,
            Self::Commit | Self::Cleanup => ConsumerProducerRole::Outer,
        }
    }
    fn frame(self, sequence: u64) -> Vec<u8> {
        match self {
            Self::Commit => commit(sequence),
            Self::Cleanup => framed(format!(r#"{{"kind":"fact","version":"0.1.0-draft.1","sequence":{sequence},"fact":{{"kind":"scratch-cleanup-finished","path":{{"kind":"unix-bytes","bytes":{{"kind":"utf8","text":"/unit-output"}}}},"outcome":"returned"}}}}"#).as_bytes()),
            Self::Release => {
                // Reuse the reviewed literal release vector. Mutation changes
                // only its numeric sequence, never creates a new expectation.
                let vector = vectors().into_iter().find(|v| v.name == "release").unwrap();
                let wire = unhex(&vector.wire_hex);
                let mut value: serde_json::Value = serde_json::from_slice(&wire[4..]).unwrap();
                value["sequence"] = serde_json::json!(sequence);
                framed(&serde_json::to_vec(&value).unwrap())
            }
        }
    }
}

fn close(role: ConsumerProducerRole, sequence: u64, facts: u64) -> Vec<u8> {
    let helper = match role {
        ConsumerProducerRole::Outer => "in-process",
        ConsumerProducerRole::TransferHelper => "not-applicable",
    };
    framed(format!(r#"{{"kind":"close","version":"0.1.0-draft.1","sequence":{sequence},"attemptedHooks":{facts},"startedFactFrames":{facts},"retainedBusinessFacts":{facts},"helper":{{"kind":"{helper}"}}}}"#).as_bytes())
}

#[derive(Clone, Copy)]
enum Scenario {
    NoFactsClose(ConsumerProducerRole),
    AckedFactCloseZero(Hook),
    Duplicate(Hook),
    CommitThenCleanup,
    CleanupThenCommit,
}
struct StructuralProbe {
    scenario: Scenario,
    entered: bool,
    owner: std::sync::Arc<TestGateOwner>,
}
impl InstalledClientAdapter for StructuralProbe {
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
        let role = match self.scenario {
            Scenario::NoFactsClose(role) => role,
            Scenario::AckedFactCloseZero(hook) | Scenario::Duplicate(hook) => hook.role(),
            Scenario::CommitThenCleanup | Scenario::CleanupThenCommit => {
                ConsumerProducerRole::Outer
            }
        };
        let peer = prepared.test_child_handle(role);
        send(peer, &framed(OPEN));
        let mut opened = receive(&mut run, &mut ports, role);
        complete_ack(&mut run, &mut ports, &mut opened, peer, 0);

        let first = match self.scenario {
            Scenario::NoFactsClose(_) => None,
            Scenario::AckedFactCloseZero(hook) | Scenario::Duplicate(hook) => Some(hook),
            Scenario::CommitThenCleanup => Some(Hook::Commit),
            Scenario::CleanupThenCommit => Some(Hook::Cleanup),
        };
        let first_frame = first.map(|hook| hook.frame(1));
        if let Some(frame) = &first_frame {
            send(peer, frame);
            let mut ticket = receive(&mut run, &mut ports, role);
            complete_ack(&mut run, &mut ports, &mut ticket, peer, 1);
        }

        if matches!(
            self.scenario,
            Scenario::CommitThenCleanup | Scenario::CleanupThenCommit
        ) {
            let second = match self.scenario {
                Scenario::CommitThenCleanup => Hook::Cleanup,
                Scenario::CleanupThenCommit => Hook::Commit,
                _ => unreachable!(),
            };
            let second_frame = second.frame(2);
            send(peer, &second_frame);
            let mut second_ticket = receive(&mut run, &mut ports, role);
            complete_ack(&mut run, &mut ports, &mut second_ticket, peer, 2);
            let closing = close(role, 3, 2);
            send(peer, &closing);
            let mut close_ticket = receive(&mut run, &mut ports, role);
            complete_ack(&mut run, &mut ports, &mut close_ticket, peer, 3);
            let cache = run.test_consumer_cache(role);
            let preserved = cache.len() == 4
                && cache[0].literal_utf8().as_bytes() == OPEN
                && cache[1].literal_utf8().as_bytes() == &first_frame.as_ref().unwrap()[4..]
                && cache[2].literal_utf8().as_bytes() == &second_frame[4..]
                && cache[3].literal_utf8().as_bytes() == &closing[4..];
            drop(prepared);
            drop(ports);
            assert!(
                preserved,
                "both distinct facts and matching Close must retain exact literals"
            );
            return Err(InstalledAdapterError::ObservationIncomplete);
        }

        let (bad, expected, prior_len) = match self.scenario {
            Scenario::NoFactsClose(_) => (close(role, 1, 1), ConsumerCodecError::Shape, 1),
            Scenario::AckedFactCloseZero(_) => (close(role, 2, 0), ConsumerCodecError::Shape, 2),
            Scenario::Duplicate(hook) => (hook.frame(2), ConsumerCodecError::Sequence, 2),
            _ => unreachable!(),
        };
        send(peer, &bad);
        let first_error = run.poll_consumer_frame(&mut ports, role).err();
        let cache = run.test_consumer_cache(role);
        let prior_preserved = cache.len() == prior_len
            && cache[0].literal_utf8().as_bytes() == OPEN
            && first_frame.as_ref().is_none_or(|frame| {
                cache
                    .get(1)
                    .is_some_and(|entry| entry.literal_utf8().as_bytes() == &frame[4..])
            });
        let repeated_error = run.poll_consumer_frame(&mut ports, role).err();
        let no_bad_ack = matches!(
            rustix::io::read(peer, &mut [0u8; 1]),
            Ok(0) | Err(rustix::io::Errno::AGAIN)
        );
        // No child was spawned. Drop the actual owning endpoint pair and
        // collector before the behavioral RED assertion, even on old behavior.
        drop(prepared);
        drop(ports);
        assert_eq!(first_error, Some(expected));
        assert!(
            prior_preserved,
            "offending frame must not replace or extend prior cache"
        );
        assert_eq!(repeated_error, Some(ConsumerCodecError::PriorFault));
        assert!(no_bad_ack, "no ACK byte may authorize the offending frame");
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}

fn exercise_structural(scenario: Scenario) {
    let mut probe = StructuralProbe {
        scenario,
        entered: false,
        owner: std::sync::Arc::new(TestGateOwner {
            gate: InvocationGate::dormant(),
        }),
    };
    with_policy(&mut probe);
    assert!(probe.entered, "genuine complete24 callback must execute");
}

#[test]
fn healthy_close_cannot_claim_one_retained_fact_when_none_was_received() {
    for role in [
        ConsumerProducerRole::Outer,
        ConsumerProducerRole::TransferHelper,
    ] {
        exercise_structural(Scenario::NoFactsClose(role));
    }
}
#[test]
fn healthy_close_cannot_erase_a_previously_acked_fact() {
    for hook in [Hook::Release, Hook::Commit, Hook::Cleanup] {
        exercise_structural(Scenario::AckedFactCloseZero(hook));
    }
}
#[test]
fn release_fact_is_once_only_with_a_correct_next_sequence() {
    exercise_structural(Scenario::Duplicate(Hook::Release));
}
#[test]
fn commit_fact_is_once_only_with_a_correct_next_sequence() {
    exercise_structural(Scenario::Duplicate(Hook::Commit));
}
#[test]
fn cleanup_fact_is_once_only_with_a_correct_next_sequence() {
    exercise_structural(Scenario::Duplicate(Hook::Cleanup));
}
#[test]
fn distinct_outer_facts_and_correlated_close_remain_structurally_valid() {
    exercise_structural(Scenario::CommitThenCleanup);
    exercise_structural(Scenario::CleanupThenCommit);
}
