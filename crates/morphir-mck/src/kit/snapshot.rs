//! Kit snapshots (`spec/mck/kit-manifest.md`): collecting a kit's complete
//! input closure, writing it under a directory with its manifest, and
//! verifying a directory against the manifest it carries.

use std::collections::{BTreeMap, BTreeSet};
use std::fmt;
use std::io;
use std::path::{Path, PathBuf};

use super::closure::FIXED_INPUTS;
use super::hash::{ContentDigest, content_hash, sha256_hex};
use super::load::Kit;
use super::manifest::{
    DriverRange, Lock, LockFile, LockSource, MANIFEST_NAME, MAX_FILES, check_snapshot_path,
    portable_key,
};
use super::syntax::text::utf16_cmp;

/// Files a snapshot root may hold beside its inventory without making it
/// "modified". `.gitattributes` lets an implementor pin line endings next to
/// the data, as `kit vendor` advises.
pub const ALLOWED_UNMANAGED: &[&str] = &[MANIFEST_NAME, ".gitattributes"];

/// A kit's complete input closure, ready to write.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Snapshot {
    pub files: BTreeMap<String, Vec<u8>>,
    /// The legacy corpus identity: kit files plus `text` fixtures.
    pub corpus_hash: ContentDigest,
}

#[derive(Debug)]
pub enum SnapshotError {
    /// A kit with errors has no identity worth recording.
    KitHasErrors(usize),
    /// A parent-owned input every snapshot carries is absent from the source.
    MissingFixedInput(String),
    UnsafePath(String),
    /// A symbolic link or special file where the snapshot needs a regular file.
    NotRegular(String),
    /// Two paths only a case-sensitive, non-normalizing file system can tell apart.
    Collision(String, String),
    TooManyFiles(usize),
    Io(io::Error),
}

impl fmt::Display for SnapshotError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::KitHasErrors(n) => write!(
                f,
                "the kit has {n} error(s); run `morphir mck check` on it first"
            ),
            Self::MissingFixedInput(path) => write!(
                f,
                "the source lacks {path}, which every kit snapshot carries"
            ),
            Self::UnsafePath(why) => f.write_str(why),
            Self::NotRegular(path) => write!(
                f,
                "{path} is a symbolic link or special file; a kit snapshot takes regular files only"
            ),
            Self::Collision(a, b) => write!(
                f,
                "{a} and {b} collide on a case-insensitive or normalizing file system"
            ),
            Self::TooManyFiles(n) => write!(
                f,
                "the kit closure has {n} files; a snapshot holds at most {MAX_FILES}"
            ),
            Self::Io(error) => write!(f, "{error}"),
        }
    }
}

impl std::error::Error for SnapshotError {}

impl From<io::Error> for SnapshotError {
    fn from(error: io::Error) -> Self {
        Self::Io(error)
    }
}

/// Collects `kit`'s closure: every file under the kit directory, every
/// `text` fixture, and the fixed inputs.
pub fn collect(kit: &Kit) -> Result<Snapshot, SnapshotError> {
    let Some(mut files) = kit.corpus_files()? else {
        return Err(SnapshotError::KitHasErrors(kit.errors.len()));
    };
    let corpus_hash = content_hash(
        files
            .iter()
            .map(|(path, bytes)| (path.as_str(), bytes.as_slice())),
    );
    for fixed in FIXED_INPUTS {
        let bytes = kit
            .source
            .read(fixed)?
            .ok_or_else(|| SnapshotError::MissingFixedInput((*fixed).to_owned()))?;
        files.insert((*fixed).to_owned(), bytes.into_owned());
    }
    if files.len() > MAX_FILES {
        return Err(SnapshotError::TooManyFiles(files.len()));
    }
    // The corpus must not shrink silently: a link or special file inside the
    // kit directory, which loading skips, is refused here.
    if let Some(path) = kit.source.irregular_entries()?.into_iter().next() {
        return Err(SnapshotError::NotRegular(path));
    }
    let mut keys: BTreeMap<String, &str> = BTreeMap::new();
    for path in files.keys() {
        check_snapshot_path(path).map_err(SnapshotError::UnsafePath)?;
        if !kit.source.is_plain_file(path)? {
            return Err(SnapshotError::NotRegular(path.clone()));
        }
        if let Some(other) = keys.insert(portable_key(path), path) {
            return Err(SnapshotError::Collision(other.to_owned(), path.clone()));
        }
    }
    Ok(Snapshot { files, corpus_hash })
}

impl Snapshot {
    /// The manifest describing these files.
    pub fn lock(&self, source: LockSource) -> Lock {
        let mut files: Vec<LockFile> = self
            .files
            .iter()
            .map(|(path, bytes)| LockFile {
                path: path.clone(),
                sha256: sha256_hex(bytes),
                size: bytes.len() as u64,
            })
            .collect();
        files.sort_by(|a, b| utf16_cmp(&a.path, &b.path));
        let mut lock = Lock {
            driver_contract: DriverRange::CURRENT,
            source,
            corpus_hash: self.corpus_hash.clone(),
            snapshot_digest: content_hash([]),
            files,
        };
        lock.snapshot_digest = lock.inventory_digest();
        lock
    }

    /// Writes the files and `lock` under `dir`, which must not exist yet.
    pub fn write(&self, dir: &Path, lock: &Lock) -> io::Result<()> {
        std::fs::create_dir(dir)?;
        for (path, bytes) in &self.files {
            let target = join(dir, path);
            if let Some(parent) = target.parent() {
                std::fs::create_dir_all(parent)?;
            }
            write_new(&target, bytes)?;
        }
        write_new(&dir.join(MANIFEST_NAME), lock.render().as_bytes())
    }
}

fn write_new(path: &Path, bytes: &[u8]) -> io::Result<()> {
    use std::io::Write as _;
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)?;
    file.write_all(bytes)?;
    file.sync_all()
}

/// `root` joined with a checked snapshot path, one segment at a time.
pub fn join(root: &Path, path: &str) -> PathBuf {
    path.split('/')
        .fold(root.to_path_buf(), |dir, segment| dir.join(segment))
}

/// A way a directory departs from its manifest.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Problem {
    Missing(String),
    Altered(String),
    /// A symbolic link, directory or special file where a regular file belongs.
    NotRegular(String),
    /// A file the manifest does not list.
    Extra(String),
}

impl fmt::Display for Problem {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Missing(path) => write!(f, "missing: {path}"),
            Self::Altered(path) => write!(f, "altered: {path}"),
            Self::NotRegular(path) => write!(f, "not a regular file: {path}"),
            Self::Extra(path) => write!(f, "not in the manifest: {path}"),
        }
    }
}

fn walk(dir: &Path, prefix: &str, out: &mut Vec<(String, std::fs::FileType)>) -> io::Result<()> {
    for entry in std::fs::read_dir(dir)? {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().into_owned();
        let key = if prefix.is_empty() {
            name
        } else {
            format!("{prefix}/{name}")
        };
        // `file_type` does not follow links, so a linked directory is
        // reported rather than walked into.
        let kind = entry.file_type()?;
        if kind.is_dir() {
            walk(&entry.path(), &key, out)?;
        } else {
            out.push((key, kind));
        }
    }
    Ok(())
}

/// Every way `root` departs from `lock`, in inventory order then walk order.
/// Empty means every listed file is a regular file with the recorded size
/// and SHA-256, and nothing else is there but the allowed unmanaged files.
pub fn verify(root: &Path, lock: &Lock) -> io::Result<Vec<Problem>> {
    let mut problems = Vec::new();
    let mut listed = BTreeSet::new();
    for entry in &lock.files {
        listed.insert(entry.path.as_str());
        let path = join(root, &entry.path);
        let metadata = match std::fs::symlink_metadata(&path) {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                problems.push(Problem::Missing(entry.path.clone()));
                continue;
            }
            Err(error) => return Err(error),
        };
        if !metadata.file_type().is_file() {
            problems.push(Problem::NotRegular(entry.path.clone()));
        } else if metadata.len() != entry.size || sha256_hex(&std::fs::read(&path)?) != entry.sha256
        {
            problems.push(Problem::Altered(entry.path.clone()));
        }
    }

    let mut present = Vec::new();
    walk(root, "", &mut present)?;
    present.sort_by(|a, b| utf16_cmp(&a.0, &b.0));
    for (path, kind) in present {
        if listed.contains(path.as_str()) || ALLOWED_UNMANAGED.contains(&path.as_str()) {
            continue;
        }
        problems.push(if kind.is_file() {
            Problem::Extra(path)
        } else {
            Problem::NotRegular(path)
        });
    }
    Ok(problems)
}

#[cfg(test)]
mod tests {
    use std::borrow::Cow;

    use super::*;
    use crate::kit::load::load_kit;
    use crate::kit::source::KitSource;

    const CASE: &str = "## types-0001: t\n```text canonical\nfixtures/a.json\n```\n";

    fn map_kit(extra: &[(&str, &str)]) -> Kit {
        let mut files: BTreeMap<String, Cow<'static, [u8]>> = [
            ("spec/ir/mck/types.md", CASE),
            ("spec/ir/mck/README.md", "readme"),
            ("fixtures/a.json", "{}"),
            ("website/unrelated.json", "{}"),
        ]
        .iter()
        .chain(extra)
        .map(|(p, t)| ((*p).to_owned(), Cow::Owned(t.as_bytes().to_vec())))
        .collect();
        for fixed in FIXED_INPUTS {
            files
                .entry((*fixed).to_owned())
                .or_insert(Cow::Borrowed(b"{}"));
        }
        load_kit(KitSource::map("test kit", files)).unwrap()
    }

    #[test]
    fn collects_the_kit_its_fixtures_and_the_fixed_inputs_only() {
        let snapshot = collect(&map_kit(&[])).unwrap();
        let mut expected: Vec<&str> = vec![
            "fixtures/a.json",
            "spec/ir/mck/README.md",
            "spec/ir/mck/types.md",
        ];
        expected.extend(FIXED_INPUTS);
        expected.sort_unstable();
        assert_eq!(
            snapshot
                .files
                .keys()
                .map(String::as_str)
                .collect::<Vec<_>>(),
            expected
        );
        assert!(!snapshot.files.contains_key("website/unrelated.json"));
    }

    #[test]
    fn the_corpus_hash_covers_only_the_legacy_corpus_set() {
        let kit = map_kit(&[]);
        let snapshot = collect(&kit).unwrap();
        assert_eq!(
            Some(snapshot.corpus_hash.clone()),
            kit.corpus_hash().unwrap()
        );
        let lock = snapshot.lock(LockSource::Local { revision: None });
        assert_ne!(
            lock.snapshot_digest, lock.corpus_hash,
            "the full inventory adds the fixed inputs"
        );
    }

    #[test]
    fn refuses_a_kit_with_errors_or_without_a_fixed_input() {
        let broken = map_kit(&[("spec/ir/mck/values.md", "## values-1: bad\n")]);
        assert!(matches!(
            collect(&broken),
            Err(SnapshotError::KitHasErrors(1))
        ));

        let files = [(
            "spec/ir/mck/types.md",
            "## types-0001: t\n```yaml canonical\na: 1\n```\n",
        )]
        .iter()
        .map(|(p, t)| ((*p).to_owned(), Cow::Owned(t.as_bytes().to_vec())))
        .collect();
        let kit = load_kit(KitSource::map("bare", files)).unwrap();
        assert!(
            matches!(collect(&kit), Err(SnapshotError::MissingFixedInput(path)) if path == FIXED_INPUTS[0])
        );
    }

    #[test]
    fn refuses_paths_a_folding_file_system_cannot_tell_apart() {
        for (a, b) in [
            (
                "spec/ir/mck/documents/X.yaml",
                "spec/ir/mck/documents/x.yaml",
            ),
            (
                "spec/ir/mck/documents/caf\u{e9}.yaml",
                "spec/ir/mck/documents/cafe\u{301}.yaml",
            ),
        ] {
            let error = collect(&map_kit(&[(a, "a: 1"), (b, "a: 2")]))
                .unwrap_err()
                .to_string();
            assert!(
                error.contains("collide on a case-insensitive or normalizing file system"),
                "{error}"
            );
        }
    }

    #[cfg(unix)]
    #[test]
    fn refuses_a_symbolic_link_in_the_kit_or_as_a_fixture() {
        use std::os::unix::fs::symlink;

        let repo = tempfile::tempdir().unwrap();
        let kit_dir = repo.path().join("spec/ir/mck");
        std::fs::create_dir_all(&kit_dir).unwrap();
        std::fs::create_dir_all(repo.path().join("fixtures")).unwrap();
        std::fs::write(kit_dir.join("types.md"), CASE).unwrap();
        std::fs::write(repo.path().join("fixtures/real.json"), "{}").unwrap();
        for fixed in FIXED_INPUTS {
            let path = join(repo.path(), fixed);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(path, "{}").unwrap();
        }
        symlink(
            repo.path().join("fixtures/real.json"),
            repo.path().join("fixtures/a.json"),
        )
        .unwrap();
        let source = || KitSource::directory(&kit_dir, Some(repo.path()));
        let error = collect(&load_kit(source()).unwrap())
            .unwrap_err()
            .to_string();
        assert!(
            error.contains("fixtures/a.json is a symbolic link"),
            "{error}"
        );

        std::fs::remove_file(repo.path().join("fixtures/a.json")).unwrap();
        std::fs::rename(
            repo.path().join("fixtures/real.json"),
            repo.path().join("fixtures/a.json"),
        )
        .unwrap();
        std::fs::write(repo.path().join("elsewhere.md"), "## values-0001: v\n").unwrap();
        symlink(repo.path().join("elsewhere.md"), kit_dir.join("values.md")).unwrap();
        let kit = load_kit(source()).unwrap();
        assert_eq!(
            kit.errors,
            vec![],
            "check skips the link, as the first driver did"
        );
        let error = collect(&kit).unwrap_err().to_string();
        assert!(
            error.contains("spec/ir/mck/values.md is a symbolic link"),
            "{error}"
        );
    }

    #[test]
    fn a_written_snapshot_verifies_and_reads_back_as_the_same_kit() {
        let snapshot = collect(&map_kit(&[])).unwrap();
        let lock = snapshot.lock(LockSource::Local { revision: None });
        let parent = tempfile::tempdir().unwrap();
        let root = parent.path().join("vendor");
        snapshot.write(&root, &lock).unwrap();

        assert_eq!(verify(&root, &lock).unwrap(), vec![]);
        assert_eq!(
            Lock::parse(&std::fs::read(root.join(MANIFEST_NAME)).unwrap()).unwrap(),
            lock
        );
        let reread = load_kit(KitSource::directory(&root.join("spec/ir/mck"), None)).unwrap();
        assert_eq!(reread.errors, vec![]);
        assert_eq!(
            reread.corpus_hash().unwrap(),
            Some(lock.corpus_hash.clone())
        );
        assert!(
            snapshot.write(&root, &lock).is_err(),
            "writing never overwrites"
        );
    }

    #[test]
    fn verify_reports_missing_altered_extra_and_irregular_files() {
        let snapshot = collect(&map_kit(&[])).unwrap();
        let lock = snapshot.lock(LockSource::Local { revision: None });
        let parent = tempfile::tempdir().unwrap();
        let root = parent.path().join("vendor");
        snapshot.write(&root, &lock).unwrap();

        std::fs::remove_file(root.join("fixtures/a.json")).unwrap();
        std::fs::write(root.join("spec/ir/mck/README.md"), "edited").unwrap();
        std::fs::write(root.join("spec/ir/mck/new.md"), "## new-0001: n\n").unwrap();
        std::fs::create_dir(root.join("spec/ir/mck/types.md.d")).unwrap();
        std::fs::write(root.join("spec/ir/mck/types.md.d/x"), "").unwrap();
        std::fs::write(root.join(".gitattributes"), "* -text\n").unwrap();

        assert_eq!(
            verify(&root, &lock).unwrap(),
            vec![
                Problem::Missing("fixtures/a.json".into()),
                Problem::Altered("spec/ir/mck/README.md".into()),
                Problem::Extra("spec/ir/mck/new.md".into()),
                Problem::Extra("spec/ir/mck/types.md.d/x".into()),
            ]
        );
    }

    #[test]
    fn a_same_size_edit_is_caught_by_the_hash() {
        let snapshot = collect(&map_kit(&[])).unwrap();
        let lock = snapshot.lock(LockSource::Local { revision: None });
        let parent = tempfile::tempdir().unwrap();
        let root = parent.path().join("vendor");
        snapshot.write(&root, &lock).unwrap();
        std::fs::write(root.join("fixtures/a.json"), "[]").unwrap();
        assert_eq!(
            verify(&root, &lock).unwrap(),
            vec![Problem::Altered("fixtures/a.json".into())]
        );
    }

    #[cfg(unix)]
    #[test]
    fn a_symbolic_link_is_never_a_listed_file() {
        let snapshot = collect(&map_kit(&[])).unwrap();
        let lock = snapshot.lock(LockSource::Local { revision: None });
        let parent = tempfile::tempdir().unwrap();
        let root = parent.path().join("vendor");
        snapshot.write(&root, &lock).unwrap();
        let outside = parent.path().join("outside.json");
        std::fs::write(&outside, "{}").unwrap();
        std::fs::remove_file(root.join("fixtures/a.json")).unwrap();
        std::os::unix::fs::symlink(&outside, root.join("fixtures/a.json")).unwrap();
        assert_eq!(
            verify(&root, &lock).unwrap(),
            vec![Problem::NotRegular("fixtures/a.json".into())]
        );
    }
}
