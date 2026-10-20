//! Child module of the existing real-process tests/transport.rs harness.
//! No byte-count oracle is claimed. The valid reply makes the pre-fix API
//! return Ok deterministically; reviewed pre-send placement proves ordering.
use super::*;
use serde::Serialize;
use serde_json::value::RawValue;

const INPUT: &str = "{\n \"zero\":-0,\n \"count\":1.00000000000000001,\n \"label\":\"é\"\n}";
const RESPONSE: &str = r#"{"id":1,"value":null}"#;

#[derive(Serialize)]
struct MultilineRequest<'a> {
    op: &'static str,
    input: &'a RawValue,
}

pub(super) fn adapter(mode: &str) -> bool {
    if mode != "raw-workflow-multiline-request" {
        return false;
    }
    {
        let mut output = std::io::stdout().lock();
        output.write_all(RESPONSE.as_bytes()).unwrap();
        output.write_all(b"\n").unwrap();
        output.flush().unwrap();
    }
    // Keep the genuine peer alive without a clock-based oracle. This peer
    // deliberately does not claim that zero stdin bytes were measured.
    for line in std::io::stdin().lock().lines() {
        line.unwrap();
    }
    true
}

pub(super) fn literal_newline_request_refuses_actual_lf_without_normalizing_source() {
    let input: &RawValue = serde_json::from_str(INPUT).unwrap();
    assert!(input.get().contains('\n'));
    let request = MultilineRequest {
        op: "literal-boundary",
        input,
    };
    let mut actual = session("raw-workflow-multiline-request", None, quick());
    let result = actual.exchange_literal_frame(&request);
    assert!(
        matches!(result, Err(TransportError::Malformed(_))),
        "selected newline transport must refuse a multiline literal request"
    );
    assert_eq!(
        input.get(),
        INPUT,
        "refusal must not normalize caller bytes"
    );
    assert!(actual.broken().is_some());
    actual.close().unwrap();
}
