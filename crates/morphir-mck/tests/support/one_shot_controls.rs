//! Source-first ordinary-process controls in the existing self-peer harness.
//! S07 awaits the real private async wrapper and is intentionally absent.
use super::*;
use morphir_mck::transport::process::{
    CommandSpec, DescendantEvidence, OneShotProcess, ProcessFault, ProcessFinish, ProcessOutcome,
    ProcessProgress,
};
use std::{
    io::{Read as _, Write as _},
    net::{TcpListener, TcpStream},
    process::{Command, Stdio},
};

const WAIT: Duration = Duration::from_secs(5);
const RAW: &[u8] = &[0, 255, 13, 10, 128];

pub(super) fn peer(mode: &str, arg: Option<&str>) -> bool {
    if !mode.starts_with("one-shot-") {
        return false;
    }
    let write = |bytes: &[u8]| {
        let mut out = std::io::stdout().lock();
        out.write_all(bytes).unwrap();
        out.flush().unwrap();
    };
    let connect = || {
        let mut stream = TcpStream::connect(arg.unwrap()).unwrap();
        writeln!(stream, "{mode} {}", std::process::id()).unwrap();
        stream.flush().unwrap();
        stream
    };
    match mode {
        "one-shot-env-parent" => {
            assert_eq!(std::env::var("ONE_SHOT_PARENT_POISON").unwrap(), "poison");
            argv_env_body();
            write(b"env-parent-done");
        }
        "one-shot-literal" => {
            let mut input = Vec::new();
            std::io::stdin().read_to_end(&mut input).unwrap();
            assert!(input.is_empty());
            std::io::stderr().write_all(b"ERR").unwrap();
            write(RAW);
        }
        "one-shot-argv-env" => {
            assert_eq!(
                std::env::args_os().skip(3).collect::<Vec<_>>(),
                [
                    OsString::from("$(not-a-shell);'quoted'"),
                    OsString::from("sp ace"),
                    OsString::from("é")
                ]
            );
            assert_eq!(
                std::env::var_os("ONE_SHOT_DECLARED"),
                Some(OsString::from("only"))
            );
            assert!(std::env::var_os("ONE_SHOT_PARENT_POISON").is_none());
            assert_eq!(
                std::env::current_dir().unwrap(),
                PathBuf::from(std::env::var_os("ONE_SHOT_CWD").unwrap())
            );
            write(b"literal-argv");
        }
        "one-shot-output-exact" => write(RAW),
        "one-shot-output-over" => write(&[0, 255, 13, 10, 128, 42]),
        "one-shot-chatty-stderr" => {
            std::io::stderr().write_all(b"ERR").unwrap();
            for _ in 0..256 {
                std::io::stderr().write_all(&[b'x'; 4096]).unwrap();
            }
            write(b"OK");
        }
        "one-shot-exit7" => {
            std::io::stderr().write_all(b"seven").unwrap();
            std::process::exit(7);
        }
        "one-shot-held" => {
            let mut stream = connect();
            let mut byte = [0];
            stream.read_exact(&mut byte).unwrap();
            assert_eq!(byte, [1]);
            write(b"released");
        }
        "one-shot-parent-with-descendant" | "one-shot-root-exits-child-holds-pipe" => {
            let _stream = connect();
            let mut command = Command::new(std::env::current_exe().unwrap());
            command
                .args([ADAPTER_FLAG, "one-shot-descendant", arg.unwrap()])
                .stdin(Stdio::null())
                .stdout(Stdio::inherit())
                .stderr(Stdio::null());
            let mut child = command.spawn().unwrap();
            if mode == "one-shot-parent-with-descendant" {
                let _ = child.wait();
            }
            // Deliberately leave this genuine descendant owning stdout. Dropping
            // std::process::Child does not kill it or prove that it exited.
        }
        "one-shot-descendant" => {
            let mut stream = connect();
            let mut byte = [0];
            let _ = stream.read_exact(&mut byte);
        }
        "one-shot-overflow-then-held" => {
            let mut stream = connect();
            write(&[0, 255, 13, 10, 128, 42]);
            let mut byte = [0];
            let _ = stream.read_exact(&mut byte);
        }
        "one-shot-root-finishes-descendant-held" => {
            let _stream = connect();
            let _child = Command::new(std::env::current_exe().unwrap())
                .args([
                    ADAPTER_FLAG,
                    "one-shot-descendant-release-witness",
                    arg.unwrap(),
                ])
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()
                .unwrap();
        }
        "one-shot-descendant-release-witness" => {
            let mut stream = connect();
            let mut release = [0];
            if stream.read_exact(&mut release).is_ok() {
                assert_eq!(release, [1]);
                stream.write_all(b"R").unwrap();
            }
        }
        "one-shot-exit7-control" => {
            let _root = connect();
            std::io::stderr().write_all(b"seven").unwrap();
            std::process::exit(7);
        }
        _ => panic!("unrecognized one-shot mode"),
    }
    true
}

fn command(mode: &str, arg: Option<&str>, directory: &Path) -> CommandSpec {
    let mut argv = vec![OsString::from(ADAPTER_FLAG), OsString::from(mode)];
    argv.extend(arg.map(OsString::from));
    CommandSpec::new(
        std::env::current_exe().unwrap(),
        argv,
        directory.to_path_buf(),
        environment(),
    )
    .unwrap()
}
fn environment() -> Vec<(OsString, OsString)> {
    // Windows needs its actual OS loader roots. No other parent environment
    // enters these one-shot fixtures, including preload/helper variables.
    ["SystemRoot", "WINDIR"]
        .into_iter()
        .filter_map(|key| std::env::var_os(key).map(|value| (OsString::from(key), value)))
        .collect()
}
fn limits(stdout: usize, stderr: usize) -> Limits {
    Limits {
        max_frame: stdout,
        stderr_capture: stderr,
        ..quick()
    }
}
fn complete(process: &mut OneShotProcess) {
    let end = Instant::now() + WAIT;
    loop {
        if matches!(process.advance(), ProcessProgress::Finished(_)) {
            return;
        }
        if process.observed_exit().is_some() && process.status().is_none() {
            // Raw completion explicitly chooses reap without helper termination.
            // The returned std status still comes only from the actual wait.
            process.reap_retained().unwrap();
        }
        assert!(
            Instant::now() < end,
            "actual child/readers did not complete"
        );
        std::thread::sleep(Duration::from_millis(2));
    }
}
fn outcome(process: OneShotProcess) -> ProcessOutcome {
    match process.into_finished() {
        ProcessFinish::Finished(outcome) => outcome,
        ProcessFinish::Pending(_) => panic!("owner was not actually Finished"),
    }
}
struct Gate {
    listener: TcpListener,
}
impl Gate {
    fn new() -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        listener.set_nonblocking(true).unwrap();
        Self { listener }
    }
    fn address(&self) -> String {
        self.listener.local_addr().unwrap().to_string()
    }
    fn entered(&self) -> (TcpStream, u32) {
        let end = Instant::now() + WAIT;
        let stream = loop {
            match self.listener.accept() {
                Ok((stream, _)) => break stream,
                Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                    assert!(Instant::now() < end, "actual peer never entered");
                    std::thread::sleep(Duration::from_millis(2));
                }
                Err(error) => panic!("actual control accept: {error}"),
            }
        };
        stream.set_nonblocking(false).unwrap();
        stream.set_read_timeout(Some(WAIT)).unwrap();
        let mut reader = std::io::BufReader::new(stream.try_clone().unwrap());
        let mut witness = String::new();
        reader.read_line(&mut witness).unwrap();
        let pid = witness.split_whitespace().nth(1).unwrap().parse().unwrap();
        (stream, pid)
    }
}
fn endpoint_closed(mut stream: TcpStream) {
    let mut byte = [0];
    match stream.read(&mut byte) {
        Ok(0) => {}
        Err(error)
            if matches!(
                error.kind(),
                std::io::ErrorKind::ConnectionReset | std::io::ErrorKind::ConnectionAborted
            ) => {}
        other => panic!("actual held endpoint did not close: {other:?}"),
    }
}

pub(super) fn one_shot_s01_literal_raw_output_has_no_adapter_protocol() {
    let directory = tempfile::tempdir().unwrap();
    let mut process = OneShotProcess::spawn(
        command("one-shot-literal", None, directory.path()),
        limits(5, 3),
    )
    .unwrap();
    complete(&mut process);
    let actual = outcome(process);
    assert_eq!(actual.status().code(), Some(0));
    assert_eq!(actual.stdout(), RAW);
    assert_eq!(actual.stderr(), b"ERR");
    assert!(!actual.stderr_truncated());
    assert!(actual.first_fault().is_none());
    assert_eq!(actual.descendants(), DescendantEvidence::Unobserved);
}
fn argv_env_body() {
    let temporary = tempfile::tempdir().unwrap();
    let directory = temporary.path().join("private cwd space");
    std::fs::create_dir(&directory).unwrap();
    let directory = directory.canonicalize().unwrap();
    let argv = vec![
        ADAPTER_FLAG.into(),
        "one-shot-argv-env".into(),
        "$(not-a-shell);'quoted'".into(),
        "sp ace".into(),
        "é".into(),
    ];
    let mut env = environment();
    env.push(("ONE_SHOT_DECLARED".into(), "only".into()));
    env.push(("ONE_SHOT_CWD".into(), directory.as_os_str().to_owned()));
    let spec = CommandSpec::new(
        std::env::current_exe().unwrap(),
        argv,
        directory.clone(),
        env,
    )
    .unwrap();
    let mut process = OneShotProcess::spawn(spec, limits(12, 128)).unwrap();
    complete(&mut process);
    let actual = outcome(process);
    assert_eq!(actual.status().code(), Some(0));
    assert_eq!(actual.stdout(), b"literal-argv");
    assert!(actual.first_fault().is_none());
    assert!(
        CommandSpec::new(PathBuf::from("relative"), vec![], directory.clone(), vec![]).is_err()
    );
    assert!(
        CommandSpec::new(
            std::env::current_exe().unwrap(),
            vec![],
            PathBuf::from("relative"),
            vec![]
        )
        .is_err()
    );
    assert!(
        CommandSpec::new(
            std::env::current_exe().unwrap(),
            vec![],
            directory,
            vec![("DUP".into(), "a".into()), ("DUP".into(), "b".into())]
        )
        .is_err()
    );
}
pub(super) fn one_shot_s02_literal_argv_private_environment_and_absolute_paths() {
    // Poison belongs only to a genuine fixture parent process, never to the
    // running test harness's global environment. Its real child uses the SUT.
    let mut child = Command::new(std::env::current_exe().unwrap())
        .args([ADAPTER_FLAG, "one-shot-env-parent"])
        .env("ONE_SHOT_PARENT_POISON", "poison")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .unwrap();
    let end = Instant::now() + WAIT;
    let status = loop {
        if let Some(status) = child.try_wait().unwrap() {
            break status;
        }
        if Instant::now() >= end {
            let _ = child.kill();
            let _ = child.wait();
            panic!("actual fixture parent timed out");
        }
        std::thread::sleep(Duration::from_millis(2));
    };
    assert!(status.success());
    let mut marker = Vec::new();
    child
        .stdout
        .take()
        .unwrap()
        .read_to_end(&mut marker)
        .unwrap();
    assert_eq!(marker, b"env-parent-done");
}
pub(super) fn one_shot_s03_exact_stdout_and_first_excess_retained_byte() {
    let directory = tempfile::tempdir().unwrap();
    let mut exact = OneShotProcess::spawn(
        command("one-shot-output-exact", None, directory.path()),
        limits(5, 128),
    )
    .unwrap();
    complete(&mut exact);
    let exact = outcome(exact);
    assert_eq!(exact.stdout(), RAW);
    assert!(exact.first_fault().is_none());
    let mut over = OneShotProcess::spawn(
        command("one-shot-output-over", None, directory.path()),
        limits(5, 128),
    )
    .unwrap();
    complete(&mut over);
    let over = outcome(over);
    assert_eq!(over.stdout(), RAW);
    assert!(matches!(
        over.first_fault(),
        Some(ProcessFault::StdoutLimit)
    ));
}
pub(super) fn one_shot_s04_stderr_prefix_and_zero_still_drain() {
    let directory = tempfile::tempdir().unwrap();
    for bound in [3, 0] {
        let mut process = OneShotProcess::spawn(
            command("one-shot-chatty-stderr", None, directory.path()),
            limits(2, bound),
        )
        .unwrap();
        complete(&mut process);
        let actual = outcome(process);
        assert_eq!(actual.status().code(), Some(0));
        assert_eq!(actual.stdout(), b"OK");
        assert_eq!(actual.stderr(), &b"ERR"[..bound]);
        assert!(actual.stderr_truncated());
        assert!(actual.first_fault().is_none());
    }
}
pub(super) fn one_shot_s05_actual_nonzero_status_is_not_cleanup_failure() {
    let directory = tempfile::tempdir().unwrap();
    let mut process = OneShotProcess::spawn(
        command("one-shot-exit7", None, directory.path()),
        limits(5, 5),
    )
    .unwrap();
    complete(&mut process);
    let actual = outcome(process);
    assert_eq!(actual.status().code(), Some(7));
    assert_eq!(actual.stderr(), b"seven");
    assert!(actual.first_fault().is_none());
}
pub(super) fn one_shot_s06_pending_owner_survives_deadline_and_same_owner_retry() {
    let directory = tempfile::tempdir().unwrap();
    let gate = Gate::new();
    let mut process = OneShotProcess::spawn(
        command("one-shot-held", Some(&gate.address()), directory.path()),
        limits(8, 128),
    )
    .unwrap();
    let (mut stream, pid) = gate.entered();
    assert_eq!(process.id(), pid);
    let end = Instant::now() + Duration::from_millis(30);
    while Instant::now() < end {
        assert!(!matches!(process.advance(), ProcessProgress::Finished(_)));
        std::thread::sleep(Duration::from_millis(2));
    }
    let mut process = match process.into_finished() {
        ProcessFinish::Pending(same) => same,
        ProcessFinish::Finished(_) => panic!("held child falsely Finished"),
    };
    assert_eq!(process.id(), pid);
    stream.write_all(&[1]).unwrap();
    complete(&mut process);
    let actual = outcome(process);
    assert_eq!(actual.status().code(), Some(0));
    assert_eq!(actual.stdout(), b"released");
    assert!(actual.first_fault().is_none());
}
pub(super) fn one_shot_s08_same_tree_termination_and_actual_direct_child_join() {
    let directory = tempfile::tempdir().unwrap();
    let gate = Gate::new();
    let mut process = OneShotProcess::spawn(
        command(
            "one-shot-parent-with-descendant",
            Some(&gate.address()),
            directory.path(),
        ),
        limits(32, 128),
    )
    .unwrap();
    let (parent, pid) = gate.entered();
    let (descendant, other) = gate.entered();
    assert_eq!(process.id(), pid);
    assert_ne!(pid, other);
    process.request_termination().unwrap();
    complete(&mut process);
    let actual = outcome(process);
    assert!(!actual.status().success());
    assert_eq!(
        actual.descendants(),
        DescendantEvidence::TerminationRequestedUnverified
    );
    endpoint_closed(parent);
    endpoint_closed(descendant);
}
pub(super) fn one_shot_s09_root_exit_does_not_join_inherited_pipe_reader() {
    let directory = tempfile::tempdir().unwrap();
    let gate = Gate::new();
    let mut process = OneShotProcess::spawn(
        command(
            "one-shot-root-exits-child-holds-pipe",
            Some(&gate.address()),
            directory.path(),
        ),
        limits(32, 128),
    )
    .unwrap();
    let (parent, _) = gate.entered();
    let (descendant, _) = gate.entered();
    endpoint_closed(parent);
    let end = Instant::now() + WAIT;
    loop {
        assert!(!matches!(process.advance(), ProcessProgress::Finished(_)));
        if process.observed_exit().is_some() {
            break;
        }
        assert!(Instant::now() < end, "real root exit not observed");
        std::thread::sleep(Duration::from_millis(2));
    }
    assert_eq!(process.observed_exit().unwrap().code(), Some(0));
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    assert!(
        process.status().is_none(),
        "exit observation is not an actual std reap"
    );
    process.request_termination().unwrap();
    complete(&mut process);
    let actual = outcome(process);
    assert_eq!(actual.status().code(), Some(0));
    assert_eq!(
        actual.descendants(),
        DescendantEvidence::TerminationRequestedUnverified
    );
    endpoint_closed(descendant);
}
pub(super) fn one_shot_s10_fault_progresses_cleanup_and_drop_does_not_claim_join() {
    let directory = tempfile::tempdir().unwrap();
    let gate = Gate::new();
    let mut process = OneShotProcess::spawn(
        command(
            "one-shot-overflow-then-held",
            Some(&gate.address()),
            directory.path(),
        ),
        limits(5, 128),
    )
    .unwrap();
    let (held, _) = gate.entered();
    let end = Instant::now() + WAIT;
    loop {
        match process.advance() {
            ProcessProgress::Faulted(ProcessFault::StdoutLimit) => break,
            ProcessProgress::Finished(_) => panic!("held overflow child falsely Finished"),
            _ => {
                assert!(Instant::now() < end);
                std::thread::sleep(Duration::from_millis(2));
            }
        }
    }
    process.request_termination().unwrap();
    complete(&mut process);
    let actual = outcome(process);
    assert_eq!(actual.stdout(), RAW);
    assert!(matches!(
        actual.first_fault(),
        Some(ProcessFault::StdoutLimit)
    ));
    assert_eq!(
        actual.descendants(),
        DescendantEvidence::TerminationRequestedUnverified
    );
    endpoint_closed(held);
    let gate = Gate::new();
    let process = OneShotProcess::spawn(
        command("one-shot-held", Some(&gate.address()), directory.path()),
        limits(8, 128),
    )
    .unwrap();
    let (held, pid) = gate.entered();
    drop(process);
    endpoint_closed(held);
    #[cfg(unix)]
    {
        // Test teardown owns this independent direct-child reap only. It is
        // not a production Drop/join certificate and never signals the PID.
        let actual = rustix::process::Pid::from_raw(i32::try_from(pid).unwrap()).unwrap();
        let end = Instant::now() + WAIT;
        loop {
            match rustix::process::waitpid(Some(actual), rustix::process::WaitOptions::NOHANG) {
                Ok(Some(_)) => break,
                Ok(None) => {
                    assert!(
                        Instant::now() < end,
                        "independent fixture direct-child reap timed out"
                    );
                    std::thread::sleep(Duration::from_millis(2));
                }
                Err(error) => panic!("independent fixture direct-child reap: {error}"),
            }
        }
    }
    #[cfg(not(unix))]
    let _ = pid;
    // Endpoint closure measures containment only. Drop returns no Finished
    // outcome, direct-child wait receipt, or pipe-reader joined proof.
}

struct HeldDescendant {
    stream: TcpStream,
}
impl Drop for HeldDescendant {
    fn drop(&mut self) {
        // Fixture-only RAII release also runs if any assertion panics. No PID
        // signaling, background reaper, or production join proof is inferred.
        let _ = self.stream.write_all(&[1]);
    }
}
pub(super) fn one_shot_s11_consuming_raw_finished_does_not_terminate_held_descendant() {
    let directory = tempfile::tempdir().unwrap();
    let gate = Gate::new();
    let mut process = OneShotProcess::spawn(
        command(
            "one-shot-root-finishes-descendant-held",
            Some(&gate.address()),
            directory.path(),
        ),
        limits(32, 128),
    )
    .unwrap();
    let (parent, pid) = gate.entered();
    let (descendant, other) = gate.entered();
    assert_eq!(process.id(), pid);
    assert_ne!(pid, other);
    let mut held = HeldDescendant { stream: descendant };
    endpoint_closed(parent);
    complete(&mut process);
    let actual = outcome(process);
    assert_eq!(actual.status().code(), Some(0));
    assert_eq!(actual.descendants(), DescendantEvidence::Unobserved);
    held.stream
        .set_read_timeout(Some(Duration::from_millis(30)))
        .unwrap();
    let mut byte = [0];
    let waiting = held.stream.read(&mut byte);
    assert!(
        matches!(waiting, Err(ref error) if matches!(error.kind(), std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut)),
        "raw Finished consumption must leave the real held descendant alive: {waiting:?}"
    );
    held.stream.set_read_timeout(Some(WAIT)).unwrap();
    held.stream.write_all(&[1]).unwrap();
    held.stream.read_exact(&mut byte).unwrap();
    assert_eq!(byte, *b"R");
    assert_eq!(held.stream.read(&mut byte).unwrap(), 0);
    // Keep the genuine finished outcome alive across the explicit descendant
    // release. The measured endpoint proves only this actual fixture process.
    assert!(actual.first_fault().is_none());
}

// Source-first additions to the existing self-peer controls. Unix safety only.
// Baseline runs on the OLD API: independent WNOWAIT sees actual exit before
// advance(), then must still see it afterward. No new method is needed for RED.
#[cfg(any(target_os = "linux", target_os = "macos"))]
struct IndependentFixtureReap(Option<rustix::process::Pid>);
#[cfg(any(target_os = "linux", target_os = "macos"))]
impl Drop for IndependentFixtureReap {
    fn drop(&mut self) {
        use rustix::process::{WaitOptions, waitpid};
        let Some(pid) = self.0 else { return };
        let end = Instant::now() + WAIT;
        loop {
            match waitpid(Some(pid), WaitOptions::NOHANG) {
                Ok(Some(_)) | Err(rustix::io::Errno::CHILD) => return,
                Ok(None) | Err(rustix::io::Errno::INTR) if Instant::now() < end => {
                    std::thread::sleep(Duration::from_millis(2));
                }
                result => {
                    eprintln!("fixture direct-child reap incomplete: {result:?}");
                    return;
                }
            }
        }
    }
}
#[cfg(any(target_os = "linux", target_os = "macos"))]
fn assert_genuine_descendant_held(held: &mut HeldDescendant) {
    held.stream
        .set_read_timeout(Some(Duration::from_millis(30)))
        .unwrap();
    let mut byte = [0];
    let actual = held.stream.read(&mut byte);
    assert!(
        matches!(actual, Err(ref e) if matches!(e.kind(),std::io::ErrorKind::WouldBlock|std::io::ErrorKind::TimedOut)),
        "retired/unproven numeric authority must not kill the actual held descendant: {actual:?}"
    );
    held.stream.set_read_timeout(Some(WAIT)).unwrap();
}
#[cfg(any(target_os = "linux", target_os = "macos"))]
fn release_genuine_descendant(held: &mut HeldDescendant) {
    held.stream.write_all(&[1]).unwrap();
    let mut byte = [0];
    held.stream.read_exact(&mut byte).unwrap();
    assert_eq!(byte, *b"R");
    assert_eq!(held.stream.read(&mut byte).unwrap(), 0);
}
#[cfg(any(target_os = "linux", target_os = "macos"))]
pub(super) fn one_shot_u01_observing_exit_keeps_child_waitable_before_explicit_reap() {
    use rustix::process::{Pid, WaitId, WaitIdOptions, waitid};
    let directory = tempfile::tempdir().unwrap();
    let gate = Gate::new();
    // Declared before the owner: on assertion panic, production Drop runs first.
    // This independent fixture reap grants no production cleanup/join credit.
    let mut fixture_reap = IndependentFixtureReap(None);
    let mut process = OneShotProcess::spawn(
        command(
            "one-shot-exit7-control",
            Some(&gate.address()),
            directory.path(),
        ),
        limits(5, 5),
    )
    .unwrap();
    let pid = Pid::from_raw(i32::try_from(process.id()).unwrap()).unwrap();
    fixture_reap.0 = Some(pid);
    let (root, actual_pid) = gate.entered();
    assert_eq!(process.id(), actual_pid);
    endpoint_closed(root);
    let options = WaitIdOptions::EXITED | WaitIdOptions::NOHANG | WaitIdOptions::NOWAIT;
    let end = Instant::now() + WAIT;
    loop {
        match waitid(WaitId::Pid(pid), options).unwrap() {
            Some(state) => {
                assert_eq!(state.exit_status(), Some(7));
                break;
            }
            None => {
                assert!(Instant::now() < end);
                std::thread::sleep(Duration::from_millis(2));
            }
        }
    }
    let _ = process.advance();
    for _ in 0..2 {
        let observed = waitid(WaitId::Pid(pid), options);
        assert!(
            matches!(observed,Ok(Some(ref state)) if state.exit_status()==Some(7)),
            "exit observation must keep SAME actual child waitable: {observed:?}"
        );
    }
    complete(&mut process);
    let actual = outcome(process);
    assert_eq!(actual.status().code(), Some(7));
    assert_eq!(actual.stderr(), b"seven");
}
#[cfg(any(target_os = "linux", target_os = "macos"))]
enum FinalFixtureAction {
    RequestThenDrop,
    DropOnly,
}
#[cfg(any(target_os = "linux", target_os = "macos"))]
pub(super) fn one_shot_u02_after_raw_reap_first_delayed_request_and_drop_cannot_signal() {
    for action in [
        FinalFixtureAction::RequestThenDrop,
        FinalFixtureAction::DropOnly,
    ] {
        let directory = tempfile::tempdir().unwrap();
        let gate = Gate::new();
        let mut process = OneShotProcess::spawn(
            command(
                "one-shot-root-finishes-descendant-held",
                Some(&gate.address()),
                directory.path(),
            ),
            limits(32, 128),
        )
        .unwrap();
        let (parent, pid) = gate.entered();
        let (descendant, other) = gate.entered();
        assert_eq!(process.id(), pid);
        assert_ne!(pid, other);
        let mut held = HeldDescendant { stream: descendant };
        endpoint_closed(parent);
        complete(&mut process);
        assert_eq!(process.status().unwrap().code(), Some(0));
        if matches!(action, FinalFixtureAction::RequestThenDrop) {
            let _ = process.request_termination();
            assert_genuine_descendant_held(&mut held);
        }
        drop(process);
        assert_genuine_descendant_held(&mut held);
        release_genuine_descendant(&mut held);
    }
}
#[cfg(any(target_os = "linux", target_os = "macos"))]
pub(super) fn one_shot_u03_foreign_reap_identity_uncertainty_refuses_numeric_signal() {
    for action in [
        FinalFixtureAction::RequestThenDrop,
        FinalFixtureAction::DropOnly,
    ] {
        use rustix::process::{Pid, WaitOptions, waitpid};
        let directory = tempfile::tempdir().unwrap();
        let gate = Gate::new();
        let mut process = OneShotProcess::spawn(
            command(
                "one-shot-root-finishes-descendant-held",
                Some(&gate.address()),
                directory.path(),
            ),
            limits(32, 128),
        )
        .unwrap();
        let (parent, pid) = gate.entered();
        let (descendant, other) = gate.entered();
        assert_eq!(process.id(), pid);
        assert_ne!(pid, other);
        let mut held = HeldDescendant { stream: descendant };
        endpoint_closed(parent);
        let actual_pid = Pid::from_raw(i32::try_from(pid).unwrap()).unwrap();
        let end = Instant::now() + WAIT;
        loop {
            match waitpid(Some(actual_pid), WaitOptions::NOHANG).unwrap() {
                Some((got, status)) => {
                    assert_eq!(got, actual_pid);
                    assert_eq!(status.exit_status(), Some(0));
                    break;
                }
                None => {
                    assert!(Instant::now() < end);
                    std::thread::sleep(Duration::from_millis(2));
                }
            }
        }
        // This independent test wait deliberately violates exclusive reap ownership.
        // The process owner must detect that uncertainty, not target its numeric PGID.
        if matches!(action, FinalFixtureAction::RequestThenDrop) {
            let _ = process.request_termination();
            assert_genuine_descendant_held(&mut held);
        }
        drop(process);
        assert_genuine_descendant_held(&mut held);
        release_genuine_descendant(&mut held);
    }
}
