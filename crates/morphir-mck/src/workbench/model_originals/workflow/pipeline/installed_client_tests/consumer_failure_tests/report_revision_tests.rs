//! Historical actual failure DATA, never successful consumer or live authority.
//! Proposed child of existing installed_client_tests::consumer_failure_tests.
use super::*;
use crate::workbench::model_originals::workflow::pipeline::installed::adapter::{
    InstalledAdapterError, InstalledClientAdapter, InstalledClientMeasurements, InstalledClientRun,
};

#[test]
fn historical_draft30_failure_and_corpus_remain_exactly_supported() {
    let (report, configuration) = input();
    assert_eq!(report["formatVersion"], json!("0.1.0-draft.30"));
    replay(&report, &configuration).expect("exact old failure DATA remains readable");
    assert_eq!(digest(REPORT), REPORT_SHA);
    assert_eq!(
        digest(CORPUS.as_bytes()),
        "26559149b6a1e67e13a4e59422ebf5e22f399799f3f28eba0b20c7002919e26e"
    );
}

#[test]
fn report_only_draft31_accepts_existing_actual_failure_in_explicit_mode_without_measurements() {
    let (mut report, configuration) = input();
    report["formatVersion"] = json!("0.1.0-draft.31");
    replay(&report, &configuration)
        .expect("new report dispatch preserves exact actual failure, not business success");
    assert_eq!(report["qualified"], false);
    let rows = report["records"].as_array().unwrap();
    assert_eq!(rows.len(), 24);
    for (index, row) in rows.iter().enumerate() {
        assert_eq!(
            row["evidence"],
            if index == 0 {
                json!({"kind":"attempt-failed","failureIndex":0})
            } else {
                json!({"kind":"not-attempted","priorFailureIndex":0})
            }
        );
    }
}

#[test]
fn report31_requires_explicit_same_mode_and_exact_supported_revision() {
    let (mut report, mut configuration) = input();
    report["formatVersion"] = json!("0.1.0-draft.31");
    replay(&report, &configuration)
        .expect("exact31 positive prerequisite before one-field refusals");
    for revision in ["0.1.0-draft.32", "v0.1.0-draft.31", "0.1.0-draft.31+future"] {
        let mut altered = report.clone();
        altered["formatVersion"] = json!(revision);
        assert!(
            replay(&altered, &configuration).is_err(),
            "unsupported revision {revision}"
        );
    }
    configuration
        .as_object_mut()
        .unwrap()
        .remove("consumerObservation");
    assert_eq!(
        replay(&report, &configuration).unwrap_err(),
        "consumer report revision requires explicit operation selection"
    );
}

#[test]
fn decoded_record_shaped_data_cannot_replace_live_process_or_failure_prefix() {
    let (original, configuration) = input();
    replay(&original, &configuration).unwrap();
    for revision in ["0.1.0-draft.30", "0.1.0-draft.31"] {
        let mut altered = original.clone();
        altered["formatVersion"] = json!(revision);
        altered["records"][0]["evidence"]["consumerObservation"] = json!({
            "kind":"recorded", "version":"0.1.0-draft.1", "processOrdinal":0,
            "completion":"drained", "endpoints":[]
        });
        assert!(
            replay(&altered, &configuration).is_err(),
            "record-shaped DATA cannot add a measurement to actual attempt-failed {revision}"
        );
    }
}

#[test]
fn report31_support_does_not_accept_corpus31_or_enter_its_adapter_callback() {
    struct CountCalls(usize);
    impl InstalledClientAdapter for CountCalls {
        fn observe(
            &mut self,
            _run: InstalledClientRun<'_>,
        ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
            self.0 += 1;
            Err(InstalledAdapterError::ObservationIncomplete)
        }
    }
    let (_, configuration) = input();
    let configuration = RunConfiguration::from_json(&configuration.to_string()).unwrap();
    let root = tempfile::tempdir().unwrap();
    std::fs::write(root.path().join("cases.json"), CORPUS).unwrap();
    let mut allowed = CountCalls(0);
    let original = crate::workbench::run_configured_with_installed_client_adapter(
        root.path(),
        &configuration,
        &mut allowed,
    )
    .unwrap();
    assert_eq!(
        allowed.0, 1,
        "genuine unchanged30 full24 must reach the actual adapter"
    );
    assert!(!original.qualified());
    let mut altered: Value = serde_json::from_str(CORPUS).unwrap();
    assert_eq!(altered["formatVersion"], json!("0.1.0-draft.30"));
    altered["formatVersion"] = json!("0.1.0-draft.31");
    std::fs::write(root.path().join("cases.json"), altered.to_string()).unwrap();
    let mut refused = CountCalls(0);
    let result = crate::workbench::run_configured_with_installed_client_adapter(
        root.path(),
        &configuration,
        &mut refused,
    );
    assert!(
        result.is_err(),
        "report-only31 must not widen shared corpus/operation/negotiation version rules"
    );
    assert_eq!(
        refused.0, 0,
        "unsupported corpus must refuse before the adapter/effects"
    );
}
