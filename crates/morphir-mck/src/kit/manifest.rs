//! `mck-kit.lock.json`: the provenance and integrity manifest at the root of a
//! vendored kit snapshot (`spec/mck/kit-manifest.md`, schema
//! `spec/mck/mck-kit.lock.schema.json`).
//!
//! Parsing validates everything the schema does and a little more: the
//! inventory must be sorted, unique and made of safe paths, and
//! `snapshotDigest` must be the digest of that inventory. Rendering is
//! canonical, so an unchanged snapshot rewrites byte for byte.

use std::fmt;

use serde::Serialize;
use serde_json::Value;

use super::hash::{ALGORITHM, ContentDigest, digest_of_hashes, is_sha256_hex};
use super::syntax::text::utf16_cmp;
use crate::DRIVER_CONTRACT;

/// The manifest's file name at a snapshot's root.
pub const MANIFEST_NAME: &str = "mck-kit.lock.json";

pub const LOCK_VERSION: u64 = 1;
/// The only upstream repository a snapshot may name in this delivery.
pub const UPSTREAM_REPOSITORY: &str = "finos/morphir";
/// The IR protocol and report versions this runner speaks.
pub const PROTOCOL_VERSION: u64 = 1;
pub const REPORT_VERSION: u64 = 1;

/// The longest snapshot path, in bytes.
pub const MAX_PATH_BYTES: usize = 1024;
/// The most files a snapshot may list.
pub const MAX_FILES: usize = 10_000;

/// A full 40-character lowercase hex commit id.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct CommitId(String);

impl CommitId {
    pub fn parse(text: &str) -> Result<Self, String> {
        let hex = text.len() == 40
            && text
                .bytes()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b));
        if hex {
            Ok(Self(text.to_owned()))
        } else {
            Err(format!(
                "\"{text}\" is not a full 40-character lowercase hex commit id"
            ))
        }
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for CommitId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

/// The driver contract versions a snapshot supports: `>=min, <below`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DriverRange {
    min: u32,
    below: u32,
}

impl DriverRange {
    /// The range a snapshot written by this build declares: this contract only.
    pub const CURRENT: Self = Self {
        min: DRIVER_CONTRACT,
        below: DRIVER_CONTRACT + 1,
    };

    pub fn parse(text: &str) -> Result<Self, String> {
        let invalid = || format!("driverContract \"{text}\" is not \">=N, <M\" with 1 <= N < M");
        let (min, below) = text
            .strip_prefix(">=")
            .and_then(|rest| rest.split_once(", <"))
            .ok_or_else(invalid)?;
        let number = |digits: &str| {
            (!digits.is_empty()
                && !digits.starts_with('0')
                && digits.bytes().all(|b| b.is_ascii_digit()))
            .then(|| digits.parse::<u32>().ok())
            .flatten()
        };
        match (number(min), number(below)) {
            (Some(min), Some(below)) if min < below => Ok(Self { min, below }),
            _ => Err(invalid()),
        }
    }

    pub fn contains(self, version: u32) -> bool {
        (self.min..self.below).contains(&version)
    }
}

impl fmt::Display for DriverRange {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, ">={}, <{}", self.min, self.below)
    }
}

/// Where a snapshot's bytes came from.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LockSource {
    /// A pinned commit of the official upstream repository.
    Github { revision: CommitId },
    /// The kit compiled into a CLI release.
    Embedded {
        cli_version: String,
        revision: Option<CommitId>,
    },
    /// A local directory: a snapshot (whose revision is carried over) or a checkout (none).
    Local { revision: Option<CommitId> },
}

impl LockSource {
    pub fn kind(&self) -> &'static str {
        match self {
            Self::Github { .. } => "github",
            Self::Embedded { .. } => "embedded",
            Self::Local { .. } => "local",
        }
    }

    pub fn revision(&self) -> Option<&CommitId> {
        match self {
            Self::Github { revision } => Some(revision),
            Self::Embedded { revision, .. } | Self::Local { revision } => revision.as_ref(),
        }
    }
}

/// One inventory entry.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct LockFile {
    pub path: String,
    pub sha256: String,
    pub size: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Lock {
    pub driver_contract: DriverRange,
    pub source: LockSource,
    pub corpus_hash: ContentDigest,
    pub snapshot_digest: ContentDigest,
    /// Sorted by UTF-16 code unit, unique, never the manifest itself.
    pub files: Vec<LockFile>,
}

/// Checks a snapshot path: repository-relative, `/`-separated, no empty, `.`
/// or `..` segment, no backslash, colon or control character, and no segment
/// Windows cannot create (a reserved device name, or a trailing dot or space).
/// The same rules apply on every platform so a snapshot is portable.
pub fn check_snapshot_path(path: &str) -> Result<(), String> {
    let fail = |why: &str| Err(format!("unsafe path \"{path}\": {why}"));
    if path.is_empty() || path.len() > MAX_PATH_BYTES {
        return fail("empty or longer than 1024 bytes");
    }
    if path.contains(|c: char| c == '\\' || c == ':' || c.is_control()) {
        return fail("contains a backslash, colon or control character");
    }
    for segment in path.split('/') {
        if segment.is_empty() || segment == "." || segment == ".." {
            return fail("has an empty, `.` or `..` segment, or a leading or trailing `/`");
        }
        if segment.ends_with(['.', ' ']) {
            return fail("has a segment ending in a dot or space");
        }
        let stem = segment
            .split('.')
            .next()
            .unwrap_or(segment)
            .to_ascii_uppercase();
        let reserved = matches!(stem.as_str(), "CON" | "PRN" | "AUX" | "NUL")
            || (stem.len() == 4
                && (stem.starts_with("COM") || stem.starts_with("LPT"))
                && stem.as_bytes()[3].is_ascii_digit());
        if reserved {
            return fail("names a reserved Windows device");
        }
    }
    if path == MANIFEST_NAME {
        return fail("is the manifest itself");
    }
    Ok(())
}

/// Why a manifest was refused.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ManifestError(pub String);

impl fmt::Display for ManifestError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{MANIFEST_NAME}: {}", self.0)
    }
}

impl std::error::Error for ManifestError {}

fn field<'a>(
    object: &'a serde_json::Map<String, Value>,
    name: &str,
) -> Result<&'a Value, ManifestError> {
    object
        .get(name)
        .ok_or_else(|| ManifestError(format!("missing \"{name}\"")))
}

fn string<'a>(value: &'a Value, name: &str) -> Result<&'a str, ManifestError> {
    value
        .as_str()
        .ok_or_else(|| ManifestError(format!("\"{name}\" must be a string")))
}

fn object<'a>(
    value: &'a Value,
    name: &str,
    allowed: &[&str],
) -> Result<&'a serde_json::Map<String, Value>, ManifestError> {
    let object = value
        .as_object()
        .ok_or_else(|| ManifestError(format!("\"{name}\" must be an object")))?;
    if let Some(unknown) = object.keys().find(|key| !allowed.contains(&key.as_str())) {
        return Err(ManifestError(format!(
            "unknown member \"{unknown}\" in \"{name}\""
        )));
    }
    Ok(object)
}

fn optional_revision(value: &Value) -> Result<Option<CommitId>, ManifestError> {
    match value {
        Value::Null => Ok(None),
        Value::String(text) => CommitId::parse(text).map(Some).map_err(ManifestError),
        _ => Err(ManifestError(
            "\"source.revision\" must be a commit id or null".to_owned(),
        )),
    }
}

fn parse_source(value: &Value) -> Result<LockSource, ManifestError> {
    let kind = value
        .get("kind")
        .and_then(Value::as_str)
        .unwrap_or_default();
    match kind {
        "github" => {
            let source = object(value, "source", &["kind", "repository", "revision"])?;
            let repository = string(field(source, "repository")?, "source.repository")?;
            if repository != UPSTREAM_REPOSITORY {
                return Err(ManifestError(format!(
                    "\"source.repository\" must be {UPSTREAM_REPOSITORY}, got {repository}"
                )));
            }
            let revision = string(field(source, "revision")?, "source.revision")?;
            Ok(LockSource::Github {
                revision: CommitId::parse(revision).map_err(ManifestError)?,
            })
        }
        "embedded" => {
            let source = object(value, "source", &["kind", "cliVersion", "revision"])?;
            let cli_version = string(field(source, "cliVersion")?, "source.cliVersion")?;
            if cli_version.is_empty() {
                return Err(ManifestError(
                    "\"source.cliVersion\" must not be empty".to_owned(),
                ));
            }
            Ok(LockSource::Embedded {
                cli_version: cli_version.to_owned(),
                revision: optional_revision(field(source, "revision")?)?,
            })
        }
        "local" => {
            let source = object(value, "source", &["kind", "revision"])?;
            Ok(LockSource::Local {
                revision: optional_revision(field(source, "revision")?)?,
            })
        }
        other => Err(ManifestError(format!(
            "unknown \"source.kind\" \"{other}\""
        ))),
    }
}

fn parse_files(value: &Value) -> Result<Vec<LockFile>, ManifestError> {
    let entries = value
        .as_array()
        .ok_or_else(|| ManifestError("\"files\" must be an array".to_owned()))?;
    if entries.is_empty() || entries.len() > MAX_FILES {
        return Err(ManifestError(format!(
            "\"files\" must list 1 to {MAX_FILES} files"
        )));
    }
    let mut files: Vec<LockFile> = Vec::with_capacity(entries.len());
    for entry in entries {
        let entry = object(entry, "files[]", &["path", "sha256", "size"])?;
        let path = string(field(entry, "path")?, "files[].path")?;
        check_snapshot_path(path).map_err(ManifestError)?;
        let sha256 = string(field(entry, "sha256")?, "files[].sha256")?;
        if !is_sha256_hex(sha256) {
            return Err(ManifestError(format!(
                "{path}: \"sha256\" is not 64 lowercase hex digits"
            )));
        }
        let size = field(entry, "size")?.as_u64().ok_or_else(|| {
            ManifestError(format!("{path}: \"size\" must be a non-negative integer"))
        })?;
        if let Some(previous) = files.last()
            && utf16_cmp(&previous.path, path).is_ge()
        {
            return Err(ManifestError(format!(
                "\"files\" is not sorted and unique at {path}"
            )));
        }
        files.push(LockFile {
            path: path.to_owned(),
            sha256: sha256.to_owned(),
            size,
        });
    }
    Ok(files)
}

impl Lock {
    pub fn parse(bytes: &[u8]) -> Result<Self, ManifestError> {
        let text = std::str::from_utf8(bytes)
            .map_err(|_| ManifestError("is not valid UTF-8".to_owned()))?;
        let value: Value = serde_json::from_str(text)
            .map_err(|error| ManifestError(format!("is not JSON: {error}")))?;
        let root = object(
            &value,
            "(root)",
            &[
                "lockVersion",
                "suite",
                "contract",
                "driverContract",
                "source",
                "algorithm",
                "corpusHash",
                "snapshotDigest",
                "files",
            ],
        )?;

        // The version comes first: a newer manifest is refused as newer, not
        // as malformed, and never read as if it were this one.
        match field(root, "lockVersion")?.as_u64() {
            Some(LOCK_VERSION) => {}
            other => {
                return Err(ManifestError(format!(
                    "unsupported lockVersion {}; this CLI reads version {LOCK_VERSION}",
                    other.map_or_else(|| "(not an integer)".to_owned(), |v| v.to_string())
                )));
            }
        }
        let suite = string(field(root, "suite")?, "suite")?;
        if suite != "ir" {
            return Err(ManifestError(format!(
                "unsupported suite \"{suite}\"; this CLI vendors the ir suite"
            )));
        }
        let contract = object(
            field(root, "contract")?,
            "contract",
            &["protocol", "report"],
        )?;
        let protocol = field(contract, "protocol")?.as_u64();
        let report = field(contract, "report")?.as_u64();
        if protocol != Some(PROTOCOL_VERSION) || report != Some(REPORT_VERSION) {
            return Err(ManifestError(format!(
                "unsupported contract; this CLI speaks IR protocol {PROTOCOL_VERSION} and report {REPORT_VERSION}"
            )));
        }
        let algorithm = string(field(root, "algorithm")?, "algorithm")?;
        if algorithm != ALGORITHM {
            return Err(ManifestError(format!(
                "unsupported algorithm \"{algorithm}\"; this CLI computes {ALGORITHM}"
            )));
        }

        let driver_contract =
            DriverRange::parse(string(field(root, "driverContract")?, "driverContract")?)
                .map_err(ManifestError)?;
        let source = parse_source(field(root, "source")?)?;
        let corpus_hash = ContentDigest::parse(string(field(root, "corpusHash")?, "corpusHash")?)
            .map_err(ManifestError)?;
        let snapshot_digest =
            ContentDigest::parse(string(field(root, "snapshotDigest")?, "snapshotDigest")?)
                .map_err(ManifestError)?;
        let files = parse_files(field(root, "files")?)?;

        let lock = Self {
            driver_contract,
            source,
            corpus_hash,
            snapshot_digest,
            files,
        };
        let computed = lock.inventory_digest();
        if computed != lock.snapshot_digest {
            return Err(ManifestError(format!(
                "snapshotDigest {} does not match its inventory ({computed})",
                lock.snapshot_digest
            )));
        }
        Ok(lock)
    }

    /// The digest the inventory's hashes imply.
    pub fn inventory_digest(&self) -> ContentDigest {
        digest_of_hashes(
            self.files
                .iter()
                .map(|f| (f.path.as_str(), f.sha256.as_str())),
        )
    }

    /// Whether this CLI's driver contract is one the snapshot supports.
    pub fn supports_this_driver(&self) -> bool {
        self.driver_contract.contains(DRIVER_CONTRACT)
    }

    /// The canonical text: tab-indented, keys in contract order, trailing newline.
    pub fn render(&self) -> String {
        #[derive(Serialize)]
        #[serde(rename_all = "camelCase")]
        struct Contract {
            protocol: u64,
            report: u64,
        }

        #[derive(Serialize)]
        #[serde(tag = "kind", rename_all = "lowercase")]
        enum Source<'a> {
            Github {
                repository: &'a str,
                revision: &'a str,
            },
            Embedded {
                #[serde(rename = "cliVersion")]
                cli_version: &'a str,
                revision: Option<&'a str>,
            },
            Local {
                revision: Option<&'a str>,
            },
        }

        #[derive(Serialize)]
        #[serde(rename_all = "camelCase")]
        struct Document<'a> {
            lock_version: u64,
            suite: &'a str,
            contract: Contract,
            driver_contract: String,
            source: Source<'a>,
            algorithm: &'a str,
            corpus_hash: &'a str,
            snapshot_digest: &'a str,
            files: &'a [LockFile],
        }

        let source = match &self.source {
            LockSource::Github { revision } => Source::Github {
                repository: UPSTREAM_REPOSITORY,
                revision: revision.as_str(),
            },
            LockSource::Embedded {
                cli_version,
                revision,
            } => Source::Embedded {
                cli_version,
                revision: revision.as_ref().map(CommitId::as_str),
            },
            LockSource::Local { revision } => Source::Local {
                revision: revision.as_ref().map(CommitId::as_str),
            },
        };
        let document = Document {
            lock_version: LOCK_VERSION,
            suite: "ir",
            contract: Contract {
                protocol: PROTOCOL_VERSION,
                report: REPORT_VERSION,
            },
            driver_contract: self.driver_contract.to_string(),
            source,
            algorithm: ALGORITHM,
            corpus_hash: self.corpus_hash.as_str(),
            snapshot_digest: self.snapshot_digest.as_str(),
            files: &self.files,
        };
        format!("{}\n", crate::json::to_tab_json(&document))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::kit::hash::{content_hash, sha256_hex};

    fn lock_of(files: &[(&str, &str)], source: LockSource) -> Lock {
        let mut files: Vec<LockFile> = files
            .iter()
            .map(|(path, text)| LockFile {
                path: (*path).to_owned(),
                sha256: sha256_hex(text.as_bytes()),
                size: text.len() as u64,
            })
            .collect();
        files.sort_by(|a, b| utf16_cmp(&a.path, &b.path));
        let snapshot_digest =
            digest_of_hashes(files.iter().map(|f| (f.path.as_str(), f.sha256.as_str())));
        Lock {
            driver_contract: DriverRange::CURRENT,
            source,
            corpus_hash: content_hash([("spec/ir/mck/types.md", b"x".as_slice())]),
            snapshot_digest,
            files,
        }
    }

    fn revision() -> CommitId {
        CommitId::parse("a2803f2cbfbb9baffe8a939e9462b18fd5bcdda0").unwrap()
    }

    #[test]
    fn render_and_parse_round_trip_for_every_source_kind() {
        let files = [
            ("spec/ir/mck/types.md", "x"),
            ("spec/mck/vocabulary.json", "{}"),
        ];
        for source in [
            LockSource::Github {
                revision: revision(),
            },
            LockSource::Embedded {
                cli_version: "0.4.0-beta.1".into(),
                revision: Some(revision()),
            },
            LockSource::Embedded {
                cli_version: "0.4.0-beta.1".into(),
                revision: None,
            },
            LockSource::Local { revision: None },
        ] {
            let lock = lock_of(&files, source);
            let text = lock.render();
            assert!(
                text.ends_with("}\n") && text.starts_with("{\n\t\"lockVersion\": 1,"),
                "{text}"
            );
            assert_eq!(Lock::parse(text.as_bytes()), Ok(lock.clone()));
            assert_eq!(
                Lock::parse(text.as_bytes()).unwrap().render(),
                text,
                "rendering is canonical"
            );
        }
    }

    #[test]
    fn keys_are_written_in_contract_order() {
        let text = lock_of(&[("a", "1")], LockSource::Local { revision: None }).render();
        let order: Vec<usize> = [
            "lockVersion",
            "suite",
            "contract",
            "driverContract",
            "source",
            "algorithm",
            "corpusHash",
            "snapshotDigest",
            "files",
        ]
        .iter()
        .map(|key| text.find(&format!("\"{key}\"")).unwrap())
        .collect();
        assert!(order.windows(2).all(|pair| pair[0] < pair[1]), "{text}");
    }

    /// The committed example must stay a valid manifest for this parser.
    #[test]
    fn the_committed_example_parses() {
        let raw = include_bytes!("../../../../spec/mck/mck-kit.lock.example.json");
        let lock = Lock::parse(raw).unwrap();
        assert_eq!(lock.source.kind(), "github");
        assert_eq!(lock.files.len(), 15);
    }

    fn edited(edit: impl FnOnce(&mut Value)) -> Result<Lock, ManifestError> {
        let mut value: Value = serde_json::from_str(
            &lock_of(
                &[("a", "1"), ("b", "2")],
                LockSource::Github {
                    revision: revision(),
                },
            )
            .render(),
        )
        .unwrap();
        edit(&mut value);
        Lock::parse(value.to_string().as_bytes())
    }

    fn refused(edit: impl FnOnce(&mut Value), expected: &str) {
        let error = edited(edit).unwrap_err().to_string();
        assert!(error.contains(expected), "{error:?} lacks {expected:?}");
    }

    #[test]
    fn refuses_what_the_schema_refuses() {
        refused(|v| v["lockVersion"] = 2.into(), "unsupported lockVersion 2");
        refused(|v| v["suite"] = "package".into(), "unsupported suite");
        refused(
            |v| v["contract"]["protocol"] = 2.into(),
            "unsupported contract",
        );
        refused(|v| v["algorithm"] = "md5".into(), "unsupported algorithm");
        refused(
            |v| v["extra"] = true.into(),
            "unknown member \"extra\" in \"(root)\"",
        );
        refused(
            |v| v["source"]["mirror"] = "x".into(),
            "unknown member \"mirror\"",
        );
        refused(
            |v| v["source"]["repository"] = "someone/fork".into(),
            "must be finos/morphir",
        );
        refused(
            |v| v["source"]["revision"] = "a2803f2".into(),
            "not a full 40-character",
        );
        refused(
            |v| v["source"]["kind"] = "ftp".into(),
            "unknown \"source.kind\"",
        );
        refused(|v| v["driverContract"] = ">=2, <1".into(), "driverContract");
        refused(
            |v| v["corpusHash"] = "sha256-00".into(),
            "not a sha256-<64 lowercase hex> digest",
        );
        refused(|v| v["files"] = Value::Array(vec![]), "must list 1 to");
        refused(
            |v| v["files"][0]["sha256"] = "00".into(),
            "not 64 lowercase hex",
        );
        refused(
            |v| v["files"][0]["size"] = (-1).into(),
            "non-negative integer",
        );
        refused(
            |v| {
                v.as_object_mut()
                    .unwrap()
                    .remove("source")
                    .map(drop)
                    .unwrap()
            },
            "missing \"source\"",
        );
    }

    #[test]
    fn refuses_an_inventory_that_is_unsorted_duplicated_or_inconsistent() {
        refused(
            |v| v["files"].as_array_mut().unwrap().reverse(),
            "not sorted and unique at a",
        );
        refused(
            |v| {
                let first = v["files"][0].clone();
                v["files"][1] = first;
            },
            "not sorted and unique",
        );
        refused(
            |v| v["files"][0]["sha256"] = sha256_hex(b"other").into(),
            "does not match its inventory",
        );
        refused(
            |v| v["files"][0]["path"] = "../escape".into(),
            "unsafe path",
        );
    }

    #[test]
    fn snapshot_paths_are_portable_and_confined() {
        for good in [
            "spec/ir/mck/types.md",
            "website/static/ir/examples/v4/complete-example.json",
            "a/con-trol.md",
            "a/b.c",
        ] {
            assert_eq!(check_snapshot_path(good), Ok(()), "{good}");
        }
        for bad in [
            "",
            "/abs",
            "a//b",
            "a/./b",
            "a/../b",
            "..",
            "a/",
            "a\\b",
            "C:x",
            "a/b\u{0}",
            "a/NUL",
            "a/con.txt",
            "a/COM1.md",
            "a/lpt9",
            "a/b.",
            "a/b ",
            MANIFEST_NAME,
        ] {
            assert!(check_snapshot_path(bad).is_err(), "{bad:?}");
        }
        assert!(check_snapshot_path(&"a".repeat(MAX_PATH_BYTES + 1)).is_err());
    }

    #[test]
    fn driver_ranges_parse_strictly_and_contain_the_current_contract() {
        assert_eq!(DriverRange::parse(">=1, <2"), Ok(DriverRange::CURRENT));
        assert!(DriverRange::CURRENT.contains(DRIVER_CONTRACT));
        assert!(
            !DriverRange::parse(">=2, <3")
                .unwrap()
                .contains(DRIVER_CONTRACT)
        );
        for bad in [">=1,<2", ">=0, <2", ">=01, <2", "1-2", ">=2, <2", ""] {
            assert!(DriverRange::parse(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn commit_ids_are_full_lowercase_hex() {
        assert!(CommitId::parse("a2803f2cbfbb9baffe8a939e9462b18fd5bcdda0").is_ok());
        for bad in [
            "a2803f2",
            "A2803F2CBFBB9BAFFE8A939E9462B18FD5BCDDA0",
            "main",
            "g2803f2cbfbb9baffe8a939e9462b18fd5bcdda0",
        ] {
            assert!(CommitId::parse(bad).is_err(), "{bad}");
        }
    }
}
