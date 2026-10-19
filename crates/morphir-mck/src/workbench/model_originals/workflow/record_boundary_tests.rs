//! Untrusted saved-data controls, not fabricated completed transport receipts.
use super::observation_check::{CompareLimits, CompareOwner};
use super::record_check::{WorkflowEnvelopeFault, WorkflowRecordError};
use super::{DecodeError, OperandResource};
use crate::json::strict::{ReadWork, ReadWorkLimits, StrictReadError};
use crate::workbench::report::WorkflowExchangeRecord;
#[path = "record_boundary_support.rs"]
mod support;

enum ExpectedFailure {
    Envelope(WorkflowEnvelopeFault),
    Literal,
    Value,
    Shape,
}

#[test]
fn untrusted_record_forgery_refuses_at_actual_source_or_exact_decode_boundary() {
    support::with_v3(|context, decode| {
        let mut saved_work = ReadWork::new(ReadWorkLimits::new(67_108_864, 1_000_000).unwrap());
        let cases = [
            (
                include_str!("record_boundary_controls/wrong-run.json"),
                ExpectedFailure::Envelope(WorkflowEnvelopeFault::RunIndex),
            ),
            (
                include_str!("record_boundary_controls/wrong-role.json"),
                ExpectedFailure::Envelope(WorkflowEnvelopeFault::Role),
            ),
            (
                include_str!("record_boundary_controls/wrong-version.json"),
                ExpectedFailure::Envelope(WorkflowEnvelopeFault::Version),
            ),
            (
                include_str!("record_boundary_controls/wrong-suite.json"),
                ExpectedFailure::Envelope(WorkflowEnvelopeFault::Suite),
            ),
            (
                include_str!("record_boundary_controls/wrong-format.json"),
                ExpectedFailure::Envelope(WorkflowEnvelopeFault::Format),
            ),
            (
                include_str!("record_boundary_controls/input-interior-space.json"),
                ExpectedFailure::Envelope(WorkflowEnvelopeFault::Input),
            ),
            (
                include_str!("record_boundary_controls/other-source-case.json"),
                ExpectedFailure::Envelope(WorkflowEnvelopeFault::Input),
            ),
            (
                include_str!("record_boundary_controls/wrong-origin-input.json"),
                ExpectedFailure::Envelope(WorkflowEnvelopeFault::Input),
            ),
            (
                include_str!("record_boundary_controls/request-id-zero.json"),
                ExpectedFailure::Envelope(WorkflowEnvelopeFault::RequestId),
            ),
            (
                include_str!("record_boundary_controls/request-id-negative-zero.json"),
                ExpectedFailure::Envelope(WorkflowEnvelopeFault::RequestId),
            ),
            (
                include_str!("record_boundary_controls/request-id-fraction-spelling.json"),
                ExpectedFailure::Envelope(WorkflowEnvelopeFault::RequestId),
            ),
            (
                include_str!("record_boundary_controls/request-id-exponent-spelling.json"),
                ExpectedFailure::Envelope(WorkflowEnvelopeFault::RequestId),
            ),
            (
                include_str!("record_boundary_controls/reply-id-zero.json"),
                ExpectedFailure::Envelope(WorkflowEnvelopeFault::ReplyId),
            ),
            (
                include_str!("record_boundary_controls/reply-id-other.json"),
                ExpectedFailure::Envelope(WorkflowEnvelopeFault::Correlation),
            ),
            (
                include_str!("record_boundary_controls/reply-id-exponent.json"),
                ExpectedFailure::Envelope(WorkflowEnvelopeFault::ReplyId),
            ),
            (
                include_str!("record_boundary_controls/wrong-status.json"),
                ExpectedFailure::Envelope(WorkflowEnvelopeFault::Status),
            ),
            (
                include_str!("record_boundary_controls/observed-duplicate-role.json"),
                ExpectedFailure::Literal,
            ),
            (
                include_str!("record_boundary_controls/observed-fractional-count.json"),
                ExpectedFailure::Value,
            ),
            (
                include_str!("record_boundary_controls/observed-private-marker-count.json"),
                ExpectedFailure::Shape,
            ),
            (
                include_str!("record_boundary_controls/request-duplicate-id.json"),
                ExpectedFailure::Literal,
            ),
            (
                include_str!("record_boundary_controls/reply-duplicate-id.json"),
                ExpectedFailure::Literal,
            ),
            (
                include_str!("record_boundary_controls/invented-token-hash-field.json"),
                ExpectedFailure::Shape,
            ),
        ];
        for (index, (raw, expected)) in cases.into_iter().enumerate() {
            let record = WorkflowExchangeRecord::from_json(raw, &mut saved_work).unwrap();
            // Each independent adversarial example is a separate comparison
            // attempt. Actual Decoder and saved ReadWork remain cumulative.
            let mut comparison =
                CompareOwner::new(CompareLimits::new(100_000, 1_000_000, 100_000).unwrap());
            let error = match context.check_record(&record, decode, &mut comparison) {
                Err(error) => error,
                Ok(_) => panic!("forged saved record {index} was accepted"),
            };
            match expected {
                ExpectedFailure::Envelope(fault) => assert!(
                    matches!(error, WorkflowRecordError::Envelope(actual) if actual == fault),
                    "case {index}: {error:?}"
                ),
                ExpectedFailure::Literal => assert!(
                    matches!(
                        error,
                        WorkflowRecordError::Decode(DecodeError::Literal(StrictReadError::Json(_)))
                    ),
                    "case {index}: {error:?}"
                ),
                ExpectedFailure::Value => assert!(
                    matches!(error, WorkflowRecordError::Decode(DecodeError::Value(_))),
                    "case {index}: {error:?}"
                ),
                ExpectedFailure::Shape => assert!(
                    matches!(error, WorkflowRecordError::Decode(DecodeError::Shape(_))),
                    "case {index}: {error:?}"
                ),
            }
            assert_eq!(
                comparison.usage().checks,
                0,
                "no expected-leaf predicate reached"
            );
        }

        // A genuine refusal through the same actual Decoder is established
        // without allocating a giant object or editing its private fault state.
        let record = WorkflowExchangeRecord::from_json(
            include_str!("record_boundary_controls/wrong-version.json"),
            &mut saved_work,
        )
        .unwrap();
        assert!(matches!(
            decode.slots(usize::MAX),
            Err(DecodeError::Work(OperandResource::Slots))
        ));
        let spent = decode.usage();
        let mut comparison =
            CompareOwner::new(CompareLimits::new(100_000, 1_000_000, 100_000).unwrap());
        for _ in 0..2 {
            assert!(matches!(
                context.check_record(&record, decode, &mut comparison),
                Err(WorkflowRecordError::Decode(DecodeError::Work(
                    OperandResource::Slots
                )))
            ));
            assert_eq!(decode.usage(), spent);
            assert_eq!(comparison.usage().checks, 0);
        }
    });
}

#[test]
fn saved_record_body_stays_closed_and_its_real_read_work_stays_cumulative() {
    let mut work = ReadWork::new(ReadWorkLimits::new(67_108_864, 1_000_000).unwrap());
    for raw in [
        include_str!("record_boundary_controls/saved-duplicate-key.json"),
        include_str!("record_boundary_controls/saved-extra-qualified.json"),
        include_str!("record_boundary_controls/saved-missing-payload.json"),
        include_str!("record_boundary_controls/saved-null-payload.json"),
    ] {
        assert!(WorkflowExchangeRecord::from_json(raw, &mut work).is_err());
    }
    let raw = include_str!("record_boundary_controls/wrong-version.json");
    let mut exhausted = ReadWork::new(ReadWorkLimits::new(1, 1).unwrap());
    assert!(WorkflowExchangeRecord::from_json(raw, &mut exhausted).is_err());
    let spent = exhausted.usage();
    assert!(WorkflowExchangeRecord::from_json(raw, &mut exhausted).is_err());
    assert_eq!(exhausted.usage(), spent);
}
