//! Child of genuine workflow module. Actual immutable ingress remains source.
use super::*;
use serde::Serialize;
use serde_json::value::RawValue;

#[derive(Serialize)]
struct BorrowedRequest<'a> {
    input: &'a RawValue,
}

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
fn actual_bound_input_raw_value_is_borrowed_from_original_immutable_corpus_and_serializes_verbatim()
{
    let raw = include_str!("raw_boundary_controls/positive-first.corpus.json");
    let mut decode = owner();
    let corpus = ingress::BoundCorpus::decode(raw, &mut decode).unwrap();
    let case = &corpus.cases()[0];
    let input = case.input_raw();
    assert_eq!(input.get(), case.input_token());
    assert!(std::ptr::eq(
        input.get().as_ptr(),
        case.input_token().as_ptr()
    ));
    let lower = raw.as_ptr() as usize;
    let upper = lower + raw.len();
    let start = input.get().as_ptr() as usize;
    assert!(start >= lower && start + input.get().len() <= upper);
    let serialized = serde_json::to_string(&BorrowedRequest { input }).unwrap();
    assert_eq!(serialized, format!("{{\"input\":{}}}", case.input_token()));
    assert_eq!(
        crate::kit::hash::sha256_hex(input.get().as_bytes()),
        "b5e06157888b2721fa5831a1e3504b3061310d1f171dcfe15ea6939bcd1b797b"
    );
}

#[test]
fn borrowed_raw_accessor_does_not_reparse_or_debit_the_existing_decoder() {
    let raw = include_str!("raw_boundary_controls/positive-first.corpus.json");
    let mut decode = owner();
    let corpus = ingress::BoundCorpus::decode(raw, &mut decode).unwrap();
    let before = decode.usage();
    for _ in 0..3 {
        assert_eq!(
            corpus.cases()[0].input_raw().get(),
            corpus.cases()[0].input_token()
        );
    }
    assert_eq!(decode.usage(), before);
    // The raw reference is stored from the existing duplicate-aware parse,
    // never manufactured by parsing token text again without this owner.
}
