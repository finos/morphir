//! Genuine compiler setup shared by additive boundary tests only.
use super::expansion::{ExpansionLimits, ExpansionOwner, ReadExpansionLimits};
use super::ingress::BoundCorpus;
use super::reviewed_sources::ReviewedSources;
use super::source_compile::{CaseCompiler, WorkflowReportContext};
use super::source_proof::{LineageStatus, SourceVerifier};
use super::work::{ClosureLimits, ClosureOwner};
use super::{DecodeLimits, Decoder};

pub(super) fn with_v3(test: impl FnOnce(&WorkflowReportContext<'_, '_, '_, '_, '_>, &mut Decoder)) {
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
    let bound = BoundCorpus::decode(
        include_str!("source_compile/controls/bound-corpus.json"),
        &mut decode,
    )
    .unwrap();
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
    let context = compiled.report_context();
    assert_eq!(
        context.case().id(),
        "connected-inventory-single-file-json-v3"
    );
    assert_eq!(context.lineage(), LineageStatus::Unproven);
    drop(compiler);
    test(&context, &mut decode);
}
