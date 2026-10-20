//! Source-authored subset controls, never reviewed source/runtime qualification.
use super::identity_input::IdentityInputPlan;
use super::observation_check::{
    CompareLimits, CompareOwner, ControllerFault, IdentityFault, ObservationError,
};
use super::work::{ClosureLimits, ClosureOwner};
use super::*;
fn decode_owner() -> Decoder {
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
fn static_owner() -> ClosureOwner {
    ClosureOwner::new(ClosureLimits::new(100_000, 100_000, 100_000_000, 100_000_000).unwrap())
}
fn compare_owner() -> CompareOwner {
    CompareOwner::new(CompareLimits::new(1_000_000, 100_000_000, 100_000).unwrap())
}
const PROVIDER: &str =
    include_str!("identity_source_controls/identity-provider-separation.component.corpus.json");
#[test]
fn actual_workspace_shape_compares_exact_keys_and_controller_without_empty_semantic_owner_substitution()
 {
    for (corpus, raw, count) in [
        (
            PROVIDER,
            include_str!("identity_source_controls/provider.observed.json"),
            7,
        ),
        (
            include_str!(
                "identity_source_controls/identity-label-and-persistence-do-not-rekey.component.corpus.json"
            ),
            include_str!("identity_source_controls/metadata.observed.json"),
            4,
        ),
        (
            include_str!(
                "identity_source_controls/identity-same-name-distinct-project-paths.component.corpus.json"
            ),
            include_str!("identity_source_controls/paths.observed.json"),
            4,
        ),
    ] {
        let mut owner = decode_owner();
        let bound = ingress::BoundCorpus::decode(corpus, &mut owner).unwrap();
        let paired = bound.cases()[0].paired_with_work(&mut owner).unwrap();
        let plan = IdentityInputPlan::from_paired(&paired, &mut static_owner()).unwrap();
        let observed = owner.decode::<observed::Observation>(raw).unwrap();
        let result =
            observation_check::check_planned(&paired, &plan, &observed, &mut compare_owner())
                .unwrap();
        assert_eq!(result.checked_predicates(), count);
    }
}
#[test]
fn real_controller_source_and_complete_provider_sequence_bind_before_literal_predicates() {
    for (raw, kind) in [
        (
            include_str!(
                "identity_source_controls/forged-matching-controller-snapshot-and-key.observed.json"
            ),
            ControllerFault::SourceBinding,
        ),
        (
            include_str!(
                "identity_source_controls/swapped-real-provider-invocation-order.observed.json"
            ),
            ControllerFault::InvocationOrder,
        ),
        (
            include_str!("identity_source_controls/omitted-real-provider-invocation.observed.json"),
            ControllerFault::MissingInvocation,
        ),
        (
            include_str!("identity_source_controls/foreign-controller-entry.observed.json"),
            ControllerFault::Key,
        ),
    ] {
        let mut owner = decode_owner();
        let bound = ingress::BoundCorpus::decode(PROVIDER, &mut owner).unwrap();
        let paired = bound.cases()[0].paired_with_work(&mut owner).unwrap();
        let plan = IdentityInputPlan::from_paired(&paired, &mut static_owner()).unwrap();
        let actual = owner.decode::<observed::Observation>(raw).unwrap();
        assert!(
            matches!(observation_check::check_planned(&paired,&plan,&actual,&mut compare_owner()),Err(ObservationError::Controller{kind:actual_kind,..}) if actual_kind==kind)
        );
    }
}
#[test]
fn compiled_action_checkpoint_and_exact_composite_duplicates_keep_named_identity_faults_in_workspace_arm()
 {
    for (raw, kind) in [
        (
            include_str!("identity_source_controls/foreign-unbound-action-result.observed.json"),
            IdentityFault::ActionIndex,
        ),
        (
            include_str!("identity_source_controls/not-first-subsequent-checkpoint.observed.json"),
            IdentityFault::Checkpoint,
        ),
        (
            include_str!("identity_source_controls/omitted-produced-identity-result.observed.json"),
            IdentityFault::Missing,
        ),
        (
            include_str!(
                "identity_source_controls/duplicate-produced-identity-result.observed.json"
            ),
            IdentityFault::Duplicate,
        ),
    ] {
        let mut owner = decode_owner();
        let bound = ingress::BoundCorpus::decode(PROVIDER, &mut owner).unwrap();
        let paired = bound.cases()[0].paired_with_work(&mut owner).unwrap();
        let plan = IdentityInputPlan::from_paired(&paired, &mut static_owner()).unwrap();
        let actual = owner.decode::<observed::Observation>(raw).unwrap();
        assert!(
            matches!(observation_check::check_planned(&paired,&plan,&actual,&mut compare_owner()),Err(ObservationError::Identity{kind:actual_kind,..}) if actual_kind==kind)
        );
    }
}
