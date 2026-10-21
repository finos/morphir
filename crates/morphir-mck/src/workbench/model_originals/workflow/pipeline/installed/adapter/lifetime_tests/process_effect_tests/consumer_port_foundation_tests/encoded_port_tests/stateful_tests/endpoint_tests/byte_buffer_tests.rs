//! Opaque I/O buffers under unchanged historical V3, through a genuine Run.
use super::*;
use crate::workbench::model_originals::workflow::decode::{DecodeError, OperandResource};
const V3: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/src/workbench/model_originals/workflow/pipeline/installed_client_tests/sealed_claims_controls/checker-policy-v3.json"
));
enum Case {
    Slots,
    Bytes,
    Capacity,
}
struct Probe {
    case: Case,
    entered: bool,
}
impl InstalledClientAdapter for Probe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        self.entered = true;
        let n = match self.case {
            Case::Slots => 16 * 1024 * 1024,
            _ => 128,
        };
        let before = run.decode.usage();
        match self.case {
            Case::Slots => {
                run.decode.slots(4_000_000 - before.slots - 2).unwrap();
                let first = run.observation_read_buffer(n);
                let second = if first.is_ok() {
                    Some(run.observation_read_buffer(n))
                } else {
                    None
                };
                let valid = first
                    .as_ref()
                    .is_ok_and(|b| b.len() == n && b.iter().all(|v| *v == 0))
                    && second.as_ref().is_some_and(|r| {
                        r.as_ref()
                            .is_ok_and(|b| b.len() == n && b.iter().all(|v| *v == 0))
                    });
                drop(first);
                drop(second);
                assert!(
                    valid,
                    "two opaque buffers require two structural slots, not one per byte"
                );
                assert_eq!(run.decode.usage().slots, 4_000_000);
            }
            Case::Bytes => {
                run.decode
                    .bytes(1_073_741_824 - before.byte_visits - (n - 1))
                    .unwrap();
                let receiving = run.installed_observation_usage();
                let result = run.observation_read_buffer(n);
                let refused = result.is_err();
                drop(result);
                assert!(
                    refused,
                    "N-1 byte work must refuse the N-byte initialization"
                );
                assert_eq!(
                    run.decode.ready(),
                    Err(DecodeError::Work(OperandResource::ByteVisits))
                );
                assert_eq!(run.installed_observation_usage(), receiving);
                let decoder = run.decode.usage();
                assert!(run.observation_read_buffer(n).is_err());
                assert_eq!(run.installed_observation_usage(), receiving);
                assert_eq!(run.decode.usage(), decoder);
            }
            Case::Capacity => {
                let remaining = 67_108_864 - run.installed_observation_usage().retained_bytes();
                run.reserve_storage(usize::try_from(remaining).unwrap() - (n - 1))
                    .unwrap();
                let result = run.observation_read_buffer(n);
                let refused = result.is_err();
                drop(result);
                assert!(refused);
                assert!(matches!(
                    run.receiving.ready(),
                    Err(InstalledObservationError::Resource {
                        kind: InstalledObservationResource::RetainedBytes,
                        used: 67_108_737,
                        requested: 128,
                        ..
                    })
                ));
                let receiving = run.installed_observation_usage();
                let decoder = run.decode.usage();
                assert!(run.observation_read_buffer(n).is_err());
                assert_eq!(run.installed_observation_usage(), receiving);
                assert_eq!(run.decode.usage(), decoder);
            }
        }
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
fn exercise(case: Case) {
    let kit = tempfile::tempdir().unwrap();
    std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
    let mut probe = Probe {
        case,
        entered: false,
    };
    let report = run_configured_with_installed_client_adapter(
        kit.path(),
        &RunConfiguration::from_json(V3).unwrap(),
        &mut probe,
    )
    .unwrap();
    assert!(probe.entered, "genuine complete24 callback required");
    assert!(!report.qualified());
}
#[test]
fn two_full_byte_buffers_use_two_structural_slots_under_unchanged_v3() {
    exercise(Case::Slots);
}
#[test]
fn byte_initialization_refuses_before_storage_when_byte_work_is_one_short() {
    exercise(Case::Bytes);
}
#[test]
fn byte_buffer_capacity_refusal_is_sticky_under_unchanged_v3() {
    exercise(Case::Capacity);
}
