//! Raw windows reuse the existing strict reader, before any implementation.
use super::*;

#[test]
fn exact_raw_children_preserve_interior_whitespace_tokens_and_marker_objects() {
    const RAW: &str = " \n{\"input\": { \"n\":9007199254740993,\"z\":-0.0,\"e\":1e+0002,\"s\":\"\\u00e9\",\"marker\":{\"$serde_json::private::Number\":\"1\"} },\"expected\":[-0,1.00,1E2]}\r\n";
    let mut work = ReadWork::new(ReadWorkLimits::new(100_000, 1000).unwrap());
    let (document, raw) = Document::parse_exact_with_raw(RAW.as_bytes(), &mut work).unwrap();
    assert!(matches!(document, Document::Object(_)));
    let members = raw_members_with_work(raw, &mut work).unwrap();
    assert_eq!(members[0].0, "input");
    assert_eq!(
        members[0].1.get(),
        r#"{ "n":9007199254740993,"z":-0.0,"e":1e+0002,"s":"\u00e9","marker":{"$serde_json::private::Number":"1"} }"#
    );
    assert_eq!(members[1].1.get(), "[-0,1.00,1E2]");
    let values = raw_elements_with_work(members[1].1, &mut work).unwrap();
    assert_eq!(
        values.iter().map(|raw| raw.get()).collect::<Vec<_>>(),
        ["-0", "1.00", "1E2"]
    );
    for token in values {
        let start = token
            .get()
            .as_ptr()
            .addr()
            .checked_sub(RAW.as_ptr().addr())
            .unwrap();
        assert_eq!(RAW.get(start..start + token.get().len()), Some(token.get()));
    }
}

#[test]
fn raw_views_share_sticky_work_and_never_accept_decoded_duplicate_keys() {
    let mut work = ReadWork::new(ReadWorkLimits::new(100_000, 1000).unwrap());
    assert!(Document::parse_exact_with_raw(br#"{"a":0,"\u0061":1}"#, &mut work).is_err());
    let mut tiny = ReadWork::new(ReadWorkLimits::new(1, 1000).unwrap());
    assert!(matches!(
        Document::parse_exact_with_raw(b"{}", &mut tiny),
        Err(StrictReadError::Work(_))
    ));
    let spent = tiny.usage();
    assert!(matches!(
        Document::parse_exact_with_raw(b"0", &mut tiny),
        Err(StrictReadError::Work(_))
    ));
    assert_eq!(tiny.usage(), spent);
}
