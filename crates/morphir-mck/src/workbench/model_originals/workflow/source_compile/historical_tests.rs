//! Exact original operands through the existing source/closure/expansion path.
//! Compilation is not lifecycle, semantic-lineage or native-runtime evidence.
use super::super::expansion::{ExpansionLimits, ReadExpansionLimits};
use super::super::work::ClosureLimits;
use super::super::{
    DecodeLimits, Decoder, ingress::BoundCorpus, reviewed_sources::ReviewedSources,
};
use super::*;

macro_rules! original {($case:literal,$file:literal)=>{include_str!(concat!(env!("CARGO_MANIFEST_DIR"),"/../../spec/workbench/model-originals/0.1.0-draft.1/reviewed-sources/local-historical-first-v1/cases/",$case,"/",$file,".json"))};}
const ORIGINALS: [(&str, &str, &str); 3] = [
    (
        "inspection-and-search-use-current-local-reference",
        original!("inspection-and-search-use-current-local-reference", "input"),
        original!(
            "inspection-and-search-use-current-local-reference",
            "expected"
        ),
    ),
    (
        "browser-import-v4-bom-crlf.json",
        original!("browser-import-v4-bom-crlf.json", "input"),
        original!("browser-import-v4-bom-crlf.json", "expected"),
    ),
    (
        "native-import-v4-bom-crlf.json",
        original!("native-import-v4-bom-crlf.json", "input"),
        original!("native-import-v4-bom-crlf.json", "expected"),
    ),
];
pub(in crate::workbench::model_originals::workflow) fn corpus() -> String {
    format!(
        "{{\"cases\":[{}]}}",
        ORIGINALS
            .iter()
            .map(|(id, input, expected)| format!(
                "{{\"id\":\"{id}\",\"input\":{input},\"expected\":{expected}}}"
            ))
            .collect::<Vec<_>>()
            .join(",")
    )
}
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

#[test]
fn historical_compilation_01_three_original_cases_reach_the_same_compiler_result() {
    let sources = ReviewedSources::historical_selected();
    let raw = corpus();
    let mut d = decoder();
    let bound = BoundCorpus::decode_historical(&raw, &mut d).unwrap();
    let verifier = SourceVerifier::new(&sources, &mut d).unwrap();
    let mut closure = closure();
    let mut expansion = expansion();
    let mut compiler = CaseCompiler::new(verifier, &mut closure, &mut expansion);
    compiler.require_inventory(bound.cases()).unwrap();
    assert_eq!(bound.cases().len(), 3);
    for (case, (_, input, expected)) in bound.cases().iter().zip(ORIGINALS) {
        let compiled: CompiledSourceCase<'_, '_, '_, '_> = compiler.compile(case).unwrap();
        assert!(std::ptr::eq(compiled.source().case(), case));
        assert_eq!(case.input_token(), input.trim());
        assert_eq!(case.expected_token(), expected.trim());
        assert_eq!(compiled.report_context().lineage(), LineageStatus::Unproven);
        assert!(
            compiled
                .source()
                .paired()
                .scenario()
                .same_owner(compiled.expansion().scenario())
        );
        assert!(
            compiled
                .source()
                .paired()
                .scenario()
                .same_owner(compiled.identity_input().scenario())
        );
        assert!(compiled.source().paired().scenario().current().is_none());
        assert!(compiled.source().paired().expected().is_none());
        assert!(!compiled.aliases().definitions().is_empty());
        assert!(!compiled.aliases().associations().is_empty());
    }
}

fn compare() -> CompareOwner {
    CompareOwner::new(
        super::super::observation_check::CompareLimits::new(1_000_000, 16_777_216, 100_000)
            .unwrap(),
    )
}
const OBSERVATION: &str = include_str!("../observed_controls/positive.observed.json");

#[test]
fn historical_compilation_02_context_keeps_blocked_qualification_and_absent_ledger_without_debit() {
    use super::super::observation_check::lifecycle::LifecycleFault;
    let sources = ReviewedSources::historical_selected();
    let raw = corpus();
    let mut d = decoder();
    let bound = BoundCorpus::decode_historical(&raw, &mut d).unwrap();
    for case in bound.cases() {
        let verifier = SourceVerifier::new(&sources, &mut d).unwrap();
        let mut c = closure();
        let mut e = expansion();
        let mut compiler = CaseCompiler::new(verifier, &mut c, &mut e);
        let compiled = compiler.compile(case).unwrap();
        drop(compiler);
        // Existing literal component DATA is deliberately not a historical
        // runtime observation. It must never discharge the blocked source.
        let actual: observed::Observation = d.decode(OBSERVATION).unwrap();
        let mut owner = compare();
        let before = (d.usage(), e.usage(), owner.usage());
        assert!(matches!(
            compiled
                .report_context()
                .check_client_lifecycle(&actual, &mut d, &mut e, &mut owner),
            Err(ObservationError::Lifecycle {
                kind: LifecycleFault::MissingLedgerAllowances,
                event: 0
            })
        ));
        assert_eq!((d.usage(), e.usage(), owner.usage()), before);
        assert!(matches!(
            owner.ready(),
            Err(ObservationError::Lifecycle {
                kind: LifecycleFault::MissingLedgerAllowances,
                ..
            })
        ));
        assert!(matches!(
            compiled
                .report_context()
                .check_observation(&actual, &mut compare()),
            Err(ObservationError::ExpectedBlocked)
        ));
    }
}

#[test]
fn historical_compilation_03_lifecycle_ready_precedence_retains_real_cumulative_faults() {
    use super::super::observation_check::{CompareResource, lifecycle::LifecycleFault};
    let sources = ReviewedSources::historical_selected();
    let raw = corpus();
    let mut d = decoder();
    let bound = BoundCorpus::decode_historical(&raw, &mut d).unwrap();
    let verifier = SourceVerifier::new(&sources, &mut d).unwrap();
    let mut c = closure();
    let mut e = expansion();
    let mut compiler = CaseCompiler::new(verifier, &mut c, &mut e);
    let compiled = compiler.compile(&bound.cases()[0]).unwrap();
    drop(compiler);
    let actual: observed::Observation = d.decode(OBSERVATION).unwrap();
    let mut owner = compare();
    let fault = owner
        .charge(CompareResource::StructuralVisits, usize::MAX)
        .unwrap_err();
    let before = (d.usage(), e.usage(), owner.usage());
    assert!(
        matches!(compiled.report_context().check_client_lifecycle(&actual,&mut d,&mut e,&mut owner),Err(e) if e==fault)
    );
    assert_eq!((d.usage(), e.usage(), owner.usage()), before);
    // Decoder readiness wins over a simultaneous expansion refusal; neither
    // can be replaced by the later absent authored ledger policy.
    assert!(d.bytes(usize::MAX).is_err());
    assert!(e.measure_metadata_work(usize::MAX).is_err());
    let mut owner = compare();
    let before = (d.usage(), e.usage(), owner.usage());
    assert!(matches!(
        compiled
            .report_context()
            .check_client_lifecycle(&actual, &mut d, &mut e, &mut owner),
        Err(ObservationError::Lifecycle {
            kind: LifecycleFault::DecodeWork(_),
            ..
        })
    ));
    assert_eq!((d.usage(), e.usage(), owner.usage()), before);
}

#[test]
fn historical_compilation_04_source_tokens_and_selected_run_are_not_replaceable() {
    for (input, expected, fault) in [
        (
            ORIGINALS[0].1.replacen("\"limits\":", "\"limits\": ", 1),
            ORIGINALS[0].2.to_owned(),
            "input",
        ),
        (
            ORIGINALS[0].1.to_owned(),
            ORIGINALS[0].2.replacen("\"origin\":", "\"origin\": ", 1),
            "expected",
        ),
        (ORIGINALS[0].1.to_owned(), ORIGINALS[0].2.to_owned(), "run"),
    ] {
        let (input, expected) = if fault == "run" {
            let mut i: serde_json::Value = serde_json::from_str(&input).unwrap();
            i["runs"] = serde_json::json!([i["runs"][0].clone(), i["runs"][0].clone()]);
            let mut e: serde_json::Value = serde_json::from_str(&expected).unwrap();
            e["runIndex"] = serde_json::json!(1);
            (i.to_string(), e.to_string())
        } else {
            (input, expected)
        };
        let raw = format!(
            "{{\"cases\":[{{\"id\":\"{}\",\"input\":{},\"expected\":{}}}]}}",
            ORIGINALS[0].0, input, expected
        );
        let sources = ReviewedSources::historical_selected();
        let mut d = decoder();
        let bound = BoundCorpus::decode_historical(&raw, &mut d).unwrap();
        let verifier = SourceVerifier::new(&sources, &mut d).unwrap();
        let mut c = closure();
        let mut e = expansion();
        let mut compiler = CaseCompiler::new(verifier, &mut c, &mut e);
        let before = compiler.usage();
        assert!(matches!(
            (fault, compiler.compile(&bound.cases()[0]).err().unwrap()),
            ("input", CompilationError::Source(SourceError::InputToken))
                | (
                    "expected",
                    CompilationError::Source(SourceError::ExpectedToken)
                )
                | ("run", CompilationError::Source(SourceError::ManifestCase))
        ));
        let spent = compiler.usage();
        assert_eq!(spent.closure, before.closure);
        assert_eq!(spent.expansion, before.expansion);
        assert!(compiler.compile(&bound.cases()[0]).is_err());
        assert_eq!(compiler.usage(), spent);
    }
}

#[test]
fn historical_compilation_05_fixed_source_file_digest_and_receipt_anchor_refuse_substitution() {
    let raw = corpus();
    let mut d = decoder();
    let bound = BoundCorpus::decode_historical(&raw, &mut d).unwrap();
    let replaced = format!("{}\n", ORIGINALS[0].1);
    let sources=ReviewedSources::historical_selected().with_replacement("local-historical-first-v1/cases/inspection-and-search-use-current-local-reference/input.json",replaced.as_bytes());
    let verifier = SourceVerifier::new(&sources, &mut d).unwrap();
    let mut c = closure();
    let mut e = expansion();
    let mut compiler = CaseCompiler::new(verifier, &mut c, &mut e);
    assert!(matches!(
        compiler.compile(&bound.cases()[0]),
        Err(CompilationError::Source(SourceError::SourceFileDigest))
    ));
    let sources = ReviewedSources::historical_selected()
        .with_replacement("local-historical-first-v1/bundle-receipt.json", b"{}");
    assert!(matches!(
        SourceVerifier::new(&sources, &mut decoder()),
        Err(SourceError::Anchor(
            super::super::source_proof::ReviewedAnchor::PairedReceipt
        ))
    ));
}
