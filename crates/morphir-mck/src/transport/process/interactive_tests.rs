//! Physical stdio controls only. No browser, source, budget or product claim.
use super::{
    interactive::{
        FixedCaptureBuffers, InputRelease, InputStateView, InteractiveFault, InteractiveFinish,
        InteractiveProcess, InteractiveProgress, InteractiveSpawnError, InteractiveWrite,
    },
    *,
};
use std::{
    future::{Future, poll_fn},
    pin::pin,
    task::{Context, Poll, Waker},
    time::{Duration, Instant},
};

const WAIT: Duration = Duration::from_secs(5);
fn limits(stdout: usize, stderr: usize) -> Limits {
    Limits {
        max_frame: stdout,
        stderr_capture: stderr,
        ..Limits::DEFAULT
    }
}
fn command(program: &str, args: &[&str], directory: &std::path::Path) -> CommandSpec {
    CommandSpec::new(
        program.into(),
        args.iter().map(OsString::from).collect(),
        directory.into(),
        vec![],
    )
    .unwrap()
}
fn buffers(stdout: usize, stderr: usize) -> FixedCaptureBuffers {
    FixedCaptureBuffers::new(Vec::with_capacity(stdout), Vec::with_capacity(stderr))
}
fn settle_fixed_oneshot(mut process: OneShotProcess) -> ProcessOutcome {
    let end = Instant::now() + WAIT;
    loop {
        match process.advance() {
            ProcessProgress::ExitObserved(_) | ProcessProgress::Faulted(_) => {
                let _ = process.reap_retained();
            }
            ProcessProgress::Finished(_) => break,
            ProcessProgress::Working => {}
        }
        if Instant::now() >= end {
            let _ = process.request_termination();
        }
        assert!(
            Instant::now() < end + WAIT,
            "actual fixed process/readers remain owned"
        );
        std::thread::sleep(Duration::from_millis(1));
    }
    match process.into_finished() {
        ProcessFinish::Finished(outcome) => outcome,
        ProcessFinish::Pending(_) => panic!("actual fixed process/readers must join"),
    }
}

#[test]
fn fixed_oneshot_capture_01_consumes_actual_backing_and_joins_real_readers() {
    let directory = tempfile::tempdir().unwrap();
    let stdout = Vec::with_capacity(8);
    let stderr = Vec::with_capacity(4);
    let stdout_backing = stdout.as_ptr();
    let stderr_backing = stderr.as_ptr();
    let process = OneShotProcess::spawn_fixed_capture(
        command(
            "/bin/sh",
            &["-c", "printf fixed; printf err >&2"],
            directory.path(),
        ),
        limits(8, 4),
        FixedCaptureBuffers::new(stdout, stderr),
    )
    .unwrap();
    let outcome = settle_fixed_oneshot(process);
    assert!(outcome.status().success());
    assert_eq!(outcome.stdout(), b"fixed");
    assert_eq!(outcome.stderr(), b"err");
    assert_eq!(outcome.stdout().as_ptr(), stdout_backing);
    assert_eq!(outcome.stderr().as_ptr(), stderr_backing);
    assert!(outcome.first_fault().is_none());
}

#[test]
fn fixed_oneshot_capture_02_refuses_before_spawn_and_spare_capacity_never_extends_payload() {
    let directory = tempfile::tempdir().unwrap();
    let marker = directory.path().join("must-not-exist");
    let result = OneShotProcess::spawn_fixed_capture(
        command(
            "/bin/sh",
            &["-c", "printf effect > must-not-exist"],
            directory.path(),
        ),
        limits(8, 4),
        buffers(7, 4),
    );
    assert!(matches!(
        result,
        Err(InteractiveSpawnError::CaptureCapacity(OutputStream::Stdout))
    ));
    assert!(!marker.exists());
    let process = OneShotProcess::spawn_fixed_capture(
        command("/bin/sh", &["-c", "printf abcdef"], directory.path()),
        limits(4, 0),
        buffers(8, 0),
    )
    .unwrap();
    let outcome = settle_fixed_oneshot(process);
    assert_eq!(outcome.stdout(), b"abcd");
    assert!(matches!(
        outcome.first_fault(),
        Some(ProcessFault::StdoutLimit)
    ));
}
struct Actual(Option<InteractiveProcess>);
impl Actual {
    fn owner(&mut self) -> &mut InteractiveProcess {
        self.0.as_mut().unwrap()
    }
    fn finish(mut self) -> super::interactive::InteractiveOutcome {
        settle(self.owner());
        match self.0.take().unwrap().into_finished() {
            InteractiveFinish::Finished(outcome) => outcome,
            InteractiveFinish::Pending(owner) => {
                self.0 = Some(owner);
                panic!("actual cleanup must finish")
            }
        }
    }
}
impl Drop for Actual {
    fn drop(&mut self) {
        if let Some(owner) = self.0.as_mut() {
            settle(owner);
        }
    }
}
fn settle(owner: &mut InteractiveProcess) {
    owner.close_stdin();
    let end = Instant::now() + WAIT;
    loop {
        match owner.advance() {
            InteractiveProgress::Faulted(_) | InteractiveProgress::ExitObserved(_) => {
                let _ = owner.request_termination();
            }
            InteractiveProgress::Working | InteractiveProgress::Finished(_) => {}
        }
        let _ = owner.reap_retained();
        if matches!(owner.advance(), InteractiveProgress::Finished(_)) {
            return;
        }
        // This is a test teardown guard, not a new production business window.
        if Instant::now() >= end {
            let _ = owner.request_termination();
        }
        assert!(
            Instant::now() < end + WAIT,
            "actual child/readers did not settle"
        );
        std::thread::sleep(Duration::from_millis(1));
    }
}
fn actual(program: &str, args: &[&str], stdout: usize, directory: &std::path::Path) -> Actual {
    Actual(Some(
        InteractiveProcess::spawn(
            command(program, args, directory),
            limits(stdout, 64),
            buffers(stdout, 64),
        )
        .unwrap(),
    ))
}

#[test]
fn interactive_i01_actual_echo_eof_and_fixed_backing_transfer() {
    let directory = tempfile::tempdir().unwrap();
    let stdout = Vec::with_capacity(128);
    let address = stdout.as_ptr();
    let capacity = stdout.capacity();
    let mut actual = Actual(Some(
        InteractiveProcess::spawn(
            command("/bin/cat", &[], directory.path()),
            limits(128, 0),
            FixedCaptureBuffers::new(stdout, vec![]),
        )
        .unwrap(),
    ));
    let payload = b"first\nsecond\n";
    let mut sent = 0;
    let end = Instant::now() + WAIT;
    let mut error = None;
    while sent < payload.len() && Instant::now() < end {
        match actual.owner().write_stdin(&payload[sent..]) {
            Ok(InteractiveWrite::Written(count)) => sent += count,
            Ok(InteractiveWrite::Pending) => std::thread::yield_now(),
            Err(fault) => {
                error = Some(fault);
                break;
            }
        }
    }
    let before_release = actual.owner().input_state();
    let release = actual.owner().close_stdin();
    let again = actual.owner().close_stdin();
    settle(actual.owner());
    let mut copied = [0u8; 128];
    let copied_result = actual.owner().copy_stdout(0, &mut copied[..payload.len()]);
    let terminal = actual.owner().stdout_terminal();
    let outcome = actual.finish();
    assert!(error.is_none());
    assert_eq!(sent, payload.len());
    assert_eq!(
        before_release,
        InputStateView::Open {
            written: payload.len() as u64
        }
    );
    assert_eq!(
        release,
        InputRelease::HandleReleasedUnverified {
            written: payload.len() as u64
        }
    );
    assert_eq!(again, release);
    assert_eq!(outcome.input_release(), release);
    assert_eq!(outcome.process().status().code(), Some(0));
    assert_eq!(outcome.process().stdout(), payload);
    assert_eq!(outcome.process().stdout().as_ptr(), address);
    assert_eq!(outcome.process().test_prefix_capacities()[0], capacity);
    assert_eq!(copied_result.unwrap(), payload.len());
    assert_eq!(&copied[..payload.len()], payload);
    assert_eq!(terminal, ReadTerminal::Eof);
    assert!(outcome.first_fault().is_none());
}

#[test]
fn interactive_i02_real_backpressure_borrow_cancellation_retains_same_input_progress() {
    let directory = tempfile::tempdir().unwrap();
    let mut actual = actual("/bin/sleep", &["60"], 16, directory.path());
    let id = actual.owner().id();
    let bytes = vec![0x5a; 1024 * 1024];
    let mut sent = 0;
    let mut blocked = false;
    let mut error = None;
    let end = Instant::now() + WAIT;
    while sent < bytes.len() && Instant::now() < end {
        match actual.owner().write_stdin(&bytes[sent..]) {
            Ok(InteractiveWrite::Written(count)) => sent += count,
            Ok(InteractiveWrite::Pending) => {
                blocked = true;
                break;
            }
            Err(fault) => {
                error = Some(fault);
                break;
            }
        }
    }
    let before = actual.owner().input_state();
    let pending = {
        let owner = actual.owner();
        let mut wait = pin!(poll_fn(|_| match owner.write_stdin(&bytes[sent..]) {
            Ok(InteractiveWrite::Pending) => Poll::<()>::Pending,
            _ => Poll::Ready(()),
        }));
        wait.as_mut()
            .poll(&mut Context::from_waker(Waker::noop()))
            .is_pending()
    };
    let after = actual.owner().input_state();
    let same_id = actual.owner().id();
    let _ = actual.owner().request_termination();
    let outcome = actual.finish();
    assert!(error.is_none());
    assert!(
        blocked && pending,
        "genuine unread pipe must reach WouldBlock"
    );
    assert!(
        sent > 0 && sent < bytes.len(),
        "actual partial write, not assumed pipe capacity"
    );
    assert_eq!(
        before,
        InputStateView::Open {
            written: sent as u64
        }
    );
    assert_eq!(after, before);
    assert_eq!(same_id, id);
    assert!(!outcome.process().status().success());
    assert!(outcome.first_fault().is_none());
}

#[test]
fn interactive_i03_stdout_limit_is_sticky_and_spare_capacity_does_not_extend_bound() {
    let directory = tempfile::tempdir().unwrap();
    let mut actual = Actual(Some(
        InteractiveProcess::spawn(
            command("/bin/cat", &[], directory.path()),
            limits(5, 0),
            buffers(128, 0),
        )
        .unwrap(),
    ));
    let sent = actual.owner().write_stdin(b"123456");
    let end = Instant::now() + WAIT;
    let observed = loop {
        if let Some(fault) = actual.owner().first_fault() {
            break Some(*fault);
        }
        actual.owner().advance();
        if Instant::now() >= end {
            break None;
        }
        std::thread::sleep(Duration::from_millis(1));
    };
    let later = actual.owner().write_stdin(b"must-not-write");
    let release = actual.owner().close_stdin();
    let outcome = actual.finish();
    assert_eq!(sent.unwrap(), InteractiveWrite::Written(6));
    assert_eq!(
        observed,
        Some(InteractiveFault::Process(ProcessFault::StdoutLimit))
    );
    assert_eq!(
        later,
        Err(InteractiveFault::Process(ProcessFault::StdoutLimit))
    );
    assert_eq!(
        release,
        InputRelease::HandleReleasedUnverified { written: 6 }
    );
    assert_eq!(outcome.process().stdout(), b"12345");
    assert_eq!(outcome.first_fault(), observed.as_ref());
    assert_eq!(
        outcome.process().first_fault(),
        Some(&ProcessFault::StdoutLimit)
    );
}

#[test]
fn interactive_i04_real_read_failure_is_not_eof_and_reader_is_actually_joined() {
    let directory = tempfile::tempdir().unwrap();
    let file = std::fs::File::open(directory.path()).unwrap();
    let faults = Arc::new(Mutex::new(None));
    let mut reader = OutputReader::start_fixed(
        file,
        OutputStream::Stdout,
        8,
        Vec::with_capacity(8),
        &faults,
    );
    let end = Instant::now() + WAIT;
    while !reader.settled() && Instant::now() < end {
        reader.join_if_finished(&faults);
        std::thread::sleep(Duration::from_millis(1));
    }
    let joined = matches!(reader.thread, ReaderThread::Joined);
    let terminal = lock(&reader.output).terminal;
    let fault = *lock(&faults);
    assert!(
        joined,
        "the real failing reader must be joined before assertions"
    );
    assert!(matches!(
        terminal,
        ReadTerminal::Failed(ProcessFault::PipeRead(OutputStream::Stdout, _))
    ));
    assert!(matches!(
        fault,
        Some(ProcessFault::PipeRead(OutputStream::Stdout, _))
    ));
    assert_ne!(terminal, ReadTerminal::Eof);
}

#[test]
fn interactive_i05_closed_input_is_not_a_successful_write_and_invalid_buffers_refuse() {
    let directory = tempfile::tempdir().unwrap();
    let refused = InteractiveProcess::spawn(
        command("/bin/cat", &[], directory.path()),
        limits(8, 0),
        buffers(7, 0),
    );
    // A returned child would still be cleaned before the intended assertion.
    let refused = match refused {
        Err(fault) => Some(fault),
        Ok(owner) => {
            let _ = Actual(Some(owner)).finish();
            None
        }
    };
    let mut actual = actual("/bin/cat", &[], 8, directory.path());
    let released = actual.owner().close_stdin();
    settle(actual.owner());
    let state = actual.owner().input_state();
    let written = actual.owner().write_stdin(b"x");
    let outcome = actual.finish();
    assert!(matches!(
        refused,
        Some(InteractiveSpawnError::CaptureCapacity(OutputStream::Stdout))
    ));
    assert_eq!(
        released,
        InputRelease::HandleReleasedUnverified { written: 0 }
    );
    assert_eq!(
        state,
        InputStateView::HandleReleasedUnverified { written: 0 }
    );
    assert_eq!(written, Err(InteractiveFault::InputReleased));
    assert_eq!(outcome.process().status().code(), Some(0));
    assert_eq!(
        outcome.first_fault(),
        Some(&InteractiveFault::InputReleased)
    );
}

#[test]
fn interactive_i06_ordinary_null_stdin_and_original_capture_are_preserved() {
    let directory = tempfile::tempdir().unwrap();
    let mut process =
        OneShotProcess::spawn(command("/bin/cat", &[], directory.path()), limits(8, 8)).unwrap();
    let end = Instant::now() + WAIT;
    loop {
        match process.advance() {
            ProcessProgress::ExitObserved(_) | ProcessProgress::Faulted(_) => {
                let _ = process.request_termination();
            }
            ProcessProgress::Working | ProcessProgress::Finished(_) => {}
        }
        let _ = process.reap_retained();
        if matches!(process.advance(), ProcessProgress::Finished(_)) {
            break;
        }
        if Instant::now() >= end {
            let _ = process.request_termination();
        }
        assert!(Instant::now() < end + WAIT);
        std::thread::sleep(Duration::from_millis(1));
    }
    let outcome = match process.into_finished() {
        ProcessFinish::Finished(o) => o,
        ProcessFinish::Pending(_) => panic!("actual ordinary child/readers remain pending"),
    };
    assert_eq!(outcome.status().code(), Some(0));
    assert!(outcome.stdout().is_empty() && outcome.stderr().is_empty());
    assert!(outcome.first_fault().is_none());
}

// Reader-component controls. The wrapper forwards real OS File reads unchanged,
// then panics during actual reader destruction; it invents no read result.
struct PanicAfterFileRead(std::fs::File);
impl Read for PanicAfterFileRead {
    fn read(&mut self, bytes: &mut [u8]) -> io::Result<usize> {
        self.0.read(bytes)
    }
}
impl Drop for PanicAfterFileRead {
    fn drop(&mut self) {
        panic!("actual reader wrapper destructor panic after OS read");
    }
}
fn join_panicking_file(file: std::fs::File) -> (ReadTerminal, ReadTerminal, Option<ProcessFault>) {
    let faults = Arc::new(Mutex::new(None));
    let mut reader = OutputReader::start_fixed(
        PanicAfterFileRead(file),
        OutputStream::Stdout,
        8,
        Vec::with_capacity(8),
        &faults,
    );
    let end = Instant::now() + WAIT;
    let timed_out = loop {
        if !matches!(&reader.thread, ReaderThread::Running(thread) if !thread.is_finished()) {
            break false;
        }
        if Instant::now() >= end {
            break true;
        }
        std::thread::sleep(Duration::from_millis(1));
    };
    let before = lock(&reader.output).terminal;
    if timed_out {
        // Teardown owns and joins the actual local-file reader even if the
        // readiness bound failed. That branch cannot satisfy this control.
        if let ReaderThread::Running(thread) =
            std::mem::replace(&mut reader.thread, ReaderThread::Joined)
        {
            let _ = thread.join();
        }
    } else {
        reader.join_if_finished(&faults);
    }
    let joined = matches!(reader.thread, ReaderThread::Joined);
    let after = lock(&reader.output).terminal;
    let first_fault = *lock(&faults);
    assert!(
        !timed_out && joined,
        "actual reader must join before terminal assertions"
    );
    (before, after, first_fault)
}

#[test]
fn interactive_i07_actual_eof_survives_later_reader_destructor_panic() {
    let (before, after, first_fault) =
        join_panicking_file(std::fs::File::open("/dev/null").unwrap());
    assert_eq!(before, ReadTerminal::Eof);
    assert_eq!(after, ReadTerminal::Eof);
    assert_eq!(
        first_fault,
        Some(ProcessFault::ReaderPanicked(OutputStream::Stdout))
    );
}

#[test]
fn interactive_i08_actual_read_error_survives_later_reader_destructor_panic() {
    let directory = tempfile::tempdir().unwrap();
    let (before, after, first_fault) =
        join_panicking_file(std::fs::File::open(directory.path()).unwrap());
    assert!(matches!(
        before,
        ReadTerminal::Failed(ProcessFault::PipeRead(OutputStream::Stdout, _))
    ));
    assert_eq!(after, before);
    let ReadTerminal::Failed(actual) = before else {
        unreachable!()
    };
    assert_eq!(first_fault, Some(actual));
}
