//! Actual create-only output observations. Authenticated archive descriptors are
//! DATA; only the actual held output and its readback establish these facts.
use super::super::source_inputs::{
    RuntimeArchiveFile, RuntimeArchiveReadFault, RuntimePackageDimensions, RuntimePackageFile,
};
use super::*;
use std::os::fd::{AsRawFd, IntoRawFd};
const PATH_BYTES: usize = 72;
unsafe extern "C" {
    #[link_name = "close"]
    fn close_descriptor(fd: std::ffi::c_int) -> std::ffi::c_int;
}
#[derive(Debug)]
pub(super) enum RuntimeSinkFault {
    Acquisition(ControllerAcquisitionFault),
    Read(RuntimeArchiveReadFault),
    Identity,
    Capacity,
    Length { declared: u64, actual: u64 },
    Digest,
    Order,
}
impl From<ControllerAcquisitionFault> for RuntimeSinkFault {
    fn from(f: ControllerAcquisitionFault) -> Self {
        Self::Acquisition(f)
    }
}
#[derive(Debug)]
pub(super) enum RuntimeClose {
    NotAttempted,
    Returned,
    Failed(io::Error),
    HandlesReleasedUnverified,
}
#[derive(Clone, Copy)]
enum OutputObservation {
    Opened,
    Identified(Identity),
    Written(Identity),
    ReadEof {
        identity: Identity,
        digest: [u8; 32],
    },
    Verified {
        identity: Identity,
        digest: [u8; 32],
    },
}
struct HeldOutput {
    file: File,
    observation: OutputObservation,
}
enum OutputOwnership {
    Held(HeldOutput),
    Released {
        observation: OutputObservation,
        close: RuntimeClose,
    },
    Moved {
        observation: OutputObservation,
    },
}
struct OutputRecord {
    name: [u8; PATH_BYTES],
    length: usize,
    declared: u64,
    written: u64,
    readback: u64,
    ownership: OutputOwnership,
}
struct DirectoryRecord {
    name: [u8; PATH_BYTES],
    length: usize,
    file: Option<File>,
    identity: Option<Identity>,
}
/// All vectors, scratch and per-entry work are paid before residual cleanup.
/// The fixed selected inventory bounds these capacities; they are not grants.
pub(super) struct RuntimeSink {
    directories: Vec<DirectoryRecord>,
    outputs: Vec<OutputRecord>,
    scratch: Vec<u8>,
    directory_bound: usize,
    file_bound: usize,
}
impl RuntimeSink {
    pub(super) fn empty() -> Self {
        Self {
            directories: Vec::new(),
            outputs: Vec::new(),
            scratch: Vec::new(),
            directory_bound: 0,
            file_bound: 0,
        }
    }
    pub(super) fn prepare(
        &mut self,
        d: RuntimePackageDimensions,
        lifetime: &SourceControllerLifetime,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<(), RuntimeSinkFault> {
        lifetime
            .validate(loans)
            .map_err(ControllerAcquisitionFault::Input)?;
        let directories = checked_add(d.component_count(), 1)?;
        let files = d.file_count();
        let backing = checked_add(
            checked_add(
                directories
                    .checked_mul(size_of::<DirectoryRecord>())
                    .ok_or(ControllerAcquisitionFault::Overflow)?,
                files
                    .checked_mul(size_of::<OutputRecord>())
                    .ok_or(ControllerAcquisitionFault::Overflow)?,
            )?,
            65536 + size_of::<Self>() + size_of::<Sha256>(),
        )?;
        // Count every possible partial byte write/read, copy/hash pass, EOF and
        // bounded parent-name/metadata walk. No OS allocator/VM claim is made.
        let bytes = usize::try_from(d.total_file_bytes())
            .map_err(|_| ControllerAcquisitionFault::Overflow)?;
        let names = directories
            .checked_mul(PATH_BYTES)
            .ok_or(ControllerAcquisitionFault::Overflow)?;
        let work = checked_add(
            backing,
            checked_add(
                bytes
                    .checked_mul(8)
                    .ok_or(ControllerAcquisitionFault::Overflow)?,
                checked_add(
                    names
                        .checked_mul(checked_add(directories, 8)?)
                        .ok_or(ControllerAcquisitionFault::Overflow)?,
                    directories
                        .checked_mul(8 * size_of::<fs::Metadata>())
                        .ok_or(ControllerAcquisitionFault::Overflow)?,
                )?,
            )?,
        )?;
        let windows = checked_add(file_windows(bytes)?, files)?;
        let guard_calls = checked_add(
            8,
            checked_add(
                directories
                    .checked_mul(4)
                    .ok_or(ControllerAcquisitionFault::Overflow)?,
                checked_add(
                    files
                        .checked_mul(4)
                        .ok_or(ControllerAcquisitionFault::Overflow)?,
                    windows
                        .checked_mul(3)
                        .ok_or(ControllerAcquisitionFault::Overflow)?,
                )?,
            )?,
        )?;
        let partial_calls = checked_add(bytes, files)?
            .checked_mul(2)
            .ok_or(ControllerAcquisitionFault::Overflow)?;
        let work = checked_add(
            work,
            checked_add(
                guard_calls
                    .checked_mul(file_guard_work()?)
                    .ok_or(ControllerAcquisitionFault::Overflow)?,
                partial_calls
                    .checked_mul(file_partial_work()?)
                    .ok_or(ControllerAcquisitionFault::Overflow)?,
            )?,
        )?;
        #[cfg(test)]
        eprintln!(
            "source runtime sink work: guards={guard_calls},guard_bytes={},partials={partial_calls},partial_bytes={},total={work}",
            file_guard_work()?,
            file_partial_work()?
        );
        loans
            .reserve_controlled_host_storage(backing, checked_add(directories, files)?, work)
            .map_err(ControllerAcquisitionFault::Input)?;
        active(lifetime, || {
            self.directories
                .try_reserve_exact(directories)
                .map_err(|_| ControllerAcquisitionFault::Allocation)?;
            Ok(())
        })?;
        active(lifetime, || {
            self.outputs
                .try_reserve_exact(files)
                .map_err(|_| ControllerAcquisitionFault::Allocation)?;
            Ok(())
        })?;
        active(lifetime, || {
            self.scratch
                .try_reserve_exact(65536)
                .map_err(|_| ControllerAcquisitionFault::Allocation)?;
            Ok(())
        })?;
        let extra = checked_add(
            self.directories
                .capacity()
                .saturating_sub(directories)
                .checked_mul(size_of::<DirectoryRecord>())
                .ok_or(ControllerAcquisitionFault::Overflow)?,
            checked_add(
                self.outputs
                    .capacity()
                    .saturating_sub(files)
                    .checked_mul(size_of::<OutputRecord>())
                    .ok_or(ControllerAcquisitionFault::Overflow)?,
                self.scratch.capacity().saturating_sub(65536),
            )?,
        )?;
        loans
            .reserve_controlled_host_storage(extra, 0, 0)
            .map_err(ControllerAcquisitionFault::Input)?;
        active(lifetime, || {
            self.scratch.resize(65536, 0);
            Ok(())
        })?;
        self.directory_bound = directories;
        self.file_bound = files;
        Ok(())
    }
    pub(super) fn start(
        &mut self,
        artifacts: &File,
        lifetime: &SourceControllerLifetime,
    ) -> Result<(), RuntimeSinkFault> {
        if !self.directories.is_empty() || self.directory_bound == 0 {
            return Err(RuntimeSinkFault::Order);
        }
        self.new_directory(artifacts, b"runtime", b"", lifetime)?;
        Ok(())
    }
    fn new_directory(
        &mut self,
        parent: &File,
        name: &[u8],
        full: &[u8],
        lifetime: &SourceControllerLifetime,
    ) -> Result<usize, RuntimeSinkFault> {
        use rustix::fs::{Mode, OFlags, mkdirat, openat};
        if self.directories.len() >= self.directory_bound || full.len() > PATH_BYTES {
            return Err(RuntimeSinkFault::Capacity);
        }
        let mut nul = [0u8; PATH_BYTES + 1];
        nul[..name.len()].copy_from_slice(name);
        let c = std::ffi::CStr::from_bytes_with_nul(&nul[..name.len() + 1])
            .map_err(|_| RuntimeSinkFault::Identity)?;
        active(lifetime, || {
            mkdirat(parent, c, Mode::RUSR | Mode::WUSR | Mode::XUSR).map_err(os)
        })?;
        // Record actual creation before the fallible open/metadata observations.
        let index = self.directories.len();
        let mut held = [0; PATH_BYTES];
        held[..full.len()].copy_from_slice(full);
        self.directories.push(DirectoryRecord {
            name: held,
            length: full.len(),
            file: None,
            identity: None,
        });
        let file = active(lifetime, || {
            openat(
                parent,
                c,
                OFlags::RDONLY | OFlags::DIRECTORY | OFlags::NOFOLLOW | OFlags::CLOEXEC,
                Mode::empty(),
            )
            .map(File::from)
            .map_err(os)
        })?;
        self.directories[index].file = Some(file);
        let metadata = active(lifetime, || {
            self.directories[index]
                .file
                .as_ref()
                .unwrap()
                .metadata()
                .map_err(|e| ControllerAcquisitionFault::Io(e.kind()))
        })?;
        if !metadata.is_dir() {
            return Err(RuntimeSinkFault::Identity);
        }
        self.directories[index].identity = Some(Identity::from(&metadata));
        Ok(index)
    }
    fn check_directory(
        &self,
        parent: &File,
        name: &[u8],
        index: usize,
        lifetime: &SourceControllerLifetime,
    ) -> Result<(), RuntimeSinkFault> {
        let mut nul = [0u8; PATH_BYTES + 1];
        nul[..name.len()].copy_from_slice(name);
        let c = std::ffi::CStr::from_bytes_with_nul(&nul[..name.len() + 1])
            .map_err(|_| RuntimeSinkFault::Identity)?;
        let now = active(lifetime, || {
            rustix::fs::statat(parent, c, rustix::fs::AtFlags::SYMLINK_NOFOLLOW).map_err(os)
        })?;
        let held = self.directories[index]
            .identity
            .ok_or(RuntimeSinkFault::Identity)?;
        if now.st_dev as u64 != held.dev
            || now.st_ino as u64 != held.ino
            || now.st_mode & 0o170000 != 0o040000
        {
            return Err(RuntimeSinkFault::Identity);
        }
        Ok(())
    }
    fn parent(
        &mut self,
        path: &[u8],
        lifetime: &SourceControllerLifetime,
    ) -> Result<usize, RuntimeSinkFault> {
        if self.directories.is_empty() {
            return Err(RuntimeSinkFault::Order);
        }
        let mut parent = 0;
        let mut start = 0;
        for end in path
            .iter()
            .enumerate()
            .filter_map(|(i, b)| (*b == b'/').then_some(i))
        {
            let prefix = &path[..end];
            let name = &path[start..end];
            let found = self
                .directories
                .iter()
                .position(|d| d.length == prefix.len() && &d.name[..d.length] == prefix);
            if let Some(index) = found {
                self.check_directory(
                    self.directories[parent]
                        .file
                        .as_ref()
                        .ok_or(RuntimeSinkFault::Identity)?,
                    name,
                    index,
                    lifetime,
                )?;
                parent = index;
            } else {
                // Borrow just the actual held FD, avoiding a duplicate OS owner.
                let fd = self.directories[parent]
                    .file
                    .as_ref()
                    .ok_or(RuntimeSinkFault::Identity)?
                    .as_raw_fd();
                let borrowed = unsafe { std::os::fd::BorrowedFd::borrow_raw(fd) };
                parent = self.new_directory_fd(borrowed, name, prefix, lifetime)?;
            }
            start = end + 1;
        }
        Ok(parent)
    }
    fn new_directory_fd(
        &mut self,
        parent: std::os::fd::BorrowedFd<'_>,
        name: &[u8],
        full: &[u8],
        lifetime: &SourceControllerLifetime,
    ) -> Result<usize, RuntimeSinkFault> {
        // Same held parent; this borrowed view never closes or duplicates it.
        use rustix::fs::{Mode, OFlags, mkdirat, openat};
        if self.directories.len() >= self.directory_bound || full.len() > PATH_BYTES {
            return Err(RuntimeSinkFault::Capacity);
        }
        let mut nul = [0u8; PATH_BYTES + 1];
        nul[..name.len()].copy_from_slice(name);
        let c = std::ffi::CStr::from_bytes_with_nul(&nul[..name.len() + 1])
            .map_err(|_| RuntimeSinkFault::Identity)?;
        active(lifetime, || {
            mkdirat(parent, c, Mode::RUSR | Mode::WUSR | Mode::XUSR).map_err(os)
        })?;
        let i = self.directories.len();
        let mut held = [0; PATH_BYTES];
        held[..full.len()].copy_from_slice(full);
        self.directories.push(DirectoryRecord {
            name: held,
            length: full.len(),
            file: None,
            identity: None,
        });
        let file = active(lifetime, || {
            openat(
                parent,
                c,
                OFlags::RDONLY | OFlags::DIRECTORY | OFlags::NOFOLLOW | OFlags::CLOEXEC,
                Mode::empty(),
            )
            .map(File::from)
            .map_err(os)
        })?;
        self.directories[i].file = Some(file);
        let m = active(lifetime, || {
            self.directories[i]
                .file
                .as_ref()
                .unwrap()
                .metadata()
                .map_err(|e| ControllerAcquisitionFault::Io(e.kind()))
        })?;
        if !m.is_dir() {
            return Err(RuntimeSinkFault::Identity);
        }
        self.directories[i].identity = Some(Identity::from(&m));
        Ok(i)
    }
    pub(super) fn write_entry(
        &mut self,
        descriptor: RuntimePackageFile<'_>,
        source: &mut RuntimeArchiveFile<'_, '_, '_>,
        lifetime: &SourceControllerLifetime,
    ) -> Result<(), RuntimeSinkFault> {
        use rustix::fs::{Mode, OFlags, openat};
        if self.outputs.len() >= self.file_bound || descriptor.path().len() > PATH_BYTES {
            return Err(RuntimeSinkFault::Capacity);
        }
        let path = descriptor.path().as_bytes();
        let parent = self.parent(path, lifetime)?;
        let leaf = path
            .rsplit(|b| *b == b'/')
            .next()
            .ok_or(RuntimeSinkFault::Identity)?;
        let mut nul = [0u8; PATH_BYTES + 1];
        nul[..leaf.len()].copy_from_slice(leaf);
        let name = std::ffi::CStr::from_bytes_with_nul(&nul[..leaf.len() + 1])
            .map_err(|_| RuntimeSinkFault::Identity)?;
        let mode = if descriptor.mode().unix_mode() & 0o111 != 0 {
            Mode::RUSR | Mode::WUSR | Mode::XUSR
        } else {
            Mode::RUSR | Mode::WUSR
        };
        let file = active(lifetime, || {
            openat(
                self.directories[parent]
                    .file
                    .as_ref()
                    .ok_or(ControllerAcquisitionFault::Shape)?,
                name,
                OFlags::RDWR | OFlags::CREATE | OFlags::EXCL | OFlags::NOFOLLOW | OFlags::CLOEXEC,
                mode,
            )
            .map(File::from)
            .map_err(os)
        })?;
        let mut held = [0; PATH_BYTES];
        held[..path.len()].copy_from_slice(path);
        self.outputs.push(OutputRecord {
            name: held,
            length: path.len(),
            declared: descriptor.byte_length(),
            written: 0,
            readback: 0,
            ownership: OutputOwnership::Held(HeldOutput {
                file,
                observation: OutputObservation::Opened,
            }),
        });
        let record = self.outputs.last_mut().unwrap();
        let OutputOwnership::Held(output) = &mut record.ownership else {
            return Err(RuntimeSinkFault::Order);
        };
        let m = active(lifetime, || {
            output
                .file
                .metadata()
                .map_err(|e| ControllerAcquisitionFault::Io(e.kind()))
        })?;
        if !m.is_file() || m.len() != 0 {
            return Err(RuntimeSinkFault::Identity);
        }
        let identity = Identity::from(&m);
        output.observation = OutputObservation::Identified(identity);
        while let Some(chunk) = source.next_chunk().map_err(RuntimeSinkFault::Read)? {
            active(lifetime, || {
                let mut done = 0;
                while done < chunk.len() {
                    check_file_end(lifetime)?;
                    let n = output
                        .file
                        .write_at(&chunk[done..], record.written)
                        .map_err(|e| ControllerAcquisitionFault::Io(e.kind()))?;
                    record.written += n as u64;
                    done += n;
                    if n == 0 {
                        return Err(ControllerAcquisitionFault::Io(io::ErrorKind::WriteZero));
                    }
                }
                Ok(())
            })?;
        }
        if record.written != record.declared {
            return Err(RuntimeSinkFault::Length {
                declared: record.declared,
                actual: record.written,
            });
        }
        output.observation = OutputObservation::Written(identity);
        let m = active(lifetime, || {
            output
                .file
                .metadata()
                .map_err(|e| ControllerAcquisitionFault::Io(e.kind()))
        })?;
        if m.dev() != identity.dev
            || m.ino() != identity.ino
            || !m.is_file()
            || m.len() != record.declared
        {
            return Err(RuntimeSinkFault::Identity);
        }
        let mut digest = Sha256::new();
        while record.readback < record.declared {
            let request =
                usize::try_from((record.declared - record.readback).min(self.scratch.len() as u64))
                    .map_err(|_| ControllerAcquisitionFault::Overflow)?;
            let n = active(lifetime, || {
                let mut filled = 0;
                while filled < request {
                    check_file_end(lifetime)?;
                    let n = output
                        .file
                        .read_at(&mut self.scratch[filled..request], record.readback)
                        .map_err(|e| ControllerAcquisitionFault::Io(e.kind()))?;
                    record.readback += n as u64;
                    filled += n;
                    if n == 0 {
                        return Err(ControllerAcquisitionFault::Length {
                            declared: record.declared,
                            actual: record.readback,
                        });
                    }
                }
                Ok(filled)
            })?;
            active(lifetime, || {
                digest.update(&self.scratch[..n]);
                Ok(())
            })?;
        }
        let eof = active(lifetime, || {
            output
                .file
                .read_at(&mut self.scratch[..1], record.readback)
                .map_err(|e| ControllerAcquisitionFault::Io(e.kind()))
        })?;
        if eof != 0 {
            record.readback += eof as u64;
            return Err(RuntimeSinkFault::Length {
                declared: record.declared,
                actual: record.readback,
            });
        }
        let actual: [u8; 32] = digest.finalize().into();
        output.observation = OutputObservation::ReadEof {
            identity,
            digest: actual,
        };
        if &actual != descriptor.sha256() {
            return Err(RuntimeSinkFault::Digest);
        }
        output.observation = OutputObservation::Verified {
            identity,
            digest: actual,
        };
        // Keep actual core/entry FDs for target transfer; all other close results
        // are actual OS observations, independent of successful readback.
        if !matches!(descriptor.path(), "index.mjs" | "lib/coreBundle.js") {
            let placeholder = OutputOwnership::Released {
                observation: output.observation,
                close: RuntimeClose::NotAttempted,
            };
            let OutputOwnership::Held(output) =
                std::mem::replace(&mut record.ownership, placeholder)
            else {
                unreachable!()
            };
            let raw = output.file.into_raw_fd();
            let close = if unsafe { close_descriptor(raw) } == 0 {
                RuntimeClose::Returned
            } else {
                RuntimeClose::Failed(io::Error::last_os_error())
            };
            let failure = match &close {
                RuntimeClose::Failed(error) => Some(error.kind()),
                _ => None,
            };
            record.ownership = OutputOwnership::Released {
                observation: output.observation,
                close,
            };
            if let Some(kind) = failure {
                return Err(ControllerAcquisitionFault::Io(kind).into());
            }
        }
        Ok(())
    }
    pub(super) fn completed_files(&self) -> usize {
        self.outputs
            .iter()
            .filter(|r| {
                matches!(
                    match &r.ownership {
                        OutputOwnership::Held(o) => o.observation,
                        OutputOwnership::Released { observation, .. }
                        | OutputOwnership::Moved { observation } => *observation,
                    },
                    OutputObservation::Verified { .. }
                )
            })
            .count()
    }
    pub(super) fn observed_eofs(&self) -> usize {
        self.outputs
            .iter()
            .filter(|r| {
                matches!(
                    match &r.ownership {
                        OutputOwnership::Held(o) => o.observation,
                        OutputOwnership::Released { observation, .. }
                        | OutputOwnership::Moved { observation } => *observation,
                    },
                    OutputObservation::ReadEof { .. } | OutputObservation::Verified { .. }
                )
            })
            .count()
    }
    pub(super) fn verified_digest(&self, path: &str) -> Option<[u8; 32]> {
        let r = self
            .outputs
            .iter()
            .find(|r| &r.name[..r.length] == path.as_bytes())?;
        let observation = match &r.ownership {
            OutputOwnership::Held(o) => o.observation,
            OutputOwnership::Released { observation, .. }
            | OutputOwnership::Moved { observation } => *observation,
        };
        if let OutputObservation::Verified { digest, .. } = observation {
            Some(digest)
        } else {
            None
        }
    }
    pub(super) fn disposal_uncertain(&self) -> bool {
        self.outputs.iter().any(|r| {
            matches!(
                r.ownership,
                OutputOwnership::Released {
                    close: RuntimeClose::Failed(_),
                    ..
                }
            )
        })
    }
    pub(super) fn take_verified(&mut self, path: &str) -> Result<File, RuntimeSinkFault> {
        let record = self
            .outputs
            .iter_mut()
            .find(|r| &r.name[..r.length] == path.as_bytes())
            .ok_or(RuntimeSinkFault::Order)?;
        let OutputOwnership::Held(output) = &record.ownership else {
            return Err(RuntimeSinkFault::Order);
        };
        let OutputObservation::Verified { .. } = output.observation else {
            return Err(RuntimeSinkFault::Order);
        };
        let replacement = OutputOwnership::Moved {
            observation: output.observation,
        };
        let OutputOwnership::Held(output) = std::mem::replace(&mut record.ownership, replacement)
        else {
            unreachable!()
        };
        Ok(output.file)
    }
    pub(super) fn release_handles(&mut self) -> usize {
        let mut released = 0;
        for directory in &mut self.directories {
            if let Some(file) = directory.file.take() {
                drop(file);
                released += 1;
            }
        }
        for record in &mut self.outputs {
            if let OutputOwnership::Held(output) = &record.ownership {
                let replacement = OutputOwnership::Released {
                    observation: output.observation,
                    close: RuntimeClose::HandlesReleasedUnverified,
                };
                let OutputOwnership::Held(output) =
                    std::mem::replace(&mut record.ownership, replacement)
                else {
                    unreachable!()
                };
                drop(output.file);
                released += 1;
            }
        }
        released
    }
    pub(super) fn held_files(&self) -> usize {
        self.directories.iter().filter(|d| d.file.is_some()).count()
            + self
                .outputs
                .iter()
                .filter(|r| matches!(r.ownership, OutputOwnership::Held(_)))
                .count()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum RuntimeOutputStage {
    Opened,
    Identified,
    Written,
    ReadEof,
    Verified,
}
pub(super) enum RuntimeOutputDisposal<'a> {
    Held,
    Transferred,
    Released(&'a RuntimeClose),
}
pub(super) struct RuntimeOutputView<'a>(&'a OutputRecord);
impl RuntimeOutputView<'_> {
    pub(super) fn path(&self) -> &str {
        std::str::from_utf8(&self.0.name[..self.0.length]).expect("selected ASCII path")
    }
    pub(super) fn declared_length(&self) -> u64 {
        self.0.declared
    }
    pub(super) fn written_bytes(&self) -> u64 {
        self.0.written
    }
    pub(super) fn readback_bytes(&self) -> u64 {
        self.0.readback
    }
    pub(super) fn stage(&self) -> RuntimeOutputStage {
        let observation = match &self.0.ownership {
            OutputOwnership::Held(output) => output.observation,
            OutputOwnership::Released { observation, .. }
            | OutputOwnership::Moved { observation } => *observation,
        };
        match observation {
            OutputObservation::Opened => RuntimeOutputStage::Opened,
            OutputObservation::Identified(_) => RuntimeOutputStage::Identified,
            OutputObservation::Written(_) => RuntimeOutputStage::Written,
            OutputObservation::ReadEof { .. } => RuntimeOutputStage::ReadEof,
            OutputObservation::Verified { .. } => RuntimeOutputStage::Verified,
        }
    }
    pub(super) fn disposal(&self) -> RuntimeOutputDisposal<'_> {
        match &self.0.ownership {
            OutputOwnership::Held(_) => RuntimeOutputDisposal::Held,
            OutputOwnership::Moved { .. } => RuntimeOutputDisposal::Transferred,
            OutputOwnership::Released { close, .. } => RuntimeOutputDisposal::Released(close),
        }
    }
}
impl RuntimeSink {
    pub(super) fn outputs(&self) -> impl ExactSizeIterator<Item = RuntimeOutputView<'_>> {
        self.outputs.iter().map(RuntimeOutputView)
    }
}
