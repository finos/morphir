//! Reading a kit snapshot out of a finos/morphir source archive, the
//! `.tar.gz` GitHub serves for one commit (`spec/mck/kit-manifest.md`,
//! "Sources and trust" and "Bounds and unsafe input").
//!
//! This module never touches the network: the caller downloads the archive,
//! within its own size bound, and hands over the file. The archive is read
//! twice. The first pass takes `spec/ir/mck/**` and the fixed inputs; the
//! second takes the fixtures the cases parsed from the first pass name.
//! Nothing outside that closure is extracted, and nothing is written to disk.
//!
//! Every entry must have a safe path under one top-level directory named for
//! the requested commit. The repository legitimately holds symbolic links
//! elsewhere, so the rules about entry type, portable names and collisions
//! apply to the entries a snapshot takes.

use std::borrow::Cow;
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::fmt;
use std::fs::File;
use std::io::{self, Read};
use std::path::Path;

use flate2::read::GzDecoder;
use tar::EntryType;

use super::closure::FIXED_INPUTS;
use super::load::load_kit;
use super::manifest::{CommitId, MAX_FILES, MAX_PATH_BYTES, check_snapshot_path, portable_key};
use super::snapshot::{Snapshot, SnapshotError, collect};
use super::source::{KIT_PATH, KitSource};

/// The bounds of one acquisition.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ArchiveLimits {
    /// Archive entries read, of any kind.
    pub entries: usize,
    /// Total bytes of the entries a snapshot takes.
    pub selected_bytes: u64,
    /// Files in the snapshot.
    pub files: usize,
}

impl ArchiveLimits {
    /// The contract's bounds.
    pub const DEFAULT: Self = Self {
        entries: 100_000,
        selected_bytes: 256 * 1024 * 1024,
        files: MAX_FILES,
    };
}

/// The most bytes a download may carry, checked by whoever downloads.
pub const MAX_DOWNLOAD_BYTES: u64 = 64 * 1024 * 1024;

#[derive(Debug)]
pub enum ArchiveError {
    /// Not a gzip-compressed tar stream, or a truncated one.
    Format(String),
    /// An entry that must never be accepted.
    Unsafe(String),
    /// A bound was exceeded.
    Limit(String),
    /// A well-formed archive with no kit in it.
    NoKit,
    Snapshot(SnapshotError),
    Io(io::Error),
}

impl fmt::Display for ArchiveError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Format(why) => write!(f, "the archive is not a readable .tar.gz: {why}"),
            Self::Unsafe(why) => write!(f, "the archive is refused: {why}"),
            Self::Limit(why) => write!(f, "the archive exceeds a bound: {why}"),
            Self::NoKit => write!(
                f,
                "the archive has no {KIT_PATH}; is it a finos/morphir revision that holds the kit?"
            ),
            Self::Snapshot(error) => write!(f, "{error}"),
            Self::Io(error) => write!(f, "{error}"),
        }
    }
}

impl std::error::Error for ArchiveError {}

impl From<SnapshotError> for ArchiveError {
    fn from(error: SnapshotError) -> Self {
        Self::Snapshot(error)
    }
}

/// An I/O error while decoding is a format problem, not an environment one.
fn format(error: io::Error) -> ArchiveError {
    ArchiveError::Format(error.to_string())
}

/// Splits an entry path into its top-level directory and the path below it,
/// refusing any shape that could name something outside the archive root.
/// Directory entries carry a trailing `/`, which is dropped.
fn split_entry_path(raw: &[u8]) -> Result<(&str, &str), ArchiveError> {
    let path = std::str::from_utf8(raw).map_err(|_| {
        ArchiveError::Unsafe(format!(
            "an entry path is not UTF-8: {}",
            String::from_utf8_lossy(raw)
        ))
    })?;
    let unsafe_path = |why: &str| Err(ArchiveError::Unsafe(format!("entry \"{path}\" {why}")));
    if path.len() > MAX_PATH_BYTES + 256 {
        return unsafe_path("has an overlong path");
    }
    if path.starts_with('/') || path.contains(['\\', '\0']) {
        return unsafe_path("is absolute or contains a backslash or NUL");
    }
    let trimmed = path.strip_suffix('/').unwrap_or(path);
    if trimmed
        .split('/')
        .any(|segment| segment.is_empty() || segment == "." || segment == "..")
    {
        return unsafe_path("has an empty, `.` or `..` segment");
    }
    Ok(trimmed.split_once('/').unwrap_or((trimmed, "")))
}

/// What one pass collected.
#[derive(Default)]
struct Pass {
    files: BTreeMap<String, Vec<u8>>,
    /// NFC, ASCII-lowercased path to the path that claimed it.
    folded: HashMap<String, String>,
    selected_bytes: u64,
}

/// Reads the archive at `archive` once, taking the entries `select` accepts
/// into `pass`.
fn scan(
    archive: &Path,
    revision: &CommitId,
    limits: &ArchiveLimits,
    select: &dyn Fn(&str) -> bool,
    pass: &mut Pass,
) -> Result<(), ArchiveError> {
    let file = File::open(archive).map_err(ArchiveError::Io)?;
    let mut tar = tar::Archive::new(GzDecoder::new(file));
    let mut top: Option<String> = None;
    let mut entries = 0usize;

    for entry in tar.entries().map_err(format)? {
        let mut entry = entry.map_err(format)?;
        entries += 1;
        if entries > limits.entries {
            return Err(ArchiveError::Limit(format!(
                "more than {} entries",
                limits.entries
            )));
        }
        let kind = entry.header().entry_type();
        // Metadata records, not files: GitHub's global comment names the commit.
        if matches!(
            kind,
            EntryType::XGlobalHeader
                | EntryType::XHeader
                | EntryType::GNULongName
                | EntryType::GNULongLink
        ) {
            continue;
        }

        let raw = entry.path_bytes().into_owned();
        let (root, relative) = split_entry_path(&raw)?;
        match &top {
            None => {
                if !root.ends_with(revision.as_str()) {
                    return Err(ArchiveError::Unsafe(format!(
                        "its top-level directory \"{root}\" does not name the requested commit {revision}"
                    )));
                }
                top = Some(root.to_owned());
            }
            Some(expected) if expected != root => {
                return Err(ArchiveError::Unsafe(format!(
                    "it has more than one top-level directory (\"{expected}\" and \"{root}\")"
                )));
            }
            Some(_) => {}
        }
        if relative.is_empty() || kind == EntryType::Directory || !select(relative) {
            continue;
        }

        if kind != EntryType::Regular {
            return Err(ArchiveError::Unsafe(format!(
                "\"{relative}\" is a {} where the kit needs a regular file",
                match kind {
                    EntryType::Symlink => "symbolic link",
                    EntryType::Link => "hard link",
                    _ => "special file",
                }
            )));
        }
        check_snapshot_path(relative).map_err(ArchiveError::Unsafe)?;
        let folded = portable_key(relative);
        if let Some(previous) = pass.folded.get(&folded) {
            return Err(ArchiveError::Unsafe(if previous == relative {
                format!("\"{relative}\" appears twice")
            } else {
                format!(
                    "\"{relative}\" and \"{previous}\" collide on a case-insensitive or normalizing file system"
                )
            }));
        }
        pass.folded.insert(folded, relative.to_owned());

        let size = entry.header().size().map_err(format)?;
        pass.selected_bytes = pass.selected_bytes.saturating_add(size);
        if pass.selected_bytes > limits.selected_bytes {
            return Err(ArchiveError::Limit(format!(
                "the selected files exceed {} bytes",
                limits.selected_bytes
            )));
        }
        if pass.files.len() >= limits.files {
            return Err(ArchiveError::Limit(format!(
                "more than {} files",
                limits.files
            )));
        }
        let mut bytes = Vec::with_capacity(usize::try_from(size).unwrap_or(0));
        (&mut entry)
            .take(size)
            .read_to_end(&mut bytes)
            .map_err(format)?;
        if bytes.len() as u64 != size {
            return Err(ArchiveError::Format(format!("\"{relative}\" is truncated")));
        }
        pass.files.insert(relative.to_owned(), bytes);
    }

    if top.is_none() {
        return Err(ArchiveError::Format("it holds no entries".to_owned()));
    }
    Ok(())
}

fn source_of(files: &BTreeMap<String, Vec<u8>>, revision: &CommitId) -> KitSource {
    KitSource::map(
        format!("github:finos/morphir@{revision}"),
        files
            .iter()
            .map(|(path, bytes)| (path.clone(), Cow::Owned(bytes.clone())))
            .collect(),
    )
}

/// The kit snapshot in the finos/morphir archive at `archive`, checked
/// against every bound and safety rule before anything is returned.
pub fn snapshot_from_archive(
    archive: &Path,
    revision: &CommitId,
    limits: &ArchiveLimits,
) -> Result<Snapshot, ArchiveError> {
    let kit_prefix = format!("{KIT_PATH}/");
    let mut pass = Pass::default();
    scan(
        archive,
        revision,
        limits,
        &|path| path.starts_with(&kit_prefix) || FIXED_INPUTS.contains(&path),
        &mut pass,
    )?;
    if !pass.files.keys().any(|path| path.starts_with(&kit_prefix)) {
        return Err(ArchiveError::NoKit);
    }

    // The fixtures the cases name, which the first pass could not know.
    let kit = load_kit(source_of(&pass.files, revision)).map_err(ArchiveError::Io)?;
    let wanted: BTreeSet<String> = kit
        .cases
        .iter()
        .flat_map(|case| &case.fences)
        .filter(|fence| fence.info.language == super::syntax::info_string::Language::Text)
        .map(|fence| fence.text_target().to_owned())
        .filter(|target| !pass.files.contains_key(target) && check_snapshot_path(target).is_ok())
        .collect();
    if !wanted.is_empty() {
        scan(
            archive,
            revision,
            limits,
            &|path| wanted.contains(path),
            &mut pass,
        )?;
    }

    let kit = load_kit(source_of(&pass.files, revision)).map_err(ArchiveError::Io)?;
    Ok(collect(&kit)?)
}

#[cfg(test)]
mod tests {
    use std::io::Write as _;

    use flate2::Compression;
    use flate2::write::GzEncoder;
    use tar::{Builder, Header};

    use super::*;

    const REVISION: &str = "a2803f2cbfbb9baffe8a939e9462b18fd5bcdda0";

    fn revision() -> CommitId {
        CommitId::parse(REVISION).unwrap()
    }

    /// One archive entry. Names are written raw, so the tests can build the
    /// hostile paths `tar::Builder` itself would refuse.
    enum Entry<'a> {
        File(&'a str, &'a str),
        Dir(&'a str),
        Symlink(&'a str, &'a str),
        HardLink(&'a str, &'a str),
        Fifo(&'a str),
    }

    fn archive(entries: &[Entry]) -> tempfile::NamedTempFile {
        let mut builder = Builder::new(GzEncoder::new(Vec::new(), Compression::fast()));
        let mut global = Header::new_ustar();
        global.set_entry_type(EntryType::XGlobalHeader);
        let comment = format!("52 comment={REVISION}\n");
        global.set_size(comment.len() as u64);
        global.as_old_mut().name[..17].copy_from_slice(b"pax_global_header");
        global.set_cksum();
        builder.append(&global, comment.as_bytes()).unwrap();

        for entry in entries {
            let mut header = Header::new_gnu();
            let (name, kind, data, link): (&str, EntryType, &[u8], Option<&str>) = match entry {
                Entry::File(name, text) => (name, EntryType::Regular, text.as_bytes(), None),
                Entry::Dir(name) => (name, EntryType::Directory, b"", None),
                Entry::Symlink(name, to) => (name, EntryType::Symlink, b"", Some(to)),
                Entry::HardLink(name, to) => (name, EntryType::Link, b"", Some(to)),
                Entry::Fifo(name) => (name, EntryType::Fifo, b"", None),
            };
            // A long path travels in a GNU long-name record before its entry,
            // as real archives carry it in an extended header.
            if name.len() > 100 {
                let mut long = Header::new_gnu();
                long.as_old_mut().name[..13].copy_from_slice(b"././@LongLink");
                long.set_entry_type(EntryType::GNULongName);
                long.set_size(name.len() as u64 + 1);
                long.set_cksum();
                builder
                    .append(&long, [name.as_bytes(), b"\0"].concat().as_slice())
                    .unwrap();
            }
            let short = &name.as_bytes()[..name.len().min(100)];
            header.as_old_mut().name[..short.len()].copy_from_slice(short);
            if let Some(to) = link {
                header.as_old_mut().linkname[..to.len()].copy_from_slice(to.as_bytes());
            }
            header.set_entry_type(kind);
            header.set_mode(0o644);
            header.set_size(data.len() as u64);
            header.set_cksum();
            builder.append(&header, data).unwrap();
        }
        let bytes = builder.into_inner().unwrap().finish().unwrap();
        let mut file = tempfile::NamedTempFile::new().unwrap();
        file.write_all(&bytes).unwrap();
        file
    }

    fn top(path: &str) -> String {
        format!("morphir-{REVISION}/{path}")
    }

    /// A finos/morphir-shaped archive holding a one-case kit and unrelated content.
    fn good_entries() -> Vec<(String, String)> {
        let mut files = vec![
            (
                top("spec/ir/mck/types.feature"),
                "@node:Type\nFeature: Types\n  Scenario: types-0001 t\n    Then its canonical YAML spelling is a\n".to_owned(),
            ),
            (top("spec/ir/mck/README.md"), "readme".to_owned()),
            (top("website/fixture.json"), "{}".to_owned()),
            (top("website/unrelated.json"), "{}".to_owned()),
            (top("README.md"), "repo".to_owned()),
        ];
        files.extend(
            FIXED_INPUTS
                .iter()
                .map(|fixed| (top(fixed), "{}".to_owned())),
        );
        files
    }

    fn build(extra: Vec<Entry>) -> tempfile::NamedTempFile {
        let good = good_entries();
        let root = top("");
        let mut entries = vec![Entry::Dir(&root)];
        entries.extend(good.iter().map(|(path, text)| Entry::File(path, text)));
        entries.extend(extra);
        archive(&entries)
    }

    fn refused(extra: Vec<Entry>, expected: &str) {
        let file = build(extra);
        let error = snapshot_from_archive(file.path(), &revision(), &ArchiveLimits::DEFAULT)
            .unwrap_err()
            .to_string();
        assert!(error.contains(expected), "{error:?} lacks {expected:?}");
    }

    #[test]
    fn takes_the_kit_and_the_fixed_inputs_and_nothing_else() {
        let file = build(vec![]);
        let snapshot =
            snapshot_from_archive(file.path(), &revision(), &ArchiveLimits::DEFAULT).unwrap();
        let mut expected = vec!["spec/ir/mck/README.md", "spec/ir/mck/types.feature"];
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
    }

    #[test]
    fn a_symbolic_link_outside_the_closure_is_ignored() {
        let (link, target) = (top("wit/deps/morphir-ir"), "../../elsewhere".to_owned());
        let file = build(vec![Entry::Symlink(&link, &target)]);
        assert!(snapshot_from_archive(file.path(), &revision(), &ArchiveLimits::DEFAULT).is_ok());
    }

    #[test]
    fn refuses_a_path_that_could_leave_the_archive_root() {
        refused(vec![Entry::File("../evil.md", "x")], "`..` segment");
        refused(
            vec![Entry::File(&top("spec/ir/mck/../../../evil.md"), "x")],
            "`..` segment",
        );
        refused(vec![Entry::File("/etc/passwd", "x")], "is absolute");
        refused(
            vec![Entry::File(&top("spec\\ir\\mck\\x.md"), "x")],
            "backslash",
        );
        refused(vec![Entry::File(&top("spec//ir/mck/x.md"), "x")], "empty");
    }

    #[test]
    fn refuses_an_archive_for_another_commit_or_with_two_roots() {
        let other = "morphir-0000000000000000000000000000000000000000/spec/ir/mck/types.md";
        let file = archive(&[Entry::File(
            other,
            "## types-0001: t\n```yaml canonical\na: 1\n```\n",
        )]);
        let error = snapshot_from_archive(file.path(), &revision(), &ArchiveLimits::DEFAULT)
            .unwrap_err()
            .to_string();
        assert!(
            error.contains("does not name the requested commit"),
            "{error}"
        );
        refused(
            vec![Entry::File("elsewhere/x", "x")],
            "more than one top-level directory",
        );
    }

    #[test]
    fn refuses_a_link_or_special_file_where_the_kit_needs_a_file() {
        let path = top("spec/ir/mck/linked.md");
        refused(
            vec![Entry::Symlink(&path, "/etc/passwd")],
            "is a symbolic link",
        );
        refused(vec![Entry::HardLink(&path, "README.md")], "is a hard link");
        refused(vec![Entry::Fifo(&path)], "is a special file");
    }

    #[test]
    fn refuses_duplicates_collisions_and_unportable_names_in_the_closure() {
        let types = top("spec/ir/mck/types.feature");
        refused(vec![Entry::File(&types, "again")], "appears twice");
        refused(
            vec![Entry::File(&top("spec/ir/mck/TYPES.feature"), "x")],
            "collide",
        );
        refused(
            vec![
                Entry::File(&top("spec/ir/mck/caf\u{e9}.md"), "x"),
                Entry::File(&top("spec/ir/mck/cafe\u{301}.md"), "x"),
            ],
            "collide",
        );
        refused(
            vec![Entry::File(&top("spec/ir/mck/nul.md"), "x")],
            "reserved Windows device",
        );
        refused(
            vec![Entry::File(&top("spec/ir/mck/trailing."), "x")],
            "ending in a dot",
        );
    }

    #[test]
    fn enforces_the_entry_size_and_file_bounds() {
        let file = build(vec![]);
        let tight = |limits: ArchiveLimits| {
            snapshot_from_archive(file.path(), &revision(), &limits)
                .unwrap_err()
                .to_string()
        };
        assert!(
            tight(ArchiveLimits {
                entries: 3,
                ..ArchiveLimits::DEFAULT
            })
            .contains("more than 3 entries")
        );
        assert!(
            tight(ArchiveLimits {
                selected_bytes: 10,
                ..ArchiveLimits::DEFAULT
            })
            .contains("exceed 10 bytes")
        );
        assert!(
            tight(ArchiveLimits {
                files: 2,
                ..ArchiveLimits::DEFAULT
            })
            .contains("more than 2 files")
        );
    }

    #[test]
    fn a_revision_without_a_fixed_input_cannot_be_snapshotted() {
        let good = good_entries();
        let root = top("");
        let mut entries = vec![Entry::Dir(&root)];
        entries.extend(
            good.iter()
                .filter(|(p, _)| !p.ends_with(FIXED_INPUTS[0]))
                .map(|(p, t)| Entry::File(p, t)),
        );
        let file = archive(&entries);
        let error = snapshot_from_archive(file.path(), &revision(), &ArchiveLimits::DEFAULT)
            .unwrap_err()
            .to_string();
        assert!(
            error.contains(&format!("lacks {}", FIXED_INPUTS[0])),
            "{error}"
        );
    }

    #[test]
    fn vendoring_from_an_archive_records_github_provenance_and_verifies() {
        use crate::kit::manifest::LockSource;
        use crate::kit::vendor::{VendorOutcome, VendorSource, open_managed, vendor};

        let file = build(vec![]);
        let out = tempfile::tempdir().unwrap();
        let dest = out.path().join("vendor/morphir-mck");
        let source = VendorSource::GithubArchive {
            archive: file.path().to_path_buf(),
            revision: revision(),
        };
        let VendorOutcome::Created(lock) = vendor(&source, &dest, None).unwrap() else {
            panic!("expected a new snapshot")
        };
        assert_eq!(
            lock.source,
            LockSource::Github {
                revision: revision()
            }
        );
        let managed = open_managed(&dest).unwrap();
        assert_eq!(managed.lock, lock);
        assert!(matches!(
            vendor(&source, &dest, None).unwrap(),
            VendorOutcome::Unchanged(_)
        ));
    }

    #[test]
    fn refuses_what_is_not_a_tar_gz_or_holds_no_kit() {
        let mut junk = tempfile::NamedTempFile::new().unwrap();
        junk.write_all(b"not an archive").unwrap();
        let error = snapshot_from_archive(junk.path(), &revision(), &ArchiveLimits::DEFAULT)
            .unwrap_err()
            .to_string();
        assert!(error.contains("not a readable .tar.gz"), "{error}");

        let file = archive(&[Entry::File(&top("README.md"), "repo")]);
        let error = snapshot_from_archive(file.path(), &revision(), &ArchiveLimits::DEFAULT)
            .unwrap_err()
            .to_string();
        assert!(error.contains("has no spec/ir/mck"), "{error}");
    }
}
