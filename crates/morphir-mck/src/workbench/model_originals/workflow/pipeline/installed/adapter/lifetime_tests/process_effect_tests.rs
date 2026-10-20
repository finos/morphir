//! Actual child-entry effects through a SYNTHETIC compiled invocation.
//! No installed-client behavior, Git metadata, source association or role credit.
//! Child of existing installed::adapter::lifetime_tests, reusing its fixtures
//! and genuine pre-existing TestGateOwner allocation/engine callback.
use super::*;
use crate::transport::{Limits, process::ProcessProgress};
use std::{
    ffi::OsString,
    path::{Path, PathBuf},
    time::{Duration, Instant},
};

const ENTRY: &[u8] = b"installed-process-effect-entry-v1\n";

#[derive(Clone, Copy)]
enum Effect {
    Finish,
    Refuse(InstalledObservationResource),
    PriorFault,
}
struct EffectProbe {
    owner: std::sync::Arc<TestGateOwner>,
    program: PathBuf,
    marker: PathBuf,
    directory: PathBuf,
    effect: Effect,
    entered: bool,
}
fn actual_finish(mut process: RunningInstalledProcess) -> FinishedInstalledProcess {
    let end = Instant::now() + Duration::from_secs(10);
    loop {
        match process.advance() {
            ProcessProgress::ExitObserved(_) => {
                // This finite peer has no descendants. Retire the actual tree
                // before consuming its root, exactly as the real owner requires.
                process.request_termination().unwrap();
                process.reap_retained().unwrap();
            }
            ProcessProgress::Finished(_) => break,
            ProcessProgress::Working | ProcessProgress::Faulted(_) => {}
        }
        assert!(
            Instant::now() < end,
            "actual peer must finish within finite control deadline"
        );
        std::thread::sleep(Duration::from_millis(1));
    }
    match process.try_finish() {
        InstalledProcessFinish::Finished(finished) => finished,
        InstalledProcessFinish::Pending(_same_process) => {
            panic!("Finished progress must transfer actual status and reader joins")
        }
    }
}
impl InstalledClientAdapter for EffectProbe {
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
        assert_eq!(
            run.actions().len(),
            12,
            "genuine existing source-issued action view"
        );
        let projection: std::sync::Arc<dyn InvocationGateSource> = self.owner.clone();
        let _token = run
            .issue_host_observation(std::sync::Arc::downgrade(&projection))
            .unwrap();
        let prior = if matches!(self.effect, Effect::PriorFault) {
            let error = *run
                .prepare_snapshot_read(16 * 1024 * 1024 + 1)
                .err()
                .expect("authored finite snapshot permission must refuse");
            Some((error, run.installed_observation_usage()))
        } else {
            None
        };
        let arguments = [
            OsString::from("--adapter"),
            OsString::from("installed-process-effect-marker"),
            self.marker.as_os_str().to_owned(),
        ];
        let limits = Limits {
            max_frame: 64,
            stderr_capture: 32,
            ..Limits::DEFAULT
        };
        let result = run.spawn_process(
            InstalledProcessPurpose::Canonical {
                action_index: 2,
                command: InstalledCommand::Connect,
            },
            &self.program,
            arguments.iter().map(|arg| arg.as_os_str()),
            &self.directory,
            &[],
            limits,
        );
        match self.effect {
            Effect::Finish => {
                let process = match result {
                    Ok(process) => process,
                    Err(error) => {
                        panic!("positive calibration must launch actual same peer: {error:?}")
                    }
                };
                let finished = actual_finish(process);
                assert_eq!(finished.outcome().status().code(), Some(0));
                assert_eq!(finished.outcome().stdout(), b"entered\n");
                assert_eq!(finished.outcome().stderr(), b"");
                assert!(!finished.outcome().stderr_truncated());
                assert_eq!(finished.outcome().first_fault(), None);
                assert_eq!(std::fs::read(&self.marker).unwrap(), ENTRY);
                // try_finish required actual direct-child wait and actual reader
                // thread joins. This is not universal descendant quiescence.
                drop(finished);
            }
            Effect::Refuse(_) | Effect::PriorFault => {
                // If implementation launches anyway, finish the actual owner
                // before failing, rather than orphaning an unexpected child.
                let refused = match result {
                    Err(error) => {
                        assert_eq!(error, InstalledAdapterError::ObservationIncomplete);
                        true
                    }
                    Ok(process) => {
                        drop(actual_finish(process));
                        false
                    }
                };
                assert!(
                    refused,
                    "requested process permission must refuse synchronously"
                );
                assert!(
                    !self.marker.exists(),
                    "same actual peer entry marker must remain absent"
                );
                let fault = match run.receiving.ready() {
                    Err(fault) => *fault,
                    Ok(_) => panic!("real receiving owner keeps first failure"),
                };
                let expected = match self.effect {
                    Effect::Refuse(kind) => kind,
                    Effect::PriorFault => InstalledObservationResource::SnapshotReadBytes,
                    Effect::Finish => unreachable!(),
                };
                assert!(
                    matches!(fault, InstalledObservationError::Resource {kind,..} if kind==expected),
                    "{fault:?}"
                );
                let usage = run.installed_observation_usage();
                if let Some((original, before)) = prior {
                    assert_eq!(fault, original);
                    assert_eq!(usage, before)
                }
                let retry = run.spawn_process(
                    InstalledProcessPurpose::Canonical {
                        action_index: 2,
                        command: InstalledCommand::Connect,
                    },
                    &self.program,
                    arguments.iter().map(|arg| arg.as_os_str()),
                    &self.directory,
                    &[],
                    limits,
                );
                let refused = match retry {
                    Err(_) => true,
                    Ok(process) => {
                        drop(actual_finish(process));
                        false
                    }
                };
                assert!(refused, "same latched owner must refuse retry");
                assert_eq!(run.installed_observation_usage(), usage);
                assert_eq!(run.receiving.ready().err(), Some(&fault));
                assert!(!self.marker.exists());
            }
        }
        // No successful DATA constructor or factual association is invented.
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
fn effect_configuration(stdout: u64, stderr: u64, records: u64) -> RunConfiguration {
    RunConfiguration::from_json(&serde_json::json!({
        "kind":"model-originals-installed-client",
        "checker":serde_json::from_str::<serde_json::Value>(CHECKER).unwrap(),
        "observation":{"source":{"attempts":8192,"readCalls":8192,"returnedBytes":67108864,"files":16},"workers":{"attempts":64,"updates":8192},"host":{"updates":8192}},
        "privateRecord":{"retainedBytes":67108864},
        "installedObservation":{"rpcFrames":"checker-capture","retainedBytes":16777216,"stdoutPrefixBytes":stdout,"stderrPrefixBytes":stderr,"snapshotReadBytes":16777216,"byteVisits":67108864,"records":records}
    }).to_string()).unwrap()
}
fn exercise_effect(kit: &Path, marker: &Path, config: &RunConfiguration, effect: Effect) {
    let program = PathBuf::from(
        std::env::var_os("MORPHIR_MCK_REPORT_PEER_BIN")
            .expect("explicit fresh actual MEP harness executable required"),
    );
    assert!(
        program.is_absolute(),
        "actual peer executable must be absolute"
    );
    let program = program.canonicalize().unwrap();
    let mut probe = EffectProbe {
        owner: std::sync::Arc::new(TestGateOwner {
            gate: InvocationGate::dormant(),
        }),
        program,
        marker: marker.to_owned(),
        directory: kit.to_owned(),
        effect,
        entered: false,
    };
    let report = run_configured_with_installed_client_adapter(kit, config, &mut probe).unwrap();
    assert!(
        probe.entered,
        "complete24 source gate must issue actual callback"
    );
    assert!(!report.qualified());
}
fn calibrated_refusal(config: RunConfiguration, effect: Effect) {
    let kit = tempfile::tempdir().unwrap();
    let kit = kit.path().canonicalize().unwrap();
    std::fs::write(kit.join("cases.json"), CASES).unwrap();
    let marker = kit.join("actual-entry.marker");
    exercise_effect(
        &kit,
        &marker,
        &effect_configuration(64, 32, 8192),
        Effect::Finish,
    );
    assert_eq!(std::fs::read(&marker).unwrap(), ENTRY);
    std::fs::remove_file(&marker).unwrap();
    exercise_effect(&kit, &marker, &config, effect);
    assert!(!marker.exists());
}
#[test]
fn e01_actual_peer_entry_finishes_and_joins_through_same_source_issued_run() {
    let kit = tempfile::tempdir().unwrap();
    let kit = kit.path().canonicalize().unwrap();
    std::fs::write(kit.join("cases.json"), CASES).unwrap();
    exercise_effect(
        &kit,
        &kit.join("actual-entry.marker"),
        &effect_configuration(64, 32, 8192),
        Effect::Finish,
    );
}
#[test]
fn e02_zero_stdout_or_stderr_prefix_refuses_same_calibrated_peer_entry() {
    for (stdout, stderr, resource) in [
        (0, 32, InstalledObservationResource::StdoutPrefixBytes),
        (64, 0, InstalledObservationResource::StderrPrefixBytes),
    ] {
        calibrated_refusal(
            effect_configuration(stdout, stderr, 8192),
            Effect::Refuse(resource),
        )
    }
}
#[test]
fn e03_process_record_refusal_precedes_same_calibrated_peer_entry() {
    // Genuine Invocation+Mailbox already spend two records. No third Process
    // record exists, while positive calibration keeps identical executable/argv.
    calibrated_refusal(
        effect_configuration(64, 32, 2),
        Effect::Refuse(InstalledObservationResource::Records),
    );
}
#[test]
fn e04_prior_real_receiving_fault_prevents_same_calibrated_peer_entry_and_retry() {
    calibrated_refusal(effect_configuration(64, 32, 8192), Effect::PriorFault);
}
