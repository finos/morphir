//! Insert as a child module of the EXISTING tests/transport.rs binary.
//! Its existing adapter dispatcher calls adapter(mode) before historical modes;
//! its existing test list calls the five controls below. No separate transport.
use super::*;
use serde::Serialize;
use serde_json::value::RawValue;
use std::cell::Cell;

const INPUT: &str = r#"{ "max":18446744073709551615,"count":1.00000000000000001,"zero":-0,"exponent":1e+0002,"opaque":{"$serde_json::private::Number":"1","$serde_json::private::RawValue":"false"} }"#;
const REQUEST: &str = r#"{"id":1,"op":"literal-boundary","input":{ "max":18446744073709551615,"count":1.00000000000000001,"zero":-0,"exponent":1e+0002,"opaque":{"$serde_json::private::Number":"1","$serde_json::private::RawValue":"false"} }}"#;
const RESPONSE: &str = r#"{ "id":1, "status":"ok", "value":{ "max":18446744073709551615,"count":1.00000000000000001,"zero":-0,"exponent":1e+0002,"opaque":{"$serde_json::private::Number":"1","$serde_json::private::RawValue":"false"} } }"#;

#[derive(Serialize)]
struct Probe<'a> {
    op: &'static str,
    input: &'a RawValue,
}
fn request() -> Probe<'static> {
    Probe {
        op: "literal-boundary",
        input: serde_json::from_str(INPUT).unwrap(),
    }
}

/// Literal external peer. It verifies the WHOLE actual first request byte for
/// byte before returning independently fixed reply bytes. It is no producer.
pub(super) fn adapter(mode: &str) -> bool {
    let reply = match mode {
        "raw-workflow-literal" => RESPONSE,
        "raw-workflow-duplicate" => r#"{"id":1,"status":"ok","value":{"key":0,"key":1}}"#,
        "raw-workflow-duplicate-opaque" => {
            r#"{"id":1,"status":"ok","value":{"$serde_json::private::RawValue":0,"$serde_json::private::RawValue":1}}"#
        }
        "raw-workflow-wrong-id" => r#"{"id":2,"status":"ok","value":null}"#,
        "raw-workflow-decimal-id" => r#"{"id":1.0,"status":"ok","value":null}"#,
        "raw-workflow-fraction-id" => r#"{"id":1.00000000000000001,"status":"ok","value":null}"#,
        "raw-workflow-string-id" => r#"{"id":"1","status":"ok","value":null}"#,
        "raw-workflow-zero-id" => r#"{"id":0,"status":"ok","value":null}"#,
        "raw-workflow-overflow-id" => r#"{"id":18446744073709551616,"status":"ok","value":null}"#,
        _ => return false,
    };
    let mut input = std::io::stdin().lock().lines();
    let line = input.next().unwrap().unwrap();
    assert_eq!(
        line, REQUEST,
        "actual raw input was narrowed or reserialized"
    );
    {
        let mut output = std::io::stdout().lock();
        output.write_all(reply.as_bytes()).unwrap();
        output.write_all(b"\n").unwrap();
        output.flush().unwrap();
    }
    if let Some(line) = input.next() {
        assert_eq!(
            line.unwrap(),
            r#"{"id":2,"op":"exit"}"#,
            "unexpected second effect after first exchange"
        );
    }
    true
}

pub(super) fn raw_workflow_transport_preserves_whole_request_and_response_tokens() {
    let mut actual = session("raw-workflow-literal", None, quick());
    let frame = actual.exchange_literal_frame(&request()).unwrap();
    assert_eq!(frame.id(), 1);
    assert_eq!(frame.raw(), RESPONSE);
    actual.close().unwrap();
}

pub(super) fn raw_workflow_selected_outer_ids_are_canonical_positive_u64() {
    for mode in [
        "raw-workflow-decimal-id",
        "raw-workflow-fraction-id",
        "raw-workflow-string-id",
        "raw-workflow-zero-id",
        "raw-workflow-overflow-id",
    ] {
        let mut actual = session(mode, None, quick());
        assert!(
            matches!(
                actual.exchange_literal_frame(&request()),
                Err(TransportError::Malformed(_))
            ),
            "{mode}"
        );
        actual.close().unwrap();
    }
    let mut actual = session("raw-workflow-wrong-id", None, quick());
    assert_eq!(
        actual.exchange_literal_frame(&request()).err().unwrap(),
        TransportError::WrongId {
            expected: 1,
            got: 2
        }
    );
    actual.close().unwrap();
    // The INNER max-u64 above is an opaque operand token, not this generated
    // session's first outer ID. No counter setter or inferred producer grant.
}

pub(super) fn raw_workflow_duplicate_members_never_disappear_inside_opaque_objects() {
    for mode in ["raw-workflow-duplicate", "raw-workflow-duplicate-opaque"] {
        let mut actual = session(mode, None, quick());
        assert!(matches!(
            actual.exchange_literal_frame(&request()),
            Err(TransportError::Malformed(_))
        ));
        actual.close().unwrap();
    }
}

struct CountSerialize<'a> {
    calls: &'a Cell<usize>,
}
impl Serialize for CountSerialize<'_> {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        self.calls.set(self.calls.get() + 1);
        request().serialize(serializer)
    }
}
pub(super) fn raw_workflow_first_transport_fault_precedes_retry_serialization_and_io() {
    let mut actual = session("raw-workflow-duplicate", None, quick());
    let first = actual.exchange_literal_frame(&request()).err().unwrap();
    let calls = Cell::new(0);
    let second = actual
        .exchange_literal_frame(&CountSerialize { calls: &calls })
        .err()
        .unwrap();
    assert_eq!(second, first);
    assert_eq!(calls.get(), 0);
    actual.close().unwrap();
}

pub(super) fn raw_workflow_exact_frame_bound_and_one_less_are_actual_session_limits() {
    let mut exact = quick();
    exact.max_frame = RESPONSE.len();
    let mut actual = session("raw-workflow-literal", None, exact);
    assert_eq!(
        actual.exchange_literal_frame(&request()).unwrap().raw(),
        RESPONSE
    );
    actual.close().unwrap();
    let mut short = quick();
    short.max_frame = RESPONSE.len() - 1;
    let mut actual = session("raw-workflow-literal", None, short);
    assert_eq!(
        actual.exchange_literal_frame(&request()).err().unwrap(),
        TransportError::FrameTooLong {
            limit: RESPONSE.len() - 1
        }
    );
    actual.close().unwrap();
}
