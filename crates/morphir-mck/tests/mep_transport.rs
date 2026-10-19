//! Real subprocess checks for the shared session's MEP framing mode.
use std::ffi::OsString;
use std::io::{BufRead, Read, Write};
use std::time::{Duration, Instant};

use morphir_mck::transport::{Limits, Session, TransportError};
use serde_json::{Value, json};

fn adapter(mode: &str) {
    if mode == "stalled-stdin" {
        std::thread::sleep(Duration::from_secs(60));
        return;
    }
    if mode == "child" || mode == "child-exit" {
        let path = std::env::args().nth(3).unwrap();
        let mut child = std::process::Command::new(std::env::current_exe().unwrap())
            .args(["--heartbeat", &path])
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()
            .unwrap();
        std::thread::spawn(move || {
            let _ = child.wait();
        });
        let started = Instant::now();
        while std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0) == 0 {
            assert!(started.elapsed() < Duration::from_secs(3));
            std::thread::sleep(Duration::from_millis(10));
        }
    }
    let mut input = std::io::stdin().lock();
    loop {
        let mut header = String::new();
        if input.read_line(&mut header).unwrap() == 0 {
            return;
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
        let request: Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(request["jsonrpc"], "2.0");
        if request["method"] == "morphir.exit" {
            assert!(request.get("id").is_none());
            if mode == "exit-reply" {
                say_frame(r#"{"jsonrpc":"2.0","id":null,"result":null}"#);
            }
            return;
        }
        if request.get("id").is_none() {
            if mode == "notification-reply" {
                say_frame(r#"{"jsonrpc":"2.0","id":null,"result":null}"#);
            }
            continue;
        }
        if mode == "raw" {
            say(std::env::args().nth(3).unwrap().as_bytes());
            return;
        }
        if mode == "invalid-utf8" {
            say(b"Content-Length: 1\r\n\r\n\xff");
            return;
        }
        if mode == "body" {
            say_frame(&std::env::args().nth(3).unwrap());
            continue;
        }
        if mode == "silent" {
            std::thread::sleep(Duration::from_secs(60));
        }
        if mode == "stderr" {
            std::io::stderr().write_all(&vec![b'x'; 100_000]).unwrap();
        }
        let response = json!({"jsonrpc":"2.0", "id":request["id"], "result":request["params"]});
        let body = response.to_string();
        let mut output = std::io::stdout().lock();
        if mode == "fragmented" {
            let body = serde_json::to_string_pretty(&response).unwrap();
            for byte in format!("Content-Length: {}\r\n\r\n{body}", body.len()).bytes() {
                output.write_all(&[byte]).unwrap();
                output.flush().unwrap();
            }
        } else if mode == "extra-header" {
            write!(
                output,
                "X_Trace: ignored\r\ncOnTeNt-LeNgTh: {}\r\n\r\n{body}",
                body.len()
            )
            .unwrap();
        } else {
            write!(output, "Content-Length: {}\r\n\r\n{body}", body.len()).unwrap();
        }
        output.flush().unwrap();
        if mode == "child-exit" || mode == "early-exit" {
            return;
        }
        if mode == "unsolicited" {
            drop(output);
            say_frame(r#"{"jsonrpc":"2.0","method":"unexpected","params":{}}"#);
        }
    }
}

fn say(bytes: &[u8]) {
    let mut output = std::io::stdout().lock();
    output.write_all(bytes).unwrap();
    output.flush().unwrap();
}

fn say_frame(body: &str) {
    say(format!("Content-Length: {}\r\n\r\n{body}", body.len()).as_bytes());
}

fn session(mode: &str) -> Session {
    session_with(
        mode,
        None,
        Limits {
            request_timeout: Duration::from_secs(2),
            ..Limits::DEFAULT
        },
    )
}

fn session_with(mode: &str, arg: Option<&str>, limits: Limits) -> Session {
    let mut args = vec![OsString::from("--adapter"), OsString::from(mode)];
    if let Some(arg) = arg {
        args.push(OsString::from(arg));
    }
    Session::spawn_mep(
        &std::env::current_exe().unwrap().into_os_string(),
        &args,
        limits,
    )
    .unwrap()
}

fn malformed_frames_and_jsonrpc_envelopes_break_the_session() {
    for raw in [
        "Content-Length: 2\n\n{}",
        "Content-Length: 2\r\ncontent-length: 2\r\n\r\n{}",
        "X-Other: 2\r\n\r\n{}",
        "Content-Length: +2\r\n\r\n{}",
        "Content-Length: 2.0\r\n\r\n{}",
        "Content-Length: -2\r\n\r\n{}",
        "Content-Length: \r\n\r\n{}",
        "Content-Length: 20\r\n\r\n{}",
        "Content-Length: 2\r\n",
        "log output\n",
    ] {
        let mut session = session_with("raw", Some(raw), Limits::DEFAULT);
        let failure = session
            .exchange_mep("morphir.ping", &json!({}))
            .unwrap_err();
        assert!(
            matches!(failure, TransportError::Malformed(_)),
            "{raw:?}: {failure:?}"
        );
        assert_eq!(
            session.exchange_mep("morphir.ping", &json!({})),
            Err(failure.clone())
        );
        assert_eq!(
            session.notify_mep("morphir.initialized", &json!({})),
            Err(failure.clone())
        );
        assert_eq!(session.assert_silence(Duration::ZERO), Err(failure));
        session.close().unwrap();
    }
    for body in [
        "[]",
        "null",
        "{",
        "{}",
        r#"{"jsonrpc":"1.0","id":1,"result":null}"#,
        r#"{"jsonrpc":"2.0","id":null,"result":null}"#,
        r#"{"jsonrpc":"2.0","id":"1","result":null}"#,
        r#"{"jsonrpc":"2.0","id":1.00000000000000001,"result":null}"#,
        r#"{"jsonrpc":"2.0","id":1,"result":null,"error":{"code":-1,"message":"no"}}"#,
        r#"{"jsonrpc":"2.0","id":1}"#,
        r#"{"jsonrpc":"2.0","id":1,"result":null,"method":"bad"}"#,
        r#"{"jsonrpc":"2.0","id":1,"error":null}"#,
        r#"{"jsonrpc":"2.0","id":1,"error":{"code":1.1,"message":"bad"}}"#,
        r#"{"jsonrpc":"2.0","id":1,"error":{"code":1}}"#,
        r#"{"jsonrpc":"2.0","id":1,"result":null,"id":1}"#,
        r#"{"jsonrpc":"2.0","id":1,"result":{"a":1,"\u0061":2}}"#,
        r#"{"jsonrpc":"2.0","id":1,"result":[{"a":1,"a":2}]}"#,
    ] {
        let mut session = session_with("body", Some(body), Limits::DEFAULT);
        let failure = session
            .exchange_mep("morphir.ping", &json!({}))
            .unwrap_err();
        assert!(
            matches!(failure, TransportError::Malformed(_)),
            "{body}: {failure:?}"
        );
        session.close().unwrap();
    }
    let mut session = session_with(
        "body",
        Some(r#"{"jsonrpc":"2.0","id":2,"result":null}"#),
        Limits::DEFAULT,
    );
    assert_eq!(
        session.exchange_mep("morphir.ping", &Value::Null),
        Err(TransportError::WrongId {
            expected: 1,
            got: 2
        })
    );
}

fn protocol_errors_and_literal_private_members_are_preserved() {
    let body = r#"{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"unknown","data":{"$serde_json::private::RawValue":"true"}}}"#;
    let mut session = session_with("body", Some(body), Limits::DEFAULT);
    let response = session.exchange_mep("unknown", &Value::Null).unwrap();
    assert_eq!(response["error"]["code"], -32601);
    assert_eq!(
        response["error"]["data"]
            .as_object()
            .unwrap()
            .get("$serde_json::private::RawValue")
            .unwrap(),
        "true"
    );
    session.close().unwrap();
}

fn oversized_headers_and_bodies_are_bounded() {
    for raw in [
        "Content-Length: 99999999999999999999999999999999999999\r\n\r\n".to_owned(),
        "Content-Length: 1000000\r\n\r\n".to_owned(),
        format!(
            "X-Long: {}\r\nContent-Length: 2\r\n\r\n{{}}",
            "x".repeat(8192)
        ),
    ] {
        let mut session = session_with(
            "raw",
            Some(&raw),
            Limits {
                max_frame: 64,
                ..Limits::DEFAULT
            },
        );
        let failure = session
            .exchange_mep("morphir.ping", &json!({}))
            .unwrap_err();
        assert!(
            matches!(
                failure,
                TransportError::Malformed(_) | TransportError::FrameTooLong { limit: 64 }
            ),
            "{failure:?}"
        );
        session.close().unwrap();
    }
}

fn notifications_must_be_silent_and_unsolicited_output_fails() {
    let mut session = session("notification-reply");
    session
        .notify_mep("morphir.initialized", &json!({}))
        .unwrap();
    assert!(matches!(
        session.exchange_mep("morphir.ping", &json!({})),
        Err(TransportError::Malformed(_))
    ));
    session.close().unwrap();

    let mut session = self::session("unsolicited");
    session.exchange_mep("morphir.ping", &json!({})).unwrap();
    assert!(matches!(
        session.assert_silence(Duration::from_secs(1)),
        Err(TransportError::Malformed(_))
    ));
    session.close().unwrap();

    let mut session = self::session("exit-reply");
    session
        .exchange_mep("morphir.shutdown", &Value::Null)
        .unwrap();
    assert!(matches!(session.close(), Err(TransportError::Shutdown(_))));
}

fn request_writes_reads_and_silence_share_session_limits() {
    for mode in ["stalled-stdin", "silent"] {
        let mut session = session_with(
            mode,
            None,
            Limits {
                request_timeout: Duration::from_millis(100),
                ..Limits::DEFAULT
            },
        );
        let params = if mode == "stalled-stdin" {
            json!({"large":"x".repeat(4 * 1024 * 1024)})
        } else {
            Value::Null
        };
        let start = Instant::now();
        assert!(matches!(
            session.exchange_mep("morphir.ping", &params),
            Err(TransportError::Timeout { .. })
        ));
        session.close().unwrap();
        assert!(start.elapsed() < Duration::from_secs(2));
    }
    let mut session = session_with(
        "echo",
        None,
        Limits {
            session_timeout: Duration::from_millis(80),
            ..Limits::DEFAULT
        },
    );
    assert!(matches!(
        session.assert_silence(Duration::from_secs(1)),
        Err(TransportError::SessionTimeout { .. })
    ));
    session.close().unwrap();
}

fn stderr_is_drained_without_blocking_mep() {
    let mut session = session("stderr");
    session.exchange_mep("morphir.ping", &json!({})).unwrap();
    assert_eq!(session.stderr().len(), Limits::DEFAULT.stderr_capture);
    session.close().unwrap();
}

fn fragmented_and_formatted_bodies_are_accepted_and_invalid_utf8_is_refused() {
    let mut session = session("fragmented");
    assert_eq!(
        session
            .exchange_mep("morphir.ping", &json!({"unicode":"λ"}))
            .unwrap()["result"],
        json!({"unicode":"λ"})
    );
    session.close().unwrap();
    let mut session = self::session("invalid-utf8");
    assert!(matches!(
        session.exchange_mep("morphir.ping", &Value::Null),
        Err(TransportError::Malformed(_))
    ));
    session.close().unwrap();
}

fn closing_a_mep_session_terminates_descendants_after_clean_parent_exit() {
    let root = tempfile::tempdir().unwrap();
    let heartbeat = root.path().join("heartbeat");
    let mut session = session_with("child", Some(heartbeat.to_str().unwrap()), Limits::DEFAULT);
    session
        .exchange_mep("morphir.shutdown", &Value::Null)
        .unwrap();
    session.close().unwrap();
    std::thread::sleep(Duration::from_millis(100));
    let stopped = std::fs::metadata(&heartbeat).unwrap().len();
    assert!(stopped > 0);
    std::thread::sleep(Duration::from_millis(100));
    assert_eq!(std::fs::metadata(&heartbeat).unwrap().len(), stopped);
}

fn dropping_an_exited_mep_guest_still_terminates_its_descendants() {
    let root = tempfile::tempdir().unwrap();
    let heartbeat = root.path().join("heartbeat");
    let mut session = session_with(
        "child-exit",
        Some(heartbeat.to_str().unwrap()),
        Limits::DEFAULT,
    );
    let cleanup = session.terminator();
    session.exchange_mep("morphir.ping", &Value::Null).unwrap();
    assert!(matches!(
        session.assert_silence(Duration::from_secs(1)),
        Err(TransportError::Closed {
            status: Some(_),
            ..
        })
    ));
    drop(session);
    std::thread::sleep(Duration::from_millis(100));
    let stopped = std::fs::metadata(&heartbeat).unwrap().len();
    std::thread::sleep(Duration::from_millis(100));
    let after = std::fs::metadata(&heartbeat).unwrap().len();
    cleanup.kill();
    assert_eq!(after, stopped, "Drop left the exited guest's child alive");
}

fn a_guest_that_exits_before_the_exit_notification_fails_shutdown() {
    let mut session = session("early-exit");
    session
        .exchange_mep("morphir.shutdown", &json!({}))
        .unwrap();
    std::thread::sleep(Duration::from_millis(100));
    assert!(matches!(session.close(), Err(TransportError::Shutdown(_))));
}

fn unknown_headers_are_ignored_and_header_names_are_case_insensitive() {
    let mut session = session("extra-header");
    assert!(session.exchange_mep("morphir.ping", &json!({})).is_ok());
    session.close().unwrap();
}

fn framed_exchange_preserves_jsonrpc_envelope_and_notification_order() {
    let mut session = Session::spawn_mep(
        &std::env::current_exe().unwrap().into_os_string(),
        &[OsString::from("--adapter")],
        Limits {
            request_timeout: Duration::from_secs(2),
            ..Limits::DEFAULT
        },
    )
    .unwrap();
    session
        .notify_mep("morphir.initialized", &json!({}))
        .unwrap();
    let response = session
        .exchange_mep("morphir.ping", &json!({"text":"λ\nbytes"}))
        .unwrap();
    assert_eq!(
        response,
        json!({"jsonrpc":"2.0", "id":1, "result":{"text":"λ\nbytes"}})
    );
    session.assert_silence(Duration::from_millis(20)).unwrap();
    session
        .exchange_mep("morphir.shutdown", &Value::Null)
        .unwrap();
    session.close().unwrap();
}

fn main() {
    if std::env::args().nth(1).as_deref() == Some("--heartbeat") {
        let mut output = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(std::env::args().nth(2).unwrap())
            .unwrap();
        loop {
            output.write_all(b".").unwrap();
            output.flush().unwrap();
            std::thread::sleep(Duration::from_millis(20));
        }
    }
    if std::env::args().nth(1).as_deref() == Some("--adapter") {
        adapter(&std::env::args().nth(2).unwrap_or_default());
        return;
    }
    let tests: &[(&str, fn())] = &[
        (
            "framed_exchange_preserves_jsonrpc_envelope_and_notification_order",
            framed_exchange_preserves_jsonrpc_envelope_and_notification_order,
        ),
        (
            "unknown_headers_are_ignored_and_header_names_are_case_insensitive",
            unknown_headers_are_ignored_and_header_names_are_case_insensitive,
        ),
        (
            "malformed_frames_and_jsonrpc_envelopes_break_the_session",
            malformed_frames_and_jsonrpc_envelopes_break_the_session,
        ),
        (
            "protocol_errors_and_literal_private_members_are_preserved",
            protocol_errors_and_literal_private_members_are_preserved,
        ),
        (
            "oversized_headers_and_bodies_are_bounded",
            oversized_headers_and_bodies_are_bounded,
        ),
        (
            "notifications_must_be_silent_and_unsolicited_output_fails",
            notifications_must_be_silent_and_unsolicited_output_fails,
        ),
        (
            "request_writes_reads_and_silence_share_session_limits",
            request_writes_reads_and_silence_share_session_limits,
        ),
        (
            "stderr_is_drained_without_blocking_mep",
            stderr_is_drained_without_blocking_mep,
        ),
        (
            "fragmented_and_formatted_bodies_are_accepted_and_invalid_utf8_is_refused",
            fragmented_and_formatted_bodies_are_accepted_and_invalid_utf8_is_refused,
        ),
        (
            "closing_a_mep_session_terminates_descendants_after_clean_parent_exit",
            closing_a_mep_session_terminates_descendants_after_clean_parent_exit,
        ),
        (
            "dropping_an_exited_mep_guest_still_terminates_its_descendants",
            dropping_an_exited_mep_guest_still_terminates_its_descendants,
        ),
        (
            "a_guest_that_exits_before_the_exit_notification_fails_shutdown",
            a_guest_that_exits_before_the_exit_notification_fails_shutdown,
        ),
    ];
    let filter = std::env::args().skip(1).find(|arg| !arg.starts_with('-'));
    let mut failed = 0;
    let mut ran = 0;
    for (name, test) in tests {
        if filter
            .as_ref()
            .is_some_and(|filter| !name.contains(filter.as_str()))
        {
            continue;
        }
        ran += 1;
        let passed = std::panic::catch_unwind(test).is_ok();
        println!("test {name} ... {}", if passed { "ok" } else { "FAILED" });
        failed += usize::from(!passed);
    }
    println!("{ran} tests, {failed} failed");
    if failed != 0 {
        std::process::exit(101);
    }
}
