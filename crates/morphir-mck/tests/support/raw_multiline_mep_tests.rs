//! Child module of the existing real-process tests/mep_transport.rs harness.
use super::*;
use serde::Serialize;
use serde_json::value::RawValue;

const INPUT: &str = "{\n \"zero\":-0,\n \"count\":1.00000000000000001,\n \"label\":\"é\"\n}";
const REQUEST: &str = concat!(
    "{\"id\":1,\"jsonrpc\":\"2.0\",\"method\":\"literal-boundary\",\"params\":",
    "{\n \"zero\":-0,\n \"count\":1.00000000000000001,\n \"label\":\"é\"\n}}"
);
const RESPONSE: &str = "\r\n {\"id\":1,\"value\":null}\n ";

#[derive(Serialize)]
struct MultilineRequest<'a> {
    jsonrpc: &'static str,
    method: &'static str,
    params: &'a RawValue,
}

fn receive(input: &mut impl BufRead) -> Option<Vec<u8>> {
    let mut header = String::new();
    if input.read_line(&mut header).unwrap() == 0 {
        return None;
    }
    let length: usize = header
        .strip_prefix("Content-Length: ")
        .unwrap()
        .trim()
        .parse()
        .unwrap();
    let mut blank = String::new();
    input.read_line(&mut blank).unwrap();
    assert_eq!(blank, "\r\n");
    let mut body = vec![0; length];
    input.read_exact(&mut body).unwrap();
    Some(body)
}

pub(super) fn adapter(mode: &str) -> bool {
    if mode != "raw-literal-multiline-request" {
        return false;
    }
    let mut input = std::io::stdin().lock();
    assert_eq!(
        receive(&mut input).unwrap(),
        REQUEST.as_bytes(),
        "actual selected ContentLength request must preserve every raw byte"
    );
    say_frame(RESPONSE);
    if let Some(exit) = receive(&mut input) {
        assert_eq!(
            exit,
            br#"{"jsonrpc":"2.0","method":"morphir.exit","params":{}}"#
        );
    }
    true
}

pub(super) fn literal_content_length_request_keeps_actual_multiline_raw_bytes() {
    let input: &RawValue = serde_json::from_str(INPUT).unwrap();
    let request = MultilineRequest {
        jsonrpc: "2.0",
        method: "literal-boundary",
        params: input,
    };
    let mut actual = session_with("raw-literal-multiline-request", None, Limits::DEFAULT);
    let frame = actual.exchange_literal_frame(&request).unwrap();
    assert_eq!(frame.id(), 1);
    assert_eq!(frame.raw(), RESPONSE);
    assert_eq!(input.get(), INPUT);
    actual.close().unwrap();
}
