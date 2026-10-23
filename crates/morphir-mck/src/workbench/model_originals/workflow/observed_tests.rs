//! Independent source/schema controls before observed decoder/dispatcher code.
//! This component tests evidence comparison, never actual producer execution.
use super::observation_check::{
    CompareLimits, CompareOwner, CorrelationFault, ObservationError, PredicateFault,
};
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
fn owner(visits: usize) -> CompareOwner {
    CompareOwner::new(CompareLimits::new(visits, 1_000_000, 10_000).unwrap())
}
const CASE: &str = include_str!("observed_controls/component.corpus.json");
const GOOD: &str = include_str!("observed_controls/positive.observed.json");

#[test]
fn workflow_effect_vocabulary_matches_the_explicit_nineteen_kind_source() {
    use crate::workbench::model_originals::EffectKind as Ledger;
    use input::EffectKind as Input;
    use observed::EffectKind as Observed;
    let schema: serde_json::Value = serde_json::from_str(include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../spec/workbench/model-originals/0.1.0-draft.1/schemas/mck-workflow-observation.schema.json"
    )))
    .unwrap();
    let kinds = [
        (Input::Picker, Observed::Picker, Ledger::Picker),
        (Input::FileRead, Observed::FileRead, Ledger::FileRead),
        (
            Input::NativeCapture,
            Observed::NativeCapture,
            Ledger::NativeCapture,
        ),
        (Input::Initialize, Observed::Initialize, Ledger::Initialize),
        (Input::Capture, Observed::Capture, Ledger::Capture),
        (Input::Inventory, Observed::Inventory, Ledger::Inventory),
        (
            Input::ReadOriginal,
            Observed::ReadOriginal,
            Ledger::ReadOriginal,
        ),
        (
            Input::ReadProjection,
            Observed::ReadProjection,
            Ledger::ReadProjection,
        ),
        (Input::Release, Observed::Release, Ledger::Release),
        (Input::Digest, Observed::Digest, Ledger::Digest),
        (Input::Inspection, Observed::Inspection, Ledger::Inspection),
        (
            Input::ExecutionSubmit,
            Observed::ExecutionSubmit,
            Ledger::ExecutionSubmit,
        ),
        (
            Input::ExecutionObserve,
            Observed::ExecutionObserve,
            Ledger::ExecutionObserve,
        ),
        (
            Input::ExecutionRelease,
            Observed::ExecutionRelease,
            Ledger::ExecutionRelease,
        ),
        (
            Input::LocalEvaluation,
            Observed::LocalEvaluation,
            Ledger::LocalEvaluation,
        ),
        (Input::Catalog, Observed::Catalog, Ledger::Catalog),
        (
            Input::NativeInvoke,
            Observed::NativeInvoke,
            Ledger::NativeInvoke,
        ),
        (
            Input::ManifestFetch,
            Observed::ManifestFetch,
            Ledger::ManifestFetch,
        ),
        (
            Input::WorkspaceOpen,
            Observed::WorkspaceOpen,
            Ledger::WorkspaceOpen,
        ),
    ];
    let source = schema["$defs"]["EffectKind"]["enum"].as_array().unwrap();
    assert_eq!(source.len(), kinds.len());
    let mut ledger_kinds = std::collections::BTreeSet::new();
    for ((input, observed, ledger), source) in kinds.into_iter().zip(source) {
        let wire = source.as_str().unwrap();
        assert_eq!(input.key(), wire);
        assert_eq!(observed.key(), wire);
        let raw = serde_json::to_string(wire).unwrap();
        assert_eq!(decoder().decode::<Input>(&raw).unwrap(), input);
        assert_eq!(decoder().decode::<Observed>(&raw).unwrap(), observed);
        assert!(
            ledger_kinds.insert(ledger),
            "duplicate ledger mapping for {wire}"
        );
    }
    assert_eq!(ledger_kinds.len(), source.len());
}

#[test]
fn workflow_effect_vocabulary_refuses_unknown_and_noncanonical_kinds() {
    for raw in [
        "\"manifest_fetch\"",
        "\"workspace-open-extra\"",
        "\"unknown\"",
        "\"Catalog\"",
        "null",
        "19",
    ] {
        assert!(decoder().decode::<input::EffectKind>(raw).is_err());
        assert!(decoder().decode::<observed::EffectKind>(raw).is_err());
    }
}

#[test]
fn workflow_effect_vocabulary_decodes_new_kinds_in_complete_observed_records() {
    let schema: serde_json::Value = serde_json::from_str(include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../spec/workbench/model-originals/0.1.0-draft.1/schemas/mck-workflow-observation.schema.json"
    )))
    .unwrap();
    let validator = jsonschema::options()
        .with_draft(jsonschema::Draft::Draft202012)
        .build(&schema)
        .unwrap();
    for kind in [
        "local-evaluation",
        "catalog",
        "native-invoke",
        "manifest-fetch",
        "workspace-open",
    ] {
        let effect = serde_json::json!({"attempt":"actual-attempt","kind":kind,"ordinal":0});
        let mut complete: serde_json::Value = serde_json::from_str(GOOD).unwrap();
        complete["effects"] = serde_json::json!([{"kind":"pending","effect":effect,"input":{"kind":"none"},"port":"promise"}]);
        complete["checkpoints"][0]["pendingEffects"] = serde_json::json!([effect]);
        complete["checkpoints"][0]["eventCount"] = serde_json::json!(1);
        validator.validate(&complete).unwrap();
        decoder()
            .decode::<observed::Observation>(&complete.to_string())
            .unwrap();
        complete["effects"][0]["effect"]["kind"] = serde_json::json!("unknown-effect");
        assert!(validator.validate(&complete).is_err());
        assert!(
            decoder()
                .decode::<observed::Observation>(&complete.to_string())
                .is_err()
        );
        // Literal evidence decoding only: no producer authority, completed
        // lifecycle, expected predicate or qualification follows from this.
    }
}

#[test]
fn independently_typed_observed_client_decodes_and_all_four_real_predicates_compare() {
    let mut decode = decoder();
    let corpus = ingress::BoundCorpus::decode(CASE, &mut decode).unwrap();
    let pair = corpus.cases()[0].paired_with_work(&mut decode).unwrap();
    let actual = decode.decode::<observed::Observation>(GOOD).unwrap();
    let result = observation_check::check_paired(&pair, &actual, &mut owner(100_000)).unwrap();
    assert_eq!(result.checked_predicates(), 4);
    assert!(super::historical::ScenarioRef::from(result.scenario()).same_owner(pair.scenario()));
    // No Qualified/Ready/producer-authority/semantic-lineage assertion.
}

#[test]
fn observed_schema_is_closed_and_exact_fractional_counts_never_round_to_integers() {
    for raw in [
        include_str!("observed_controls/extra.observed.json"),
        include_str!("observed_controls/missing.observed.json"),
        include_str!("observed_controls/fraction.observed.json"),
        include_str!("observed_controls/duplicate.observed.json"),
        include_str!("observed_controls/private-map-count.observed.json"),
    ] {
        let mut decode = decoder();
        assert!(decode.decode::<observed::Observation>(raw).is_err());
    }
}

#[test]
fn a_latched_genuine_decode_fault_precedes_observed_role_or_shape_dispatch() {
    let mut decode = Decoder::new(
        DecodeLimits::new(16_777_216, 1_073_741_824, 4_000_000, 1, 4_000_000).unwrap(),
    );
    assert!(decode.decode::<observed::Observation>(GOOD).is_err());
    let spent = decode.usage();
    assert!(matches!(
        decode.decode::<observed::Observation>("false"),
        Err(DecodeError::Work(OperandResource::ByteVisits))
    ));
    assert_eq!(decode.usage(), spent);
}

#[test]
fn observation_checkpoint_must_correspond_to_a_real_selected_input_action() {
    let mut decode = decoder();
    let corpus = ingress::BoundCorpus::decode(CASE, &mut decode).unwrap();
    let pair = corpus.cases()[0].paired_with_work(&mut decode).unwrap();
    let actual = decode
        .decode::<observed::Observation>(include_str!(
            "observed_controls/foreign-checkpoint.observed.json"
        ))
        .unwrap();
    assert!(matches!(
        observation_check::check_paired(&pair, &actual, &mut owner(100_000)),
        Err(ObservationError::Correlation {
            kind: CorrelationFault::UnknownCheckpoint,
            ..
        })
    ));
}

#[test]
fn duplicated_checkpoint_labels_cannot_replace_actual_ordered_observation_occurrences() {
    let mut decode = decoder();
    let corpus = ingress::BoundCorpus::decode(CASE, &mut decode).unwrap();
    let pair = corpus.cases()[0].paired_with_work(&mut decode).unwrap();
    let actual = decode
        .decode::<observed::Observation>(include_str!(
            "observed_controls/duplicate-checkpoint.observed.json"
        ))
        .unwrap();
    assert!(matches!(
        observation_check::check_paired(&pair, &actual, &mut owner(100_000)),
        Err(ObservationError::Correlation {
            kind: CorrelationFault::DuplicateCheckpoint,
            ..
        })
    ));
}

#[test]
fn self_consistent_observed_opening_model_and_navigation_aliases_are_not_input_bindings() {
    for raw in [
        include_str!("observed_controls/foreign-opening.observed.json"),
        include_str!("observed_controls/foreign-model.observed.json"),
        include_str!("observed_controls/foreign-navigation.observed.json"),
    ] {
        let mut decode = decoder();
        let corpus = ingress::BoundCorpus::decode(CASE, &mut decode).unwrap();
        let pair = corpus.cases()[0].paired_with_work(&mut decode).unwrap();
        let actual = decode.decode::<observed::Observation>(raw).unwrap();
        assert!(matches!(
            observation_check::check_paired(&pair, &actual, &mut owner(100_000)),
            Err(ObservationError::Correlation {
                kind: CorrelationFault::UnboundOwner,
                ..
            })
        ));
    }
}

#[test]
fn genuine_navigation_predicate_rejects_nonzero_measured_destination_count() {
    let mut decode = decoder();
    let corpus = ingress::BoundCorpus::decode(CASE, &mut decode).unwrap();
    let pair = corpus.cases()[0].paired_with_work(&mut decode).unwrap();
    let actual = decode
        .decode::<observed::Observation>(include_str!(
            "observed_controls/wrong-navigation-count.observed.json"
        ))
        .unwrap();
    assert!(matches!(
        observation_check::check_paired(&pair, &actual, &mut owner(100_000)),
        Err(ObservationError::Predicate {
            index: 3,
            kind: PredicateFault::Navigation,
            ..
        })
    ));
}

#[test]
fn an_unhandled_strong_check_is_a_source_located_blocker_after_supported_checks() {
    let mut decode = decoder();
    let corpus = ingress::BoundCorpus::decode(
        include_str!("observed_controls/strong-check.corpus.json"),
        &mut decode,
    )
    .unwrap();
    let pair = corpus.cases()[0].paired_with_work(&mut decode).unwrap();
    let actual = decode.decode::<observed::Observation>(GOOD).unwrap();
    assert!(matches!(
        observation_check::check_paired(&pair, &actual, &mut owner(100_000)),
        Err(ObservationError::UnsupportedClientCheck { index: 4 })
    ));
}

#[test]
fn actual_work_and_effect_evidence_cannot_be_ignored_by_a_four_predicate_comparison() {
    let mut decode = decoder();
    let corpus = ingress::BoundCorpus::decode(CASE, &mut decode).unwrap();
    let pair = corpus.cases()[0].paired_with_work(&mut decode).unwrap();
    let actual = decode
        .decode::<observed::Observation>(include_str!(
            "observed_controls/unbound-work.observed.json"
        ))
        .unwrap();
    assert!(matches!(
        observation_check::check_paired(&pair, &actual, &mut owner(100_000)),
        Err(ObservationError::UnqualifiedEvidence)
    ));
    // Later typed bridge must feed genuine shared effects/core validators;
    // no second ledger and no acceptance from four unrelated state predicates.
}

#[test]
fn explicit_compare_owner_is_cumulative_and_first_resource_fault_stops_retries() {
    let mut decode = decoder();
    let corpus = ingress::BoundCorpus::decode(CASE, &mut decode).unwrap();
    let pair = corpus.cases()[0].paired_with_work(&mut decode).unwrap();
    let actual = decode.decode::<observed::Observation>(GOOD).unwrap();
    let mut enough = owner(100_000);
    observation_check::check_paired(&pair, &actual, &mut enough).unwrap();
    let once = enough.usage();
    observation_check::check_paired(&pair, &actual, &mut enough).unwrap();
    assert!(enough.usage().visits > once.visits);
    assert!(enough.usage().comparison_bytes > once.comparison_bytes);
    assert_eq!(enough.usage().checks, 2 * once.checks);
    let mut none = owner(0);
    let first = observation_check::check_paired(&pair, &actual, &mut none)
        .err()
        .unwrap();
    let spent = none.usage();
    let second = observation_check::check_paired(&pair, &actual, &mut none)
        .err()
        .unwrap();
    assert_eq!(second, first);
    assert_eq!(none.usage(), spent);
}
