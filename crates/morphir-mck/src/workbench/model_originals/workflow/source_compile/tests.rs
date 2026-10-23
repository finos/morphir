//! Prospective composition controls, frozen before implementation/execution.
//! These prove static source correspondence/closure/expansion only.
use super::*;
use crate::workbench::model_originals::workflow::{
    DecodeLimits, Decoder,
    compile::CompileError,
    expansion::{
        ExpansionError, ExpansionLimits, ExpansionOwner, ExpansionResource, ReadExpansionLimits,
    },
    ingress::BoundCorpus,
    reviewed_sources::ReviewedSources,
    source_proof::{LineageStatus, SourceError, SourceVerifier},
    work::{ClosureError, ClosureLimits, ClosureOwner, Resource},
};

const ALL: &str = include_str!("controls/bound-corpus.json");
const FIRST: &str = include_str!("controls/positive-first.corpus.json");
const SPACE: &str = include_str!("controls/interior-input-space.corpus.json");
// Independently summed UTF-8 literals: 8 request frames, 8 reply frames,
// and the actual manifest body in the first immutable input fixture.
const FIRST_FRAME_BYTES: u64 = include!("controls/first-frame-bytes.rs");
const FIRST_LAST_FRAME_BYTES: u64 = include!("controls/first-last-frame-bytes.rs");

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
fn closure(definitions: usize) -> ClosureOwner {
    ClosureOwner::new(ClosureLimits::new(definitions, 1_000_000, 100_000_000, 100_000_000).unwrap())
}
fn expansion(frames: u64) -> ExpansionOwner {
    ExpansionOwner::new(
        ExpansionLimits::new(1_073_741_824, frames, 1_073_741_824, 1_000_000, 10_000_000)
            .with_reads(ReadExpansionLimits::new(
                1_000_000,
                4_294_967_296,
                8_589_934_592,
                8_589_934_592,
            )),
    )
}

#[test]
fn all23_bound_cases_compose_existing_static_algorithms_without_lineage_or_runtime_upgrade() {
    let sources = ReviewedSources::selected();
    let mut decode = decoder();
    let bound = BoundCorpus::decode(ALL, &mut decode).unwrap();
    let verifier = SourceVerifier::new(&sources, &mut decode).unwrap();
    let mut aliases = closure(1_000_000);
    let mut expanded = expansion(1_073_741_824);
    let mut compiler = CaseCompiler::new(verifier, &mut aliases, &mut expanded);
    assert_eq!(bound.cases().len(), 23);
    for case in bound.cases() {
        let plan = compiler.compile(case).unwrap();
        assert!(std::ptr::eq(plan.source().case(), case));
        assert_eq!(plan.source().lineage(), LineageStatus::Unproven);
        assert!(
            plan.source()
                .paired()
                .scenario()
                .same_owner(plan.expansion().scenario())
        );
        assert!(!plan.aliases().definitions().is_empty());
        assert!(!plan.aliases().associations().is_empty());
    }
    // No actual producer, effect, semantic leaf or Ready assertion is present.
}

#[test]
fn source_refusal_precedes_zero_closure_and_expansion_policy_and_is_retained_exactly() {
    let sources = ReviewedSources::selected();
    let mut decode = decoder();
    let good = BoundCorpus::decode(FIRST, &mut decode).unwrap();
    let bad = BoundCorpus::decode(SPACE, &mut decode).unwrap();
    let verifier = SourceVerifier::new(&sources, &mut decode).unwrap();
    let mut aliases = closure(0);
    let mut expanded = expansion(0);
    let mut compiler = CaseCompiler::new(verifier, &mut aliases, &mut expanded);
    let before = compiler.usage();
    let first = {
        let error = compiler.compile(&bad.cases()[0]).err().unwrap();
        assert!(matches!(
            error,
            CompilationError::Source(SourceError::InputToken)
        ));
        std::ptr::from_ref(error)
    };
    let spent = compiler.usage();
    assert_eq!(spent.closure, before.closure);
    assert_eq!(spent.expansion, before.expansion);
    assert!(spent.decode.byte_visits > before.decode.byte_visits);
    assert_eq!(
        std::ptr::from_ref(compiler.compile(&good.cases()[0]).err().unwrap()),
        first
    );
    assert_eq!(compiler.usage(), spent);
}

#[test]
fn closure_refusal_stops_expansion_and_later_source_work_without_cloning_the_error() {
    let sources = ReviewedSources::selected();
    let mut decode = decoder();
    let good = BoundCorpus::decode(FIRST, &mut decode).unwrap();
    let bad = BoundCorpus::decode(SPACE, &mut decode).unwrap();
    let verifier = SourceVerifier::new(&sources, &mut decode).unwrap();
    let mut aliases = closure(0);
    let mut expanded = expansion(1_073_741_824);
    let mut compiler = CaseCompiler::new(verifier, &mut aliases, &mut expanded);
    let before = compiler.usage();
    let first = {
        let error = compiler.compile(&good.cases()[0]).err().unwrap();
        assert!(matches!(
            error,
            CompilationError::Closure(CompileError::Owner(ClosureError::Resource(
                Resource::Definitions
            )))
        ));
        std::ptr::from_ref(error)
    };
    let spent = compiler.usage();
    assert_eq!(spent.expansion, before.expansion);
    assert!(spent.decode.byte_visits > before.decode.byte_visits);
    assert_eq!(
        std::ptr::from_ref(compiler.compile(&bad.cases()[0]).err().unwrap()),
        first
    );
    assert_eq!(compiler.usage(), spent);
}

#[test]
fn expansion_refusal_preserves_earlier_actual_source_and_closure_work_and_stops_retries() {
    let sources = ReviewedSources::selected();
    let mut decode = decoder();
    let good = BoundCorpus::decode(FIRST, &mut decode).unwrap();
    let bad = BoundCorpus::decode(SPACE, &mut decode).unwrap();
    let verifier = SourceVerifier::new(&sources, &mut decode).unwrap();
    let mut aliases = closure(1_000_000);
    let mut expanded = expansion(0);
    let mut compiler = CaseCompiler::new(verifier, &mut aliases, &mut expanded);
    let first = {
        let error = compiler.compile(&good.cases()[0]).err().unwrap();
        assert!(matches!(
            error,
            CompilationError::Expansion(ExpansionError::Resource(ExpansionResource::FrameBytes))
        ));
        std::ptr::from_ref(error)
    };
    let spent = compiler.usage();
    assert!(spent.closure.definitions > 0);
    assert!(spent.closure.references > 0);
    assert_eq!(spent.expansion.amount(ExpansionResource::FrameBytes), 0);
    assert_eq!(
        std::ptr::from_ref(compiler.compile(&bad.cases()[0]).err().unwrap()),
        first
    );
    assert_eq!(compiler.usage(), spent);
}

#[test]
fn explicit_frame_policy_is_cumulative_across_case_calls_and_independent_of_scenario_claims() {
    for (maximum, succeeds_twice) in [
        (2 * FIRST_FRAME_BYTES, true),
        (2 * FIRST_FRAME_BYTES - 1, false),
    ] {
        let sources = ReviewedSources::selected();
        let mut decode = decoder();
        let bound = BoundCorpus::decode(FIRST, &mut decode).unwrap();
        let verifier = SourceVerifier::new(&sources, &mut decode).unwrap();
        let mut aliases = closure(1_000_000);
        let mut expanded = expansion(maximum);
        let mut compiler = CaseCompiler::new(verifier, &mut aliases, &mut expanded);
        {
            let plan = compiler.compile(&bound.cases()[0]).unwrap();
            assert_eq!(
                plan.expansion()
                    .usage()
                    .amount(ExpansionResource::FrameBytes),
                FIRST_FRAME_BYTES
            );
        }
        let first = compiler.usage();
        if succeeds_twice {
            let plan = compiler.compile(&bound.cases()[0]).unwrap();
            assert_eq!(
                plan.expansion()
                    .usage()
                    .amount(ExpansionResource::FrameBytes),
                FIRST_FRAME_BYTES
            );
            let total = compiler.usage();
            assert_eq!(
                total.expansion.amount(ExpansionResource::FrameBytes),
                2 * FIRST_FRAME_BYTES
            );
            assert_eq!(total.closure.definitions, 2 * first.closure.definitions);
            assert_eq!(total.closure.references, 2 * first.closure.references);
        } else {
            assert!(matches!(
                compiler.compile(&bound.cases()[0]),
                Err(CompilationError::Expansion(ExpansionError::Resource(
                    ExpansionResource::FrameBytes
                )))
            ));
            let spent = compiler.usage();
            assert_eq!(
                spent.expansion.amount(ExpansionResource::FrameBytes),
                2 * FIRST_FRAME_BYTES - FIRST_LAST_FRAME_BYTES
            );
            assert!(compiler.compile(&bound.cases()[0]).is_err());
            assert_eq!(compiler.usage(), spent);
        }
    }
}

#[test]
fn a_preexisting_closure_fault_is_checked_before_any_new_source_binding_work() {
    let sources = ReviewedSources::selected();
    let mut decode = decoder();
    let bound = BoundCorpus::decode(SPACE, &mut decode).unwrap();
    let verifier = SourceVerifier::new(&sources, &mut decode).unwrap();
    let mut aliases = closure(0);
    assert_eq!(
        aliases.charge(Resource::Definitions, 1),
        Err(ClosureError::Resource(Resource::Definitions))
    );
    let mut expanded = expansion(1_073_741_824);
    let mut compiler = CaseCompiler::new(verifier, &mut aliases, &mut expanded);
    let before = compiler.usage();
    assert!(matches!(
        compiler.compile(&bound.cases()[0]),
        Err(CompilationError::Closure(CompileError::Owner(
            ClosureError::Resource(Resource::Definitions)
        )))
    ));
    assert_eq!(compiler.usage(), before);
}

#[cfg(test)]
mod owned_fault;
