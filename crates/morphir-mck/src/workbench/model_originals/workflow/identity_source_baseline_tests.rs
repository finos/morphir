//! Source-order-derived CURRENT API controls, frozen before execution.
//! Old component origins remain historical and never gain source provenance.
use super::reviewed_sources::ReviewedSources;
use super::source_proof::{SourceError, SourceVerifier};
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
fn unchanged_old_components_fail_original_packet_membership_before_manifest_lookup() {
    for raw in [
        include_str!("identity_source_controls/provider-old-component.corpus.json"),
        include_str!("identity_source_controls/metadata-old-component.corpus.json"),
        include_str!("identity_source_controls/paths-old-component.corpus.json"),
    ] {
        let mut decode = owner();
        let bound = ingress::BoundCorpus::decode(raw, &mut decode).unwrap();
        let sources = ReviewedSources::selected();
        let mut verifier = SourceVerifier::new(&sources, &mut decode).unwrap();
        assert!(matches!(
            verifier.bind(&bound.cases()[0]),
            Err(SourceError::MissingOriginalCase)
        ));
    }
}
#[test]
fn corrected_original60_component_origin_still_has_no_reviewed_manifest_membership() {
    for raw in [
        include_str!("identity_source_controls/provider-correct-origin-component.corpus.json"),
        include_str!("identity_source_controls/metadata-correct-origin-component.corpus.json"),
        include_str!("identity_source_controls/paths-correct-origin-component.corpus.json"),
    ] {
        let mut decode = owner();
        let bound = ingress::BoundCorpus::decode(raw, &mut decode).unwrap();
        let sources = ReviewedSources::selected();
        let mut verifier = SourceVerifier::new(&sources, &mut decode).unwrap();
        assert!(matches!(
            verifier.bind(&bound.cases()[0]),
            Err(SourceError::MissingManifestCase)
        ));
    }
}
