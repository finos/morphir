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
#[path = "acquisition/runtime_sink.rs"]
mod runtime_sink;
use super::source_inputs::{
    ConsumedRuntimePackage, PreparedRuntimeMaterialization, RuntimeArchiveReadTerminal,
    RuntimeMaterializationPreparationFailure, RuntimePackageDimensions, RuntimePackageFile,
    RuntimeSinkTerminal, SelectedRuntimePackage,
};
use runtime_sink::{RuntimeSink, RuntimeSinkFault};
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct SelectedControllerTargetInput<
    'a,
> {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) chromium:
        ControllerFileInput<'a>,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) node:
        ControllerFileInput<'a>,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) root: &'a Path,
}
enum RuntimeReaderState {
    NotSelected,
    Package(SelectedRuntimePackage),
    Prepared(PreparedRuntimeMaterialization<RuntimeSinkFault>),
    PreparationFailed(RuntimeMaterializationPreparationFailure),
    Observed {
        package: ConsumedRuntimePackage,
        read: RuntimeArchiveReadTerminal,
        sink: RuntimeSinkTerminal<RuntimeSinkFault>,
    },
    Moving,
}
enum RuntimeSetup {
    Pending,
    Prepared,
    Started,
    Faulted(RuntimeSinkFault),
}
struct RuntimeAcquisition {
    setup: RuntimeSetup,
    reader: RuntimeReaderState,
    sink: RuntimeSink,
}
impl RuntimeAcquisition {
    fn component() -> Self {
        Self {
            setup: RuntimeSetup::Pending,
            reader: RuntimeReaderState::NotSelected,
            sink: RuntimeSink::empty(),
        }
    }
    fn prepare(
        &mut self,
        lifetime: &SourceControllerLifetime,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<(), ControllerAcquisitionFault> {
        let RuntimeReaderState::Package(package) =
            std::mem::replace(&mut self.reader, RuntimeReaderState::Moving)
        else {
            self.reader = RuntimeReaderState::NotSelected;
            return Ok(());
        };
        let dimensions = package.dimensions();
        self.reader = match package.prepare_materialization::<RuntimeSinkFault>(lifetime, loans) {
            Ok(reader) => RuntimeReaderState::Prepared(reader),
            Err(failure) => {
                self.reader = RuntimeReaderState::PreparationFailed(failure);
                return Err(ControllerAcquisitionFault::Runtime);
            }
        };
        if let Err(error) = self.sink.prepare(dimensions, lifetime, loans) {
            self.setup = RuntimeSetup::Faulted(error);
            return Err(ControllerAcquisitionFault::Runtime);
        }
        self.setup = RuntimeSetup::Prepared;
        Ok(())
    }
    fn selected(&self) -> bool {
        !matches!(self.reader, RuntimeReaderState::NotSelected)
    }
    pub(super) fn outputs(
        &self,
    ) -> impl ExactSizeIterator<Item = runtime_sink::RuntimeOutputView<'_>> {
        self.sink.outputs()
    }
    pub(super) fn completed_files(&self) -> usize {
        self.sink.completed_files()
    }
    pub(super) fn observed_eofs(&self) -> usize {
        self.sink.observed_eofs()
    }
    pub(super) fn files(&self) -> impl Iterator<Item = RuntimePackageFile<'_>> {
        let RuntimeReaderState::Observed { package, .. } = &self.reader else {
            unreachable!("actual materialization result")
        };
        package.files()
    }
}

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
    Runtime,
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
        .while_business_active(|| {
            if Instant::now() >= lifetime.end() {
                return Err(ControllerAcquisitionFault::End);
            }
            action()
        })
        .map_err(ControllerAcquisitionFault::Input)?
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
    driver_written: u64,
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
            driver_written: 0,
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
    runtime: RuntimeAcquisition,
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
    pub(super) fn runtime_materialization(&self) -> Option<&RuntimeAcquisition> {
        matches!(
            self.retained.runtime.reader,
            RuntimeReaderState::Observed { .. }
        )
        .then_some(&self.retained.runtime)
    }
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
        self.retained.partial.held_files() + self.retained.runtime.sink.held_files()
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
        if !self.cleanup_owned_entries().is_complete()
            || self.retained.runtime.sink.disposal_uncertain()
        {
            return Err(self);
        }
        let Self { first, retained } = self;
        let FundedControllerAcquisition {
            lifetime,
            partial,
            mut descendants,
            runtime,
            ..
        } = retained;
        let mut runtime = runtime;
        let held = partial.held_files() + runtime.sink.release_handles();
        let descendant_handles = descendants.as_mut().map_or(0, CleanupPlan::release_handles);
        let cleanup = partial.cleanup;
        let read_bytes = partial.read_bytes;
        let eofs = partial.eofs;
        let driver_written = partial.driver_written;
        drop(partial);
        Ok(CleanedAcquisitionFailure {
            first,
            lifetime,
            cleanup,
            descendants,
            read_bytes,
            eofs,
            driver_written,
            release: SourceFileRelease::HandlesReleasedUnverified {
                handles: held + descendant_handles,
            },
            runtime,
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
    driver_written: u64,
    release: SourceFileRelease,
    runtime: RuntimeAcquisition,
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
            driver_written,
            release,
            runtime,
        } = self;
        (
            lifetime,
            AcquisitionFailureCleanupEvidence {
                first,
                cleanup,
                descendants,
                read_bytes,
                eofs,
                driver_written,
                release,
                runtime,
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
    driver_written: u64,
    release: SourceFileRelease,
    runtime: RuntimeAcquisition,
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
    _driver_written: u64,
    runtime: RuntimeAcquisition,
}
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct AcquiredControllerTarget
{
    target: AcquiredTarget,
    buffers: BrowserPhysicalBuffers,
    lifetime: SourceControllerLifetime,
    prepayment: SourceOperationPrepayment,
}
/// Actual complete selected runtime outputs with their retained filesystem and
/// source owners. This is not a host association, launch grant or BrowserRun.
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct MaterializedControllerTarget(
    AcquiredControllerTarget,
);
impl MaterializedControllerTarget {
    pub(super) fn take_business(
        &mut self,
        operation: super::source_business::SourceBusinessOperation,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<
        super::source_business::SourceBusinessCredit,
        super::super::adapter::execution_loans::BrowserActionIssueError,
    > {
        use super::super::adapter::execution_loans::BrowserActionIssueError;
        self.0
            .prepayment
            .validate(&self.0.lifetime, self.0.buffers.limits(), loans)
            .map_err(BrowserActionIssueError::Input)?;
        // Moving already-paid work is not a new reserve or a source grant.
        // Keep actual source/end currentness at this mutation too; the later
        // real consumer must independently validate its own exact affinity.
        self.0
            .lifetime
            .while_business_active(|| {
                self.0
                    .prepayment
                    .take_business(operation)
                    .map_err(BrowserActionIssueError::Funding)
            })
            .map_err(BrowserActionIssueError::Input)?
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn launch_parts(
        &self,
    ) -> (
        &AcquiredTarget,
        &SourceControllerLifetime,
        &SourceOperationPrepayment,
        Limits,
    ) {
        (
            &self.0.target,
            &self.0.lifetime,
            &self.0.prepayment,
            self.0.buffers.limits(),
        )
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn finish_unlaunched(
        self,
    ) -> Result<(SourceControllerLifetime, SourceUnlaunchedFileOutcome), Self> {
        let Self(mut owned) = self;
        if !owned.target.clean_source_entries() {
            return Err(Self(owned));
        }
        let AcquiredControllerTarget {
            target,
            lifetime,
            buffers,
            prepayment,
        } = owned;
        let files = target.release_unlaunched_source_files();
        drop((buffers, prepayment));
        Ok((lifetime, files))
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn into_parts(
        self,
    ) -> (
        AcquiredTarget,
        BrowserPhysicalParts,
        SourceControllerLifetime,
        SourceOperationPrepayment,
    ) {
        self.0.into_parts()
    }
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
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct SourceUnlaunchedFileOutcome
{
    cleanup: [EntryCleanup; 3],
    descendants: CleanupPlan,
    runtime: RuntimeAcquisition,
    release: SourceFileRelease,
    _digests: [[u8; 32]; 4],
    _actual_read_bytes: u64,
    _actual_eofs: usize,
    _driver_written: u64,
}
impl SourceUnlaunchedFileOutcome {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn release(
        &self,
    ) -> SourceFileRelease {
        self.release
    }
}
impl AcquiredTarget {
    fn clean_source_entries(&mut self) -> bool {
        let Some(owned) = self._source_owned.as_mut() else {
            return false;
        };
        let [
            CreatedEntry::Held(profile_id),
            CreatedEntry::Held(artifacts_id),
            _,
        ] = owned.entries
        else {
            return false;
        };
        owned.descendants.clean(
            &self._root,
            [&self.profile_dir, &owned._artifacts],
            [profile_id, artifacts_id],
        );
        cleanup_entries(&self._root, &mut owned.entries, &mut owned.cleanup);
        cleanup_report(&owned.entries).is_complete() && !owned.runtime.sink.disposal_uncertain()
    }
    // Only called after actual owned-entry retirement and before any process
    // exists. No fake ProcessOutcome or source acceptance is manufactured.
    fn release_unlaunched_source_files(mut self) -> SourceUnlaunchedFileOutcome {
        let SourceAcquiredOwnership {
            _core,
            _artifacts,
            _driver,
            cleanup,
            mut descendants,
            mut runtime,
            _digests,
            _actual_read_bytes,
            _actual_eofs,
            _driver_written,
            ..
        } = self._source_owned.take().expect("same source ownership");
        let handles = 8 + descendants.release_handles() + runtime.sink.release_handles();
        drop((_core, _artifacts, _driver));
        drop(self);
        SourceUnlaunchedFileOutcome {
            cleanup,
            descendants,
            runtime,
            release: SourceFileRelease::HandlesReleasedUnverified { handles },
            _digests,
            _actual_read_bytes,
            _actual_eofs,
            _driver_written,
        }
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn finish_unlaunched(
        mut self,
    ) -> Result<SourceUnlaunchedFileOutcome, Self> {
        if !self.clean_source_entries() {
            return Err(self);
        }
        Ok(self.release_unlaunched_source_files())
    }
}
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct SourceControllerFileOutcome
{
    chromium: ProcessOutcome,
    driver: Driver,
    first_fault: Option<ControllerFault>,
    cleanup: [EntryCleanup; 3],
    release: SourceFileRelease,
    descendants: CleanupPlan,
    runtime: RuntimeAcquisition,
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
        match &self.driver {
            Driver::Finished(outcome) => Some(outcome),
            _ => None,
        }
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
        if !cleanup_report(&owned.entries).is_complete() || owned.runtime.sink.disposal_uncertain()
        {
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
        // The completed owner also retains a genuinely unstarted/pre-child
        // refused driver's backing and exact cause. No process is invented.
        assert!(matches!(
            driver,
            Driver::Finished(_)
                | Driver::NotStarted
                | Driver::Prepared { .. }
                | Driver::SpawnRefused { .. }
        ));
        // Eight actual File fields in source-acquired target: executables2,
        // root/index/profile3 and core/artifacts/driver3. Never caller rootdir.
        let SourceAcquiredOwnership {
            _core,
            _artifacts,
            _driver,
            mut descendants,
            runtime,
            ..
        } = target._source_owned.take().expect("same source owner");
        let descendant_handles = descendants.release_handles();
        let mut runtime = runtime;
        let runtime_handles = runtime.sink.release_handles();
        drop((_core, _artifacts, _driver));
        drop(target);
        Ok(SourceControllerFileOutcome {
            chromium,
            driver,
            first_fault,
            cleanup,
            release: SourceFileRelease::HandlesReleasedUnverified {
                handles: 8 + descendant_handles + runtime_handles,
            },
            descendants,
            runtime,
        })
    }
}
const FILE_WINDOW: usize = 65536;
fn file_windows(bytes: usize) -> Result<usize, ControllerAcquisitionFault> {
    Ok(checked_add(bytes, FILE_WINDOW - 1)? / FILE_WINDOW)
}
fn file_partial_work() -> Result<usize, ControllerAcquisitionFault> {
    // Actual original-end samples, positions/counts, borrowed I/O span and return
    // value. This bounds source-visible work, not compiler stack or VM copies.
    checked_add(
        checked_add(
            2 * size_of::<Instant>(),
            size_of::<u64>() + 2 * size_of::<usize>(),
        )?,
        size_of::<io::Result<usize>>() + size_of::<&mut [u8]>(),
    )
}
fn file_guard_work() -> Result<usize, ControllerAcquisitionFault> {
    super::super::adapter::execution_loans::SourceControllerActivity::validation_work_upper()
        .ok_or(ControllerAcquisitionFault::Overflow)
}
fn check_file_end(lifetime: &SourceControllerLifetime) -> Result<(), ControllerAcquisitionFault> {
    if Instant::now() >= lifetime.end() {
        Err(ControllerAcquisitionFault::End)
    } else {
        Ok(())
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
        Self::prepare_with_runtime(
            input,
            limits,
            lifetime,
            loans,
            RuntimeAcquisition::component(),
        )
    }
    fn prepare_with_runtime(
        input: ControllerTargetInput<'_>,
        limits: Limits,
        lifetime: SourceControllerLifetime,
        loans: &mut BrowserLoans<'_, '_>,
        runtime: RuntimeAcquisition,
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
            runtime,
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
            let windows = prepared
                .lengths
                .into_iter()
                .try_fold(0usize, |sum, length| {
                    checked_add(
                        sum,
                        file_windows(
                            usize::try_from(length)
                                .map_err(|_| ControllerAcquisitionFault::Overflow)?,
                        )?,
                    )
                })?;
            let partial_calls = prepared.lengths.into_iter().try_fold(
                checked_add(DRIVER.len(), 1)?,
                |sum, length| {
                    checked_add(
                        sum,
                        checked_add(
                            usize::try_from(length)
                                .map_err(|_| ControllerAcquisitionFault::Overflow)?,
                            1,
                        )?,
                    )
                },
            )?;
            // Explicit preparation, held path/metadata, create, two guards per
            // hash window, actual EOF and driver-write window boundaries.
            let fixed_guards = checked_add(
                checked_add(
                    2 * source_paths.len() + 2 * NAMES.len() + 2 + 2,
                    source_paths.len() * 2 + 3 * 2 + 2 + 4 + 3 + 3,
                )?,
                file_windows(DRIVER.len())?,
            )?;
            let guard_calls = checked_add(
                checked_add(fixed_guards, components)?,
                windows
                    .checked_mul(2)
                    .ok_or(ControllerAcquisitionFault::Overflow)?,
            )?;
            let guard_work = guard_calls
                .checked_mul(file_guard_work()?)
                .ok_or(ControllerAcquisitionFault::Overflow)?;
            let partial_work = partial_calls
                .checked_mul(file_partial_work()?)
                .ok_or(ControllerAcquisitionFault::Overflow)?;
            let io_work = checked_add(guard_work, partial_work)?;
            #[cfg(test)]
            eprintln!(
                "source filesystem work: guards={guard_calls},guard_bytes={},partials={partial_calls},partial_bytes={},total={io_work}",
                file_guard_work()?,
                file_partial_work()?
            );
            loans
                .reserve_controlled_host_storage(0, 0, io_work)
                .map_err(ControllerAcquisitionFault::Input)?;
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
            prepared.runtime.prepare(&prepared.lifetime, loans)?;
            prepared.descendants = Some(CleanupPlan::prepare(&prepared.lifetime, loans)?);
            if let RuntimeReaderState::Prepared(reader) = &prepared.runtime.reader {
                prepared
                    .descendants
                    .as_ref()
                    .expect("retained cleanup plan")
                    .require_runtime_capacity(reader.dimensions())?;
            }
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
            while self.partial.driver_written < DRIVER.len() as u64 {
                let request = ((DRIVER.len() as u64 - self.partial.driver_written)
                    .min(FILE_WINDOW as u64)) as usize;
                let base = self.partial.driver_written;
                active(&self.lifetime, || {
                    let mut filled = 0;
                    while filled < request {
                        check_file_end(&self.lifetime)?;
                        let count = self.partial.created_files[index]
                            .as_ref()
                            .unwrap()
                            .write_at(
                                &DRIVER[base as usize + filled..base as usize + request],
                                base + filled as u64,
                            )
                            .map_err(|e| ControllerAcquisitionFault::Io(e.kind()))?;
                        self.partial.driver_written += count as u64;
                        if count == 0 {
                            return Err(ControllerAcquisitionFault::Io(io::ErrorKind::WriteZero));
                        }
                        filled += count;
                    }
                    Ok(())
                })?;
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
                let mut filled = 0;
                while filled < request {
                    check_file_end(&self.lifetime)?;
                    let count = file
                        .read_at(&mut scratch[filled..request], offset + filled as u64)
                        .map_err(|e| ControllerAcquisitionFault::Io(e.kind()))?;
                    self.partial.read_bytes += count as u64;
                    if count == 0 {
                        self.partial.eofs += 1;
                        return Err(ControllerAcquisitionFault::Length {
                            declared: self.lengths[index],
                            actual: offset + filled as u64,
                        });
                    }
                    filled += count;
                }
                Ok(filled)
            })?;
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
            if self.runtime.selected() {
                return Err(ControllerAcquisitionFault::Shape);
            }
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
        Ok(self.into_acquired(digests))
    }
    fn into_acquired(mut self, digests: [[u8; 32]; 4]) -> AcquiredControllerTarget {
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
                _driver_written: self.partial.driver_written,
                runtime: self.runtime,
            }),
        };
        AcquiredControllerTarget {
            target,
            buffers: self.buffers.take().unwrap(),
            lifetime: self.lifetime,
            prepayment: self
                .prepayment
                .take()
                .expect("same known-operation prepayment"),
        }
    }
}

#[cfg(test)]
#[path = "acquisition/runtime_tests.rs"]
mod runtime_tests;

impl FundedControllerAcquisition {
    pub(super) fn prepare_selected(
        input: SelectedControllerTargetInput<'_>,
        limits: Limits,
        lifetime: SourceControllerLifetime,
        package: SelectedRuntimePackage,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<Self, ControllerAcquisitionFailure> {
        // Only validated SAME source/End may pay/copy paths. Derived fixed paths are
        // ordinary DATA until held no-follow acquisition/materialization observes them.
        let paths = (|| {
            lifetime
                .validate(loans)
                .map_err(ControllerAcquisitionFault::Input)?;
            package
                .validate(&lifetime, loans)
                .map_err(|_| ControllerAcquisitionFault::Runtime)?;
            let d = package.dimensions();
            let paths = checked_add(
                input
                    .root
                    .as_os_str()
                    .len()
                    .checked_mul(2)
                    .ok_or(ControllerAcquisitionFault::Overflow)?,
                "/artifacts/runtime/lib/coreBundle.js".len() + "/artifacts/runtime/index.mjs".len(),
            )?;
            let scan = d
                .file_count()
                .checked_mul(checked_add(
                    d.max_path_bytes()
                        .checked_mul(2)
                        .ok_or(ControllerAcquisitionFault::Overflow)?,
                    size_of::<RuntimePackageFile<'_>>(),
                )?)
                .ok_or(ControllerAcquisitionFault::Overflow)?;
            loans
                .reserve_controlled_host_storage(
                    checked_add(paths, 2 * size_of::<PathBuf>() + size_of::<Self>())?,
                    2,
                    checked_add(paths, scan)?,
                )
                .map_err(ControllerAcquisitionFault::Input)?;
            if !valid_path(input.root) {
                return Err(ControllerAcquisitionFault::Shape);
            }
            let core = copy_path(
                input.root,
                Some("artifacts/runtime/lib/coreBundle.js"),
                &lifetime,
                loans,
            )?;
            let entry = copy_path(
                input.root,
                Some("artifacts/runtime/index.mjs"),
                &lifetime,
                loans,
            )?;
            let core_length = package
                .files()
                .find(|f| f.path() == "lib/coreBundle.js")
                .ok_or(ControllerAcquisitionFault::Package)?
                .byte_length();
            let entry_length = package
                .files()
                .find(|f| f.path() == "index.mjs")
                .ok_or(ControllerAcquisitionFault::Package)?
                .byte_length();
            Ok((core, entry, core_length, entry_length))
        })();
        let runtime = RuntimeAcquisition {
            setup: RuntimeSetup::Pending,
            reader: RuntimeReaderState::Package(package),
            sink: RuntimeSink::empty(),
        };
        let (core, entry, core_length, entry_length) = match paths {
            Ok(paths) => paths,
            Err(first) => {
                return Err(ControllerAcquisitionFailure {
                    first,
                    retained: Self {
                        lifetime,
                        paths: std::array::from_fn(|_| PathBuf::new()),
                        created_paths: std::array::from_fn(|_| PathBuf::new()),
                        lengths: [0; 4],
                        buffers: None,
                        partial: PartialAcquisition::empty(),
                        scratch: None,
                        descendants: None,
                        prepayment: None,
                        runtime,
                    },
                });
            }
        };
        Self::prepare_with_runtime(
            ControllerTargetInput {
                chromium: input.chromium,
                node: input.node,
                core_bundle: ControllerFileInput {
                    path: &core,
                    byte_length: core_length,
                },
                entry: ControllerFileInput {
                    path: &entry,
                    byte_length: entry_length,
                },
                root: input.root,
            },
            limits,
            lifetime,
            loans,
            runtime,
        )
    }
    pub(super) fn acquire_selected(
        mut self,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<MaterializedControllerTarget, ControllerAcquisitionFailure> {
        let result = (|| {
            self.lifetime
                .validate(loans)
                .map_err(ControllerAcquisitionFault::Input)?;
            if !matches!(self.runtime.reader, RuntimeReaderState::Prepared(_)) {
                return Err(ControllerAcquisitionFault::Shape);
            }
            for index in [4, 0, 1] {
                self.walk(index)?;
            }
            self.create(0)?;
            self.create(1)?;
            let node = self.digest(1)?;
            if node != NODE {
                return Err(ControllerAcquisitionFault::Clock);
            }
            let chromium = self.digest(0)?;
            if let Err(error) = self.runtime.sink.start(
                self.partial.created_files[1].as_ref().unwrap(),
                &self.lifetime,
            ) {
                self.runtime.setup = RuntimeSetup::Faulted(error);
                return Err(ControllerAcquisitionFault::Runtime);
            }
            self.runtime.setup = RuntimeSetup::Started;
            let RuntimeReaderState::Prepared(reader) =
                std::mem::replace(&mut self.runtime.reader, RuntimeReaderState::Moving)
            else {
                unreachable!()
            };
            let result = reader.materialize(loans, |file, source| {
                self.runtime.sink.write_entry(file, source, &self.lifetime)
            });
            let (package, read, sink) = result.into_parts();
            let expected = package.dimensions().file_count();
            let complete = matches!(&read,RuntimeArchiveReadTerminal::Complete{files,..} if *files==expected)
                && matches!(&sink,RuntimeSinkTerminal::Returned{entries} if *entries==expected);
            self.runtime.reader = RuntimeReaderState::Observed {
                package,
                read,
                sink,
            };
            if !complete || self.runtime.sink.disposal_uncertain() {
                return Err(ControllerAcquisitionFault::Runtime);
            }
            let core = self
                .runtime
                .sink
                .verified_digest("lib/coreBundle.js")
                .ok_or(ControllerAcquisitionFault::Runtime)?;
            let entry = self
                .runtime
                .sink
                .verified_digest("index.mjs")
                .ok_or(ControllerAcquisitionFault::Runtime)?;
            self.partial.files[2] = Some(
                self.runtime
                    .sink
                    .take_verified("lib/coreBundle.js")
                    .map_err(|_| ControllerAcquisitionFault::Runtime)?,
            );
            self.partial.files[3] = Some(
                self.runtime
                    .sink
                    .take_verified("index.mjs")
                    .map_err(|_| ControllerAcquisitionFault::Runtime)?,
            );
            self.create(2)?;
            active(&self.lifetime, || Ok(()))?;
            Ok([chromium, node, core, entry])
        })();
        match result {
            Ok(digests) => Ok(MaterializedControllerTarget(self.into_acquired(digests))),
            Err(first) => Err(ControllerAcquisitionFailure {
                first,
                retained: self,
            }),
        }
    }
}

#[cfg(test)]
#[path = "acquisition/runtime_canary_tests.rs"]
mod runtime_canary_tests;
