//! Actual Unix configured CLI and owned Session process tree. Endpoint closure
//! is observed; parent reaping of the adapter/descendant is NOT inferred.
#![cfg(unix)]
use rustix::process::{Pid, Signal, getpgid, getpgrp, kill_process, kill_process_group};
use serde::Deserialize;
use std::io::{BufRead, BufReader, Read};
use std::net::{TcpListener, TcpStream};
use std::path::Path;
use std::process::{Child, Command, ExitStatus, Stdio};
use std::time::{Duration, Instant};

const SOURCE: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls"
);
const BOUND: Duration = Duration::from_secs(10);

#[derive(Deserialize, Debug)]
#[serde(deny_unknown_fields)]
struct Witness {
    kind: String,
    nonce: String,
    pid: i32,
    ppid: i32,
    pgid: i32,
    descendant: Option<i32>,
}
struct CliTree {
    child: Child,
    group: Option<Pid>,
    observed_closed: bool,
}
impl Drop for CliTree {
    fn drop(&mut self) {
        // Only this actual spawned CLI and a validated adapter-owned group.
        // No fixture label or arbitrary supplied PID is cleanup authority.
        if let Some(group) = self.group
            && !self.observed_closed
            && getpgid(Some(group)).ok() == Some(group)
        {
            let _ = kill_process_group(group, Signal::KILL);
        }
        if matches!(self.child.try_wait(), Ok(None)) {
            // Also cover setup failure before both ownership witnesses arrived:
            // ask the genuine CLI owner to kill its own tree before last-resort
            // root cleanup. The positive test signal remains separately fixed.
            let _ = kill_process(Pid::from_child(&self.child), Signal::INT);
            let until = Instant::now() + Duration::from_secs(2);
            while matches!(self.child.try_wait(), Ok(None)) && Instant::now() < until {
                std::thread::sleep(Duration::from_millis(5));
            }
            if matches!(self.child.try_wait(), Ok(None)) {
                let _ = self.child.kill();
            }
        }
        let _ = self.child.wait();
    }
}
fn accept(listener: &TcpListener, until: Instant) -> (Witness, TcpStream) {
    loop {
        match listener.accept() {
            Ok((stream, address)) => {
                assert!(address.ip().is_loopback());
                // Accepted sockets can inherit nonblocking mode on Unix.
                stream.set_nonblocking(false).unwrap();
                stream
                    .set_read_timeout(Some(until.saturating_duration_since(Instant::now())))
                    .unwrap();
                let mut line = Vec::new();
                BufReader::new(stream.try_clone().unwrap().take(1025))
                    .read_until(b'\n', &mut line)
                    .unwrap();
                assert!(
                    line.len() <= 1024 && line.last() == Some(&b'\n'),
                    "bounded complete ownership witness required"
                );
                return (serde_json::from_slice(&line).unwrap(), stream);
            }
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                assert!(
                    Instant::now() < until,
                    "real adapter/descendant ownership handshake did not arrive"
                );
                std::thread::sleep(Duration::from_millis(5));
            }
            Err(error) => panic!("accept real process witness: {error}"),
        }
    }
}
fn exited(child: &mut Child, until: Instant) -> ExitStatus {
    loop {
        if let Some(status) = child.try_wait().unwrap() {
            return status;
        }
        assert!(
            Instant::now() < until,
            "actual CLI did not exit within bounded cancellation interval"
        );
        std::thread::sleep(Duration::from_millis(5));
    }
}
fn endpoint_closed(stream: &mut TcpStream, until: Instant) {
    assert!(Instant::now() < until);
    stream
        .set_read_timeout(Some(until.saturating_duration_since(Instant::now())))
        .unwrap();
    let mut byte = [0];
    match stream.read(&mut byte) {
        Ok(0) => {}
        Err(error) if error.kind() == std::io::ErrorKind::ConnectionReset => {}
        result => panic!(
            "actual process-owned endpoint remained open or emitted unexpected data: {result:?}"
        ),
    }
}

#[test]
fn configured_cli_sigint_closes_actual_adapter_and_descendant_without_report() {
    let temp = tempfile::tempdir().unwrap();
    let kit = temp.path().join("kit");
    std::fs::create_dir(&kit).unwrap();
    std::fs::copy(Path::new(SOURCE).join("cases.json"), kit.join("cases.json")).unwrap();
    let policy = temp.path().join("policy.json");
    std::fs::copy(Path::new(SOURCE).join("explicit-test-policy.json"), &policy).unwrap();
    let report = temp.path().join("report.json");
    let listener = TcpListener::bind((std::net::Ipv4Addr::LOCALHOST, 0)).unwrap();
    listener.set_nonblocking(true).unwrap();
    let address = listener.local_addr().unwrap().to_string();
    let nonce = format!("fixed-cli-interrupt-test-{}", std::process::id());
    let peer = std::env::var_os("MORPHIR_MCK_REPORT_PEER_BIN")
        .expect("actual existing compiled MEP harness");
    let child = Command::new(env!("CARGO_BIN_EXE_morphir"))
        .env("MORPHIR_LOG_FILE", "false")
        .env("MORPHIR_NO_BANNER", "true")
        .env_remove("MORPHIR_LOG_DIR")
        .env_remove("MORPHIR_OUT_DIR")
        .args(["mck", "workbench", "run", "--kit"])
        .arg(&kit)
        .arg("--checker-policy")
        .arg(&policy)
        .arg("--report")
        .arg(&report)
        .arg("--adapter")
        .arg(peer)
        .args([
            "--adapter-arg=--adapter",
            "--adapter-arg=workflow-pipeline-interrupt-tree",
        ])
        .arg(format!("--adapter-arg={address}"))
        .arg(format!("--adapter-arg={nonce}"))
        .args(["--timeout", "30000", "--session-timeout", "60000"])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let cli_pid = Pid::from_child(&child);
    let mut owned = CliTree {
        child,
        group: None,
        observed_closed: false,
    };
    let until = Instant::now() + BOUND;
    let (first, first_stream) = accept(&listener, until);
    let (second, second_stream) = accept(&listener, until);
    let (adapter, mut adapter_stream, descendant, mut descendant_stream) =
        if first.kind == "adapter" {
            (first, first_stream, second, second_stream)
        } else {
            (second, second_stream, first, first_stream)
        };
    assert_eq!(adapter.kind, "adapter");
    assert_eq!(descendant.kind, "descendant");
    assert_eq!(adapter.nonce, nonce);
    assert_eq!(descendant.nonce, nonce);
    let adapter_pid = Pid::from_raw(adapter.pid).unwrap();
    let descendant_pid = Pid::from_raw(descendant.pid).unwrap();
    assert_eq!(adapter.ppid, cli_pid.as_raw_pid());
    assert_eq!(adapter.descendant, Some(descendant.pid));
    assert_eq!(descendant.ppid, adapter.pid);
    assert_eq!(descendant.descendant, None);
    assert_eq!(adapter.pgid, adapter.pid);
    assert_eq!(descendant.pgid, adapter.pid);
    assert_ne!(adapter_pid, cli_pid);
    assert_ne!(descendant_pid, cli_pid);
    assert_ne!(adapter_pid, descendant_pid);
    assert_ne!(
        adapter_pid,
        getpgrp(),
        "the test process group must never be signalled"
    );
    assert_eq!(getpgid(Some(adapter_pid)).unwrap(), adapter_pid);
    assert_eq!(getpgid(Some(descendant_pid)).unwrap(), adapter_pid);
    owned.group = Some(adapter_pid);
    assert!(
        !report.exists(),
        "no workflow reply/report exists at the genuine pending boundary"
    );
    eprintln!(
        "actual pending tree cli={} adapter={} descendant={} group={}; signal ONLY CLI PID",
        cli_pid.as_raw_pid(),
        adapter.pid,
        descendant.pid,
        adapter.pgid
    );
    let signalled = Instant::now();
    kill_process(cli_pid, Signal::INT).unwrap();
    let until = signalled + BOUND;
    let status = exited(&mut owned.child, until);
    assert_eq!(status.code(), Some(130), "actual Ctrl-C exit status");
    endpoint_closed(&mut adapter_stream, until);
    endpoint_closed(&mut descendant_stream, until);
    owned.observed_closed = true;
    assert!(
        !report.exists(),
        "interrupted workflow must not publish a report"
    );
    let mut stderr = String::new();
    owned
        .child
        .stderr
        .take()
        .unwrap()
        .take(65536)
        .read_to_string(&mut stderr)
        .unwrap();
    assert!(stderr.contains("interrupted"), "{stderr}");
    eprintln!(
        "actual CLI status130 and both held process endpoints closed in {:?}; no parent-reap claim",
        signalled.elapsed()
    );
}
