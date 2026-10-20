//! Intended child of actual workflow module; no replacement compiler/checker.
//! Root integrates before missing-method RED. Candidate API remains private.
use super::expansion::{ExpansionLimits, ExpansionOwner, ReadExpansionLimits};
use super::ingress::BoundCorpus;
use super::reviewed_sources::ReviewedSources;
use super::source_compile::CaseCompiler;
use super::source_proof::{LineageStatus, SourceVerifier};
use super::work::{ClosureLimits, ClosureOwner};
use super::*;

#[test]
fn report_context_is_issued_only_from_actual_compiled_source_and_borrows_its_operands() {
    let raw = include_str!("source_compile/controls/bound-corpus.json");
    let sources = ReviewedSources::selected();
    let mut decode = Decoder::new(
        DecodeLimits::new(
            16_777_216,
            1_073_741_824,
            4_000_000,
            1_073_741_824,
            4_000_000,
        )
        .unwrap(),
    );
    let bound = BoundCorpus::decode(raw, &mut decode).unwrap();
    let verifier = SourceVerifier::new(&sources, &mut decode).unwrap();
    let mut closure = ClosureOwner::new(
        ClosureLimits::new(1_000_000, 1_000_000, 100_000_000, 100_000_000).unwrap(),
    );
    let mut expanded = ExpansionOwner::new(
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
    );
    let mut compiler = CaseCompiler::new(verifier, &mut closure, &mut expanded);
    let compiled = compiler.compile(&bound.cases()[0]).unwrap();

    // This is the currently missing genuine compiler-to-Report seam, not a
    // constructor accepting a saved case name/digest/qualified flag.
    let context = compiled.report_context();
    assert!(std::ptr::eq(context.case(), compiled.source().case()));
    assert!(std::ptr::eq(context.paired(), compiled.source().paired()));
    assert!(std::ptr::eq(
        context.input_raw(),
        bound.cases()[0].input_raw()
    ));
    assert_eq!(context.paired().run_index(), 0);
    assert!(matches!(
        context.paired().run(),
        super::pairing::PairedRun::Client { .. }
    ));
    assert_eq!(
        context.case().id(),
        "connected-inventory-single-file-json-v3"
    );
    assert_eq!(context.lineage(), LineageStatus::Unproven);
}
