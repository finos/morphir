//! Caller-buffer Darwin directory metadata, never file contents or symlink
//! targets. Every fixed destination is paid before the first acquisition effect.
use super::*;
use std::os::fd::{AsRawFd, BorrowedFd};

// Darwin's public 64-bit-inode name representation permits MAXPATHLEN bytes
// including NUL. These are ABI dimensions, not an application cleanup quota.
const NAME_BYTES: usize = 1024;
const RECORD_HEADER: usize = 44;
const SCRATCH_BYTES: usize = (RECORD_HEADER + NAME_BYTES + 3) & !3;
const ATTRS: u32 = 0x80000000 | 0x02000000 | 0x00000008 | 0x00000001;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) enum CleanupFault {
    Capacity,
    Record,
    Identity,
    Unsupported,
    Io(io::ErrorKind),
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) enum Kind {
    File,
    Directory,
    Symlink,
    Socket,
    Fifo,
}
impl Kind {
    fn vnode(value: u32) -> Option<Self> {
        match value {
            1 => Some(Self::File),
            2 => Some(Self::Directory),
            5 => Some(Self::Symlink),
            6 => Some(Self::Socket),
            7 => Some(Self::Fifo),
            _ => None,
        }
    }
    fn mode(value: u32) -> Option<Self> {
        match value & 0o170000 {
            0o100000 => Some(Self::File),
            0o040000 => Some(Self::Directory),
            0o120000 => Some(Self::Symlink),
            0o140000 => Some(Self::Socket),
            0o010000 => Some(Self::Fifo),
            _ => None,
        }
    }
}
struct NameRecord<'a> {
    name: &'a [u8],
    terminated: &'a std::ffi::CStr,
    inode: u64,
    kind: Kind,
    span: usize,
}
fn read<const N: usize>(bytes: &[u8], at: usize) -> Result<[u8; N], CleanupFault> {
    bytes
        .get(at..at.checked_add(N).ok_or(CleanupFault::Record)?)
        .ok_or(CleanupFault::Record)?
        .try_into()
        .map_err(|_| CleanupFault::Record)
}
fn decode(bytes: &[u8]) -> Result<NameRecord<'_>, CleanupFault> {
    let span = u32::from_ne_bytes(read(bytes, 0)?) as usize;
    if span < RECORD_HEADER || span % 4 != 0 || span > bytes.len() {
        return Err(CleanupFault::Record);
    }
    let record = &bytes[..span];
    if u32::from_ne_bytes(read(record, 4)?) != ATTRS || record[8..24].iter().any(|byte| *byte != 0)
    {
        return Err(CleanupFault::Record);
    }
    let offset = i32::from_ne_bytes(read(record, 24)?);
    let length = u32::from_ne_bytes(read(record, 28)?) as usize;
    let start = 24usize
        .checked_add_signed(offset as isize)
        .ok_or(CleanupFault::Record)?;
    if start < RECORD_HEADER || length < 2 || length > NAME_BYTES {
        return Err(CleanupFault::Record);
    }
    let end = start.checked_add(length).ok_or(CleanupFault::Record)?;
    let name = record.get(start..end).ok_or(CleanupFault::Record)?;
    if name.last() != Some(&0) {
        return Err(CleanupFault::Record);
    }
    let terminated = std::ffi::CStr::from_bytes_with_nul(name).map_err(|_| CleanupFault::Record)?;
    let name = &name[..name.len() - 1];
    if name.contains(&0) || name.contains(&b'/') || name == b"." || name == b".." {
        return Err(CleanupFault::Record);
    }
    let kind = Kind::vnode(u32::from_ne_bytes(read(record, 32)?)).ok_or(CleanupFault::Record)?;
    let inode = u64::from_ne_bytes(read(record, 36)?);
    if inode == 0 {
        return Err(CleanupFault::Record);
    }
    Ok(NameRecord {
        name,
        terminated,
        inode,
        kind,
        span,
    })
}
#[repr(C)]
struct AttrList {
    bitmap_count: u16,
    reserved: u16,
    common: u32,
    volume: u32,
    directory: u32,
    file: u32,
    fork: u32,
}
#[cfg(target_os = "macos")]
unsafe extern "C" {
    fn getattrlistbulk(
        fd: std::ffi::c_int,
        attributes: *mut AttrList,
        buffer: *mut std::ffi::c_void,
        size: usize,
        options: u64,
    ) -> std::ffi::c_int;
}
#[cfg(target_os = "macos")]
fn bulk(fd: BorrowedFd<'_>, scratch: &mut [u8]) -> Result<usize, CleanupFault> {
    let mut attrs = AttrList {
        bitmap_count: 5,
        reserved: 0,
        common: ATTRS,
        volume: 0,
        directory: 0,
        file: 0,
        fork: 0,
    };
    scratch.fill(0);
    // Public Darwin API: initialized caller storage, exact byte dimension, and
    // stack-owned repr(C) attribute selector live throughout this synchronous call.
    let count = unsafe {
        getattrlistbulk(
            fd.as_raw_fd(),
            &mut attrs,
            scratch.as_mut_ptr().cast(),
            scratch.len(),
            0,
        )
    };
    if count < 0 {
        return Err(CleanupFault::Io(io::Error::last_os_error().kind()));
    }
    Ok(count as usize)
}
#[cfg(not(target_os = "macos"))]
fn bulk(_fd: BorrowedFd<'_>, _scratch: &mut [u8]) -> Result<usize, CleanupFault> {
    Err(CleanupFault::Unsupported)
}
#[derive(Clone, Copy)]
enum Parent {
    Root(usize),
    Entry(usize),
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) enum DirectoryOpen {
    NotAttempted,
    Returned { identity: CleanupIdentity },
    Failed(io::ErrorKind),
}
struct Descendant {
    parent: Parent,
    name: [u8; NAME_BYTES],
    name_len: usize,
    identity: Identity,
    kind: Kind,
    held: Option<File>,
    discovered: CleanupIdentity,
    opened: DirectoryOpen,
    checked: CleanupIdentity,
    unlink: CleanupUnlink,
}
impl Descendant {
    fn name(&self) -> &std::ffi::CStr {
        std::ffi::CStr::from_bytes_with_nul(&self.name[..self.name_len + 1])
            .expect("validated fixed name")
    }
}
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct CleanupPlan {
    records: Vec<Descendant>,
    scratch: Vec<u8>,
    capacity: usize,
    state: CleanupState,
    root_checks: [CleanupIdentity; 2],
    calls: usize,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) enum CleanupState {
    Ready,
    InProgress,
    Complete,
    Faulted(CleanupFault),
}
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct CleanupEntryView<'a> {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) name: &'a [u8],
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) inode: u64,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) kind: Kind,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) discovered:
        CleanupIdentity,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) opened: DirectoryOpen,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) identity:
        CleanupIdentity,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) unlink: CleanupUnlink,
}
impl CleanupPlan {
    pub(super) fn require_runtime_capacity(
        &self,
        dimensions: RuntimePackageDimensions,
    ) -> Result<(), ControllerAcquisitionFault> {
        // Every authenticated file and an upper bound for its parent components,
        // plus the private runtime directory. Repeated parents deliberately
        // overcount. The caller-root profile/artifacts/driver entries have their
        // separate fixed three-entry owner; they are not descendant records.
        let required = checked_add(
            checked_add(dimensions.component_count(), dimensions.file_count())?,
            1,
        )?;
        if self.capacity < required {
            return Err(ControllerAcquisitionFault::Cleanup(CleanupFault::Capacity));
        }
        Ok(())
    }
    #[cfg(test)]
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn capacity(
        &self,
    ) -> usize {
        self.capacity
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn first_fault(
        &self,
    ) -> Option<CleanupFault> {
        match self.state {
            CleanupState::Faulted(first) => Some(first),
            _ => None,
        }
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn record_count(
        &self,
    ) -> usize {
        self.records.len()
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn record(
        &self,
        index: usize,
    ) -> Option<CleanupEntryView<'_>> {
        self.records.get(index).map(|record| CleanupEntryView {
            name: &record.name[..record.name_len],
            inode: record.identity.ino,
            kind: record.kind,
            discovered: record.discovered,
            opened: record.opened,
            identity: record.checked,
            unlink: record.unlink,
        })
    }
    pub(super) fn prepare(
        lifetime: &SourceControllerLifetime,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<Self, ControllerAcquisitionFault> {
        let available = loans
            .remaining_cleanup_resources(lifetime)
            .map_err(ControllerAcquisitionFault::Input)?;
        let fixed_bytes = checked_add(size_of::<Self>(), SCRATCH_BYTES)?;
        // The residual query, two distinct allocation effects and scratch
        // initialization each traverse the SAME source/document relation.
        let fixed_work = checked_add(
            checked_add(fixed_bytes, 2 * SCRATCH_BYTES)?,
            file_guard_work()?
                .checked_mul(4)
                .ok_or(ControllerAcquisitionFault::Overflow)?,
        )?;
        let per_bytes = size_of::<Descendant>();
        // One initialized record/name; one metadata batch+validation; discovery,
        // held-directory and final identity observations; one final name visit.
        // At most one successful nonempty batch per entry and two root EOFs.
        let per_work = checked_add(
            per_bytes,
            checked_add(
                2 * SCRATCH_BYTES,
                checked_add(3 * size_of::<fs::Metadata>(), NAME_BYTES)?,
            )?,
        )?;
        let capacity = available.retained_bytes.saturating_sub(fixed_bytes) / per_bytes;
        let capacity = capacity
            .min(available.receiving_visits.saturating_sub(fixed_work) / per_work)
            .min(available.decode_visits.saturating_sub(fixed_work) / per_work)
            .min(available.decode_slots.saturating_sub(1));
        if capacity == 0 {
            return Err(ControllerAcquisitionFault::Cleanup(CleanupFault::Capacity));
        }
        let requested = checked_add(
            fixed_bytes,
            capacity
                .checked_mul(per_bytes)
                .ok_or(ControllerAcquisitionFault::Overflow)?,
        )?;
        let work = checked_add(
            fixed_work,
            capacity
                .checked_mul(per_work)
                .ok_or(ControllerAcquisitionFault::Overflow)?,
        )?;
        #[cfg(test)]
        eprintln!(
            "source cleanup plan: remaining_retained={},remaining_receiving_work={},remaining_decode_work={},fixed_bytes={fixed_bytes},entry_bytes={per_bytes},capacity={capacity},requested_bytes={requested},work={work}",
            available.retained_bytes, available.receiving_visits, available.decode_visits
        );
        loans
            .reserve_controlled_host_storage(requested, checked_add(capacity, 1)?, work)
            .map_err(ControllerAcquisitionFault::Input)?;
        let records = active(lifetime, || {
            let mut records = Vec::new();
            records
                .try_reserve_exact(capacity)
                .map_err(|_| ControllerAcquisitionFault::Allocation)?;
            Ok(records)
        })?;
        let mut scratch = active(lifetime, || {
            let mut scratch = Vec::new();
            scratch
                .try_reserve_exact(SCRATCH_BYTES)
                .map_err(|_| ControllerAcquisitionFault::Allocation)?;
            Ok(scratch)
        })?;
        let extra = checked_add(
            records
                .capacity()
                .checked_sub(capacity)
                .ok_or(ControllerAcquisitionFault::Overflow)?
                .checked_mul(per_bytes)
                .ok_or(ControllerAcquisitionFault::Overflow)?,
            scratch
                .capacity()
                .checked_sub(SCRATCH_BYTES)
                .ok_or(ControllerAcquisitionFault::Overflow)?,
        )?;
        loans
            .reserve_controlled_host_storage(extra, 0, 0)
            .map_err(ControllerAcquisitionFault::Input)?;
        active(lifetime, || {
            scratch.resize(SCRATCH_BYTES, 0);
            Ok(())
        })?;
        Ok(Self {
            records,
            scratch,
            capacity,
            state: CleanupState::Ready,
            root_checks: [CleanupIdentity::NotChecked; 2],
            calls: 0,
        })
    }
    fn fd(&self, parent: Parent, roots: [&File; 2]) -> i32 {
        match parent {
            Parent::Root(index) => roots[index].as_raw_fd(),
            Parent::Entry(index) => self.records[index]
                .held
                .as_ref()
                .expect("retained directory owner")
                .as_raw_fd(),
        }
    }
    fn fail(&mut self, fault: CleanupFault) -> CleanupFault {
        if let CleanupState::Faulted(first) = self.state {
            first
        } else {
            self.state = CleanupState::Faulted(fault);
            fault
        }
    }
    fn inspect(
        &mut self,
        parent: Parent,
        root_dev: u64,
        roots: [&File; 2],
    ) -> Result<(), CleanupFault> {
        // The parent File is retained by this SAME non-reentrant owner and is
        // never taken/dropped until traversal and all deletion observations end.
        let fd = self.fd(parent, roots);
        let fd = unsafe { BorrowedFd::borrow_raw(fd) };
        loop {
            if self.calls
                >= self
                    .capacity
                    .checked_mul(2)
                    .and_then(|n| n.checked_add(2))
                    .ok_or(CleanupFault::Capacity)?
            {
                return Err(CleanupFault::Capacity);
            }
            self.calls += 1;
            let count = bulk(fd, &mut self.scratch)?;
            if count == 0 {
                return Ok(());
            }
            let mut offset = 0;
            for _ in 0..count {
                if self.records.len() == self.capacity {
                    return Err(CleanupFault::Capacity);
                }
                let item = decode(self.scratch.get(offset..).ok_or(CleanupFault::Record)?)?;
                offset = offset.checked_add(item.span).ok_or(CleanupFault::Record)?;
                let mut name = [0; NAME_BYTES];
                name[..item.name.len()].copy_from_slice(item.name);
                let path = item.terminated;
                // Retain exact observed DATA before the first comparison or
                // child open, including the record on any following failure.
                let index = self.records.len();
                self.records.push(Descendant {
                    parent,
                    name,
                    name_len: item.name.len(),
                    identity: Identity {
                        dev: root_dev,
                        ino: item.inode,
                        directory: item.kind == Kind::Directory,
                    },
                    kind: item.kind,
                    held: None,
                    discovered: CleanupIdentity::NotChecked,
                    opened: DirectoryOpen::NotAttempted,
                    checked: CleanupIdentity::NotChecked,
                    unlink: CleanupUnlink::NotAttempted,
                });
                let record = &mut self.records[index];
                let actual =
                    match rustix::fs::statat(fd, path, rustix::fs::AtFlags::SYMLINK_NOFOLLOW) {
                        Ok(actual) => actual,
                        Err(error) => {
                            let kind = io::Error::from(error).kind();
                            record.discovered = CleanupIdentity::Failed(kind);
                            return Err(CleanupFault::Io(kind));
                        }
                    };
                if actual.st_dev as u64 != root_dev
                    || actual.st_ino as u64 != item.inode
                    || Kind::mode(actual.st_mode as u32) != Some(item.kind)
                {
                    record.discovered = CleanupIdentity::Replacement;
                    return Err(CleanupFault::Identity);
                }
                record.discovered = CleanupIdentity::Matched;
                if record.kind == Kind::Directory {
                    let file = match rustix::fs::openat(
                        fd,
                        path,
                        rustix::fs::OFlags::RDONLY
                            | rustix::fs::OFlags::DIRECTORY
                            | rustix::fs::OFlags::NOFOLLOW
                            | rustix::fs::OFlags::CLOEXEC,
                        rustix::fs::Mode::empty(),
                    ) {
                        Ok(file) => File::from(file),
                        Err(error) => {
                            let kind = io::Error::from(error).kind();
                            record.opened = DirectoryOpen::Failed(kind);
                            return Err(CleanupFault::Io(kind));
                        }
                    };
                    record.held = Some(file);
                    record.opened = DirectoryOpen::Returned {
                        identity: CleanupIdentity::NotChecked,
                    };
                    let actual = match record.held.as_ref().unwrap().metadata() {
                        Ok(actual) => actual,
                        Err(error) => {
                            record.opened = DirectoryOpen::Returned {
                                identity: CleanupIdentity::Failed(error.kind()),
                            };
                            return Err(CleanupFault::Io(error.kind()));
                        }
                    };
                    if actual.dev() != root_dev || actual.ino() != item.inode || !actual.is_dir() {
                        record.opened = DirectoryOpen::Returned {
                            identity: CleanupIdentity::Replacement,
                        };
                        return Err(CleanupFault::Identity);
                    }
                    record.opened = DirectoryOpen::Returned {
                        identity: CleanupIdentity::Matched,
                    };
                }
            }
        }
    }
    pub(super) fn clean(
        &mut self,
        caller: &File,
        roots: [&File; 2],
        expected: [Identity; 2],
    ) -> bool {
        match self.state {
            CleanupState::Ready => self.state = CleanupState::InProgress,
            CleanupState::Complete => return true,
            CleanupState::InProgress | CleanupState::Faulted(_) => return false,
        }
        for index in 0..2 {
            let stat = match rustix::fs::statat(
                caller,
                NAMES[index],
                rustix::fs::AtFlags::SYMLINK_NOFOLLOW,
            ) {
                Ok(stat) => stat,
                Err(e) => {
                    self.root_checks[index] = CleanupIdentity::Failed(io::Error::from(e).kind());
                    self.fail(CleanupFault::Identity);
                    return false;
                }
            };
            if stat.st_dev as u64 != expected[index].dev
                || stat.st_ino as u64 != expected[index].ino
                || Kind::mode(stat.st_mode as u32) != Some(Kind::Directory)
            {
                self.root_checks[index] = CleanupIdentity::Replacement;
                self.fail(CleanupFault::Identity);
                return false;
            }
            self.root_checks[index] = CleanupIdentity::Matched;
            if let Err(fault) = self.inspect(Parent::Root(index), expected[index].dev, roots) {
                self.fail(fault);
                return false;
            }
        }
        let mut index = 0;
        while index < self.records.len() {
            if self.records[index].kind == Kind::Directory {
                if let Err(fault) = self.inspect(
                    Parent::Entry(index),
                    self.records[index].identity.dev,
                    roots,
                ) {
                    self.fail(fault);
                    return false;
                }
            }
            index += 1;
        }
        for index in (0..self.records.len()).rev() {
            let fd = self.fd(self.records[index].parent, roots);
            let fd = unsafe { BorrowedFd::borrow_raw(fd) };
            let record = &mut self.records[index];
            let actual = match rustix::fs::statat(
                fd,
                record.name(),
                rustix::fs::AtFlags::SYMLINK_NOFOLLOW,
            ) {
                Ok(actual) => actual,
                Err(e) => {
                    record.checked = CleanupIdentity::Failed(io::Error::from(e).kind());
                    self.fail(CleanupFault::Identity);
                    return false;
                }
            };
            if actual.st_dev as u64 != record.identity.dev
                || actual.st_ino as u64 != record.identity.ino
                || Kind::mode(actual.st_mode as u32) != Some(record.kind)
            {
                record.checked = CleanupIdentity::Replacement;
                self.fail(CleanupFault::Identity);
                return false;
            }
            record.checked = CleanupIdentity::Matched;
            let flags = if record.kind == Kind::Directory {
                rustix::fs::AtFlags::REMOVEDIR
            } else {
                rustix::fs::AtFlags::empty()
            };
            match rustix::fs::unlinkat(fd, record.name(), flags) {
                Ok(()) => record.unlink = CleanupUnlink::Returned,
                Err(e) => {
                    record.unlink = CleanupUnlink::Failed(io::Error::from(e).kind());
                    self.fail(CleanupFault::Io(io::Error::from(e).kind()));
                    return false;
                }
            }
        }
        self.state = CleanupState::Complete;
        true
    }
    pub(super) fn release_handles(&mut self) -> usize {
        let mut released = 0;
        for record in &mut self.records {
            if let Some(file) = record.held.take() {
                drop(file);
                released += 1;
            }
        }
        released
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn literal() -> Vec<u8> {
        // Literal Darwin ATTR_BULK_REQUIRED/name/type/fileid layout; not a
        // system-call observation or fixture qualification.
        let mut bytes = vec![0; 48];
        bytes[0..4].copy_from_slice(&48u32.to_ne_bytes());
        bytes[4..8].copy_from_slice(&ATTRS.to_ne_bytes());
        bytes[24..28].copy_from_slice(&20i32.to_ne_bytes());
        bytes[28..32].copy_from_slice(&2u32.to_ne_bytes());
        bytes[32..36].copy_from_slice(&1u32.to_ne_bytes());
        bytes[36..44].copy_from_slice(&7u64.to_ne_bytes());
        bytes[44] = b'x';
        bytes
    }
    #[test]
    fn cleanup_metadata_01_closed_bounded_record_refuses_masks_offsets_and_names() {
        let bytes = literal();
        let item = decode(&bytes).unwrap();
        assert_eq!(item.name, b"x");
        assert_eq!(item.inode, 7);
        for (start, value) in [(0, 49u32), (4, ATTRS | 2), (24, 0), (28, 1025), (32, 0)] {
            let mut bad = bytes.clone();
            bad[start..start + 4].copy_from_slice(&value.to_ne_bytes());
            assert!(decode(&bad).is_err());
        }
        let mut bad = bytes;
        bad[44] = b'/';
        assert!(decode(&bad).is_err());
    }
}
