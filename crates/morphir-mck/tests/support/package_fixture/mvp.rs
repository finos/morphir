// Copyright 2026 FINOS
// SPDX-License-Identifier: Apache-2.0
//! MVP authoring reuses the independent public-seed signer, never a package client.
use super::{
    Files, Result, generate,
    ordered::{canonical, pretty},
    read_inputs, signing,
};
use serde_json::{Value, json};
use std::path::Path;

pub const PATH: &str = "spec/package/mck/fixtures/mvp-fresh-restore/signed";
pub const PROFILE: &str = "local-library-mvp:0.1.0-draft.1";
const EXPIRES: &str = "2100-01-01T00:00:00Z";

pub fn generate_mvp(source: &Path) -> Result<Files> {
    let mut files = generate(&read_inputs(source)?)?;
    // These draft.3 protocol-tree assets belong to the historical review fixture.
    // The CLI controller uses actual directories, not serialized provider trees.
    for path in [
        "configuration-one.json",
        "view-one.json",
        "empty-cache.json",
    ] {
        files.remove(path);
    }
    // The real CLI uses its wall clock. Re-sign only this public-key test fixture
    // with a fixed long horizon, rebuilding every exact-byte parent link and pin.
    for (role, child) in [
        ("root", None),
        ("targets", None),
        ("snapshot", Some("targets")),
        ("timestamp", Some("snapshot")),
    ] {
        let path = format!("registry/metadata/1.{role}.json");
        let envelope: Value = serde_json::from_slice(&files[&path])?;
        let mut body = envelope["signed"].clone();
        body["expires"] = EXPIRES.into();
        if let Some(child) = child {
            body["meta"][format!("{child}.json")] = serde_json::to_value(signing::metadata_link(
                &files[&format!("registry/metadata/1.{child}.json")],
            ))?;
        }
        files.insert(path, pretty(&signing::tuf(body.into(), role)));
    }
    files.insert(
        "registry/metadata/timestamp.json".into(),
        files["registry/metadata/1.timestamp.json"].clone(),
    );
    let root: Value = serde_json::from_slice(&files["registry/metadata/1.root.json"])?;
    let mut policy: Value = serde_json::from_slice(&files["trust-policy.json"])?;
    policy["continuedUse"] = "fresh-metadata".into();
    policy["repositories"][0]["identity"] = signing::digest(&canonical(&root["signed"])).into();
    policy["repositories"][0]["bootstrapRoot"]["digest"] =
        signing::digest(&files["registry/metadata/1.root.json"]).into();
    files.insert("trust-policy.json".into(), pretty(&policy.into()));

    let mut lock: Value = serde_json::from_slice(&files["morphir.lock"])?;
    for evidence in lock["evidence"].as_array_mut().ok_or("lock evidence")? {
        if evidence["kind"] != "release-statement" {
            let path = evidence["path"].as_str().ok_or("metadata evidence path")?;
            evidence["digest"] = signing::digest(&files[&format!("registry/{path}")]).into();
        }
    }
    files.insert("morphir.lock".into(), pretty(&lock.into()));

    let mut description: Value = serde_json::from_slice(&files["fixture-description.json"])?;
    description["profile"] = PROFILE.into();
    description["sourceFixture"] = super::SIGNED_PATH.into();
    description["positiveMetadataExpires"] = EXPIRES.into();
    description["authoring"] = json!({
        "signer": "ed25519-dalek",
        "tufVerifier": "rust-tuf 0.3.0-beta14 with reviewed literal 1.0.36 patch",
        "publisherVerifier": "ring",
        "expectedResultsGenerated": false
    });
    description.as_object_mut().unwrap().remove("tools");
    files.insert(
        "fixture-description.json".into(),
        pretty(&description.into()),
    );

    // An independently signed expired timestamp isolates expiry from bad signatures.
    let timestamp: Value = serde_json::from_slice(&files["registry/metadata/timestamp.json"])?;
    let mut expired = timestamp["signed"].clone();
    expired["expires"] = "2020-01-01T00:00:00Z".into();
    files.insert(
        "variants/expired-timestamp.json".into(),
        pretty(&signing::tuf(expired.into(), "timestamp")),
    );
    Ok(files)
}
