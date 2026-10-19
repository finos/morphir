// Source-only setup corpus. These tests establish decoding and metadata pairing only.
// No compiler/reference proof, provenance verification, provider authority or runtime claim.
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
    generation: String,
    #[serde(rename = "rawInput")]
    raw_input: String,
    #[serde(rename = "rawExpected")]
    raw_expected: String,
    #[serde(rename = "inputBytes")]
    input_bytes: usize,
    #[serde(rename = "expectedBytes")]
    expected_bytes: usize,
    #[serde(rename = "inputSHA256")]
    input_sha256: String,
    #[serde(rename = "expectedSHA256")]
    expected_sha256: String,
    #[serde(rename = "originPacket")]
    origin_packet: String,
    #[serde(rename = "originSHA256")]
    origin_sha256: String,
    #[serde(rename = "originId")]
    origin_id: String,
    #[serde(rename = "runIndex")]
    run_index: usize,
    role: String,
    #[serde(rename = "actionCount")]
    action_count: usize,
}
#[test]
fn frozen_23_source_pairs_decode_and_select_exact_origin_run_role_only() {
    const ENCODED_SIZE: usize = 129426;
    const DECODED_SIZE: usize = 1251395;
    let encoded = include_bytes!("cases.json.gz");
    assert_eq!(encoded.len(), ENCODED_SIZE);
    assert_eq!(
        crate::kit::hash::sha256_hex(encoded),
        "10b055a43bc6152e7615075b7ab0686b7d583b43d170d02a47e5604a7a3b3078"
    );
    let mut bytes = Vec::with_capacity(DECODED_SIZE);
    flate2::read::GzDecoder::new(encoded.as_slice())
        .take((DECODED_SIZE as u64) + 1)
        .read_to_end(&mut bytes)
        .unwrap();
    assert_eq!(bytes.len(), DECODED_SIZE);
    assert_eq!(
        crate::kit::hash::sha256_hex(&bytes),
        "355968023861bc8e5069d56ef50a388c204659ed2e1ae3c491f3c93075158a66"
    );
    let corpus: Corpus = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(corpus.kind, "exact-source-pairs-origin-run-role-only");
    assert_eq!(corpus.cases.len(), 23);
    let mut migrated = 0;
    let mut original = 0;
    for case in corpus.cases {
        match case.generation.as_str() {
            "migrated-v16" => migrated += 1,
            "original-v17" => original += 1,
            _ => panic!("unknown frozen source generation"),
        }
        assert_eq!(case.raw_input.len(), case.input_bytes);
        assert_eq!(case.raw_expected.len(), case.expected_bytes);
        assert_eq!(
            crate::kit::hash::sha256_hex(case.raw_input.as_bytes()),
            case.input_sha256
        );
        assert_eq!(
            crate::kit::hash::sha256_hex(case.raw_expected.as_bytes()),
            case.expected_sha256
        );
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
        let scenario: input::Scenario = owner
            .decode(&case.raw_input)
            .unwrap_or_else(|error| panic!("input {}: {error:?}", case.id));
        let expected: domain::ExpectedWorkflow = owner
            .decode(&case.raw_expected)
            .unwrap_or_else(|error| panic!("expected {}: {error:?}", case.id));
        let fixed_digest: decode::ContentSha256 = owner
            .decode(&format!("\"{}\"", case.origin_sha256))
            .unwrap();
        assert_eq!(scenario.origin.packet.key(), case.origin_packet);
        assert_eq!(scenario.origin.id.0, case.origin_id);
        assert_eq!(scenario.origin.sha256, fixed_digest);
        let paired = pairing::PairedWorkflow::new(&scenario, &expected)
            .unwrap_or_else(|error| panic!("pair {}: {error:?}", case.id));
        // Explicit test-only compiler ceilings, independent of scenario claims.
        // This checks recipe/read-plan expansion, not authority or runtime work.
        let limits = expansion::ExpansionLimits::new(
            1_073_741_824,
            1_073_741_824,
            1_073_741_824,
            1_000_000,
            1_000_000,
        )
        .with_reads(expansion::ReadExpansionLimits::new(
            8192,
            1_073_741_824,
            4_294_967_296,
            8_589_934_592,
        ));
        let mut expansion = expansion::ExpansionOwner::new(limits);
        expansion::ScenarioExpansion::measure(&scenario, &mut expansion)
            .unwrap_or_else(|error| panic!("expansion {}: {error:?}", case.id));
        assert_eq!(paired.run_index(), case.run_index);
        match (&expected, paired.run(), &scenario.runs.0[case.run_index]) {
            (
                domain::ExpectedWorkflow::ModelOriginalsClient {
                    origin, run_index, ..
                },
                pairing::PairedRun::Client { actions, fixture },
                input::Run::ModelOriginalsClient {
                    actions: source_actions,
                    fixture: source_fixture,
                },
            ) => {
                assert_eq!(case.role, "model-originals-client");
                assert_eq!(run_index.0, case.run_index as u64);
                assert_eq!(origin.packet.key(), case.origin_packet);
                assert_eq!(origin.id.0, case.origin_id);
                assert_eq!(origin.sha256, fixed_digest);
                assert_eq!(actions.len(), case.action_count);
                assert!(std::ptr::eq(actions, source_actions.0.as_slice()));
                assert!(std::ptr::eq(fixture, source_fixture));
            }
            _ => panic!("frozen client source role/run mismatch {}", case.id),
        }
    }
    assert_eq!(migrated, 20);
    assert_eq!(original, 3);
}
