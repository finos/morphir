//! Independently fixed source schedule/borrow controls, not actual UI work.
use super::*;
use crate::workbench::model_originals::workflow::{DecodeLimits, Decoder, ingress};

fn decoder() -> Decoder {
    Decoder::new(
        DecodeLimits::new(
            16_777_216,
            1_073_741_824,
            4_000_000,
            1_073_741_824,
            4_000_000,
        )
        .unwrap(),
    )
}
#[test]
fn controller_schedule_borrows_real_input_once_with_exact_initialization_order() {
    for (raw, calls, entries) in [
        (
            include_str!(
                "../identity_source_controls/identity-provider-separation.component.corpus.json"
            ),
            4,
            2,
        ),
        (
            include_str!(
                "../identity_source_controls/identity-label-and-persistence-do-not-rekey.component.corpus.json"
            ),
            3,
            1,
        ),
        (
            include_str!(
                "../identity_source_controls/identity-same-name-distinct-project-paths.component.corpus.json"
            ),
            2,
            1,
        ),
    ] {
        let mut decode = decoder();
        let bound = ingress::BoundCorpus::decode(raw, &mut decode).unwrap();
        let paired = bound.cases()[0].paired_with_work(&mut decode).unwrap();
        let mut work = ClosureOwner::new(
            super::super::work::ClosureLimits::new(100_000, 100_000, 100_000_000, 100_000_000)
                .unwrap(),
        );
        let plan = IdentityInputPlan::from_paired(&paired, &mut work).unwrap();
        assert_eq!(plan.controllers().len(), 1);
        let controller = &plan.controllers()[0];
        assert_eq!(controller.run, paired.run_index());
        assert_eq!(controller.calls.len(), calls);
        assert_eq!(controller.entries.len(), entries);
        assert_eq!(controller.calls[0].kind, ControllerCallKind::Inspect);
        assert_eq!(
            controller.calls[1].kind,
            ControllerCallKind::LoadDevelopment
        );
        if calls == 3 {
            assert_eq!(controller.calls[2].kind, ControllerCallKind::Inspect);
        }
        if calls == 4 {
            assert_eq!(controller.calls[2].kind, ControllerCallKind::Inspect);
            assert_eq!(
                controller.calls[3].kind,
                ControllerCallKind::LoadDevelopment
            );
        }
        assert!(std::ptr::eq(
            controller.entries[0],
            &controller.fixture.initial_sources.0[0]
        ));
        assert!(std::ptr::eq(
            controller.calls[0].source,
            &controller.fixture.initial_sources.0[0]
        ));
        assert!(std::ptr::eq(
            controller.calls[0].reply,
            &controller.fixture.providers.0[0].inspections.0[0].reply
        ));
        assert!(std::ptr::eq(plan.scenario(), paired.scenario()));
        assert!(work.usage().allocation_attempts > 0);
    }
}

#[test]
fn controller_plan_first_work_refusal_precedes_any_allocation_or_schedule_access() {
    let mut decode = decoder();
    let bound = ingress::BoundCorpus::decode(
        include_str!(
            "../identity_source_controls/identity-provider-separation.component.corpus.json"
        ),
        &mut decode,
    )
    .unwrap();
    let paired = bound.cases()[0].paired_with_work(&mut decode).unwrap();
    let mut owner = ClosureOwner::new(super::super::work::ClosureLimits::new(0, 0, 0, 0).unwrap());
    assert!(matches!(
        IdentityInputPlan::from_paired(&paired, &mut owner),
        Err(IdentityInputError::Work(ClosureError::Resource(
            Resource::StructuralVisits
        )))
    ));
    assert_eq!(owner.usage().allocation_attempts, 0);
    let before = owner.usage();
    assert!(matches!(
        IdentityInputPlan::from_paired(&paired, &mut owner),
        Err(IdentityInputError::Work(ClosureError::Resource(
            Resource::StructuralVisits
        )))
    ));
    assert_eq!(owner.usage().structural_visits, before.structural_visits);
    assert_eq!(owner.usage().lookup_bytes, before.lookup_bytes);
    assert_eq!(owner.usage().allocation_attempts, 0);
}
