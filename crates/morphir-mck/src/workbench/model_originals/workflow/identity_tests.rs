//! Prospective shared model/action/checker tests. Exact original leaves are
//! separate frozen source records, not actual host/revision/opening evidence.
use super::identity_input::{IdentityInputError, IdentityInputPlan};
use super::observation_check::{
    CompareLimits, CompareOwner, IdentityFault, ObservationError, PredicateFault,
};
use super::work::{ClosureLimits, ClosureOwner};
use super::*;

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
fn closure() -> ClosureOwner {
    ClosureOwner::new(ClosureLimits::new(100_000, 100_000, 100_000_000, 100_000_000).unwrap())
}
fn compare() -> CompareOwner {
    CompareOwner::new(CompareLimits::new(1_000_000, 100_000_000, 100_000).unwrap())
}

#[test]
fn original_provider_metadata_and_project_path_key_leaves_use_actual_input_bound_samples() {
    for (corpus, observed, samples, checks) in [
        (
            include_str!("identity_controls/provider.corpus.json"),
            include_str!("identity_controls/provider.observed.json"),
            4,
            10,
        ),
        (
            include_str!("identity_controls/metadata.corpus.json"),
            include_str!("identity_controls/metadata.observed.json"),
            2,
            7,
        ),
        (
            include_str!("identity_controls/paths.corpus.json"),
            include_str!("identity_controls/paths.observed.json"),
            2,
            7,
        ),
    ] {
        let mut decode = decoder();
        let bound = ingress::BoundCorpus::decode(corpus, &mut decode).unwrap();
        let pair = bound.cases()[0].paired_with_work(&mut decode).unwrap();
        let aliases = compile::compile(&pair, &mut closure()).unwrap();
        assert_eq!(
            aliases
                .definitions()
                .iter()
                .filter(|d| d.role == meaning::Role::IdentitySample)
                .count(),
            samples
        );
        let plan = IdentityInputPlan::from_paired(&pair, &mut closure()).unwrap();
        assert_eq!(plan.bindings().len(), samples);
        for (index, binding) in plan.bindings().iter().enumerate() {
            assert_eq!(binding.run_index(), 0);
            assert_eq!(binding.action_index(), index);
            assert_eq!(binding.checkpoint_index(), samples);
            assert_eq!(binding.checkpoint().as_str(), "identity-records");
        }
        let actual = decode.decode::<observed::Observation>(observed).unwrap();
        let result =
            observation_check::check_planned(&pair, &plan, &actual, &mut compare()).unwrap();
        assert_eq!(result.checked_predicates(), checks);
        // This never proves host authority, revision identity or fourth-role
        // fresh opening/currentness/history, and is no full workflow pass.
    }
}

#[test]
fn matching_forged_key_and_snapshot_do_not_replace_actual_input_source_metadata_or_path() {
    for (raw, fault) in [
        (
            include_str!("identity_controls/forged-provider.observed.json"),
            IdentityFault::Snapshot,
        ),
        (
            include_str!("identity_controls/forged-label.observed.json"),
            IdentityFault::Snapshot,
        ),
        (
            include_str!("identity_controls/forged-persistence.observed.json"),
            IdentityFault::Snapshot,
        ),
        (
            include_str!("identity_controls/forged-path.observed.json"),
            IdentityFault::Path,
        ),
        (
            include_str!("identity_controls/wrong-sample.observed.json"),
            IdentityFault::Sample,
        ),
        (
            include_str!("identity_controls/wrong-action.observed.json"),
            IdentityFault::ActionIndex,
        ),
        (
            include_str!("identity_controls/wrong-checkpoint.observed.json"),
            IdentityFault::Checkpoint,
        ),
        (
            include_str!("identity_controls/wrong-kind.observed.json"),
            IdentityFault::Kind,
        ),
    ] {
        let mut decode = decoder();
        let bound = ingress::BoundCorpus::decode(
            include_str!("identity_controls/provider.corpus.json"),
            &mut decode,
        )
        .unwrap();
        let pair = bound.cases()[0].paired_with_work(&mut decode).unwrap();
        let plan = IdentityInputPlan::from_paired(&pair, &mut closure()).unwrap();
        let actual = decode.decode::<observed::Observation>(raw).unwrap();
        assert!(
            matches!(observation_check::check_planned(&pair, &plan, &actual, &mut compare()), Err(ObservationError::Identity { kind, .. }) if kind == fault)
        );
    }
}

#[test]
fn every_actual_identity_action_has_exactly_one_result_and_absence_is_not_empty_authority() {
    for (raw, fault) in [
        (
            include_str!("identity_controls/absent.observed.json"),
            IdentityFault::Missing,
        ),
        (
            include_str!("identity_controls/empty.observed.json"),
            IdentityFault::Missing,
        ),
        (
            include_str!("identity_controls/omitted.observed.json"),
            IdentityFault::Missing,
        ),
        (
            include_str!("identity_controls/duplicate-result.observed.json"),
            IdentityFault::Duplicate,
        ),
        (
            include_str!("identity_controls/unexpected-result.observed.json"),
            IdentityFault::Unexpected,
        ),
    ] {
        let mut decode = decoder();
        let bound = ingress::BoundCorpus::decode(
            include_str!("identity_controls/provider.corpus.json"),
            &mut decode,
        )
        .unwrap();
        let pair = bound.cases()[0].paired_with_work(&mut decode).unwrap();
        let plan = IdentityInputPlan::from_paired(&pair, &mut closure()).unwrap();
        let actual = decode.decode::<observed::Observation>(raw).unwrap();
        assert!(
            matches!(observation_check::check_planned(&pair, &plan, &actual, &mut compare()), Err(ObservationError::Identity { kind, .. }) if kind == fault)
        );
    }
}

#[test]
fn exact_expected_key_and_relation_are_independent_predicates_after_input_binding() {
    for (corpus, observed, index, kind) in [
        (
            include_str!("identity_controls/provider.corpus.json"),
            include_str!("identity_controls/wrong-key.observed.json"),
            4,
            PredicateFault::IdentityKey,
        ),
        (
            include_str!("identity_controls/wrong-relation.corpus.json"),
            include_str!("identity_controls/provider.observed.json"),
            8,
            PredicateFault::IdentityRelation,
        ),
    ] {
        let mut decode = decoder();
        let bound = ingress::BoundCorpus::decode(corpus, &mut decode).unwrap();
        let pair = bound.cases()[0].paired_with_work(&mut decode).unwrap();
        let plan = IdentityInputPlan::from_paired(&pair, &mut closure()).unwrap();
        let actual = decode.decode::<observed::Observation>(observed).unwrap();
        assert!(
            matches!(observation_check::check_planned(&pair, &plan, &actual, &mut compare()), Err(ObservationError::Predicate { index: at, kind: actual_kind }) if at == index && actual_kind == kind)
        );
    }
}

#[test]
fn input_without_future_checkpoint_or_with_duplicate_run_sample_refuses_before_plan_issue() {
    for (raw, duplicate) in [
        (
            include_str!("identity_controls/no-checkpoint.corpus.json"),
            false,
        ),
        (
            include_str!("identity_controls/duplicate-sample.corpus.json"),
            true,
        ),
    ] {
        let mut decode = decoder();
        let bound = ingress::BoundCorpus::decode(raw, &mut decode).unwrap();
        let pair = bound.cases()[0].paired_with_work(&mut decode).unwrap();
        if duplicate {
            assert!(matches!(
                IdentityInputPlan::from_paired(&pair, &mut closure()),
                Err(IdentityInputError::DuplicateSample { run: 0, action: 1 })
            ));
        } else {
            assert!(matches!(
                IdentityInputPlan::from_paired(&pair, &mut closure()),
                Err(IdentityInputError::MissingCheckpoint { run: 0, action: 0 })
            ));
        }
    }
    // Actual zero-producer-call enforcement needs the root live branch to
    // consume this compiled plan before sending the genuine request.
}

#[test]
fn same_sample_spelling_in_two_runs_stays_distinct_and_a_foreign_plan_cannot_be_reused() {
    let mut decode = decoder();
    let two = ingress::BoundCorpus::decode(
        include_str!("identity_controls/two-runs.corpus.json"),
        &mut decode,
    )
    .unwrap();
    let pair = two.cases()[0].paired_with_work(&mut decode).unwrap();
    let plan = IdentityInputPlan::from_paired(&pair, &mut closure()).unwrap();
    assert_eq!(
        plan.bindings()
            .iter()
            .filter(|b| b.run_index() == 0)
            .count(),
        2
    );
    assert_eq!(
        plan.bindings()
            .iter()
            .filter(|b| b.run_index() == 1)
            .count(),
        2
    );
    let other = ingress::BoundCorpus::decode(
        include_str!("identity_controls/metadata.corpus.json"),
        &mut decode,
    )
    .unwrap();
    let foreign = other.cases()[0].paired_with_work(&mut decode).unwrap();
    let actual = decode
        .decode::<observed::Observation>(include_str!("identity_controls/metadata.observed.json"))
        .unwrap();
    assert!(matches!(
        observation_check::check_planned(&foreign, &plan, &actual, &mut compare()),
        Err(ObservationError::Identity {
            kind: IdentityFault::Plan,
            ..
        })
    ));
}

#[test]
fn full_actual_ui_strings_and_metadata_use_global_policy_without_new_scalar_caps_or_normalization()
{
    for (raw, observed) in [
        (
            include_str!("identity_controls/full-strings.corpus.json"),
            include_str!("identity_controls/full-strings.observed.json"),
        ),
        (
            include_str!("identity_controls/unicode.corpus.json"),
            include_str!("identity_controls/unicode.observed.json"),
        ),
    ] {
        let mut decode = decoder();
        let bound = ingress::BoundCorpus::decode(raw, &mut decode).unwrap();
        let pair = bound.cases()[0].paired_with_work(&mut decode).unwrap();
        let plan = IdentityInputPlan::from_paired(&pair, &mut closure()).unwrap();
        let actual = decode.decode::<observed::Observation>(observed).unwrap();
        assert!(observation_check::check_planned(&pair, &plan, &actual, &mut compare()).is_ok());
    }
}

#[test]
fn original_fourth_role_and_unprovable_host_revision_leaves_remain_blocked() {
    let mut decode = decoder();
    let bound = ingress::BoundCorpus::decode(
        include_str!("identity_controls/reopen-blocked.corpus.json"),
        &mut decode,
    )
    .unwrap();
    let pair = bound.cases()[0].paired_with_work(&mut decode).unwrap();
    let plan = IdentityInputPlan::from_paired(&pair, &mut closure()).unwrap();
    let actual = decode
        .decode::<observed::Observation>(include_str!("identity_controls/metadata.observed.json"))
        .unwrap();
    assert!(matches!(
        observation_check::check_planned(&pair, &plan, &actual, &mut compare()),
        Err(ObservationError::ExpectedBlocked)
    ));
}

tagged! { OptionalIdentityProbe("kind") {
    Historical => "historical" { required: Text<0, 32> => "required" },
    Extended => "extended" { required: Text<0, 32> => "required" } optional { metadata: Text<0, 32> => "metadata" },
} }
#[test]
fn shared_tagged_optional_suffix_preserves_old_fields_duplicates_null_and_explicit_presence() {
    let mut decode = decoder();
    assert!(
        decode
            .decode::<OptionalIdentityProbe>(r#"{"kind":"historical","required":"a"}"#)
            .is_ok()
    );
    assert!(matches!(
        decode
            .decode::<OptionalIdentityProbe>(r#"{"kind":"extended","required":"a"}"#)
            .unwrap(),
        OptionalIdentityProbe::Extended {
            metadata: Presence::Absent,
            ..
        }
    ));
    assert!(matches!(
        decode
            .decode::<OptionalIdentityProbe>(r#"{"kind":"extended","required":"a","metadata":"b"}"#)
            .unwrap(),
        OptionalIdentityProbe::Extended {
            metadata: Presence::Present(_),
            ..
        }
    ));
    for raw in [
        r#"{"kind":"extended","required":"a","metadata":null}"#,
        r#"{"kind":"extended","metadata":"b"}"#,
        r#"{"kind":"historical","required":"a","metadata":"b"}"#,
        r#"{"kind":"extended","required":"a","metadata":"a","metadata":"b"}"#,
    ] {
        assert!(decoder().decode::<OptionalIdentityProbe>(raw).is_err());
    }
    for raw in [
        include_str!("identity_controls/null-results.observed.json"),
        include_str!("identity_controls/null-persistence.observed.json"),
    ] {
        assert!(decoder().decode::<observed::Observation>(raw).is_err());
    }
}
