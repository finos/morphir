//! Additive source-authored negotiation consistency controls, not authority.
use crate::workbench::{Report, RunConfiguration, check_report_configured};
fn reject(raw: &str) {
    let temp = tempfile::tempdir().unwrap();
    std::fs::write(
        temp.path().join("cases.json"),
        include_bytes!("pipeline_controls/cases.json"),
    )
    .unwrap();
    let configuration =
        RunConfiguration::from_json(include_str!("pipeline_controls/explicit-test-policy.json"))
            .unwrap();
    let result = Report::from_json(raw)
        .and_then(|report| check_report_configured(temp.path(), &report, &configuration));
    assert!(result.is_err(), "negotiation evidence was forged");
    assert!(
        result.unwrap_err().contains("negotiation"),
        "must fail at actual negotiation boundary"
    );
}
#[test]
fn saved_binding_and_language_are_bound_to_actual_capability_reply() {
    for raw in [
        include_str!("pipeline_negotiation_controls/forged-summary-binding.json"),
        include_str!("pipeline_negotiation_controls/forged-summary-language.json"),
    ] {
        reject(raw);
    }
}
#[test]
fn negotiation_reply_cannot_reuse_the_first_case_id() {
    reject(include_str!(
        "pipeline_negotiation_controls/negotiation-reply-id-two.json"
    ));
}
