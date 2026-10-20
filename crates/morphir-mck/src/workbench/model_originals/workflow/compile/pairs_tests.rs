//! Unchanged authored operands, static compiler only, never runtime evidence.
use super::super::work::ClosureLimits;
use super::super::{DecodeLimits, Decoder, domain, input};
use super::*;
use std::io::Read;

#[derive(serde::Deserialize)]
#[serde(deny_unknown_fields)]
struct Corpus {
    kind: String,
    cases: Vec<Case>,
}
#[derive(serde::Deserialize)]
#[serde(deny_unknown_fields)]
struct Case {
    id: String,
    #[serde(rename = "rawInput")]
    raw_input: String,
    #[serde(rename = "rawExpected")]
    raw_expected: String,
    #[serde(rename = "inputSHA256")]
    input_sha256: String,
    #[serde(rename = "expectedSHA256")]
    expected_sha256: String,
}

#[test]
fn all_23_unchanged_pairs_have_static_declared_reference_closure_only() {
    const ENCODED: usize = 127_043;
    const DECODED: usize = 1_244_636;
    let encoded = include_bytes!("controls/source-pairs.json.gz");
    assert_eq!(encoded.len(), ENCODED);
    assert_eq!(
        crate::kit::hash::sha256_hex(encoded),
        "6b882fee5e54737dcc14e7153aa8c0162d6b3f18727749d6f232f5e956e60b2d"
    );
    let mut decoded = Vec::with_capacity(DECODED);
    flate2::read::GzDecoder::new(encoded.as_slice())
        .take((DECODED as u64) + 1)
        .read_to_end(&mut decoded)
        .unwrap();
    assert_eq!(decoded.len(), DECODED);
    assert_eq!(
        crate::kit::hash::sha256_hex(&decoded),
        "66475701c35c08147506e42d72ca15dabf84dca692c2c42f3318d02058c537b8"
    );
    let corpus: Corpus = serde_json::from_slice(&decoded).unwrap();
    assert_eq!(
        corpus.kind,
        "all23-unchanged-source-pairs-for-static-closure-only"
    );
    assert_eq!(corpus.cases.len(), 23);
    for case in corpus.cases {
        assert_eq!(
            crate::kit::hash::sha256_hex(case.raw_input.as_bytes()),
            case.input_sha256
        );
        assert_eq!(
            crate::kit::hash::sha256_hex(case.raw_expected.as_bytes()),
            case.expected_sha256
        );
        let mut decoder = Decoder::new(
            DecodeLimits::new(
                16_777_216,
                1_073_741_824,
                4_000_000,
                1_073_741_824,
                4_000_000,
            )
            .unwrap(),
        );
        let scenario: input::Scenario = decoder
            .decode(&case.raw_input)
            .unwrap_or_else(|error| panic!("input {}: {error:?}", case.id));
        let expected: domain::ExpectedWorkflow = decoder
            .decode(&case.raw_expected)
            .unwrap_or_else(|error| panic!("expected {}: {error:?}", case.id));
        let pair = super::super::pairing::PairedWorkflow::new(&scenario, &expected).unwrap();
        let mut owner =
            ClosureOwner::new(ClosureLimits::new(100_000, 100_000, 2_000_000, 2_000_000).unwrap());
        let plan = compile(&pair, &mut owner)
            .unwrap_or_else(|error| panic!("static closure {}: {error:?}", case.id));
        assert!(!plan.definitions().is_empty());
        // Runtime bindings are obligations, not evidence that owners exist.
        for association in plan.associations() {
            assert!(association.definition.0 < plan.definitions().len());
        }
    }
}
