// Copyright 2026 FINOS
// SPDX-License-Identifier: Apache-2.0
//! Independent offline verification. No authoring/signing module is imported.
//! Upstream rust-tuf owns signatures, expiry, role versions and download hashes/limits.
//! Authenticated descriptions also enforce the original fixture gate's exact lengths;
//! upstream download readers treat their length argument as an upper bound.
//! EphemeralRepository cannot perform network I/O. The fixed time is passed to both
//! update and target fetch; Database-only validation would omit download hashes.
use super::{Files, Result};
use chrono::{DateTime, Utc};
use futures_util::io::{AsyncReadExt, Cursor};
use serde_json::Value;
use std::collections::BTreeSet;
use tuf::{
    Database,
    client::{Client, Config},
    crypto::HashAlgorithm,
    metadata::{MetadataPath, MetadataVersion, RawSignedMetadata, TargetPath},
    pouf::Pouf1,
    repository::{EphemeralRepository, RepositoryStorage},
};
const ROLES: [&str; 4] = ["root", "timestamp", "snapshot", "targets"];
fn profile(condition: bool, detail: &str) -> Result<()> {
    if condition {
        Ok(())
    } else {
        Err(format!("Unsupported Morphir TUF profile: {detail}").into())
    }
}
fn object(value: &Value) -> Result<&serde_json::Map<String, Value>> {
    value
        .as_object()
        .ok_or_else(|| "Unsupported Morphir TUF profile: expected object".into())
}
fn positive(value: &Value) -> bool {
    value
        .as_u64()
        .is_some_and(|n| n > 0 && n <= 9_007_199_254_740_991)
}
fn hex32(value: &Value) -> bool {
    value.as_str().is_some_and(|s| {
        s.len() == 64
            && s.bytes()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    })
}
fn info(value: &Value, metadata: bool) -> Result<()> {
    object(value)?;
    profile(
        value["length"]
            .as_u64()
            .is_some_and(|n| n <= 9_007_199_254_740_991),
        "file length is required",
    )?;
    profile(hex32(&value["hashes"]["sha256"]), "SHA-256 is required")?;
    profile(
        !metadata || positive(&value["version"]),
        "metadata link version must be positive",
    )
}
fn check_profile(metadata: &[Value]) -> Result<()> {
    for (role, envelope) in ROLES.iter().zip(metadata) {
        let signed = &envelope["signed"];
        object(signed)?;
        profile(signed["_type"] == *role, "incorrect role")?;
        profile(
            signed["spec_version"] == "1.0.36",
            "spec_version must be 1.0.36",
        )?;
        profile(
            positive(&signed["version"]),
            "metadata version must be positive",
        )?;
    }
    let root = &metadata[0]["signed"];
    profile(
        root["consistent_snapshot"] == true,
        "consistent_snapshot must be true",
    )?;
    let keys = object(&root["keys"])?;
    let roles = object(&root["roles"])?;
    let mut assigned = BTreeSet::new();
    for role in ROLES {
        let definition = roles
            .get(role)
            .ok_or("Unsupported Morphir TUF profile: missing role")?;
        profile(
            positive(&definition["threshold"]),
            "role threshold must be positive",
        )?;
        let ids = definition["keyids"]
            .as_array()
            .ok_or("Unsupported Morphir TUF profile: role keyids")?;
        profile(
            ids.len() as u64 >= definition["threshold"].as_u64().unwrap(),
            "insufficient role keys",
        )?;
        for id in ids {
            let key = id
                .as_str()
                .and_then(|id| keys.get(id))
                .ok_or("Unsupported Morphir TUF profile: key ID")?;
            profile(
                key["keytype"] == "ed25519" && key["scheme"] == "ed25519",
                "role keys must be Ed25519",
            )?;
            let public = &key["keyval"]["public"];
            profile(hex32(public), "invalid Ed25519 public key")?;
            profile(
                assigned.insert(public.as_str().unwrap()),
                "role keys must be distinct",
            )?;
        }
    }
    for (index, child) in [(1, "snapshot.json"), (2, "targets.json")] {
        let meta = object(&metadata[index]["signed"]["meta"])?;
        profile(
            meta.len() == 1 && meta.contains_key(child),
            "metadata must link exactly its child",
        )?;
        info(&meta[child], true)?;
    }
    for (path, value) in object(&metadata[3]["signed"]["targets"])? {
        profile(
            !path.is_empty()
                && !path.contains('\\')
                && path.split('/').all(|p| !matches!(p, "" | "." | "..")),
            "invalid logical target path",
        )?;
        info(value, false)?;
    }
    Ok(())
}
pub fn verify_tuf(files: &Files, at: &str) -> Result<usize> {
    let at = DateTime::parse_from_rfc3339(at)?.with_timezone(&Utc);
    let raw: Vec<_> = ROLES
        .iter()
        .map(|role| {
            files
                .get(&format!("registry/metadata/1.{role}.json"))
                .ok_or_else(|| format!("Missing fixture metadata: {role}"))
        })
        .collect::<std::result::Result<_, _>>()?;
    let parsed: Vec<Value> = raw
        .iter()
        .map(|bytes| serde_json::from_slice(bytes))
        .collect::<std::result::Result<_, _>>()?;
    check_profile(&parsed)?;
    futures_executor::block_on(async {
        let remote = EphemeralRepository::<Pouf1>::new();
        for (role, bytes) in ROLES.iter().zip(&raw) {
            let version = if *role == "timestamp" {
                MetadataVersion::None
            } else {
                MetadataVersion::Number(1)
            };
            remote
                .store_metadata(
                    &MetadataPath::new(*role)?,
                    version,
                    &mut Cursor::new(bytes.as_slice()),
                )
                .await?;
        }
        for (path, bytes) in files {
            if let Some(path) = path.strip_prefix("registry/targets/") {
                remote
                    .store_target(&TargetPath::new(path)?, &mut Cursor::new(bytes.as_slice()))
                    .await?;
            }
        }
        let database =
            Database::<Pouf1>::from_trusted_root(&RawSignedMetadata::new(raw[0].clone()))?;
        let mut client = Client::from_database(
            Config::default(),
            database,
            EphemeralRepository::new(),
            remote,
        );
        client.update_with_start_time(&at).await?;
        let timestamp = client
            .database()
            .trusted_timestamp()
            .ok_or("TUF timestamp")?;
        let snapshot = client.database().trusted_snapshot().ok_or("TUF snapshot")?;
        // Compare the complete supplied files, never a possibly truncated stream.
        for (actual, expected) in [
            (raw[2].len(), timestamp.snapshot().length()),
            (
                raw[3].len(),
                snapshot
                    .meta()
                    .get(&MetadataPath::targets())
                    .ok_or("TUF targets link")?
                    .length(),
            ),
        ] {
            if Some(actual) != expected {
                return Err("TUF metadata length mismatch".into());
            }
        }
        let targets: Vec<_> = client
            .database()
            .trusted_targets()
            .ok_or("TUF targets were not loaded")?
            .targets()
            .iter()
            .map(|(path, description)| (path.clone(), description.clone()))
            .collect();
        for (target, description) in &targets {
            let hash = description
                .hashes()
                .get(&HashAlgorithm::Sha256)
                .ok_or("TUF target SHA-256")?;
            let physical = format!("registry/targets/{}", target.with_hash_prefix(hash)?);
            let complete = files.get(&physical).ok_or("Missing fixture target file")?;
            if complete.len() as u64 != description.length() {
                return Err("TUF target length mismatch".into());
            }
            let mut verified = client.fetch_target_with_start_time(target, &at).await?;
            let mut bytes = Vec::new();
            verified.read_to_end(&mut bytes).await?;
        }
        Ok(targets.len())
    })
}
