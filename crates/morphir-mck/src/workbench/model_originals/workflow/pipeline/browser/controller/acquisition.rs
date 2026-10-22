//! Source-related, bounded held-path acquisition. Paths and declared lengths
//! are DATA, not grants, canonical identity or path-exec immutability evidence.
use super::super::{
    adapter::{
        BrowserInputError, BrowserLoans, BrowserSourceFault,
        execution_loans::SourceControllerLifetime,
    },
    funded_workflow::{BrowserPhysicalBuffers, BrowserPhysicalParts},
};
use super::*;
use std::{
    io,
    mem::size_of,
    os::unix::{ffi::OsStrExt, fs::FileExt},
};
#[path = "acquisition/cleanup.rs"]
mod cleanup;
use super::source_operation::SourceOperationPrepayment;
pub(in crate::workbench::model_originals::workflow::pipeline::browser) use cleanup::CleanupFault;
use cleanup::CleanupPlan;
#[cfg(test)]
pub(super) use cleanup::{DirectoryOpen as CleanupDirectoryOpen, Kind as CleanupEntryKind};

const DRIVER: &[u8] = include_bytes!("driver.js");
const NAMES: [&str; 3] = ["profile", "artifacts", "driver.mjs"];
const NODE: [u8; 32] = [
    0xb4, 0x68, 0xfb, 0x9c, 0x67, 0x42, 0x7c, 0x9d, 0x3a, 0xec, 0x07, 0xee, 0x11, 0x05, 0xe6, 0x30,
    0x20, 0x92, 0x3a, 0x63, 0x1a, 0x9a, 0x2a, 0x00, 0xbe, 0xb7, 0x1a, 0x7b, 0xa3, 0x76, 0x8b, 0xfd,
];
const CORE: [u8; 32] = [
    0x82, 0x95, 0x21, 0xb6, 0x7e, 0xd7, 0xbe, 0x90, 0xc7, 0xd6, 0xd6, 0x09, 0x8f, 0xf3, 0x9f, 0x22,
    0x41, 0x56, 0x2d, 0x47, 0xe4, 0xad, 0x7c, 0xca, 0xb1, 0x37, 0x10, 0x92, 0x4a, 0x56, 0x00, 0x1d,
];

#[derive(Clone, Copy)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct ControllerFileInput<
    'a,
> {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) path: &'a Path,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) byte_length: u64,
}
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct ControllerTargetInput<
    'a,
> {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) chromium:
        ControllerFileInput<'a>,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) node:
        ControllerFileInput<'a>,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) core_bundle:
        ControllerFileInput<'a>,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) entry:
        ControllerFileInput<'a>,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) root: &'a Path,
}
#[derive(Debug)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) enum ControllerAcquisitionFault
{
    Input(BrowserInputError),
    Source(BrowserSourceFault),
    End,
    Shape,
    Io(io::ErrorKind),
    Length { declared: u64, actual: u64 },
    Executable,
    Clock,
    Package,
    Allocation,
    Overflow,
    Cleanup(CleanupFault),
}
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct ControllerLaunchLayout
{
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) bytes: usize,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) slots: usize,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) visits: usize,
}
impl ControllerTargetInput<'_> {
    /// Common fixed Chromium/Node argv and public command wrappers only. The
    /// source variant/URL/selection/association are prepaid by their own owner.
    /// Decimal/endpoint bounds are wire-type maxima, not caller length grants.
    /// This does not estimate private stdlib allocator or VM/kernel storage.
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn launch_layout(
        &self,
    ) -> Result<ControllerLaunchLayout, ControllerFault> {
        let layout = (|| {
            let root = self.root.as_os_str().len();
            let profile = checked_add(root, "/profile".len())?;
            let artifacts = checked_add(root, "/artifacts".len())?;
            let driver = checked_add(root, "/driver.mjs".len())?;
            let chromium = [
                "--headless".len(),
                "--password-store=basic".len(),
                "--use-mock-keychain".len(),
                "--remote-debugging-port=0".len(),
                checked_add("--user-data-dir=".len(), profile)?,
                "--no-first-run".len(),
                "--no-default-browser-check".len(),
                "about:blank".len(),
            ];
            let node = [
                driver,
                self.entry.path.as_os_str().len(),
                "ws://127.0.0.1:65535/devtools/browser/00000000-0000-0000-0000-000000000000".len(),
                artifacts,
                20,
                20,
                10,
                10,
            ];
            let mut bytes = 2 * (size_of::<CommandSpec>() + size_of::<std::process::Command>());
            let mut visits = 0;
            for length in chromium.into_iter().chain(node).chain([
                self.chromium.path.as_os_str().len(),
                self.node.path.as_os_str().len(),
                root,
                root,
            ]) {
                // Owned description payload plus the std::process argument/path
                // copy including its OS string terminator; each is visited.
                let copies = checked_add(length, checked_add(length, 1)?)?;
                bytes = checked_add(bytes, copies)?;
                visits = checked_add(visits, copies)?;
            }
            let slots = 8 + 8 + 4 + 2;
            bytes = checked_add(bytes, slots * size_of::<OsString>())?;
            Ok(ControllerLaunchLayout {
                bytes,
                slots,
                visits: checked_add(visits, bytes)?,
            })
        })();
        layout.map_err(|_: ControllerAcquisitionFault| ControllerFault::Acquisition)
    }
}
fn os(error: rustix::io::Errno) -> ControllerAcquisitionFault {
    ControllerAcquisitionFault::Io(io::Error::from(error).kind())
}
fn active<R>(
    lifetime: &SourceControllerLifetime,
    action: impl FnOnce() -> Result<R, ControllerAcquisitionFault>,
) -> Result<R, ControllerAcquisitionFault> {
    lifetime
        .while_active(|| {
            if Instant::now() >= lifetime.end() {
                return Err(ControllerAcquisitionFault::End);
            }
            action()
        })
        .map_err(ControllerAcquisitionFault::Source)?
}
#[derive(Clone, Copy)]
struct Identity {
    dev: u64,
    ino: u64,
    directory: bool,
}
impl Identity {
    fn from(metadata: &fs::Metadata) -> Self {
        Self {
            dev: metadata.dev(),
            ino: metadata.ino(),
            directory: metadata.is_dir(),
        }
    }
}
#[derive(Clone, Copy)]
enum CreatedEntry {
    NotCreated,
    Unidentified,
    Held(Identity),
    Removed,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) enum CleanupIdentity {
    NotChecked,
    Matched,
    Replacement,
    Missing,
    Failed(io::ErrorKind),
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) enum CleanupUnlink {
    NotAttempted,
    Returned,
    Failed(io::ErrorKind),
}
#[derive(Debug, Clone, Copy)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct EntryCleanup {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) identity:
        CleanupIdentity,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) unlink: CleanupUnlink,
}
struct PartialAcquisition {
    files: [Option<File>; 5],
    walk_parent: Option<File>,
    created_files: [Option<File>; 3],
    created: [CreatedEntry; 3],
    cleanup: [EntryCleanup; 3],
    read_bytes: u64,
    eofs: usize,
}
impl PartialAcquisition {
    fn empty() -> Self {
        Self {
            files: [None, None, None, None, None],
            walk_parent: None,
            created_files: [None, None, None],
            created: [CreatedEntry::NotCreated; 3],
            cleanup: [EntryCleanup {
                identity: CleanupIdentity::NotChecked,
                unlink: CleanupUnlink::NotAttempted,
            }; 3],
            read_bytes: 0,
            eofs: 0,
        }
    }
    fn held_files(&self) -> usize {
        self.files.iter().filter(|f| f.is_some()).count()
            + self.created_files.iter().filter(|f| f.is_some()).count()
            + usize::from(self.walk_parent.is_some())
    }
}
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct FundedControllerAcquisition
{
    lifetime: SourceControllerLifetime,
    paths: [PathBuf; 5],
    created_paths: [PathBuf; 3],
    lengths: [u64; 4],
    buffers: Option<BrowserPhysicalBuffers>,
    partial: PartialAcquisition,
    scratch: Option<Vec<u8>>,
    descendants: Option<CleanupPlan>,
    prepayment: Option<SourceOperationPrepayment>,
}
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct ControllerAcquisitionFailure
{
    first: ControllerAcquisitionFault,
    retained: FundedControllerAcquisition,
}
/// Entry retirement only; File owners and SAME source debt remain retained.
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct AcquisitionCleanup {
    retained: usize,
}
impl AcquisitionCleanup {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn is_complete(
        &self,
    ) -> bool {
        self.retained == 0
    }
}
impl ControllerAcquisitionFailure {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn fault(
        &self,
    ) -> &ControllerAcquisitionFault {
        &self.first
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn read_bytes(
        &self,
    ) -> u64 {
        self.retained.partial.read_bytes
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn observed_eofs(
        &self,
    ) -> usize {
        self.retained.partial.eofs
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn held_files(
        &self,
    ) -> usize {
        self.retained.partial.held_files()
    }
    /// One prepaid cleanup attempt per actually created entry, even after source
    /// revocation/end. This is identity-check followed by unlinkat, not an atomic
    /// identity-conditional deletion against concurrent same-user mutation.
    /// The caller root is held and borrowed, and is never removed.
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn cleanup_owned_entries(
        &mut self,
    ) -> AcquisitionCleanup {
        if let Some(root) = self.retained.partial.files[4].as_ref() {
            if let (
                Some(plan),
                Some(profile),
                Some(artifacts),
                CreatedEntry::Held(profile_id),
                CreatedEntry::Held(artifacts_id),
            ) = (
                self.retained.descendants.as_mut(),
                self.retained.partial.created_files[0].as_ref(),
                self.retained.partial.created_files[1].as_ref(),
                self.retained.partial.created[0],
                self.retained.partial.created[1],
            ) {
                plan.clean(root, [profile, artifacts], [profile_id, artifacts_id]);
            }
            cleanup_entries(
                root,
                &mut self.retained.partial.created,
                &mut self.retained.partial.cleanup,
            );
        }
        cleanup_report(&self.retained.partial.created)
    }

    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn cleanup_record(
        &self,
        index: usize,
    ) -> Option<EntryCleanup> {
        self.retained.partial.cleanup.get(index).copied()
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn descendant_cleanup(
        &self,
    ) -> Option<&CleanupPlan> {
        self.retained.descendants.as_ref()
    }
    /// No child process was started by acquisition. This consumes only actual
    /// owned entry retirement and held File owners, without inventing OS close.
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn finish_cleanup(
        mut self,
    ) -> Result<CleanedAcquisitionFailure, Self> {
        if !self.cleanup_owned_entries().is_complete() {
            return Err(self);
        }
        let Self { first, retained } = self;
        let FundedControllerAcquisition {
            lifetime,
            partial,
            mut descendants,
            ..
        } = retained;
        let held = partial.held_files();
        let descendant_handles = descendants.as_mut().map_or(0, CleanupPlan::release_handles);
        let cleanup = partial.cleanup;
        let read_bytes = partial.read_bytes;
        let eofs = partial.eofs;
        drop(partial);
        Ok(CleanedAcquisitionFailure {
            first,
            lifetime,
            cleanup,
            descendants,
            read_bytes,
            eofs,
            release: SourceFileRelease::HandlesReleasedUnverified {
                handles: held + descendant_handles,
            },
        })
    }
}
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct CleanedAcquisitionFailure
{
    first: ControllerAcquisitionFault,
    lifetime: SourceControllerLifetime,
    cleanup: [EntryCleanup; 3],
    descendants: Option<CleanupPlan>,
    read_bytes: u64,
    eofs: usize,
    release: SourceFileRelease,
}
impl CleanedAcquisitionFailure {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn fault(
        &self,
    ) -> &ControllerAcquisitionFault {
        &self.first
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn release(
        &self,
    ) -> SourceFileRelease {
        self.release
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn into_parts(
        self,
    ) -> (SourceControllerLifetime, AcquisitionFailureCleanupEvidence) {
        let Self {
            first,
            lifetime,
            cleanup,
            descendants,
            read_bytes,
            eofs,
            release,
        } = self;
        (
            lifetime,
            AcquisitionFailureCleanupEvidence {
                first,
                cleanup,
                descendants,
                read_bytes,
                eofs,
                release,
            },
        )
    }
}
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct AcquisitionFailureCleanupEvidence
{
    first: ControllerAcquisitionFault,
    cleanup: [EntryCleanup; 3],
    descendants: Option<CleanupPlan>,
    read_bytes: u64,
    eofs: usize,
    release: SourceFileRelease,
}
impl AcquisitionFailureCleanupEvidence {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn fault(
        &self,
    ) -> &ControllerAcquisitionFault {
        &self.first
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn release(
        &self,
    ) -> SourceFileRelease {
        self.release
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn cleanup(
        &self,
    ) -> &[EntryCleanup; 3] {
        &self.cleanup
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn descendant_cleanup(
        &self,
    ) -> Option<&CleanupPlan> {
        self.descendants.as_ref()
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn reads(
        &self,
    ) -> (u64, usize) {
        (self.read_bytes, self.eofs)
    }
}
fn cleanup_report(entries: &[CreatedEntry; 3]) -> AcquisitionCleanup {
    AcquisitionCleanup {
        retained: entries
            .iter()
            .filter(|entry| !matches!(entry, CreatedEntry::NotCreated | CreatedEntry::Removed))
            .count(),
    }
}
fn cleanup_entries(root: &File, entries: &mut [CreatedEntry; 3], records: &mut [EntryCleanup; 3]) {
    use rustix::fs::{AtFlags, statat, unlinkat};
    for index in (0..3).rev() {
        let CreatedEntry::Held(identity) = entries[index] else {
            continue;
        };
        let record = &mut records[index];
        if record.identity != CleanupIdentity::NotChecked {
            continue;
        }
        match statat(root, NAMES[index], AtFlags::SYMLINK_NOFOLLOW) {
            Ok(now) => {
                let directory = now.st_mode & 0o170000 == 0o040000;
                if now.st_dev as u64 != identity.dev
                    || now.st_ino as u64 != identity.ino
                    || directory != identity.directory
                {
                    record.identity = CleanupIdentity::Replacement;
                    continue;
                }
                record.identity = CleanupIdentity::Matched;
            }
            Err(rustix::io::Errno::NOENT) => {
                record.identity = CleanupIdentity::Missing;
                continue;
            }
            Err(error) => {
                record.identity = CleanupIdentity::Failed(io::Error::from(error).kind());
                continue;
            }
        }
        let flags = if identity.directory {
            AtFlags::REMOVEDIR
        } else {
            AtFlags::empty()
        };
        match unlinkat(root, NAMES[index], flags) {
            Ok(()) => {
                record.unlink = CleanupUnlink::Returned;
                entries[index] = CreatedEntry::Removed;
            }
            Err(error) => {
                record.unlink = CleanupUnlink::Failed(io::Error::from(error).kind());
            }
        }
    }
}
pub(super) struct SourceAcquiredOwnership {
    _core: File,
    _artifacts: File,
    _driver: File,
    entries: [CreatedEntry; 3],
    cleanup: [EntryCleanup; 3],
    descendants: CleanupPlan,
    _digests: [[u8; 32]; 4],
    _actual_read_bytes: u64,
    _actual_eofs: usize,
}
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct AcquiredControllerTarget
{
    target: AcquiredTarget,
    buffers: BrowserPhysicalBuffers,
    lifetime: SourceControllerLifetime,
    prepayment: SourceOperationPrepayment,
}
impl AcquiredControllerTarget {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn into_parts(
        self,
    ) -> (
        AcquiredTarget,
        BrowserPhysicalParts,
        SourceControllerLifetime,
        SourceOperationPrepayment,
    ) {
        (
            self.target,
            self.buffers.into_parts(),
            self.lifetime,
            self.prepayment,
        )
    }
}
/// Actual File owners were consumed by Drop. Rust's File destructor provides no
/// OS close result, so this is deliberately not a successful-close assertion.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) enum SourceFileRelease {
    HandlesReleasedUnverified { handles: usize },
}
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct SourceControllerFileOutcome
{
    chromium: ProcessOutcome,
    driver: Option<InteractiveOutcome>,
    first_fault: Option<ControllerFault>,
    cleanup: [EntryCleanup; 3],
    release: SourceFileRelease,
    descendants: CleanupPlan,
}
impl SourceControllerFileOutcome {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn descendant_cleanup(
        &self,
    ) -> &CleanupPlan {
        &self.descendants
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn chromium(
        &self,
    ) -> &ProcessOutcome {
        &self.chromium
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn driver(
        &self,
    ) -> Option<&InteractiveOutcome> {
        self.driver.as_ref()
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn first_fault(
        &self,
    ) -> Option<ControllerFault> {
        self.first_fault
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn cleanup(
        &self,
    ) -> &[EntryCleanup; 3] {
        &self.cleanup
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn release(
        &self,
    ) -> SourceFileRelease {
        self.release
    }
}
impl ControllerOutcome {
    /// Only an actual raw finished controller can reach this consuming seam.
    /// Failed cleanup retains SAME raw outcomes, files, first fault and debt.
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn finish_source_files(
        mut self,
    ) -> Result<SourceControllerFileOutcome, Self> {
        let Some(owned) = self.0.target._source_owned.as_mut() else {
            return Err(self);
        };
        let [
            CreatedEntry::Held(profile_id),
            CreatedEntry::Held(artifacts_id),
            _,
        ] = owned.entries
        else {
            return Err(self);
        };
        owned.descendants.clean(
            &self.0.target._root,
            [&self.0.target.profile_dir, &owned._artifacts],
            [profile_id, artifacts_id],
        );
        cleanup_entries(&self.0.target._root, &mut owned.entries, &mut owned.cleanup);
        if !cleanup_report(&owned.entries).is_complete() {
            self.0
                .first_fault
                .get_or_insert(ControllerFault::Acquisition);
            return Err(self);
        }
        let cleanup = owned.cleanup;
        let BrowserController {
            mut target,
            chromium,
            driver,
            first_fault,
            ..
        } = self.0;
        let Chromium::Finished(chromium) = chromium else {
            unreachable!("actual finished controller")
        };
        let driver = match driver {
            Driver::Finished(outcome) => Some(outcome),
            Driver::NotStarted => None,
            _ => unreachable!("actual finished driver"),
        };
        // Eight actual File fields in source-acquired target: executables2,
        // root/index/profile3 and core/artifacts/driver3. Never caller rootdir.
        let SourceAcquiredOwnership {
            _core,
            _artifacts,
            _driver,
            mut descendants,
            ..
        } = target._source_owned.take().expect("same source owner");
        let descendant_handles = descendants.release_handles();
        drop((_core, _artifacts, _driver));
        drop(target);
        Ok(SourceControllerFileOutcome {
            chromium,
            driver,
            first_fault,
            cleanup,
            release: SourceFileRelease::HandlesReleasedUnverified {
                handles: 8 + descendant_handles,
            },
            descendants,
        })
    }
}
fn checked_add(a: usize, b: usize) -> Result<usize, ControllerAcquisitionFault> {
    a.checked_add(b).ok_or(ControllerAcquisitionFault::Overflow)
}
fn valid_path(path: &Path) -> bool {
    let bytes = path.as_os_str().as_bytes();
    bytes.first() == Some(&b'/')
        && bytes.len() > 1
        && bytes[1..].split(|b| *b == b'/').all(|part| {
            !part.is_empty()
                && part.len() < 1024
                && part != b"."
                && part != b".."
                && !part.contains(&0)
        })
}
fn copy_path(
    path: &Path,
    suffix: Option<&str>,
    lifetime: &SourceControllerLifetime,
    loans: &mut BrowserLoans<'_, '_>,
) -> Result<PathBuf, ControllerAcquisitionFault> {
    let requested = match suffix {
        Some(suffix) => checked_add(checked_add(path.as_os_str().len(), 1)?, suffix.len())?,
        None => path.as_os_str().len(),
    };
    let mut owned = active(lifetime, || {
        let mut owned = PathBuf::new();
        owned
            .try_reserve_exact(requested)
            .map_err(|_| ControllerAcquisitionFault::Allocation)?;
        Ok(owned)
    })?;
    let spare = owned
        .capacity()
        .checked_sub(requested)
        .ok_or(ControllerAcquisitionFault::Overflow)?;
    loans
        .reserve_controlled_host_storage(spare, 0, 0)
        .map_err(ControllerAcquisitionFault::Input)?;
    active(lifetime, || {
        owned.push(path);
        if let Some(suffix) = suffix {
            owned.push(suffix);
        }
        Ok(())
    })?;
    Ok(owned)
}
impl FundedControllerAcquisition {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn prepare(
        input: ControllerTargetInput<'_>,
        limits: Limits,
        lifetime: SourceControllerLifetime,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<Self, ControllerAcquisitionFailure> {
        // Failure itself retains the exact lifetime and any physical ownership.
        // No path copy, scan, allocation or syscall precedes relation validation.
        let mut prepared = Self {
            lifetime,
            paths: std::array::from_fn(|_| PathBuf::new()),
            created_paths: std::array::from_fn(|_| PathBuf::new()),
            lengths: [
                input.chromium.byte_length,
                input.node.byte_length,
                input.core_bundle.byte_length,
                input.entry.byte_length,
            ],
            buffers: None,
            partial: PartialAcquisition::empty(),
            scratch: None,
            descendants: None,
            prepayment: None,
        };
        let result = (|| {
            prepared
                .lifetime
                .validate(loans)
                .map_err(ControllerAcquisitionFault::Input)?;
            active(&prepared.lifetime, || Ok(()))?;
            prepared.prepayment = Some(
                SourceOperationPrepayment::prepare(&input, limits, &prepared.lifetime, loans)
                    .map_err(ControllerAcquisitionFault::Input)?,
            );
            let source_paths = [
                input.chromium.path,
                input.node.path,
                input.core_bundle.path,
                input.entry.path,
                input.root,
            ];
            // Requested application headers across preparation/failure,
            // successful target and final factual outcome. This is not a claim
            // about compiler stack reuse, VM pages or kernel descriptor storage.
            let headers = checked_add(
                checked_add(
                    size_of::<ControllerAcquisitionFailure>(),
                    size_of::<AcquiredControllerTarget>(),
                )?,
                checked_add(
                    size_of::<SourceAcquiredOwnership>(),
                    checked_add(
                        size_of::<SourceControllerFileOutcome>(),
                        size_of::<CleanedAcquisitionFailure>(),
                    )?,
                )?,
            )?;
            let mut bytes = checked_add(headers, 65536)?;
            let mut visits = checked_add(headers, 65536)?;
            for path in source_paths {
                bytes = checked_add(bytes, path.as_os_str().len())?;
                visits = checked_add(
                    visits,
                    path.as_os_str()
                        .len()
                        .checked_mul(4)
                        .ok_or(ControllerAcquisitionFault::Overflow)?,
                )?;
            }
            for name in NAMES {
                let length =
                    checked_add(checked_add(input.root.as_os_str().len(), 1)?, name.len())?;
                bytes = checked_add(bytes, length)?;
                visits = checked_add(
                    visits,
                    length
                        .checked_mul(2)
                        .ok_or(ControllerAcquisitionFault::Overflow)?,
                )?;
            }
            for length in prepared.lengths {
                let length =
                    usize::try_from(length).map_err(|_| ControllerAcquisitionFault::Overflow)?;
                visits = checked_add(
                    visits,
                    checked_add(
                        length
                            .checked_mul(2)
                            .ok_or(ControllerAcquisitionFault::Overflow)?,
                        1,
                    )?,
                )?;
            }
            visits = checked_add(
                visits,
                DRIVER
                    .len()
                    .checked_mul(2)
                    .ok_or(ControllerAcquisitionFault::Overflow)?,
            )?;
            loans
                .reserve_controlled_host_storage(bytes, 8, visits)
                .map_err(ControllerAcquisitionFault::Input)?;
            if source_paths.into_iter().any(|path| !valid_path(path)) {
                return Err(ControllerAcquisitionFault::Shape);
            }
            // Metadata work is derived only after the raw-component scan is paid.
            let components = source_paths.into_iter().try_fold(0usize, |count, path| {
                checked_add(
                    count,
                    path.as_os_str().as_bytes()[1..]
                        .split(|b| *b == b'/')
                        .count(),
                )
            })?;
            // One walk-handle step per component, five actual held metadata
            // checks, three created identities and three cleanup identity reads.
            let metadata_work = checked_add(
                components
                    .checked_mul(size_of::<File>())
                    .ok_or(ControllerAcquisitionFault::Overflow)?,
                (5usize + 3 + 3)
                    .checked_mul(size_of::<fs::Metadata>())
                    .ok_or(ControllerAcquisitionFault::Overflow)?,
            )?;
            loans
                .reserve_controlled_host_storage(0, 0, metadata_work)
                .map_err(ControllerAcquisitionFault::Input)?;
            prepared.buffers = Some(
                loans
                    .prepare_controller_buffers(&prepared.lifetime, limits)
                    .map_err(ControllerAcquisitionFault::Input)?,
            );
            let mut scratch = active(&prepared.lifetime, || {
                let mut bytes = Vec::new();
                bytes
                    .try_reserve_exact(65536)
                    .map_err(|_| ControllerAcquisitionFault::Allocation)?;
                Ok(bytes)
            })?;
            let spare = scratch
                .capacity()
                .checked_sub(65536)
                .ok_or(ControllerAcquisitionFault::Overflow)?;
            loans
                .reserve_controlled_host_storage(spare, 0, 0)
                .map_err(ControllerAcquisitionFault::Input)?;
            active(&prepared.lifetime, || {
                scratch.resize(65536, 0);
                Ok(())
            })?;
            prepared.scratch = Some(scratch);
            for (index, path) in source_paths.into_iter().enumerate() {
                prepared.paths[index] = copy_path(path, None, &prepared.lifetime, loans)?;
            }
            for (index, name) in NAMES.into_iter().enumerate() {
                prepared.created_paths[index] =
                    copy_path(input.root, Some(name), &prepared.lifetime, loans)?;
            }
            // Callers must already have prepared their actual runtime/UI input
            // association and source owner work. The known fixed conversation
            // prepayment above precedes this SAME-owner residual selection.
            prepared.descendants = Some(CleanupPlan::prepare(&prepared.lifetime, loans)?);
            active(&prepared.lifetime, || Ok(()))?;
            Ok(())
        })();
        match result {
            Ok(()) => Ok(prepared),
            Err(first) => Err(ControllerAcquisitionFailure {
                first,
                retained: prepared,
            }),
        }
    }
    fn walk(&mut self, index: usize) -> Result<(), ControllerAcquisitionFault> {
        use rustix::fs::{Mode, OFlags, open, openat};
        let directory = OFlags::RDONLY | OFlags::DIRECTORY | OFlags::NOFOLLOW | OFlags::CLOEXEC;
        self.partial.walk_parent = Some(active(&self.lifetime, || {
            open("/", directory, Mode::empty())
                .map(File::from)
                .map_err(os)
        })?);
        let mut components = self.paths[index].as_os_str().as_bytes()[1..]
            .split(|b| *b == b'/')
            .peekable();
        while let Some(component) = components.next() {
            let final_component = components.peek().is_none();
            let flags = if !final_component || index == 4 {
                directory
            } else {
                OFlags::RDONLY | OFlags::NOFOLLOW | OFlags::NONBLOCK | OFlags::CLOEXEC
            };
            let parent = self.partial.walk_parent.as_ref().expect("held parent");
            let scratch = self.scratch.as_mut().expect("funded path/hash scratch");
            let file = active(&self.lifetime, || {
                // Reuse the actually funded scratch for a terminated component;
                // no hidden path-to-CString allocation is needed by openat.
                scratch[..component.len()].copy_from_slice(component);
                scratch[component.len()] = 0;
                let name = std::ffi::CStr::from_bytes_with_nul(&scratch[..component.len() + 1])
                    .map_err(|_| ControllerAcquisitionFault::Shape)?;
                openat(parent, name, flags, Mode::empty())
                    .map(File::from)
                    .map_err(os)
            })?;
            if final_component {
                self.partial.files[index] = Some(file);
            } else {
                self.partial.walk_parent = Some(file);
            }
        }
        self.partial.walk_parent = None;
        let file = self.partial.files[index].as_ref().expect("absolute file");
        let metadata = active(&self.lifetime, || {
            file.metadata()
                .map_err(|error| ControllerAcquisitionFault::Io(error.kind()))
        })?;
        if index == 4 {
            if !metadata.is_dir() {
                return Err(ControllerAcquisitionFault::Shape);
            }
        } else {
            if !metadata.is_file() {
                return Err(ControllerAcquisitionFault::Shape);
            }
            if metadata.len() != self.lengths[index] {
                return Err(ControllerAcquisitionFault::Length {
                    declared: self.lengths[index],
                    actual: metadata.len(),
                });
            }
            if index < 2 && metadata.permissions().mode() & 0o111 == 0 {
                return Err(ControllerAcquisitionFault::Executable);
            }
        }
        Ok(())
    }
    fn create(&mut self, index: usize) -> Result<(), ControllerAcquisitionFault> {
        use rustix::fs::{Mode, OFlags, mkdirat, openat};
        let root = self.partial.files[4].as_ref().expect("held caller root");
        let file = if index < 2 {
            active(&self.lifetime, || {
                mkdirat(root, NAMES[index], Mode::RUSR | Mode::WUSR | Mode::XUSR).map_err(os)
            })?;
            self.partial.created[index] = CreatedEntry::Unidentified;
            active(&self.lifetime, || {
                openat(
                    root,
                    NAMES[index],
                    OFlags::RDONLY | OFlags::DIRECTORY | OFlags::NOFOLLOW | OFlags::CLOEXEC,
                    Mode::empty(),
                )
                .map(File::from)
                .map_err(os)
            })?
        } else {
            let file = active(&self.lifetime, || {
                openat(
                    root,
                    NAMES[index],
                    OFlags::WRONLY
                        | OFlags::CREATE
                        | OFlags::EXCL
                        | OFlags::NOFOLLOW
                        | OFlags::CLOEXEC,
                    Mode::RUSR | Mode::WUSR,
                )
                .map(File::from)
                .map_err(os)
            })?;
            self.partial.created[index] = CreatedEntry::Unidentified;
            file
        };
        self.partial.created_files[index] = Some(file);
        let metadata = active(&self.lifetime, || {
            self.partial.created_files[index]
                .as_ref()
                .unwrap()
                .metadata()
                .map_err(|e| ControllerAcquisitionFault::Io(e.kind()))
        })?;
        if metadata.is_dir() != (index < 2) || (index == 2 && !metadata.is_file()) {
            return Err(ControllerAcquisitionFault::Shape);
        }
        self.partial.created[index] = CreatedEntry::Held(Identity::from(&metadata));
        if index == 2 {
            let mut offset = 0;
            while offset < DRIVER.len() {
                let count = active(&self.lifetime, || {
                    self.partial.created_files[index]
                        .as_ref()
                        .unwrap()
                        .write_at(&DRIVER[offset..], offset as u64)
                        .map_err(|e| ControllerAcquisitionFault::Io(e.kind()))
                })?;
                if count == 0 {
                    return Err(ControllerAcquisitionFault::Io(io::ErrorKind::WriteZero));
                }
                offset += count;
            }
        }
        Ok(())
    }
    fn digest(&mut self, index: usize) -> Result<[u8; 32], ControllerAcquisitionFault> {
        let scratch = self.scratch.as_mut().expect("funded hash scratch");
        let mut digest = Sha256::new();
        let mut offset = 0;
        while offset < self.lengths[index] {
            let request = usize::try_from((self.lengths[index] - offset).min(scratch.len() as u64))
                .map_err(|_| ControllerAcquisitionFault::Overflow)?;
            let file = self.partial.files[index].as_ref().unwrap();
            let count = active(&self.lifetime, || {
                file.read_at(&mut scratch[..request], offset)
                    .map_err(|e| ControllerAcquisitionFault::Io(e.kind()))
            })?;
            self.partial.read_bytes += count as u64;
            if count == 0 {
                self.partial.eofs += 1;
                return Err(ControllerAcquisitionFault::Length {
                    declared: self.lengths[index],
                    actual: offset,
                });
            }
            active(&self.lifetime, || {
                digest.update(&scratch[..count]);
                Ok(())
            })?;
            offset += count as u64;
        }
        // EOF is actually observed, not inferred from the earlier metadata. A
        // grown file's extra byte is refused and never hashed as admitted data.
        let count = active(&self.lifetime, || {
            self.partial.files[index]
                .as_ref()
                .unwrap()
                .read_at(&mut scratch[..1], offset)
                .map_err(|e| ControllerAcquisitionFault::Io(e.kind()))
        })?;
        self.partial.read_bytes += count as u64;
        if count != 0 {
            return Err(ControllerAcquisitionFault::Length {
                declared: self.lengths[index],
                actual: offset + count as u64,
            });
        }
        self.partial.eofs += 1;
        Ok(digest.finalize().into())
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn acquire(
        mut self,
    ) -> Result<AcquiredControllerTarget, ControllerAcquisitionFailure> {
        let result = (|| {
            // Metadata/length checks precede every hash read. Root is borrowed.
            for index in [4, 0, 1, 2, 3] {
                self.walk(index)?;
            }
            self.create(0)?;
            self.create(1)?;
            let node = self.digest(1)?;
            if node != NODE {
                return Err(ControllerAcquisitionFault::Clock);
            }
            let core = self.digest(2)?;
            if core != CORE {
                return Err(ControllerAcquisitionFault::Package);
            }
            let chromium = self.digest(0)?;
            let entry = self.digest(3)?;
            self.create(2)?;
            active(&self.lifetime, || Ok(()))?;
            Ok([chromium, node, core, entry])
        })();
        let digests = match result {
            Ok(digests) => digests,
            Err(first) => {
                return Err(ControllerAcquisitionFailure {
                    first,
                    retained: self,
                });
            }
        };
        let [chromium_path, node_path, _core_path, entry, root] = self.paths;
        let [profile, artifacts, driver] = self.created_paths;
        let target = AcquiredTarget {
            chromium: Executable {
                path: chromium_path,
                held: self.partial.files[0].take().unwrap(),
            },
            node: Executable {
                path: node_path,
                held: self.partial.files[1].take().unwrap(),
            },
            entry,
            _package: self.partial.files[3].take().unwrap(),
            root,
            _root: self.partial.files[4].take().unwrap(),
            profile,
            profile_dir: self.partial.created_files[0].take().unwrap(),
            artifacts,
            driver,
            _source_owned: Some(SourceAcquiredOwnership {
                _core: self.partial.files[2].take().unwrap(),
                _artifacts: self.partial.created_files[1].take().unwrap(),
                _driver: self.partial.created_files[2].take().unwrap(),
                entries: self.partial.created,
                cleanup: self.partial.cleanup,
                descendants: self.descendants.take().expect("prepaid cleanup owner"),
                _digests: digests,
                _actual_read_bytes: self.partial.read_bytes,
                _actual_eofs: self.partial.eofs,
            }),
        };
        Ok(AcquiredControllerTarget {
            target,
            buffers: self.buffers.take().unwrap(),
            lifetime: self.lifetime,
            prepayment: self
                .prepayment
                .take()
                .expect("same known-operation prepayment"),
        })
    }
}
