//! Direct physical roots and fixed attach-only control. This is not BrowserRun,
//! a source grant, or complete profile metadata/storage/work preparation.
use super::super::clock;
use crate::transport::{
    Limits,
    process::{
        CommandSpec, OneShotProcess, ProcessFinish, ProcessOutcome, ProcessProgress, ReadTerminal,
        interactive::{
            FixedCaptureBuffers, InteractiveFinish, InteractiveOutcome, InteractiveProcess,
            InteractiveProgress, InteractiveWrite,
        },
    },
};
use sha2::{Digest, Sha256};
use std::{
    ffi::OsString,
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    os::{
        fd::AsFd,
        unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt},
    },
    path::{Path, PathBuf},
    sync::atomic::{AtomicBool, Ordering},
    time::Instant,
};
mod observed_launch;
pub(super) use observed_launch::ObservedLaunch;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum ControllerFault {
    Acquisition,
    Clock,
    Spawn,
    ChromiumExited,
    DriverExited,
    Process,
    Shape,
    Order,
    End,
    Cancelled,
    Input,
    Output,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum ControllerCommand {
    CreateProbePage,
    StartObservedDocument,
    ClosePageContextAndDisconnect,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum ControllerReply {
    Attached,
    ProbePageCreated,
    ObservedDocumentStarted,
    Disconnected,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum ControllerProgress {
    Pending,
    Reply(ControllerReply),
    DriverJoined,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum RootState {
    Running(u32),
    Finished,
}
pub(super) fn parse_reply(bytes: &[u8]) -> Result<ControllerReply, ControllerFault> {
    match bytes {
        b"attached\n" => Ok(ControllerReply::Attached),
        b"1 page-created\n" => Ok(ControllerReply::ProbePageCreated),
        b"1 document-started\n" => Ok(ControllerReply::ObservedDocumentStarted),
        b"2 disconnected\n" => Ok(ControllerReply::Disconnected),
        _ => Err(ControllerFault::Shape),
    }
}
struct Executable {
    path: PathBuf,
    held: File,
}
impl Executable {
    fn acquire(path: PathBuf) -> Result<Self, ControllerFault> {
        if !path.is_absolute() {
            return Err(ControllerFault::Acquisition);
        }
        let path = path
            .canonicalize()
            .map_err(|_| ControllerFault::Acquisition)?;
        let held = open_regular(&path)?;
        if held
            .metadata()
            .map_err(|_| ControllerFault::Acquisition)?
            .permissions()
            .mode()
            & 0o111
            == 0
        {
            return Err(ControllerFault::Acquisition);
        }
        Ok(Self { path, held })
    }
    fn validate(&self) -> Result<(), ControllerFault> {
        let held = self
            .held
            .metadata()
            .map_err(|_| ControllerFault::Acquisition)?;
        let now = fs::symlink_metadata(&self.path).map_err(|_| ControllerFault::Acquisition)?;
        if !now.is_file()
            || now.dev() != held.dev()
            || now.ino() != held.ino()
            || now.len() != held.len()
            || now.mtime() != held.mtime()
            || now.mtime_nsec() != held.mtime_nsec()
        {
            return Err(ControllerFault::Acquisition);
        }
        Ok(())
    }
}
fn open_regular(path: &Path) -> Result<File, ControllerFault> {
    let flags = i32::try_from((rustix::fs::OFlags::NOFOLLOW | rustix::fs::OFlags::NONBLOCK).bits())
        .map_err(|_| ControllerFault::Acquisition)?;
    let file = OpenOptions::new()
        .read(true)
        .custom_flags(flags)
        .open(path)
        .map_err(|_| ControllerFault::Acquisition)?;
    if !file
        .metadata()
        .map_err(|_| ControllerFault::Acquisition)?
        .is_file()
    {
        return Err(ControllerFault::Acquisition);
    }
    Ok(file)
}
fn hash(file: &File) -> Result<String, ControllerFault> {
    use std::os::unix::fs::FileExt;
    let mut hash = Sha256::new();
    let mut bytes = [0u8; 65536];
    let mut offset = 0;
    loop {
        let n = file
            .read_at(&mut bytes, offset)
            .map_err(|_| ControllerFault::Acquisition)?;
        if n == 0 {
            break;
        }
        hash.update(&bytes[..n]);
        offset += n as u64;
    }
    use std::fmt::Write as _;
    let mut hex = String::with_capacity(64);
    for byte in hash.finalize() {
        write!(&mut hex, "{byte:02x}").map_err(|_| ControllerFault::Acquisition)?;
    }
    Ok(hex)
}
/// Explicit physical inputs. Holding these files is not immutable path-exec
/// provenance or a source/policy grant. The caller owns their acquisition scope.
pub(super) struct AcquiredTarget {
    chromium: Executable,
    node: Executable,
    entry: PathBuf,
    _package: File,
    root: PathBuf,
    _root: File,
    profile: PathBuf,
    profile_dir: File,
    artifacts: PathBuf,
    driver: PathBuf,
}
impl AcquiredTarget {
    pub(super) fn acquire(
        chromium: PathBuf,
        node: PathBuf,
        package: PathBuf,
        root: PathBuf,
    ) -> Result<Self, ControllerFault> {
        let chromium = Executable::acquire(chromium)?;
        let node = Executable::acquire(node)?;
        // This exact binary's hrtime basis was independently qualified against
        // Darwin continuous time. Version text alone cannot select this basis.
        if hash(&node.held)? != "b468fb9c67427c9d3aec07ee1105e63020923a631a9a2a00beb71a7ba3768bfd" {
            return Err(ControllerFault::Clock);
        }
        if !package.is_absolute() || !root.is_absolute() {
            return Err(ControllerFault::Acquisition);
        }
        let package = package
            .canonicalize()
            .map_err(|_| ControllerFault::Acquisition)?;
        let pinned = open_regular(&package.join("lib/coreBundle.js"))?;
        if hash(&pinned)? != "829521b67ed7be90c7d6d6098ff39f2241562d47e4ad7ccab13710924a56001d" {
            return Err(ControllerFault::Acquisition);
        }
        let entry = package.join("index.mjs");
        let package_file = open_regular(&entry)?;
        let root = root
            .canonicalize()
            .map_err(|_| ControllerFault::Acquisition)?;
        let dirflags = rustix::fs::OFlags::RDONLY
            | rustix::fs::OFlags::DIRECTORY
            | rustix::fs::OFlags::NOFOLLOW
            | rustix::fs::OFlags::CLOEXEC;
        let root_file = File::from(
            rustix::fs::open(&root, dirflags, rustix::fs::Mode::empty())
                .map_err(|_| ControllerFault::Acquisition)?,
        );
        for name in ["profile", "artifacts"] {
            rustix::fs::mkdirat(
                &root_file,
                name,
                rustix::fs::Mode::RUSR | rustix::fs::Mode::WUSR | rustix::fs::Mode::XUSR,
            )
            .map_err(|_| ControllerFault::Acquisition)?;
        }
        let profile_dir = File::from(
            rustix::fs::openat(&root_file, "profile", dirflags, rustix::fs::Mode::empty())
                .map_err(|_| ControllerFault::Acquisition)?,
        );
        let driver = root.join("driver.mjs");
        let mut output = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&driver)
            .map_err(|_| ControllerFault::Acquisition)?;
        output
            .write_all(include_bytes!("controller/driver.js"))
            .map_err(|_| ControllerFault::Acquisition)?;
        Ok(Self {
            chromium,
            node,
            entry,
            _package: package_file,
            profile: root.join("profile"),
            artifacts: root.join("artifacts"),
            root,
            _root: root_file,
            profile_dir,
            driver,
        })
    }
    fn endpoint(&self, buffer: &mut [u8]) -> Result<Option<String>, ControllerFault> {
        let fd = match rustix::fs::openat(
            self.profile_dir.as_fd(),
            "DevToolsActivePort",
            rustix::fs::OFlags::RDONLY
                | rustix::fs::OFlags::NOFOLLOW
                | rustix::fs::OFlags::NONBLOCK
                | rustix::fs::OFlags::CLOEXEC,
            rustix::fs::Mode::empty(),
        ) {
            Ok(fd) => fd,
            Err(rustix::io::Errno::NOENT) => return Ok(None),
            Err(_) => return Err(ControllerFault::Acquisition),
        };
        let mut file = File::from(fd);
        if !file
            .metadata()
            .map_err(|_| ControllerFault::Acquisition)?
            .is_file()
        {
            return Err(ControllerFault::Shape);
        }
        let mut count = 0;
        loop {
            if count == buffer.len() {
                return Err(ControllerFault::Shape);
            }
            let n = file
                .read(&mut buffer[count..])
                .map_err(|_| ControllerFault::Acquisition)?;
            if n == 0 {
                break;
            }
            count += n;
        }
        let text = std::str::from_utf8(&buffer[..count]).map_err(|_| ControllerFault::Shape)?;
        let mut lines = text.lines();
        let Some(port) = lines.next() else {
            return Ok(None);
        };
        let Some(path) = lines.next() else {
            return Ok(None);
        };
        let port: u16 = port.parse().map_err(|_| ControllerFault::Shape)?;
        if port == 0 || !path.starts_with("/devtools/browser/") || lines.next().is_some() {
            return Err(ControllerFault::Shape);
        }
        let id = &path[18..];
        // A file write can be observed in progress. Do not launch from a
        // truncated browser UUID; the same fixed end bounds further polling.
        if id.len() < 36 {
            return Ok(None);
        }
        if id.len() != 36
            || !id.bytes().enumerate().all(|(at, b)| {
                if matches!(at, 8 | 13 | 18 | 23) {
                    b == b'-'
                } else {
                    b.is_ascii_hexdigit()
                }
            })
        {
            return Err(ControllerFault::Shape);
        }
        Ok(Some(format!("ws://127.0.0.1:{port}{path}")))
    }
}
enum Chromium {
    Running(OneShotProcess),
    Finished(ProcessOutcome),
    Moving,
}
enum Driver {
    NotStarted,
    Running(InteractiveProcess),
    Finished(InteractiveOutcome),
    Moving,
}
/// Selection of the maintained physical operation, never source authority.
enum ControllerVariant {
    Probe,
    Observed(ObservedLaunch),
}
impl ControllerVariant {
    fn accepts_start(&self, command: ControllerCommand) -> bool {
        matches!(
            (self, command),
            (Self::Probe, ControllerCommand::CreateProbePage)
                | (Self::Observed(_), ControllerCommand::StartObservedDocument)
        )
    }
    fn accepts_reply(&self, reply: ControllerReply) -> bool {
        matches!(
            (self, reply),
            (Self::Probe, ControllerReply::ProbePageCreated)
                | (Self::Observed(_), ControllerReply::ObservedDocumentStarted)
        )
    }
    fn start_frame(&self) -> &'static [u8] {
        match self {
            Self::Probe => b"1 page\n",
            Self::Observed(_) => b"1 start\n",
        }
    }
}
#[derive(Clone, Copy)]
enum Conversation {
    Launching,
    AttachedPending,
    Ready,
    SendingPage(usize),
    PagePending,
    PageReady,
    SendingClose(usize),
    ClosePending,
    Disconnected,
    Joined,
    Stopping,
}
pub(super) struct BrowserController {
    target: AcquiredTarget,
    variant: ControllerVariant,
    limits: Limits,
    end: Instant,
    clock: clock::deadline::DarwinContinuousDeadline,
    chromium: Chromium,
    driver: Driver,
    conversation: Conversation,
    first_fault: Option<ControllerFault>,
    capture: Vec<u8>,
    cursor: usize,
    frame_start: usize,
}
pub(super) struct ControllerOutcome(BrowserController);
pub(super) enum ControllerFinish {
    Pending(BrowserController),
    Finished(ControllerOutcome),
}
impl ControllerOutcome {
    pub(super) fn chromium(&self) -> &ProcessOutcome {
        let Chromium::Finished(value) = &self.0.chromium else {
            unreachable!("finished root")
        };
        value
    }
    pub(super) fn driver(&self) -> Option<&InteractiveOutcome> {
        match &self.0.driver {
            Driver::Finished(value) => Some(value),
            _ => None,
        }
    }
    pub(super) fn first_fault(&self) -> Option<&ControllerFault> {
        self.0.first_fault.as_ref()
    }
}
impl BrowserController {
    pub(super) fn launch(
        target: AcquiredTarget,
        limits: Limits,
        end: Instant,
    ) -> Result<Self, ControllerFault> {
        Self::launch_variant(target, limits, end, ControllerVariant::Probe)
    }
    pub(super) fn launch_observed(
        target: AcquiredTarget,
        limits: Limits,
        end: Instant,
        launch: ObservedLaunch,
    ) -> Result<Self, ControllerFault> {
        Self::launch_variant(target, limits, end, ControllerVariant::Observed(launch))
    }
    fn launch_variant(
        target: AcquiredTarget,
        limits: Limits,
        end: Instant,
        variant: ControllerVariant,
    ) -> Result<Self, ControllerFault> {
        if Instant::now() >= end || limits.max_frame == 0 {
            return Err(ControllerFault::End);
        }
        target.chromium.validate()?;
        target.node.validate()?;
        let (before, ticks, after, ratio) = clock::sample().map_err(|_| ControllerFault::Clock)?;
        let clock = clock::deadline::export(end, before, ticks, after, ratio)
            .map_err(|_| ControllerFault::Clock)?;
        let args = vec![
            OsString::from("--headless"),
            // This isolated disposable profile must not request the user's
            // macOS keychain. Match Playwright's normal test storage defaults.
            OsString::from("--password-store=basic"),
            OsString::from("--use-mock-keychain"),
            OsString::from("--remote-debugging-port=0"),
            {
                let mut arg = OsString::from("--user-data-dir=");
                arg.push(&target.profile);
                arg
            },
            OsString::from("--no-first-run"),
            OsString::from("--no-default-browser-check"),
            OsString::from("about:blank"),
        ];
        let spec = CommandSpec::new(
            target.chromium.path.clone(),
            args,
            target.root.clone(),
            vec![],
        )
        .map_err(|_| ControllerFault::Acquisition)?;
        let capture = vec![0; limits.max_frame];
        let chromium = OneShotProcess::spawn(spec, limits).map_err(|_| ControllerFault::Spawn)?;
        Ok(Self {
            target,
            variant,
            limits,
            end,
            clock,
            chromium: Chromium::Running(chromium),
            driver: Driver::NotStarted,
            conversation: Conversation::Launching,
            first_fault: None,
            capture,
            cursor: 0,
            frame_start: 0,
        })
    }
    fn fail(&mut self, fault: ControllerFault) -> ControllerFault {
        *self.first_fault.get_or_insert(fault)
    }
    pub(super) fn end(&self) -> Instant {
        self.end
    }
    pub(super) fn ids(&self) -> (Option<u32>, Option<u32>) {
        (
            match &self.chromium {
                Chromium::Running(p) => Some(p.id()),
                _ => None,
            },
            match &self.driver {
                Driver::Running(p) => Some(p.id()),
                _ => None,
            },
        )
    }
    pub(super) fn chromium_state(&self) -> RootState {
        match &self.chromium {
            Chromium::Running(p) => RootState::Running(p.id()),
            _ => RootState::Finished,
        }
    }
    pub(super) fn begin(&mut self, command: ControllerCommand) -> Result<(), ControllerFault> {
        if let Some(fault) = self.first_fault {
            return Err(fault);
        }
        if Instant::now() >= self.end {
            return Err(self.fail(ControllerFault::End));
        }
        self.conversation = match (self.conversation, command) {
            (Conversation::Ready, start) if self.variant.accepts_start(start) => {
                Conversation::SendingPage(0)
            }
            (Conversation::PageReady, ControllerCommand::ClosePageContextAndDisconnect) => {
                Conversation::SendingClose(0)
            }
            _ => return Err(self.fail(ControllerFault::Order)),
        };
        Ok(())
    }
    fn start_driver(&mut self, endpoint: String) -> Result<(), ControllerFault> {
        self.target.node.validate()?;
        let mut arguments = vec![
            self.target.driver.as_os_str().to_owned(),
            self.target.entry.as_os_str().to_owned(),
            endpoint.into(),
            self.target.artifacts.as_os_str().to_owned(),
            self.clock.calibrated_at_ns().to_string().into(),
            self.clock.end_ns().to_string().into(),
            self.clock.timebase().numerator().to_string().into(),
            self.clock.timebase().denominator().to_string().into(),
        ];
        if let ControllerVariant::Observed(launch) = &self.variant {
            arguments.push("observed-workbench".into());
            arguments.push(launch.as_str().into());
        }
        let spec = CommandSpec::new(
            self.target.node.path.clone(),
            arguments,
            self.target.root.clone(),
            vec![],
        )
        .map_err(|_| ControllerFault::Acquisition)?;
        let stdout = Vec::with_capacity(self.limits.max_frame);
        let stderr = Vec::with_capacity(self.limits.stderr_capture);
        let driver =
            InteractiveProcess::spawn(spec, self.limits, FixedCaptureBuffers::new(stdout, stderr))
                .map_err(|_| ControllerFault::Spawn)?;
        self.driver = Driver::Running(driver);
        self.conversation = Conversation::AttachedPending;
        Ok(())
    }
    fn advance_roots(&mut self) {
        if let Chromium::Running(owner) = &mut self.chromium {
            let stop = matches!(
                owner.advance(),
                ProcessProgress::ExitObserved(_) | ProcessProgress::Faulted(_)
            );
            if stop {
                let _ = owner.request_termination();
                let _ = owner.reap_retained();
                owner.advance();
            }
        }
        let root = std::mem::replace(&mut self.chromium, Chromium::Moving);
        self.chromium = match root {
            Chromium::Running(owner) => match owner.into_finished() {
                ProcessFinish::Pending(owner) => Chromium::Running(owner),
                ProcessFinish::Finished(outcome) => Chromium::Finished(outcome),
            },
            other => other,
        };
        if let Driver::Running(owner) = &mut self.driver {
            match owner.advance() {
                InteractiveProgress::ExitObserved(_) | InteractiveProgress::Faulted(_) => {
                    let _ = owner.request_termination();
                    let _ = owner.reap_retained();
                    owner.advance();
                }
                InteractiveProgress::Finished(_) => {
                    owner.close_stdin();
                }
                InteractiveProgress::Working => {}
            }
        }
        let driver = std::mem::replace(&mut self.driver, Driver::Moving);
        self.driver = match driver {
            Driver::Running(owner) => match owner.into_finished() {
                InteractiveFinish::Pending(owner) => Driver::Running(owner),
                InteractiveFinish::Finished(outcome) => Driver::Finished(outcome),
            },
            other => other,
        };
    }
    fn receive(&mut self) -> Result<Option<ControllerReply>, ControllerFault> {
        let count = match &self.driver {
            Driver::Running(owner) => owner
                .copy_stdout(self.cursor, &mut self.capture[self.cursor..])
                .map_err(|_| ControllerFault::Output)?,
            Driver::Finished(outcome) => {
                let bytes = outcome.process().stdout();
                if bytes.len() < self.cursor || bytes.len() > self.capture.len() {
                    return Err(ControllerFault::Output);
                }
                let count = bytes.len() - self.cursor;
                self.capture[self.cursor..self.cursor + count]
                    .copy_from_slice(&bytes[self.cursor..]);
                count
            }
            _ => 0,
        };
        let old = self.cursor;
        self.cursor += count;
        for index in old..self.cursor {
            if self.capture[index] == b'\n' {
                // Exactly one outstanding reply and no trailing buffered frame.
                if index + 1 != self.cursor {
                    return Err(ControllerFault::Shape);
                }
                let reply = parse_reply(&self.capture[self.frame_start..=index])?;
                self.frame_start = index + 1;
                self.conversation = match (self.conversation, reply) {
                    (Conversation::AttachedPending, ControllerReply::Attached) => {
                        Conversation::Ready
                    }
                    (Conversation::PagePending, started) if self.variant.accepts_reply(started) => {
                        Conversation::PageReady
                    }
                    (Conversation::ClosePending, ControllerReply::Disconnected) => {
                        if let Driver::Running(owner) = &mut self.driver {
                            owner.close_stdin();
                        }
                        Conversation::Disconnected
                    }
                    _ => return Err(ControllerFault::Order),
                };
                return Ok(Some(reply));
            }
        }
        if self.cursor == self.capture.len() {
            return Err(ControllerFault::Output);
        }
        Ok(None)
    }
    pub(super) fn poll(
        &mut self,
        interrupted: &AtomicBool,
    ) -> Result<ControllerProgress, ControllerFault> {
        if let Some(fault) = self.first_fault {
            return Err(fault);
        }
        if interrupted.load(Ordering::Acquire) {
            return Err(self.fail(ControllerFault::Cancelled));
        }
        if Instant::now() >= self.end {
            return Err(self.fail(ControllerFault::End));
        }
        self.advance_roots();
        if matches!(self.chromium, Chromium::Finished(_)) {
            return Err(self.fail(ControllerFault::ChromiumExited));
        }
        if matches!(self.conversation, Conversation::Launching) {
            match self.target.endpoint(&mut self.capture) {
                Ok(Some(endpoint)) => {
                    if let Err(fault) = self.start_driver(endpoint) {
                        return Err(self.fail(fault));
                    }
                }
                Ok(None) => return Ok(ControllerProgress::Pending),
                Err(fault) => return Err(self.fail(fault)),
            }
        }
        if let Driver::Running(owner) = &self.driver
            && owner.first_fault().is_some()
        {
            return Err(self.fail(ControllerFault::Process));
        }
        if let Driver::Finished(outcome) = &self.driver
            && outcome.first_fault().is_some()
        {
            return Err(self.fail(ControllerFault::Process));
        }
        let (frame, offset) = match self.conversation {
            Conversation::SendingPage(offset) => (Some(self.variant.start_frame()), offset),
            Conversation::SendingClose(offset) => (Some(b"2 close\n".as_slice()), offset),
            _ => (None, 0),
        };
        if let Some(frame) = frame {
            let result = match &mut self.driver {
                Driver::Running(owner) => owner.write_stdin(&frame[offset..]),
                _ => return Err(self.fail(ControllerFault::DriverExited)),
            };
            match result {
                Ok(InteractiveWrite::Pending) => {}
                Ok(InteractiveWrite::Written(count)) => {
                    let next = offset + count;
                    self.conversation = match self.conversation {
                        Conversation::SendingPage(_) => {
                            if next == frame.len() {
                                Conversation::PagePending
                            } else {
                                Conversation::SendingPage(next)
                            }
                        }
                        Conversation::SendingClose(_) => {
                            if next == frame.len() {
                                Conversation::ClosePending
                            } else {
                                Conversation::SendingClose(next)
                            }
                        }
                        _ => unreachable!(),
                    };
                }
                Err(_) => return Err(self.fail(ControllerFault::Input)),
            }
        }
        match self.receive() {
            Ok(Some(reply)) => return Ok(ControllerProgress::Reply(reply)),
            Err(fault) => return Err(self.fail(fault)),
            Ok(None) => {}
        }
        if let Driver::Finished(outcome) = &self.driver {
            if matches!(self.conversation, Conversation::Disconnected)
                && outcome.process().status().success()
                && matches!(outcome.stdout_terminal(), ReadTerminal::Eof)
                && self.cursor == self.frame_start
            {
                self.conversation = Conversation::Joined;
                return Ok(ControllerProgress::DriverJoined);
            }
            if !matches!(self.conversation, Conversation::Joined) {
                return Err(self.fail(ControllerFault::DriverExited));
            }
        }
        Ok(ControllerProgress::Pending)
    }
    pub(super) fn request_driver_termination(&mut self) {
        if let Driver::Running(owner) = &mut self.driver {
            owner.close_stdin();
            let _ = owner.request_termination();
        }
    }
    pub(super) fn request_shutdown(&mut self) {
        self.conversation = Conversation::Stopping;
        self.request_driver_termination();
        if let Chromium::Running(owner) = &mut self.chromium {
            let _ = owner.request_termination();
        }
    }
    pub(super) fn poll_cleanup(&mut self) -> bool {
        self.advance_roots();
        matches!(self.chromium, Chromium::Finished(_))
            && matches!(self.driver, Driver::NotStarted | Driver::Finished(_))
    }
    pub(super) fn into_finished(self) -> ControllerFinish {
        if matches!(self.chromium, Chromium::Finished(_))
            && matches!(self.driver, Driver::NotStarted | Driver::Finished(_))
        {
            ControllerFinish::Finished(ControllerOutcome(self))
        } else {
            ControllerFinish::Pending(self)
        }
    }
}

#[cfg(test)]
mod end_test {
    use super::*;
    use std::time::Duration;
    #[test]
    #[ignore = "requires explicit acquired inputs; actual driver expired-export control"]
    fn browser_controller_c05_actual_selected_driver_refuses_expired_cached_export() {
        let directory = tempfile::tempdir().unwrap();
        let target = AcquiredTarget::acquire(
            std::env::var_os("MORPHIR_MCK_BROWSER_CHROMIUM")
                .expect("explicit Chromium")
                .into(),
            std::env::var_os("MORPHIR_MCK_BROWSER_NODE")
                .expect("explicit Node")
                .into(),
            std::env::var_os("MORPHIR_MCK_BROWSER_PLAYWRIGHT")
                .expect("explicit package")
                .into(),
            directory.path().to_path_buf(),
        )
        .unwrap();
        let end = Instant::now() + Duration::from_millis(50);
        let (before, ticks, after, ratio) = clock::sample().unwrap();
        let export = clock::deadline::export(end, before, ticks, after, ratio).unwrap();
        // Real elapsed time, no controllable producer clock and no new window.
        std::thread::sleep(Duration::from_millis(70));
        let spec = CommandSpec::new(
            target.node.path.clone(),
            vec![
                target.driver.into_os_string(),
                target.entry.into_os_string(),
                "ws://127.0.0.1:1/devtools/browser/00000000-0000-0000-0000-000000000000".into(),
                target.artifacts.into_os_string(),
                export.calibrated_at_ns().to_string().into(),
                export.end_ns().to_string().into(),
                export.timebase().numerator().to_string().into(),
                export.timebase().denominator().to_string().into(),
            ],
            target.root,
            vec![],
        )
        .unwrap();
        let mut owner = OneShotProcess::spawn(spec, Limits::DEFAULT).unwrap();
        let cleanup_end = Instant::now() + Duration::from_secs(10);
        loop {
            match owner.advance() {
                ProcessProgress::ExitObserved(_) | ProcessProgress::Faulted(_) => {
                    let _ = owner.request_termination();
                    let _ = owner.reap_retained();
                }
                ProcessProgress::Finished(_) => break,
                ProcessProgress::Working => {
                    if Instant::now() >= cleanup_end {
                        let _ = owner.request_termination();
                    }
                }
            }
            std::thread::sleep(Duration::from_millis(1));
        }
        let ProcessFinish::Finished(outcome) = owner.into_finished() else {
            panic!("actual driver/readers not joined")
        };
        assert_eq!(outcome.status().code(), Some(1));
        assert!(outcome.first_fault().is_none());
        assert!(outcome.stdout().is_empty());
        assert!(
            std::str::from_utf8(outcome.stderr())
                .unwrap()
                .contains("Error: original end elapsed"),
            "must refuse for the real cached end before CDP attach, not socket refusal"
        );
    }
}
