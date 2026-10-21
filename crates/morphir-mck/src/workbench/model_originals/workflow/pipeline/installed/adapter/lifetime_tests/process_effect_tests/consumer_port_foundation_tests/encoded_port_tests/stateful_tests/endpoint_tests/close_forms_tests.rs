//! Endpoint/lane forms on actual sockets, SYNTHETIC association DATA only.
use super::*;

#[derive(Clone, Copy)]
enum CloseForm {
    HelperInProcess,
    NodeStarted,
    NativeInProcess,
    NativeNotAttempted,
    NativeLaunchFailed,
    NativeStarted,
}
struct CloseProbe {
    form: CloseForm,
    owner: std::sync::Arc<TestGateOwner>,
    entered: bool,
}
impl InstalledClientAdapter for CloseProbe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        self.entered = true;
        let end = Instant::now() + Duration::from_secs(10);
        activate(&mut run, &self.owner, end);
        let program = std::env::current_exe().unwrap().canonicalize().unwrap();
        let directory = tempfile::tempdir().unwrap();
        let native = matches!(
            self.form,
            CloseForm::NativeInProcess
                | CloseForm::NativeNotAttempted
                | CloseForm::NativeLaunchFailed
                | CloseForm::NativeStarted
        );
        let unit = Unit::new(
            &mut run,
            &program,
            directory.path(),
            if native {
                FixtureStrategy::NativeExecutable
            } else {
                FixtureStrategy::NodePackage
            },
        );
        let (prepared, mut ports) = unit.prepare(&mut run, end);
        let role = if matches!(self.form, CloseForm::HelperInProcess) {
            ConsumerProducerRole::TransferHelper
        } else {
            ConsumerProducerRole::Outer
        };
        let peer = prepared.test_child_handle(role);
        send(peer, &framed(OPEN));
        let mut opened = receive(&mut run, &mut ports, role);
        complete_ack(&mut run, &mut ports, &mut opened, peer, 0);
        let sequence = if matches!(self.form, CloseForm::NativeStarted) {
            send(peer, &unit.helper_started(&mut run));
            let mut ticket = receive(&mut run, &mut ports, role);
            complete_ack(&mut run, &mut ports, &mut ticket, peer, 1);
            2
        } else {
            1
        };
        let helper = match self.form {
            CloseForm::HelperInProcess | CloseForm::NativeInProcess => r#"{"kind":"in-process"}"#,
            CloseForm::NodeStarted | CloseForm::NativeStarted => {
                r#"{"kind":"started","wait":{"kind":"waited","rawStatus":"0"},"stdout":{"kind":"not-created"},"stderr":{"kind":"not-created"}}"#
            }
            CloseForm::NativeNotAttempted => r#"{"kind":"not-attempted"}"#,
            CloseForm::NativeLaunchFailed => {
                r#"{"kind":"launch-failed","stage":"preparation","stdout":{"kind":"not-created"},"stderr":{"kind":"not-created"}}"#
            }
        };
        let closing=framed(format!(r#"{{"kind":"close","version":"0.1.0-draft.1","sequence":{sequence},"attemptedHooks":0,"startedFactFrames":0,"retainedBusinessFacts":0,"helper":{helper}}}"#).as_bytes());
        send(peer, &closing);
        let expected = match self.form {
            CloseForm::HelperInProcess => Some(ConsumerCodecError::Role),
            CloseForm::NodeStarted | CloseForm::NativeInProcess => {
                Some(ConsumerCodecError::Association)
            }
            _ => None,
        };
        let result = run.poll_consumer_frame(&mut ports, role);
        let actual = match result {
            Ok(ConsumerReceiveProgress::Retained(mut ticket)) => {
                if expected.is_none() {
                    complete_ack(&mut run, &mut ports, &mut ticket, peer, sequence);
                }
                None
            }
            Err(error) => Some(error),
            _ => panic!("complete test frame must make progress"),
        };
        let cache = run.test_consumer_cache(role);
        let preserved = cache
            .first()
            .is_some_and(|entry| entry.literal_utf8().as_bytes() == OPEN);
        let count = cache.len();
        let last = cache
            .last()
            .map(|entry| entry.literal_utf8().as_bytes() == &closing[4..]);
        let repeated = if expected.is_some() {
            run.poll_consumer_frame(&mut ports, role).err()
        } else {
            None
        };
        let no_bad_ack = if expected.is_some() {
            matches!(
                rustix::io::read(peer, &mut [0; 1]),
                Ok(0) | Err(rustix::io::Errno::AGAIN)
            )
        } else {
            true
        };
        drop(prepared);
        drop(ports);
        // All behavioral assertions follow owning endpoint destruction.
        assert_eq!(actual, expected);
        assert!(preserved);
        if expected.is_some() {
            assert_eq!(count, sequence as usize);
            assert_eq!(repeated, Some(ConsumerCodecError::PriorFault));
            assert!(no_bad_ack);
        } else {
            assert_eq!(count, sequence as usize + 1);
            assert_eq!(last, Some(true));
        }
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
fn exercise_close(form: CloseForm) {
    let mut probe = CloseProbe {
        form,
        owner: std::sync::Arc::new(TestGateOwner {
            gate: InvocationGate::dormant(),
        }),
        entered: false,
    };
    with_policy(&mut probe);
    assert!(probe.entered);
}
#[test]
fn helper_close_cannot_use_outer_in_process_form() {
    exercise_close(CloseForm::HelperInProcess)
}
#[test]
fn node_outer_close_cannot_claim_native_started_completion() {
    exercise_close(CloseForm::NodeStarted)
}
#[test]
fn native_outer_close_cannot_claim_in_process_completion() {
    exercise_close(CloseForm::NativeInProcess)
}
#[test]
fn native_outer_completion_forms_preserve_their_existing_association() {
    for form in [
        CloseForm::NativeNotAttempted,
        CloseForm::NativeLaunchFailed,
        CloseForm::NativeStarted,
    ] {
        exercise_close(form)
    }
}
