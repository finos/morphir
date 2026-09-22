// Copyright 2026 FINOS
// SPDX-License-Identifier: Apache-2.0
//! Deterministic authoring from seven hash-pinned inputs. Expected observations
//! and signed outputs are never read here. Historical tool provenance is frozen.
use super::{
    CLOCK, Files, Result,
    ordered::{Json, canonical, object, pretty},
    signing::*,
};
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet};
pub const VERSION: &str = "0.1.0-draft.3";
const BASE: &str = "spec/package/mck/fixtures/";
pub const INPUT_DIGESTS: [(&str, &str); 7] = [
    (
        "spec/package/mck/fixtures/two-libraries/eligibility/manifest.json",
        "0a91b5e3a5e377fa4557212fc5b561a66067d67292123136575e46ce5a3fd0b7",
    ),
    (
        "spec/package/mck/fixtures/two-libraries/eligibility/ir.json",
        "243e640848e5ee728224c0bc9090c67cf434d9814cec77745daad918119ceb43",
    ),
    (
        "spec/package/mck/fixtures/two-libraries/loan-rules/manifest.json",
        "e98ea924e66b96a5050e2c3a690f9534db32f5971401d2965791546872ecb7a3",
    ),
    (
        "spec/package/mck/fixtures/two-libraries/loan-rules/ir.json",
        "b1884eeb8364f96c6405cc45f2fe07a006c22f066a4136656ad05dda9c9a94cc",
    ),
    (
        "spec/package/mck/fixtures/two-libraries/lock-core.json",
        "6470c10d02092c9bf6c2ba9d945c88d2d0310cad2fffc25226acd87f85e3129b",
    ),
    (
        "spec/package/mck/fixtures/local-registry/unsigned/eligibility-statement-payload.json",
        "98b42b54516d679247a649a95c554dd310f71be357046ad3ecd81f4e3b0d7d31",
    ),
    (
        "spec/package/mck/fixtures/local-registry/unsigned/loan-rules-statement-payload.json",
        "b6c9301e78a523f8037dd6bf1fbd2b7ca89aa836b293e13d72f776db26a6d683",
    ),
];
fn release(value: &Value) -> Json {
    object!("packagePath" => &value["packagePath"], "version" => &value["version"])
}
fn bytes_value(bytes: &[u8]) -> Json {
    object!("kind" => "hex", "value" => hex(bytes))
}
fn body(role: &str, expires: &str, field: &str, value: Json) -> Json {
    object!("_type" => role, "spec_version" => "1.0.36", "version" => 1usize, "expires" => expires, field => value)
}
fn evidence(id: &str, kind: &str, path: &str, bytes: &[u8]) -> Json {
    object!("id" => id, "registry" => "finance", "kind" => kind, "path" => path, "digest" => digest(bytes))
}
pub fn generate(inputs: &Files) -> Result<Files> {
    for (path, expected) in INPUT_DIGESTS {
        let bytes = inputs
            .get(path)
            .ok_or_else(|| format!("missing input: {path}"))?;
        if hash(bytes) != expected {
            return Err(format!("input digest: {path}").into());
        }
    }
    if inputs.len() != INPUT_DIGESTS.len() {
        return Err("unexpected fixture input".into());
    }
    let input = |path: &str| -> Result<&Vec<u8>> {
        inputs
            .get(&format!("{BASE}{path}"))
            .ok_or_else(|| format!("missing input: {path}").into())
    };
    let parse = |path: &str| -> Result<Value> { Ok(serde_json::from_slice(input(path)?)?) };
    let mut files = Files::new();
    let mut targets = BTreeMap::new();
    let mut acquisitions = Vec::new();
    let mut evidences = BTreeMap::new();
    for name in ["eligibility", "loan-rules"] {
        let manifest_bytes = input(&format!("two-libraries/{name}/manifest.json"))?;
        let manifest = parse(&format!("two-libraries/{name}/manifest.json"))?;
        let payload = parse(&format!(
            "local-registry/unsigned/{name}-statement-payload.json"
        ))?;
        let normalized = canonical(&manifest);
        let mut content_prefix = b"morphir-package-content:0.1.0-draft.1\n".to_vec();
        content_prefix.extend_from_slice(&normalized);
        let dependencies: Vec<_> = manifest["dependencies"]
            .as_object()
            .ok_or("manifest dependencies")?
            .iter()
            .map(|(name, requirement)| {
                let mut value = requirement.clone();
                value
                    .as_object_mut()
                    .unwrap()
                    .insert("irPackageName".into(), name.clone().into());
                value
            })
            .collect();
        if payload
            != json!({"formatVersion":VERSION,"kind":"LibraryReleaseStatement","release":{"packagePath":manifest["packagePath"],"version":manifest["version"]},"irPackageName":manifest["ir"]["packageName"],"dependencies":dependencies,"manifestDigest":digest(&normalized),"contentDigest":digest(&content_prefix)})
        {
            return Err(format!("statement inputs disagree: {name}").into());
        }
        let bundle = format!("bundles/{}", hash(&content_prefix));
        let source = object!("kind" => "registry-directory", "path" => bundle.clone());
        files.insert(
            format!("registry/{bundle}/manifest.json"),
            manifest_bytes.clone(),
        );
        for (path, expected) in manifest["content"].as_object().ok_or("manifest content")? {
            let bytes = input(&format!("two-libraries/{name}/{path}"))?;
            if expected != &digest(bytes) {
                return Err(format!("declared content: {name}/{path}").into());
            }
            files.insert(format!("registry/{bundle}/{path}"), bytes.clone());
        }
        let version = manifest["version"].as_str().ok_or("manifest version")?;
        let statement_path = format!("statements/{name}-{version}.json");
        let record_path = format!("records/{name}-{version}.json");
        let envelope = pretty(&dsse(&canonical(&payload), &["publisher-a", "publisher-b"]));
        let statement = object!("path" => statement_path.clone(), "digest" => digest(&envelope));
        let mut record = payload.clone();
        record["kind"] = "LibraryRegistryRecord".into();
        record["source"] = serde_json::to_value(&source)?;
        record["statement"] = serde_json::to_value(&statement)?;
        let mut record_bytes = canonical(&record);
        record_bytes.push(b'\n');
        for (path, bytes, kind, active) in [
            (&statement_path, &envelope, "LibraryReleaseStatement", false),
            (&record_path, &record_bytes, "LibraryRelease", true),
        ] {
            let (directory, leaf) = path.rsplit_once('/').ok_or("logical target")?;
            files.insert(
                format!("registry/targets/{directory}/{}.{leaf}", hash(bytes)),
                bytes.clone(),
            );
            let mut morphir = vec![
                ("formatVersion".into(), VERSION.into()),
                ("kind".into(), kind.into()),
                ("release".into(), release(&payload["release"])),
            ];
            if active {
                morphir.push(("status".into(), "active".into()));
            }
            targets.insert(path.clone(), object!("length" => bytes.len(), "hashes" => object!("sha256" => hash(bytes)), "custom" => object!("morphir" => Json::Object(morphir))));
        }
        acquisitions.push(object!("release" => release(&payload["release"]), "registry" => "finance", "record" => object!("path" => record_path, "digest" => digest(&record_bytes)), "source" => source, "statement" => format!("{name}-statement")));
        let id = format!("{name}-statement");
        evidences.insert(
            id.clone(),
            evidence(&id, "release-statement", &statement_path, &envelope),
        );
    }
    let roles = ["root", "timestamp", "snapshot", "targets"];
    let keys: BTreeMap<_, _> = roles
        .iter()
        .map(|role| (key_id(role), public_tuf(role)))
        .collect();
    let root_body = object!("_type" => "root", "spec_version" => "1.0.36", "version" => 1usize, "expires" => "2030-01-01T00:00:00Z", "consistent_snapshot" => true,
        "keys" => Json::Object(keys.into_iter().collect()),
        "roles" => Json::Object(roles.iter().map(|role| (role.to_string(), object!("keyids" => vec![key_id(role).into()], "threshold" => 1usize))).collect()));
    let root_bytes = pretty(&tuf(root_body.clone(), "root"));
    let targets_bytes = pretty(&tuf(
        body(
            "targets",
            "2028-01-01T00:00:00Z",
            "targets",
            Json::Object(targets.into_iter().collect()),
        ),
        "targets",
    ));
    let snapshot_bytes = pretty(&tuf(
        body(
            "snapshot",
            "2028-01-01T00:00:00Z",
            "meta",
            object!("targets.json" => metadata_link(&targets_bytes)),
        ),
        "snapshot",
    ));
    let timestamp_bytes = pretty(&tuf(
        body(
            "timestamp",
            "2027-02-01T00:00:00Z",
            "meta",
            object!("snapshot.json" => metadata_link(&snapshot_bytes)),
        ),
        "timestamp",
    ));
    for (role, bytes) in [
        ("root", &root_bytes),
        ("targets", &targets_bytes),
        ("snapshot", &snapshot_bytes),
        ("timestamp", &timestamp_bytes),
    ] {
        let path = format!("metadata/1.{role}.json");
        files.insert(format!("registry/{path}"), bytes.clone());
        let id = format!("finance-{role}");
        evidences.insert(
            id.clone(),
            evidence(&id, &format!("tuf-{role}"), &path, bytes),
        );
    }
    files.insert("registry/metadata/timestamp.json".into(), timestamp_bytes);
    let old = parse("two-libraries/lock-core.json")?;
    let old_nodes = old["nodes"].as_object().ok_or("old nodes")?;
    let root_id = old["root"].as_str().ok_or("old root")?;
    let mut ids: Vec<_> = old_nodes.keys().filter(|id| *id != root_id).collect();
    ids.sort_by_key(|id| old_nodes[*id]["release"]["packagePath"].as_str());
    ids.insert(
        0,
        old_nodes.get_key_value(root_id).ok_or("old root node")?.0,
    );
    let nodes = ids.into_iter().map(|id| {
        let node = &old_nodes[id];
        let bindings = node["bindings"].as_object().ok_or("old bindings")?.iter().map(|(name, target)| {
            let target = old_nodes.get(target.as_str().ok_or("old binding target")?).ok_or("old target node")?;
            Ok(object!("irPackageName" => name.as_str(), "target" => release(&target["release"])))
        }).collect::<Result<Vec<_>>>()?;
        Ok(object!("release" => release(&node["release"]), "irPackageName" => &node["irPackageName"], "manifestDigest" => &node["manifestDigest"], "contentDigest" => &node["contentDigest"], "bindings" => bindings))
    }).collect::<Result<Vec<_>>>()?;
    files.insert("morphir.lock".into(), pretty(&object!("formatVersion" => VERSION, "kind" => "LibraryLock", "resolution" => object!("policy" => "flat-library:0.1.0-draft.2", "profile" => "local-library", "requiredCapabilities" => vec![Json::from("dsse-ed25519"), "local-directory".into(), "tuf-1.0.36".into()]), "graph" => object!("root" => release(&old_nodes[root_id]["release"]), "nodes" => nodes), "registries" => vec![object!("id" => "finance", "snapshot" => "finance-snapshot")], "acquisitions" => acquisitions, "evidence" => evidences.into_values().collect::<Vec<_>>())));
    let identity = digest(&canonical(&root_body));
    let mut publisher_keys = [public("publisher-a"), public("publisher-b")];
    publisher_keys.sort();
    files.insert("trust-policy.json".into(), pretty(&object!("formatVersion" => VERSION, "kind" => "LibraryTrustPolicy", "repositories" => vec![object!("identity" => identity.clone(), "bootstrapRoot" => object!("version" => 1usize, "digest" => digest(&root_bytes)), "namespaces" => vec![Json::from("example.com/finance")])], "publisherRules" => vec![object!("namespace" => "example.com/finance", "publicKeys" => publisher_keys.into_iter().map(Json::from).collect::<Vec<_>>(), "threshold" => 1usize)], "continuedUse" => "previous-authorization")));
    files.insert("configuration-one.json".into(), pretty(&object!("bindings" => vec![object!("alias" => "finance", "registryRoot" => "finance", "identity" => identity.clone())], "bootstrapRoots" => vec![object!("identity" => identity, "version" => "1", "bytes" => bytes_value(&root_bytes))])));
    let mut entries = BTreeMap::new();
    let mut directories = BTreeSet::new();
    for (path, bytes) in &files {
        if let Some(path) = path.strip_prefix("registry/") {
            entries.insert(
                path.to_owned(),
                object!("kind" => "file", "path" => path, "bytes" => bytes_value(bytes)),
            );
            let parts: Vec<_> = path.split('/').collect();
            for end in 1..parts.len() {
                directories.insert(parts[..end].join("/"));
            }
        }
    }
    for path in directories {
        entries.insert(path.clone(), object!("kind" => "directory", "path" => path));
    }
    files.insert(
        "view-one.json".into(),
        pretty(&object!("entries" => entries.into_values().collect::<Vec<_>>())),
    );
    files.insert(
        "empty-cache.json".into(),
        pretty(&object!("entries" => Vec::<Json>::new())),
    );
    let digests: BTreeMap<_, _> = INPUT_DIGESTS
        .into_iter()
        .map(|(path, hash)| (path.to_string(), Json::from(format!("sha256:{hash}"))))
        .collect();
    files.insert("fixture-description.json".into(), pretty(&object!("kind" => "PublicDeterministicSignedFixture", "fixedClock" => CLOCK,
        "tools" => object!("bun" => "1.4.2", "tuf-js" => "5.0.1", "@tufjs/canonical-json" => "2.0.0", "@noble/curves" => "2.4.0"),
        "keyDerivation" => "SHA-256 of UTF-8 morphir-mck-fixture:<label>; public test seeds only",
        "publicKeys" => roles.into_iter().chain(["publisher-a", "publisher-b"]).map(|label| object!("label" => label, "publicKey" => public(label))).collect::<Vec<_>>(), "inputDigests" => Json::Object(digests.into_iter().collect()))));
    Ok(files)
}
