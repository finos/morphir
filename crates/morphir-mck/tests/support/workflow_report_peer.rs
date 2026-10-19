//! Prospective existing MEP harness child, private Workbench envelope control.
//! ContentLength framing is not a claim of JSONRPC2 result conformance.
use super::*;

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
    if mode != "workflow-report-v3" {
        return false;
    }
    let mut input = std::io::stdin().lock();
    assert_eq!(
        receive(&mut input).unwrap(),
        include_bytes!("workflow_report_controls/sent-request.payload.json")
    );
    say_frame(include_str!(
        "workflow_report_controls/received-reply.payload.json"
    ));
    if let Some(exit) = receive(&mut input) {
        assert_eq!(
            exit,
            br#"{"jsonrpc":"2.0","method":"morphir.exit","params":{}}"#
        );
    }
    true
}
