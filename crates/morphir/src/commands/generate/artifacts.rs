use crate::error::CliError;
use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use cap_fs_ext::{DirExt, FollowSymlinks, OpenOptionsFollowExt};
use cap_std::fs::{Dir, OpenOptions};
use morphir_extension_sdk::Artifact;
use std::collections::{BTreeMap, BTreeSet};
use std::ffi::{OsStr, OsString};
use std::io::{self, Read, Write};
use std::path::{Component, Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT_TRANSACTION_ID: AtomicU64 = AtomicU64::new(0);
const MANIFEST_PATH: &str = ".morphir-generated-artifacts.json";
const MANIFEST_SCHEMA_VERSION: u32 = 1;

pub(super) fn write_all(
    output_root: &Path,
    artifacts: &[Artifact],
) -> Result<Vec<String>, CliError> {
    ArtifactWriter::new(output_root).write_all(artifacts)
}

/// Publishes one returned artifact set with in-process failure rollback.
///
/// Staged files and destination operations are capability-relative and synced
/// where supported. This is not crash-atomic: a process or machine failure can
/// leave the retained transaction directory for manual recovery.
struct ArtifactWriter<'a, H: ArtifactHooks + ?Sized = NoopHooks> {
    output_root: &'a Path,
    hooks: &'a H,
}

impl<'a> ArtifactWriter<'a, NoopHooks> {
    fn new(output_root: &'a Path) -> Self {
        Self {
            output_root,
            hooks: &NOOP_HOOKS,
        }
    }
}

impl<'a, H: ArtifactHooks + ?Sized> ArtifactWriter<'a, H> {
    #[cfg(test)]
    fn with_ops(output_root: &'a Path, hooks: &'a H) -> Self {
        Self { output_root, hooks }
    }

    fn write_all(&self, artifacts: &[Artifact]) -> Result<Vec<String>, CliError> {
        let mut validated = validate_complete_set(artifacts)?;
        let display_paths = validated
            .iter()
            .map(|artifact| artifact.display_path.clone())
            .collect::<Vec<_>>();
        let root = acquire_output_root(self.output_root, self.hooks).map_err(file_system_error)?;
        let previous = load_manifest(&root.directory)?;
        if validated.is_empty() && previous.is_none() {
            remove_created_output_directories(&root.created);
            return Ok(Vec::new());
        }
        let current_paths = display_paths.iter().cloned().collect::<BTreeSet<_>>();
        let stale = previous
            .unwrap_or_default()
            .into_iter()
            .filter(|artifact| !current_paths.contains(&artifact.display_path))
            .collect::<Vec<_>>();
        validated.push(manifest_artifact(&display_paths)?);
        let result = self.run(&root.directory, &validated, &stale);
        if result.is_err() {
            remove_created_output_directories(&root.created);
        }
        result.map(|()| display_paths)
    }

    fn run(
        &self,
        root: &Dir,
        artifacts: &[ValidatedArtifact],
        stale: &[ValidatedRemoval],
    ) -> Result<(), CliError> {
        let transaction = create_transaction(root).map_err(file_system_error)?;
        let recovery_path = self.output_root.join(&transaction.relative_path);
        let result = run_transaction(root, &transaction.directory, artifacts, stale, self.hooks);
        match result {
            // All destination files are installed and synced here. This is the
            // publication commit point; subsequent maintenance never rolls them back.
            Ok(()) => finish_committed_transaction(
                root,
                transaction.directory,
                &recovery_path,
                self.hooks,
            ),
            Err(TransactionFailure::RolledBack(error)) => {
                let cleanup = transaction.directory.remove_open_dir_all();
                let error = cleanup
                    .err()
                    .map(|cleanup| io::Error::other(format!("{error}; cleanup failed: {cleanup}")))
                    .unwrap_or(error);
                Err(file_system_error(error))
            }
            Err(TransactionFailure::RecoveryRequired(error)) => {
                Err(file_system_error(io::Error::other(format!(
                    "{error}; artifact backup preserved at '{}'",
                    recovery_path.display()
                ))))
            }
        }
    }
}

struct Transaction {
    directory: Dir,
    relative_path: PathBuf,
}

struct Destination {
    parent: Dir,
    relative_path: PathBuf,
    leaf: OsString,
    staged: Option<PathBuf>,
    backup: PathBuf,
    rollback: PathBuf,
    hook_index: Option<usize>,
}

struct CommitRecord {
    index: usize,
    backup: bool,
    installed: bool,
}

enum TransactionFailure {
    RolledBack(io::Error),
    RecoveryRequired(io::Error),
}

trait ArtifactHooks {
    fn before_output_component_open(&self, _parent: &Dir, _leaf: &OsStr) -> io::Result<()> {
        Ok(())
    }

    fn before_stage(&self, _index: usize) -> io::Result<()> {
        Ok(())
    }

    fn after_backup_move(&self, _index: usize) -> io::Result<()> {
        Ok(())
    }

    fn before_install(&self, _index: usize, _parent: &Dir, _leaf: &OsStr) -> io::Result<()> {
        Ok(())
    }

    fn before_rollback(&self, _index: usize) -> io::Result<()> {
        Ok(())
    }

    fn before_post_commit_root_sync(&self) -> io::Result<()> {
        Ok(())
    }

    fn before_post_commit_cleanup(&self) -> io::Result<()> {
        Ok(())
    }
}

struct NoopHooks;
static NOOP_HOOKS: NoopHooks = NoopHooks;
impl ArtifactHooks for NoopHooks {}

struct AcquiredOutputRoot {
    directory: Dir,
    created: Vec<CreatedOutputDirectory>,
}

struct CreatedOutputDirectory {
    parent: Dir,
    leaf: OsString,
}

fn acquire_output_root<H: ArtifactHooks + ?Sized>(
    output_root: &Path,
    hooks: &H,
) -> io::Result<AcquiredOutputRoot> {
    let (anchor, components) = output_root_anchor(output_root)?;
    let mut current = anchor;
    let mut created = Vec::new();

    for component in components {
        hooks.before_output_component_open(&current, &component)?;
        current = match current.open_dir_nofollow(&component) {
            Ok(directory) => directory,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                let parent = match current.try_clone() {
                    Ok(parent) => parent,
                    Err(error) => {
                        remove_created_output_directories(&created);
                        return Err(error);
                    }
                };
                let newly_created = match current.create_dir(&component) {
                    Ok(()) => true,
                    Err(error) if error.kind() == io::ErrorKind::AlreadyExists => false,
                    Err(error) => {
                        remove_created_output_directories(&created);
                        return Err(error);
                    }
                };
                if newly_created {
                    created.push(CreatedOutputDirectory {
                        parent,
                        leaf: component.clone(),
                    });
                }
                match current.open_dir_nofollow(&component) {
                    Ok(directory) => directory,
                    Err(error) => {
                        remove_created_output_directories(&created);
                        return Err(error);
                    }
                }
            }
            Err(error) => {
                remove_created_output_directories(&created);
                return Err(error);
            }
        };
    }

    Ok(AcquiredOutputRoot {
        directory: current,
        created,
    })
}

fn output_root_anchor(output_root: &Path) -> io::Result<(Dir, Vec<OsString>)> {
    let absolute = std::path::absolute(output_root)?;
    let Some(leaf) = absolute.file_name() else {
        return Dir::open_ambient_dir(&absolute, cap_std::ambient_authority())
            .map(|directory| (directory, Vec::new()));
    };
    let mut components = vec![leaf.to_owned()];
    let mut candidate = absolute
        .parent()
        .ok_or_else(|| io::Error::other("artifact output root has no parent directory"))?;

    loop {
        match Dir::open_ambient_dir(candidate, cap_std::ambient_authority()) {
            Ok(directory) => return Ok((directory, components)),
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                let missing = candidate.file_name().ok_or(error)?;
                components.insert(0, missing.to_owned());
                candidate = candidate.parent().ok_or_else(|| {
                    io::Error::other("artifact output root has no existing parent directory")
                })?;
            }
            Err(error) => return Err(error),
        }
    }
}

fn remove_created_output_directories(directories: &[CreatedOutputDirectory]) {
    for directory in directories.iter().rev() {
        let _ = directory.parent.remove_dir(&directory.leaf);
        let _ = sync_dir(&directory.parent);
    }
}

fn finish_committed_transaction<H: ArtifactHooks + ?Sized>(
    root: &Dir,
    transaction: Dir,
    recovery_path: &Path,
    hooks: &H,
) -> Result<(), CliError> {
    if let Err(error) = hooks
        .before_post_commit_root_sync()
        .and_then(|()| sync_dir(root))
    {
        return Err(committed_error(
            error,
            format!("transaction retained at '{}'", recovery_path.display()),
        ));
    }
    if let Err(error) = hooks.before_post_commit_cleanup() {
        return Err(committed_error(
            error,
            format!("transaction retained at '{}'", recovery_path.display()),
        ));
    }
    if let Err(error) = transaction.remove_open_dir_all() {
        return Err(committed_error(
            error,
            format!(
                "transaction cleanup incomplete; inspect '{}'",
                recovery_path.display()
            ),
        ));
    }
    sync_dir(root).map_err(|error| {
        committed_error(
            error,
            "transaction cleanup completed but the output directory sync failed".to_owned(),
        )
    })
}

fn create_transaction(root: &Dir) -> io::Result<Transaction> {
    for _ in 0..100 {
        let id = NEXT_TRANSACTION_ID.fetch_add(1, Ordering::Relaxed);
        let relative_path =
            PathBuf::from(format!(".morphir-artifacts-{}-{id}", std::process::id()));
        match root.create_dir(&relative_path) {
            Ok(()) => {
                return Ok(Transaction {
                    directory: root.open_dir_nofollow(&relative_path)?,
                    relative_path,
                });
            }
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error),
        }
    }
    Err(io::Error::other(
        "unable to allocate artifact transaction directory",
    ))
}

fn run_transaction<H: ArtifactHooks + ?Sized>(
    root: &Dir,
    transaction: &Dir,
    artifacts: &[ValidatedArtifact],
    stale: &[ValidatedRemoval],
    hooks: &H,
) -> Result<(), TransactionFailure> {
    transaction
        .create_dir("staged")
        .and_then(|()| transaction.create_dir("backups"))
        .and_then(|()| transaction.create_dir("rollback"))
        .map_err(TransactionFailure::RolledBack)?;
    for (index, artifact) in artifacts.iter().enumerate() {
        let staged = if artifact.internal {
            stage_artifact(transaction, artifact)
        } else {
            hooks
                .before_stage(index)
                .and_then(|()| stage_artifact(transaction, artifact))
        };
        staged.map_err(TransactionFailure::RolledBack)?;
    }
    for artifact in stale {
        preflight_destination(root, &artifact.relative_path)
            .map_err(TransactionFailure::RolledBack)?;
    }
    let mut created_directories = Vec::new();
    let mut destinations = match prepare_stale_destinations(root, artifacts.len(), stale) {
        Ok(destinations) => destinations,
        Err(error) => {
            return Err(TransactionFailure::RolledBack(error));
        }
    };
    let mut records = Vec::new();
    commit_destinations(root, transaction, &destinations, &mut records, hooks)?;
    if let Err(error) = remove_blocking_managed_directories(root, artifacts, stale) {
        return rollback_failure(error, root, transaction, &destinations, &records, hooks);
    }
    for artifact in artifacts {
        if let Err(error) = preflight_destination(root, &artifact.relative_path) {
            return rollback_failure(error, root, transaction, &destinations, &records, hooks);
        }
    }
    let artifact_destinations =
        match prepare_artifact_destinations(root, artifacts, &mut created_directories) {
            Ok(destinations) => destinations,
            Err(error) => {
                let result =
                    rollback_failure(error, root, transaction, &destinations, &records, hooks);
                remove_created_directories(root, &created_directories);
                return result;
            }
        };
    destinations.extend(artifact_destinations);
    let result = commit_destinations(root, transaction, &destinations, &mut records, hooks);
    drop(destinations);
    if result.is_err() {
        remove_created_directories(root, &created_directories);
    }
    result
}

fn stage_artifact(transaction: &Dir, artifact: &ValidatedArtifact) -> io::Result<()> {
    let staged = PathBuf::from("staged").join(&artifact.relative_path);
    let parent = ensure_directory_path(
        transaction,
        staged.parent().expect("validated artifact has a parent"),
        &mut Vec::new(),
    )?;
    let mut options = OpenOptions::new();
    options
        .write(true)
        .create_new(true)
        .follow(FollowSymlinks::No);
    let mut file = parent.open_with(
        staged.file_name().expect("validated artifact has a leaf"),
        &options,
    )?;
    file.write_all(&artifact.bytes)?;
    file.sync_all()?;
    sync_dir(&parent)
}

fn preflight_destination(root: &Dir, path: &Path) -> io::Result<()> {
    let Some(parent) = open_existing_directory_path(root, path.parent().unwrap_or(Path::new("")))?
    else {
        return Ok(());
    };
    validate_leaf(
        &parent,
        path.file_name().expect("validated artifact has a leaf"),
    )
    .map(|_| ())
}

fn prepare_stale_destinations(
    root: &Dir,
    artifact_count: usize,
    stale: &[ValidatedRemoval],
) -> io::Result<Vec<Destination>> {
    let mut destinations = Vec::with_capacity(stale.len());
    for (offset, artifact) in stale.iter().enumerate() {
        let Some(parent) = open_existing_directory_path(
            root,
            artifact.relative_path.parent().unwrap_or(Path::new("")),
        )?
        else {
            continue;
        };
        let leaf = artifact
            .relative_path
            .file_name()
            .expect("validated artifact has a leaf")
            .to_owned();
        match validate_leaf(&parent, &leaf)? {
            LeafState::Absent => continue,
            LeafState::Regular => {}
        }
        let index = artifact_count + offset;
        destinations.push(Destination {
            parent,
            relative_path: artifact.relative_path.clone(),
            leaf,
            staged: None,
            backup: PathBuf::from("backups").join(&artifact.relative_path),
            rollback: PathBuf::from("rollback").join(index.to_string()),
            hook_index: Some(index),
        });
    }
    Ok(destinations)
}

fn prepare_artifact_destinations(
    root: &Dir,
    artifacts: &[ValidatedArtifact],
    created: &mut Vec<PathBuf>,
) -> io::Result<Vec<Destination>> {
    let mut destinations = Vec::with_capacity(artifacts.len());
    for (index, artifact) in artifacts.iter().enumerate() {
        let parent = ensure_directory_path(
            root,
            artifact.relative_path.parent().unwrap_or(Path::new("")),
            created,
        )?;
        destinations.push(Destination {
            parent,
            relative_path: artifact.relative_path.clone(),
            leaf: artifact
                .relative_path
                .file_name()
                .expect("validated artifact has a leaf")
                .to_owned(),
            staged: Some(PathBuf::from("staged").join(&artifact.relative_path)),
            backup: PathBuf::from("backups").join(&artifact.relative_path),
            rollback: PathBuf::from("rollback").join(index.to_string()),
            hook_index: (!artifact.internal).then_some(index),
        });
    }
    Ok(destinations)
}

fn remove_blocking_managed_directories(
    root: &Dir,
    artifacts: &[ValidatedArtifact],
    stale: &[ValidatedRemoval],
) -> io::Result<()> {
    let mut directories = BTreeSet::new();
    for artifact in artifacts.iter().filter(|artifact| !artifact.internal) {
        for removed in stale.iter().filter(|removed| {
            removed.relative_path != artifact.relative_path
                && removed.relative_path.starts_with(&artifact.relative_path)
        }) {
            let mut candidate = removed.relative_path.parent();
            while let Some(directory) = candidate {
                if !directory.starts_with(&artifact.relative_path) {
                    break;
                }
                directories.insert(directory.to_path_buf());
                if directory == artifact.relative_path {
                    break;
                }
                candidate = directory.parent();
            }
        }
    }
    let mut directories = directories.into_iter().collect::<Vec<_>>();
    directories.sort_by(|left, right| {
        right
            .components()
            .count()
            .cmp(&left.components().count())
            .then_with(|| right.cmp(left))
    });
    for directory in directories {
        let parent_path = directory.parent().unwrap_or(Path::new(""));
        let Some(parent) = open_existing_directory_path(root, parent_path)? else {
            continue;
        };
        let leaf = directory
            .file_name()
            .expect("blocking managed directory has a leaf");
        match parent.remove_dir(leaf) {
            Ok(()) => sync_dir(&parent)?,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(error),
        }
    }
    Ok(())
}

fn commit_destinations<H: ArtifactHooks + ?Sized>(
    root: &Dir,
    transaction: &Dir,
    destinations: &[Destination],
    records: &mut Vec<CommitRecord>,
    hooks: &H,
) -> Result<(), TransactionFailure> {
    for (index, destination) in destinations.iter().enumerate().skip(records.len()) {
        records.push(CommitRecord {
            index,
            backup: false,
            installed: false,
        });
        match validate_leaf(&destination.parent, &destination.leaf) {
            Ok(LeafState::Absent) => {}
            Ok(LeafState::Regular) => {
                if let Err(error) = move_destination_to_backup(transaction, destination) {
                    return rollback_failure(
                        error,
                        root,
                        transaction,
                        destinations,
                        records,
                        hooks,
                    );
                }
                records.last_mut().expect("record exists").backup = true;
                let verified = destination
                    .hook_index
                    .map_or_else(|| Ok(()), |index| hooks.after_backup_move(index))
                    .and_then(|()| verify_moved_backup(transaction, destination));
                if let Err(error) = verified {
                    return rollback_failure(
                        error,
                        root,
                        transaction,
                        destinations,
                        records,
                        hooks,
                    );
                }
            }
            Err(error) => {
                return rollback_failure(error, root, transaction, destinations, records, hooks);
            }
        }
        if let Some(staged) = &destination.staged {
            let hook = destination.hook_index.map_or_else(
                || Ok(()),
                |index| hooks.before_install(index, &destination.parent, &destination.leaf),
            );
            if let Err(error) = hook {
                return rollback_failure(error, root, transaction, destinations, records, hooks);
            }
            if let Err(error) =
                transaction.hard_link(staged, &destination.parent, &destination.leaf)
            {
                return rollback_failure(error, root, transaction, destinations, records, hooks);
            }
            records.last_mut().expect("record exists").installed = true;
            if let Err(error) = sync_file_and_parent(&destination.parent, &destination.leaf) {
                return rollback_failure(error, root, transaction, destinations, records, hooks);
            }
        }
    }
    Ok(())
}

fn move_destination_to_backup(transaction: &Dir, destination: &Destination) -> io::Result<()> {
    let backup_parent = ensure_directory_path(
        transaction,
        destination.backup.parent().expect("backup has parent"),
        &mut Vec::new(),
    )?;
    let backup_leaf = destination.backup.file_name().expect("backup has leaf");
    destination
        .parent
        .rename(&destination.leaf, &backup_parent, backup_leaf)
}

fn verify_moved_backup(transaction: &Dir, destination: &Destination) -> io::Result<()> {
    let backup_parent = open_existing_directory_path(
        transaction,
        destination.backup.parent().expect("backup has parent"),
    )?
    .ok_or_else(|| io::Error::other("artifact backup parent disappeared"))?;
    let backup_leaf = destination.backup.file_name().expect("backup has leaf");
    let metadata = backup_parent.symlink_metadata(backup_leaf)?;
    if !metadata.is_file() || metadata.file_type().is_symlink() {
        return Err(io::Error::other(
            "artifact destination is not a regular file",
        ));
    }
    sync_dir(&destination.parent)?;
    sync_dir(&backup_parent)
}

fn rollback_failure<H: ArtifactHooks + ?Sized>(
    error: io::Error,
    root: &Dir,
    transaction: &Dir,
    destinations: &[Destination],
    records: &[CommitRecord],
    hooks: &H,
) -> Result<(), TransactionFailure> {
    match rollback(root, transaction, destinations, records, hooks) {
        Ok(()) => Err(TransactionFailure::RolledBack(error)),
        Err(rollback) => Err(TransactionFailure::RecoveryRequired(io::Error::other(
            format!("{error}; rollback failed: {rollback}"),
        ))),
    }
}

fn rollback<H: ArtifactHooks + ?Sized>(
    root: &Dir,
    transaction: &Dir,
    destinations: &[Destination],
    records: &[CommitRecord],
    hooks: &H,
) -> io::Result<()> {
    let mut errors = Vec::new();
    for record in records.iter().rev() {
        let destination = &destinations[record.index];
        let result: io::Result<()> = (|| {
            if let Some(index) = destination.hook_index {
                hooks.before_rollback(index)?;
            }
            if record.installed {
                let rollback_parent = ensure_directory_path(
                    transaction,
                    destination.rollback.parent().expect("rollback has parent"),
                    &mut Vec::new(),
                )?;
                destination.parent.rename(
                    &destination.leaf,
                    &rollback_parent,
                    destination.rollback.file_name().expect("rollback has leaf"),
                )?;
            }
            if record.backup {
                match root.symlink_metadata(&destination.relative_path) {
                    Ok(metadata) if metadata.is_dir() && !metadata.file_type().is_symlink() => {
                        root.remove_dir(&destination.relative_path)?;
                    }
                    Ok(_) => {}
                    Err(error) if error.kind() == io::ErrorKind::NotFound => {}
                    Err(error) => return Err(error),
                }
                let parent = ensure_directory_path(
                    root,
                    destination
                        .relative_path
                        .parent()
                        .expect("destination has a parent"),
                    &mut Vec::new(),
                )?;
                transaction.hard_link(&destination.backup, &parent, &destination.leaf)?;
                sync_file_and_parent(&parent, &destination.leaf)?;
            }
            Ok(())
        })();
        if let Err(error) = result {
            errors.push(error.to_string());
        }
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(io::Error::other(errors.join("; ")))
    }
}

fn validate_leaf(parent: &Dir, leaf: &OsStr) -> io::Result<LeafState> {
    match parent.symlink_metadata(leaf) {
        Ok(metadata) if metadata.file_type().is_symlink() => {
            Err(io::Error::other("artifact destination is a symbolic link"))
        }
        Ok(metadata) if metadata.is_file() => Ok(LeafState::Regular),
        Ok(_) => Err(io::Error::other(
            "artifact destination is not a regular file",
        )),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(LeafState::Absent),
        Err(error) => Err(error),
    }
}

enum LeafState {
    Absent,
    Regular,
}

fn open_existing_directory_path(root: &Dir, path: &Path) -> io::Result<Option<Dir>> {
    let mut current = root.try_clone()?;
    for component in normal_components(path)? {
        match current.symlink_metadata(component) {
            Ok(metadata) if metadata.file_type().is_symlink() => {
                return Err(io::Error::other(
                    "artifact destination parent is a symbolic link",
                ));
            }
            Ok(metadata) if metadata.is_dir() => current = current.open_dir_nofollow(component)?,
            Ok(_) => {
                return Err(io::Error::other(
                    "artifact destination parent is not a directory",
                ));
            }
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error),
        }
    }
    Ok(Some(current))
}

fn ensure_directory_path(root: &Dir, path: &Path, created: &mut Vec<PathBuf>) -> io::Result<Dir> {
    let mut current = root.try_clone()?;
    let mut relative = PathBuf::new();
    for component in normal_components(path)? {
        relative.push(component);
        current = match current.open_dir_nofollow(component) {
            Ok(directory) => directory,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                current.create_dir(component)?;
                created.push(relative.clone());
                current.open_dir_nofollow(component)?
            }
            Err(error) => return Err(error),
        };
    }
    Ok(current)
}

fn normal_components(path: &Path) -> io::Result<Vec<&OsStr>> {
    path.components()
        .map(|component| match component {
            Component::Normal(segment) => Ok(segment),
            _ => Err(io::Error::other(
                "artifact path contains a non-normal component",
            )),
        })
        .collect()
}

fn remove_created_directories(root: &Dir, directories: &[PathBuf]) {
    for directory in directories.iter().rev() {
        let _ = root.remove_dir(directory);
    }
}

fn sync_file_and_parent(parent: &Dir, leaf: &OsStr) -> io::Result<()> {
    let mut options = OpenOptions::new();
    options.read(true).follow(FollowSymlinks::No);
    parent.open_with(leaf, &options)?.sync_all()?;
    sync_dir(parent)
}

fn sync_dir(directory: &Dir) -> io::Result<()> {
    directory.open(".")?.sync_all()
}

struct ValidatedArtifact {
    relative_path: PathBuf,
    display_path: String,
    bytes: Vec<u8>,
    internal: bool,
}

struct ValidatedRemoval {
    relative_path: PathBuf,
    display_path: String,
}

#[derive(serde::Deserialize, serde::Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ArtifactManifest {
    schema_version: u32,
    artifacts: Vec<String>,
}

fn load_manifest(root: &Dir) -> Result<Option<Vec<ValidatedRemoval>>, CliError> {
    let mut options = OpenOptions::new();
    options.read(true).follow(FollowSymlinks::No);
    let mut source = match root.open_with(MANIFEST_PATH, &options) {
        Ok(source) => source,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(file_system_error(error)),
    };
    let mut bytes = Vec::new();
    source.read_to_end(&mut bytes).map_err(file_system_error)?;
    let manifest: ArtifactManifest = serde_json::from_slice(&bytes).map_err(|error| {
        validation_error(format!("invalid generated-artifact manifest: {error}"))
    })?;
    if manifest.schema_version != MANIFEST_SCHEMA_VERSION {
        return Err(validation_error(format!(
            "unsupported generated-artifact manifest schema version {}",
            manifest.schema_version
        )));
    }
    let mut paths_by_case_key = BTreeMap::<String, String>::new();
    let mut validated = Vec::with_capacity(manifest.artifacts.len());
    for path in manifest.artifacts {
        if path.eq_ignore_ascii_case(MANIFEST_PATH) {
            return Err(validation_error(
                "generated-artifact manifest cannot list itself".to_owned(),
            ));
        }
        let (relative_path, display_path) = validate_path(&path)?;
        let case_key = display_path.to_ascii_lowercase();
        if paths_by_case_key
            .insert(case_key, display_path.clone())
            .is_some()
        {
            return Err(validation_error(format!(
                "duplicate path '{display_path}' in generated-artifact manifest"
            )));
        }
        validated.push(ValidatedRemoval {
            relative_path,
            display_path,
        });
    }
    Ok(Some(validated))
}

fn manifest_artifact(paths: &[String]) -> Result<ValidatedArtifact, CliError> {
    let mut bytes = serde_json::to_vec_pretty(&ArtifactManifest {
        schema_version: MANIFEST_SCHEMA_VERSION,
        artifacts: paths.to_vec(),
    })
    .map_err(|error| validation_error(format!("cannot encode artifact manifest: {error}")))?;
    bytes.push(b'\n');
    Ok(ValidatedArtifact {
        relative_path: PathBuf::from(MANIFEST_PATH),
        display_path: MANIFEST_PATH.to_owned(),
        bytes,
        internal: true,
    })
}

fn validate_complete_set(artifacts: &[Artifact]) -> Result<Vec<ValidatedArtifact>, CliError> {
    let mut paths_by_case_key = BTreeMap::<String, String>::new();
    let mut validated = Vec::with_capacity(artifacts.len());

    for artifact in artifacts {
        if artifact.path.eq_ignore_ascii_case(MANIFEST_PATH) {
            return Err(validation_error(format!(
                "artifact path '{}' is reserved for Morphir generation state",
                artifact.path
            )));
        }
        let (relative_path, display_path) = validate_path(&artifact.path)?;
        let case_key = display_path.to_ascii_lowercase();
        if let Some(previous) = paths_by_case_key.get(&case_key) {
            let problem = if previous == &display_path {
                format!("duplicate artifact path '{display_path}'")
            } else {
                format!("case-colliding artifact paths '{previous}' and '{display_path}'")
            };
            return Err(validation_error(problem));
        }
        paths_by_case_key.insert(case_key, display_path.clone());

        let bytes = if artifact.binary {
            STANDARD.decode(&artifact.content).map_err(|error| {
                validation_error(format!(
                    "artifact '{display_path}' contains invalid Base64: {error}"
                ))
            })?
        } else {
            artifact.content.as_bytes().to_vec()
        };
        validated.push(ValidatedArtifact {
            relative_path,
            display_path,
            bytes,
            internal: false,
        });
    }

    for (case_key, display_path) in &paths_by_case_key {
        for (separator, _) in case_key.match_indices('/') {
            let ancestor = &case_key[..separator];
            if let Some(ancestor_path) = paths_by_case_key.get(ancestor) {
                return Err(validation_error(format!(
                    "artifact path prefix conflict between '{ancestor_path}' and '{display_path}'"
                )));
            }
        }
    }

    validated.sort_by(|left, right| left.display_path.cmp(&right.display_path));
    Ok(validated)
}

fn validate_path(path: &str) -> Result<(PathBuf, String), CliError> {
    let raw_segments = path.split('/').collect::<Vec<_>>();
    if raw_segments
        .iter()
        .any(|segment| segment.is_empty() || matches!(*segment, "." | ".."))
        || has_windows_drive_prefix(path)
        || path.contains('\\')
    {
        return Err(invalid_path(path));
    }

    let mut segments = Vec::with_capacity(raw_segments.len());
    for segment in raw_segments {
        if !portable_segment_is_valid(segment) {
            return Err(invalid_path(path));
        }
        let mut components = Path::new(segment).components();
        match (components.next(), components.next()) {
            (Some(Component::Normal(normal)), None) => segments.push(normal.to_owned()),
            _ => return Err(invalid_path(path)),
        }
    }

    let relative_path = segments.iter().collect::<PathBuf>();
    let display_path = segments
        .iter()
        .map(|segment| segment.to_string_lossy())
        .collect::<Vec<_>>()
        .join("/");
    Ok((relative_path, display_path))
}

fn portable_segment_is_valid(segment: &str) -> bool {
    if segment
        .chars()
        .any(|character| character.is_control() || r#"<>:"/\|?*"#.contains(character))
        || segment.ends_with(['.', ' '])
    {
        return false;
    }
    let stem = segment.split('.').next().unwrap_or(segment);
    let upper = stem.to_ascii_uppercase();
    !matches!(
        upper.as_str(),
        "CON" | "PRN" | "AUX" | "NUL" | "CONIN$" | "CONOUT$"
    ) && !windows_numbered_device(&upper, "COM")
        && !windows_numbered_device(&upper, "LPT")
}

fn windows_numbered_device(segment: &str, prefix: &str) -> bool {
    segment.strip_prefix(prefix).is_some_and(|suffix| {
        let mut characters = suffix.chars();
        matches!(characters.next(), Some('1'..='9' | '¹' | '²' | '³'))
            && characters.next().is_none()
    })
}

fn has_windows_drive_prefix(path: &str) -> bool {
    let bytes = path.as_bytes();
    bytes.len() >= 2 && bytes[0].is_ascii_alphabetic() && bytes[1] == b':'
}

fn invalid_path(path: &str) -> CliError {
    validation_error(format!(
        "artifact path '{path}' must contain only non-empty relative path segments"
    ))
}

fn validation_error(message: String) -> CliError {
    CliError::Validation { message }
}

fn file_system_error(error: io::Error) -> CliError {
    CliError::FileSystem { error }
}

fn committed_error(error: io::Error, state: String) -> CliError {
    CliError::ArtifactPublication {
        message: format!("outputs committed; {state}"),
        error,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use morphir_extension_sdk::Artifact;
    use std::fs;
    use std::io;
    use tempfile::tempdir;

    fn text(path: &str, content: &str) -> Artifact {
        Artifact {
            path: path.to_owned(),
            content: content.to_owned(),
            binary: false,
        }
    }

    fn binary(path: &str, content: &str) -> Artifact {
        Artifact {
            path: path.to_owned(),
            content: content.to_owned(),
            binary: true,
        }
    }

    #[test]
    fn rejects_unsafe_paths_before_writing() {
        for path in [
            "/absolute",
            "C:/absolute",
            "../escape",
            "a/../escape",
            "",
            "a//empty",
            "trailing/",
            ".",
            "a/./normalized",
            "CON.avsc",
            "nested/aux.json",
            "CONIN$",
            "conout$.txt",
            "COM¹.log",
            "lpt²",
            "COM³",
            "name:stream.avsc",
            "less<than.avsc",
            "greater>than.avsc",
            "quote\"name.avsc",
            "pipe|name.avsc",
            "question?.avsc",
            "star*.avsc",
            "control\u{1f}.avsc",
            "delete\u{7f}.avsc",
            "trailing-dot./file.avsc",
            "trailing-space /file.avsc",
        ] {
            let output = tempdir().unwrap();

            let error = ArtifactWriter::new(output.path())
                .write_all(&[text(path, "unsafe")])
                .unwrap_err();

            assert!(
                error.to_string().contains("path"),
                "unexpected error for {path:?}: {error}"
            );
            assert!(output.path().read_dir().unwrap().next().is_none());
        }
    }

    #[test]
    fn rejects_existing_non_regular_destination_without_touching_its_children() {
        let output = tempdir().unwrap();
        fs::create_dir(output.path().join("schemas")).unwrap();
        fs::write(output.path().join("schemas/keep.txt"), "keep").unwrap();

        let error = ArtifactWriter::new(output.path())
            .write_all(&[text("schemas", "replacement")])
            .unwrap_err();

        assert!(error.to_string().contains("File system"));
        assert_eq!(
            fs::read_to_string(output.path().join("schemas/keep.txt")).unwrap(),
            "keep"
        );
    }

    #[test]
    fn rejects_duplicate_paths_before_writing() {
        let output = tempdir().unwrap();
        let artifacts = vec![text("same.avsc", "one"), text("same.avsc", "two")];

        let error = ArtifactWriter::new(output.path())
            .write_all(&artifacts)
            .unwrap_err();

        assert!(error.to_string().contains("duplicate"));
        assert!(output.path().read_dir().unwrap().next().is_none());
    }

    #[test]
    fn rejects_case_collisions_before_writing() {
        let output = tempdir().unwrap();
        let artifacts = vec![text("Foo.avsc", "{}"), text("foo.avsc", "{}")];

        let error = ArtifactWriter::new(output.path())
            .write_all(&artifacts)
            .unwrap_err();

        assert!(error.to_string().contains("case-colliding"));
        assert!(output.path().read_dir().unwrap().next().is_none());
    }

    #[test]
    fn rejects_file_directory_prefix_conflicts_before_writing() {
        let output = tempdir().unwrap();
        let artifacts = vec![text("schema", "file"), text("schema/nested.avsc", "nested")];

        let error = ArtifactWriter::new(output.path())
            .write_all(&artifacts)
            .unwrap_err();

        assert!(error.to_string().contains("prefix conflict"));
        assert!(output.path().read_dir().unwrap().next().is_none());
    }

    #[test]
    fn rejects_prefix_conflicts_even_when_an_unrelated_path_sorts_between_them() {
        let output = tempdir().unwrap();
        let artifacts = vec![
            text("a", "file"),
            text("a-elsewhere", "other"),
            text("a/nested.avsc", "nested"),
        ];

        let error = ArtifactWriter::new(output.path())
            .write_all(&artifacts)
            .unwrap_err();

        assert!(error.to_string().contains("prefix conflict"));
        assert!(output.path().read_dir().unwrap().next().is_none());
    }

    #[test]
    fn writes_text_and_strict_base64_binary_then_returns_sorted_paths() {
        let output = tempdir().unwrap();
        let artifacts = vec![
            binary("z/data.bin", "AP+A"),
            text("a/schema.avsc", "{\"type\":\"record\"}"),
        ];

        let paths = ArtifactWriter::new(output.path())
            .write_all(&artifacts)
            .unwrap();

        assert_eq!(paths, ["a/schema.avsc", "z/data.bin"]);
        assert_eq!(
            fs::read(output.path().join("a/schema.avsc")).unwrap(),
            b"{\"type\":\"record\"}"
        );
        assert_eq!(
            fs::read(output.path().join("z/data.bin")).unwrap(),
            [0, 255, 128]
        );
    }

    #[test]
    fn reconciles_the_previous_generated_set_without_removing_user_files() {
        let output = tempdir().unwrap();
        fs::write(output.path().join("keep.txt"), "user-owned").unwrap();
        let writer = ArtifactWriter::new(output.path());

        writer
            .write_all(&[
                text("schemas/obsolete.avsc", "old"),
                text("schemas/current.avsc", "first"),
            ])
            .unwrap();
        let paths = writer
            .write_all(&[text("schemas/current.avsc", "second")])
            .unwrap();

        assert_eq!(paths, ["schemas/current.avsc"]);
        assert!(!output.path().join("schemas/obsolete.avsc").exists());
        assert_eq!(
            fs::read_to_string(output.path().join("schemas/current.avsc")).unwrap(),
            "second"
        );
        assert_eq!(
            fs::read_to_string(output.path().join("keep.txt")).unwrap(),
            "user-owned"
        );
    }

    #[test]
    fn reconciles_a_managed_file_into_a_directory() {
        let output = tempdir().unwrap();
        let writer = ArtifactWriter::new(output.path());

        writer.write_all(&[text("schema", "old")]).unwrap();
        let paths = writer
            .write_all(&[text("schema/item.avsc", "new")])
            .unwrap();

        assert_eq!(paths, ["schema/item.avsc"]);
        assert_eq!(
            fs::read_to_string(output.path().join("schema/item.avsc")).unwrap(),
            "new"
        );
    }

    #[test]
    fn reconciles_a_managed_directory_into_a_file() {
        let output = tempdir().unwrap();
        let writer = ArtifactWriter::new(output.path());

        writer
            .write_all(&[text("schema/item.avsc", "old")])
            .unwrap();
        let paths = writer.write_all(&[text("schema", "new")]).unwrap();

        assert_eq!(paths, ["schema"]);
        assert_eq!(
            fs::read_to_string(output.path().join("schema")).unwrap(),
            "new"
        );
    }

    #[test]
    fn refuses_to_replace_a_directory_containing_user_files() {
        let output = tempdir().unwrap();
        let writer = ArtifactWriter::new(output.path());

        writer
            .write_all(&[text("schema/item.avsc", "managed")])
            .unwrap();
        fs::write(output.path().join("schema/keep.txt"), "user-owned").unwrap();

        assert!(writer.write_all(&[text("schema", "new")]).is_err());
        assert_eq!(
            fs::read_to_string(output.path().join("schema/item.avsc")).unwrap(),
            "managed"
        );
        assert_eq!(
            fs::read_to_string(output.path().join("schema/keep.txt")).unwrap(),
            "user-owned"
        );
    }

    #[test]
    fn failed_file_to_directory_transition_restores_the_managed_file() {
        let output = tempdir().unwrap();
        ArtifactWriter::new(output.path())
            .write_all(&[text("schema", "old")])
            .unwrap();
        let ops = FailingOps::on_install(0);

        assert!(
            ArtifactWriter::with_ops(output.path(), &ops)
                .write_all(&[text("schema/item.avsc", "new")])
                .is_err()
        );

        assert_eq!(
            fs::read_to_string(output.path().join("schema")).unwrap(),
            "old"
        );
    }

    #[test]
    fn rejects_invalid_base64_before_writing() {
        let output = tempdir().unwrap();

        let error = ArtifactWriter::new(output.path())
            .write_all(&[binary("bad.bin", "not base64")])
            .unwrap_err();

        assert!(error.to_string().contains("Base64"));
        assert!(output.path().read_dir().unwrap().next().is_none());
    }

    #[cfg(unix)]
    #[test]
    fn rejects_a_symlinked_destination_parent() {
        use std::os::unix::fs::symlink;

        let output = tempdir().unwrap();
        let outside = tempdir().unwrap();
        symlink(outside.path(), output.path().join("linked")).unwrap();

        let error = ArtifactWriter::new(output.path())
            .write_all(&[text("linked/escape.avsc", "escaped")])
            .unwrap_err();

        assert!(error.to_string().contains("File system"));
        assert!(!outside.path().join("escape.avsc").exists());
    }

    #[test]
    fn failed_publish_restores_the_previous_set() {
        let output = tempdir().unwrap();
        fs::write(output.path().join("one.avsc"), "old one").unwrap();
        fs::write(output.path().join("two.avsc"), "old two").unwrap();
        let ops = FailingOps::on_install(1);
        let writer = ArtifactWriter::with_ops(output.path(), &ops);

        assert!(
            writer
                .write_all(&[text("one.avsc", "new one"), text("two.avsc", "new two"),])
                .is_err()
        );

        assert_eq!(
            fs::read_to_string(output.path().join("one.avsc")).unwrap(),
            "old one"
        );
        assert_eq!(
            fs::read_to_string(output.path().join("two.avsc")).unwrap(),
            "old two"
        );
        let visible = fs::read_dir(output.path())
            .unwrap()
            .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
            .collect::<Vec<_>>();
        assert_eq!(visible.len(), 2, "temporary paths leaked: {visible:?}");
    }

    struct FailAfterBackupMove;

    impl ArtifactHooks for FailAfterBackupMove {
        fn after_backup_move(&self, _index: usize) -> io::Result<()> {
            Err(io::Error::other("injected post-backup failure"))
        }
    }

    #[test]
    fn failure_after_backup_move_restores_the_moved_destination() {
        let output = tempdir().unwrap();
        fs::write(output.path().join("schema.avsc"), "old").unwrap();
        let writer = ArtifactWriter::with_ops(output.path(), &FailAfterBackupMove);

        let error = writer.write_all(&[text("schema.avsc", "new")]).unwrap_err();

        let CliError::FileSystem { error } = error else {
            panic!("expected a pre-commit file-system failure");
        };
        assert!(error.to_string().contains("post-backup"));
        assert_eq!(
            fs::read_to_string(output.path().join("schema.avsc")).unwrap(),
            "old"
        );
        assert_eq!(output.path().read_dir().unwrap().count(), 1);
    }

    struct FailPostCommitRootSync;

    impl ArtifactHooks for FailPostCommitRootSync {
        fn before_post_commit_root_sync(&self) -> io::Result<()> {
            Err(io::Error::other("injected root sync failure"))
        }
    }

    #[test]
    fn post_commit_root_sync_failure_reports_committed_outputs_and_retained_recovery() {
        let output = tempdir().unwrap();
        let writer = ArtifactWriter::with_ops(output.path(), &FailPostCommitRootSync);

        let error = writer
            .write_all(&[text("schema.avsc", "generated")])
            .unwrap_err();

        assert!(error.to_string().contains("outputs committed"));
        assert!(error.to_string().contains("transaction retained"));
        assert_eq!(
            fs::read_to_string(output.path().join("schema.avsc")).unwrap(),
            "generated"
        );
        assert!(transaction_directory(output.path()).is_some());
    }

    struct FailPostCommitCleanup;

    impl ArtifactHooks for FailPostCommitCleanup {
        fn before_post_commit_cleanup(&self) -> io::Result<()> {
            Err(io::Error::other("injected cleanup failure"))
        }
    }

    #[test]
    fn post_commit_cleanup_failure_reports_committed_outputs_and_retained_recovery() {
        let output = tempdir().unwrap();
        let writer = ArtifactWriter::with_ops(output.path(), &FailPostCommitCleanup);

        let error = writer
            .write_all(&[text("schema.avsc", "generated")])
            .unwrap_err();

        assert!(error.to_string().contains("outputs committed"));
        assert!(error.to_string().contains("transaction retained"));
        assert_eq!(
            fs::read_to_string(output.path().join("schema.avsc")).unwrap(),
            "generated"
        );
        assert!(transaction_directory(output.path()).is_some());
    }

    fn transaction_directory(output: &Path) -> Option<PathBuf> {
        fs::read_dir(output)
            .unwrap()
            .map(|entry| entry.unwrap().path())
            .find(|path| {
                path.file_name()
                    .unwrap()
                    .to_string_lossy()
                    .starts_with(".morphir-artifacts-")
            })
    }

    #[test]
    fn failed_publish_removes_new_parent_directories() {
        let output = tempdir().unwrap();
        let ops = FailingOps::on_install(1);
        let writer = ArtifactWriter::with_ops(output.path(), &ops);

        assert!(
            writer
                .write_all(&[
                    text("nested/one.avsc", "one"),
                    text("second/two.avsc", "two"),
                ])
                .is_err()
        );

        assert!(output.path().read_dir().unwrap().next().is_none());
    }

    #[test]
    fn failed_publication_removes_a_newly_created_output_root() {
        let parent = tempdir().unwrap();
        let output = parent.path().join("new-output");
        let ops = FailingOps::on_install(0);
        let writer = ArtifactWriter::with_ops(&output, &ops);

        assert!(writer.write_all(&[text("one.avsc", "one")]).is_err());

        assert!(!output.exists());
    }

    #[test]
    fn failed_staging_removes_a_newly_created_output_root() {
        let parent = tempdir().unwrap();
        let output = parent.path().join("new-output");
        let ops = FailingWriteOps;
        let writer = ArtifactWriter::with_ops(&output, &ops);

        assert!(writer.write_all(&[text("one.avsc", "one")]).is_err());

        assert!(!output.exists());
    }

    #[test]
    fn failed_restore_preserves_the_backup_tree() {
        let output = tempdir().unwrap();
        fs::write(output.path().join("one.avsc"), "old one").unwrap();
        fs::write(output.path().join("two.avsc"), "old two").unwrap();
        let ops = FailingOps::on_install_and_rollback(1, 0);
        let writer = ArtifactWriter::with_ops(output.path(), &ops);

        let error = writer
            .write_all(&[text("one.avsc", "new one"), text("two.avsc", "new two")])
            .unwrap_err();

        let CliError::FileSystem { error } = error else {
            panic!("expected a file-system error");
        };
        assert!(error.to_string().contains("backup preserved"));
        let backup = fs::read_dir(output.path())
            .unwrap()
            .map(|entry| entry.unwrap().path())
            .find(|path| {
                path.file_name()
                    .unwrap()
                    .to_string_lossy()
                    .starts_with(".morphir-artifacts-")
            })
            .expect("rollback failure should retain its backup tree");
        assert_eq!(
            fs::read_to_string(backup.join("backups/one.avsc")).unwrap(),
            "old one"
        );
    }

    struct FailingOps {
        fail_install: Option<usize>,
        fail_rollback: Option<usize>,
    }

    impl FailingOps {
        fn on_install(index: usize) -> Self {
            Self {
                fail_install: Some(index),
                fail_rollback: None,
            }
        }

        fn on_install_and_rollback(install: usize, rollback: usize) -> Self {
            Self {
                fail_install: Some(install),
                fail_rollback: Some(rollback),
            }
        }
    }

    impl ArtifactHooks for FailingOps {
        fn before_install(&self, index: usize, _parent: &Dir, _leaf: &OsStr) -> io::Result<()> {
            if self.fail_install == Some(index) {
                return Err(io::Error::other("injected publish failure"));
            }
            Ok(())
        }

        fn before_rollback(&self, index: usize) -> io::Result<()> {
            if self.fail_rollback == Some(index) {
                return Err(io::Error::other("injected rollback failure"));
            }
            Ok(())
        }
    }

    struct FailingWriteOps;

    impl ArtifactHooks for FailingWriteOps {
        fn before_stage(&self, _index: usize) -> io::Result<()> {
            Err(io::Error::other("injected staging failure"))
        }
    }

    struct ConcurrentCreateOps;

    impl ArtifactHooks for ConcurrentCreateOps {
        fn before_install(&self, _index: usize, parent: &Dir, leaf: &OsStr) -> io::Result<()> {
            let mut options = OpenOptions::new();
            options
                .write(true)
                .create_new(true)
                .follow(FollowSymlinks::No);
            let mut file = parent.open_with(leaf, &options)?;
            file.write_all(b"concurrent")?;
            file.sync_all()
        }
    }

    #[test]
    fn concurrent_destination_creation_is_not_overwritten() {
        let output = tempdir().unwrap();
        let writer = ArtifactWriter::with_ops(output.path(), &ConcurrentCreateOps);

        assert!(
            writer
                .write_all(&[text("schema.avsc", "generated")])
                .is_err()
        );

        assert_eq!(
            fs::read_to_string(output.path().join("schema.avsc")).unwrap(),
            "concurrent"
        );
    }

    #[cfg(unix)]
    struct RootSwapOps {
        root: PathBuf,
        moved: PathBuf,
        outside: PathBuf,
    }

    #[cfg(unix)]
    impl ArtifactHooks for RootSwapOps {
        fn before_install(&self, _index: usize, _parent: &Dir, _leaf: &OsStr) -> io::Result<()> {
            use std::os::unix::fs::symlink;
            fs::rename(&self.root, &self.moved)?;
            symlink(&self.outside, &self.root)
        }
    }

    #[cfg(unix)]
    #[test]
    fn output_root_swap_cannot_redirect_publication() {
        let parent = tempdir().unwrap();
        let outside = tempdir().unwrap();
        let root = parent.path().join("output");
        let moved = parent.path().join("moved-output");
        fs::create_dir(&root).unwrap();
        let ops = RootSwapOps {
            root: root.clone(),
            moved: moved.clone(),
            outside: outside.path().to_path_buf(),
        };

        ArtifactWriter::with_ops(&root, &ops)
            .write_all(&[text("schema.avsc", "generated")])
            .unwrap();

        assert_eq!(
            fs::read_to_string(moved.join("schema.avsc")).unwrap(),
            "generated"
        );
        assert!(!outside.path().join("schema.avsc").exists());
    }

    #[cfg(unix)]
    struct AcquisitionSwapOps {
        root: PathBuf,
        moved: PathBuf,
        outside: PathBuf,
    }

    #[cfg(unix)]
    impl ArtifactHooks for AcquisitionSwapOps {
        fn before_output_component_open(&self, _parent: &Dir, leaf: &OsStr) -> io::Result<()> {
            if leaf == self.root.file_name().unwrap() {
                use std::os::unix::fs::symlink;
                fs::rename(&self.root, &self.moved)?;
                symlink(&self.outside, &self.root)?;
            }
            Ok(())
        }
    }

    #[cfg(unix)]
    #[test]
    fn output_root_swap_during_capability_acquisition_is_rejected() {
        let parent = tempdir().unwrap();
        let outside = tempdir().unwrap();
        let root = parent.path().join("output");
        let moved = parent.path().join("moved-output");
        fs::create_dir(&root).unwrap();
        let ops = AcquisitionSwapOps {
            root: root.clone(),
            moved: moved.clone(),
            outside: outside.path().to_path_buf(),
        };

        let error = ArtifactWriter::with_ops(&root, &ops)
            .write_all(&[text("schema.avsc", "generated")])
            .unwrap_err();

        assert!(error.to_string().contains("File system"));
        assert!(!outside.path().join("schema.avsc").exists());
        assert!(moved.read_dir().unwrap().next().is_none());
    }

    #[cfg(unix)]
    #[test]
    fn symlinked_output_root_is_rejected_during_capability_acquisition() {
        use std::os::unix::fs::symlink;

        let parent = tempdir().unwrap();
        let outside = tempdir().unwrap();
        let root = parent.path().join("output");
        symlink(outside.path(), &root).unwrap();

        let error = ArtifactWriter::new(&root)
            .write_all(&[text("schema.avsc", "generated")])
            .unwrap_err();

        assert!(error.to_string().contains("File system"));
        assert!(!outside.path().join("schema.avsc").exists());
    }

    #[test]
    fn nested_missing_output_root_is_created_and_published() {
        let parent = tempdir().unwrap();
        let output = parent.path().join("first/second/output");

        ArtifactWriter::new(&output)
            .write_all(&[text("schema.avsc", "generated")])
            .unwrap();

        assert_eq!(
            fs::read_to_string(output.join("schema.avsc")).unwrap(),
            "generated"
        );
    }

    #[cfg(unix)]
    struct ParentSwapOps {
        root: PathBuf,
        outside: PathBuf,
    }

    #[cfg(unix)]
    impl ArtifactHooks for ParentSwapOps {
        fn before_install(&self, _index: usize, _parent: &Dir, _leaf: &OsStr) -> io::Result<()> {
            use std::os::unix::fs::symlink;
            fs::rename(self.root.join("nested"), self.root.join("moved-nested"))?;
            symlink(&self.outside, self.root.join("nested"))
        }
    }

    #[cfg(unix)]
    #[test]
    fn destination_parent_swap_cannot_redirect_publication() {
        let output = tempdir().unwrap();
        let outside = tempdir().unwrap();
        fs::create_dir(output.path().join("nested")).unwrap();
        let ops = ParentSwapOps {
            root: output.path().to_path_buf(),
            outside: outside.path().to_path_buf(),
        };

        ArtifactWriter::with_ops(output.path(), &ops)
            .write_all(&[text("nested/schema.avsc", "generated")])
            .unwrap();

        assert_eq!(
            fs::read_to_string(output.path().join("moved-nested/schema.avsc")).unwrap(),
            "generated"
        );
        assert!(!outside.path().join("schema.avsc").exists());
    }
}
