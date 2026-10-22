//! Private physical stdio ownership, not a browser/source or budget grant.
//! The caller supplies fixed capture storage. Complete controller preparation
//! must separately fund actual metadata, storage and all control-copy work.
use super::*;

/// Already allocated caller storage. Spare capacity never changes Limits.
pub(crate) struct FixedCaptureBuffers {
    stdout: Vec<u8>,
    stderr: Vec<u8>,
}
impl FixedCaptureBuffers {
    pub(crate) fn new(stdout: Vec<u8>, stderr: Vec<u8>) -> Self {
        Self { stdout, stderr }
    }
    fn validate(&self, limits: Limits) -> Result<(), InteractiveSpawnError> {
        for (stream, bytes, bound) in [
            (OutputStream::Stdout, &self.stdout, limits.max_frame),
            (OutputStream::Stderr, &self.stderr, limits.stderr_capture),
        ] {
            if !bytes.is_empty() {
                return Err(InteractiveSpawnError::CaptureNotEmpty(stream));
            }
            if bytes.capacity() < bound {
                return Err(InteractiveSpawnError::CaptureCapacity(stream));
            }
        }
        Ok(())
    }
}
#[derive(Debug)]
pub(crate) enum InteractiveSpawnError {
    CaptureCapacity(OutputStream),
    CaptureNotEmpty(OutputStream),
    Process(ProcessError),
}
impl OneShotProcess {
    /// Consume the caller's fixed backing through the existing output readers.
    /// This owns physical capture only; it grants no source or launch authority.
    #[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
    pub(crate) fn spawn_fixed_capture(
        spec: CommandSpec,
        limits: Limits,
        capture: FixedCaptureBuffers,
    ) -> Result<Self, InteractiveSpawnError> {
        capture.validate(limits)?;
        Self::spawn_with_io(
            spec,
            limits,
            ProcessInput::Null,
            CaptureBuffers::Fixed {
                stdout: capture.stdout,
                stderr: capture.stderr,
            },
        )
        .map(|(process, _)| process)
        .map_err(InteractiveSpawnError::Process)
    }
    #[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
    pub(crate) fn spawn_fixed_capture(
        _spec: CommandSpec,
        _limits: Limits,
        _capture: FixedCaptureBuffers,
    ) -> Result<Self, InteractiveSpawnError> {
        Err(InteractiveSpawnError::Process(
            ProcessError::UnsupportedPlatform,
        ))
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum InteractiveFault {
    Process(ProcessFault),
    InputSetup(io::ErrorKind),
    InputWrite(io::ErrorKind),
    InputReleased,
    InputSizeOverflow,
    InvalidCursor,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum InteractiveWrite {
    Pending,
    Written(usize),
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum InputRelease {
    /// ChildStdin was consumed by Drop exactly once. No OS close result exists.
    HandleReleasedUnverified {
        written: u64,
    },
    NotCreated,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum InputStateView {
    Open { written: u64 },
    HandleReleasedUnverified { written: u64 },
    NotCreated,
}
enum Input {
    Open { pipe: ChildStdin, written: u64 },
    Released(InputRelease),
}
pub(crate) struct InteractiveProcess {
    process: OneShotProcess,
    input: Input,
    first_fault: Option<InteractiveFault>,
}
pub(crate) enum InteractiveProgress<'a> {
    Working,
    Faulted(&'a InteractiveFault),
    ExitObserved(&'a ExitObservation),
    /// Actual process/readers completion only; first_fault remains separate.
    Finished(&'a ProcessOutcome),
}
pub(crate) enum InteractiveFinish {
    Pending(InteractiveProcess),
    Finished(InteractiveOutcome),
}
pub(crate) struct InteractiveOutcome {
    process: ProcessOutcome,
    input: InputRelease,
    first_fault: Option<InteractiveFault>,
}
impl InteractiveOutcome {
    pub(crate) fn stdout_terminal(&self) -> ReadTerminal {
        self.process.stdout_terminal
    }
    pub(crate) fn process(&self) -> &ProcessOutcome {
        &self.process
    }
    pub(crate) fn input_release(&self) -> InputRelease {
        self.input
    }
    pub(crate) fn first_fault(&self) -> Option<&InteractiveFault> {
        self.first_fault.as_ref()
    }
}
impl InteractiveProcess {
    #[cfg(not(target_os = "macos"))]
    pub(crate) fn spawn(
        _spec: CommandSpec,
        _limits: Limits,
        _capture: FixedCaptureBuffers,
    ) -> Result<Self, InteractiveSpawnError> {
        // No blocking-input fallback or qualification for an untested backend.
        Err(InteractiveSpawnError::Process(
            ProcessError::UnsupportedPlatform,
        ))
    }
    #[cfg(target_os = "macos")]
    pub(crate) fn spawn(
        spec: CommandSpec,
        limits: Limits,
        capture: FixedCaptureBuffers,
    ) -> Result<Self, InteractiveSpawnError> {
        use rustix::fs::{OFlags, fcntl_getfl, fcntl_setfl};
        capture.validate(limits)?;
        let (process, stdin) = OneShotProcess::spawn_with_io(
            spec,
            limits,
            ProcessInput::Piped,
            CaptureBuffers::Fixed {
                stdout: capture.stdout,
                stderr: capture.stderr,
            },
        )
        .map_err(InteractiveSpawnError::Process)?;
        // From here onward the actual child/readers MUST be returned retained,
        // including fcntl or missing-input setup failure. No bare Err is possible.
        let mut owner = Self {
            process,
            input: match stdin {
                Some(pipe) => Input::Open { pipe, written: 0 },
                None => Input::Released(InputRelease::NotCreated),
            },
            first_fault: None,
        };
        let setup = match &owner.input {
            Input::Open { pipe, .. } => fcntl_getfl(pipe)
                .and_then(|flags| fcntl_setfl(pipe, flags | OFlags::NONBLOCK))
                .map_err(|error| io::Error::from(error).kind()),
            Input::Released(_) => Err(io::ErrorKind::BrokenPipe),
        };
        if let Err(kind) = setup {
            owner.advance();
            owner.fail(InteractiveFault::InputSetup(kind));
            let _ = owner.request_termination();
        }
        Ok(owner)
    }
    fn fail(&mut self, fault: InteractiveFault) -> InteractiveFault {
        *self.first_fault.get_or_insert(fault)
    }
    pub(crate) fn id(&self) -> u32 {
        self.process.id()
    }
    pub(crate) fn first_fault(&self) -> Option<&InteractiveFault> {
        self.first_fault.as_ref()
    }
    pub(crate) fn input_state(&self) -> InputStateView {
        match &self.input {
            Input::Open { written, .. } => InputStateView::Open { written: *written },
            Input::Released(InputRelease::HandleReleasedUnverified { written }) => {
                InputStateView::HandleReleasedUnverified { written: *written }
            }
            Input::Released(InputRelease::NotCreated) => InputStateView::NotCreated,
        }
    }
    pub(crate) fn write_stdin(
        &mut self,
        bytes: &[u8],
    ) -> Result<InteractiveWrite, InteractiveFault> {
        use std::io::Write as _;
        self.advance();
        if let Some(fault) = self.first_fault {
            return Err(fault);
        }
        let Input::Open { pipe, written } = &mut self.input else {
            return Err(self.fail(InteractiveFault::InputReleased));
        };
        // Check the largest possible accounting update BEFORE the syscall.
        let requested = u64::try_from(bytes.len()).ok();
        if requested.and_then(|n| written.checked_add(n)).is_none() {
            return Err(self.fail(InteractiveFault::InputSizeOverflow));
        }
        match pipe.write(bytes) {
            Ok(0) if !bytes.is_empty() => {
                Err(self.fail(InteractiveFault::InputWrite(io::ErrorKind::WriteZero)))
            }
            Ok(count) => {
                // Actual progress is retained before returning or any caller's
                // later deadline/cancellation observation. Never write_all.
                *written += u64::try_from(count).expect("count bounded by checked request");
                Ok(InteractiveWrite::Written(count))
            }
            Err(error)
                if matches!(
                    error.kind(),
                    io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted
                ) =>
            {
                Ok(InteractiveWrite::Pending)
            }
            Err(error) => Err(self.fail(InteractiveFault::InputWrite(error.kind()))),
        }
    }
    pub(crate) fn close_stdin(&mut self) -> InputRelease {
        let previous =
            std::mem::replace(&mut self.input, Input::Released(InputRelease::NotCreated));
        let released = match previous {
            Input::Open { pipe, written } => {
                // Retire the unique field before actual handle disposal. std
                // exposes no close result; no numeric retry/OS success claim.
                drop(pipe);
                InputRelease::HandleReleasedUnverified { written }
            }
            Input::Released(released) => released,
        };
        self.input = Input::Released(released);
        released
    }
    pub(crate) fn advance(&mut self) -> InteractiveProgress<'_> {
        let progress = self.process.advance();
        let process_fault = match &progress {
            ProcessProgress::Faulted(fault) => Some(**fault),
            ProcessProgress::Finished(outcome) => outcome.first_fault().copied(),
            _ => None,
        };
        if let Some(fault) = process_fault {
            self.first_fault
                .get_or_insert(InteractiveFault::Process(fault));
        }
        match progress {
            // Preserve actual completion even when an earlier input fault
            // exists. Finished never means healthy protocol/business success.
            ProcessProgress::Finished(outcome) => InteractiveProgress::Finished(outcome),
            _ if self.first_fault.is_some() => {
                InteractiveProgress::Faulted(self.first_fault.as_ref().unwrap())
            }
            ProcessProgress::Working => InteractiveProgress::Working,
            ProcessProgress::ExitObserved(observed) => InteractiveProgress::ExitObserved(observed),
            ProcessProgress::Faulted(_) => unreachable!("process fault retained above"),
        }
    }
    pub(crate) fn request_termination(
        &mut self,
    ) -> Result<TerminationDisposition, TerminationRefusal> {
        self.process.request_termination()
    }
    pub(crate) fn reap_retained(&mut self) -> Result<ReapProgress, ReapError> {
        self.process.reap_retained()
    }
    pub(crate) fn into_finished(mut self) -> InteractiveFinish {
        self.advance();
        if matches!(self.input, Input::Open { .. }) {
            return InteractiveFinish::Pending(self);
        }
        let Self {
            process,
            input,
            first_fault,
        } = self;
        match process.into_finished() {
            ProcessFinish::Pending(process) => InteractiveFinish::Pending(Self {
                process,
                input,
                first_fault,
            }),
            ProcessFinish::Finished(process) => {
                let Input::Released(input) = input else {
                    unreachable!("open input retained above")
                };
                InteractiveFinish::Finished(InteractiveOutcome {
                    process,
                    input,
                    first_fault,
                })
            }
        }
    }
    pub(crate) fn stdout_available(&self, cursor: usize) -> Result<usize, InteractiveFault> {
        let length = match &self.process.state {
            State::Active(active) => lock(&active.stdout.output).bytes.len(),
            State::Finished(outcome) => outcome.stdout.len(),
            State::Consumed => unreachable!("consumed owner cannot be lent"),
        };
        length
            .checked_sub(cursor)
            .ok_or(InteractiveFault::InvalidCursor)
    }
    pub(crate) fn copy_stdout(
        &self,
        cursor: usize,
        destination: &mut [u8],
    ) -> Result<usize, InteractiveFault> {
        fn copy(
            bytes: &[u8],
            cursor: usize,
            destination: &mut [u8],
        ) -> Result<usize, InteractiveFault> {
            let available = bytes.get(cursor..).ok_or(InteractiveFault::InvalidCursor)?;
            let count = available.len().min(destination.len());
            destination[..count].copy_from_slice(&available[..count]);
            Ok(count)
        }
        match &self.process.state {
            State::Active(active) => copy(&lock(&active.stdout.output).bytes, cursor, destination),
            State::Finished(outcome) => copy(&outcome.stdout, cursor, destination),
            State::Consumed => unreachable!("consumed owner cannot be lent"),
        }
    }
    pub(crate) fn stdout_terminal(&self) -> ReadTerminal {
        match &self.process.state {
            State::Active(active) => lock(&active.stdout.output).terminal,
            State::Finished(outcome) => outcome.stdout_terminal,
            State::Consumed => unreachable!("consumed owner cannot be lent"),
        }
    }
    pub(crate) fn stderr_terminal(&self) -> ReadTerminal {
        match &self.process.state {
            State::Active(active) => lock(&active.stderr.output).terminal,
            State::Finished(outcome) => outcome.stderr_terminal,
            State::Consumed => unreachable!("consumed owner cannot be lent"),
        }
    }
}
