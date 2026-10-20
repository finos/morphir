//! Source-first shared engine/native callback controls. No host is simulated.
//! The unit adapter deliberately fails Startup and cannot return Ready data.
use super::model_originals::native::{
    NativeAdapterError, NativeOriginalAdapter, NativeOriginalMeasurements, NativeOriginalRun,
};
use super::{
    Operation, Report, RunConfiguration, check_report_configured,
    run_configured_with_native_adapter, run_configured_with_session_factory,
};
use crate::transport::TransportError;
use serde::Deserialize;
use std::cell::Cell;

const POLICY: &str = include_str!("native_pipeline_controls/native-policy.json");
const ZERO: &str = include_str!("native_pipeline_controls/zero-policy.json");
const CURRENT_POLICY: &str = include_str!("native_pipeline_controls/current-policy.json");
const CASES: &[u8] = include_bytes!("native_pipeline_controls/cases24.json");
const OLD23: &[u8] = include_bytes!("native_pipeline_controls/old23.json");
const ID: &str = "explicit-empty-companion-declaration-is-complete";

struct RefusingAdapter {
    calls: usize,
}
impl NativeOriginalAdapter for RefusingAdapter {
    fn observe(
        &mut self,
        run: NativeOriginalRun<'_>,
    ) -> Result<NativeOriginalMeasurements, NativeAdapterError> {
        self.calls += 1;
        // These are the actual callback's source-issued immutable views.
        // They are not supplied by this unit adapter or an observed report.
        let source = run.source();
        assert_eq!(source.case_id(), ID);
        assert_eq!(source.original_packet(), "wire49");
        assert_eq!(source.original_id(), ID);
        assert_eq!(source.run_index(), 0);
        assert_eq!(source.operation(), Operation::ModelOriginalsServer);
        assert_eq!(run.actions().len(), 10);
        assert_eq!(run.observation_limits().source_files(), 16);
        Err(NativeAdapterError::Startup)
    }
}
fn put_kit(bytes: &[u8]) -> tempfile::TempDir {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(root.path().join("cases.json"), bytes).unwrap();
    root
}
fn configured() -> RunConfiguration {
    RunConfiguration::from_json(POLICY).unwrap()
}

#[test]
fn native_configuration_requires_all_seven_explicit_bounds_and_accepts_zero_without_default() {
    let policy = configured();
    let limits = policy
        .native_observation_limits()
        .expect("closed native policy branch");
    assert_eq!(limits.source_attempts(), 8192);
    assert_eq!(limits.source_read_calls(), 8192);
    assert_eq!(limits.source_returned_bytes(), 67_108_864);
    assert_eq!(limits.source_files(), 16);
    assert_eq!(limits.worker_attempts(), 64);
    assert_eq!(limits.worker_updates(), 8192);
    assert_eq!(limits.host_updates(), 8192);
    let zero = RunConfiguration::from_json(ZERO).unwrap();
    let limits = zero.native_observation_limits().unwrap();
    assert_eq!(
        (
            limits.source_attempts(),
            limits.source_read_calls(),
            limits.source_returned_bytes(),
            limits.source_files(),
            limits.worker_attempts(),
            limits.worker_updates(),
            limits.host_updates()
        ),
        (0, 0, 0, 0, 0, 0, 0)
    );
    assert!(
        RunConfiguration::from_json(CURRENT_POLICY)
            .unwrap()
            .native_observation_limits()
            .is_none()
    );
    assert!(
        RunConfiguration::from_json(r#"{"kind":"historical"}"#)
            .unwrap()
            .native_observation_limits()
            .is_none()
    );
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct RefusedPolicy {
    id: String,
    raw: String,
    expected: String,
}
#[test]
fn native_configuration_refuses_missing_unknown_duplicate_noncanonical_and_overflow_bounds() {
    let cases: Vec<RefusedPolicy> = serde_json::from_str(include_str!(
        "native_pipeline_controls/refused-policies.json"
    ))
    .unwrap();
    assert_eq!(cases.len(), 17);
    for case in cases {
        assert_eq!(case.expected, "refuse-before-effects");
        assert!(
            RunConfiguration::from_json(&case.raw).is_err(),
            "{}",
            case.id
        );
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Snapshot {
    qualified: bool,
    records: Vec<Record>,
}
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Record {
    case_id: String,
    evidence: Evidence,
}
#[derive(Deserialize, Clone, Copy)]
#[serde(tag = "kind", rename_all = "kebab-case", deny_unknown_fields)]
enum Evidence {
    AttemptFailed {
        #[serde(rename = "failureIndex")]
        failure_index: usize,
    },
    NotAttempted {
        #[serde(rename = "priorFailureIndex")]
        prior_failure_index: usize,
    },
}
#[test]
fn exact_full24_preflight_lends_one_real_source_context_and_stops_after_actual_callback_fault() {
    let kit = put_kit(CASES);
    let mut adapter = RefusingAdapter { calls: 0 };
    let report =
        run_configured_with_native_adapter(kit.path(), &configured(), &mut adapter).unwrap();
    assert_eq!(adapter.calls, 1);
    assert!(
        !report.qualified(),
        "24 partial rows never satisfy175 roles or actual host proof"
    );
    let actual: Snapshot = serde_json::from_str(&report.to_json()).unwrap();
    assert!(!actual.qualified);
    assert_eq!(actual.records.len(), 24);
    let expected_ids: Vec<String> =
        serde_json::from_str(include_str!("native_pipeline_controls/ordered-ids.json")).unwrap();
    assert_eq!(
        actual
            .records
            .iter()
            .map(|row| row.case_id.as_str())
            .collect::<Vec<_>>(),
        expected_ids.iter().map(String::as_str).collect::<Vec<_>>()
    );
    assert_eq!(actual.records[0].case_id, ID);
    let Evidence::AttemptFailed { failure_index } = actual.records[0].evidence else {
        panic!("actual failed callback has no completed measurements")
    };
    assert_eq!(failure_index, 0);
    for row in &actual.records[1..] {
        let Evidence::NotAttempted {
            prior_failure_index,
        } = row.evidence
        else {
            panic!("later23 source rows must remain not attempted")
        };
        assert_eq!(prior_failure_index, failure_index);
    }
}

#[test]
fn full24_source_tamper_inventory_omission_order_and_duplicate_refuse_before_any_callback() {
    for bytes in [
        include_bytes!("native_pipeline_controls/tampered-source.json").as_slice(),
        include_bytes!("native_pipeline_controls/native-last.json").as_slice(),
        include_bytes!("native_pipeline_controls/duplicate-native.json").as_slice(),
        OLD23,
    ] {
        let kit = put_kit(bytes);
        let mut adapter = RefusingAdapter { calls: 0 };
        assert!(
            run_configured_with_native_adapter(kit.path(), &configured(), &mut adapter).is_err()
        );
        assert_eq!(
            adapter.calls, 0,
            "source binding/inventory is before callback"
        );
    }
}

#[test]
fn native_and_external_configuration_cannot_cross_or_fall_back_before_effects() {
    let kit = put_kit(CASES);
    let native = configured();
    let factory_calls = Cell::new(0);
    assert!(
        run_configured_with_session_factory(kit.path(), &native, || {
            factory_calls.set(factory_calls.get() + 1);
            Err(TransportError::Spawn(
                "unit forbidden external factory".into(),
            ))
        })
        .is_err()
    );
    assert_eq!(factory_calls.get(), 0);
    for raw in [CURRENT_POLICY, r#"{"kind":"historical"}"#] {
        let policy = RunConfiguration::from_json(raw).unwrap();
        let mut adapter = RefusingAdapter { calls: 0 };
        assert!(run_configured_with_native_adapter(kit.path(), &policy, &mut adapter).is_err());
        assert_eq!(adapter.calls, 0);
    }
    // The actual existing external entry still invokes its genuine callback
    // after all old23 source preparation. No process/host success is claimed.
    let old = put_kit(OLD23);
    let policy = RunConfiguration::from_json(CURRENT_POLICY).unwrap();
    assert!(
        run_configured_with_session_factory(old.path(), &policy, || {
            factory_calls.set(factory_calls.get() + 1);
            Err(TransportError::Spawn(
                "unit actual external factory refusal".into(),
            ))
        })
        .is_err()
    );
    assert_eq!(factory_calls.get(), 1);
}

#[test]
fn saved_failed_native_report_has_no_live_adapter_issuance_or_qualification_upgrade() {
    let kit = put_kit(CASES);
    let policy = configured();
    let mut adapter = RefusingAdapter { calls: 0 };
    let report = run_configured_with_native_adapter(kit.path(), &policy, &mut adapter).unwrap();
    let saved = Report::from_json(&report.to_json()).unwrap();
    // Same configured replay checks the actual complete24 source inventory.
    // Its signature has no adapter argument and cannot issue a live callback.
    check_report_configured(kit.path(), &saved, &policy).unwrap();
    assert_eq!(adapter.calls, 1);
    assert!(!saved.qualified());
    std::fs::write(kit.path().join("cases.json"), [CASES, b" "].concat()).unwrap();
    assert!(
        check_report_configured(kit.path(), &saved, &policy).is_err(),
        "exact whole-file digest is still bound on saved replay"
    );
    assert_eq!(adapter.calls, 1);
    let raw = report.to_json();
    assert_eq!(raw.matches("\"qualified\":false").count(), 1);
    let forged =
        Report::from_json(&raw.replacen("\"qualified\":false", "\"qualified\":true", 1)).unwrap();
    std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
    assert!(check_report_configured(kit.path(), &forged, &policy).is_err());
    assert_eq!(adapter.calls, 1);
}
