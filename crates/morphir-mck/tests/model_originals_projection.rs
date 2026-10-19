//! Independently authored projection peers qualify the checker only.
use base64::{Engine as _, engine::general_purpose::STANDARD};
use morphir_mck::workbench::model_originals::{
    CaptureExpectation, CaptureInventory, Exchange, ExpectedProjection, ModelRelease,
    ProjectionError, ProjectionWorkLimits, Request,
};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};

fn packet() -> Value {
    serde_json::from_str(include_str!(
        "../../../spec/workbench/model-originals/0.1.0-draft.1/acceptance/wire49.json"
    ))
    .unwrap()
}
fn request(method: &str, params: Value) -> Request {
    Request::parse(&json!({"jsonrpc":"2.0","id":1,"method":format!("morphir.model-originals.{method}"),"params":params}).to_string()).unwrap()
}
fn reply(result: &Value) -> String {
    json!({"jsonrpc":"2.0","id":1,"result":result}).to_string()
}
fn inventory(projection: &[u8], version: &str) -> CaptureInventory {
    let packet = packet();
    let mut summary = packet["cases"][0]["expected"]["summary"].clone();
    summary["projection"] = json!({"status":"available","codec":"morphir-json","byteLength":projection.len(),"sha256":Sha256::digest(projection).iter().map(|b|format!("{b:02x}")).collect::<String>(),"formatVersion":version});
    let expected = CaptureExpectation::parse(&summary.to_string()).unwrap();
    let requests=[0,2].map(|start|request("inventory",json!({"contractVersion":"0.1.0-draft.1","captureId":"capture-A","startIndex":start,"maxEntries":2})));
    let replies = [0, 1].map(|i| reply(&packet["cases"][1]["input"]["pages"][i]));
    expected
        .verify_inventory(&[0, 1].map(|i| Exchange {
            request: &requests[i],
            reply: &replies[i],
        }))
        .unwrap()
}
fn limits() -> ProjectionWorkLimits {
    ProjectionWorkLimits::new(16 * 1024 * 1024, 1_000_000).unwrap()
}
fn verify(expected: &str, actual: &str, version: &str) -> Result<(), ProjectionError> {
    let inventory = inventory(actual.as_bytes(), version);
    let request = request(
        "read",
        json!({"contractVersion":"0.1.0-draft.1","captureId":"capture-A","target":{"kind":"semantic-projection"},"offset":0,"maxBytes":65536}),
    );
    let packet = packet();
    let mut chunk = packet["cases"][12]["expected"]["chunk"].clone();
    chunk["content"] = json!(STANDARD.encode(actual));
    chunk["nextOffset"] = json!(actual.len());
    let frame = reply(&chunk);
    let expected = ExpectedProjection::json(expected, limits())?;
    let checked = expected.verify(
        &inventory,
        &[Exchange {
            request: &request,
            reply: &frame,
        }],
    )?;
    assert_eq!(checked.format_version().as_str(), version);
    assert_eq!(checked.byte_length(), actual.len());
    Ok(())
}

#[test]
fn actual_projection_bytes_can_differ_in_order_whitespace_and_string_escaping() {
    verify(r#"{"formatVersion":4,"distribution":{"x":"é","items":[true,null,2]}}"#," \r\n{\"distribution\": {\"items\": [true, null, 2], \"x\": \"\\u00e9\"}, \"formatVersion\":4}\r\n","4.0.0").unwrap();
    verify(
        r#"{"formatVersion":4}"#,
        r#"{"formatVersion":"4.0.0"}"#,
        "4.0.0",
    )
    .unwrap();
}
#[test]
fn matching_digest_cannot_replace_independently_expected_semantics() {
    assert!(matches!(
        verify(
            r#"{"formatVersion":4,"value":"expected"}"#,
            r#"{"formatVersion":4,"value":"other"}"#,
            "4.0.0"
        ),
        Err(ProjectionError::Semantics)
    ));
    assert!(matches!(
        verify(
            r#"{"formatVersion":4,"items":[1,2]}"#,
            r#"{"formatVersion":4,"items":[2,1]}"#,
            "4.0.0"
        ),
        Err(ProjectionError::Semantics)
    ));
}
#[test]
fn exact_large_numbers_and_marker_looking_objects_remain_literal() {
    let json = r#"{"formatVersion":4,"n":9007199254740993,"literal":{"$serde_json::private::Number":"42"}}"#;
    verify(json, json, "4.0.0").unwrap();
    assert!(matches!(
        verify(
            json,
            &json.replace("9007199254740993", "9007199254740992"),
            "4.0.0"
        ),
        Err(ProjectionError::Semantics)
    ));
    assert!(matches!(
        verify(
            json,
            r#"{"formatVersion":4,"n":9007199254740993,"literal":42}"#,
            "4.0.0"
        ),
        Err(ProjectionError::Semantics)
    ));
}

#[test]
fn decimal_values_compare_exactly_across_serializer_spellings() {
    for (left, right) in [
        ("1", "1.0"),
        ("100", "1e2"),
        ("0.00100", "1e-3"),
        ("-0.0", "-0e999999999999999999999999"),
        ("1e999999999999999999999999", "10e999999999999999999999998"),
        (
            "10e-999999999999999999999999",
            "1e-999999999999999999999998",
        ),
        ("1e-1", "0.1"),
        ("100e-2", "1"),
        ("0.001e3", "1"),
    ] {
        let expected = format!("{{\"formatVersion\":4,\"n\":{left}}}");
        let actual = format!("{{\"formatVersion\":4,\"n\":{right}}}");
        verify(&expected, &actual, "4.0.0").unwrap();
    }
    assert!(matches!(
        verify(
            r#"{"formatVersion":4,"n":-0}"#,
            r#"{"formatVersion":4,"n":0}"#,
            "4.0.0"
        ),
        Err(ProjectionError::Semantics)
    ));
}
#[test]
fn duplicate_members_at_any_depth_and_invalid_json_are_refused() {
    let expected = r#"{"formatVersion":4,"nested":{"x":1}}"#;
    for actual in [
        r#"{"formatVersion":4,"nested":{"x":1,"x":1}}"#,
        r#"{"formatVersion":4,"formatVersion":4,"nested":{"x":1}}"#,
        r#"{"formatVersion":4,"nested":{"x":1},}"#,
    ] {
        assert!(verify(expected, actual, "4.0.0").is_err());
    }
    assert!(ExpectedProjection::json(r#"{"formatVersion":4,"x":1,"x":1}"#, limits()).is_err());
}
#[test]
fn header_evidence_is_actual_and_does_not_grant_consumer_support() {
    for (actual, version) in [
        (r#"{"formatVersion":2}"#, "2.0.0"),
        (r#"{"formatVersion":99}"#, "99.0.0"),
        (r#"{"formatVersion":"99.1.2"}"#, "99.1.2"),
    ] {
        verify(actual, actual, version).unwrap();
    }
    for actual in [
        r#"{"formatVersion":3}"#,
        r#"{"descriptorVersion":"v4"}"#,
        r#"{"formatVersion":0}"#,
        r#"{"formatVersion":4.0}"#,
        r#"{"formatVersion":"4.0.0-draft.1"}"#,
    ] {
        assert!(verify(r#"{"formatVersion":4}"#, actual, "4.0.0").is_err());
    }
}
#[test]
fn canonical_release_bounds_are_checked_with_the_semver_library() {
    for version in ["2.0.0", "99.1.2", "4294967295.4294967295.4294967295"] {
        assert!(ModelRelease::parse(version).is_ok());
    }
    for version in [
        "v4.0.0",
        "04.0.0",
        "4.0",
        "4.0.0+meta",
        "4.0.0-draft.1",
        "4294967296.0.0",
    ] {
        assert!(ModelRelease::parse(version).is_err());
    }
    let packet = packet();
    for pointer in ["/sourceFormatVersion/release", "/projection/formatVersion"] {
        let mut summary = packet["cases"][0]["expected"]["summary"].clone();
        *summary.pointer_mut(pointer).unwrap() = json!("4294967296.0.0");
        assert!(CaptureExpectation::parse(&summary.to_string()).is_err());
    }
}
#[test]
fn deep_projection_comparison_is_iterative_and_keeps_array_order() {
    let nested = format!(
        "{{\"formatVersion\":4,\"nested\":{}0{}}}",
        "[".repeat(400),
        "]".repeat(400)
    );
    verify(&nested, &nested, "4.0.0").unwrap();
}
#[test]
fn caller_supplies_finite_comparison_work_and_refusal_is_not_a_domain_success() {
    assert!(ProjectionWorkLimits::new(0, 1).is_err());
    assert!(ProjectionWorkLimits::new(1, 0).is_err());
    assert!(matches!(
        ExpectedProjection::json(
            r#"{"formatVersion":4}"#,
            ProjectionWorkLimits::new(1, 100).unwrap()
        ),
        Err(ProjectionError::WorkLimit(_))
    ));
    assert!(matches!(
        ExpectedProjection::json(
            r#"{"formatVersion":4,"items":[1,2,3]}"#,
            ProjectionWorkLimits::new(10000, 2).unwrap()
        ),
        Err(ProjectionError::WorkLimit(_))
    ));
}
