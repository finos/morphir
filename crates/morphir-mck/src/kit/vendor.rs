//! Managed kit snapshots in an implementor's repository
//! (`spec/mck/kit-manifest.md`): opening and verifying one, vendoring a new
//! one and updating an existing one.
//!
//! Publishing is all-or-nothing. A snapshot is built in a staging directory
//! beside its destination, verified by reading it back, and only then renamed
//! into place. An update renames the old snapshot aside first and restores it
//! if the second rename fails. Nothing here deletes content it did not write.

use std::fmt;
use std::io;
use std::path::{Path, PathBuf};

use super::embedded::{PROVENANCE, embedded_source};
use super::hash::ContentDigest;
use super::load::{Kit, load_kit};
use super::manifest::{Lock, LockSource, MANIFEST_NAME};
use super::snapshot::{Problem, Snapshot, SnapshotError, collect, verify};
use super::source::{KIT_PATH, KitSource};
use crate::DRIVER_CONTRACT;

/// The CLI version that exports an embedded kit (the workspace version).
pub const CLI_VERSION: &str = env!("CARGO_PKG_VERSION");

const STAGING_MARK: &str = ".mck-staging-";
const OLD_MARK: &str = ".mck-old-";

#[derive(Debug)]
pub enum VendorError {
    /// The manifest could not be read or was refused.
    Manifest(String),
    /// The snapshot's declared driver contract excludes this CLI.
    UnsupportedDriver {
        declared: String,
    },
    /// The directory departs from its manifest.
    Modified {
        root: PathBuf,
        problems: Vec<Problem>,
    },
    /// The kit data disagrees with the manifest's corpus identity.
    CorpusMismatch {
        recorded: ContentDigest,
        actual: Option<ContentDigest>,
    },
    Snapshot(SnapshotError),
    /// The destination holds something this command will not replace.
    Occupied {
        dest: PathBuf,
        why: String,
    },
    /// An interrupted vendor or update left a directory behind.
    Leftover {
        path: PathBuf,
        action: String,
    },
    /// `--expect-digest` did not match.
    DigestMismatch {
        expected: ContentDigest,
        actual: ContentDigest,
    },
    /// The command cannot work with this input as given.
    Refused(String),
    Io(io::Error),
}

impl fmt::Display for VendorError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Manifest(message) | Self::Refused(message) => f.write_str(message),
            Self::UnsupportedDriver { declared } => write!(
                f,
                "the snapshot supports driver contract {declared}; this CLI implements contract {DRIVER_CONTRACT}. Use a CLI release that supports it, or update the snapshot"
            ),
            Self::Modified { root, problems } => {
                write!(f, "{} differs from its {MANIFEST_NAME}:", root.display())?;
                for problem in problems {
                    write!(f, "\n  {problem}")?;
                }
                Ok(())
            }
            Self::CorpusMismatch { recorded, actual } => write!(
                f,
                "the kit's corpus hash is {} but the manifest records {recorded}",
                actual
                    .as_ref()
                    .map_or("unavailable (the kit has errors)", ContentDigest::as_str)
            ),
            Self::Snapshot(error) => write!(f, "{error}"),
            Self::Occupied { dest, why } => write!(f, "{} {why}", dest.display()),
            Self::Leftover { path, action } => write!(
                f,
                "{} was left by an interrupted `morphir mck kit` command and is not a usable kit; {action}",
                path.display()
            ),
            Self::DigestMismatch { expected, actual } => {
                write!(
                    f,
                    "the snapshot digest is {actual}, not the expected {expected}; nothing was written"
                )
            }
            Self::Io(error) => write!(f, "{error}"),
        }
    }
}

impl std::error::Error for VendorError {}

impl From<io::Error> for VendorError {
    fn from(error: io::Error) -> Self {
        Self::Io(error)
    }
}

impl From<SnapshotError> for VendorError {
    fn from(error: SnapshotError) -> Self {
        Self::Snapshot(error)
    }
}

/// A snapshot root: the directory holding `mck-kit.lock.json`.
pub fn manifest_path(root: &Path) -> PathBuf {
    root.join(MANIFEST_NAME)
}

pub fn read_lock(root: &Path) -> Result<Lock, VendorError> {
    let bytes = std::fs::read(manifest_path(root)).map_err(|error| {
        VendorError::Manifest(format!(
            "cannot read {}: {error}",
            manifest_path(root).display()
        ))
    })?;
    Lock::parse(&bytes)
        .map_err(|error| VendorError::Manifest(format!("{}: {}", root.display(), error)))
}

/// A verified managed snapshot and the kit it holds.
#[derive(Debug)]
pub struct Managed {
    pub root: PathBuf,
    pub lock: Lock,
    pub kit: Kit,
}

/// Opens the managed snapshot at `root`. Every check runs before the kit is
/// used: the manifest parses, its driver contract admits this CLI, every file
/// matches it with nothing extra, and the kit's corpus hash is the recorded one.
pub fn open_managed(root: &Path) -> Result<Managed, VendorError> {
    let lock = read_lock(root)?;
    if !lock.supports_this_driver() {
        return Err(VendorError::UnsupportedDriver {
            declared: lock.driver_contract.to_string(),
        });
    }
    let problems = verify(root, &lock)?;
    if !problems.is_empty() {
        return Err(VendorError::Modified {
            root: root.to_path_buf(),
            problems,
        });
    }
    let kit = load_kit(KitSource::directory(
        &super::snapshot::join(root, KIT_PATH),
        Some(root),
    ))?;
    let actual = kit.corpus_hash()?;
    if actual.as_ref() != Some(&lock.corpus_hash) {
        return Err(VendorError::CorpusMismatch {
            recorded: lock.corpus_hash,
            actual,
        });
    }
    Ok(Managed {
        root: root.to_path_buf(),
        lock,
        kit,
    })
}

/// Where a snapshot's data comes from.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VendorSource {
    /// The kit compiled into this CLI.
    Embedded,
    /// A managed snapshot, or a repository root containing `spec/ir/mck`.
    Local(PathBuf),
}

impl VendorSource {
    fn kind(&self) -> &'static str {
        match self {
            Self::Embedded => "embedded",
            Self::Local(_) => "local",
        }
    }
}

/// The closure of `source` and the provenance its manifest records.
pub fn materialize(source: &VendorSource) -> Result<(Snapshot, LockSource), VendorError> {
    match source {
        VendorSource::Embedded => {
            let kit = load_kit(embedded_source())?;
            // A build from edited kit files cannot claim the commit it was built at.
            let revision = PROVENANCE
                .revision
                .filter(|_| !PROVENANCE.dirty)
                .map(super::manifest::CommitId::parse);
            let revision = revision.transpose().map_err(VendorError::Refused)?;
            Ok((
                collect(&kit)?,
                LockSource::Embedded {
                    cli_version: CLI_VERSION.to_owned(),
                    revision,
                },
            ))
        }
        VendorSource::Local(path) => {
            if manifest_path(path).is_file() {
                let managed = open_managed(path)?;
                let revision = managed.lock.source.revision().cloned();
                return Ok((collect(&managed.kit)?, LockSource::Local { revision }));
            }
            let kit_dir = super::snapshot::join(path, KIT_PATH);
            if !kit_dir.is_dir() {
                return Err(VendorError::Refused(format!(
                    "{} is neither a kit snapshot ({MANIFEST_NAME}) nor a repository containing {KIT_PATH}",
                    path.display()
                )));
            }
            let kit = load_kit(KitSource::directory(&kit_dir, Some(path)))?;
            Ok((collect(&kit)?, LockSource::Local { revision: None }))
        }
    }
}

fn sibling(dest: &Path, mark: &str, suffix: &str) -> Result<PathBuf, VendorError> {
    let name = dest
        .file_name()
        .ok_or_else(|| {
            VendorError::Refused(format!(
                "{} has no final path segment to vendor into",
                dest.display()
            ))
        })?
        .to_string_lossy();
    let parent = dest
        .parent()
        .map_or_else(|| PathBuf::from("."), Path::to_path_buf);
    let leading = if mark == STAGING_MARK { "." } else { "" };
    Ok(parent.join(format!("{leading}{name}{mark}{suffix}")))
}

fn unique_suffix() -> String {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_nanos());
    format!("{:x}-{:x}", std::process::id(), nanos)
}

/// Fails on a staging or backup directory an interrupted run left beside
/// `dest`, naming the exact recovery step.
pub fn check_leftovers(dest: &Path) -> Result<(), VendorError> {
    let parent = dest
        .parent()
        .map_or_else(|| PathBuf::from("."), Path::to_path_buf);
    let Some(name) = dest.file_name().map(|n| n.to_string_lossy().into_owned()) else {
        return Ok(());
    };
    let entries = match std::fs::read_dir(&parent) {
        Ok(entries) => entries,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error.into()),
    };
    let mut found: Vec<PathBuf> = Vec::new();
    for entry in entries {
        let entry = entry?;
        let entry_name = entry.file_name().to_string_lossy().into_owned();
        if entry_name.starts_with(&format!(".{name}{STAGING_MARK}"))
            || entry_name.starts_with(&format!("{name}{OLD_MARK}"))
        {
            found.push(entry.path());
        }
    }
    found.sort();
    let Some(path) = found.into_iter().next() else {
        return Ok(());
    };
    let staging = path
        .file_name()
        .is_some_and(|n| n.to_string_lossy().starts_with('.'));
    let action = if staging {
        format!(
            "delete {} after checking nothing else is using it",
            path.display()
        )
    } else if manifest_path(dest).is_file() {
        format!("{} is intact; delete {}", dest.display(), path.display())
    } else {
        format!(
            "restore the previous snapshot by renaming {} to {}",
            path.display(),
            dest.display()
        )
    };
    Err(VendorError::Leftover { path, action })
}

/// Builds `snapshot` in a staging directory beside `dest` and verifies it by
/// reading it back. The caller renames it into place.
fn stage(snapshot: &Snapshot, lock: &Lock, dest: &Path) -> Result<PathBuf, VendorError> {
    let staging = sibling(dest, STAGING_MARK, &unique_suffix())?;
    let written = snapshot
        .write(&staging, lock)
        .map_err(VendorError::from)
        .and_then(|()| {
            let problems = verify(&staging, lock)?;
            if problems.is_empty() {
                Ok(())
            } else {
                Err(VendorError::Modified {
                    root: staging.clone(),
                    problems,
                })
            }
        });
    if let Err(error) = written {
        std::fs::remove_dir_all(&staging).ok();
        return Err(error);
    }
    Ok(staging)
}

fn check_expected(lock: &Lock, expected: Option<&ContentDigest>) -> Result<(), VendorError> {
    match expected {
        Some(expected) if *expected != lock.snapshot_digest => Err(VendorError::DigestMismatch {
            expected: expected.clone(),
            actual: lock.snapshot_digest.clone(),
        }),
        _ => Ok(()),
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VendorOutcome {
    Created(Lock),
    /// The destination already held this exact verified snapshot.
    Unchanged(Lock),
}

/// Writes a new managed snapshot of `source` at `dest`. `dest` must be absent
/// or an empty directory; a destination already holding the same verified
/// snapshot is a successful no-op, and anything else is refused.
pub fn vendor(
    source: &VendorSource,
    dest: &Path,
    expected: Option<&ContentDigest>,
) -> Result<VendorOutcome, VendorError> {
    check_leftovers(dest)?;
    let (snapshot, provenance) = materialize(source)?;
    let lock = snapshot.lock(provenance);
    check_expected(&lock, expected)?;

    if dest.exists() {
        if !dest.is_dir() {
            return Err(VendorError::Occupied {
                dest: dest.to_path_buf(),
                why: "exists and is not a directory".to_owned(),
            });
        }
        if manifest_path(dest).is_file() {
            let existing = open_managed(dest)?;
            if existing.lock.snapshot_digest == lock.snapshot_digest {
                return Ok(VendorOutcome::Unchanged(existing.lock));
            }
            return Err(VendorError::Occupied {
                dest: dest.to_path_buf(),
                why: format!(
                    "already holds a different kit snapshot ({}); change it with `morphir mck kit update`",
                    existing.lock.snapshot_digest
                ),
            });
        }
        if std::fs::read_dir(dest)?.next().is_some() {
            return Err(VendorError::Occupied {
                dest: dest.to_path_buf(),
                why: "is not empty; vendor into a new or empty directory".to_owned(),
            });
        }
    }

    // Parent directories are created, as `mkdir -p` would; only `dest` itself
    // must be new or empty.
    if let Some(parent) = dest.parent().filter(|p| !p.as_os_str().is_empty()) {
        std::fs::create_dir_all(parent)?;
    }
    let staging = stage(&snapshot, &lock, dest)?;
    let promoted = (|| {
        if dest.exists() {
            std::fs::remove_dir(dest)?;
        }
        std::fs::rename(&staging, dest)
    })();
    if let Err(error) = promoted {
        std::fs::remove_dir_all(&staging).ok();
        return Err(error.into());
    }
    Ok(VendorOutcome::Created(lock))
}

/// How one inventory path changed between two snapshots.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Change {
    Added,
    Removed,
    Changed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UpdateReport {
    pub old: Lock,
    pub new: Lock,
    /// Inventory paths that differ, in path order.
    pub changes: Vec<(String, Change)>,
    /// A backup the command could not delete after a successful update.
    pub leftover: Option<PathBuf>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum UpdateOutcome {
    Updated(UpdateReport),
    Unchanged(Lock),
}

/// The paths that differ between two inventories.
pub fn diff(old: &Lock, new: &Lock) -> Vec<(String, Change)> {
    let before: std::collections::BTreeMap<&str, &str> = old
        .files
        .iter()
        .map(|f| (f.path.as_str(), f.sha256.as_str()))
        .collect();
    let after: std::collections::BTreeMap<&str, &str> = new
        .files
        .iter()
        .map(|f| (f.path.as_str(), f.sha256.as_str()))
        .collect();
    let mut changes: Vec<(String, Change)> = Vec::new();
    for (path, hash) in &after {
        match before.get(path) {
            None => changes.push(((*path).to_owned(), Change::Added)),
            Some(previous) if previous != hash => {
                changes.push(((*path).to_owned(), Change::Changed))
            }
            Some(_) => {}
        }
    }
    changes.extend(
        before
            .keys()
            .filter(|path| !after.contains_key(*path))
            .map(|path| ((*path).to_owned(), Change::Removed)),
    );
    changes.sort();
    changes
}

/// The source an update uses when none is given: the manifest's own kind,
/// when that kind needs no further input.
pub fn default_update_source(lock: &Lock) -> Result<VendorSource, VendorError> {
    match &lock.source {
        LockSource::Embedded { .. } => Ok(VendorSource::Embedded),
        LockSource::Local { .. } => Err(VendorError::Refused(
            "this snapshot was copied from a local directory; name it again with --source <path>".to_owned(),
        )),
        LockSource::Github { .. } => Err(VendorError::Refused(
            "this snapshot came from github:finos/morphir; pass --source github:finos/morphir --revision <commit>".to_owned(),
        )),
    }
}

/// Replaces the managed snapshot at `root` with a new one from `source`. The
/// existing snapshot must verify first, so edits are never discarded. The
/// new one is staged and verified, the old one renamed aside, the new one
/// renamed in, and the old one deleted; a failed second rename restores the
/// old one. Nothing is committed to version control.
pub fn update(
    root: &Path,
    source: &VendorSource,
    expected: Option<&ContentDigest>,
) -> Result<UpdateOutcome, VendorError> {
    check_leftovers(root)?;
    if !manifest_path(root).is_file() {
        return Err(VendorError::Refused(format!(
            "{} is not a managed kit snapshot (no {MANIFEST_NAME}); create one with `morphir mck kit vendor`",
            root.display()
        )));
    }
    if let VendorSource::Local(path) = source
        && std::path::absolute(path).ok() == std::path::absolute(root).ok()
    {
        return Err(VendorError::Refused(
            "a snapshot cannot be updated from itself".to_owned(),
        ));
    }
    let old = open_managed(root)?.lock;
    let (snapshot, provenance) = materialize(source)?;
    let new = snapshot.lock(provenance);
    check_expected(&new, expected)?;
    if new.snapshot_digest == old.snapshot_digest && new.source == old.source {
        return Ok(UpdateOutcome::Unchanged(old));
    }

    let staging = stage(&snapshot, &new, root)?;
    let backup = sibling(root, OLD_MARK, &unique_suffix())?;
    if let Err(error) = std::fs::rename(root, &backup) {
        std::fs::remove_dir_all(&staging).ok();
        return Err(error.into());
    }
    if let Err(error) = std::fs::rename(&staging, root) {
        let restored = std::fs::rename(&backup, root);
        std::fs::remove_dir_all(&staging).ok();
        return Err(match restored {
            Ok(()) => error.into(),
            Err(_) => VendorError::Leftover {
                path: backup.clone(),
                action: format!(
                    "restore the previous snapshot by renaming {} to {}",
                    backup.display(),
                    root.display()
                ),
            },
        });
    }
    let leftover = std::fs::remove_dir_all(&backup).err().map(|_| backup);
    let changes = diff(&old, &new);
    Ok(UpdateOutcome::Updated(UpdateReport {
        old,
        new,
        changes,
        leftover,
    }))
}

/// A short name for a source in messages.
pub fn describe(source: &VendorSource) -> String {
    match source {
        VendorSource::Embedded => format!("the kit embedded in morphir {CLI_VERSION}"),
        VendorSource::Local(path) => format!("{} ({})", path.display(), source.kind()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::kit::closure::FIXED_INPUTS;
    use crate::kit::snapshot::join;

    /// A minimal finos/morphir-shaped repository.
    fn repository(case_title: &str) -> tempfile::TempDir {
        let repo = tempfile::tempdir().unwrap();
        let kit = repo.path().join(KIT_PATH);
        std::fs::create_dir_all(&kit).unwrap();
        std::fs::write(
            kit.join("types.md"),
            format!("## types-0001: {case_title}\n```text canonical\nfixtures/a.json\n```\n"),
        )
        .unwrap();
        std::fs::create_dir_all(repo.path().join("fixtures")).unwrap();
        std::fs::write(repo.path().join("fixtures/a.json"), "{}").unwrap();
        for fixed in FIXED_INPUTS {
            let path = join(repo.path(), fixed);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(path, "{}").unwrap();
        }
        repo
    }

    fn local(repo: &tempfile::TempDir) -> VendorSource {
        VendorSource::Local(repo.path().to_path_buf())
    }

    #[test]
    fn vendoring_a_checkout_creates_a_verified_snapshot_with_no_revision() {
        let repo = repository("one");
        let out = tempfile::tempdir().unwrap();
        let dest = out.path().join("vendor/morphir-mck");
        std::fs::create_dir_all(dest.parent().unwrap()).unwrap();

        let VendorOutcome::Created(lock) = vendor(&local(&repo), &dest, None).unwrap() else {
            panic!("expected a new snapshot")
        };
        assert_eq!(lock.source, LockSource::Local { revision: None });
        let managed = open_managed(&dest).unwrap();
        assert_eq!(managed.lock, lock);
        assert_eq!(managed.kit.cases.len(), 1);
        assert_eq!(
            std::fs::read_dir(dest.parent().unwrap()).unwrap().count(),
            1,
            "no staging directory is left behind"
        );
    }

    #[test]
    fn vendoring_creates_missing_parent_directories() {
        let repo = repository("one");
        let out = tempfile::tempdir().unwrap();
        let dest = out.path().join("a/b/vendor/morphir-mck");
        assert!(matches!(
            vendor(&local(&repo), &dest, None).unwrap(),
            VendorOutcome::Created(_)
        ));
        assert!(open_managed(&dest).is_ok());
    }

    #[test]
    fn vendoring_the_same_content_again_is_a_no_op_and_different_content_is_refused() {
        let repo = repository("one");
        let out = tempfile::tempdir().unwrap();
        let dest = out.path().join("kit");
        vendor(&local(&repo), &dest, None).unwrap();
        assert!(matches!(
            vendor(&local(&repo), &dest, None).unwrap(),
            VendorOutcome::Unchanged(_)
        ));

        let other = repository("two");
        let error = vendor(&local(&other), &dest, None).unwrap_err().to_string();
        assert!(
            error.contains("already holds a different kit snapshot"),
            "{error}"
        );
    }

    #[test]
    fn vendoring_into_unrelated_content_or_a_file_is_refused_untouched() {
        let repo = repository("one");
        let out = tempfile::tempdir().unwrap();
        let dest = out.path().join("kit");
        std::fs::create_dir(&dest).unwrap();
        std::fs::write(dest.join("mine.txt"), "keep me").unwrap();
        assert!(
            vendor(&local(&repo), &dest, None)
                .unwrap_err()
                .to_string()
                .contains("is not empty")
        );
        assert_eq!(
            std::fs::read_to_string(dest.join("mine.txt")).unwrap(),
            "keep me"
        );

        let file = out.path().join("file");
        std::fs::write(&file, "x").unwrap();
        assert!(
            vendor(&local(&repo), &file, None)
                .unwrap_err()
                .to_string()
                .contains("is not a directory")
        );

        let empty = out.path().join("empty");
        std::fs::create_dir(&empty).unwrap();
        assert!(matches!(
            vendor(&local(&repo), &empty, None).unwrap(),
            VendorOutcome::Created(_)
        ));
    }

    #[test]
    fn an_expected_digest_is_checked_before_anything_is_written() {
        let repo = repository("one");
        let out = tempfile::tempdir().unwrap();
        let dest = out.path().join("kit");
        let wrong = crate::kit::hash::content_hash([("x", b"y".as_slice())]);
        assert!(matches!(
            vendor(&local(&repo), &dest, Some(&wrong)),
            Err(VendorError::DigestMismatch { .. })
        ));
        assert!(!dest.exists());
        assert_eq!(std::fs::read_dir(out.path()).unwrap().count(), 0);

        let VendorOutcome::Created(lock) = vendor(&local(&repo), &dest, None).unwrap() else {
            panic!()
        };
        std::fs::remove_dir_all(&dest).unwrap();
        assert!(matches!(
            vendor(&local(&repo), &dest, Some(&lock.snapshot_digest)).unwrap(),
            VendorOutcome::Created(_)
        ));
    }

    #[test]
    fn a_snapshot_copied_from_a_snapshot_keeps_its_revision_and_rejects_a_modified_source() {
        let repo = repository("one");
        let out = tempfile::tempdir().unwrap();
        let first = out.path().join("first");
        vendor(&local(&repo), &first, None).unwrap();
        let second = out.path().join("second");
        let VendorOutcome::Created(lock) =
            vendor(&VendorSource::Local(first.clone()), &second, None).unwrap()
        else {
            panic!()
        };
        assert_eq!(lock.source, LockSource::Local { revision: None });

        std::fs::write(first.join("fixtures/a.json"), "[]").unwrap();
        let error = vendor(
            &VendorSource::Local(first.clone()),
            &out.path().join("third"),
            None,
        )
        .unwrap_err()
        .to_string();
        assert!(error.contains("altered: fixtures/a.json"), "{error}");
    }

    #[test]
    fn the_embedded_kit_vendors_offline_and_records_the_cli_version() {
        let out = tempfile::tempdir().unwrap();
        let dest = out.path().join("kit");
        let VendorOutcome::Created(lock) = vendor(&VendorSource::Embedded, &dest, None).unwrap()
        else {
            panic!()
        };
        let LockSource::Embedded {
            cli_version,
            revision,
        } = &lock.source
        else {
            panic!("{:?}", lock.source)
        };
        assert_eq!(cli_version, CLI_VERSION);
        assert_eq!(
            revision.is_some(),
            PROVENANCE.revision.is_some() && !PROVENANCE.dirty
        );
        let managed = open_managed(&dest).unwrap();
        assert!(managed.kit.cases.len() >= 120);
        for fixed in FIXED_INPUTS {
            assert!(lock.files.iter().any(|f| f.path == *fixed), "{fixed}");
        }
    }

    #[test]
    fn open_managed_refuses_edits_extras_newer_drivers_and_bad_manifests() {
        let repo = repository("one");
        let out = tempfile::tempdir().unwrap();
        let dest = out.path().join("kit");
        vendor(&local(&repo), &dest, None).unwrap();

        std::fs::write(join(&dest, "spec/ir/mck/extra.md"), "## extra-0001: e\n").unwrap();
        assert!(matches!(
            open_managed(&dest),
            Err(VendorError::Modified { .. })
        ));
        std::fs::remove_file(join(&dest, "spec/ir/mck/extra.md")).unwrap();
        assert!(open_managed(&dest).is_ok());

        let manifest = manifest_path(&dest);
        let text = std::fs::read_to_string(&manifest).unwrap();
        std::fs::write(&manifest, text.replace(">=1, <2", ">=2, <3")).unwrap();
        assert!(matches!(
            open_managed(&dest),
            Err(VendorError::UnsupportedDriver { .. })
        ));
        std::fs::write(
            &manifest,
            text.replace("\"lockVersion\": 1", "\"lockVersion\": 9"),
        )
        .unwrap();
        assert!(
            open_managed(&dest)
                .unwrap_err()
                .to_string()
                .contains("unsupported lockVersion 9")
        );
        std::fs::write(&manifest, "not json").unwrap();
        assert!(matches!(open_managed(&dest), Err(VendorError::Manifest(_))));
    }

    #[test]
    fn update_replaces_a_verified_snapshot_and_reports_what_changed() {
        let repo = repository("one");
        let out = tempfile::tempdir().unwrap();
        let dest = out.path().join("kit");
        vendor(&local(&repo), &dest, None).unwrap();
        assert!(matches!(
            update(&dest, &local(&repo), None).unwrap(),
            UpdateOutcome::Unchanged(_)
        ));

        std::fs::write(
            repo.path().join(KIT_PATH).join("types.md"),
            "## types-0001: two\n```yaml canonical\na: 1\n```\n",
        )
        .unwrap();
        let UpdateOutcome::Updated(report) = update(&dest, &local(&repo), None).unwrap() else {
            panic!()
        };
        assert_eq!(
            report.changes,
            vec![
                ("fixtures/a.json".to_owned(), Change::Removed),
                ("spec/ir/mck/types.md".to_owned(), Change::Changed)
            ]
        );
        assert_eq!(report.leftover, None);
        assert_eq!(open_managed(&dest).unwrap().lock, report.new);
        assert!(
            !dest.join("fixtures").exists(),
            "a file dropped from the closure is removed"
        );
        assert_eq!(
            std::fs::read_dir(out.path()).unwrap().count(),
            1,
            "no backup or staging directory is left behind"
        );
    }

    #[test]
    fn update_refuses_an_edited_snapshot_and_leaves_it_as_it_was() {
        let repo = repository("one");
        let out = tempfile::tempdir().unwrap();
        let dest = out.path().join("kit");
        vendor(&local(&repo), &dest, None).unwrap();
        std::fs::write(dest.join("fixtures/a.json"), "[1]").unwrap();
        std::fs::write(
            repo.path().join(KIT_PATH).join("types.md"),
            "## types-0001: two\n```yaml canonical\na: 1\n```\n",
        )
        .unwrap();

        let error = update(&dest, &local(&repo), None).unwrap_err().to_string();
        assert!(error.contains("altered: fixtures/a.json"), "{error}");
        assert_eq!(
            std::fs::read_to_string(dest.join("fixtures/a.json")).unwrap(),
            "[1]"
        );
    }

    #[test]
    fn update_needs_a_managed_snapshot_and_a_source_other_than_itself() {
        let repo = repository("one");
        let out = tempfile::tempdir().unwrap();
        let plain = out.path().join("plain");
        std::fs::create_dir(&plain).unwrap();
        assert!(
            update(&plain, &VendorSource::Embedded, None)
                .unwrap_err()
                .to_string()
                .contains("is not a managed kit snapshot")
        );

        let dest = out.path().join("kit");
        vendor(&local(&repo), &dest, None).unwrap();
        assert!(
            update(&dest, &VendorSource::Local(dest.clone()), None)
                .unwrap_err()
                .to_string()
                .contains("from itself")
        );
    }

    #[test]
    fn leftovers_from_an_interrupted_run_block_the_next_one_with_a_recovery_step() {
        let repo = repository("one");
        let out = tempfile::tempdir().unwrap();
        let dest = out.path().join("kit");
        vendor(&local(&repo), &dest, None).unwrap();

        let staging = out.path().join(".kit.mck-staging-dead");
        std::fs::create_dir(&staging).unwrap();
        let error = update(&dest, &VendorSource::Embedded, None)
            .unwrap_err()
            .to_string();
        assert!(
            error.contains("interrupted")
                && error.contains(&format!("delete {}", staging.display())),
            "{error}"
        );
        std::fs::remove_dir(&staging).unwrap();

        let backup = out.path().join("kit.mck-old-dead");
        std::fs::rename(&dest, &backup).unwrap();
        let error = vendor(&local(&repo), &dest, None).unwrap_err().to_string();
        assert!(
            error.contains(&format!(
                "renaming {} to {}",
                backup.display(),
                dest.display()
            )),
            "{error}"
        );
    }

    #[test]
    fn diff_lists_added_removed_and_changed_paths_in_order() {
        let a = Snapshot {
            files: [("a".into(), b"1".to_vec()), ("b".into(), b"2".to_vec())].into(),
            corpus_hash: crate::kit::hash::content_hash([]),
        };
        let b = Snapshot {
            files: [("b".into(), b"3".to_vec()), ("c".into(), b"4".to_vec())].into(),
            corpus_hash: crate::kit::hash::content_hash([]),
        };
        let source = LockSource::Local { revision: None };
        assert_eq!(
            diff(&a.lock(source.clone()), &b.lock(source)),
            vec![
                ("a".into(), Change::Removed),
                ("b".into(), Change::Changed),
                ("c".into(), Change::Added)
            ]
        );
    }
}
