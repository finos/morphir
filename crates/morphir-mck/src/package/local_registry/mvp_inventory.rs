//! A separately versioned, closed inventory for the first executable package
//! profile. The incomplete draft.3 definition corpus remains inspection-only.

use super::CorpusSource;
use super::corpus::logical_path;
use crate::kit::hash::{ContentDigest, content_hash, is_sha256_hex, sha256_hex};
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, BTreeSet},
    io::Read,
    path::{Path, PathBuf},
};

pub const INDEX: &str = "spec/package/mck/mvp-cases.json";
const MAX_FILE_BYTES: u64 = 1_048_576;
const MAX_TOTAL_BYTES: usize = 4_194_304;
const PROFILE: &str = "local-library-mvp";
const VERSION: &str = "0.1.0-draft.1";
const RESTORE_CASES: [&str; 16] = [
    "mvp.restore.fresh-two-libraries",
    "mvp.restore.bad-timestamp-signature",
    "mvp.restore.bad-library-content",
    "mvp.restore.unauthorized-publisher",
    "mvp.restore.unsafe-acquisition-path",
    "mvp.restore.uninitialized-state",
    "mvp.restore.occupied-output",
    "mvp.restore.historical-policy-unsupported",
    "mvp.restore.expired-timestamp",
    "mvp.restore.missing-established-state",
    "mvp.restore.corrupt-state",
    "mvp.restore.uncertain-state",
    "mvp.restore.evidence-digest-mismatch",
    "mvp.restore.evidence-path-mismatch",
    "mvp.restore.undeclared-bundle-entry",
    "mvp.restore.generated-lock-replay",
];
const RESOLVE_CASES: [&str; 13] = [
    "mvp.resolve.fresh-two-libraries",
    "mvp.resolve.absent-published-root",
    "mvp.resolve.bad-timestamp-signature",
    "mvp.resolve.bad-library-content",
    "mvp.resolve.unauthorized-publisher",
    "mvp.resolve.uninitialized-state",
    "mvp.resolve.occupied-output",
    "mvp.resolve.historical-policy-unsupported",
    "mvp.resolve.expired-timestamp",
    "mvp.resolve.missing-established-state",
    "mvp.resolve.corrupt-state",
    "mvp.resolve.uncertain-state",
    "mvp.resolve.undeclared-bundle-entry",
];
const RESTORE_INPUTS: [&str; 15] = [
    "morphir.lock",
    "registry/bundles/345706de972523b65c8711a4367d61f143035770145519576aeaaf18733d874e/ir.json",
    "registry/bundles/345706de972523b65c8711a4367d61f143035770145519576aeaaf18733d874e/manifest.json",
    "registry/bundles/5922bc8860f6cd008b9cda341be7f3a776ea332e63261392e94c17e19a647886/ir.json",
    "registry/bundles/5922bc8860f6cd008b9cda341be7f3a776ea332e63261392e94c17e19a647886/manifest.json",
    "registry/metadata/1.root.json",
    "registry/metadata/1.snapshot.json",
    "registry/metadata/1.targets.json",
    "registry/metadata/1.timestamp.json",
    "registry/metadata/timestamp.json",
    "registry/targets/records/35657eeeb56fe90fcd8caf026695fe510c7bdad2118590109403c27b8fd6eaf0.loan-rules-1.0.0.json",
    "registry/targets/records/3b8065de6416cd51ac9a3ce684110e523bce2efb700276bbda8b0fb633ced251.eligibility-1.2.0.json",
    "registry/targets/statements/4a269a16e2565353d152d233333b80add72b29651e6b13308c922628eb9efcb1.eligibility-1.2.0.json",
    "registry/targets/statements/abef7639162c3cb96cf6df5aa87aa46ef63d3c0d171719b3445d4d0f8d05494a.loan-rules-1.0.0.json",
    "trust-policy.json",
];
const EXTRA_BUNDLE_INPUT: &str = "registry/bundles/5922bc8860f6cd008b9cda341be7f3a776ea332e63261392e94c17e19a647886/undeclared.txt";

/// Reads only the MVP inventory and its fixture subtree from a repository.
/// Canonicalization rejects symlinks that leave the admitted fixture root.
pub struct MvpRepositorySource {
    root: PathBuf,
}

impl MvpRepositorySource {
    pub fn new(root: impl AsRef<Path>) -> Result<Self, String> {
        Ok(Self {
            root: root.as_ref().canonicalize().map_err(|e| e.to_string())?,
        })
    }
}

impl CorpusSource for MvpRepositorySource {
    fn read(&self, path: &str) -> Result<Vec<u8>, String> {
        logical_path(path)?;
        let scope = if path == INDEX {
            "spec/package/mck"
        } else if path.starts_with("spec/package/mck/fixtures/mvp-") {
            "spec/package/mck/fixtures"
        } else {
            return Err(format!("path is outside MVP inventory scope: {path}"));
        };
        let target = self
            .root
            .join(path)
            .canonicalize()
            .map_err(|e| format!("{path}: {e}"))?;
        let scope = self.root.join(scope);
        if !target.starts_with(scope) || !target.is_file() {
            return Err(format!("path is outside MVP inventory scope: {path}"));
        }
        let mut bounded = std::fs::File::open(target)
            .map_err(|e| format!("{path}: {e}"))?
            .take(MAX_FILE_BYTES + 1);
        let mut bytes = Vec::new();
        bounded
            .read_to_end(&mut bytes)
            .map_err(|e| format!("{path}: {e}"))?;
        if bytes.len() as u64 > MAX_FILE_BYTES {
            return Err(format!("MVP file size limit exceeded: {path}"));
        }
        Ok(bytes)
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Manifest {
    format_version: String,
    profile: String,
    scope: String,
    required_cases: Vec<String>,
    assets: Vec<Asset>,
    cases: Vec<Case>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Asset {
    id: String,
    kind: AssetKind,
    path: String,
    sha256: String,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
enum AssetKind {
    Input,
    Expected,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Case {
    id: String,
    operation: String,
    #[serde(default)]
    root: Option<String>,
    environment: MvpEnvironment,
    inputs: BTreeMap<String, String>,
    expected: String,
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct MvpEnvironment {
    trust_state: TrustState,
    output: OutputSetup,
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize)]
#[serde(rename_all = "kebab-case")]
enum TrustState {
    Initialized,
    Uninitialized,
    MissingDatabase,
    CorruptDatabase,
    UnresolvedOperation,
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize)]
#[serde(rename_all = "kebab-case")]
enum OutputSetup {
    Absent,
    Sentinel,
}

/// Owns exactly the bytes authenticated during admission. A later adapter
/// request can be built from inputs without exposing expected bytes to it.
#[derive(Debug)]
pub struct AdmittedMvpInventory {
    content_hash: ContentDigest,
    cases: Vec<AdmittedMvpCase>,
}

#[derive(Debug)]
pub struct AdmittedMvpCase {
    id: String,
    operation: String,
    root: Option<String>,
    environment: MvpEnvironment,
    inputs: BTreeMap<String, Vec<u8>>,
    expected: Vec<u8>,
}

/// The only view of an admitted case sent to an adapter. Expected bytes stay
/// owned by the runner and cannot enter this serialization path.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MvpRequest {
    op: &'static str,
    profile: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    exact_root: Option<String>,
    environment: MvpEnvironment,
    files: Vec<MvpInputFile>,
}

#[derive(Debug, Serialize)]
struct MvpInputFile {
    path: String,
    hex: String,
}

impl AdmittedMvpInventory {
    pub fn content_hash(&self) -> &ContentDigest {
        &self.content_hash
    }

    pub fn cases(&self) -> &[AdmittedMvpCase] {
        &self.cases
    }
}

impl AdmittedMvpCase {
    pub fn id(&self) -> &str {
        &self.id
    }

    pub fn operation(&self) -> &str {
        &self.operation
    }

    pub fn inputs(&self) -> &BTreeMap<String, Vec<u8>> {
        &self.inputs
    }

    pub fn expected(&self) -> &[u8] {
        &self.expected
    }

    pub fn request(&self) -> MvpRequest {
        MvpRequest {
            op: if self.operation == "resolve" {
                "resolve-local-library"
            } else {
                "restore-local-library"
            },
            profile: "local-library-mvp:0.1.0-draft.1",
            exact_root: self.root.clone(),
            environment: self.environment,
            files: self
                .inputs
                .iter()
                .map(|(path, bytes)| MvpInputFile {
                    path: path.clone(),
                    hex: bytes.iter().map(|byte| format!("{byte:02x}")).collect(),
                })
                .collect(),
        }
    }
}

pub fn admit_mvp_inventory(source: &dyn CorpusSource) -> Result<AdmittedMvpInventory, String> {
    let index_bytes = source.read(INDEX)?;
    if index_bytes.len() as u64 > MAX_FILE_BYTES {
        return Err("MVP index size limit exceeded".into());
    }
    let manifest: Manifest = serde_json::from_slice(&index_bytes).map_err(|e| e.to_string())?;
    if manifest.assets.len() > 64 {
        return Err("MVP asset count limit exceeded".into());
    }
    if manifest.format_version != VERSION
        || manifest.profile != PROFILE
        || manifest.scope != "fresh-local-library-workflow"
    {
        return Err("unsupported MVP inventory profile, version, or scope".into());
    }
    let required: BTreeSet<_> = manifest.required_cases.iter().map(String::as_str).collect();
    if manifest.required_cases.len() != RESTORE_CASES.len() + RESOLVE_CASES.len()
        || required != RESTORE_CASES.into_iter().chain(RESOLVE_CASES).collect()
    {
        return Err("MVP required-case inventory differs from the profile".into());
    }

    let mut total_bytes = index_bytes.len();
    let mut consumed = BTreeMap::from([(INDEX.to_owned(), index_bytes)]);
    let mut assets = BTreeMap::new();
    let mut paths = BTreeSet::new();
    for asset in manifest.assets {
        logical_path(&asset.path)?;
        if !asset.path.starts_with("spec/package/mck/fixtures/mvp-") {
            return Err(format!(
                "MVP asset path is outside fixture scope: {}",
                asset.path
            ));
        }
        if !paths.insert(asset.path.clone()) || assets.contains_key(&asset.id) {
            return Err(format!("duplicate MVP asset {}", asset.id));
        }
        let hash = asset
            .sha256
            .strip_prefix("sha256:")
            .ok_or("invalid MVP asset digest")?;
        if !is_sha256_hex(hash) {
            return Err(format!("invalid MVP asset digest for {}", asset.id));
        }
        let bytes = source.read(&asset.path)?;
        if bytes.len() as u64 > MAX_FILE_BYTES {
            return Err(format!("MVP file size limit exceeded: {}", asset.path));
        }
        total_bytes = total_bytes
            .checked_add(bytes.len())
            .ok_or("MVP total size limit exceeded")?;
        if total_bytes > MAX_TOTAL_BYTES {
            return Err("MVP total size limit exceeded".into());
        }
        if sha256_hex(&bytes) != hash {
            return Err(format!("MVP asset digest mismatch for {}", asset.id));
        }
        consumed.insert(asset.path, bytes.clone());
        assets.insert(asset.id, (asset.kind, bytes));
    }

    let mut case_ids = BTreeSet::new();
    let mut used_assets = BTreeSet::new();
    let mut cases = Vec::new();
    for case in manifest.cases {
        if !required.contains(case.id.as_str()) || !case_ids.insert(case.id.clone()) {
            return Err(format!("unexpected or duplicate MVP case {}", case.id));
        }
        let operation_matches_id = (case.operation == "restore"
            && RESTORE_CASES.contains(&case.id.as_str())
            && case.root.is_none())
            || (case.operation == "resolve"
                && RESOLVE_CASES.contains(&case.id.as_str())
                && case.root.as_deref()
                    == Some(if case.id == "mvp.resolve.absent-published-root" {
                        "example.com/finance/loan-rules@9.9.9"
                    } else {
                        "example.com/finance/loan-rules@1.0.0"
                    }));
        if !operation_matches_id || case.inputs.is_empty() {
            return Err(format!(
                "unsupported MVP bootstrap operation in {}",
                case.id
            ));
        }
        let mounted: BTreeSet<_> = case.inputs.keys().map(String::as_str).collect();
        let required_mounts: BTreeSet<_> = RESTORE_INPUTS.into_iter().collect();
        if !required_mounts.is_subset(&mounted)
            || mounted.len() > required_mounts.len() + 1
            || mounted.iter().any(|mount| {
                !required_mounts.contains(mount)
                    && *mount != "initialization-policy.json"
                    && *mount != EXTRA_BUNDLE_INPUT
            })
        {
            return Err(format!("incomplete MVP restore inputs in {}", case.id));
        }
        let mut inputs = BTreeMap::new();
        for (mount, id) in case.inputs {
            logical_path(&mount)?;
            if !mount.starts_with("registry/")
                && mount != "trust-policy.json"
                && mount != "morphir.lock"
                && mount != "initialization-policy.json"
            {
                return Err(format!("invalid MVP input mount {mount}"));
            }
            let (kind, bytes) = assets
                .get(&id)
                .ok_or_else(|| format!("unknown MVP input {id}"))?;
            if *kind != AssetKind::Input || inputs.insert(mount, bytes.clone()).is_some() {
                return Err(format!("invalid or duplicate MVP input {id}"));
            }
            used_assets.insert(id);
        }
        let (kind, expected) = assets
            .get(&case.expected)
            .ok_or_else(|| format!("unknown MVP expected asset {}", case.expected))?;
        if *kind != AssetKind::Expected {
            return Err(format!("MVP expected asset is an input: {}", case.expected));
        }
        used_assets.insert(case.expected);
        cases.push(AdmittedMvpCase {
            id: case.id,
            operation: case.operation,
            root: case.root,
            environment: case.environment,
            inputs,
            expected: expected.clone(),
        });
    }
    if case_ids.len() != required.len() || used_assets.len() != assets.len() {
        return Err("MVP case or asset inventory is incomplete".into());
    }
    Ok(AdmittedMvpInventory {
        content_hash: content_hash(
            consumed
                .iter()
                .map(|(path, bytes)| (path.as_str(), bytes.as_slice())),
        ),
        cases,
    })
}
