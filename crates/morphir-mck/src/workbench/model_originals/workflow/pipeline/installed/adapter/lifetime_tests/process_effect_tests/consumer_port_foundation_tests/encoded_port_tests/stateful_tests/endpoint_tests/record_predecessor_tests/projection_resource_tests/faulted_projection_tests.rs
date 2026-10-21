//! Genuine raw faulted Finished, actual prefix move and terminal projection.
//! This is a real test peer with zero business facts, not consumer52 evidence.
use super::*;
use std::os::unix::process::ExitStatusExt as _;

struct FaultedProbe {
    entered: bool,
    owner: std::sync::Arc<TestGateOwner>,
}
impl InstalledClientAdapter for FaultedProbe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        self.entered = true;
        let end = Instant::now() + Duration::from_secs(10);
        activate(&mut run, &self.owner, end);
        let root = tempfile::tempdir().unwrap();
        let marker = root.path().join("actual-projection-entry");
        let program = PathBuf::from(
            std::env::var_os("MORPHIR_MCK_REPORT_PEER_BIN")
                .expect("exact existing actual MEP peer required"),
        );
        let args = [
            OsString::from("--adapter"),
            OsString::from("installed-process-effect-marker"),
            marker.as_os_str().to_owned(),
        ];
        let purpose = InstalledProcessPurpose::Canonical {
            action_index: 8,
            command: InstalledCommand::Publish,
        };
        let (prepared, ports) = run
            .prepare_consumer_process(
                ConsumerProcessCommand {
                    purpose,
                    program: &program,
                    arguments: &args,
                    directory: root.path(),
                    environment: &[],
                    limits: Limits {
                        max_frame: 1,
                        stderr_capture: 64,
                        ..Limits::DEFAULT
                    },
                },
                end,
            )
            .unwrap();
        let ordinal = prepared.test_process_ordinal();
        let process = run.spawn_prepared_consumer_process(prepared).unwrap();
        let mut late = false;
        let finished = super::super::finish_raw(process, end, &mut late);
        let actual_status = finished.outcome().status();
        let actual_truncated = finished.outcome().stderr_truncated();
        let actual_descendants = finished.outcome().descendants();
        let pointer = finished.outcome().stdout().as_ptr();
        let actual_bytes = finished.outcome().stdout().to_vec(); // test snapshot only
        let capacities = finished.outcome().test_prefix_capacities(); // readonly actual Vec capacities
        let fault = finished.outcome().first_fault().copied();
        // Same-owner legacy DATA view prepared while Attempt is still healthy,
        // only to compare existing wire/Debug behavior. It issues no authority.
        let legacy = run.observation_literal_bytes(
            crate::workbench::model_originals::workflow::pipeline::installed::observation::ObservationBufferRole::StdoutPrefix,
            finished.outcome().stdout(),
        ).unwrap();
        let legacy_wire = serde_json::to_value(&legacy).unwrap();
        let legacy_debug = format!("{legacy:?}");
        let receiving = run.installed_observation_usage();
        let decoder = run.decode.usage();
        let result = run.record_consumer_process(ports, finished);
        let refused = match result {
            Ok(()) => false,
            Err(rejected) => {
                let (mut ports, finished) = rejected.into_parts();
                ports.revoke();
                drop(finished);
                drop(ports);
                true
            }
        };
        let projected = if !refused {
            run.test_project_consumer_record().is_ok()
        } else {
            false
        };
        // The child and actual readers are genuinely Finished before assertions.
        // Any rejected ownerpair has been explicitly closed/dropped above.
        assert!(!late);
        assert_eq!(
            std::fs::read(marker).unwrap(),
            b"installed-process-effect-entry-v1\n"
        );
        assert_eq!(
            fault,
            Some(crate::transport::process::ProcessFault::StdoutLimit)
        );
        assert!(!refused && projected);
        assert_eq!(run.installed_observation_usage(), receiving);
        assert_eq!(run.decode.usage(), decoder);
        assert!(matches!(run.attempt.ready(), Err(crate::workbench::model_originals::workflow::pipeline::RunFault::InstalledProcessFault(crate::transport::process::ProcessFault::StdoutLimit))));
        let (data, outcome) = run
            .test_consumer_projected_process()
            .expect("borrowed projection plus SAME retained outcome");
        assert_eq!(data.process_ordinal.0, ordinal);
        assert_eq!(data.stdout.as_bytes(), actual_bytes);
        assert_eq!(serde_json::to_value(&data.stdout).unwrap(), legacy_wire);
        assert_eq!(format!("{:?}", data.stdout), legacy_debug);
        assert_eq!(
            data.stdout.as_bytes().as_ptr(),
            pointer,
            "move actual prefix storage, no hidden duplicate cache"
        );
        assert_eq!(data.stdout.test_raw_capacity(), capacities[0]);
        assert_eq!(data.stderr.test_raw_capacity(), capacities[1]);
        assert_eq!(outcome.status(), actual_status);
        assert_eq!(outcome.first_fault().copied(), fault);
        assert_eq!(outcome.stderr_truncated(), actual_truncated);
        assert_eq!(outcome.descendants(), actual_descendants);
        assert_eq!(data.stderr_truncated.observed(), actual_truncated);
        let completion = serde_json::to_value(&data.completion).unwrap();
        let expected = match (actual_status.code(), actual_status.signal()) {
            (Some(code), _) => {
                serde_json::json!({"kind":"finished","exit":{"kind":"code","value":code}})
            }
            (_, Some(signal)) => {
                serde_json::json!({"kind":"finished","exit":{"kind":"signal","value":signal}})
            }
            _ => serde_json::json!({"kind":"finished","exit":{"kind":"other"}}),
        };
        assert_eq!(
            completion, expected,
            "retain actual supported exit, never synthetic0/124/127"
        );
        assert_eq!(
            run.test_consumer_record().unwrap().completion(),
            ConsumerRecordCompletion::Interrupted
        );
        let cache_lengths = [
            ConsumerProducerRole::Outer,
            ConsumerProducerRole::TransferHelper,
        ]
        .map(|role| run.test_consumer_record().unwrap().frames(role).len());
        let rejected = run
            .test_reject_consumer_encoding_at(1)
            .expect_err("actual owned record cannot encode within one byte");
        let (same_data, same_outcome) = rejected.test_projected_process();
        let preserved = same_data.stdout.as_bytes() == actual_bytes
            && same_data.stdout.as_bytes().as_ptr() == pointer
            && same_data.stdout.test_raw_capacity() == capacities[0]
            && same_data.stderr.test_raw_capacity() == capacities[1]
            && same_outcome.status() == actual_status
            && same_outcome.first_fault().copied() == fault
            && same_outcome.stderr_truncated() == actual_truncated
            && same_outcome.descendants() == actual_descendants;
        let same_caches = [
            ConsumerProducerRole::Outer,
            ConsumerProducerRole::TransferHelper,
        ]
        .map(|role| rejected.test_record().frames(role).len())
            == cache_lengths;
        let limit = rejected.test_is_limit_refusal();
        drop(rejected); // explicit resolved owner disposal, no smaller report
        assert!(limit && preserved && same_caches);
        assert_eq!(run.installed_observation_usage(), receiving);
        assert_eq!(run.decode.usage(), decoder);
        assert!(matches!(run.attempt.ready(), Err(crate::workbench::model_originals::workflow::pipeline::RunFault::InstalledProcessFault(crate::transport::process::ProcessFault::StdoutLimit))));
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
#[test]
fn genuine_faulted_finished_projection_moves_actual_prefix_without_new_credit() {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(root.path().join("cases.json"), CASES).unwrap();
    let mut policy: serde_json::Value = serde_json::from_str(V3).unwrap();
    policy["consumerObservation"] =
        serde_json::json!({"mode":"operation-port","version":"0.1.0-draft.1"});
    let mut probe = FaultedProbe {
        entered: false,
        owner: std::sync::Arc::new(TestGateOwner {
            gate: InvocationGate::dormant(),
        }),
    };
    let report = run_configured_with_installed_client_adapter(
        root.path(),
        &RunConfiguration::from_json(&policy.to_string()).unwrap(),
        &mut probe,
    )
    .unwrap();
    assert!(probe.entered);
    assert!(!report.qualified());
}
