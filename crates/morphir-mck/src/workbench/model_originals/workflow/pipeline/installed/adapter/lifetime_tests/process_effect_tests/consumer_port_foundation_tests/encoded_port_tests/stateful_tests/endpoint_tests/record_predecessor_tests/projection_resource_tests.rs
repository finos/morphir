//! Source-first SAME Run reservation controls under unchanged historical V3.
//! Proposed child of record_predecessor_tests. No endpoint or process effect.
use super::*;
use crate::workbench::model_originals::workflow::decode::{DecodeError, OperandResource};
use crate::workbench::model_originals::workflow::pipeline::installed::adapter::invocation::ConsumerRegistration;
const V3: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/src/workbench/model_originals/workflow/pipeline/installed_client_tests/sealed_claims_controls/checker-policy-v3.json"
));
#[derive(Clone, Copy)]
enum Case {
    Slots,
    Storage,
    Work,
    ClosedSource,
}
struct Probe {
    case: Case,
    entered: bool,
    owner: std::sync::Arc<TestGateOwner>,
}
impl InstalledClientAdapter for Probe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        self.entered = true;
        let end = Instant::now() + Duration::from_secs(10);
        activate(&mut run, &self.owner, end);
        let policy: serde_json::Value = serde_json::from_str(V3).unwrap();
        let slots = policy["checker"]["decode"]["slots"].as_u64().unwrap() as usize;
        let visits = policy["checker"]["decode"]["byteVisits"].as_u64().unwrap() as usize;
        let retained = policy["installedObservation"]["retainedBytes"]
            .as_u64()
            .unwrap();
        let r = usize::try_from(policy["checker"]["decode"]["savedBytes"].as_u64().unwrap())
            .unwrap()
            .min(crate::workbench::MAX_REPORT_BYTES);
        let limits = Limits {
            max_frame: 64,
            stderr_capture: 64,
            ..Limits::DEFAULT
        };
        let requirements = run.test_consumer_output_requirements(limits).unwrap();
        let diagnostic = requirements.test_diagnostic_bytes();
        let requested = r.checked_add(diagnostic).unwrap();
        assert_eq!(requirements.test_report_limit(), r);
        let work = limits
            .max_frame
            .checked_add(limits.stderr_capture)
            .unwrap()
            .checked_add(r.checked_mul(8).unwrap())
            .unwrap()
            .checked_add(20)
            .unwrap()
            .checked_add(diagnostic)
            .unwrap();
        match self.case {
            Case::Slots => {
                run.decode
                    .slots(slots - run.decode.usage().slots - 3)
                    .unwrap();
                let before = run.installed_observation_usage();
                let decode = run.decode.usage();
                let ticket = run
                    .test_prepare_consumer_output(limits)
                    .expect("three logical output/prefix-buffer slots suffice");
                let capacity = ticket.test_capacity();
                assert_eq!(ticket.test_report_limit(), r);
                assert_eq!(ticket.test_work_bound(), work);
                assert!(capacity >= r);
                assert_eq!(run.decode.usage().slots, slots);
                assert_eq!(run.decode.usage().byte_visits - decode.byte_visits, work);
                assert_eq!(
                    run.installed_observation_usage().retained_bytes() - before.retained_bytes(),
                    capacity.checked_add(diagnostic).unwrap() as u64
                );
                assert_eq!(
                    run.installed_observation_usage().byte_visits() - before.byte_visits(),
                    work as u64
                );
                drop(ticket);
            }
            Case::Storage => {
                let left = retained - run.installed_observation_usage().retained_bytes();
                run.reserve_storage(usize::try_from(left).unwrap() - (requested - 1))
                    .unwrap();
                let result = run.test_prepare_consumer_output(limits);
                let refused = result.is_err();
                drop(result);
                assert!(
                    refused,
                    "one byte short cannot fund report backing plus exact diagnostic reserve"
                );
                assert!(
                    matches!(run.receiving.ready(), Err(InstalledObservationError::Resource {
                    kind: InstalledObservationResource::RetainedBytes, requested, ..
                }) if *requested == requirements.test_retained_bytes() as u64)
                );
                let receiving = run.installed_observation_usage();
                let decoder = run.decode.usage();
                assert!(run.test_prepare_consumer_output(limits).is_err());
                assert_eq!(run.installed_observation_usage(), receiving);
                assert_eq!(run.decode.usage(), decoder);
            }
            Case::Work => {
                run.decode
                    .bytes(visits - run.decode.usage().byte_visits - (work - 1))
                    .unwrap();
                let receiving = run.installed_observation_usage();
                let result = run.test_prepare_consumer_output(limits);
                let refused = result.is_err();
                drop(result);
                assert!(
                    refused,
                    "W-1 decoder visits must refuse before retained allocation"
                );
                assert_eq!(
                    run.decode.ready(),
                    Err(DecodeError::Work(OperandResource::ByteVisits))
                );
                assert_eq!(run.installed_observation_usage(), receiving);
                let decoder = run.decode.usage();
                assert!(run.test_prepare_consumer_output(limits).is_err());
                assert_eq!(run.installed_observation_usage(), receiving);
                assert_eq!(run.decode.usage(), decoder);
            }
            Case::ClosedSource => {
                self.owner.gate.test_revoke_source();
                let receiving = run.installed_observation_usage();
                let decoder = run.decode.usage();
                assert!(run.test_prepare_consumer_output(limits).is_err());
                assert_eq!(run.installed_observation_usage(), receiving);
                assert_eq!(run.decode.usage(), decoder);
            }
        }
        assert!(
            matches!(run.revoker.consumer_ports, ConsumerRegistration::Unprepared),
            "reservation itself creates no endpoints, process or registration"
        );
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
fn exercise(case: Case) {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(root.path().join("cases.json"), CASES).unwrap();
    let mut policy: serde_json::Value = serde_json::from_str(V3).unwrap();
    policy["consumerObservation"] =
        serde_json::json!({"mode":"operation-port","version":"0.1.0-draft.1"});
    let mut probe = Probe {
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
    assert!(probe.entered, "genuine unchanged full24 callback required");
    assert!(!report.qualified());
}
#[test]
fn output_reservation_uses_three_logical_slots_and_actual_capacity() {
    exercise(Case::Slots);
}
#[test]
fn output_reservation_refuses_one_byte_short_before_endpoints_and_is_sticky() {
    exercise(Case::Storage);
}
#[test]
fn output_reservation_refuses_one_visit_short_before_storage_and_is_sticky() {
    exercise(Case::Work);
}
#[test]
fn output_reservation_refuses_closed_source_before_new_work_or_storage() {
    exercise(Case::ClosedSource);
}

mod encoding_bound_tests;
mod faulted_projection_tests;
mod prefix_data_tests;

mod preflight_tests;
mod resource_shortage_tests;
