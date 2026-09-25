//! Adapter sessions against real processes (`spec/mck/cli-contract.md`,
//! "Adapter transport" and "Test obligations").
//!
//! This binary is its own set of adapters: started as
//! `transport --mck-test-adapter <mode> [arg]` it plays the named adapter
//! instead of running tests, so hostile behaviour needs no other runtime.
//! One mode replays the frozen protocol transcript of the TypeScript adapter
//! (`spec/mck/baseline/transcripts/`), checking every request byte for byte.

use std::ffi::OsString;
use std::io::{BufRead, Write};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use morphir_mck::transport::protocol::{
    Request, parse_capabilities, parse_decode_response, parse_envelope, parse_request,
    parse_write_tree_response,
};
use morphir_mck::transport::{Limits, Session, TransportError};
use serde_json::Value;

const ADAPTER_FLAG: &str = "--mck-test-adapter";

const CAPABILITIES: &str = r#""contractVersion":1,"binding":"test","language":"rust","formatVersions":"[4.0.0,4.1.0)","versions":[4],"profiles":["json","yaml"],"layouts":["single","tree"],"paths":["current","pinned"],"nodes":["Type"]"#;

// ---------------------------------------------------------------- adapters

mod adapter {
    use super::*;

    fn requests() -> impl Iterator<Item = (u64, String)> {
        std::io::stdin()
            .lock()
            .lines()
            .map_while(Result::ok)
            .map(|line| {
                let id = parse_envelope(&line).map(|(id, _)| id).unwrap_or(0);
                (id, line)
            })
    }

    fn say(text: &[u8]) {
        let mut out = std::io::stdout().lock();
        out.write_all(text).unwrap();
        out.flush().unwrap();
    }

    fn capabilities(id: u64) {
        say(format!("{{\"id\":{id},{CAPABILITIES}}}\n").as_bytes());
    }

    fn is_exit(line: &str) -> bool {
        line.contains("\"op\":\"exit\"")
    }

    fn hang() -> ! {
        loop {
            std::thread::sleep(Duration::from_secs(60));
        }
    }

    pub fn run(mode: &str, arg: Option<&str>) {
        match mode {
            // Answers capabilities, decodes to a fixed result, exits on request.
            "good" => {
                for (id, line) in requests() {
                    if is_exit(&line) {
                        std::process::exit(0);
                    } else if line.contains("\"op\":\"capabilities\"") {
                        capabilities(id);
                    } else {
                        say(format!("{{\"id\":{id},\"ok\":true,\"kind\":\"Unit\",\"canonical\":{{\"yaml\":\"Unit: {{}}\\n\"}},\"warnings\":[]}}\n").as_bytes());
                    }
                }
            }
            "extra-on-exit" => {
                for (id, line) in requests() {
                    if is_exit(&line) {
                        capabilities(id);
                        return;
                    }
                    capabilities(id);
                }
            }
            // Answers capabilities, then leaves without answering.
            "eof" => {
                let mut requests = requests();
                if let Some((id, _)) = requests.next() {
                    capabilities(id);
                }
                let _ = requests.next();
                std::process::exit(0);
            }
            "crash" => {
                let _ = requests().next();
                eprint!("boom");
                std::process::exit(3);
            }
            "not-json" => {
                let _ = requests().next();
                say(b"hello\n");
                hang();
            }
            "wrong-id" => {
                if let Some((id, _)) = requests().next() {
                    capabilities(id + 1);
                }
                hang();
            }
            "bad-utf8" => {
                let _ = requests().next();
                say(b"\xff\xfe{}\n");
                hang();
            }
            "huge" => {
                let _ = requests().next();
                say(&[b'x'; 4096]);
                say(b"\n");
                hang();
            }
            "stdout-flood" => {
                let _ = requests().next();
                let chunk = [b'x'; 65536];
                loop {
                    let mut out = std::io::stdout().lock();
                    if out.write_all(&chunk).is_err() {
                        std::process::exit(0);
                    }
                }
            }
            "stderr-flood" => {
                let chunk = [b'e'; 65536];
                for _ in 0..128 {
                    std::io::stderr().lock().write_all(&chunk).unwrap();
                }
                run("good", None);
            }
            "hang" => hang(),
            "stdin-stall" => {
                if let Some(file) = arg {
                    #[allow(clippy::zombie_processes)]
                    std::process::Command::new(std::env::current_exe().unwrap())
                        .args([ADAPTER_FLAG, "heartbeat", file])
                        .spawn()
                        .unwrap();
                }
                if let Some((id, _)) = requests().next() {
                    capabilities(id);
                }
                hang();
            }
            "slow-io" => {
                let mut requests = requests();
                if let Some((id, _)) = requests.next() {
                    capabilities(id);
                }
                std::thread::sleep(Duration::from_millis(200));
                if let Some((id, _)) = requests.next() {
                    std::thread::sleep(Duration::from_millis(200));
                    capabilities(id);
                }
                hang();
            }
            "slow" => {
                for (id, line) in requests() {
                    if is_exit(&line) {
                        std::process::exit(0);
                    }
                    std::thread::sleep(Duration::from_millis(250));
                    capabilities(id);
                }
            }
            "ignore-exit" => {
                for (id, line) in requests() {
                    if !is_exit(&line) {
                        capabilities(id);
                    }
                }
                hang();
            }
            "exit-7" => {
                for (id, line) in requests() {
                    if is_exit(&line) {
                        std::process::exit(7);
                    }
                    capabilities(id);
                }
            }
            // Starts a heartbeat grandchild, answers capabilities, never exits.
            "parent" => {
                let file = arg.expect("parent needs a heartbeat file");
                let mut command = std::process::Command::new(std::env::current_exe().unwrap());
                command.args([ADAPTER_FLAG, "heartbeat", file]);
                #[cfg(windows)]
                {
                    use std::os::windows::process::CommandExt as _;
                    command.creation_flags(0x0800_0000);
                }
                // Never waited on: terminating the adapter's tree must reap it.
                #[allow(clippy::zombie_processes)]
                command.spawn().unwrap();
                for (id, line) in requests() {
                    if !is_exit(&line) {
                        capabilities(id);
                    }
                }
                hang();
            }
            "heartbeat" => {
                let file = arg.expect("heartbeat needs a file");
                loop {
                    let mut out = std::fs::OpenOptions::new()
                        .create(true)
                        .append(true)
                        .open(file)
                        .unwrap();
                    out.write_all(b".").unwrap();
                    drop(out);
                    std::thread::sleep(Duration::from_millis(40));
                }
            }
            // Answers from the transcript, refusing any request that is not
            // byte for byte the one the first driver sent.
            "replay" => {
                let exchanges = transcript(Path::new(arg.expect("replay needs a transcript")));
                let mut exchanges = exchanges.into_iter();
                for (_, line) in requests() {
                    let Some((expected, response)) = exchanges.next() else {
                        eprint!("more requests than the transcript holds");
                        std::process::exit(2);
                    };
                    if line != expected {
                        eprint!(
                            "request differs from the transcript:\n sent     {line}\n recorded {expected}"
                        );
                        std::process::exit(2);
                    }
                    match response {
                        Some(response) => say(format!("{response}\n").as_bytes()),
                        None => std::process::exit(0),
                    }
                }
            }
            other => panic!("unknown adapter mode {other}"),
        }
    }
}

/// The transcript's exchanges, as the raw request line and the raw response
/// line, if any (the final `exit` has none).
fn transcript(path: &Path) -> Vec<(String, Option<String>)> {
    const REQUEST: &str = "{\"dir\":\"request\",\"message\":";
    const RESPONSE: &str = "{\"dir\":\"response\",\"message\":";
    let text = std::fs::read_to_string(path).unwrap();
    let mut exchanges: Vec<(String, Option<String>)> = Vec::new();
    for line in text.lines().filter(|l| !l.is_empty()) {
        let raw = |prefix: &str| {
            line.strip_prefix(prefix)
                .and_then(|rest| rest.strip_suffix('}'))
                .map(str::to_owned)
        };
        if let Some(request) = raw(REQUEST) {
            exchanges.push((request, None));
        } else if let Some(response) = raw(RESPONSE) {
            exchanges
                .last_mut()
                .expect("a response follows its request")
                .1 = Some(response);
        } else {
            panic!("not a transcript line: {line}");
        }
    }
    exchanges
}

// ---------------------------------------------------------------- tests

fn session(mode: &str, arg: Option<&Path>, limits: Limits) -> Session {
    let exe = std::env::current_exe().unwrap().into_os_string();
    let mut args: Vec<OsString> = vec![ADAPTER_FLAG.into(), mode.into()];
    args.extend(arg.map(|a| a.as_os_str().to_owned()));
    Session::spawn(&exe, &args, limits).unwrap()
}

fn quick() -> Limits {
    Limits {
        request_timeout: Duration::from_secs(10),
        shutdown_grace: Duration::from_millis(500),
        ..Limits::DEFAULT
    }
}

fn a_healthy_adapter_answers_and_exits_cleanly() {
    let mut s = session("good", None, quick());
    let caps = s.exchange(&Request::Capabilities).unwrap();
    assert_eq!(
        parse_capabilities(&Value::Object(caps)).unwrap().binding,
        "test"
    );
    let decoded = s
        .exchange(&Request::Decode {
            version: 4,
            profile: morphir_mck::transport::protocol::Profile::Yaml,
            path: morphir_mck::transport::protocol::PathMode::Current,
            strip: true,
            node: "Type".into(),
            input: "Unit: {}\n".into(),
        })
        .unwrap();
    assert!(parse_decode_response(&Value::Object(decoded)).is_ok());
    s.close().unwrap();
}

fn an_unsolicited_reply_after_exit_fails_shutdown() {
    let mut s = session("extra-on-exit", None, quick());
    s.exchange(&Request::Capabilities).unwrap();
    let error = s.close().unwrap_err();
    assert!(error.to_string().contains("unsolicited"), "{error}");
}

fn expect_failure(mode: &str, limits: Limits, check: impl Fn(&TransportError)) {
    let mut s = session(mode, None, limits);
    let error = s.exchange(&Request::Capabilities).unwrap_err();
    check(&error);
    // The session is broken for good: the next exchange is the same failure.
    assert_eq!(s.exchange(&Request::Capabilities).unwrap_err(), error);
    let started = Instant::now();
    s.close().unwrap();
    assert!(
        started.elapsed() < Duration::from_secs(3),
        "a broken session is torn down at once"
    );
}

fn an_adapter_that_leaves_without_answering_is_a_closed_transport() {
    let mut s = session("eof", None, quick());
    s.exchange(&Request::Capabilities).unwrap();
    let error = s.exchange(&Request::Capabilities).unwrap_err();
    assert_eq!(
        error,
        TransportError::Closed {
            status: Some("code 0".into()),
            stderr: String::new()
        },
        "{error}"
    );
    s.close().unwrap();
}

fn a_crash_reports_its_exit_code_and_stderr() {
    expect_failure("crash", quick(), |e| {
        assert_eq!(e.to_string(), "adapter exited with code 3; stderr: boom")
    });
}

fn malformed_frames_and_wrong_ids_are_transport_failures() {
    expect_failure("not-json", quick(), |e| {
        assert_eq!(e.to_string(), "not a JSON line: hello")
    });
    expect_failure("wrong-id", quick(), |e| {
        assert_eq!(
            *e,
            TransportError::WrongId {
                expected: 1,
                got: 2
            }
        )
    });
    expect_failure("bad-utf8", quick(), |e| {
        assert_eq!(e.to_string(), "adapter sent a frame that is not UTF-8")
    });
}

fn frames_over_the_bound_fail_without_exhausting_memory() {
    let small = Limits {
        max_frame: 1024,
        ..quick()
    };
    expect_failure("huge", small, |e| {
        assert_eq!(*e, TransportError::FrameTooLong { limit: 1024 })
    });
    let bounded = Limits {
        max_frame: 1024 * 1024,
        ..quick()
    };
    expect_failure("stdout-flood", bounded, |e| {
        assert_eq!(*e, TransportError::FrameTooLong { limit: 1024 * 1024 })
    });
}

fn a_silent_adapter_times_out_and_a_slow_one_exceeds_the_session() {
    let short = Limits {
        request_timeout: Duration::from_millis(300),
        ..quick()
    };
    expect_failure("hang", short, |e| {
        assert_eq!(
            e.to_string(),
            "adapter timed out after 300 ms waiting for id 1"
        )
    });

    let session_bound = Limits {
        session_timeout: Duration::from_millis(400),
        ..quick()
    };
    let mut s = session("slow", None, session_bound);
    s.exchange(&Request::Capabilities).unwrap();
    let error = s.exchange(&Request::Capabilities).unwrap_err();
    assert_eq!(error, TransportError::SessionTimeout { millis: 400 });
    s.close().unwrap();
}

fn a_chatty_stderr_never_blocks_the_session() {
    let mut s = session("stderr-flood", None, quick());
    s.exchange(&Request::Capabilities).unwrap();
    assert_eq!(s.stderr().len(), Limits::DEFAULT.stderr_capture);
    s.close().unwrap();
}

fn large_request() -> Request {
    Request::Decode {
        version: 4,
        profile: morphir_mck::transport::protocol::Profile::Json,
        path: morphir_mck::transport::protocol::PathMode::Current,
        strip: false,
        node: "Type".into(),
        input: "x".repeat(2 * 1024 * 1024),
    }
}

// The watchdog makes the old blocking-write failure terminate and clean up
// instead of hanging the test process indefinitely.
fn guarded_exchange(
    s: &mut Session,
    request: &Request,
) -> (
    Result<serde_json::Map<String, Value>, TransportError>,
    Duration,
) {
    let terminator = s.terminator();
    let (finished, wait) = std::sync::mpsc::channel();
    let watchdog = std::thread::spawn(move || {
        if wait.recv_timeout(Duration::from_secs(2)).is_err() {
            terminator.kill();
        }
    });
    let started = Instant::now();
    let response = s.exchange(request);
    let elapsed = started.elapsed();
    let _ = finished.send(());
    watchdog.join().unwrap();
    (response, elapsed)
}

fn stalled_stdin_obeys_request_and_session_deadlines_and_cleans_up_children() {
    for session_bound in [false, true] {
        let directory = tempfile::tempdir().unwrap();
        let heartbeat = directory.path().join("heartbeat");
        let limits = if session_bound {
            Limits {
                request_timeout: Duration::from_secs(10),
                session_timeout: Duration::from_millis(250),
                ..quick()
            }
        } else {
            Limits {
                request_timeout: Duration::from_millis(100),
                ..quick()
            }
        };
        let mut s = session("stdin-stall", Some(&heartbeat), limits);
        s.exchange(&Request::Capabilities).unwrap();
        let (response, elapsed) = guarded_exchange(&mut s, &large_request());
        let close_started = Instant::now();
        s.close().unwrap();
        assert!(
            close_started.elapsed() < Duration::from_secs(1),
            "broken cleanup exceeded bound"
        );
        assert!(
            elapsed < Duration::from_secs(1),
            "blocked stdin ignored deadline: {elapsed:?}"
        );
        let error = response.unwrap_err();
        if session_bound {
            assert_eq!(error, TransportError::SessionTimeout { millis: 250 });
        } else {
            assert_eq!(error, TransportError::Timeout { id: 2, millis: 100 });
        }
        std::thread::sleep(Duration::from_millis(150));
        let stopped = size(&heartbeat);
        assert!(stopped > 0, "grandchild never started");
        std::thread::sleep(Duration::from_millis(150));
        assert_eq!(
            size(&heartbeat),
            stopped,
            "stdin timeout left a child running"
        );
    }
}

fn writes_and_reads_share_one_request_deadline() {
    let limits = Limits {
        request_timeout: Duration::from_millis(300),
        ..quick()
    };
    let mut s = session("slow-io", None, limits);
    s.exchange(&Request::Capabilities).unwrap();
    let (response, elapsed) = guarded_exchange(&mut s, &large_request());
    let _ = s.close();
    assert!(elapsed < Duration::from_secs(1));
    assert_eq!(
        response.unwrap_err(),
        TransportError::Timeout { id: 2, millis: 300 }
    );
}

fn an_adapter_that_ignores_exit_or_fails_it_is_a_shutdown_failure() {
    let mut s = session("ignore-exit", None, quick());
    s.exchange(&Request::Capabilities).unwrap();
    let error = s.close().unwrap_err();
    assert_eq!(
        error.to_string(),
        "adapter shutdown failed: it did not exit within 500 ms of the exit request and was terminated"
    );

    let mut s = session("exit-7", None, quick());
    s.exchange(&Request::Capabilities).unwrap();
    assert_eq!(
        s.close().unwrap_err().to_string(),
        "adapter shutdown failed: it exited with code 7"
    );
}

fn a_missing_program_is_a_spawn_failure() {
    let error = Session::spawn(
        &OsString::from("definitely-not-an-mck-adapter"),
        &[],
        quick(),
    )
    .err()
    .unwrap();
    assert!(matches!(error, TransportError::Spawn(_)), "{error}");
    assert!(error.to_string().starts_with("failed to start adapter: "));
}

fn size(path: &Path) -> u64 {
    std::fs::metadata(path).map(|m| m.len()).unwrap_or(0)
}

fn terminating_an_adapter_takes_its_children_with_it() {
    let dir = tempfile::tempdir().unwrap();
    let heartbeat = dir.path().join("heartbeat");
    let mut s = session("parent", Some(&heartbeat), quick());
    s.exchange(&Request::Capabilities).unwrap();
    let started = Instant::now();
    while size(&heartbeat) < 3 {
        assert!(
            started.elapsed() < Duration::from_secs(10),
            "the grandchild never started"
        );
        std::thread::sleep(Duration::from_millis(20));
    }
    assert!(s.close().is_err(), "the parent ignores exit");
    std::thread::sleep(Duration::from_millis(300));
    let after = size(&heartbeat);
    std::thread::sleep(Duration::from_millis(500));
    assert_eq!(
        size(&heartbeat),
        after,
        "the grandchild outlived its adapter"
    );
}

fn transcript_path() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../spec/mck/baseline/transcripts/morphir-typescript.ndjson")
}

/// Every request the first driver sent, re-sent by this transport from its
/// parsed form: the replaying adapter refuses any byte difference, and every
/// recorded answer must pass this crate's response checks.
fn the_frozen_transcript_replays_byte_for_byte() {
    let path = transcript_path();
    let exchanges = transcript(&path);
    assert_eq!(exchanges.len(), 706);
    let mut s = session("replay", Some(&path), quick());
    let mut answered = 0;
    for (raw, response) in &exchanges {
        let (_, body) = parse_envelope(raw).unwrap();
        let request = parse_request(&Value::Object(body)).unwrap();
        if request == Request::Exit {
            assert!(response.is_none());
            break;
        }
        let answer = Value::Object(
            s.exchange(&request)
                .unwrap_or_else(|e| panic!("{e}; adapter said: {}", s.stderr())),
        );
        match &request {
            Request::Capabilities => {
                let caps = parse_capabilities(&answer).unwrap();
                assert_eq!(caps.format_versions, "[4.0.0,4.1.0)");
            }
            Request::Decode { .. } | Request::ReadTree { .. } => {
                parse_decode_response(&answer).unwrap();
            }
            Request::WriteTree { .. } => {
                parse_write_tree_response(&answer).unwrap();
            }
            Request::Exit => unreachable!(),
        }
        answered += 1;
    }
    assert_eq!(answered, 705);
    let said = s.stderr();
    s.close()
        .unwrap_or_else(|e| panic!("{e}; adapter said: {said}"));
}

// ---------------------------------------------------------------- runner

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.get(1).map(String::as_str) == Some(ADAPTER_FLAG) {
        adapter::run(&args[2], args.get(3).map(String::as_str));
        return;
    }

    let tests: &[(&str, fn())] = &[
        (
            "an_unsolicited_reply_after_exit_fails_shutdown",
            an_unsolicited_reply_after_exit_fails_shutdown,
        ),
        (
            "a_healthy_adapter_answers_and_exits_cleanly",
            a_healthy_adapter_answers_and_exits_cleanly,
        ),
        (
            "an_adapter_that_leaves_without_answering_is_a_closed_transport",
            an_adapter_that_leaves_without_answering_is_a_closed_transport,
        ),
        (
            "a_crash_reports_its_exit_code_and_stderr",
            a_crash_reports_its_exit_code_and_stderr,
        ),
        (
            "malformed_frames_and_wrong_ids_are_transport_failures",
            malformed_frames_and_wrong_ids_are_transport_failures,
        ),
        (
            "frames_over_the_bound_fail_without_exhausting_memory",
            frames_over_the_bound_fail_without_exhausting_memory,
        ),
        (
            "a_silent_adapter_times_out_and_a_slow_one_exceeds_the_session",
            a_silent_adapter_times_out_and_a_slow_one_exceeds_the_session,
        ),
        (
            "a_chatty_stderr_never_blocks_the_session",
            a_chatty_stderr_never_blocks_the_session,
        ),
        (
            "stalled_stdin_obeys_request_and_session_deadlines_and_cleans_up_children",
            stalled_stdin_obeys_request_and_session_deadlines_and_cleans_up_children,
        ),
        (
            "writes_and_reads_share_one_request_deadline",
            writes_and_reads_share_one_request_deadline,
        ),
        (
            "an_adapter_that_ignores_exit_or_fails_it_is_a_shutdown_failure",
            an_adapter_that_ignores_exit_or_fails_it_is_a_shutdown_failure,
        ),
        (
            "a_missing_program_is_a_spawn_failure",
            a_missing_program_is_a_spawn_failure,
        ),
        (
            "terminating_an_adapter_takes_its_children_with_it",
            terminating_an_adapter_takes_its_children_with_it,
        ),
        (
            "the_frozen_transcript_replays_byte_for_byte",
            the_frozen_transcript_replays_byte_for_byte,
        ),
    ];
    let filter = args.iter().skip(1).find(|a| !a.starts_with('-')).cloned();
    let mut failed = Vec::new();
    let mut ran = 0;
    for (name, test) in tests {
        if filter.as_ref().is_some_and(|f| !name.contains(f.as_str())) {
            continue;
        }
        ran += 1;
        let outcome = std::panic::catch_unwind(test);
        println!(
            "test {name} ... {}",
            if outcome.is_ok() { "ok" } else { "FAILED" }
        );
        if outcome.is_err() {
            failed.push(*name);
        }
    }
    println!(
        "\ntest result: {}. {} passed; {} failed",
        if failed.is_empty() { "ok" } else { "FAILED" },
        ran - failed.len(),
        failed.len()
    );
    if !failed.is_empty() {
        std::process::exit(101);
    }
}
