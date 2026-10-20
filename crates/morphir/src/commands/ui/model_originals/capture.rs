use super::{domain::*, record};
mod reads;
use crate::commands::ui::artifacts::portable_path_key;
use cap_fs_ext::{DirExt, FollowSymlinks, OpenOptionsFollowExt, OpenOptionsSyncExt};
use cap_std::fs::{Dir, OpenOptions};
use morphir_distribution::Sha256Digest;
use reads::{
    CaptureArea, CaptureFile, CaptureFileOpenError, CaptureReads, open_directory, open_file,
};
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    io::{Read, Write},
    path::Path,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};

/// Cooperative deadline/cancellation. A blocking OS read cannot be forcibly
/// interrupted; its caller must keep any host credit until this worker exits.
#[derive(Clone)]
pub struct CaptureControl {
    cancelled: Arc<AtomicBool>,
    notification: Arc<tokio::sync::Notify>,
    deadline: Instant,
    #[cfg(test)]
    read_boundary_hook: Option<Arc<dyn Fn(CaptureReadBoundary) + Send + Sync>>,
}
#[cfg(test)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum CaptureReadBoundary {
    AfterMetadataBeforeData,
    AfterDataBeforeRead,
}
impl Default for CaptureControl {
    fn default() -> Self {
        Self::new()
    }
}
impl CaptureControl {
    pub fn new() -> Self {
        Self {
            cancelled: Arc::new(AtomicBool::new(false)),
            notification: Arc::new(tokio::sync::Notify::new()),
            deadline: Instant::now() + Duration::from_secs(30),
            #[cfg(test)]
            read_boundary_hook: None,
        }
    }
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Relaxed);
        self.notification.notify_waiters();
    }
    #[cfg(test)]
    fn with_read_boundary_hook(
        mut self,
        hook: Arc<dyn Fn(CaptureReadBoundary) + Send + Sync>,
    ) -> Self {
        self.read_boundary_hook = Some(hook);
        self
    }
    #[cfg(test)]
    fn read_boundary(&self, boundary: CaptureReadBoundary) {
        if let Some(hook) = &self.read_boundary_hook {
            hook(boundary);
        }
    }
    #[cfg(test)]
    pub(super) fn with_timeout(timeout: Duration) -> Self {
        let mut control = Self::new();
        control.deadline = Instant::now() + timeout;
        control
    }
    pub(super) fn check(&self) -> Result<(), CaptureError> {
        if self.cancelled.load(Ordering::Relaxed) || Instant::now() >= self.deadline {
            Err(CaptureError::Timeout)
        } else {
            Ok(())
        }
    }
    pub(super) fn deadline(&self) -> Instant {
        self.deadline
    }
    pub(super) async fn cancelled(&self) {
        let notified = self.notification.notified();
        tokio::pin!(notified);
        notified.as_mut().enable();
        if self.cancelled.load(Ordering::Relaxed) {
            return;
        }
        notified.await;
    }
}

/// Reservation boundary for retained copies. Temporary raw-record input has its
/// own bounded active-worker budget and never escapes into a retained capture.
pub(super) trait CaptureAccounting {
    fn source(&mut self, bytes: usize) -> Result<(), CaptureError>;
    fn metadata(&mut self, bytes: usize) -> Result<(), CaptureError>;
    fn record(&mut self, raw: Vec<u8>) -> Result<(), CaptureError> {
        drop(raw);
        Ok(())
    }
}
struct PerCaptureOnly;
impl CaptureAccounting for PerCaptureOnly {
    fn source(&mut self, _: usize) -> Result<(), CaptureError> {
        Ok(())
    }
    fn metadata(&mut self, _: usize) -> Result<(), CaptureError> {
        Ok(())
    }
}
#[derive(Clone, Copy)]
pub(super) struct Limits {
    pub source: usize,
    pub record: usize,
    pub metadata: usize,
    pub descendants: usize,
}
impl Default for Limits {
    fn default() -> Self {
        Self {
            source: MAX_SOURCE_BYTES,
            record: MAX_RECORD_BYTES,
            metadata: MAX_METADATA_BYTES,
            descendants: MAX_DESCENDANTS,
        }
    }
}

pub fn capture_compiled(
    output: &Dir,
    module: &SelectedModule,
    scope: CaptureScope,
    control: &CaptureControl,
) -> Result<CaptureResult, CaptureError> {
    capture_with_limits(output, module, scope, control, Limits::default())
}
pub(super) fn capture_with_limits(
    output: &Dir,
    module: &SelectedModule,
    scope: CaptureScope,
    control: &CaptureControl,
    limits: Limits,
) -> Result<CaptureResult, CaptureError> {
    capture_accounted(output, module, scope, control, limits, &mut PerCaptureOnly)
}
pub(super) fn capture_accounted(
    output: &Dir,
    module: &SelectedModule,
    scope: CaptureScope,
    control: &CaptureControl,
    limits: Limits,
    accounting: &mut dyn CaptureAccounting,
) -> Result<CaptureResult, CaptureError> {
    capture_with_reads(
        output,
        module,
        scope,
        control,
        limits,
        accounting,
        CaptureReads::Historical,
    )
}
pub(super) fn capture_resolved_accounted(
    resolved: &crate::commands::ui::provider::originals::ResolvedProjectSource,
    scope: CaptureScope,
    control: &CaptureControl,
    limits: Limits,
    accounting: &mut dyn CaptureAccounting,
) -> Result<CaptureResult, CaptureError> {
    let reads = match resolved.source_observation() {
        Some(source) => CaptureReads::Observed {
            source,
            binding: resolved.content_binding(),
            module: resolved.module(),
        },
        None => CaptureReads::Historical,
    };
    capture_with_reads(
        resolved.output(),
        resolved.module(),
        scope,
        control,
        limits,
        accounting,
        reads,
    )
}
fn capture_with_reads(
    output: &Dir,
    module: &SelectedModule,
    scope: CaptureScope,
    control: &CaptureControl,
    limits: Limits,
    accounting: &mut dyn CaptureAccounting,
    reads: CaptureReads<'_>,
) -> Result<CaptureResult, CaptureError> {
    control.check()?;
    let directory = match open_directory(output, Path::new(module.as_str())) {
        Ok(dir) => dir,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Ok(CaptureResult::Unavailable(CaptureUnavailable::NotCompiled));
        }
        Err(_) => return Err(CaptureError::CaptureFailed),
    };
    let mut options = OpenOptions::new();
    options
        .read(true)
        .write(true)
        .create(true)
        .follow(FollowSymlinks::No)
        .nonblock(true);
    let lock = directory
        .open_with("compile.lock", &options)
        .map_err(io_error)?
        .into_std();
    if !lock.metadata().map_err(io_error)?.is_file() {
        return Err(CaptureError::CaptureFailed);
    }
    loop {
        control.check()?;
        match fs2::FileExt::try_lock_shared(&lock) {
            Ok(()) => break,
            Err(error) if crate::commands::out_context::is_contended(&error) => {
                std::thread::sleep(Duration::from_millis(10))
            }
            Err(_) => return Err(CaptureError::CaptureFailed),
        }
    }
    let raw_file = match open_file(
        &directory,
        Path::new("compile.json"),
        reads,
        CaptureArea::Module,
        control,
    ) {
        Ok(file) => file,
        Err(error) if error.is_not_found() => {
            return Ok(CaptureResult::Unavailable(CaptureUnavailable::NotCompiled));
        }
        Err(error) => return Err(error.into_capture_error()),
    };
    let raw = read_bounded(
        raw_file,
        limits.record,
        CaptureError::RecordLimit,
        control,
        |_| Ok(()),
    )?;
    let (record, declaration) = record::decode(&raw, module, scope)?;
    let primary = record.descriptor.primary()?;
    let companions = match (scope, declaration) {
        (CaptureScope::Primary, _) => vec![],
        (_, Declaration::Absent) => {
            return Ok(CaptureResult::Unavailable(
                CaptureUnavailable::CompanionsUndeclared,
            ));
        }
        (_, Declaration::Invalid) => return Err(CaptureError::InvalidDeclaration),
        (_, Declaration::Declared(roots)) => roots,
    };
    let roots: Vec<_> = std::iter::once(&primary).chain(companions.iter()).collect();
    validate_roots(&roots)?;
    let dest = directory
        .open_dir_nofollow("compile.dest")
        .map_err(io_error)?;
    let mut builder = Builder {
        entries: vec![],
        source_left: limits.source,
        metadata_left: limits.metadata,
        descendants_left: limits.descendants,
        paths: PathSet::default(),
        control,
        accounting,
        reads,
    };
    for root in roots {
        builder.metadata(root)?;
        builder.walk(&dest, &root.path, root.kind, 0)?;
    }
    control.check()?;
    // Drop the shared lock only after all record/descriptor/originals are owned.
    drop(lock);
    builder
        .entries
        .sort_by(|left, right| left.path.cmp(&right.path));
    let inventory_digest = inventory_digest(&builder.entries);
    control.check()?;
    // Historical callers discard the temporary record. The private observed
    // caller moves this SAME worker allocation into its actual credited slot.
    builder.accounting.record(raw)?;
    Ok(CaptureResult::Ready(Box::new(CapturedSources {
        record,
        primary,
        companions,
        scope,
        entries: builder.entries,
        source_bytes: limits.source - builder.source_left,
        metadata_bytes: limits.metadata - builder.metadata_left,
        inventory_digest,
        source_version: SourceVersionEvidence::NotReported,
    })))
}
fn io_error(_: std::io::Error) -> CaptureError {
    CaptureError::CaptureFailed
}
fn read_bounded(
    mut file: CaptureFile<'_>,
    limit: usize,
    excess: CaptureError,
    control: &CaptureControl,
    mut reserve: impl FnMut(usize) -> Result<(), CaptureError>,
) -> Result<Vec<u8>, CaptureError> {
    let metadata = file.metadata().map_err(io_error)?;
    if !metadata.is_file() {
        return Err(CaptureError::CaptureFailed);
    }
    if metadata.len() > limit as u64 {
        return Err(excess);
    }
    let mut bytes = Vec::new();
    let mut block = [0u8; 65_536];
    loop {
        control.check()?;
        // Include one over-budget probe without allocating it in the owner.
        let count = file
            .read(&mut block[..65_536.min(limit - bytes.len() + 1)])
            .map_err(io_error)?;
        if count == 0 {
            break;
        }
        if count > limit - bytes.len() {
            return Err(excess);
        }
        reserve(count)?;
        bytes.extend_from_slice(&block[..count]);
    }
    Ok(bytes)
}

fn validate_roots(roots: &[&SourceRoot]) -> Result<(), CaptureError> {
    if roots.len() > MAX_ROOTS {
        return Err(CaptureError::InventoryLimit);
    }
    let mut paths = PathSet::default();
    for root in roots {
        paths.insert(&root.path, root.kind)?;
    }
    // Even directory roots cannot contain another independently selected root.
    let keys: BTreeSet<_> = roots
        .iter()
        .map(|root| portable_path_key(root.path.as_str()))
        .collect();
    for key in &keys {
        for (separator, _) in key.match_indices('/') {
            if keys.contains(&key[..separator]) {
                return Err(CaptureError::InvalidPathSet);
            }
        }
    }
    Ok(())
}
#[derive(Default)]
struct PathSet {
    roots: Trie,
    full_paths: BTreeMap<String, SourceKind>,
}
#[derive(Default)]
struct Trie {
    children: BTreeMap<String, (String, Trie)>,
    kind: Option<SourceKind>,
}
impl PathSet {
    fn insert(&mut self, path: &SourcePath, kind: SourceKind) -> Result<(), CaptureError> {
        let key = portable_path_key(path.as_str());
        if self.full_paths.contains_key(&key) {
            return Err(CaptureError::InvalidPathSet);
        }
        for (separator, _) in key.match_indices('/') {
            if self.full_paths.get(&key[..separator]) == Some(&SourceKind::File) {
                return Err(CaptureError::InvalidPathSet);
            }
        }
        if kind == SourceKind::File {
            let prefix = format!("{key}/");
            if self
                .full_paths
                .range(prefix.clone()..)
                .next()
                .is_some_and(|(next, _)| next.starts_with(&prefix))
            {
                return Err(CaptureError::InvalidPathSet);
            }
        }
        let mut node = &mut self.roots;
        for part in path.as_str().split('/') {
            if node.kind == Some(SourceKind::File) {
                return Err(CaptureError::InvalidPathSet);
            }
            let (prior, next) = node
                .children
                .entry(portable_path_key(part))
                .or_insert_with(|| (part.to_owned(), Trie::default()));
            if prior != part {
                return Err(CaptureError::InvalidPathSet);
            }
            node = next;
        }
        if node.kind.is_some() || (kind == SourceKind::File && !node.children.is_empty()) {
            return Err(CaptureError::InvalidPathSet);
        }
        node.kind = Some(kind);
        self.full_paths.insert(key, kind);
        Ok(())
    }
}

struct Builder<'a> {
    reads: CaptureReads<'a>,
    entries: Vec<SourceEntry>,
    source_left: usize,
    metadata_left: usize,
    descendants_left: usize,
    paths: PathSet,
    control: &'a CaptureControl,
    accounting: &'a mut dyn CaptureAccounting,
}
impl Builder<'_> {
    fn metadata(&mut self, value: &impl Serialize) -> Result<(), CaptureError> {
        struct Counter<'a>(&'a mut usize);
        impl Write for Counter<'_> {
            fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
                *self.0 = self
                    .0
                    .checked_sub(bytes.len())
                    .ok_or_else(|| std::io::Error::other("inventory limit"))?;
                Ok(bytes.len())
            }
            fn flush(&mut self) -> std::io::Result<()> {
                Ok(())
            }
        }
        let mut remaining = self.metadata_left;
        serde_json::to_writer(Counter(&mut remaining), value)
            .map_err(|_| CaptureError::InventoryLimit)?;
        self.accounting.metadata(self.metadata_left - remaining)?;
        self.metadata_left = remaining;
        Ok(())
    }
    fn walk(
        &mut self,
        dest: &Dir,
        path: &SourcePath,
        kind: SourceKind,
        depth: usize,
    ) -> Result<(), CaptureError> {
        self.control.check()?;
        if depth > 128 || self.entries.len() == MAX_ENTRIES {
            return Err(CaptureError::InventoryLimit);
        }
        let id = uuid::Uuid::new_v4().to_string();
        let content = match kind {
            SourceKind::File => {
                let bytes = read_bounded(
                    open_file(
                        dest,
                        Path::new(path.as_str()),
                        self.reads,
                        CaptureArea::Destination,
                        self.control,
                    )
                    .map_err(CaptureFileOpenError::into_capture_error)?,
                    self.source_left,
                    CaptureError::SourceLimit,
                    self.control,
                    |bytes| self.accounting.source(bytes),
                )?;
                self.source_left -= bytes.len();
                SourceContent::File {
                    digest: Sha256Digest::of_bytes(&bytes),
                    bytes,
                }
            }
            SourceKind::Directory => SourceContent::Directory,
        };
        // Charge the exact compact entry metadata, including generated identity,
        // before retaining the entry. Original file content never enters JSON.
        #[derive(Serialize)]
        #[serde(
            tag = "kind",
            rename_all = "lowercase",
            rename_all_fields = "camelCase"
        )]
        enum EntryMetadata<'a> {
            Directory {
                entry_id: &'a str,
                path: &'a SourcePath,
            },
            File {
                entry_id: &'a str,
                path: &'a SourcePath,
                byte_length: usize,
                sha256: &'a Sha256Digest,
            },
        }
        let metadata = match &content {
            SourceContent::Directory => EntryMetadata::Directory {
                entry_id: &id,
                path,
            },
            SourceContent::File { bytes, digest } => EntryMetadata::File {
                entry_id: &id,
                path,
                byte_length: bytes.len(),
                sha256: digest,
            },
        };
        self.metadata(&metadata)?;
        self.paths.insert(path, kind)?;
        self.entries.push(SourceEntry {
            id,
            path: path.clone(),
            content,
        });
        if kind == SourceKind::Directory {
            let directory = open_directory(dest, Path::new(path.as_str())).map_err(io_error)?;
            for child in directory.entries().map_err(io_error)? {
                self.control.check()?;
                self.descendants_left = self
                    .descendants_left
                    .checked_sub(1)
                    .ok_or(CaptureError::InventoryLimit)?;
                let child = child.map_err(io_error)?;
                let name = child.file_name();
                let name = name.to_str().ok_or(CaptureError::InvalidPath)?;
                let child_path = SourcePath::parse(&format!("{}/{name}", path.as_str()))?;
                let file_type = child.file_type().map_err(io_error)?;
                let child_kind = if file_type.is_dir() {
                    SourceKind::Directory
                } else if file_type.is_file() {
                    SourceKind::File
                } else {
                    return Err(CaptureError::CaptureFailed);
                };
                self.walk(dest, &child_path, child_kind, depth + 1)?;
            }
        }
        Ok(())
    }
}
fn inventory_digest(entries: &[SourceEntry]) -> Sha256Digest {
    let mut hash = Sha256::new();
    hash.update(b"morphir/workbench/model-originals/0.1.0-draft.1\0");
    hash.update((entries.len() as u32).to_be_bytes());
    for entry in entries {
        hash.update([if entry.kind() == SourceKind::Directory {
            0
        } else {
            1
        }]);
        hash.update((entry.path.as_str().len() as u32).to_be_bytes());
        hash.update(entry.path.as_str().as_bytes());
        if let SourceContent::File { bytes, digest } = &entry.content {
            hash.update((bytes.len() as u64).to_be_bytes());
            hash.update(digest.as_bytes());
        }
    }
    Sha256Digest::from_bytes(hash.finalize().into())
}

#[cfg(test)]
mod cancellation_tests;

#[cfg(test)]
mod output_route_tests;

#[cfg(test)]
mod private_record_tests;

#[cfg(test)]
mod installed_host_tests;
