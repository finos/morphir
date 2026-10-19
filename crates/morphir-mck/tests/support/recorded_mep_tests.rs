//! Existing tests/mep_transport.rs child. Added after generic recorded API
//! implementation, before first recorded ContentLength mode execution.
//! Physical framing + ID/byte receipt evidence, not JSONRPC conformance.
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
struct Probe<'a> {
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
    if mode != "recorded-literal-multiline" {
        return false;
    }
    let mut input = std::io::stdin().lock();
    assert_eq!(receive(&mut input).unwrap(), REQUEST.as_bytes());
    say_frame(RESPONSE);
    if let Some(exit) = receive(&mut input) {
        assert_eq!(
            exit,
            br#"{"jsonrpc":"2.0","method":"morphir.exit","params":{}}"#
        );
    }
    true
}

pub(super) fn recorded_content_length_keeps_actual_multiline_sent_and_received_payloads() {
    let input: &RawValue = serde_json::from_str(INPUT).unwrap();
    let request = Probe {
        jsonrpc: "2.0",
        method: "literal-boundary",
        params: input,
    };
    let mut actual = session_with("recorded-literal-multiline", None, Limits::DEFAULT);
    let receipt = actual.exchange_recorded_literal(&request).unwrap();
    assert_eq!(receipt.sent_payload(), REQUEST);
    assert_eq!(receipt.received().raw(), RESPONSE);
    assert_eq!(receipt.received().id(), 1);
    assert_eq!(input.get(), INPUT);
    actual.close().unwrap();
}
