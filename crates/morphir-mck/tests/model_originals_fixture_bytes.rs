//! Independent literal controls for the connected corpus's byte vocabulary.
//! These checks qualify fixture interpretation, never a host or a model codec.
use morphir_mck::workbench::model_originals::{
    ExpectedBytes, FixtureByteError, FixtureByteLimits, FixtureBytes,
};

fn limits(expanded: usize) -> FixtureByteLimits {
    FixtureByteLimits::new(4096, expanded, 32).unwrap()
}
fn check(recipe: &str, actual: &[u8]) {
    let recipe = FixtureBytes::parse(recipe, limits(1024 * 1024)).unwrap();
    assert_eq!(recipe.byte_length(), actual.len());
    let expected = recipe.expected().unwrap();
    assert!(expected.matches(actual));
    let mut changed = actual.to_vec();
    changed.push(0);
    assert!(!expected.matches(&changed));
    if !actual.is_empty() {
        changed.pop();
        changed[actual.len() - 1] ^= 1;
        assert!(!expected.matches(&changed));
    }
}

#[test]
fn literal_hex_and_utf8_are_exact_bytes_including_empty_and_nul() {
    check(r#"{"kind":"hex","hex":"0001feff"}"#, &[0, 1, 254, 255]);
    check(r#"{"kind":"utf8","text":"é\u0000😀"}"#, "é\0😀".as_bytes());
    check(r#"{"kind":"hex","hex":""}"#, &[]);
    check(r#"{"kind":"utf8","text":""}"#, &[]);
}

#[test]
fn patterns_wrap_at_actual_byte_and_chunk_boundaries() {
    check(r#"{"kind":"repeat-u8","byte":255,"length":3}"#, &[255; 3]);
    check(
        r#"{"kind":"cycle-u8","seed":254,"length":4}"#,
        &[254, 255, 0, 1],
    );
    let mut actual = vec![255; 65536];
    actual.extend([0, 0]);
    check(
        r#"{"kind":"chunk-indexed-u8","seed":255,"length":65538}"#,
        &actual,
    );
    check(r#"{"kind":"repeat-u8","byte":1,"length":0}"#, &[]);
}

#[test]
fn flat_concatenation_restarts_each_pattern_and_preserves_empty_parts() {
    check(
        r#"{"kind":"concat","parts":[{"kind":"hex","hex":"ff"},{"kind":"utf8","text":""},{"kind":"cycle-u8","seed":254,"length":3},{"kind":"utf8","text":"é"},{"kind":"repeat-u8","byte":7,"length":2}]}"#,
        &[255, 254, 255, 0, 195, 169, 7, 7],
    );
}

#[test]
fn counts_use_exact_decimal_integrality_before_any_machine_conversion() {
    check(
        r#"{"kind":"repeat-u8","byte":2.55e2,"length":30e-1}"#,
        &[255; 3],
    );
    for token in [
        "1.00000000000000001",
        "1e-1000",
        "-1",
        "18446744073709551616",
        "1e1000000",
        "\"3\"",
        "{\"$serde_json::private::Number\":\"3\"}",
    ] {
        let text = format!(r#"{{"kind":"repeat-u8","byte":0,"length":{token}}}"#);
        assert!(FixtureBytes::parse(&text, limits(100)).is_err(), "{token}");
    }
    for token in ["256", "-1", "255.00000000000000001", "{}", "true"] {
        let text = format!(r#"{{"kind":"cycle-u8","seed":{token},"length":1}}"#);
        assert!(FixtureBytes::parse(&text, limits(100)).is_err(), "{token}");
    }
}

#[test]
fn duplicate_keys_unknown_fields_and_noncanonical_hex_are_refused() {
    for text in [
        r#"{"kind":"hex","hex":"0F"}"#,
        r#"{"kind":"hex","hex":"0"}"#,
        r#"{"kind":"hex","hex":"gg"}"#,
        r#"{"kind":"hex","hex":"00","hex":"01"}"#,
        r#"{"kind":"hex","hex":"00","length":1}"#,
        r#"{"kind":"utf8","text":"\ud800"}"#,
        r#"{"kind":"concat","parts":[]}"#,
        r#"{"kind":"concat","parts":[{"kind":"concat","parts":[{"kind":"hex","hex":"00"}]}]}"#,
        r#"{"kind":"unknown","text":""}"#,
        r#"{"kind":"repeat-u8","byte":0}"#,
    ] {
        assert!(FixtureBytes::parse(text, limits(100)).is_err(), "{text}");
    }
}

#[test]
fn complete_aggregate_is_preflighted_including_utf8_and_hex_widths() {
    let text = r#"{"kind":"concat","parts":[{"kind":"repeat-u8","byte":0,"length":4},{"kind":"utf8","text":"é"},{"kind":"hex","hex":"ff"}]}"#;
    assert_eq!(
        FixtureBytes::parse(text, limits(6)).unwrap_err(),
        FixtureByteError::ExpandedBytes
    );
    assert_eq!(
        FixtureBytes::parse(text, limits(7)).unwrap().byte_length(),
        7
    );
    // The complete list must validate before even an earlier bad aggregate
    // could cause a fixture allocation. No expansion is part of parsing.
    let text = r#"{"kind":"concat","parts":[{"kind":"repeat-u8","byte":0,"length":100},{"kind":"hex","hex":"x"}]}"#;
    assert!(FixtureBytes::parse(text, limits(16)).is_err());
}

#[test]
fn caller_bounds_apply_to_saved_bytes_and_atom_count_before_growth() {
    assert!(FixtureByteLimits::new(0, 1, 1).is_err());
    assert!(FixtureByteLimits::new(1, 0, 1).is_err());
    assert!(FixtureByteLimits::new(1, 1, 0).is_err());
    let text = r#"{"kind":"hex","hex":"00"}"#;
    assert_eq!(
        FixtureBytes::parse(text, FixtureByteLimits::new(text.len() - 1, 1, 1).unwrap())
            .unwrap_err(),
        FixtureByteError::SavedBytes
    );
    assert!(FixtureBytes::parse(text, FixtureByteLimits::new(text.len(), 1, 1).unwrap()).is_ok());
    let text = r#"{"kind":"concat","parts":[{"kind":"hex","hex":""},{"kind":"hex","hex":"00"}]}"#;
    assert_eq!(
        FixtureBytes::parse(text, FixtureByteLimits::new(4096, 1, 1).unwrap()).unwrap_err(),
        FixtureByteError::Parts
    );
}

#[test]
fn oversized_source_fixture_is_valid_input_but_cannot_be_an_accepted_original() {
    let length = 64 * 1024 * 1024 + 1;
    let text = format!(r#"{{"kind":"repeat-u8","byte":0,"length":{length}}}"#);
    let recipe = FixtureBytes::parse(&text, limits(length)).unwrap();
    assert_eq!(recipe.byte_length(), length);
    assert!(recipe.expected().is_err());
    // This is a compact input for a source-limit refusal, not 64MiB allocation.
}

#[test]
fn accepted_original_expectation_borrows_validated_flat_recipe() {
    let recipe = FixtureBytes::parse(r#"{"kind":"concat","parts":[{"kind":"repeat-u8","byte":0,"length":67108863},{"kind":"hex","hex":"ff"}]}"#, limits(64 * 1024 * 1024)).unwrap();
    assert!(recipe.expected().is_ok());
}

#[test]
fn expected_segment_constructor_refuses_empty_nested_and_over_limit_sources() {
    assert!(ExpectedBytes::segments(vec![]).is_err());
    let inner = ExpectedBytes::segments(vec![ExpectedBytes::literal(b"a").unwrap()]).unwrap();
    assert!(ExpectedBytes::segments(vec![inner]).is_err());
    assert!(
        ExpectedBytes::segments(vec![
            ExpectedBytes::repeat(0, 64 * 1024 * 1024).unwrap(),
            ExpectedBytes::literal(b"x").unwrap(),
        ])
        .is_err()
    );
}
