//! Additive actual engine callback-error controls. No successful host is faked.
use super::model_originals::native::{
    NativeAdapterError, NativeOriginalAdapter, NativeOriginalMeasurements, NativeOriginalNode,
    NativeOriginalRun,
};
use super::{RunConfiguration, run_configured_with_native_adapter};
const POLICY: &str = include_str!("native_pipeline_controls/native-policy.json");
const CASES: &[u8] = include_bytes!("native_pipeline_controls/cases24.json");
struct Refuse {
    error: NativeAdapterError,
    calls: usize,
}
impl NativeOriginalAdapter for Refuse {
    fn observe(
        &mut self,
        _run: NativeOriginalRun<'_>,
    ) -> Result<NativeOriginalMeasurements, NativeAdapterError> {
        self.calls += 1;
        Err(self.error)
    }
}
#[test]
fn every_genuine_native_adapter_fault_retains_its_closed_category_until_report_encoding() {
    for (error, phase, code) in [
        (
            NativeAdapterError::Startup,
            "native-startup",
            "native-startup-refused",
        ),
        (
            NativeAdapterError::Fixture,
            "native-fixture",
            "native-fixture-refused",
        ),
        (
            NativeAdapterError::Authentication,
            "native-authentication",
            "native-authentication-refused",
        ),
        (
            NativeAdapterError::Discovery,
            "native-discovery",
            "native-discovery-refused",
        ),
        (
            NativeAdapterError::Selection,
            "native-selection",
            "native-selection-refused",
        ),
        (
            NativeAdapterError::Exchange,
            "native-exchange",
            "native-exchange-refused",
        ),
        (
            NativeAdapterError::ObservationIncomplete,
            "native-observation",
            "native-observation-incomplete",
        ),
        (
            NativeAdapterError::Cleanup,
            "native-cleanup",
            "native-cleanup-refused",
        ),
        (
            NativeAdapterError::Cancelled,
            "native-cancelled",
            "native-cancelled",
        ),
        (
            NativeAdapterError::UnsupportedAction,
            "native-action",
            "native-action-unsupported",
        ),
    ] {
        let root = tempfile::tempdir().unwrap();
        std::fs::write(root.path().join("cases.json"), CASES).unwrap();
        let policy = RunConfiguration::from_json(POLICY).unwrap();
        let mut adapter = Refuse { error, calls: 0 };
        let report =
            run_configured_with_native_adapter(root.path(), &policy, &mut adapter).unwrap();
        assert_eq!(adapter.calls, 1);
        assert!(!report.qualified());
        let data: serde_json::Value = serde_json::from_str(&report.to_json()).unwrap();
        assert_eq!(data["errors"].as_array().unwrap().len(), 1);
        assert_eq!(data["errors"][0]["phase"], phase);
        assert_eq!(data["errors"][0]["code"], code);
        assert_eq!(data["records"][0]["evidence"]["kind"], "attempt-failed");
        for row in &data["records"].as_array().unwrap()[1..] {
            assert_eq!(row["evidence"]["kind"], "not-attempted");
        }
    }
}
struct RefuseAfterRecipe {
    calls: usize,
}
impl NativeOriginalAdapter for RefuseAfterRecipe {
    fn observe(
        &mut self,
        mut run: NativeOriginalRun<'_>,
    ) -> Result<NativeOriginalMeasurements, NativeAdapterError> {
        self.calls += 1;
        let fixture = run.fixture();
        let grant = fixture.grants().next().unwrap();
        let NativeOriginalNode::File { bytes, .. } = grant.nodes().next().unwrap() else {
            panic!("original first config file")
        };
        assert!(matches!(
            run.materialize_fixture_bytes(bytes),
            Err(NativeAdapterError::Fixture)
        ));
        assert!(matches!(
            run.materialize_fixture_bytes(bytes),
            Err(NativeAdapterError::Fixture)
        ));
        Err(NativeAdapterError::Startup)
    }
}
#[test]
fn actual_same_owner_recipe_fault_precedes_later_adapter_error_without_owner_reset() {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(root.path().join("cases.json"), CASES).unwrap();
    let raw = POLICY.replacen("\"comparisonBytes\":1000000", "\"comparisonBytes\":1", 1);
    assert_ne!(raw, POLICY);
    let policy = RunConfiguration::from_json(&raw).unwrap();
    let mut adapter = RefuseAfterRecipe { calls: 0 };
    let report = run_configured_with_native_adapter(root.path(), &policy, &mut adapter).unwrap();
    assert_eq!(adapter.calls, 1);
    let data: serde_json::Value = serde_json::from_str(&report.to_json()).unwrap();
    assert_eq!(data["errors"][0]["phase"], "observation");
    assert_eq!(data["errors"][0]["code"], "observation-refused");
    assert!(!report.qualified());
}
