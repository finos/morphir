//! Funding-only controls under genuine compiled source0/host relationships.
//! No action is executed, settled or physically joined by a funding credit.
use super::*;
use crate::workbench::model_originals::workflow::pipeline::browser::adapter::execution_loans::{
    with_foreign_source_controller_lifetime, with_source_controller_artifact_control,
    with_source_controller_end,
};
use std::time::{Duration, Instant};

#[test]
fn browser_business_envelope_01_once_operations_and_credit_refusal_are_sticky() {
    with_source_controller_artifact_control(|lifetime, loans| {
        let mut envelope = SourceBusinessEnvelope::prepare(&lifetime, loans).unwrap();
        for operation in [
            SourceBusinessOperation::LaunchValidation,
            SourceBusinessOperation::ListenerStart,
            SourceBusinessOperation::OpeningSettlement,
            SourceBusinessOperation::InspectionPreparation,
            SourceBusinessOperation::InspectionSource,
            SourceBusinessOperation::InspectionSettlement,
        ] {
            let mut credit = envelope.take(operation).unwrap();
            credit.require_operation(operation).unwrap();
            let refused = credit
                .require_operation(SourceBusinessOperation::ControllerDispatch)
                .err()
                .unwrap();
            assert!(
                matches!(refused, SourceBusinessFundingFault::WrongOperation {expected:SourceBusinessOperation::ControllerDispatch, actual} if actual==operation)
            );
            assert_eq!(credit.require_operation(operation), Err(refused));
            assert!(
                credit.storage(0, 0, 0).is_err(),
                "a refused credit never heals"
            );
        }
        let mut dispatch = envelope
            .take(SourceBusinessOperation::ControllerDispatch)
            .unwrap();
        dispatch
            .require_operation(SourceBusinessOperation::ControllerDispatch)
            .unwrap();
        assert!(dispatch.storage(usize::MAX, 0, 0).is_err());
        assert!(dispatch.storage(0, 0, 0).is_err());
        let first = envelope
            .take(SourceBusinessOperation::InspectionSettlement)
            .err()
            .unwrap();
        let next = envelope
            .take(SourceBusinessOperation::ControllerDispatch)
            .err()
            .unwrap();
        assert_eq!(first, next, "the envelope preserves its first refusal");
    });
}

fn rounded_ticks(end: Instant, now: Instant) -> usize {
    usize::try_from(
        end.saturating_duration_since(now)
            .as_nanos()
            .div_ceil(1_000_000),
    )
    .unwrap()
        + 2
}
#[test]
fn browser_business_envelope_02_dispatch_count_is_derived_once_from_original_end() {
    with_source_controller_artifact_control(|lifetime, loans| {
        let before = Instant::now();
        let mut envelope = SourceBusinessEnvelope::prepare(&lifetime, loans).unwrap();
        let after = Instant::now();
        let minimum = rounded_ticks(lifetime.end(), after);
        let maximum = rounded_ticks(lifetime.end(), before);
        let mut issued = 0;
        for _ in 0..=maximum {
            if envelope
                .take(SourceBusinessOperation::ControllerDispatch)
                .is_err()
            {
                break;
            }
            issued += 1;
        }
        assert!(issued >= minimum && issued <= maximum);
        assert!(
            envelope
                .take(SourceBusinessOperation::ControllerDispatch)
                .is_err()
        );
    });
}

#[test]
fn browser_business_envelope_03_prepaid_use_after_residual_has_no_fresh_owner_debit() {
    with_source_controller_artifact_control(|lifetime, loans| {
        let mut envelope = SourceBusinessEnvelope::prepare(&lifetime, loans).unwrap();
        let layout = super::super::source_progress::business_layout().unwrap();
        let resource = layout.resources(SourceBusinessOperation::ControllerDispatch);
        // Consume the actual SAME retained remainder, just as residual cleanup
        // does. Ready owners at their limit remain valid; no new credit exists.
        let available = loans.remaining_cleanup_resources(&lifetime).unwrap();
        loans
            .reserve_controlled_host_storage(available.retained_bytes, 0, 0)
            .unwrap();
        let before = loans.business_usage().unwrap();
        let mut credit = envelope
            .take(SourceBusinessOperation::ControllerDispatch)
            .unwrap();
        credit
            .storage(resource.retained_bytes, resource.slots, resource.visits)
            .unwrap();
        credit
            .comparison(
                resource.comparison_visits,
                resource.comparison_bytes,
                resource.comparison_checks,
            )
            .unwrap();
        let after = loans.business_usage().unwrap();
        assert_eq!(before, after);
    });
}

#[test]
fn browser_business_envelope_04_expired_or_foreign_source_refuses_before_funding() {
    with_source_controller_end(Duration::from_millis(100), |lifetime, loans| {
        std::thread::sleep(
            lifetime.end().saturating_duration_since(Instant::now()) + Duration::from_millis(1),
        );
        let before = loans.business_usage().unwrap();
        assert!(SourceBusinessEnvelope::prepare(&lifetime, loans).is_err());
        let after = loans.business_usage().unwrap();
        assert_eq!(before, after);
    });
    with_foreign_source_controller_lifetime(|lifetime, loans| {
        let before = loans.business_usage().unwrap();
        assert!(SourceBusinessEnvelope::prepare(&lifetime, loans).is_err());
        let after = loans.business_usage().unwrap();
        assert_eq!(before, after);
    });
}

#[test]
fn browser_business_envelope_05_insufficient_same_owner_capacity_refuses_before_effects() {
    with_source_controller_artifact_control(|lifetime, loans| {
        let available = loans.remaining_cleanup_resources(&lifetime).unwrap();
        loans
            .reserve_controlled_host_storage(available.retained_bytes, 0, 0)
            .unwrap();
        let original_end = lifetime.end();
        let refusal = SourceBusinessEnvelope::prepare(&lifetime, loans);
        assert!(
            refusal.is_err(),
            "actual wrapper backing must be paid before issuance"
        );
        assert_eq!(lifetime.end(), original_end);
        assert!(
            loans.business_test_ready().is_err(),
            "actual cumulative resource refusal is retained"
        );
    });
}
