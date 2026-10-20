//! Additive prospective test of the real compiled-context checker boundary.
//! It does not establish a selected published envelope/report or runtime pass.
use super::expansion::{ExpansionLimits, ExpansionOwner, ReadExpansionLimits};
use super::ingress::BoundCorpus;
use super::observation_check::{CompareLimits, CompareOwner, CompareResource, ObservationError};
use super::reviewed_sources::ReviewedSources;
use super::source_compile::CaseCompiler;
use super::source_proof::{LineageStatus, SourceVerifier};
use super::work::{ClosureLimits, ClosureOwner};
use super::*;

const INCOMPLETE_CLIENT_OBSERVATION: &str = r#"{"role":"model-originals-client","outbound":[],"effects":[],"checkpoints":[{"name":"owned-transport-and-workers-exited","currentOpening":null,"currentModel":null,"owner":{"kind":"none"},"pendingEffects":[],"preparedCoreEffects":[],"heldCoreResultBytes":0,"eventCount":0,"executionOwner":{"kind":"none"},"captureCleanup":{"kind":"none"},"navigation":{"inspectionOwner":null,"searchOwner":null,"outputOwner":null,"destinationCount":0}}],"downloads":[],"coreResults":[],"richOwners":[],"outcome":{"kind":"clean","finalCheckpoint":"owned-transport-and-workers-exited"},"teardown":{"kind":"confirmed","pendingEffects":0,"heldCoreResults":0,"stillOwnedWorkers":0,"workersStarted":0,"workersExited":0,"disposedTransports":0,"productReleaseInferred":false}}"#;

#[test]
fn compiled_context_preserves_genuine_blocked_source_and_first_comparison_fault() {
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
    assert!(std::ptr::eq(
        context.input_raw(),
        bound.cases()[0].input_raw()
    ));

    // The source independently requires strong nonempty workflow evidence and
    // explicitly retains qualification.blocked. This deliberately incomplete
    // typed observation must never be relabelled a whole-case pass.
    let actual = decode
        .decode::<observed::Observation>(INCOMPLETE_CLIENT_OBSERVATION)
        .unwrap();
    let changed_raw = INCOMPLETE_CLIENT_OBSERVATION.replace("\"eventCount\":0", "\"eventCount\":1");
    let changed = decode
        .decode::<observed::Observation>(&changed_raw)
        .unwrap();
    let mut compare = CompareOwner::new(CompareLimits::new(100_000, 1_000_000, 100_000).unwrap());
    assert!(matches!(
        context.check_observation(&actual, &mut compare),
        Err(ObservationError::ExpectedBlocked)
    ));
    let spent = compare.usage();
    assert!(matches!(
        context.check_observation(&changed, &mut compare),
        Err(ObservationError::ExpectedBlocked)
    ));
    assert_eq!(compare.usage(), spent);
    assert_eq!(context.lineage(), LineageStatus::Unproven);

    // A genuine different caller-owned comparison policy can refuse even
    // before the blocked predicate. It is not issued by any saved metadata.
    let mut exhausted = CompareOwner::new(CompareLimits::new(0, 0, 0).unwrap());
    assert!(matches!(
        context.check_observation(&actual, &mut exhausted),
        Err(ObservationError::Resource(
            CompareResource::StructuralVisits
        ))
    ));
    let spent = exhausted.usage();
    assert!(matches!(
        context.check_observation(&changed, &mut exhausted),
        Err(ObservationError::Resource(
            CompareResource::StructuralVisits
        ))
    ));
    assert_eq!(exhausted.usage(), spent);
}
