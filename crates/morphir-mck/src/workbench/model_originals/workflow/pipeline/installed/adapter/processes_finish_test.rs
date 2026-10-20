//! Genuine marker peer, synthetic compiled invocation, no successful DATA or role credit.
use super::*;
use crate::workbench::model_originals::installed::InstalledProcessFinish;
use crate::workbench::{RunConfiguration, run_configured_with_installed_client_adapter};
use std::{
    path::PathBuf,
    sync::Arc,
    time::{Duration, Instant},
};

struct GateOwner {
    gate: InvocationGate,
}
impl InvocationGateSource for GateOwner {
    fn invocation_gate(&self) -> &InvocationGate {
        &self.gate
    }
    fn wake_observers(&self) {}
}
struct PendingProbe {
    owner: Arc<GateOwner>,
    program: PathBuf,
    directory: PathBuf,
    marker: PathBuf,
    entered: bool,
}
impl InstalledClientAdapter for PendingProbe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        assert!(!self.entered);
        self.entered = true;
        let projection: Arc<dyn InvocationGateSource> = self.owner.clone();
        let _token = run
            .issue_host_observation(Arc::downgrade(&projection))
            .unwrap();
        let arguments = [
            OsString::from("--adapter"),
            OsString::from("installed-process-effect-marker"),
            self.marker.as_os_str().to_owned(),
        ];
        let process = run
            .spawn_process(
                InstalledProcessPurpose::Metadata(InstalledMetadataQuery::Revision),
                &self.program,
                arguments.iter().map(|v| v.as_os_str()),
                &self.directory,
                &[],
                Limits {
                    max_frame: 64,
                    stderr_capture: 32,
                    ..Limits::DEFAULT
                },
            )
            .unwrap_or_else(|error| panic!("genuine marker peer must spawn: {error:?}"));
        let pid = process.process.id();
        let ordinal = process.description.ordinal;
        let purpose = process.description.purpose;
        let invocation = process.description.invocation.clone();
        let program_storage = process.description.program.as_encoded_bytes().as_ptr();
        let argument_storage = process.description.arguments.as_ptr();
        let directory_storage = process.description.directory.as_encoded_bytes().as_ptr();

        // No advance/status/reap has run. Even if the child body has exited,
        // the genuine owner has not observed or joined it and must stay owned.
        let mut process = match process.try_finish() {
            InstalledProcessFinish::Pending(same) => same,
            InstalledProcessFinish::Finished(_) => {
                panic!("unobserved child/readers cannot be Finished")
            }
        };
        assert_eq!(process.process.id(), pid);
        assert_eq!(process.description.ordinal, ordinal);
        assert_eq!(process.description.purpose, purpose);
        assert!(std::sync::Weak::ptr_eq(
            &invocation,
            &process.description.invocation
        ));
        assert_eq!(
            process.description.program.as_encoded_bytes().as_ptr(),
            program_storage
        );
        assert_eq!(process.description.arguments.as_ptr(), argument_storage);
        assert_eq!(
            process.description.directory.as_encoded_bytes().as_ptr(),
            directory_storage
        );
        assert_eq!(
            process.description.program.as_os_str(),
            self.program.as_os_str()
        );
        assert_eq!(process.description.arguments, arguments);
        assert_eq!(
            process.description.directory.as_os_str(),
            self.directory.as_os_str()
        );

        let end = Instant::now() + Duration::from_secs(10);
        loop {
            match process.advance() {
                ProcessProgress::ExitObserved(_) => {
                    process.request_termination().unwrap();
                    process.reap_retained().unwrap();
                }
                ProcessProgress::Finished(_) => break,
                ProcessProgress::Working | ProcessProgress::Faulted(_) => {}
            }
            assert!(
                Instant::now() < end,
                "same actual owner must finish within explicit deadline"
            );
            std::thread::sleep(Duration::from_millis(1));
        }
        let finished = match process.try_finish() {
            InstalledProcessFinish::Finished(finished) => finished,
            InstalledProcessFinish::Pending(_) => {
                panic!("actual direct-child/readers completion must transfer outcome")
            }
        };
        assert_eq!(finished.description.ordinal, ordinal);
        assert_eq!(finished.purpose(), purpose);
        assert!(std::sync::Weak::ptr_eq(
            &invocation,
            &finished.description.invocation
        ));
        assert_eq!(
            finished.description.program.as_encoded_bytes().as_ptr(),
            program_storage
        );
        assert_eq!(finished.description.arguments.as_ptr(), argument_storage);
        assert_eq!(
            finished.description.directory.as_encoded_bytes().as_ptr(),
            directory_storage
        );
        assert_eq!(finished.outcome().status().code(), Some(0));
        assert_eq!(finished.outcome().stdout(), b"entered\n");
        assert_eq!(finished.outcome().stderr(), b"");
        assert_eq!(finished.outcome().first_fault(), None);
        assert_eq!(
            std::fs::read(&self.marker).unwrap(),
            b"installed-process-effect-entry-v1\n"
        );
        // The actual same-run admission checks the retained invocation again.
        run.record_finished_process(finished).unwrap();
        assert!(run.attempt.ready().is_ok());
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
#[test]
fn pending_finish_state_preserves_same_actual_owner_before_any_advance() {
    let kit = tempfile::tempdir().unwrap();
    let directory = kit.path().canonicalize().unwrap();
    std::fs::write(
        directory.join("cases.json"),
        include_bytes!("lifetime_tests/fixtures/cases24.json"),
    )
    .unwrap();
    let policy = RunConfiguration::from_json(&serde_json::json!({
        "kind":"model-originals-installed-client",
        "checker":serde_json::from_str::<serde_json::Value>(include_str!("lifetime_tests/fixtures/checker-policy.json")).unwrap(),
        "observation":{"source":{"attempts":8192,"readCalls":8192,"returnedBytes":67108864,"files":16},"workers":{"attempts":64,"updates":8192},"host":{"updates":8192}},
        "privateRecord":{"retainedBytes":67108864},
        "installedObservation":{"rpcFrames":"checker-capture","retainedBytes":16777216,"stdoutPrefixBytes":1048576,"stderrPrefixBytes":1048576,"snapshotReadBytes":16777216,"byteVisits":67108864,"records":8192}
    }).to_string()).unwrap();
    let program = PathBuf::from(
        std::env::var_os("MORPHIR_MCK_REPORT_PEER_BIN")
            .expect("explicit fresh genuine peer required"),
    );
    assert!(program.is_absolute());
    let mut probe = PendingProbe {
        owner: Arc::new(GateOwner {
            gate: InvocationGate::dormant(),
        }),
        program: program.canonicalize().unwrap(),
        marker: directory.join("pending-owner.marker"),
        directory: directory.clone(),
        entered: false,
    };
    let report =
        run_configured_with_installed_client_adapter(&directory, &policy, &mut probe).unwrap();
    assert!(
        probe.entered,
        "same complete24 issuer must execute callback"
    );
    assert!(!report.qualified());
}
