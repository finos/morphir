//! One adapter process speaking newline-delimited JSON (`spec/mck/cli-contract.md`,
//! "Adapter transport").
//!
//! Requests go one at a time with ids from 1. The adapter's stdout is read on
//! its own thread, a frame at a time, each bounded in size and required to be
//! UTF-8; stderr is drained on another thread so a chatty adapter never blocks
//! on a full pipe, and its first bytes are kept for messages. Every request
//! waits at most the request timeout, and the whole session at most the
//! session timeout.
//!
//! A transport failure is never a domain result. After the first one the
//! session is broken for good and every later exchange returns that same
//! failure. Closing sends the `exit` request, waits a grace period, and then
//! terminates the adapter's whole process tree.

use std::ffi::OsString;
use std::fmt;
use std::io::{BufRead, BufReader, Read, Write};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use serde_json::{Map, Value};

use super::protocol::{Request, parse_envelope};
use super::tree::{self, ProcessTree};

/// The bounds of one adapter session.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Limits {
    /// How long one request may wait for its answer.
    pub request_timeout: Duration,
    /// How long the whole session may last.
    pub session_timeout: Duration,
    /// The longest response frame, in bytes, without its newline.
    pub max_frame: usize,
    /// How much of the adapter's stderr is kept for messages.
    pub stderr_capture: usize,
    /// How long to wait for an exit status after stdout closes.
    pub exit_grace: Duration,
    /// How long to wait after the `exit` request before terminating.
    pub shutdown_grace: Duration,
}

impl Limits {
    /// The contract's values.
    pub const DEFAULT: Self = Self {
        request_timeout: Duration::from_millis(30_000),
        session_timeout: Duration::from_millis(1_800_000),
        max_frame: 16 * 1024 * 1024,
        stderr_capture: 4096,
        exit_grace: Duration::from_millis(1_000),
        shutdown_grace: Duration::from_millis(5_000),
    };
}

/// Why a session failed. None of these is ever read as a domain rejection.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransportError {
    Spawn(String),
    StdinClosed(String),
    /// The adapter's stdout ended, with its exit status when it came in time.
    Closed {
        status: Option<String>,
        stderr: String,
    },
    Malformed(String),
    WrongId {
        expected: u64,
        got: u64,
    },
    FrameTooLong {
        limit: usize,
    },
    Timeout {
        id: u64,
        millis: u128,
    },
    SessionTimeout {
        millis: u128,
    },
    /// The adapter would not stop, or stopped with a failure, after `exit`.
    Shutdown(String),
}

fn with_stderr(stderr: &str) -> String {
    if stderr.is_empty() {
        String::new()
    } else {
        format!("; stderr: {stderr}")
    }
}

impl fmt::Display for TransportError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Spawn(why) => write!(f, "failed to start adapter: {why}"),
            Self::StdinClosed(why) => write!(f, "adapter stdin closed: {why}"),
            Self::Closed {
                status: None,
                stderr,
            } => write!(f, "adapter closed stdout{}", with_stderr(stderr)),
            Self::Closed {
                status: Some(status),
                stderr,
            } => write!(f, "adapter exited with {status}{}", with_stderr(stderr)),
            Self::Malformed(why) => f.write_str(why),
            Self::WrongId { expected, got } => write!(f, "expected id {expected}, got {got}"),
            Self::FrameTooLong { limit } => write!(f, "adapter frame exceeds {limit} bytes"),
            Self::Timeout { id, millis } => {
                write!(f, "adapter timed out after {millis} ms waiting for id {id}")
            }
            Self::SessionTimeout { millis } => {
                write!(f, "adapter timed out: the session exceeded {millis} ms")
            }
            Self::Shutdown(why) => write!(f, "adapter shutdown failed: {why}"),
        }
    }
}

impl std::error::Error for TransportError {}

/// What the stdout thread reports.
enum Frame {
    Line(String),
    NotUtf8,
    TooLong,
    Failed(String),
    Eof,
}

/// Reads newline-terminated frames, each at most `max` bytes. A final chunk
/// with no newline is a frame too. Stops at the first frame it cannot pass on.
fn read_frames(stdout: impl Read, frames: Sender<Frame>, max: usize) {
    let mut reader = BufReader::with_capacity(64 * 1024, stdout);
    let mut line: Vec<u8> = Vec::new();
    let finish = |line: Vec<u8>, frames: &Sender<Frame>| -> bool {
        let mut line = line;
        if line.last() == Some(&b'\r') {
            line.pop();
        }
        let frame = String::from_utf8(line).map_or(Frame::NotUtf8, Frame::Line);
        let ok = matches!(frame, Frame::Line(_));
        frames.send(frame).is_ok() && ok
    };
    loop {
        let buffer = match reader.fill_buf() {
            Ok(buffer) => buffer,
            Err(error) if error.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(error) => {
                let _ = frames.send(Frame::Failed(error.to_string()));
                return;
            }
        };
        if buffer.is_empty() {
            if !line.is_empty() && !finish(std::mem::take(&mut line), &frames) {
                return;
            }
            let _ = frames.send(Frame::Eof);
            return;
        }
        let (taken, complete) = match buffer.iter().position(|&b| b == b'\n') {
            Some(at) => (at, true),
            None => (buffer.len(), false),
        };
        if line.len() + taken > max {
            let _ = frames.send(Frame::TooLong);
            return;
        }
        line.extend_from_slice(&buffer[..taken]);
        reader.consume(if complete { taken + 1 } else { taken });
        if complete && !finish(std::mem::take(&mut line), &frames) {
            return;
        }
    }
}

/// Drains stderr to its end, keeping the first `capture` bytes.
fn drain_stderr(mut stderr: impl Read, kept: Arc<Mutex<Vec<u8>>>, capture: usize) {
    let mut chunk = [0u8; 8192];
    loop {
        match stderr.read(&mut chunk) {
            Ok(0) => return,
            Ok(n) => {
                let mut kept = kept
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                let room = capture.saturating_sub(kept.len());
                kept.extend_from_slice(&chunk[..n.min(room)]);
            }
            Err(error) if error.kind() == std::io::ErrorKind::Interrupted => {}
            Err(_) => return,
        }
    }
}

/// A running adapter.
pub struct Session {
    child: Child,
    tree: ProcessTree,
    stdin: Option<ChildStdin>,
    frames: Receiver<Frame>,
    stderr: Arc<Mutex<Vec<u8>>>,
    next_id: u64,
    broken: Option<TransportError>,
    started: Instant,
    limits: Limits,
}

fn status_text(status: std::process::ExitStatus) -> String {
    match status.code() {
        Some(code) => format!("code {code}"),
        None => format!("status {status}"),
    }
}

impl Session {
    /// Starts `program` with `args`, its stdin, stdout and stderr piped.
    pub fn spawn(
        program: &OsString,
        args: &[OsString],
        limits: Limits,
    ) -> Result<Self, TransportError> {
        let mut command = Command::new(program);
        command
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        tree::configure(&mut command);
        let mut child = command
            .spawn()
            .map_err(|error| TransportError::Spawn(error.to_string()))?;
        let tree = match ProcessTree::attach(&child) {
            Ok(tree) => tree,
            Err(why) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(TransportError::Spawn(why));
            }
        };

        let (sender, frames) = mpsc::channel();
        let stdout = child.stdout.take().expect("stdout is piped");
        thread::spawn(move || read_frames(stdout, sender, limits.max_frame));
        let stderr = Arc::new(Mutex::new(Vec::new()));
        let kept = Arc::clone(&stderr);
        let pipe = child.stderr.take().expect("stderr is piped");
        thread::spawn(move || drain_stderr(pipe, kept, limits.stderr_capture));

        Ok(Self {
            stdin: child.stdin.take(),
            child,
            tree,
            frames,
            stderr,
            next_id: 1,
            broken: None,
            started: Instant::now(),
            limits,
        })
    }

    /// The first bytes the adapter wrote to stderr, lossily decoded.
    pub fn stderr(&self) -> String {
        let kept = self
            .stderr
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        String::from_utf8_lossy(&kept).into_owned()
    }

    /// The first failure, once the session is broken.
    pub fn broken(&self) -> Option<&TransportError> {
        self.broken.as_ref()
    }

    /// Sends `request` and returns the body of its answer, without the id.
    pub fn exchange(&mut self, request: &Request) -> Result<Map<String, Value>, TransportError> {
        if let Some(broken) = &self.broken {
            return Err(broken.clone());
        }
        let id = self.next_id;
        self.next_id += 1;
        let result = self.send(request, id).and_then(|()| self.receive(id));
        if let Err(error) = &result {
            self.broken = Some(error.clone());
        }
        result
    }

    fn send(&mut self, request: &Request, id: u64) -> Result<(), TransportError> {
        let Some(stdin) = self.stdin.as_mut() else {
            return Err(TransportError::StdinClosed("already closed".to_owned()));
        };
        let line = format!("{}\n", request.line(id));
        stdin
            .write_all(line.as_bytes())
            .and_then(|()| stdin.flush())
            .map_err(|error| TransportError::StdinClosed(error.to_string()))
    }

    /// The failure for a stdout that ended: the exit status, if it arrives
    /// within the grace period, and what the adapter said on stderr.
    fn closed(&mut self) -> TransportError {
        let deadline = Instant::now() + self.limits.exit_grace;
        let status = loop {
            match self.child.try_wait() {
                Ok(Some(status)) => break Some(status_text(status)),
                Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(10)),
                _ => break None,
            }
        };
        // Give the stderr thread a moment to catch the adapter's last words.
        thread::sleep(Duration::from_millis(20));
        TransportError::Closed {
            status,
            stderr: self.stderr(),
        }
    }

    fn receive(&mut self, id: u64) -> Result<Map<String, Value>, TransportError> {
        let now = Instant::now();
        let session_end = self.started + self.limits.session_timeout;
        let request_end = now + self.limits.request_timeout;
        let (deadline, session) = if session_end <= request_end {
            (session_end, true)
        } else {
            (request_end, false)
        };
        match self
            .frames
            .recv_timeout(deadline.saturating_duration_since(now))
        {
            Ok(Frame::Line(line)) => {
                let (got, body) =
                    parse_envelope(&line).map_err(|error| TransportError::Malformed(error.0))?;
                if got == id {
                    Ok(body)
                } else {
                    Err(TransportError::WrongId { expected: id, got })
                }
            }
            Ok(Frame::NotUtf8) => Err(TransportError::Malformed(
                "adapter sent a frame that is not UTF-8".to_owned(),
            )),
            Ok(Frame::TooLong) => Err(TransportError::FrameTooLong {
                limit: self.limits.max_frame,
            }),
            Ok(Frame::Failed(why)) => Err(TransportError::Malformed(format!(
                "cannot read adapter stdout: {why}"
            ))),
            Ok(Frame::Eof) | Err(RecvTimeoutError::Disconnected) => Err(self.closed()),
            Err(RecvTimeoutError::Timeout) if session => Err(TransportError::SessionTimeout {
                millis: self.limits.session_timeout.as_millis(),
            }),
            Err(RecvTimeoutError::Timeout) => Err(TransportError::Timeout {
                id,
                millis: self.limits.request_timeout.as_millis(),
            }),
        }
    }

    /// Ends the session. A healthy adapter gets the `exit` request and the
    /// grace period to stop; one that does not stop, or stops with a failure,
    /// is a shutdown failure. A broken session is terminated without another
    /// request, and only the original failure is reported. Either way the
    /// adapter's process tree is gone when this returns.
    pub fn close(mut self) -> Result<(), TransportError> {
        let healthy = self.broken.is_none();
        if healthy && matches!(self.child.try_wait(), Ok(None)) {
            let id = self.next_id;
            self.next_id += 1;
            let _ = self.send(&Request::Exit, id);
        }
        self.stdin = None;

        let deadline = Instant::now()
            + if healthy {
                self.limits.shutdown_grace
            } else {
                Duration::ZERO
            };
        let status = loop {
            match self.child.try_wait() {
                Ok(Some(status)) => break Some(status),
                Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(10)),
                _ => break None,
            }
        };
        // Whatever the adapter left running goes too, even after a clean exit.
        self.tree.kill(&mut self.child);
        let _ = self.child.wait();
        if !healthy {
            return Ok(());
        }
        match status {
            None => Err(TransportError::Shutdown(format!(
                "it did not exit within {} ms of the exit request and was terminated",
                self.limits.shutdown_grace.as_millis()
            ))),
            Some(status) if !status.success() => Err(TransportError::Shutdown(format!(
                "it exited with {}{}",
                status_text(status),
                with_stderr(&self.stderr())
            ))),
            Some(_) => Ok(()),
        }
    }
}

impl Drop for Session {
    fn drop(&mut self) {
        if matches!(self.child.try_wait(), Ok(None)) {
            self.tree.kill(&mut self.child);
            let _ = self.child.wait();
        }
    }
}

#[cfg(test)]
mod tests {
    use std::sync::mpsc;

    use super::*;

    fn frames_of(bytes: &[u8], max: usize) -> Vec<String> {
        let (sender, receiver) = mpsc::channel();
        read_frames(bytes, sender, max);
        receiver
            .into_iter()
            .map(|frame| match frame {
                Frame::Line(line) => format!("line:{line}"),
                Frame::NotUtf8 => "not-utf8".to_owned(),
                Frame::TooLong => "too-long".to_owned(),
                Frame::Failed(why) => format!("failed:{why}"),
                Frame::Eof => "eof".to_owned(),
            })
            .collect()
    }

    #[test]
    fn frames_split_on_newlines_and_drop_one_carriage_return() {
        assert_eq!(frames_of(b"a\r\nb\n", 10), vec!["line:a", "line:b", "eof"]);
        assert_eq!(
            frames_of(b"a\n\ntail", 10),
            vec!["line:a", "line:", "line:tail", "eof"]
        );
        assert_eq!(frames_of(b"", 10), vec!["eof"]);
    }

    #[test]
    fn a_frame_over_the_bound_stops_reading() {
        assert_eq!(
            frames_of(b"12345\n123456\nnever", 5),
            vec!["line:12345", "too-long"]
        );
        assert_eq!(frames_of(b"123456", 5), vec!["too-long"]);
    }

    #[test]
    fn a_frame_that_is_not_utf8_stops_reading() {
        assert_eq!(
            frames_of(b"ok\n\xff\xfe\nnever\n", 10),
            vec!["line:ok", "not-utf8"]
        );
    }

    #[test]
    fn stderr_keeps_only_its_first_bytes_and_drains_the_rest() {
        let kept = Arc::new(Mutex::new(Vec::new()));
        drain_stderr(&[b'x'; 100_000][..], Arc::clone(&kept), 16);
        assert_eq!(kept.lock().unwrap().len(), 16);
    }

    #[test]
    fn failures_read_as_the_contract_words_them() {
        assert_eq!(
            TransportError::Closed {
                status: Some("code 3".into()),
                stderr: "boom".into()
            }
            .to_string(),
            "adapter exited with code 3; stderr: boom"
        );
        assert_eq!(
            TransportError::Closed {
                status: None,
                stderr: String::new()
            }
            .to_string(),
            "adapter closed stdout"
        );
        assert_eq!(
            TransportError::WrongId {
                expected: 2,
                got: 3
            }
            .to_string(),
            "expected id 2, got 3"
        );
        assert_eq!(
            TransportError::Timeout {
                id: 4,
                millis: 30000
            }
            .to_string(),
            "adapter timed out after 30000 ms waiting for id 4"
        );
    }
}
