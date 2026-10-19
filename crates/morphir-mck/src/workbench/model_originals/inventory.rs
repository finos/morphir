//! Pure inventory metadata verification. This does not authenticate a capture or
//! verify file contents, projection bytes, host accounting or capture lifetime.
use super::{
    EntryId, InvalidFrame, Root, RootKind, RootPath, Schema, folded, parse, portable_path, validate,
};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    fmt,
};

const MAX_ENTRIES: usize = 100064;
const MAX_DESCENDANTS: usize = 100000;
const MAX_BYTES: usize = 64 * 1024 * 1024;
const MAX_REPLY_BYTES: usize = 128 * 1024;
const DOMAIN: &[u8] = b"morphir/workbench/model-originals/0.1.0-draft.1\0";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InventoryError {
    Frame(InvalidFrame),
    Counts,
    Ordering,
    DuplicateIdentity,
    PathSet,
    Coverage,
    DescendantDepth,
    SourceBudget,
    MetadataBudget,
    Digest,
}
impl From<InvalidFrame> for InventoryError {
    fn from(value: InvalidFrame) -> Self {
        Self::Frame(value)
    }
}
impl fmt::Display for InventoryError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Frame(_) => "invalid model-originals inventory frame",
            Self::Counts => "inventory counts differ from the complete entries",
            Self::Ordering => "inventory paths are not strictly ordered UTF-8 bytes",
            Self::DuplicateIdentity => "inventory entry identities are not unique",
            Self::PathSet => "inventory paths contain aliases or file-prefix conflicts",
            Self::Coverage => "inventory does not cover exactly its declared roots",
            Self::DescendantDepth => "inventory exceeds the depth below a selected root",
            Self::SourceBudget => "inventory originals exceed the aggregate source bound",
            Self::MetadataBudget => "inventory strings exceed the metadata bound",
            Self::Digest => "inventory digest differs from the exact preimage",
        })
    }
}
impl std::error::Error for InventoryError {}

// Separate digest roles prevent a source-file digest being used as an inventory
// commitment. The constructors remain private to these validated boundaries.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct ContentSha256([u8; 32]);
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct InventorySha256([u8; 32]);
impl InventorySha256 {
    pub fn to_hex(self) -> String {
        self.0.iter().map(|byte| format!("{byte:02x}")).collect()
    }
}
fn hash(value: &Value) -> Result<[u8; 32], InvalidFrame> {
    let text = value.as_str().ok_or(InvalidFrame::Shape)?;
    if text.len() != 64
        || !text
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        return Err(InvalidFrame::Shape);
    }
    let mut result = [0; 32];
    for (index, output) in result.iter_mut().enumerate() {
        *output = u8::from_str_radix(&text[index * 2..index * 2 + 2], 16)
            .map_err(|_| InvalidFrame::Shape)?;
    }
    Ok(result)
}
fn count(value: &Value, maximum: usize) -> Result<usize, InvalidFrame> {
    super::super::artifacts::integer(value, maximum).map_err(|_| InvalidFrame::Range)
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct EntryPath(String);
impl EntryPath {
    fn parse(value: &Value) -> Result<Self, InvalidFrame> {
        let path = portable_path(value)?;
        // A 128-component root plus 128 descendant levels, checked separately
        // against the actual selected root in check_coverage.
        if path.split('/').count() > 256 {
            return Err(InvalidFrame::Path);
        }
        Ok(Self(path.to_owned()))
    }
}
#[derive(Debug, Clone, PartialEq, Eq)]
enum EntryContent {
    Directory,
    File {
        byte_length: usize,
        sha256: ContentSha256,
    },
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InventoryEntry {
    id: EntryId,
    path: EntryPath,
    content: EntryContent,
}
impl InventoryEntry {
    pub fn id(&self) -> &EntryId {
        &self.id
    }
    pub fn path(&self) -> &str {
        &self.path.0
    }
    pub fn kind(&self) -> RootKind {
        match self.content {
            EntryContent::Directory => RootKind::Directory,
            EntryContent::File { .. } => RootKind::File,
        }
    }
    fn parse(value: &Value) -> Result<Self, InvalidFrame> {
        // A malformed directory can still carry a file-only numeric member.
        // Guard every numeric schema location before evaluating oneOf branches.
        let byte_length = value
            .get("byteLength")
            .map(|length| count(length, MAX_BYTES))
            .transpose()?;
        let content = match value["kind"].as_str() {
            Some("directory") => EntryContent::Directory,
            Some("file") => EntryContent::File {
                byte_length: byte_length.ok_or(InvalidFrame::Shape)?,
                sha256: ContentSha256(hash(&value["sha256"])?),
            },
            _ => return Err(InvalidFrame::Shape),
        };
        // Exact integer preflight precedes jsonschema's numeric implementation.
        validate(Schema::Entry, value)?;
        Ok(Self {
            id: EntryId::parse(&value["entryId"])?,
            path: EntryPath::parse(&value["path"])?,
            content,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct Summary {
    entries: usize,
    files: usize,
    directories: usize,
    source_bytes: usize,
    digest: InventorySha256,
}
impl Summary {
    fn parse(value: &Value) -> Result<Self, InvalidFrame> {
        let result = Self {
            entries: count(&value["entryCount"], MAX_ENTRIES)?,
            files: count(&value["fileCount"], MAX_ENTRIES)?,
            directories: count(&value["directoryCount"], MAX_ENTRIES)?,
            source_bytes: count(&value["sourceByteLength"], MAX_BYTES)?,
            digest: InventorySha256(hash(&value["sha256"])?),
        };
        validate(Schema::Inventory, value)?;
        Ok(result)
    }
}

/// Complete, internally consistent inventory metadata only. A caller must still
/// verify every file's actual bytes and its authenticated/current capture before
/// publishing an original owner. Missing descendants require independent source
/// evidence; a self-consistent inventory alone cannot establish completeness.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Inventory {
    entries: Vec<InventoryEntry>,
    summary: Summary,
}
impl Inventory {
    pub fn entries(&self) -> &[InventoryEntry] {
        &self.entries
    }
    pub fn source_byte_length(&self) -> usize {
        self.summary.source_bytes
    }
    pub fn digest(&self) -> InventorySha256 {
        self.summary.digest
    }

    /// `ready` is a bounded ready-result object. Each entry is an exact JSON
    /// fragment from the pages, bounded by its enclosing reply. Keeping separate
    /// fragments avoids imposing a new assembled-document limit on valid paged
    /// inventories. Page binding/progress and actual source bytes still require
    /// independent checks; this parser does not grant those authorities.
    pub fn parse(ready: &str, entry_frames: &[&str]) -> Result<Self, InventoryError> {
        let ready = parse(ready, MAX_REPLY_BYTES)?;
        let summary = Summary::parse(&ready["inventory"])?;
        // These other ready-result numbers must also be safe before schema
        // validation, even though this boundary verifies only the inventory.
        if let Some(record) = ready["origin"].get("record") {
            if let Some(length) = record.get("byteLength") {
                count(length, MAX_BYTES)?;
            }
            if let Some(schema) = record.get("schema") {
                count(schema, 1)?;
            }
        }
        if let Some(length) = ready["projection"].get("byteLength") {
            count(length, MAX_BYTES)?;
        }
        validate(Schema::Ready, &ready)?;
        let roots = std::iter::once(&ready["primary"])
            .chain(
                ready["companions"]
                    .as_array()
                    .ok_or(InvalidFrame::Shape)?
                    .iter(),
            )
            .map(|root| {
                Ok(Root {
                    kind: match root["kind"].as_str() {
                        Some("file") => RootKind::File,
                        Some("directory") => RootKind::Directory,
                        _ => return Err(InvalidFrame::Shape),
                    },
                    path: RootPath::parse(&root["path"])?,
                })
            })
            .collect::<Result<Vec<_>, InvalidFrame>>()?;
        if entry_frames.len() > MAX_ENTRIES || entry_frames.len() != summary.entries {
            return Err(InventoryError::Counts);
        }
        // A necessary lower bound only, not the host's complete metadata ledger
        // or allocator overhead. Reject before retaining an impossible set.
        let mut retained_strings = roots
            .iter()
            .map(|root| root.path.as_str().len())
            .sum::<usize>();
        let mut entries = Vec::with_capacity(entry_frames.len());
        for frame in entry_frames {
            let value = parse(frame, MAX_REPLY_BYTES)?;
            let entry = InventoryEntry::parse(&value)?;
            retained_strings = retained_strings
                .checked_add(entry.path().len())
                .and_then(|length| length.checked_add(entry.id.as_str().len()))
                .filter(|length| *length <= MAX_BYTES)
                .ok_or(InventoryError::MetadataBudget)?;
            entries.push(entry);
        }
        check(&roots, &summary, &entries)?;
        Ok(Self { entries, summary })
    }
}

struct NamespacePath<'a> {
    raw: &'a str,
    normalized: String,
    kind: RootKind,
}
struct Prefix<'a> {
    raw: &'a str,
    entry: Option<RootKind>,
}

fn check_namespace(roots: &[Root], entries: &[InventoryEntry]) -> Result<(), InventoryError> {
    let mut paths = roots
        .iter()
        .map(|root| (root.path.as_str(), root.kind))
        .chain(entries.iter().map(|entry| (entry.path(), entry.kind())))
        .map(|(raw, kind)| NamespacePath {
            raw,
            normalized: folded(raw),
            kind,
        })
        .collect::<Vec<_>>();
    paths.sort_by(|a, b| a.normalized.as_bytes().cmp(b.normalized.as_bytes()));
    // Retain only prefixes of the current normalized path. Borrow raw spellings
    // instead of allocating every full prefix or a node for every component.
    // Carry prefixes across a normalization-generated slash with no raw boundary.
    let mut prefixes: BTreeMap<usize, Prefix<'_>> = BTreeMap::new();
    let mut previous = "";
    for path in &paths {
        let shared = previous
            .bytes()
            .zip(path.normalized.bytes())
            .take_while(|(a, b)| a == b)
            .count();
        prefixes.retain(|length, _| {
            *length < shared
                || (*length == shared
                    && (path.normalized.len() == *length
                        || path.normalized.as_bytes()[*length] == b'/'))
        });
        if prefixes.iter().any(|(length, prefix)| {
            prefix.entry == Some(RootKind::File) && *length < path.normalized.len()
        }) {
            return Err(InventoryError::PathSet);
        }
        let mut raw_end = 0;
        let mut normalized_end = 0;
        for part in path.raw.split('/') {
            raw_end += part.len();
            normalized_end += folded(part).len();
            let raw = &path.raw[..raw_end];
            let entry = (raw_end == path.raw.len()).then_some(path.kind);
            if let Some(prefix) = prefixes.get_mut(&normalized_end) {
                if prefix.raw != raw || matches!((prefix.entry,entry),(Some(a),Some(b)) if a!=b) {
                    return Err(InventoryError::PathSet);
                }
                if entry.is_some() {
                    prefix.entry = entry;
                }
            } else {
                prefixes.insert(normalized_end, Prefix { raw, entry });
            }
            raw_end += 1;
            normalized_end += 1;
        }
        previous = &path.normalized;
    }
    Ok(())
}

fn check(
    roots: &[Root],
    summary: &Summary,
    entries: &[InventoryEntry],
) -> Result<(), InventoryError> {
    if entries
        .windows(2)
        .any(|pair| pair[0].path().as_bytes() >= pair[1].path().as_bytes())
    {
        return Err(InventoryError::Ordering);
    }
    let mut identities = BTreeSet::new();
    let mut paths = BTreeMap::new();
    for (index, root) in roots.iter().enumerate() {
        for other in &roots[..index] {
            let a = folded(root.path.as_str());
            let b = folded(other.path.as_str());
            if a == b || beneath(&a, &b).is_some() || beneath(&b, &a).is_some() {
                return Err(InventoryError::PathSet);
            }
        }
    }
    check_namespace(roots, entries)?;
    let mut files = 0;
    let mut source_bytes = 0usize;
    let mut digest = Sha256::new();
    digest.update(DOMAIN);
    digest.update(
        u32::try_from(entries.len())
            .map_err(|_| InventoryError::Counts)?
            .to_be_bytes(),
    );
    for entry in entries {
        if !identities.insert(entry.id.as_str()) {
            return Err(InventoryError::DuplicateIdentity);
        }
        paths.insert(entry.path(), entry.kind());
        let (tag, length_hash) = match entry.content {
            EntryContent::Directory => (0, None),
            EntryContent::File {
                byte_length,
                sha256,
            } => {
                files += 1;
                source_bytes = source_bytes
                    .checked_add(byte_length)
                    .filter(|total| *total <= MAX_BYTES)
                    .ok_or(InventoryError::SourceBudget)?;
                (1, Some((byte_length, sha256)))
            }
        };
        digest.update([tag]);
        digest.update(
            u32::try_from(entry.path().len())
                .map_err(|_| InvalidFrame::Path)?
                .to_be_bytes(),
        );
        digest.update(entry.path().as_bytes());
        if let Some((length, sha256)) = length_hash {
            digest.update(
                u64::try_from(length)
                    .map_err(|_| InvalidFrame::Range)?
                    .to_be_bytes(),
            );
            digest.update(sha256.0);
        }
    }
    if files != summary.files
        || entries.len() - files != summary.directories
        || source_bytes != summary.source_bytes
    {
        return Err(InventoryError::Counts);
    }
    check_coverage(roots, entries, &paths)?;
    if InventorySha256(digest.finalize().into()) != summary.digest {
        return Err(InventoryError::Digest);
    }
    Ok(())
}
fn beneath<'a>(path: &'a str, root: &str) -> Option<&'a str> {
    path.strip_prefix(root)?.strip_prefix('/')
}
fn check_coverage(
    roots: &[Root],
    entries: &[InventoryEntry],
    paths: &BTreeMap<&str, RootKind>,
) -> Result<(), InventoryError> {
    for root in roots {
        if paths.get(root.path.as_str()) != Some(&root.kind) {
            return Err(InventoryError::Coverage);
        }
    }
    let mut descendants = 0;
    for entry in entries {
        if roots.iter().any(|root| root.path.as_str() == entry.path()) {
            continue;
        }
        let (root, relative) = roots
            .iter()
            .filter(|root| root.kind == RootKind::Directory)
            .find_map(|root| {
                beneath(entry.path(), root.path.as_str()).map(|relative| (root, relative))
            })
            .ok_or(InventoryError::Coverage)?;
        if relative.split('/').count() > 128 {
            return Err(InventoryError::DescendantDepth);
        }
        descendants += 1;
        if descendants > MAX_DESCENDANTS {
            return Err(InventoryError::Counts);
        }
        for (offset, _) in relative.match_indices('/') {
            let end = root.path.as_str().len() + 1 + offset;
            if paths.get(&entry.path()[..end]) != Some(&RootKind::Directory) {
                return Err(InventoryError::Coverage);
            }
        }
    }
    Ok(())
}
