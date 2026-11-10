//! Serve a fixture metadata set to the existing TUF tool client.

#![allow(dead_code)]

use super::repository::canonical;
use morphir_distribution::{DistributionError, TrustedToolRepository};
use serde_json::Value;
use std::path::Path;

/// Write `set` (timestamp, snapshot and targets) and the fixture's target
/// files as a consistent-snapshot filesystem repository under `root`, then
/// load it from the fixture's out-of-band trusted root.
pub async fn load_set(
    fixture: &Value,
    set: &Value,
    root: &Path,
) -> Result<TrustedToolRepository, DistributionError> {
    let metadata = root.join("metadata");
    let targets = root.join("targets");
    std::fs::create_dir_all(&metadata).unwrap();
    std::fs::create_dir_all(&targets).unwrap();
    std::fs::write(
        metadata.join("1.root.json"),
        canonical(&fixture["trustedRoot"]),
    )
    .unwrap();
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
        let Some(entry) = signed_targets.get(name) else {
            continue;
        };
        let digest = entry["hashes"]["sha256"].as_str().unwrap();
        let destination = targets.join(format!("{digest}.{name}"));
        std::fs::create_dir_all(destination.parent().unwrap()).unwrap();
        std::fs::write(destination, content.as_str().unwrap()).unwrap();
    }
    TrustedToolRepository::load_filesystem(
        &canonical(&fixture["trustedRoot"]),
        &metadata,
        &targets,
        &root.join("datastore"),
    )
    .await
}
