//! Prospective missing-API test: functional record errors are not silently
//! declared sticky Decoder/CompareOwner errors. A real attempt owns the fault.
use super::DecodeError;
use super::observation_check::{CompareLimits, CompareOwner};
use super::record_check::{WorkflowEnvelopeFault, WorkflowRecordError};
use crate::json::strict::{ReadWork, ReadWorkLimits, StrictReadError};
use crate::workbench::report::WorkflowExchangeRecord;
#[path = "record_boundary_support.rs"]
mod support;

#[test]
fn genuine_record_check_attempt_retains_exact_first_functional_error_before_retry_work() {
    support::with_v3(|context, decode| {
        let mut saved_work = ReadWork::new(ReadWorkLimits::new(67_108_864, 1_000_000).unwrap());
        let version = WorkflowExchangeRecord::from_json(
            include_str!("record_boundary_controls/wrong-version.json"),
            &mut saved_work,
        )
        .unwrap();
        let duplicate = WorkflowExchangeRecord::from_json(
            include_str!("record_boundary_controls/observed-duplicate-role.json"),
            &mut saved_work,
        )
        .unwrap();
        let mut comparison =
            CompareOwner::new(CompareLimits::new(100_000, 1_000_000, 100_000).unwrap());
        let mut attempt = context.record_attempt();
        let first_pointer = {
            let error = attempt
                .check_record(&version, decode, &mut comparison)
                .err()
                .expect("fixed version forgery must refuse");
            assert!(matches!(
                error,
                WorkflowRecordError::Envelope(WorkflowEnvelopeFault::Version)
            ));
            error as *const WorkflowRecordError
        };
        let spent_decode = decode.usage();
        let spent_compare = comparison.usage();
        let second = attempt
            .check_record(&duplicate, decode, &mut comparison)
            .err()
            .expect("failed attempt stays failed");
        assert!(matches!(
            second,
            WorkflowRecordError::Envelope(WorkflowEnvelopeFault::Version)
        ));
        assert!(std::ptr::eq(first_pointer, second));
        assert_eq!(decode.usage(), spent_decode);
        assert_eq!(comparison.usage(), spent_compare);

        // An explicit independent top-level replay attempt is distinct. This
        // proves neither pre-serialize nor inventory-wide live/run readiness.
        let mut replay = context.record_attempt();
        let error = replay
            .check_record(&duplicate, decode, &mut comparison)
            .err()
            .expect("new attempt reaches actual strict reply decoder");
        assert!(matches!(
            error,
            WorkflowRecordError::Decode(DecodeError::Literal(StrictReadError::Json(_)))
        ));
    });
}
