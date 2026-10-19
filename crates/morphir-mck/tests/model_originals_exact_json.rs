//! Independently fixed RawJson expectations, never projected numeric semantics.
use morphir_mck::workbench::model_originals::{
    ComparisonResource, ExactJsonComparison, ProjectionError, ProjectionWorkLimits,
};

fn comparator() -> ExactJsonComparison {
    ExactJsonComparison::new(ProjectionWorkLimits::new(16 * 1024 * 1024, 1_000_000).unwrap())
}

#[test]
fn whitespace_member_order_and_decoded_escapes_do_not_change_operands() {
    let mut c = comparator();
    c.verify(
        r#"{"n":9007199254740993,"label":"é","nested":[true,null,{"x":-0}]}"#,
        " \r\n {\"nested\":[true,null,{\"x\":-0}],\"label\":\"\\u00e9\",\"\\u006e\":9007199254740993} \t",
    )
    .unwrap();
    c.verify(
        r#"["\ud834\udd1e",{"a":1,"b":2}]"#,
        r#"["𝄞",{"b":2,"a":1}]"#,
    )
    .unwrap();
}

#[test]
fn number_tokens_remain_exact_at_every_depth_and_machine_boundary() {
    for (left, right) in [
        ("1", "1.0"),
        ("1", "1e0"),
        ("1e0", "1E0"),
        ("1e0", "1e+0"),
        ("-0", "0"),
        ("-0.0", "-0e0"),
        ("9007199254740993", "9007199254740992"),
        ("9223372036854775808", "9223372036854775807"),
        ("18446744073709551616", "18446744073709551615"),
        ("1e999999999999999999999999", "10e999999999999999999999998"),
        ("1.000000000000000000000001", "1.0"),
    ] {
        for (left, right) in [
            (left.to_owned(), right.to_owned()),
            (
                format!("{{\"v\":[{left}]}}"),
                format!("{{\"v\":[{right}]}}"),
            ),
        ] {
            assert_eq!(
                comparator().verify(&left, &right),
                Err(ProjectionError::Semantics)
            );
        }
    }
}

#[test]
fn huge_exponents_and_long_mantissas_are_compared_without_numeric_conversion() {
    for token in [
        "9223372036854775808".to_owned(),
        "1e-999999999999999999999999999999999999999999".to_owned(),
        format!("1e{}", "9".repeat(65_536)),
        format!("0.{}1", "0".repeat(65_536)),
    ] {
        comparator().verify(&token, &token).unwrap();
    }
}

#[test]
fn malformed_duplicate_and_marker_shaped_objects_cannot_impersonate_values() {
    for invalid in [
        r#"{"x":1,"x":1}"#,
        r#"{"x":1,"\u0078":1}"#,
        r#"{"outer":[{"x":1,"x":2}]}"#,
        "01",
        "1.",
        "NaN",
        "Infinity",
        "1 2",
        r#""\ud800""#,
    ] {
        assert!(comparator().verify(invalid, invalid).is_err(), "{invalid}");
    }
    for (literal, scalar) in [
        (r#"{"$serde_json::private::Number":"1"}"#, "1"),
        (r#"{"$serde_json::private::RawValue":"true"}"#, "true"),
    ] {
        comparator().verify(literal, literal).unwrap();
        assert_eq!(
            comparator().verify(literal, scalar),
            Err(ProjectionError::Semantics)
        );
    }
}

#[test]
fn array_order_unicode_and_projection_headers_are_ordinary_exact_operands() {
    for (left, right) in [
        ("[1,2]", "[2,1]"),
        (r#""é""#, r#""e\u0301""#),
        (r#"{"formatVersion":4}"#, r#"{"formatVersion":"4.0.0"}"#),
        (r#"{"formatVersion":4}"#, r#"{"formatVersion":4.0}"#),
        ("null", "false"),
        ("[]", "{}"),
        ("[null]", "[]"),
    ] {
        assert_eq!(
            comparator().verify(left, right),
            Err(ProjectionError::Semantics)
        );
    }
}

#[test]
fn exact_decode_and_value_credits_are_inclusive_and_cumulative() {
    let mut exact = ExactJsonComparison::new(ProjectionWorkLimits::new(12, 4).unwrap());
    exact.verify("1", "1").unwrap();
    exact.verify("1", "1").unwrap();
    assert_eq!(
        exact.verify("1", "1"),
        Err(ProjectionError::WorkLimit(ComparisonResource::DecodeBytes))
    );
    assert_eq!(
        exact.verify("null", "null"),
        Err(ProjectionError::WorkLimit(ComparisonResource::DecodeBytes))
    );
    assert_eq!(
        ExactJsonComparison::new(ProjectionWorkLimits::new(5, 2).unwrap()).verify("1", "1"),
        Err(ProjectionError::WorkLimit(ComparisonResource::DecodeBytes))
    );
    assert_eq!(
        ExactJsonComparison::new(ProjectionWorkLimits::new(6, 1).unwrap()).verify("1", "1"),
        Err(ProjectionError::WorkLimit(ComparisonResource::Values))
    );
    ExactJsonComparison::new(ProjectionWorkLimits::new(6, 2).unwrap())
        .verify("1", "1")
        .unwrap();
}

#[test]
fn failed_comparisons_spend_work_and_do_not_grant_a_fresh_budget() {
    let mut c = ExactJsonComparison::new(ProjectionWorkLimits::new(6, 2).unwrap());
    assert_eq!(c.verify("1", "2"), Err(ProjectionError::Semantics));
    assert_eq!(
        c.verify("1", "1"),
        Err(ProjectionError::WorkLimit(ComparisonResource::DecodeBytes))
    );
}
