//! Preauthored actual-code unit controls, before the native comparator exists.
//! Port inside existing workflow module. This tests typed DATA only, not an
//! actual host, SDK scope, JoinHandle, engine live context or original role.
use super::expansion::{ExpansionLimits, ExpansionOwner, ReadExpansionLimits};
use super::native_original::decode::{decode_expected, decode_input, decode_observation};
use super::native_original::{ValidatedRunIndex, compile_native_plan};
use super::observation_check::server::compare_declaration_data;
use super::observation_check::{CompareLimits, CompareOwner, ObservationError};
use super::source_compile::CompilationError;
use super::work::{ClosureLimits, ClosureOwner};
use super::{DecodeError, DecodeLimits, Decoder};
use serde::Deserialize;

const INPUT: &str = include_str!("original/input.json");
const EXPECTED: &str = include_str!("original/expected.json");
const POSITIVE: &str = include_str!("unit-data-v2/positive.observation.json");

#[derive(Debug)]
enum UnitFailure {
    InputDecode(DecodeError),
    ExpectedDecode(DecodeError),
    ObservationDecode(DecodeError),
    Compile(CompilationError),
    Compare(ObservationError),
}
impl UnitFailure {
    fn phase_and_error(&self) -> (&'static str, &dyn std::fmt::Debug) {
        match self {
            Self::InputDecode(error) => ("InputDecode", error),
            Self::ExpectedDecode(error) => ("ExpectedDecode", error),
            Self::ObservationDecode(error) => ("ObservationDecode", error),
            Self::Compile(error) => ("Compile", error),
            Self::Compare(error) => {
                assert_ne!(
                    *error,
                    ObservationError::UnsupportedServer,
                    "pure DATA helper must execute comparison, not the still-unwired live branch"
                );
                ("Compare", error)
            }
        }
    }
}
fn decoder() -> Decoder {
    // Existing source-compiler tests' explicit named UNIT policies; not a
    // production default, source/report-issued policy or actual host budget.
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
    ClosureOwner::new(ClosureLimits::new(1_000_000, 1_000_000, 100_000_000, 100_000_000).unwrap())
}
fn expansion() -> ExpansionOwner {
    ExpansionOwner::new(
        ExpansionLimits::new(
            1_073_741_824,
            1_073_741_824,
            1_073_741_824,
            1_000_000,
            10_000_000,
        )
        .with_reads(ReadExpansionLimits::new(
            1_000_000,
            4_294_967_296,
            8_589_934_592,
            8_589_934_592,
        )),
    )
}
fn check_data(input: &str, expected: &str, actual: &str) -> Result<(), UnitFailure> {
    let mut decode = decoder();
    let source = decode_input(input, &mut decode).map_err(UnitFailure::InputDecode)?;
    let expected = decode_expected(expected, &mut decode).map_err(UnitFailure::ExpectedDecode)?;
    let actual = decode_observation(actual, &mut decode).map_err(UnitFailure::ObservationDecode)?;
    let index = ValidatedRunIndex::for_original(&source, 0).map_err(UnitFailure::Compile)?;
    let mut closure = closure();
    let mut expansion = expansion();
    let plan = compile_native_plan(&source, &expected, index, &mut closure, &mut expansion)
        .map_err(UnitFailure::Compile)?;
    let mut compare =
        CompareOwner::new(CompareLimits::new(1_000_000, 100_000_000, 100_000).unwrap());
    // This is the SAME helper called by production check_core after genuine
    // live context validation. It returns only factual success, not a grant.
    compare_declaration_data(&plan, &actual, &mut compare)
        .map(|_| ())
        .map_err(UnitFailure::Compare)
}
#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct UnitCase {
    id: String,
    pointer: String,
    expected_phase: String,
    input: String,
    expected: String,
    observation: String,
    classification: String,
}
fn reject_case(raw: &str) {
    // This is test inventory metadata. The actual operand strings still go
    // through existing strict Decoder, never serde_json::Value normalization.
    let case: UnitCase = serde_json::from_str(raw).unwrap();
    assert!(case.classification.contains("unit"));
    assert!(!case.id.is_empty() && case.pointer.starts_with('/'));
    let error = check_data(&case.input, &case.expected, &case.observation)
        .expect_err("each independent fixed negative must refuse");
    let (phase, detail) = error.phase_and_error();
    if case.expected_phase == "ObservationDecodeOrCompare" {
        assert!(
            matches!(phase, "ObservationDecode" | "Compare"),
            "{detail:?}"
        );
    } else {
        assert_eq!(
            phase, case.expected_phase,
            "{} {} {detail:?}",
            case.id, case.pointer
        );
    }
}
#[test]
fn independently_authored_full_original_data_compares_without_runtime_qualification() {
    check_data(INPUT, EXPECTED, POSITIVE).unwrap();
    // No native run context/completion is constructed or returned here.
    // Actual default startup/provenance/host adapter tests remain separate.
}
#[test]
fn all42_original_leaf_mutations_refuse_at_the_frozen_typed_phase() {
    for raw in MUTATIONS {
        reject_case(raw);
    }
}
#[test]
fn all42_required_original_fields_refuse_when_omitted() {
    for raw in OMISSIONS {
        reject_case(raw);
    }
}

// The generated fixed include lists enumerate actual files and are frozen;
// no runtime directory discovery, implementation output or skipped row.
include!("unit-data-v2/include-cases.rs");

include!("supplement/native_unit_guards.rs");
