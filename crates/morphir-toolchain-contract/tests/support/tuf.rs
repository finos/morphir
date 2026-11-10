//! Serve a fixture metadata set as a filesystem TUF repository.

#![allow(dead_code)]

use super::repository::canonical;
use morphir_distribution::{DistributionError, TrustedToolRepository};
use morphir_toolchain_contract::AuthenticatedTargets;
use serde_json::Value;
use std::path::{Path, PathBuf};

/// Write `set` (timestamp, snapshot and targets) and the fixture's target
/// files as a consistent-snapshot repository under `root`.
pub fn write_set(
    fixture: &Value,
    set: &Value,
    root: &Path,
) -> (Vec<u8>, PathBuf, PathBuf, PathBuf) {
    let metadata = root.join("metadata");
    let targets = root.join("targets");
    std::fs::create_dir_all(&metadata).unwrap();
    std::fs::create_dir_all(&targets).unwrap();
    let trusted_root = canonical(&fixture["trustedRoot"]);
    std::fs::write(metadata.join("1.root.json"), &trusted_root).unwrap();
    std::fs::write(
        metadata.join("timestamp.json"),
        canonical(&set["timestamp"]),
    )
    .unwrap();
    let snapshot_version = set["snapshot"]["signed"]["version"].as_u64().unwrap();
    std::fs::write(
        metadata.join(format!("{snapshot_version}.snapshot.json")),
        canonical(&set["snapshot"]),
    )
    .unwrap();
    let targets_version = set["targets"]["signed"]["version"].as_u64().unwrap();
    std::fs::write(
        metadata.join(format!("{targets_version}.targets.json")),
        canonical(&set["targets"]),
    )
    .unwrap();
    let signed_targets = set["targets"]["signed"]["targets"].as_object().unwrap();
    for (name, content) in fixture["targetFiles"].as_object().unwrap() {
        let Some(digest) = signed_targets
            .get(name)
            .and_then(|entry| entry["hashes"]["sha256"].as_str())
        else {
            continue;
        };
        let destination = targets.join(format!("{digest}.{name}"));
        std::fs::create_dir_all(destination.parent().unwrap()).unwrap();
        std::fs::write(destination, content.as_str().unwrap()).unwrap();
    }
    (trusted_root, metadata, targets, root.join("datastore"))
}

/// Load a set through the existing v1 tool client.
pub async fn load_set(
    fixture: &Value,
    set: &Value,
    root: &Path,
) -> Result<TrustedToolRepository, DistributionError> {
    let (trusted_root, metadata, targets, datastore) = write_set(fixture, set, root);
    TrustedToolRepository::load_filesystem(&trusted_root, &metadata, &targets, &datastore).await
}

/// Load a set as the contract crate's authenticated targets.
pub async fn targets_of(
    fixture: &Value,
    set: &Value,
    root: &Path,
) -> morphir_toolchain_contract::Result<AuthenticatedTargets> {
    let (trusted_root, metadata, targets, datastore) = write_set(fixture, set, root);
    AuthenticatedTargets::load_filesystem(&trusted_root, &metadata, &targets, &datastore).await
}
