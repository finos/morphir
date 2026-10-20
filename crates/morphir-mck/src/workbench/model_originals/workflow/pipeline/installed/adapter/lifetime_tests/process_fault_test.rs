//! One actual ProcessOutcome fault control in a SYNTHETIC compiled callback.
//! Reuses sealed d423 marker peer unchanged. No Git/canonical success DATA.
//! Child of installed::adapter::lifetime_tests; no new production API.
use super::*;
use crate::transport::{
    Limits,
    process::{ProcessFault, ProcessProgress},
};
use std::{
    ffi::OsString,
    path::PathBuf,
    time::{Duration, Instant},
};

struct FaultProbe {
    owner: std::sync::Arc<TestGateOwner>,
    program: PathBuf,
    directory: PathBuf,
    marker: PathBuf,
    entered: bool,
}
fn finish_faulted(mut process: RunningInstalledProcess) -> FinishedInstalledProcess {
    let end = Instant::now() + Duration::from_secs(10);
    loop {
        let cleanup = match process.advance() {
            ProcessProgress::Finished(_) => break,
            ProcessProgress::Faulted(fault) => {
                assert_eq!(*fault, ProcessFault::StdoutLimit);
                true
            }
            ProcessProgress::ExitObserved(_) => true,
            ProcessProgress::Working => false,
        };
        if cleanup {
            // Faulted progress can mask ExitObserved; actual advance still
            // polls nonreaping exit. Same owner termination+explicit reap is
            // progressed until status/readers genuinely settle, never fake
            // success or an assumed exit0/signal race result.
            process.request_termination().unwrap();
            process.reap_retained().unwrap();
        }
        assert!(
            Instant::now() < end,
            "real faulty process must drain within finite control deadline"
        );
        std::thread::sleep(Duration::from_millis(1));
    }
    match process.try_finish() {
        InstalledProcessFinish::Finished(finished) => finished,
        InstalledProcessFinish::Pending(_same_process) => {
            panic!("actual Finished must carry waited status and joined readers")
        }
    }
}
impl InstalledClientAdapter for FaultProbe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        assert!(!self.entered);
        self.entered = true;
        assert_eq!(
            run.source().case_id(),
            "single-file-explicit-companion-preserves-opaque-bytes"
        );
        let projection: std::sync::Arc<dyn InvocationGateSource> = self.owner.clone();
        let _token = run
            .issue_host_observation(std::sync::Arc::downgrade(&projection))
            .unwrap();
        let arguments = [
            OsString::from("--adapter"),
            OsString::from("installed-process-effect-marker"),
            self.marker.as_os_str().to_owned(),
        ];
        let process = match run.spawn_process(
            // Explicit synthetic purpose isolates actual outcome-fault
            // handling from the canonical stdout JSON decoder. This peer is
            // not represented as a real Git query in any successful DATA.
            InstalledProcessPurpose::Metadata(InstalledMetadataQuery::Revision),
            &self.program,
            arguments.iter().map(|arg| arg.as_os_str()),
            &self.directory,
            &[],
            Limits {
                max_frame: 1,
                stderr_capture: 32,
                ..Limits::DEFAULT
            },
        ) {
            Ok(process) => process,
            Err(error) => panic!("actual bounded peer spawn should be admitted: {error:?}"),
        };
        let finished = finish_faulted(process);
        assert_eq!(
            std::fs::read(&self.marker).unwrap(),
            b"installed-process-effect-entry-v1\n"
        );
        assert_eq!(
            finished.outcome().first_fault(),
            Some(&ProcessFault::StdoutLimit)
        );
        assert!(finished.outcome().stdout().len() <= 1);
        // No assertion about exit0 versus termination race. Actual finished
        // owner has already waited direct child and joined created readers.
        assert!(run.attempt.ready().is_ok());
        assert!(run.receiving.ready().is_ok());
        let before = run.installed_observation_usage();
        assert_eq!(
            run.record_finished_process(finished),
            Err(InstalledAdapterError::ObservationIncomplete),
            "real transport fault must not become an ordinary Finished record"
        );
        let first = match run.attempt.ready() {
            Err(fault) => fault.summary(),
            Ok(_) => panic!("actual producer fault must latch before ordinary record"),
        };
        assert_eq!(
            (first.phase, first.code),
            ("installed-process", "stdout-limit")
        );
        assert!(
            run.receiving.ready().is_ok(),
            "transport fault is not a fabricated receiving-budget error"
        );
        assert_eq!(run.installed_observation_usage(), before);
        assert!(
            run.prepare_snapshot_read(1).is_err(),
            "later actual run work must refuse"
        );
        assert_eq!(run.attempt.ready().err().unwrap().summary(), first);
        assert_eq!(run.installed_observation_usage(), before);
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
#[test]
fn c4_actual_stdout_fault_cannot_be_erased_by_finished_process_recording() {
    let kit = tempfile::tempdir().unwrap();
    let directory = kit.path().canonicalize().unwrap();
    std::fs::write(directory.join("cases.json"), CASES).unwrap();
    let program = PathBuf::from(
        std::env::var_os("MORPHIR_MCK_REPORT_PEER_BIN")
            .expect("fresh real peer executable required, no silent skip"),
    );
    assert!(program.is_absolute());
    let program = program.canonicalize().unwrap();
    let mut probe = FaultProbe {
        owner: std::sync::Arc::new(TestGateOwner {
            gate: InvocationGate::dormant(),
        }),
        program,
        marker: directory.join("actual-entry.marker"),
        directory,
        entered: false,
    };
    let report =
        run_configured_with_installed_client_adapter(kit.path(), &configuration(), &mut probe)
            .unwrap();
    assert!(probe.entered, "genuine complete24 gate must issue callback");
    assert!(!report.qualified());
}
