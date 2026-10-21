//! DATA-only source-first preflight controls. No process/source/business proof.
//! Proposed child of projection_resource_tests, not mounted.
use super::*;
#[derive(Clone, Copy)]
enum InputCase {
    Literal,
    Metadata,
    Prefix,
    Structure,
}
struct InputProbe {
    case: InputCase,
    entered: bool,
    owner: std::sync::Arc<TestGateOwner>,
}
impl InstalledClientAdapter for InputProbe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        self.entered = true;
        activate(
            &mut run,
            &self.owner,
            Instant::now() + Duration::from_secs(10),
        );
        // Explicit synthetic DATA setup, never finish_measurements or source
        // evidence. Real bytes exceed active output cap before encoding starts.
        let ascii = "a".repeat(4096);
        let data = match self.case {
            InputCase::Literal => serde_json::json!({"record":{"literal":ascii}}),
            InputCase::Metadata => serde_json::json!({"metadata":{"program":ascii}}),
            InputCase::Prefix => serde_json::json!({"stdout":{"kind":"utf8","value":ascii}}),
            InputCase::Structure => {
                serde_json::Value::Array((0..1024).map(|_| serde_json::json!([])).collect())
            }
        };
        let ticket = run
            .test_prepare_consumer_output(Limits {
                max_frame: 64,
                stderr_capture: 64,
                ..Limits::DEFAULT
            })
            .unwrap();
        // Both are cfgtest LOWER bounds from SAME preissued R/work permission.
        // Neither can extend storage or future work. Production uses its R.
        let output_limit = 64;
        let steps = 64;
        assert!(output_limit < ticket.test_report_limit());
        let receiving = run.installed_observation_usage();
        let decode = run.decode.usage();
        let mut rejected = run
            .test_encode_consumer_data_with_preflight(ticket, &data, output_limit, steps)
            .expect_err("oversized strings/structural work refuse before pinned serde passes");
        assert_eq!(
            rejected.test_serializer_passes(),
            0,
            "preflight must run before count and write"
        );
        match self.case {
            InputCase::Structure => {
                assert!(rejected.test_is_preflight_work_refusal());
                assert_eq!(rejected.test_preflight_string_bytes(), 0);
                assert_eq!(rejected.test_preflight_steps(), steps);
            }
            _ => {
                assert!(rejected.test_is_preflight_string_refusal());
                assert!(rejected.test_preflight_string_bytes() < output_limit);
                assert!(rejected.test_preflight_steps() < steps);
            }
        }
        assert_eq!(rejected.test_retained_data(), &data);
        assert!(rejected.test_retry(&mut run).is_err());
        drop(rejected);
        assert_eq!(run.installed_observation_usage(), receiving);
        assert_eq!(run.decode.usage(), decode);
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
fn input(case: InputCase) {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(root.path().join("cases.json"), CASES).unwrap();
    let mut policy: serde_json::Value = serde_json::from_str(V3).unwrap();
    policy["consumerObservation"] =
        serde_json::json!({"mode":"operation-port","version":"0.1.0-draft.1"});
    let mut probe = InputProbe {
        case,
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
#[test]
fn long_unescaped_literal_metadata_and_prefix_refuse_before_serde_scan() {
    for case in [InputCase::Literal, InputCase::Metadata, InputCase::Prefix] {
        input(case);
    }
}
#[test]
fn high_structure_zero_string_data_refuses_at_preissued_step_bound() {
    input(InputCase::Structure);
}
