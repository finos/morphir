//! Bounded DATA writer controls under a genuine prefunded Run.
//! Historical actual failure DATA only, not a successful measurement or owner.
use super::*;
use crate::workbench::model_originals::workflow::pipeline::installed::adapter::processes::consumer::projection::ConsumerEncodingFault;
const ACTUAL_FAILURE: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/src/workbench/model_originals/workflow/pipeline/installed_client_tests/consumer_failure_controls/operation-report.json"
));
#[derive(Clone, Copy)]
enum Bound {
    Exact,
    OneShort,
    OneAbove,
}
struct EncodingProbe {
    which: Bound,
    entered: bool,
    owner: std::sync::Arc<TestGateOwner>,
}
impl InstalledClientAdapter for EncodingProbe {
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
        let raw: Box<serde_json::value::RawValue> = serde_json::from_str(ACTUAL_FAILURE).unwrap();
        let k = raw.get().len().checked_add(1).unwrap(); // same newline rule
        let ticket = run
            .test_prepare_consumer_output(Limits {
                max_frame: 64,
                stderr_capture: 64,
                ..Limits::DEFAULT
            })
            .unwrap();
        let capacity = ticket.test_capacity();
        assert!(k + 1 < ticket.test_report_limit());
        let bound = match self.which {
            Bound::Exact => k,
            Bound::OneShort => k - 1,
            Bound::OneAbove => k + 1,
        };
        let receiving = run.installed_observation_usage();
        let decoder = run.decode.usage();
        // This cfgtest lower bound cannot extend the preissued R. Production
        // accepts only its closed RuntimeReport, never this DATA test input.
        let result = run.test_encode_retained_report_data(ticket, &raw, bound);
        match self.which {
            Bound::Exact | Bound::OneAbove => {
                let encoded = result.expect("exact/below existing bound succeeds without growth");
                assert_eq!(encoded.test_capacity(), capacity);
                assert_eq!(encoded.test_bytes().len(), k);
                assert_eq!(&encoded.test_bytes()[..k - 1], raw.get().as_bytes());
                assert_eq!(encoded.test_bytes()[k - 1], b'\n');
                drop(encoded);
            }
            Bound::OneShort => {
                let mut rejected =
                    result.expect_err("one byte short refuses, no truncated/smaller success");
                assert_eq!(rejected.test_capacity(), capacity);
                assert_eq!(rejected.test_retained_data(), raw.get().as_bytes());
                assert!(rejected.test_is_limit_refusal());
                assert_eq!(
                    rejected.test_retry(&mut run),
                    Err(ConsumerEncodingFault::PriorFault)
                );
                drop(rejected);
            }
        }
        assert_eq!(run.installed_observation_usage(), receiving);
        assert_eq!(run.decode.usage(), decoder);
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
fn encoding(which: Bound) {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(root.path().join("cases.json"), CASES).unwrap();
    let mut policy: serde_json::Value = serde_json::from_str(V3).unwrap();
    policy["consumerObservation"] =
        serde_json::json!({"mode":"operation-port","version":"0.1.0-draft.1"});
    let mut probe = EncodingProbe {
        which,
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
fn actual_failure_data_encodes_at_exact_preissued_writer_bound() {
    encoding(Bound::Exact);
}
#[test]
fn actual_failure_data_refuses_one_byte_short_without_growth_or_credit_revival() {
    encoding(Bound::OneShort);
}
#[test]
fn actual_failure_data_encodes_with_one_byte_spare_under_same_cap() {
    encoding(Bound::OneAbove);
}
