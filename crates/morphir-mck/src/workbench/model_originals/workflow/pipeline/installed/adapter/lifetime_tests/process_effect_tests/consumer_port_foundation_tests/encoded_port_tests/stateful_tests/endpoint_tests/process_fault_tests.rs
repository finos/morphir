//! Actual child/reader fault precedes later missing-hook transport failure.
//! Existing raw effect peer only; no consumer business/source qualification.
use super::*;
use crate::transport::process::ProcessFault;
use crate::workbench::model_originals::workflow::pipeline::RunFault;
struct Probe {
    entered: bool,
    owner: std::sync::Arc<TestGateOwner>,
}
impl InstalledClientAdapter for Probe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        self.entered = true;
        let end = Instant::now() + Duration::from_secs(10);
        activate(&mut run, &self.owner, end);
        let directory = tempfile::tempdir().unwrap();
        let marker = directory.path().join("actual-marker");
        let program = PathBuf::from(
            std::env::var_os("MORPHIR_MCK_REPORT_PEER_BIN")
                .expect("explicit freshly-built actual peer"),
        );
        let arguments = [
            OsString::from("--adapter"),
            OsString::from("installed-process-effect-marker"),
            marker.as_os_str().to_owned(),
        ];
        let (prepared, mut ports) = run
            .prepare_consumer_process(
                ConsumerProcessCommand {
                    purpose: InstalledProcessPurpose::Canonical {
                        action_index: 8,
                        command: InstalledCommand::Publish,
                    },
                    program: &program,
                    arguments: &arguments,
                    directory: directory.path(),
                    environment: &[],
                    limits: Limits {
                        max_frame: 1,
                        stderr_capture: 128,
                        ..Limits::DEFAULT
                    },
                },
                end,
            )
            .unwrap();
        let mut process = run.spawn_prepared_consumer_process(prepared).unwrap();
        let mut observed = None;
        while Instant::now() < end {
            if let Ok(ProcessProgress::Faulted(fault)) = run.advance_consumer_process(&mut process)
            {
                observed = Some(*fault);
                break;
            }
            std::thread::sleep(Duration::from_millis(1));
        }
        // Cleanup SAME actual child/readers before any behavioral assertion.
        let finished = loop {
            let _ = process.request_termination();
            let _ = process.advance();
            let _ = process.reap_retained();
            match process.try_finish() {
                InstalledProcessFinish::Finished(finished) => break finished,
                InstalledProcessFinish::Pending(same) => process = same,
            }
            assert!(
                Instant::now() < end,
                "real faulted child/readers must be joined under original end"
            );
            std::thread::sleep(Duration::from_millis(1));
        };
        let actual_fault = finished.outcome().first_fault().copied();
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
        let later = run.require_consumer_close(&mut ports);
        let first_preserved = matches!(
            run.attempt.ready(),
            Err(RunFault::InstalledProcessFault(ProcessFault::StdoutLimit))
        );
        let before = run.installed_observation_usage();
        let repeated = run.require_consumer_close(&mut ports);
        let unchanged = run.installed_observation_usage() == before;
        drop(finished);
        drop(ports);
        assert_eq!(observed, Some(ProcessFault::StdoutLimit));
        assert_eq!(actual_fault, Some(ProcessFault::StdoutLimit));
        assert_eq!(
            std::fs::read(marker).unwrap(),
            b"installed-process-effect-entry-v1\n"
        );
        assert!(
            eof,
            "actual hook-free child closed both inherited descriptors"
        );
        assert!(later.is_err() && repeated.is_err());
        assert!(
            first_preserved,
            "later missing hooks must not replace the actual first process fault"
        );
        assert!(unchanged, "repeated refusal cannot reset/spend the owner");
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
#[test]
fn genuine_stdout_limit_precedes_later_missing_hook_eof_and_actual_readers_join() {
    let mut probe = Probe {
        entered: false,
        owner: std::sync::Arc::new(TestGateOwner {
            gate: InvocationGate::dormant(),
        }),
    };
    with_policy(&mut probe);
    assert!(probe.entered, "genuine complete24 callback required");
}
