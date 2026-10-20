//! Fixed source-proof controls. No compiler execution or runtime qualification.
use super::*;
use crate::workbench::model_originals::workflow::{
    DecodeError, DecodeLimits, Decoder, OperandResource, ingress::BoundCorpus,
    reviewed_sources::ReviewedSources,
};

const ALL: &str = include_str!("controls/bound-corpus.json");
const FIRST_INPUT_PATH: &str =
    "connected-expected-v17-migration-v1/cases/connected-inventory-single-file-json-v3/input.json";
const FIRST_EXPECTED_PATH: &str = "connected-expected-v17-migration-v1/cases/connected-inventory-single-file-json-v3/expected.json";

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
fn disposition(raw: &str, sources: &ReviewedSources) -> Result<(), SourceError> {
    let mut owner = decoder();
    let bound = BoundCorpus::decode(raw, &mut owner).unwrap();
    let mut verifier = SourceVerifier::new(sources, &mut owner)?;
    verifier.bind(&bound.cases()[0]).map(|_| ())
}

#[test]
fn all23_exact_sources_match_original_membership_without_semantic_lineage_claim() {
    assert_eq!(ALL.len(), 1_088_406);
    assert_eq!(
        crate::kit::hash::sha256_hex(ALL.as_bytes()),
        "23ff40458b12c5d179817cf9de328fb063b6daa374ffbd96998c32bc1bb7f50a"
    );
    let sources = ReviewedSources::selected();
    let mut owner = decoder();
    let bound = BoundCorpus::decode(ALL, &mut owner).unwrap();
    let mut verifier = SourceVerifier::new(&sources, &mut owner).unwrap();
    assert_eq!(verifier.packet_count(), 4);
    assert_eq!(verifier.original_case_count(), 151);
    assert_eq!(bound.cases().len(), 23);
    for case in bound.cases() {
        let matched = verifier.bind(case).unwrap();
        assert!(std::ptr::eq(matched.case(), case));
        assert_eq!(matched.lineage(), LineageStatus::Unproven);
    }
    // These counts are exact frozen source facts, never 151/175 executed roles.
}

#[test]
fn full_file_identity_and_exact_token_identity_are_distinct_fixed_witnesses() {
    let mut owner = decoder();
    let bound = BoundCorpus::decode(ALL, &mut owner).unwrap();
    let first = &bound.cases()[0];
    assert_eq!(first.id(), "connected-inventory-single-file-json-v3");
    assert_eq!(
        crate::kit::hash::sha256_hex(first.input_token().as_bytes()),
        "b5e06157888b2721fa5831a1e3504b3061310d1f171dcfe15ea6939bcd1b797b"
    );
    assert_eq!(
        crate::kit::hash::sha256_hex(first.expected_token().as_bytes()),
        "c5c6b2cbdbdcaad1e31c2c95e2385579a06b840c00c01e2b1450e01e083e7339"
    );
    let input_file =
        include_bytes!("controls/pairs/connected-inventory-single-file-json-v3.input.json");
    let expected_file =
        include_bytes!("controls/pairs/connected-inventory-single-file-json-v3.expected.json");
    assert_eq!(
        crate::kit::hash::sha256_hex(input_file),
        "7e32dd1de9b4910fbe1bdfb644cda794f0e706133ffa6337b3b4993384f29be3"
    );
    assert_eq!(
        crate::kit::hash::sha256_hex(expected_file),
        "09d4d9e98b1906adbff44406274df1b025d1f49301a36feb3bfd807c16807b90"
    );
    assert_eq!(input_file.last(), Some(&b'\n'));
    assert_eq!(expected_file.last(), Some(&b'\n'));
    assert_eq!(
        &input_file[..input_file.len() - 1],
        first.input_token().as_bytes()
    );
    assert_eq!(
        &expected_file[..expected_file.len() - 1],
        first.expected_token().as_bytes()
    );
}

#[test]
fn removing_only_source_file_lf_refuses_even_with_identical_json_tokens() {
    let raw = include_str!("controls/mutations/positive-first.corpus.json");
    for (path, bytes) in [
        (
            FIRST_INPUT_PATH,
            include_bytes!("controls/mutations/input-without-final-lf.json").as_slice(),
        ),
        (
            FIRST_EXPECTED_PATH,
            include_bytes!("controls/mutations/expected-without-final-lf.json").as_slice(),
        ),
    ] {
        let sources = ReviewedSources::selected().with_replacement(path, bytes);
        assert!(matches!(
            disposition(raw, &sources),
            Err(SourceError::SourceFileDigest)
        ));
    }
}

#[test]
fn semantically_equal_bound_token_with_interior_space_is_not_source_equal() {
    assert!(matches!(
        disposition(
            include_str!("controls/mutations/interior-input-space.corpus.json"),
            &ReviewedSources::selected()
        ),
        Err(SourceError::InputToken)
    ));
}

#[test]
fn equally_forged_paired_digest_cannot_replace_actual_original_packet() {
    assert!(matches!(
        disposition(
            include_str!("controls/mutations/forged-packet-digest.corpus.json"),
            &ReviewedSources::selected()
        ),
        Err(SourceError::PacketDigest)
    ));
}

#[test]
fn missing_original_id_is_not_supplied_by_a_matching_author_case_label() {
    assert!(matches!(
        disposition(
            include_str!("controls/mutations/missing-original-case.corpus.json"),
            &ReviewedSources::selected()
        ),
        Err(SourceError::MissingOriginalCase)
    ));
}

#[test]
fn intact_second_pair_under_first_case_id_refuses_manifest_correspondence() {
    assert!(matches!(
        disposition(
            include_str!("controls/mutations/cross-case-body-swap.corpus.json"),
            &ReviewedSources::selected()
        ),
        Err(SourceError::ManifestCase)
    ));
}

#[test]
fn real_server_pair_does_not_satisfy_a_reviewed_client_source_role() {
    assert!(matches!(
        disposition(
            include_str!("controls/mutations/wrong-selected-role.corpus.json"),
            &ReviewedSources::selected()
        ),
        Err(SourceError::ManifestRole)
    ));
}

#[test]
fn undeclared_authored_case_has_no_global_origin_fallback() {
    assert!(matches!(
        disposition(
            include_str!("controls/mutations/missing-author-row.corpus.json"),
            &ReviewedSources::selected()
        ),
        Err(SourceError::MissingManifestCase)
    ));
}

#[test]
fn replacing_actual_packet_bytes_refuses_before_case_membership() {
    let sources = ReviewedSources::selected().with_replacement(
        "preceding60.json",
        include_bytes!("controls/mutations/preceding60-swapped-with-preceding35.json"),
    );
    assert!(matches!(
        disposition(
            include_str!("controls/mutations/positive-first.corpus.json"),
            &sources
        ),
        Err(SourceError::PacketDigest)
    ));
}

#[test]
fn rewritten_receipt_and_packet_cannot_replace_the_reviewed_parent_anchor() {
    let sources = ReviewedSources::selected()
        .with_replacement(
            "preceding60.json",
            include_bytes!("controls/mutations/preceding60-plus-space.json"),
        )
        .with_replacement(
            "acceptance/provenance.json",
            include_bytes!("controls/mutations/self-consistent-rewritten-provenance.json"),
        );
    assert!(matches!(
        disposition(
            include_str!("controls/mutations/positive-first.corpus.json"),
            &sources
        ),
        Err(SourceError::Anchor(ReviewedAnchor::Acceptance))
    ));
}

#[test]
fn the_same_verifier_owner_latches_first_fault_before_source_or_shape_work() {
    let mut owner = Decoder::new(
        DecodeLimits::new(16_777_216, 1_073_741_824, 4_000_000, 1, 4_000_000).unwrap(),
    );
    let sources = ReviewedSources::selected();
    assert!(matches!(
        SourceVerifier::new(&sources, &mut owner),
        Err(SourceError::Decode(DecodeError::Work(
            OperandResource::ByteVisits
        )))
    ));
    let spent = owner.usage();
    let malformed =
        ReviewedSources::selected().with_replacement("acceptance/provenance.json", b"false");
    assert!(matches!(
        SourceVerifier::new(&malformed, &mut owner),
        Err(SourceError::Decode(DecodeError::Work(
            OperandResource::ByteVisits
        )))
    ));
    assert_eq!(owner.usage(), spent);
}
