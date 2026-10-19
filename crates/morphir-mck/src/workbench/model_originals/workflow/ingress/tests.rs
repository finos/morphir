//! Independently authored before the staged ingress exists. No runtime claims.
use super::*;
use crate::workbench::model_originals::workflow::{DecodeLimits, Decoder, pairing::PairError};

const RAW: &str = include_str!("controls/corpus.json");
const INPUT: &str = include_str!("controls/input-token.json");
const EXPECTED: &str = include_str!("controls/expected-token.json");

fn owner() -> Decoder {
    Decoder::new(
        DecodeLimits::new(1_048_576, 67_108_864, 1_000_000, 67_108_864, 1_000_000).unwrap(),
    )
}
fn envelope(id: &str, input: &str, expected: &str) -> String {
    format!(r#"{{"cases":[{{"id":"{id}","input":{input},"expected":{expected}}}]}}"#)
}

#[test]
fn retained_corpus_and_borrowed_tokens_are_exact_not_reserialized() {
    let mut decoder = owner();
    let corpus = BoundCorpus::decode(RAW, &mut decoder).unwrap();
    assert_eq!(corpus.raw(), RAW);
    assert_eq!(corpus.raw().as_ptr(), RAW.as_ptr());
    assert_eq!(corpus.cases().len(), 1);
    let case = &corpus.cases()[0];
    assert_eq!(case.id(), "case-A");
    assert_eq!(case.input_token(), INPUT);
    assert_eq!(case.expected_token(), EXPECTED);
    for token in [case.input_token(), case.expected_token()] {
        let start = token
            .as_ptr()
            .addr()
            .checked_sub(RAW.as_ptr().addr())
            .unwrap();
        let end = start.checked_add(token.len()).unwrap();
        assert_eq!(RAW.get(start..end), Some(token));
    }
    let paired = case.paired().unwrap();
    assert_eq!(paired.run_index(), 0);
    assert!(matches!(
        paired.run(),
        super::super::pairing::PairedRun::Server { .. }
    ));
    assert!(decoder.usage().literal.decode_bytes > RAW.len());
}

#[test]
fn expected_operand_is_direct_v17_not_an_observation_wrapper() {
    let wrapper = format!(r#"{{"status":"ok","value":{EXPECTED}}}"#);
    assert!(matches!(
        BoundCorpus::decode(&envelope("case-A", INPUT, &wrapper), &mut owner()),
        Err(IngressError::Decode(_))
    ));
}

#[test]
fn envelope_and_case_fields_are_closed_and_required() {
    for raw in [
        "{}".to_owned(),
        r#"{"cases":[],"extra":false}"#.to_owned(),
        r#"{"cases":[{"id":"case-A"}]}"#.to_owned(),
        format!(
            r#"{{"cases":[{{"id":"case-A","input":{INPUT},"expected":{EXPECTED},"extra":null}}]}}"#
        ),
        format!(r#"{{"cases":[{{"input":{INPUT},"expected":{EXPECTED}}}]}}"#),
        format!(r#"{{"cases":[{{"id":null,"input":{INPUT},"expected":{EXPECTED}}}]}}"#),
    ] {
        assert!(matches!(
            BoundCorpus::decode(&raw, &mut owner()),
            Err(IngressError::Decode(_))
        ));
    }
}

#[test]
fn duplicate_decoded_names_and_duplicate_case_ids_refuse() {
    for raw in [
        r#"{"cases":[],"cases":[]}"#.to_owned(),
        r#"{"cases":[],"cas\u0065s":[]}"#.to_owned(),
        format!(
            r#"{{"cases":[{{"id":"case-A","id":"case-A","input":{INPUT},"expected":{EXPECTED}}}]}}"#
        ),
    ] {
        assert!(matches!(
            BoundCorpus::decode(&raw, &mut owner()),
            Err(IngressError::Decode(_))
        ));
    }
    let row = format!(r#"{{"id":"case-A","input":{INPUT},"expected":{EXPECTED}}}"#);
    let duplicate = format!(r#"{{"cases":[{row},{row}]}}"#);
    assert!(matches!(
        BoundCorpus::decode(&duplicate, &mut owner()),
        Err(IngressError::DuplicateCase)
    ));
}

#[test]
fn real_pairing_rejects_selected_run_and_origin_mismatch() {
    let wrong_run = EXPECTED.replace(r#""runIndex":0"#, r#""runIndex":1"#);
    assert_ne!(wrong_run, EXPECTED);
    assert!(matches!(
        BoundCorpus::decode(&envelope("case-A", INPUT, &wrong_run), &mut owner()),
        Err(IngressError::Pair(PairError::RunIndex))
    ));
    let wrong_origin = EXPECTED.replace("static-reference-component-v1", "different-original");
    assert!(matches!(
        BoundCorpus::decode(&envelope("case-A", INPUT, &wrong_origin), &mut owner()),
        Err(IngressError::Pair(PairError::Case))
    ));
}

#[test]
fn exact_bindings_do_not_reinterpret_equal_forged_origin_claims_as_authenticity() {
    let old = "a4a98e2e5d021673c6d6e9eab8605d22f43e44073b38143f53ff17b7bde4e092";
    let zero = "0000000000000000000000000000000000000000000000000000000000000000";
    let input = INPUT.replace(old, zero);
    let expected = EXPECTED.replace(old, zero);
    assert_ne!(input, INPUT);
    assert_ne!(expected, EXPECTED);
    let raw = envelope("case-A", &input, &expected);
    let corpus = BoundCorpus::decode(&raw, &mut owner()).unwrap();
    let case = &corpus.cases()[0];
    assert_eq!(case.input_token(), input);
    assert_eq!(case.expected_token(), expected);
    assert!(case.paired().is_ok());
    // This type binds parent-selected bytes only. Original151 packet and
    // authored-manifest membership still require their independent proof.
}

#[test]
fn cumulative_decoder_fault_precedes_shape_dispatch_and_stops_retries() {
    let mut decoder =
        Decoder::new(DecodeLimits::new(1_048_576, 1, 1_000_000, 67_108_864, 1_000_000).unwrap());
    assert!(matches!(
        BoundCorpus::decode(RAW, &mut decoder),
        Err(IngressError::Decode(super::super::DecodeError::Literal(
            crate::json::strict::StrictReadError::Work(_)
        )))
    ));
    let spent = decoder.usage();
    assert!(matches!(
        BoundCorpus::decode("false", &mut decoder),
        Err(IngressError::Decode(super::super::DecodeError::Literal(
            crate::json::strict::StrictReadError::Work(_)
        )))
    ));
    assert_eq!(decoder.usage(), spent);
}
