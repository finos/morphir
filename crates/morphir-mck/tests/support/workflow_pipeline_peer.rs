//! Existing MEP harness child. Exact Workbench payloads, not JSONRPC conformance.
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
    #[cfg(target_os = "macos")]
    if mode == "installed-consumer-port-foundation" {
        use std::os::fd::FromRawFd as _;
        use std::os::unix::net::UnixStream;
        use std::time::{Duration, Instant};
        let outer: i32 = std::env::var("MORPHIR_PRIVATE_CONSUMER_OUTER_FD")
            .unwrap()
            .parse()
            .unwrap();
        let helper: i32 = std::env::var("MORPHIR_PRIVATE_CONSUMER_HELPER_FD")
            .unwrap()
            .parse()
            .unwrap();
        assert!(outer >= 3 && helper >= 3);
        assert_ne!(outer, helper);
        fn role(descriptor: i32, sent: u8, expected: u8) {
            unsafe extern "C" {
                fn fcntl(fd: i32, operation: i32, ...) -> i32;
            }
            let flags = unsafe { fcntl(descriptor, 1) };
            let status = unsafe { fcntl(descriptor, 3) };
            assert!(
                flags >= 0 && flags & 1 == 0,
                "only exact child endpoint must cross exec without CLOEXEC"
            );
            assert!(
                status >= 0 && status & 4 != 0,
                "actual inherited endpoint must remain nonblocking"
            );
            // SAFETY: the opt-in test process owns this explicitly transferred
            // descriptor. Its selector names it; the selector creates nothing.
            let mut socket = unsafe { UnixStream::from_raw_fd(descriptor) };
            socket.set_nonblocking(true).unwrap();
            let end = Instant::now() + Duration::from_secs(10);
            loop {
                match socket.write(&[sent]) {
                    Ok(1) => break,
                    Err(error)
                        if matches!(
                            error.kind(),
                            std::io::ErrorKind::WouldBlock | std::io::ErrorKind::Interrupted
                        ) => {}
                    result => panic!("actual role write: {result:?}"),
                }
                assert!(Instant::now() < end);
                std::thread::sleep(Duration::from_millis(1));
            }
            let mut byte = [0u8; 1];
            loop {
                match socket.read(&mut byte) {
                    Ok(1) => break,
                    Err(error)
                        if matches!(
                            error.kind(),
                            std::io::ErrorKind::WouldBlock | std::io::ErrorKind::Interrupted
                        ) => {}
                    result => panic!("actual role read: {result:?}"),
                }
                assert!(Instant::now() < end);
                std::thread::sleep(Duration::from_millis(1));
            }
            assert_eq!(byte, [expected]);
        }
        role(outer, b'O', b'o');
        role(helper, b'H', b'h');
        std::fs::write(std::env::args_os().nth(3).unwrap(), b"both-owned\n").unwrap();
        println!("consumer-port-entry-v1");
        return true;
    }
    // Test-only ordinary process entry, no MEP request/expected DATA.
    if mode == "installed-process-effect-marker" {
        let marker = std::path::PathBuf::from(std::env::args_os().nth(3).unwrap());
        assert!(marker.is_absolute());
        let mut file = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(marker)
            .unwrap();
        file.write_all(b"installed-process-effect-entry-v1\n")
            .unwrap();
        file.flush().unwrap();
        std::io::stdout().write_all(b"entered\n").unwrap();
        std::io::stdout().flush().unwrap();
        return true;
    }
    #[cfg(unix)]
    if interrupt_tree_adapter(mode) {
        return true;
    }
    if mode != "workflow-pipeline-blocked23" {
        return false;
    }
    let mut input = std::io::stdin().lock();
    assert_eq!(
        receive(&mut input).unwrap(),
        include_bytes!("workflow_pipeline_controls/capabilities-request.payload.json")
    );
    say_frame(include_str!(
        "workflow_pipeline_controls/capabilities-reply.payload.json"
    ));
    assert_eq!(
        receive(&mut input).unwrap(),
        include_bytes!("workflow_pipeline_controls/first-request.payload.json")
    );
    say_frame(include_str!(
        "workflow_pipeline_controls/first-reply.payload.json"
    ));
    // Deterministic actual peer evidence of no second request. This does not
    // separately measure Serialize invocation; source ordering + existing
    // actual Session failed-latch/Serialize-once controls cover that boundary.
    assert_eq!(
        receive(&mut input).unwrap(),
        br#"{"jsonrpc":"2.0","method":"morphir.exit","params":{}}"#
    );
    true
}

// Test-only Unix process ownership witness. The original blocked23 peer mode
// stays byte-identical. Neither helper interprets expected predicates.
#[cfg(unix)]
fn interrupt_tree_adapter(mode: &str) -> bool {
    use rustix::process::{getpgrp, getpid, getppid};
    use std::net::TcpStream;
    use std::process::{Command, Stdio};
    if !matches!(
        mode,
        "workflow-pipeline-interrupt-tree" | "workflow-pipeline-interrupt-descendant"
    ) {
        return false;
    }
    let address = std::env::args()
        .nth(3)
        .expect("owned local control listener");
    let nonce = std::env::args().nth(4).expect("source nonce");
    let descendant = if mode == "workflow-pipeline-interrupt-tree" {
        let mut input = std::io::stdin().lock();
        assert_eq!(
            receive(&mut input).unwrap(),
            include_bytes!("workflow_pipeline_controls/capabilities-request.payload.json")
        );
        say_frame(include_str!(
            "workflow_pipeline_controls/capabilities-reply.payload.json"
        ));
        assert_eq!(
            receive(&mut input).unwrap(),
            include_bytes!("workflow_pipeline_controls/first-request.payload.json")
        );
        let mut child = Command::new(std::env::current_exe().unwrap())
            .args([
                "--adapter",
                "workflow-pipeline-interrupt-descendant",
                &address,
                &nonce,
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .unwrap();
        let id = i32::try_from(child.id()).unwrap();
        std::thread::spawn(move || {
            let _ = child.wait();
        });
        Some(id)
    } else {
        None
    };
    let mut connection = TcpStream::connect(address).unwrap();
    let witness = serde_json::json!({"kind": if descendant.is_some() {"adapter"} else {"descendant"},"nonce":nonce,"pid":getpid().as_raw_pid(),"ppid":getppid().unwrap().as_raw_pid(),"pgid":getpgrp().as_raw_pid(),"descendant":descendant});
    writeln!(connection, "{witness}").unwrap();
    connection.flush().unwrap();
    // The test keeps its endpoint open. No voluntary helper close/return occurs
    // before the CLI cancellation; an unexpected byte/EOF is setup failure.
    connection
        .set_read_timeout(Some(Duration::from_secs(60)))
        .unwrap();
    let mut byte = [0];
    let result = connection.read(&mut byte);
    panic!("held process witness ended without tree termination: {result:?}");
}
