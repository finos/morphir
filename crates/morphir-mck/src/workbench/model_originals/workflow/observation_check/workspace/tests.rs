//! Source-derived UTF8 tuple and pre-effect work controls. No UI invocation.
use super::*;
use crate::workbench::model_originals::workflow::{DecodeLimits, Decoder};

fn source() -> input::IdentitySourceSnapshot {
    Decoder::new(DecodeLimits::new(4096, 100_000, 1000, 100_000, 1000).unwrap())
        .decode::<input::IdentitySourceSnapshot>(
            r#"{"providerId":"é","locator":"😀","displayName":"ignored","persistence":"session"}"#,
        )
        .unwrap()
}
#[test]
fn canonical_tuple_comparison_preserves_unicode_and_exact_precharged_work() {
    let source = source();
    // Fixed literal UTF8: input words2+4=6, exact tuple13 bytes. The same
    // serializer emits13 bytes and the sink compares13 actual bytes:32 total.
    let mut exact = CompareOwner::new(CompareLimits::new(1, 32, 0).unwrap());
    assert!(canonical_key(&source, None, "[\"é\",\"😀\"]", &mut exact).unwrap());
    assert_eq!(exact.usage().visits, 1);
    assert_eq!(exact.usage().comparison_bytes, 32);
    let mut short = CompareOwner::new(CompareLimits::new(1, 31, 0).unwrap());
    assert_eq!(
        canonical_key(&source, None, "[\"é\",\"😀\"]", &mut short),
        Err(ObservationError::Resource(CompareResource::ComparisonBytes))
    );
    // Last emitted ']' needs2 comparison bytes. No debit after refusal.
    assert_eq!(short.usage().comparison_bytes, 30);
    let before = short.usage();
    assert_eq!(
        canonical_key(&source, Some("ignored-after-fault"), "x", &mut short),
        Err(ObservationError::Resource(CompareResource::ComparisonBytes))
    );
    assert_eq!(short.usage(), before);
}

#[test]
fn canonical_tuple_compares_control_escapes_paths_and_normalization_literally() {
    let mut decode = Decoder::new(DecodeLimits::new(4096, 100_000, 1000, 100_000, 1000).unwrap());
    let source = decode
        .decode::<input::IdentitySourceSnapshot>(
            r#"{"providerId":"a\"b","locator":"x\u0000y","displayName":"ignored"}"#,
        )
        .unwrap();
    let mut owner = CompareOwner::new(CompareLimits::new(100, 100_000, 0).unwrap());
    assert!(
        canonical_key(
            &source,
            Some("a/b"),
            r#"["a\"b","x\u0000y","a/b"]"#,
            &mut owner
        )
        .unwrap()
    );
    assert!(
        !canonical_key(
            &source,
            Some("a/b"),
            r#"["a\"b","x\u0000y","a\\b"]"#,
            &mut owner
        )
        .unwrap()
    );
    let unicode = super::tests::source();
    assert!(!canonical_key(&unicode, None, "[\"e\u{301}\",\"😀\"]", &mut owner).unwrap());
}
