//! Ordinary one-shot processes, using the SAME transport process-tree owner.
//!
//! This module supplies no adapter protocol, source grant or cleanup inference.
//! Retained output limits count payload bytes, not allocator capacity or RSS.
use std::{
    ffi::{OsStr, OsString},
    io::{self, Read},
    path::PathBuf,
    process::{Child, Command, ExitStatus, Stdio},
    sync::{Arc, Mutex, MutexGuard},
    thread::{self, JoinHandle},
};

use super::{
    Limits,
    tree::{self, ProcessTree},
};

/// A validated command description. Constructing it performs no effects.
pub struct CommandSpec {
    program: PathBuf,
    arguments: Vec<OsString>,
    directory: PathBuf,
    environment: Vec<(OsString, OsString)>,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CommandSpecError {
    RelativeProgram,
    RelativeDirectory,
    InvalidEnvironment,
    DuplicateEnvironmentKey,
}
impl CommandSpec {
    pub fn new(
        program: PathBuf,
        arguments: Vec<OsString>,
        directory: PathBuf,
        environment: Vec<(OsString, OsString)>,
    ) -> Result<Self, CommandSpecError> {
        if !program.is_absolute() {
            return Err(CommandSpecError::RelativeProgram);
        }
        if !directory.is_absolute() {
            return Err(CommandSpecError::RelativeDirectory);
        }
        for (index, (key, value)) in environment.iter().enumerate() {
            if key.is_empty()
                || key.as_encoded_bytes().iter().any(|b| matches!(b, 0 | b'='))
                || value.as_encoded_bytes().contains(&0)
            {
                return Err(CommandSpecError::InvalidEnvironment);
            }
            for (previous, _) in &environment[..index] {
                if environment_key_equal(previous, key)? {
                    return Err(CommandSpecError::DuplicateEnvironmentKey);
                }
            }
        }
        Ok(Self {
            program,
            arguments,
            directory,
            environment,
        })
    }
}
#[cfg(not(windows))]
fn environment_key_equal(left: &OsStr, right: &OsStr) -> Result<bool, CommandSpecError> {
    Ok(left == right)
}
#[cfg(windows)]
fn environment_key_equal(left: &OsStr, right: &OsStr) -> Result<bool, CommandSpecError> {
    use std::os::windows::ffi::OsStrExt as _;
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn CompareStringOrdinal(
            left: *const u16,
            left_len: i32,
            right: *const u16,
            right_len: i32,
            ignore_case: i32,
        ) -> i32;
    }
    let left: Vec<u16> = left.encode_wide().collect();
    let right: Vec<u16> = right.encode_wide().collect();
    let left_len = i32::try_from(left.len()).map_err(|_| CommandSpecError::InvalidEnvironment)?;
    let right_len = i32::try_from(right.len()).map_err(|_| CommandSpecError::InvalidEnvironment)?;
    // SAFETY: both counted UTF16 slices remain alive; ignore_case is TRUE=1.
    // Use Windows ordinal casing, not Unicode normalization or lossy strings.
    match unsafe { CompareStringOrdinal(left.as_ptr(), left_len, right.as_ptr(), right_len, 1) } {
        0 => Err(CommandSpecError::InvalidEnvironment),
        2 => Ok(true),
        _ => Ok(false),
    }
}

#[derive(Debug)]
pub enum ProcessError {
    Spawn(io::Error),
    UnsupportedPlatform,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OutputStream {
    Stdout,
    Stderr,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProcessFault {
    StdoutLimit,
    OutputAllocation(OutputStream),
    PipeRead(OutputStream, io::ErrorKind),
    PipeThreadStart(OutputStream, io::ErrorKind),
    ReaderPanicked(OutputStream),
    Containment,
    ChildWait(io::ErrorKind),
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DescendantEvidence {
    Unobserved,
    TerminationRequestedUnverified,
}
/// Finished certifies actual direct-child status and actual joins of every
/// reader thread that was created. Missing readers remain a sticky fault.
pub struct ProcessOutcome {
    status: ExitStatus,
    observed: ExitObservation,
    stdout: Vec<u8>,
    stderr: Vec<u8>,
    stderr_truncated: bool,
    first_fault: Option<ProcessFault>,
    descendants: DescendantEvidence,
    // Raw finish transfers this SAME tree lease. In particular, consuming the
    // process must not close a Windows kill-on-close job before returning its
    // Unobserved outcome. This private RAII field issues no authority or join
    // proof. Callers requiring helper cleanup must explicitly terminate first.
    _retained_tree: Option<ProcessTree>,
}
impl ProcessOutcome {
    pub fn status(&self) -> ExitStatus {
        self.status
    }
    pub fn stdout(&self) -> &[u8] {
        &self.stdout
    }
    pub fn stderr(&self) -> &[u8] {
        &self.stderr
    }
    pub fn stderr_truncated(&self) -> bool {
        self.stderr_truncated
    }
    pub fn first_fault(&self) -> Option<&ProcessFault> {
        self.first_fault.as_ref()
    }
    pub fn descendants(&self) -> DescendantEvidence {
        self.descendants
    }
}
/// Moving the same pending owner is an expected state, not an error.
pub enum ProcessFinish {
    Finished(ProcessOutcome),
    Pending(OneShotProcess),
}

pub enum ProcessProgress<'a> {
    Working,
    Faulted(&'a ProcessFault),
    ExitObserved(&'a ExitObservation),
    Finished(&'a ProcessOutcome),
}
/// Actual exit evidence, separate from the consuming std wait result.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ExitObservation(ExitKind);
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ExitKind {
    Code(i32),
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    Signal(i32),
    #[cfg(windows)]
    OtherStatus,
}
impl ExitObservation {
    pub fn code(&self) -> Option<i32> {
        match self.0 {
            ExitKind::Code(code) => Some(code),
            _ => None,
        }
    }
    pub fn signal(&self) -> Option<i32> {
        match self.0 {
            #[cfg(any(target_os = "linux", target_os = "macos"))]
            ExitKind::Signal(signal) => Some(signal),
            _ => None,
        }
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReapProgress {
    Pending,
    Reaped,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReapError {
    OwnershipUnproven,
    Wait(io::ErrorKind),
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TerminationDisposition {
    Requested,
    AlreadyRequested,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TerminationRefusal {
    ReapedAuthorityRetired,
    IdentityUnproven,
    ObservationInterrupted,
    Consumed,
}
/// Only Unreaped permits Unix numeric signaling. ReapPending has already
/// retired that authority even though the actual std wait may need a retry.
enum ChildLifetime {
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    Unreaped(Option<ExitObservation>),
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    ReapPending(ExitObservation),
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    Unproven(Option<ExitObservation>),
    #[cfg(windows)]
    JobRunning,
    Reaped {
        status: ExitStatus,
        observed: ExitObservation,
    },
}
impl ChildLifetime {
    fn status(&self) -> Option<ExitStatus> {
        match self {
            Self::Reaped { status, .. } => Some(*status),
            _ => None,
        }
    }
    fn observed(&self) -> Option<&ExitObservation> {
        match self {
            Self::Reaped { observed, .. } => Some(observed),
            #[cfg(any(target_os = "linux", target_os = "macos"))]
            Self::Unreaped(observed) | Self::Unproven(observed) => observed.as_ref(),
            #[cfg(any(target_os = "linux", target_os = "macos"))]
            Self::ReapPending(observed) => Some(observed),
            #[cfg(windows)]
            Self::JobRunning => None,
        }
    }
}
type FaultOwner = Arc<Mutex<Option<ProcessFault>>>;
fn lock<T>(value: &Mutex<T>) -> MutexGuard<'_, T> {
    value
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}
fn record(owner: &FaultOwner, fault: ProcessFault) {
    lock(owner).get_or_insert(fault);
}
#[derive(Default)]
struct OutputState {
    bytes: Vec<u8>,
    truncated: bool,
}
enum ReaderThread {
    Running(JoinHandle<()>),
    Joined,
    NotCreated,
}
struct OutputReader {
    output: Arc<Mutex<OutputState>>,
    thread: ReaderThread,
    stream: OutputStream,
}
impl OutputReader {
    fn start(
        pipe: impl Read + Send + 'static,
        stream: OutputStream,
        bound: usize,
        faults: &FaultOwner,
    ) -> Self {
        let output = Arc::new(Mutex::new(OutputState::default()));
        let writer = output.clone();
        let errors = faults.clone();
        let spawned = thread::Builder::new()
            .name(
                match stream {
                    OutputStream::Stdout => "mck-one-shot-stdout",
                    OutputStream::Stderr => "mck-one-shot-stderr",
                }
                .into(),
            )
            .spawn(move || read_output(pipe, stream, bound, &writer, &errors));
        let thread = match spawned {
            Ok(thread) => ReaderThread::Running(thread),
            Err(error) => {
                record(faults, ProcessFault::PipeThreadStart(stream, error.kind()));
                ReaderThread::NotCreated
            }
        };
        Self {
            output,
            thread,
            stream,
        }
    }
    fn join_if_finished(&mut self, faults: &FaultOwner) {
        if matches!(&self.thread,ReaderThread::Running(thread) if thread.is_finished()) {
            let ReaderThread::Running(thread) =
                std::mem::replace(&mut self.thread, ReaderThread::Joined)
            else {
                unreachable!()
            };
            // is_finished is only readiness. This ACTUAL join resolves panic.
            if thread.join().is_err() {
                record(faults, ProcessFault::ReaderPanicked(self.stream));
            }
        }
    }
    fn settled(&self) -> bool {
        !matches!(self.thread, ReaderThread::Running(_))
    }
}
fn read_output(
    mut pipe: impl Read,
    stream: OutputStream,
    bound: usize,
    output: &Mutex<OutputState>,
    faults: &FaultOwner,
) {
    let mut block = [0u8; 8192];
    loop {
        let count = match pipe.read(&mut block) {
            Ok(0) => return,
            Ok(count) => count,
            Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
            Err(error) => {
                record(faults, ProcessFault::PipeRead(stream, error.kind()));
                return;
            }
        };
        let mut state = lock(output);
        let retain = count.min(bound.saturating_sub(state.bytes.len()));
        if retain < count {
            state.truncated = true;
            if stream == OutputStream::Stdout {
                record(faults, ProcessFault::StdoutLimit);
            }
        }
        // Reserve before each retained payload growth/copy. Excess output is
        // drained without an unbounded queue, including a zero stderr prefix.
        if state.bytes.try_reserve_exact(retain).is_err() {
            record(faults, ProcessFault::OutputAllocation(stream));
            state.truncated = true;
            continue;
        }
        state.bytes.extend_from_slice(&block[..retain]);
    }
}
struct ActiveProcess {
    child: Child,
    lifetime: ChildLifetime,
    stdout: OutputReader,
    stderr: OutputReader,
    faults: FaultOwner,
    first_fault: Option<ProcessFault>,
}
enum State {
    Active(ActiveProcess),
    Finished(ProcessOutcome),
    Consumed,
}
/// Real one-shot process ownership. No await, reaper or blocking error cleanup.
pub struct OneShotProcess {
    id: u32,
    tree: Option<ProcessTree>,
    state: State,
    termination: DescendantEvidence,
}
impl OneShotProcess {
    #[cfg(not(any(target_os = "linux", target_os = "macos", windows)))]
    pub fn spawn(_spec: CommandSpec, _limits: Limits) -> Result<Self, ProcessError> {
        // No reaping poll fallback may silently invalidate numeric authority.
        Err(ProcessError::UnsupportedPlatform)
    }
    #[cfg(any(target_os = "linux", target_os = "macos", windows))]
    pub fn spawn(spec: CommandSpec, limits: Limits) -> Result<Self, ProcessError> {
        let mut command = Command::new(spec.program);
        command
            .args(spec.arguments)
            .current_dir(spec.directory)
            .env_clear()
            .envs(spec.environment)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        tree::configure(&mut command);
        // Only a spawn failure returns Err: there is no returned actual child.
        let mut child = command.spawn().map_err(ProcessError::Spawn)?;
        let id = child.id();
        let faults = Arc::new(Mutex::new(None));
        let tree = match ProcessTree::attach(&child) {
            Ok(tree) => Some(tree),
            Err(_) => {
                record(&faults, ProcessFault::Containment);
                None
            }
        };
        let stdout = OutputReader::start(
            child.stdout.take().expect("pipedstdout"),
            OutputStream::Stdout,
            limits.max_frame,
            &faults,
        );
        let stderr = OutputReader::start(
            child.stderr.take().expect("pipedstderr"),
            OutputStream::Stderr,
            limits.stderr_capture,
            &faults,
        );
        let must_stop = tree.is_none()
            || matches!(&stdout.thread, ReaderThread::NotCreated)
            || matches!(&stderr.thread, ReaderThread::NotCreated);
        let mut owner = Self {
            id,
            tree,
            state: State::Active(ActiveProcess {
                child,
                #[cfg(any(target_os = "linux", target_os = "macos"))]
                lifetime: ChildLifetime::Unreaped(None),
                #[cfg(windows)]
                lifetime: ChildLifetime::JobRunning,
                stdout,
                stderr,
                faults,
                first_fault: None,
            }),
            termination: DescendantEvidence::Unobserved,
        };
        // Attachment/thread-start failures retain the actual child/readers in
        // a faulted owner. Request containment now, never wait/join invisibly.
        if must_stop {
            let _ = owner.request_termination();
        }
        Ok(owner)
    }
    pub fn id(&self) -> u32 {
        self.id
    }
    pub fn status(&self) -> Option<ExitStatus> {
        match &self.state {
            State::Active(active) => active.lifetime.status(),
            State::Finished(outcome) => Some(outcome.status),
            State::Consumed => None,
        }
    }
    pub fn observed_exit(&self) -> Option<&ExitObservation> {
        match &self.state {
            State::Active(active) => active.lifetime.observed(),
            State::Finished(outcome) => Some(&outcome.observed),
            State::Consumed => None,
        }
    }
    /// Signal at most once, only while the Unix child is still waitable.
    /// A private Child assumes exclusive wait ownership. A foreign processwide
    /// reaper is uncertainty, never permission to target a numeric group.
    pub fn request_termination(&mut self) -> Result<TerminationDisposition, TerminationRefusal> {
        if matches!(self.state, State::Consumed) {
            return Err(TerminationRefusal::Consumed);
        }
        if self.termination == DescendantEvidence::TerminationRequestedUnverified {
            return Ok(TerminationDisposition::AlreadyRequested);
        }
        #[cfg(any(target_os = "linux", target_os = "macos"))]
        {
            let State::Active(active) = &mut self.state else {
                return Err(TerminationRefusal::ReapedAuthorityRetired);
            };
            match active.lifetime {
                ChildLifetime::Unreaped(_) => {}
                ChildLifetime::Unproven(_) => return Err(TerminationRefusal::IdentityUnproven),
                _ => return Err(TerminationRefusal::ReapedAuthorityRetired),
            }
            // One non-consuming query precedes EVERY first signal, including
            // Drop without advance and construction-failure containment.
            match observe_unreaped(&active.child) {
                Ok(observed) => {
                    active.lifetime = ChildLifetime::Unreaped(observed);
                }
                Err(error) if error.kind() == io::ErrorKind::Interrupted => {
                    return Err(TerminationRefusal::ObservationInterrupted);
                }
                Err(error) => {
                    let observed = active.lifetime.observed().copied();
                    active.lifetime = ChildLifetime::Unproven(observed);
                    self.tree.take();
                    record(&active.faults, ProcessFault::ChildWait(error.kind()));
                    return Err(TerminationRefusal::IdentityUnproven);
                }
            }
        }
        #[cfg(not(any(target_os = "linux", target_os = "macos", windows)))]
        return Err(TerminationRefusal::IdentityUnproven);

        // Commit the once-only transition before any actual signal. Unix
        // WNOWAIT reserves the leader pid/group until our explicit reap.
        self.termination = DescendantEvidence::TerminationRequestedUnverified;
        if let Some(tree) = &self.tree {
            tree.terminator().kill();
        }
        if let State::Active(active) = &mut self.state
            && active.lifetime.status().is_none()
        {
            let _ = active.child.kill();
        }
        if let State::Finished(outcome) = &mut self.state {
            outcome.descendants = self.termination;
        }
        Ok(TerminationDisposition::Requested)
    }
    /// Explicitly retire Unix numeric authority before consuming child status.
    /// A Pending result never restores that authority.
    pub fn reap_retained(&mut self) -> Result<ReapProgress, ReapError> {
        let State::Active(active) = &mut self.state else {
            return match self.state {
                State::Finished(_) => Ok(ReapProgress::Reaped),
                _ => Err(ReapError::OwnershipUnproven),
            };
        };
        if active.lifetime.status().is_some() {
            return Ok(ReapProgress::Reaped);
        }
        #[cfg(any(target_os = "linux", target_os = "macos"))]
        {
            let observed = match active.lifetime {
                ChildLifetime::Unreaped(Some(observed)) => {
                    // Retire BEFORE the consuming wait, not after its return.
                    self.tree.take();
                    active.lifetime = ChildLifetime::ReapPending(observed);
                    observed
                }
                ChildLifetime::ReapPending(observed) => observed,
                ChildLifetime::Unreaped(None) => return Ok(ReapProgress::Pending),
                _ => return Err(ReapError::OwnershipUnproven),
            };
            match active.child.try_wait() {
                Ok(Some(status)) => {
                    active.lifetime = ChildLifetime::Reaped { status, observed };
                    Ok(ReapProgress::Reaped)
                }
                Ok(None) => {
                    // EXITED was actually observed. An unexpected None is
                    // uncertainty, not permission to reacquire numeric IDs.
                    active.lifetime = ChildLifetime::Unproven(Some(observed));
                    record(
                        &active.faults,
                        ProcessFault::ChildWait(io::ErrorKind::InvalidData),
                    );
                    Ok(ReapProgress::Pending)
                }
                Err(error) => {
                    record(&active.faults, ProcessFault::ChildWait(error.kind()));
                    if error.kind() == io::ErrorKind::Interrupted {
                        Ok(ReapProgress::Pending)
                    } else {
                        active.lifetime = ChildLifetime::Unproven(Some(observed));
                        Err(ReapError::Wait(error.kind()))
                    }
                }
            }
        }
        #[cfg(windows)]
        {
            poll_job_child(active);
            Ok(if active.lifetime.status().is_some() {
                ReapProgress::Reaped
            } else {
                ReapProgress::Pending
            })
        }
        #[cfg(not(any(target_os = "linux", target_os = "macos", windows)))]
        Err(ReapError::OwnershipUnproven)
    }
    pub fn advance(&mut self) -> ProcessProgress<'_> {
        if let State::Active(active) = &mut self.state {
            #[cfg(any(target_os = "linux", target_os = "macos"))]
            if matches!(active.lifetime, ChildLifetime::Unreaped(_)) {
                match observe_unreaped(&active.child) {
                    Ok(observed) => active.lifetime = ChildLifetime::Unreaped(observed),
                    Err(error) if error.kind() == io::ErrorKind::Interrupted => {}
                    Err(error) => {
                        let observed = active.lifetime.observed().copied();
                        active.lifetime = ChildLifetime::Unproven(observed);
                        self.tree.take();
                        record(&active.faults, ProcessFault::ChildWait(error.kind()));
                    }
                }
            }
            #[cfg(windows)]
            poll_job_child(active);
            active.stdout.join_if_finished(&active.faults);
            active.stderr.join_if_finished(&active.faults);
            active.first_fault = *lock(&active.faults);
            if let ChildLifetime::Reaped { status, observed } = active.lifetime
                && active.stdout.settled()
                && active.stderr.settled()
            {
                let stdout = std::mem::take(&mut lock(&active.stdout.output).bytes);
                let (stderr, stderr_truncated) = {
                    let mut output = lock(&active.stderr.output);
                    (std::mem::take(&mut output.bytes), output.truncated)
                };
                self.state = State::Finished(ProcessOutcome {
                    status,
                    observed,
                    stdout,
                    stderr,
                    stderr_truncated,
                    first_fault: active.first_fault,
                    descendants: self.termination,
                    _retained_tree: None,
                });
            }
        }
        match &self.state {
            State::Active(active) => match &active.first_fault {
                Some(fault) => ProcessProgress::Faulted(fault),
                None => match active.lifetime.observed() {
                    Some(observed) => ProcessProgress::ExitObserved(observed),
                    None => ProcessProgress::Working,
                },
            },
            State::Finished(outcome) => ProcessProgress::Finished(outcome),
            State::Consumed => unreachable!("consumedowner"),
        }
    }
    pub fn into_finished(mut self) -> ProcessFinish {
        if !matches!(self.state, State::Finished(_)) {
            return ProcessFinish::Pending(self);
        }
        let State::Finished(mut outcome) = std::mem::replace(&mut self.state, State::Consumed)
        else {
            unreachable!()
        };
        outcome._retained_tree = self.tree.take();
        ProcessFinish::Finished(outcome)
    }
}
impl Drop for OneShotProcess {
    fn drop(&mut self) {
        // Containment only. No blocking wait/join, background reaper or joined
        // certificate. Explicit advance/finish owns those proofs.
        if !matches!(self.state, State::Consumed) {
            let _ = self.request_termination();
        }
    }
}

#[cfg(any(target_os = "linux", target_os = "macos"))]
fn observe_unreaped(child: &Child) -> io::Result<Option<ExitObservation>> {
    use rustix::process::{Pid, WaitId, WaitIdOptions, waitid};
    let raw = i32::try_from(child.id()).map_err(|_| io::ErrorKind::InvalidInput)?;
    let pid = Pid::from_raw(raw).ok_or(io::ErrorKind::InvalidInput)?;
    // No EINTR loop. The caller retains the same actual owner and may retry.
    let observed = waitid(
        WaitId::Pid(pid),
        WaitIdOptions::EXITED | WaitIdOptions::NOHANG | WaitIdOptions::NOWAIT,
    )?;
    observed
        .map(|status| {
            if let Some(code) = status.exit_status() {
                Ok(ExitObservation(ExitKind::Code(code)))
            } else if let Some(signal) = status.terminating_signal() {
                Ok(ExitObservation(ExitKind::Signal(signal)))
            } else {
                Err(io::ErrorKind::InvalidData.into())
            }
        })
        .transpose()
}

#[cfg(windows)]
fn poll_job_child(active: &mut ActiveProcess) {
    if matches!(active.lifetime, ChildLifetime::JobRunning) {
        match active.child.try_wait() {
            Ok(Some(status)) => {
                let observed = ExitObservation(match status.code() {
                    Some(code) => ExitKind::Code(code),
                    None => ExitKind::OtherStatus,
                });
                active.lifetime = ChildLifetime::Reaped { status, observed };
            }
            Ok(None) => {}
            Err(error) => record(&active.faults, ProcessFault::ChildWait(error.kind())),
        }
    }
}
