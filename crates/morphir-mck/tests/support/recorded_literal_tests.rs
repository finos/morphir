//! Child of existing tests/transport.rs. Opaque raw transport evidence only.
//! Root integrates these independently authored controls before API repair.
use super::*;
use serde::Serialize;
use serde_json::value::RawValue;
use std::cell::Cell;

const INPUT_A: &str =
    r#"{ "fraction":1.00000000000000001,"zero":-0,"opaque":{"$serde_json::private::Number":"1"} }"#;
const INPUT_B: &str = r#"{"different":true}"#;
const REQUEST_A: &str = r#"{"id":1,"op":"literal-record","input":{ "fraction":1.00000000000000001,"zero":-0,"opaque":{"$serde_json::private::Number":"1"} }}"#;
const RESPONSE: &str = r#"{ "id":1, "value":{ "zero":-0,"fraction":1.00000000000000001,"opaque":{"$serde_json::private::RawValue":"false"} } }"#;
const DUPLICATE: &str = r#"{"id":1,"value":{"same":0,"same":1}}"#;
const MULTILINE: &str = "{\n \"zero\":-0,\n \"fraction\":1.00000000000000001\n}";

#[derive(Serialize)]
struct Probe<'a> {
    op: &'static str,
    input: &'a RawValue,
}

struct StatefulRequest<'a> {
    calls: &'a Cell<usize>,
    first_input: &'a RawValue,
}
impl Serialize for StatefulRequest<'_> {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let calls = self.calls.get();
        self.calls.set(calls + 1);
        let input = if calls == 0 {
            self.first_input
        } else {
            serde_json::from_str(INPUT_B).unwrap()
        };
        Probe {
            op: "literal-record",
            input,
        }
        .serialize(serializer)
    }
}

pub(super) fn adapter(mode: &str) -> bool {
    let (reply, ahead) = match mode {
        "recorded-literal-once" => (RESPONSE, false),
        "recorded-literal-duplicate" => (DUPLICATE, false),
        "recorded-literal-multiline" => (RESPONSE, true),
        _ => return false,
    };
    let mut input = std::io::stdin().lock().lines();
    if !ahead {
        assert_eq!(input.next().unwrap().unwrap(), REQUEST_A);
    }
    {
        let mut output = std::io::stdout().lock();
        output.write_all(reply.as_bytes()).unwrap();
        output.write_all(b"\n").unwrap();
        output.flush().unwrap();
    }
    // No absence-of-I/O or wall-clock oracle. LF refusal ordering is reviewed
    // at the real send boundary; the ahead reply is deterministic pre-fix RED.
    for line in input {
        let line = line.unwrap();
        if !ahead {
            assert_eq!(line, r#"{"id":2,"op":"exit"}"#);
        }
    }
    true
}

pub(super) fn recorded_literal_retains_the_actual_sent_request_without_second_serialize() {
    let calls = Cell::new(0);
    let input: &RawValue = serde_json::from_str(INPUT_A).unwrap();
    let mut actual = session("recorded-literal-once", None, quick());
    let receipt = actual
        .exchange_recorded_literal(&StatefulRequest {
            calls: &calls,
            first_input: input,
        })
        .unwrap();
    assert_eq!(
        calls.get(),
        1,
        "receipt must move actual sent payload, not serialize again"
    );
    assert_eq!(receipt.sent_payload(), REQUEST_A);
    assert_eq!(receipt.received().raw(), RESPONSE);
    assert_eq!(receipt.received().id(), 1);
    assert_eq!(input.get(), INPUT_A);
    actual.close().unwrap();
}

pub(super) fn recorded_literal_lf_refusal_cannot_return_a_completed_exchange_receipt() {
    let calls = Cell::new(0);
    let input: &RawValue = serde_json::from_str(MULTILINE).unwrap();
    let mut actual = session("recorded-literal-multiline", None, quick());
    assert!(matches!(
        actual.exchange_recorded_literal(&StatefulRequest {
            calls: &calls,
            first_input: input,
        }),
        Err(TransportError::Malformed(_))
    ));
    assert_eq!(calls.get(), 1);
    assert_eq!(input.get(), MULTILINE);
    assert!(actual.broken().is_some());
    actual.close().unwrap();
}

pub(super) fn recorded_literal_first_fault_precedes_next_serialization_or_receipt() {
    let first_calls = Cell::new(0);
    let next_calls = Cell::new(0);
    let input: &RawValue = serde_json::from_str(INPUT_A).unwrap();
    let mut actual = session("recorded-literal-duplicate", None, quick());
    let first = actual
        .exchange_recorded_literal(&StatefulRequest {
            calls: &first_calls,
            first_input: input,
        })
        .err()
        .unwrap();
    assert!(matches!(first, TransportError::Malformed(_)));
    assert_eq!(first_calls.get(), 1);
    let second = actual
        .exchange_recorded_literal(&StatefulRequest {
            calls: &next_calls,
            first_input: input,
        })
        .err()
        .unwrap();
    assert_eq!(second, first);
    assert_eq!(next_calls.get(), 0);
    actual.close().unwrap();
}
