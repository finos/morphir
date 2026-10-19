//! Prospective controls for the existing real-process MEP harness.
use super::*;
use serde::Serialize;
use serde_json::value::RawValue;

const INPUT: &str = r#"{ "max":18446744073709551615,"fraction":1.00000000000000001,"opaque":{"$serde_json::private::Number":"1"},"unicode":"é" }"#;
const REQUEST: &str = r#"{"id":1,"jsonrpc":"2.0","method":"literal-boundary","params":{ "max":18446744073709551615,"fraction":1.00000000000000001,"opaque":{"$serde_json::private::Number":"1"},"unicode":"é" }}"#;
const RESPONSE: &str = concat!(
    "\r\n {\"id\":1,\n",
    "\"jsonrpc\":\"2.0\",\"value\":{\"max\":18446744073709551615,",
    "\"zero\":-0,\"exponent\":1e+0002,\"unicode\":\"é\",",
    "\"opaque\":{\"$serde_json::private::RawValue\":\"false\"}}\n}\r\n "
);

#[derive(Serialize)]
struct Probe<'a> {
    jsonrpc: &'static str,
    method: &'static str,
    params: &'a RawValue,
}
fn request() -> Probe<'static> {
    Probe {
        jsonrpc: "2.0",
        method: "literal-boundary",
        params: serde_json::from_str(INPUT).unwrap(),
    }
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
    if mode != "raw-literal-control" {
        return false;
    }
    let response = match std::env::args().nth(3).as_deref() {
        None | Some("positive") => RESPONSE,
        Some("exponent-id") => r#"{"id":1e0,"value":null}"#,
        Some("negative-zero-id") => r#"{"id":-0,"value":null}"#,
        Some("duplicate-id") => r#"{"id":1,"id":1,"value":null}"#,
        _ => panic!("unknown independently authored peer case"),
    };
    let mut input = std::io::stdin().lock();
    assert_eq!(receive(&mut input).unwrap(), REQUEST.as_bytes());
    say_frame(response);
    if let Some(exit) = receive(&mut input) {
        assert_eq!(
            exit,
            br#"{"jsonrpc":"2.0","method":"morphir.exit","params":{}}"#
        );
    }
    true
}

pub(super) fn literal_mep_payload_preserves_body_newlines_whitespace_and_utf8() {
    let mut actual = session_with("raw-literal-control", None, Limits::DEFAULT);
    let frame = actual.exchange_literal_frame(&request()).unwrap();
    assert_eq!(frame.id(), 1);
    assert_eq!(frame.raw(), RESPONSE);
    actual.close().unwrap();
}

pub(super) fn literal_mep_exact_body_limit_and_one_less_use_existing_framing() {
    let mut limits = Limits::DEFAULT;
    limits.max_frame = RESPONSE.len();
    let mut actual = session_with("raw-literal-control", None, limits);
    assert_eq!(
        actual.exchange_literal_frame(&request()).unwrap().raw(),
        RESPONSE
    );
    actual.close().unwrap();
    limits.max_frame = RESPONSE.len() - 1;
    let mut actual = session_with("raw-literal-control", None, limits);
    assert_eq!(
        actual.exchange_literal_frame(&request()).err().unwrap(),
        TransportError::FrameTooLong {
            limit: RESPONSE.len() - 1
        }
    );
    actual.close().unwrap();
}

pub(super) fn literal_mep_selected_id_policy_refuses_exponent_negative_zero_and_duplicates() {
    for case in ["exponent-id", "negative-zero-id", "duplicate-id"] {
        let mut actual = session_with("raw-literal-control", Some(case), Limits::DEFAULT);
        assert!(matches!(
            actual.exchange_literal_frame(&request()),
            Err(TransportError::Malformed(_))
        ));
        actual.close().unwrap();
    }
}
