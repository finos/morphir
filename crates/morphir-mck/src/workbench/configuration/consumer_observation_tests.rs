//! Explicit caller selection only. No port, process or operation fact is issued.
use super::*;

const INSTALLED: &str = include_str!("../installed_borrowed_controls/installed-policy.json");

fn selected(mode: &str, version: &str) -> serde_json::Value {
    let mut policy: serde_json::Value = serde_json::from_str(INSTALLED).unwrap();
    policy["consumerObservation"] = serde_json::json!({
        "mode": mode,
        "version": version,
    });
    policy
}

#[test]
fn consumer_observation_policy_absence_preserves_legacy_installed_selection() {
    let configuration = RunConfiguration::from_json(INSTALLED).unwrap();
    assert_eq!(
        configuration.execution_mode(),
        WorkbenchExecutionMode::InstalledOriginals
    );
}

#[test]
fn consumer_observation_policy_accepts_only_explicit_operation_port_revision() {
    let raw = selected("operation-port", "0.1.0-draft.1").to_string();
    let configuration = RunConfiguration::from_json(&raw)
        .expect("explicit reviewed operation-port revision must be parsed before any effect");
    assert_eq!(
        configuration.execution_mode(),
        WorkbenchExecutionMode::InstalledOriginals
    );
}

#[test]
fn consumer_observation_policy_refuses_foreign_modes_and_versions() {
    for (mode, version) in [
        ("enabled", "0.1.0-draft.1"),
        ("disabled", "0.1.0-draft.1"),
        ("operation-port", "0.1.0"),
        ("operation-port", "0.1.0-draft.2"),
        ("operation-port", "v0.1.0-draft.1"),
        ("operation-port", "00.1.0-draft.1"),
    ] {
        assert!(RunConfiguration::from_json(&selected(mode, version).to_string()).is_err());
    }
}

#[test]
fn consumer_observation_policy_refuses_unknown_duplicate_or_missing_members() {
    let mut extra = selected("operation-port", "0.1.0-draft.1");
    extra["consumerObservation"]["endpoint"] = "not-an-authority".into();
    assert!(RunConfiguration::from_json(&extra.to_string()).is_err());
    let mut missing = selected("operation-port", "0.1.0-draft.1");
    missing["consumerObservation"] = serde_json::json!({"version":"0.1.0-draft.1"});
    assert!(RunConfiguration::from_json(&missing.to_string()).is_err());
    let raw = selected("operation-port", "0.1.0-draft.1").to_string();
    let duplicate = raw.replacen(
        "\"mode\":\"operation-port\"",
        "\"mode\":\"operation-port\",\"mode\":\"operation-port\"",
        1,
    );
    assert_ne!(duplicate, raw);
    assert!(RunConfiguration::from_json(&duplicate).is_err());
}

#[test]
fn consumer_observation_policy_cannot_select_a_different_checker_kind() {
    for seed in [
        "{\"kind\":\"historical\"}",
        include_str!("../native_pipeline_controls/native-policy.json"),
        include_str!(
            "../model_originals/workflow/pipeline/installed/adapter/lifetime_tests/fixtures/checker-policy.json"
        ),
    ] {
        assert!(RunConfiguration::from_json(seed).is_ok());
        let mut raw: serde_json::Value = serde_json::from_str(seed).unwrap();
        raw["consumerObservation"] =
            selected("operation-port", "0.1.0-draft.1")["consumerObservation"].clone();
        assert!(RunConfiguration::from_json(&raw.to_string()).is_err());
    }
}
