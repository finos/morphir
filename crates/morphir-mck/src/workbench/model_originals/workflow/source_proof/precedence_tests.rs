//! Fixed before the typed-domain refactor. Preserve semantic refusal order.
use super::*;
use crate::workbench::model_originals::workflow::{
    DecodeLimits, Decoder, ingress::BoundCorpus, reviewed_sources::ReviewedSources,
};

fn check(raw: &str, sources: &ReviewedSources) -> Result<(), SourceError> {
    let mut owner = Decoder::new(
        DecodeLimits::new(
            16_777_216,
            1_073_741_824,
            4_000_000,
            1_073_741_824,
            4_000_000,
        )
        .unwrap(),
    );
    let bound = BoundCorpus::decode(raw, &mut owner).unwrap();
    let mut verifier = SourceVerifier::new(sources, &mut owner)?;
    verifier.bind(&bound.cases()[0]).map(|_| ())
}

#[test]
fn earlier_case_role_and_original_failures_precede_operand_file_failure() {
    let sources = ReviewedSources::selected().with_replacement(
        "connected-expected-v17-migration-v1/cases/connected-inventory-single-file-json-v3/input.json",
        include_bytes!("controls/mutations/input-without-final-lf.json"),
    );
    assert!(matches!(
        check(
            include_str!("controls/mutations/wrong-selected-role.corpus.json"),
            &sources
        ),
        Err(SourceError::ManifestRole)
    ));
    assert!(matches!(
        check(
            include_str!("controls/mutations/forged-packet-digest.corpus.json"),
            &sources
        ),
        Err(SourceError::PacketDigest)
    ));
    assert!(matches!(
        check(
            include_str!("controls/mutations/missing-original-case.corpus.json"),
            &sources
        ),
        Err(SourceError::MissingOriginalCase)
    ));
    assert!(matches!(
        check(
            include_str!("controls/mutations/cross-case-body-swap.corpus.json"),
            &sources
        ),
        Err(SourceError::ManifestCase)
    ));
    assert!(matches!(
        check(
            include_str!("controls/mutations/missing-author-row.corpus.json"),
            &sources
        ),
        Err(SourceError::MissingManifestCase)
    ));
}

#[test]
fn manifest_anchor_failure_precedes_packet_body_failure() {
    let sources = ReviewedSources::selected()
        .with_replacement("paired-source-corpus-v1/source-manifest.json", b"false")
        .with_replacement(
            "preceding60.json",
            include_bytes!("controls/mutations/preceding60-swapped-with-preceding35.json"),
        );
    assert!(matches!(
        check(
            include_str!("controls/mutations/positive-first.corpus.json"),
            &sources
        ),
        Err(SourceError::Anchor(ReviewedAnchor::Manifest))
    ));
}
