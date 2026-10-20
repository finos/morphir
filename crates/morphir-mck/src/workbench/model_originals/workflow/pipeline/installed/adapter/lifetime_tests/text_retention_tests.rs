//! Genuine compiled callback and existing owner. Retained text is DATA only.
use super::*;
use crate::workbench::model_originals::installed::RetainedObservationText;
const RAW: &str = "a€🦀";
struct TextProbe {
    owner: std::sync::Arc<TestGateOwner>,
    retained: Option<RetainedObservationText>,
}
impl InstalledClientAdapter for TextProbe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        let source: std::sync::Arc<dyn InvocationGateSource> = self.owner.clone();
        let projection = std::sync::Arc::downgrade(&source);
        let _token = run.issue_host_observation(projection.clone()).unwrap();
        let text: RetainedObservationText = run
            .retain_host_text(&projection, ObservationBufferRole::RpcRequest, RAW)
            .unwrap();
        assert_eq!(text.as_str(), RAW);
        assert_eq!(
            run.installed_observation_usage().byte_visits(),
            RAW.len() as u64
        );
        let first = text.as_str().as_ptr();
        assert_eq!(text.as_str().as_ptr(), first);
        assert_eq!(
            run.installed_observation_usage().byte_visits(),
            RAW.len() as u64
        );
        self.retained = Some(text);
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
#[test]
fn genuine_run_retains_opaque_utf8_text_with_one_copy_budget_and_borrowed_getters() {
    let kit = tempfile::tempdir().unwrap();
    std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
    let mut probe = TextProbe {
        owner: std::sync::Arc::new(TestGateOwner {
            gate: InvocationGate::dormant(),
        }),
        retained: None,
    };
    let report =
        run_configured_with_installed_client_adapter(kit.path(), &configuration(), &mut probe)
            .unwrap();
    assert!(!report.qualified());
    assert_eq!(probe.retained.unwrap().as_str(), RAW);
}
