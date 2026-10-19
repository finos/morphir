use super::*;

record! { RequiredNullable { alias: FixtureAlias => "alias", other: Nullable<FixtureAlias> => "other" } }
record! { RawPair { left: RawJson => "left", right: RawJson => "right" } }
record! { AliasList { items: Items<FixtureAlias, 1, 4> => "items" } }
words! { Mode { Current => "current", Retired => "retired" } }
literal! { Confirmed => false }
tagged! { Selection("kind") {
    Empty => "none" {},
    Selected => "selected" { model: FixtureAlias => "model", mode: Mode => "mode", inferred: Confirmed => "inferred" }
} }

fn decoder() -> Decoder {
    Decoder::new(DecodeLimits::new(4096, 65536, 4096, 65536, 4096).unwrap())
}

#[test]
fn fixture_alias_decode_reuses_the_existing_validated_domain_type() {
    let actual: crate::workbench::model_originals::FixtureAlias =
        decoder().decode("\"Root.A\"").unwrap();
    assert_eq!(
        actual,
        crate::workbench::model_originals::FixtureAlias::new("Root.A").unwrap()
    );
}

#[test]
fn closed_operands_require_explicit_null_and_refuse_extra_or_mistyped_fields() {
    let mut d = decoder();
    let parsed: RequiredNullable = d.decode(r#"{"alias":"A","other":null}"#).unwrap();
    assert_eq!(parsed.alias.as_str(), "A");
    assert!(parsed.other.0.is_none());
    for raw in [
        r#"{"alias":"A"}"#,
        r#"{"alias":"A","other":null,"passed":true}"#,
        r#"{"alias":"bad/path","other":null}"#,
        r#"{"alias":"A","other":false}"#,
    ] {
        assert!(d.decode::<RequiredNullable>(raw).is_err(), "{raw}");
    }
    assert!(matches!(
        d.decode::<Selection>(r#"{"kind":"none"}"#).unwrap(),
        Selection::Empty {}
    ));
    assert!(
        d.decode::<Selection>(r#"{"kind":"none","model":"A"}"#)
            .is_err()
    );
    assert!(
        d.decode::<Selection>(
            r#"{"kind":"selected","model":"A","mode":"current","inferred":false}"#
        )
        .is_ok()
    );
    assert!(
        d.decode::<Selection>(
            r#"{"kind":"selected","model":"A","mode":"current","inferred":true}"#
        )
        .is_err()
    );
}

#[test]
fn counts_use_exact_decimal_integrality_without_float_rounding_or_marker_coercion() {
    let mut d = decoder();
    for (raw, expected) in [
        ("1.0", 1),
        ("1e0", 1),
        ("-0", 0),
        ("9007199254740991", 9007199254740991),
    ] {
        assert_eq!(
            d.decode::<Natural<0, 9007199254740991>>(raw).unwrap().0,
            expected
        );
    }
    for raw in [
        "9007199254740991.1",
        "9007199254740992",
        "1e999999",
        "-1",
        r#"{"$serde_json::private::Number":"1"}"#,
        "1e9223372036854775807",
        "11e9223372036854775807",
        "1e9223372036854775808",
    ] {
        assert!(
            d.decode::<Natural<0, 9007199254740991>>(raw).is_err(),
            "{raw}"
        );
    }
}

#[test]
fn embedded_json_uses_the_same_owner_and_exhaustion_remains_sticky() {
    let mut d = Decoder::new(DecodeLimits::new(4096, 65536, 4, 65536, 4096).unwrap());
    assert!(matches!(
        d.decode::<RawPair>(r#"{"left":"0","right":"0"}"#),
        Err(DecodeError::Literal(
            crate::json::strict::StrictReadError::Work(
                crate::json::strict::ReadWorkResource::Values
            )
        ))
    ));
    let spent = d.usage();
    assert_eq!(spent.literal.values, 4);
    assert!(d.decode::<RawPair>(r#"{"left":"0","right":"0"}"#).is_err());
    assert_eq!(d.usage(), spent);
}

#[test]
fn aggregate_array_slots_are_reserved_before_any_child_decode() {
    let mut d = Decoder::new(DecodeLimits::new(4096, 65536, 4096, 65536, 1).unwrap());
    // The first alias is independently invalid. The whole-array reservation
    // must refuse first, before invoking even that child's constructor.
    assert!(matches!(
        d.decode::<AliasList>(r#"{"items":["bad/path","B"]}"#),
        Err(DecodeError::Work(OperandResource::Slots))
    ));
}

#[test]
fn indirect_operand_slot_is_reserved_before_its_child_or_heap_allocation() {
    let mut d = Decoder::new(DecodeLimits::new(4096, 65536, 4096, 65536, 1).unwrap());
    let Items(values) = d.decode::<Items<JsonNull, 1, 1>>("[null]").unwrap();
    assert_eq!(values.len(), 1);
    // Null is independently wrong for JsonBool. Exhaustion must win before
    // that constructor, and a boxed payload cannot bypass the common owner.
    assert!(matches!(
        d.decode::<Box<JsonBool>>("null"),
        Err(DecodeError::Work(OperandResource::Slots))
    ));
    let mut d = decoder();
    let value = d.decode::<Box<JsonBool>>("true").unwrap();
    assert!(value.0);
    assert_eq!(d.usage().slots, 1);
}

#[test]
fn shared_roles_validate_aliases_paths_hashes_and_full_u64_tokens() {
    let mut d = decoder();
    for raw in [r#""9bad""#, r#"".bad""#, r#""bad/path""#, r#""""#] {
        assert!(d.decode::<FixtureAlias>(raw).is_err());
    }
    assert!(d.decode::<FixtureAlias>(r#""A-9._""#).is_ok());
    let U64Token(id) = d.decode(r#""18446744073709551615""#).unwrap();
    assert_eq!(id.get(), u64::MAX);
    for raw in [
        r#""18446744073709551616""#,
        r#""01""#,
        "1",
        r#""-1""#,
        r#""""#,
    ] {
        assert!(d.decode::<U64Token>(raw).is_err());
    }
    let SourcePath(path) = d.decode(r#""models/example.json""#).unwrap();
    assert_eq!(path.as_str(), "models/example.json");
    for raw in [r#""../secrets.json""#, r#""a/../b""#, r#""CON.json""#] {
        assert!(d.decode::<SourcePath>(raw).is_err());
    }
    let ContentSha256(bytes) = d
        .decode(r#""000000000000000000000000000000000000000000000000000000000000000a""#)
        .unwrap();
    assert_eq!(bytes[31], 10);
    assert!(
        d.decode::<ContentSha256>(
            r#""000000000000000000000000000000000000000000000000000000000000000A""#
        )
        .is_err()
    );
}

#[test]
fn unique_lists_compare_literal_values_and_latch_comparison_work_refusal() {
    let mut d = decoder();
    let UniqueItems(values) = d
        .decode::<UniqueItems<Text<1, 20>, 0, 10>>(r#"["c","a","b"]"#)
        .unwrap();
    assert_eq!(
        values
            .iter()
            .map(|value| value.0.as_str())
            .collect::<Vec<_>>(),
        ["c", "a", "b"]
    );
    assert!(
        d.decode::<UniqueItems<Text<1, 20>, 0, 10>>(r#"["b","a","\u0062"]"#)
            .is_err()
    );
    assert!(
        d.decode::<UniqueItems<Mode, 1, 3>>(r#"["current","retired","current"]"#)
            .is_err()
    );
    let mut d = Decoder::new(DecodeLimits::new(1000, 10000, 100, 3, 100).unwrap());
    assert!(matches!(
        d.decode::<UniqueItems<Text<1, 20>, 0, 10>>(r#"["a","b"]"#),
        Err(DecodeError::Work(OperandResource::ByteVisits))
    ));
    let usage = d.usage();
    assert!(d.decode::<JsonNull>("null").is_err());
    assert_eq!(d.usage(), usage);
}

#[test]
fn patterned_text_and_disposition_factoring_preserve_every_closed_literal() {
    let mut d = decoder();
    assert!(
        d.decode::<domain::AtomicBytes>(r#"{"kind":"hex","hex":"00ff"}"#)
            .is_ok()
    );
    for raw in [
        r#"{"kind":"hex","hex":"0"}"#,
        r#"{"kind":"hex","hex":"FF"}"#,
    ] {
        assert!(d.decode::<domain::AtomicBytes>(raw).is_err());
    }
    for raw in [
        r#"{"stage":"ingress-request","disposition":{"kind":"accepted","code":null}}"#,
        r#"{"stage":"ingress-request","disposition":{"kind":"refused","code":"model_originals.invalid_request"}}"#,
        r#"{"stage":"egress-reply","disposition":{"kind":"refused","code":"model_originals.reply_limit"}}"#,
    ] {
        assert!(
            d.decode::<domain::ExpectedServerCheckProducerMessageBoundaryBoundary>(raw)
                .is_ok(),
            "{raw}"
        );
    }
    assert!(d.decode::<domain::ExpectedServerCheckProducerMessageBoundaryBoundary>(r#"{"stage":"ingress-request","disposition":{"kind":"refused","code":"model_originals.reply_limit"}}"#).is_err());
}
