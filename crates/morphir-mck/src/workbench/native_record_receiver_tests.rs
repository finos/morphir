//! Independent receiving-budget DATA tests through the genuine source-issued
//! callback. These adapters deliberately return Startup, never host/Ready DATA.
use super::model_originals::native::{
    NativeAdapterError, NativeOriginalAdapter, NativeOriginalMeasurements, NativeOriginalNode,
    NativeOriginalRun, PrivateRecordError,
};
use super::{RunConfiguration, run_configured_with_native_adapter};
const POLICY: &str = include_str!("native_record_receiver_controls/native-policy.json");
const OLD_POLICY: &str = include_str!("native_record_receiver_controls/prior-native-policy.json");
const CASES: &[u8] = include_bytes!("native_pipeline_controls/cases24.json");
const RECORD: &[u8] = include_bytes!("native_record_receiver_controls/private-record-237.json");
fn policy(limit: u64, comparison: u64) -> RunConfiguration {
    let raw = POLICY
        .replacen(
            "\"retainedBytes\":237",
            &format!("\"retainedBytes\":{limit}"),
            1,
        )
        .replacen(
            "\"comparisonBytes\":1000000",
            &format!("\"comparisonBytes\":{comparison}"),
            1,
        );
    RunConfiguration::from_json(&raw).unwrap()
}
#[test]
fn private_record_policy_is_explicit_canonical_and_separate_from_existing_observation() {
    let config = policy(237, 1_000_000);
    assert_eq!(
        config.private_record_limits().unwrap().retained_bytes(),
        237
    );
    assert_eq!(
        config
            .native_observation_limits()
            .unwrap()
            .source_returned_bytes(),
        67_108_864
    );
    assert_eq!(
        policy(0, 1_000_000)
            .private_record_limits()
            .unwrap()
            .retained_bytes(),
        0
    );
    assert_eq!(
        policy(u64::MAX, 1_000_000)
            .private_record_limits()
            .unwrap()
            .retained_bytes(),
        u64::MAX
    );
    assert!(
        RunConfiguration::from_json(OLD_POLICY).is_err(),
        "new explicit member is required, no default"
    );
    for raw in [
        r#"{"kind":"historical"}"#,
        include_str!("native_pipeline_controls/current-policy.json"),
    ] {
        assert!(
            RunConfiguration::from_json(raw)
                .unwrap()
                .private_record_limits()
                .is_none()
        );
    }
    let rejected: Vec<String> = serde_json::from_str(include_str!(
        "native_record_receiver_controls/rejected-policies.json"
    ))
    .unwrap();
    assert_eq!(rejected.len(), 15);
    for raw in rejected {
        assert!(RunConfiguration::from_json(&raw).is_err(), "{raw}");
    }
}
#[derive(Clone, Copy)]
enum Control {
    OneLess,
    Exact,
    TwoExact,
    TwoOneLess,
    SpareRefused,
    SpareExact,
    EmptyZero,
    EmptySpare,
    LengthMismatch,
    CapacityMismatch,
    AllocationMismatch,
    InvalidUtf8,
    TooManyCharacters,
    Multibyte,
    Abandon,
    Cancel,
    RecordFirst,
    ComparisonFirst,
}
struct Adapter {
    control: Control,
    calls: usize,
}
fn record() -> Vec<u8> {
    assert_eq!(RECORD.len(), 237);
    let value = RECORD.to_vec();
    assert_eq!(
        value.capacity(),
        237,
        "fixed unit Vec allocation, not producer output"
    );
    value
}
fn capacity_error(error: &PrivateRecordError, limit: u64, used: u64, requested: u64) {
    assert!(
        matches!(error,PrivateRecordError::Capacity {limit:l,used:u,requested:r} if (*l,*u,*r)==(limit,used,requested)),
        "{error:?}"
    );
}
impl NativeOriginalAdapter for Adapter {
    fn observe(
        &mut self,
        mut run: NativeOriginalRun<'_>,
    ) -> Result<NativeOriginalMeasurements, NativeAdapterError> {
        self.calls += 1;
        assert_eq!(
            run.source().original_id(),
            "explicit-empty-companion-declaration-is-complete"
        );
        assert_eq!(run.private_record_retention_usage().reserved_bytes(), 0);
        match self.control {
            Control::OneLess
            | Control::SpareRefused
            | Control::EmptySpare
            | Control::RecordFirst => {
                let mut slot = Some(
                    if matches!(self.control, Control::SpareRefused | Control::EmptySpare) {
                        let mut bytes = Vec::with_capacity(4096);
                        if !matches!(self.control, Control::EmptySpare) {
                            bytes.extend_from_slice(RECORD)
                        }
                        assert_eq!(bytes.capacity(), 4096);
                        bytes
                    } else {
                        record()
                    },
                );
                let expected = if matches!(self.control, Control::SpareRefused) {
                    (237, 4096)
                } else if matches!(self.control, Control::EmptySpare) {
                    (0, 4096)
                } else {
                    (236, 237)
                };
                let pointer = slot.as_ref().unwrap().as_ptr();
                let first = match run.prepare_private_record_adoption(slot.as_ref().unwrap()) {
                    Err(error) => {
                        capacity_error(error, expected.0, 0, expected.1);
                        std::ptr::from_ref(error)
                    }
                    Ok(_) => panic!("refuse BEFORE caller slot take"),
                };
                assert_eq!(slot.as_ref().unwrap().as_ptr(), pointer);
                assert_eq!(run.private_record_retention_usage().reserved_bytes(), 0);
                if matches!(self.control, Control::RecordFirst) {
                    let fixture = run.fixture();
                    let grant = fixture.grants().next().unwrap();
                    let NativeOriginalNode::File { bytes, .. } = grant.nodes().next().unwrap()
                    else {
                        panic!("first config")
                    };
                    assert!(
                        run.materialize_fixture_bytes(bytes).is_err(),
                        "record fault prevents new recipe work"
                    );
                }
                match run.prepare_private_record_adoption(slot.as_ref().unwrap()) {
                    Err(error) => assert_eq!(std::ptr::from_ref(error), first),
                    Ok(_) => panic!("sticky exact first fault"),
                }
                drop(slot.take());
            }
            Control::Exact | Control::SpareExact | Control::EmptyZero | Control::Multibyte => {
                let bytes = match self.control {
                    Control::SpareExact => {
                        let mut value = Vec::with_capacity(4096);
                        value.extend_from_slice(RECORD);
                        assert_eq!(value.capacity(), 4096);
                        value
                    }
                    Control::EmptyZero => Vec::new(),
                    Control::Multibyte => "é".repeat(524_289).into_bytes(),
                    _ => record(),
                };
                let pointer = bytes.as_ptr();
                let length = bytes.len();
                let capacity = bytes.capacity();
                if matches!(self.control, Control::Multibyte) {
                    assert_eq!(length, 1_048_578);
                }
                let ticket = run
                    .prepare_private_record_adoption(&bytes)
                    .unwrap_or_else(|error| panic!("{error:?}"));
                assert_eq!(ticket.usage().reserved_bytes(), capacity as u64);
                let data = ticket.commit(bytes).unwrap();
                let super::model_originals::native::data::Bytes::Utf8 { text } = data else {
                    panic!("same UTF8 representation")
                };
                assert_eq!(
                    text.as_str().as_ptr(),
                    pointer,
                    "SAME allocation, no to_owned/reallocation"
                );
                assert_eq!(text.as_str().len(), length);
                match self.control {
                    Control::Multibyte => assert_eq!(text.as_str().chars().count(), 524_289),
                    Control::EmptyZero => assert!(text.as_str().is_empty()),
                    _ => assert_eq!(text.as_str().as_bytes(), RECORD),
                }
                assert_eq!(
                    run.private_record_retention_usage().reserved_bytes(),
                    capacity as u64
                );
                drop(text);
                assert_eq!(
                    run.private_record_retention_usage().reserved_bytes(),
                    capacity as u64,
                    "no refund"
                );
            }
            Control::TwoExact | Control::TwoOneLess => {
                let first = record();
                let ticket = run
                    .prepare_private_record_adoption(&first)
                    .unwrap_or_else(|error| panic!("{error:?}"));
                drop(ticket.commit(first).unwrap());
                assert_eq!(run.private_record_retention_usage().reserved_bytes(), 237);
                let second = record();
                if matches!(self.control, Control::TwoExact) {
                    let ticket = run
                        .prepare_private_record_adoption(&second)
                        .unwrap_or_else(|error| panic!("{error:?}"));
                    assert_eq!(ticket.usage().reserved_bytes(), 474);
                    drop(ticket.commit(second).unwrap());
                    assert_eq!(run.private_record_retention_usage().reserved_bytes(), 474);
                } else {
                    let first_error = match run.prepare_private_record_adoption(&second) {
                        Err(error) => {
                            capacity_error(error, 473, 237, 237);
                            std::ptr::from_ref(error)
                        }
                        Ok(_) => panic!("cumulative474 exceeds473"),
                    };
                    assert_eq!(run.private_record_retention_usage().reserved_bytes(), 237);
                    match run.prepare_private_record_adoption(&second) {
                        Err(error) => assert_eq!(std::ptr::from_ref(error), first_error),
                        Ok(_) => panic!("retry after refusal"),
                    }
                }
            }
            Control::LengthMismatch
            | Control::CapacityMismatch
            | Control::AllocationMismatch
            | Control::InvalidUtf8
            | Control::TooManyCharacters => {
                let mut bytes = if matches!(self.control, Control::TooManyCharacters) {
                    vec![b' '; 1_048_577]
                } else {
                    record()
                };
                let original_capacity = bytes.capacity();
                let ticket = run
                    .prepare_private_record_adoption(&bytes)
                    .unwrap_or_else(|error| panic!("{error:?}"));
                match self.control {
                    Control::LengthMismatch => bytes.truncate(236),
                    Control::CapacityMismatch => {
                        bytes.reserve_exact(4096 - bytes.len());
                        assert_eq!(bytes.capacity(), 4096);
                    }
                    Control::InvalidUtf8 => bytes[0] = 255,
                    _ => {}
                }
                let original = if matches!(self.control, Control::AllocationMismatch) {
                    let other = record();
                    assert_ne!(bytes.as_ptr(), other.as_ptr());
                    Some(std::mem::replace(&mut bytes, other))
                } else {
                    None
                };
                let first_error = match ticket.commit(bytes) {
                    Err(error) => {
                        let expected = match self.control {
                            Control::LengthMismatch => matches!(
                                error,
                                PrivateRecordError::LengthMismatch {
                                    expected: 237,
                                    actual: 236
                                }
                            ),
                            Control::CapacityMismatch => matches!(
                                error,
                                PrivateRecordError::CapacityMismatch {
                                    expected: 237,
                                    actual: 4096
                                }
                            ),
                            Control::AllocationMismatch => {
                                matches!(error, PrivateRecordError::AllocationMismatch)
                            }
                            Control::InvalidUtf8 => {
                                matches!(error, PrivateRecordError::InvalidUtf8)
                            }
                            Control::TooManyCharacters => {
                                matches!(error, PrivateRecordError::UnsupportedRepresentation)
                            }
                            _ => false,
                        };
                        assert!(expected, "{error:?}");
                        std::ptr::from_ref(error)
                    }
                    Ok(_) => panic!("invalid commit refuses"),
                };
                drop(original);
                assert_eq!(
                    run.private_record_retention_usage().reserved_bytes(),
                    original_capacity as u64
                );
                let retry = record();
                match run.prepare_private_record_adoption(&retry) {
                    Err(error) => assert_eq!(std::ptr::from_ref(error), first_error),
                    Ok(_) => panic!("failed commit stays sticky"),
                }
            }
            Control::Abandon | Control::Cancel => {
                let bytes = record();
                let ticket = run
                    .prepare_private_record_adoption(&bytes)
                    .unwrap_or_else(|error| panic!("{error:?}"));
                assert_eq!(ticket.usage().reserved_bytes(), 237);
                if matches!(self.control, Control::Cancel) {
                    ticket.cancel()
                } else {
                    drop(ticket)
                }
                assert_eq!(run.private_record_retention_usage().reserved_bytes(), 237);
                let first = match run.prepare_private_record_adoption(&bytes) {
                    Err(error) => {
                        assert!(matches!(error, PrivateRecordError::Abandoned));
                        std::ptr::from_ref(error)
                    }
                    Ok(_) => panic!("abandoned reservation refuses"),
                };
                match run.prepare_private_record_adoption(&bytes) {
                    Err(error) => assert_eq!(std::ptr::from_ref(error), first),
                    Ok(_) => panic!("no reset/refund"),
                }
            }
            Control::ComparisonFirst => {
                let fixture = run.fixture();
                let grant = fixture.grants().next().unwrap();
                let NativeOriginalNode::File { bytes, .. } = grant.nodes().next().unwrap() else {
                    panic!("first config")
                };
                assert!(run.materialize_fixture_bytes(bytes).is_err());
                let bytes = record();
                match run.prepare_private_record_adoption(&bytes) {
                    Err(error) => assert!(matches!(error, PrivateRecordError::PriorWorkFault)),
                    Ok(_) => panic!("work fault precedes receiving reservation"),
                }
                assert_eq!(run.private_record_retention_usage().reserved_bytes(), 0);
            }
        }
        Err(NativeAdapterError::Startup)
    }
}
fn exercise(control: Control, limit: u64, comparison: u64, phase: &str, code: &str) {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(root.path().join("cases.json"), CASES).unwrap();
    let mut adapter = Adapter { control, calls: 0 };
    let report =
        run_configured_with_native_adapter(root.path(), &policy(limit, comparison), &mut adapter)
            .unwrap();
    assert_eq!(adapter.calls, 1);
    assert!(!report.qualified());
    let data: serde_json::Value = serde_json::from_str(&report.to_json()).unwrap();
    assert_eq!(data["errors"].as_array().unwrap().len(), 1);
    assert_eq!(data["errors"][0]["phase"], phase);
    assert_eq!(data["errors"][0]["code"], code);
    assert_eq!(data["records"].as_array().unwrap().len(), 24);
    assert_eq!(data["records"][0]["evidence"]["kind"], "attempt-failed");
    for row in &data["records"].as_array().unwrap()[1..] {
        assert_eq!(row["evidence"]["kind"], "not-attempted");
    }
}
#[test]
fn capacity_before_take_exact_cumulative_and_spare_capacity_boundaries() {
    for control in [
        Control::Exact,
        Control::TwoExact,
        Control::SpareExact,
        Control::EmptyZero,
    ] {
        let limit = match control {
            Control::TwoExact => 474,
            Control::SpareExact => 4096,
            Control::EmptyZero => 0,
            _ => 237,
        };
        exercise(
            control,
            limit,
            1_000_000,
            "native-startup",
            "native-startup-refused",
        );
    }
    for (control, limit) in [
        (Control::OneLess, 236),
        (Control::TwoOneLess, 473),
        (Control::SpareRefused, 237),
        (Control::EmptySpare, 0),
    ] {
        exercise(
            control,
            limit,
            1_000_000,
            "native-record-retention",
            "record-retention-capacity",
        );
    }
}
#[test]
fn wrong_buffer_shape_and_allocation_refuse_without_replacement_data_or_retry() {
    for (control, code) in [
        (Control::LengthMismatch, "record-length-mismatch"),
        (Control::CapacityMismatch, "record-capacity-mismatch"),
        (Control::AllocationMismatch, "record-allocation-mismatch"),
    ] {
        exercise(control, 237, 1_000_000, "native-record-retention", code);
    }
}
#[test]
fn utf8_and_existing_character_bound_are_checked_without_a_new_byte_limit() {
    exercise(
        Control::InvalidUtf8,
        237,
        8_388_608,
        "native-record-retention",
        "record-invalid-utf8",
    );
    exercise(
        Control::TooManyCharacters,
        8_388_608,
        8_388_608,
        "native-record-retention",
        "record-representation-unsupported",
    );
    exercise(
        Control::Multibyte,
        8_388_608,
        8_388_608,
        "native-startup",
        "native-startup-refused",
    );
}
#[test]
fn abandoned_or_cancelled_ticket_is_sticky_and_cumulative_without_refund() {
    for control in [Control::Abandon, Control::Cancel] {
        exercise(
            control,
            237,
            1_000_000,
            "native-record-retention",
            "record-adoption-abandoned",
        );
    }
}
#[test]
fn genuine_receiving_and_comparison_first_faults_precede_later_adapter_startup() {
    exercise(
        Control::RecordFirst,
        236,
        1,
        "native-record-retention",
        "record-retention-capacity",
    );
    exercise(
        Control::ComparisonFirst,
        237,
        1,
        "observation",
        "observation-refused",
    );
}
