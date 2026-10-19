//! These literals and outcomes were frozen and schema-checked independently
//! before the Rust input decoder existed. They are decoding, not SUT workflows.
use super::*;
use crate::json::strict::StrictReadError;
use serde::Deserialize;

#[derive(Deserialize)]
enum InputShape {
    RawJsonSource,
    ClientFixture,
    HostAction,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Case {
    id: String,
    #[serde(rename = "type")]
    shape: InputShape,
    raw: String,
    accepts: bool,
    reason: String,
}
fn decoder() -> Decoder {
    Decoder::new(
        DecodeLimits::new(1_048_576, 67_108_864, 1_000_000, 67_108_864, 1_000_000).unwrap(),
    )
}
#[test]
fn frozen_input_v27_shapes_decode_with_exact_authored_outcomes() {
    let bytes = include_bytes!("input_boundaries.json");
    assert_eq!(
        crate::kit::hash::sha256_hex(bytes),
        "944a89485b8532e74c6062c9d5120e42fc0ff3594d25a0e72c5be48f659e7f3a"
    );
    let cases: Vec<Case> = serde_json::from_slice(bytes).unwrap();
    assert_eq!(cases.len(), 21);
    for case in cases {
        let mut d = decoder();
        let result = match case.shape {
            InputShape::RawJsonSource => d.decode::<input::RawJsonSource>(&case.raw).map(|_| ()),
            InputShape::ClientFixture => d.decode::<input::ClientFixture>(&case.raw).map(|_| ()),
            InputShape::HostAction => d.decode::<input::HostAction>(&case.raw).map(|_| ()),
        };
        if let Err(
            DecodeError::Limits
            | DecodeError::SavedBytes
            | DecodeError::Work(_)
            | DecodeError::Allocation
            | DecodeError::Literal(StrictReadError::Limits | StrictReadError::Work(_)),
        ) = &result
        {
            panic!(
                "{} exhausted test work instead of checking its authored shape: {result:?}",
                case.id
            );
        }
        assert_eq!(
            result.is_ok(),
            case.accepts,
            "{}: {}: {result:?}",
            case.id,
            case.reason
        );
    }
}
#[test]
fn complete_fixture_domain_keeps_optional_presence_without_inventing_defaults() {
    let mut d = decoder();
    let absent = d
        .decode::<input::ClientFixture>(
            r#"{"files":[],"literalPeers":[{"alias":"A","frames":[]}]}"#,
        )
        .unwrap();
    assert!(matches!(absent.runtime, Presence::Absent));
    assert!(matches!(
        absent.literal_peers.0[0].requests,
        Presence::Absent
    ));
    let empty = d
        .decode::<input::ClientFixture>(
            r#"{"files":[],"literalPeers":[{"alias":"A","frames":[],"requests":[]}]}"#,
        )
        .unwrap();
    assert!(
        matches!(&empty.literal_peers.0[0].requests, Presence::Present(Items(values)) if values.is_empty())
    );
    let with_runtime = d.decode::<input::ClientFixture>(r#"{"files":[],"literalPeers":[],"runtime":{"kind":"controlled-http-executions","peer":"A","sessionId":"S"}}"#).unwrap();
    assert!(matches!(with_runtime.runtime, Presence::Present(_)));
}
