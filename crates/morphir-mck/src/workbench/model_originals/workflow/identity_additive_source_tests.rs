//! Prospective fixed identity-view/source/compiler controls, not producer proof.
use super::expansion::{ExpansionLimits, ExpansionOwner};
use super::reviewed_sources::ReviewedSources;
use super::source_compile::{CaseCompiler, CompilationError};
use super::source_proof::{LineageStatus, SourceError, SourceVerifier};
use super::work::{ClosureLimits, ClosureOwner};
use super::*;
fn owner() -> Decoder {
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
fn fixed_identity_source_view_issues_actual_static_compilation_for_all_three_original60_pairs_only_unproven_lineage()
 {
    let sources = ReviewedSources::identity_selected();
    for (raw, count) in [
        (
            include_str!("identity_source_controls/provider-new.corpus.json"),
            4,
        ),
        (
            include_str!("identity_source_controls/metadata-new.corpus.json"),
            2,
        ),
        (
            include_str!("identity_source_controls/paths-new.corpus.json"),
            2,
        ),
    ] {
        let mut decode = owner();
        let bound = ingress::BoundCorpus::decode(raw, &mut decode).unwrap();
        let verifier = SourceVerifier::new(&sources, &mut decode).unwrap();
        let mut closure = ClosureOwner::new(
            ClosureLimits::new(1_000_000, 1_000_000, 100_000_000, 100_000_000).unwrap(),
        );
        let mut expansion = ExpansionOwner::new(ExpansionLimits::new(
            1_073_741_824,
            1_073_741_824,
            1_073_741_824,
            1_000_000,
            10_000_000,
        ));
        let mut compiler = CaseCompiler::new(verifier, &mut closure, &mut expansion);
        let compiled = compiler.compile(&bound.cases()[0]).unwrap();
        assert!(std::ptr::eq(compiled.source().case(), &bound.cases()[0]));
        assert_eq!(compiled.source().lineage(), LineageStatus::Unproven);
        assert_eq!(compiled.identity_input().bindings().len(), count);
        assert!(
            compiled
                .identity_input()
                .scenario()
                .same_owner(compiled.source().paired().scenario())
        );
    }
}
#[test]
fn fixed_identity_source_view_rejects_old_coherent_inventory35_claim_before_any_closure_or_ui_work()
{
    let sources = ReviewedSources::identity_selected();
    for raw in [
        include_str!("identity_source_controls/provider-wrong-inventory35.corpus.json"),
        include_str!("identity_source_controls/metadata-wrong-inventory35.corpus.json"),
        include_str!("identity_source_controls/paths-wrong-inventory35.corpus.json"),
    ] {
        let mut decode = owner();
        let bound = ingress::BoundCorpus::decode(raw, &mut decode).unwrap();
        let verifier = SourceVerifier::new(&sources, &mut decode).unwrap();
        let mut closure = ClosureOwner::new(
            ClosureLimits::new(1_000_000, 1_000_000, 100_000_000, 100_000_000).unwrap(),
        );
        let mut expansion = ExpansionOwner::new(ExpansionLimits::new(
            1_073_741_824,
            1_073_741_824,
            1_073_741_824,
            1_000_000,
            10_000_000,
        ));
        let mut compiler = CaseCompiler::new(verifier, &mut closure, &mut expansion);
        let before = compiler.usage();
        assert!(matches!(
            compiler.compile(&bound.cases()[0]),
            Err(CompilationError::Source(SourceError::MissingOriginalCase))
        ));
        assert_eq!(compiler.usage().closure, before.closure);
        assert_eq!(compiler.usage().expansion, before.expansion);
    }
}
