//! Actual native controller/driver controls with a literal HTTP module fixture.
//! This fixture is not the Workbench host or evidence of product DATA/reporting.
use super::*;
use crate::workbench::model_originals::workflow::pipeline::browser::controller::ObservedLaunch;
use std::{
    io::{Read, Write},
    net::TcpListener,
    sync::{Arc, atomic::Ordering},
    thread::JoinHandle,
};

struct ModuleFixture {
    port: u16,
    entered: Arc<AtomicBool>,
    release: Arc<AtomicBool>,
    stop: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}
impl ModuleFixture {
    fn start() -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        listener.set_nonblocking(true).unwrap();
        let port = listener.local_addr().unwrap().port();
        let entered = Arc::new(AtomicBool::new(false));
        let release = Arc::new(AtomicBool::new(false));
        let stop = Arc::new(AtomicBool::new(false));
        let flags = (entered.clone(), release.clone(), stop.clone());
        let thread = std::thread::spawn(move || {
            let (entered, release, stop) = flags;
            while !stop.load(Ordering::Acquire) {
                let (mut stream, _) = match listener.accept() {
                    Ok(peer) => peer,
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                        std::thread::sleep(Duration::from_millis(1));
                        continue;
                    }
                    Err(error) => panic!("literal module listener: {error}"),
                };
                // Darwin accept can inherit the listener's O_NONBLOCK. This
                // literal fixture uses bounded blocking header reads instead.
                eprintln!(
                    "literal fixture inherited nonblocking: {}",
                    rustix::fs::fcntl_getfl(&stream)
                        .unwrap()
                        .contains(rustix::fs::OFlags::NONBLOCK)
                );
                stream.set_nonblocking(false).unwrap();
                stream
                    .set_read_timeout(Some(Duration::from_millis(500)))
                    .unwrap();
                stream
                    .set_write_timeout(Some(Duration::from_millis(500)))
                    .unwrap();
                let mut request = [0; 4096];
                let mut used = 0;
                while used < request.len() {
                    match stream.read(&mut request[used..]) {
                        Ok(0) | Err(_) => break,
                        Ok(count) => used += count,
                    }
                    if request[..used].windows(4).any(|bytes| bytes == b"\r\n\r\n") {
                        break;
                    }
                }
                let line = request[..used]
                    .split(|byte| *byte == b'\n')
                    .next()
                    .unwrap_or_default();
                let (status, headers, body) = if line.starts_with(b"GET /launch?token=") {
                    eprintln!("literal fixture: launch");
                    (
                        "302 Found",
                        "Location: /observed/?mode=connected-originals\r\n",
                        "",
                    )
                } else if line == b"GET /observed/?mode=connected-originals HTTP/1.1\r" {
                    eprintln!("literal fixture: document");
                    (
                        "200 OK",
                        "Content-Type: text/html\r\n",
                        "<!doctype html><title>literal module control</title>",
                    )
                } else if line == b"GET /observed/observed-document-entry.js HTTP/1.1\r" {
                    eprintln!("literal fixture: module");
                    (
                        "200 OK",
                        "Content-Type: text/javascript\r\n",
                        "await fetch('/module-gate');",
                    )
                } else if line == b"GET /module-gate HTTP/1.1\r" {
                    eprintln!("literal fixture: gate");
                    entered.store(true, Ordering::Release);
                    while !release.load(Ordering::Acquire) && !stop.load(Ordering::Acquire) {
                        std::thread::sleep(Duration::from_millis(1));
                    }
                    ("200 OK", "Content-Type: text/plain\r\n", "released")
                } else {
                    eprintln!("literal fixture: unmatched request, {} bytes", used);
                    ("404 Not Found", "", "")
                };
                let response = format!(
                    "HTTP/1.1 {status}\r\n{headers}Content-Length: {}\r\nConnection: close\r\n\r\n{body}",
                    body.len()
                );
                let _ = stream.write_all(response.as_bytes());
            }
        });
        Self {
            port,
            entered,
            release,
            stop,
            thread: Some(thread),
        }
    }
    fn launch(&self) -> ObservedLaunch {
        ObservedLaunch::parse(format!(
            "http://127.0.0.1:{}/launch?token={}",
            self.port,
            "A".repeat(43)
        ))
        .unwrap()
    }
    fn await_module(&self, actual: &mut Actual) {
        while !self.entered.load(Ordering::Acquire) {
            let polled = actual.owner().poll(&AtomicBool::new(false));
            if polled != Ok(ControllerProgress::Pending) {
                let outcome = Actual(actual.0.take()).finish();
                assert_eq!(
                    polled,
                    Ok(ControllerProgress::Pending),
                    "actual driver stdout={:?} stderr={:?}",
                    outcome
                        .driver()
                        .map(|value| String::from_utf8_lossy(value.process().stdout())),
                    outcome
                        .driver()
                        .map(|value| String::from_utf8_lossy(value.process().stderr()))
                );
            }
            std::thread::sleep(Duration::from_millis(1));
        }
    }
}
impl Drop for ModuleFixture {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Release);
        self.thread.take().unwrap().join().unwrap();
    }
}

#[test]
fn browser_controller_c06_observed_launch_accepts_only_closed_canonical_data() {
    let valid = format!("http://127.0.0.1:80/launch?token={}", "A".repeat(43));
    assert!(ObservedLaunch::parse(valid.clone()).is_ok());
    for invalid in [
        valid.replace(":80/", ":0/"),
        valid.replace(":80/", ":080/"),
        valid.replace(":80/", ":65536/"),
        valid.replace("127.0.0.1", "localhost"),
        valid.replace("http:", "https:"),
        format!("{valid}&extra=1"),
        format!("{valid}#fragment"),
        valid.replace("/launch?", "/arbitrary?"),
        valid.replace(&"A".repeat(43), &"A".repeat(42)),
        valid.replace(&"A".repeat(43), &format!("{}B", "A".repeat(42))),
    ] {
        assert!(ObservedLaunch::parse(invalid).is_err());
    }
    assert_eq!(
        parse_reply(b"1 document-started\n"),
        Ok(ControllerReply::ObservedDocumentStarted)
    );
}

#[test]
#[ignore = "requires explicit acquired Chromium/Node/Playwright; literal module native control"]
fn browser_controller_c07_native_observed_start_waits_for_actual_module_then_joins_both_roots() {
    let fixture = ModuleFixture::start();
    let directory = tempfile::tempdir().unwrap();
    let end = Instant::now() + limits().session_timeout;
    let mut actual = Actual(Some(
        BrowserController::launch_observed(
            target(directory.path()),
            limits(),
            end,
            fixture.launch(),
        )
        .unwrap(),
    ));
    assert_eq!(
        next(&mut actual),
        Ok(ControllerProgress::Reply(ControllerReply::Attached))
    );
    assert_eq!(
        actual
            .owner()
            .begin(ControllerCommand::StartObservedDocument),
        Ok(())
    );
    fixture.await_module(&mut actual);
    assert_eq!(
        actual.owner().poll(&AtomicBool::new(false)),
        Ok(ControllerProgress::Pending)
    );
    fixture.release.store(true, Ordering::Release);
    assert_eq!(
        next(&mut actual),
        Ok(ControllerProgress::Reply(
            ControllerReply::ObservedDocumentStarted
        ))
    );
    assert_eq!(actual.owner().end(), end);
    assert_eq!(
        actual
            .owner()
            .begin(ControllerCommand::ClosePageContextAndDisconnect),
        Ok(())
    );
    assert_eq!(
        next(&mut actual),
        Ok(ControllerProgress::Reply(ControllerReply::Disconnected))
    );
    assert_eq!(next(&mut actual), Ok(ControllerProgress::DriverJoined));
    assert!(matches!(
        actual.owner().chromium_state(),
        RootState::Running(_)
    ));
    let outcome = actual.finish();
    assert!(outcome.first_fault().is_none());
    assert_eq!(outcome.driver().unwrap().process().status().code(), Some(0));
    assert!(outcome.chromium().first_fault().is_none());
}

#[test]
#[ignore = "requires explicit acquired Chromium/Node/Playwright; original end while TLA pending"]
fn browser_controller_c08_never_settling_module_keeps_original_end_and_cleanup_joins() {
    let fixture = ModuleFixture::start();
    let directory = tempfile::tempdir().unwrap();
    let end = Instant::now() + Duration::from_secs(5);
    let mut actual = Actual(Some(
        BrowserController::launch_observed(
            target(directory.path()),
            limits(),
            end,
            fixture.launch(),
        )
        .unwrap(),
    ));
    assert_eq!(
        next(&mut actual),
        Ok(ControllerProgress::Reply(ControllerReply::Attached))
    );
    assert_eq!(
        actual
            .owner()
            .begin(ControllerCommand::StartObservedDocument),
        Ok(())
    );
    fixture.await_module(&mut actual);
    assert_eq!(next(&mut actual), Err(ControllerFault::End));
    assert_eq!(actual.owner().end(), end);
    let outcome = actual.finish();
    assert_eq!(outcome.first_fault(), Some(&ControllerFault::End));
    assert!(outcome.driver().is_some());
    assert!(
        !outcome
            .driver()
            .unwrap()
            .process()
            .stdout()
            .windows(b"1 document-started".len())
            .any(|bytes| bytes == b"1 document-started")
    );
}
