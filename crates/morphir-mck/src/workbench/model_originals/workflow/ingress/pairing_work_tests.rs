use super::super::{DecodeLimits, OperandResource};
use super::*;

fn owner(byte_visits: usize) -> Decoder {
    Decoder::new(
        DecodeLimits::new(1_048_576, 67_108_864, 1_000_000, byte_visits, 1_000_000).unwrap(),
    )
}

#[test]
fn existing_pair_comparisons_spend_exact_precharged_bytes_and_stop_after_refusal() {
    let corpus =
        BoundCorpus::decode(include_str!("controls/corpus.json"), &mut owner(67_108_864)).unwrap();
    let case = &corpus.cases()[0];
    // Fixed source: two 8-byte "additive" keys, two actual 32-byte digests
    // and two 29-byte "static-reference-component-v1" IDs. 16+64+58=138.
    let mut exact = owner(138);
    assert!(case.paired_with_work(&mut exact).is_ok());
    assert_eq!(exact.usage().byte_visits, 138);
    let mut short = owner(137);
    assert!(matches!(
        case.paired_with_work(&mut short),
        Err(IngressError::Decode(DecodeError::Work(
            OperandResource::ByteVisits
        )))
    ));
    assert_eq!(short.usage().byte_visits, 109);
    let before = short.usage();
    assert!(matches!(
        case.paired_with_work(&mut short),
        Err(IngressError::Decode(DecodeError::Work(
            OperandResource::ByteVisits
        )))
    ));
    assert_eq!(short.usage(), before);
}
