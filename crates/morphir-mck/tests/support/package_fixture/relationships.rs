// Copyright 2026 FINOS
// SPDX-License-Identifier: Apache-2.0
//! Frozen artifact checks independent of authoring and of the package implementation.
use super::{Files, Result, decode_hex, verify_dsse};
use base64::{Engine, engine::general_purpose::STANDARD};
use jsonschema::{Resource, Retrieve, Uri};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::Path,
};
const VERSION: &str = "0.1.0-draft.3";
fn require(condition: bool, message: &str) -> Result<()> {
    if condition {
        Ok(())
    } else {
        Err(message.to_owned().into())
    }
}
fn bytes<'a>(files: &'a Files, path: &str) -> Result<&'a [u8]> {
    files
        .get(path)
        .map(Vec::as_slice)
        .ok_or_else(|| format!("Missing fixture file: {path}").into())
}
fn document(files: &Files, path: &str) -> Result<Value> {
    Ok(serde_json::from_slice(bytes(files, path)?)?)
}
fn digest(data: &[u8]) -> String {
    format!(
        "sha256:{}",
        Sha256::digest(data)
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect::<String>()
    )
}
fn canonical(value: &Value) -> Result<Vec<u8>> {
    Ok(serde_json::to_vec(value)?)
}
fn physical(reference: &Value) -> Result<String> {
    let path = reference["path"].as_str().ok_or("reference path")?;
    let hash = reference["digest"]
        .as_str()
        .and_then(|d| d.strip_prefix("sha256:"))
        .ok_or("reference digest")?;
    let (directory, leaf) = path.rsplit_once('/').ok_or("logical path")?;
    Ok(format!("registry/targets/{directory}/{hash}.{leaf}"))
}
struct Offline;
impl Retrieve for Offline {
    fn retrieve(
        &self,
        uri: &Uri<&str>,
    ) -> std::result::Result<Value, Box<dyn std::error::Error + Send + Sync>> {
        Err(format!("No network schema retrieval: {uri}").into())
    }
}
struct Schemas {
    values: Vec<Value>,
}
impl Schemas {
    fn load(source: &Path) -> Result<Self> {
        let values = [
            "library-manifest",
            "lock-core",
            "resolution-input",
            "resolution-result",
            "resolution-case",
            "library-lock",
            "registry-record",
            "release-statement",
            "package-trust-policy",
            "local-registry-case",
        ]
        .into_iter()
        .map(|name| {
            Ok(serde_json::from_slice(&fs::read(source.join(format!(
                "spec/package/schemas/{name}.schema.json"
            )))?)?)
        })
        .collect::<Result<_>>()?;
        Ok(Self { values })
    }
    fn validate(&self, name: &str, version: &str, fragment: &str, value: &Value) -> Result<()> {
        let mut options = jsonschema::options();
        options.with_retriever(Offline);
        for resource in &self.values {
            options.with_resource(
                resource["$id"].as_str().ok_or("schema ID")?,
                Resource::from_contents(resource.clone())?,
            );
        }
        let validator = options.build(&json!({"$ref":format!("https://morphir.finos.org/spec/package/{version}/{name}.schema.json{fragment}")}))?;
        validator
            .validate(value)
            .map_err(|e| format!("{name}{fragment}: {e} at {}", e.instance_path).into())
    }
}
pub fn verify_relationships(source: &Path, files: &Files) -> Result<()> {
    let schemas = Schemas::load(source)?;
    let lock = document(files, "morphir.lock")?;
    let policy = document(files, "trust-policy.json")?;
    schemas.validate("library-lock", VERSION, "", &lock)?;
    schemas.validate("package-trust-policy", VERSION, "", &policy)?;
    for (path, kind) in [
        ("view-one.json", "Tree"),
        ("empty-cache.json", "Tree"),
        ("configuration-one.json", "Configuration"),
    ] {
        schemas.validate(
            "local-registry-case",
            VERSION,
            &format!("#/$defs/{kind}"),
            &document(files, path)?,
        )?;
    }
    require(
        lock["resolution"]
            == json!({"policy":"flat-library:0.1.0-draft.2","profile":"local-library","requiredCapabilities":["dsse-ed25519","local-directory","tuf-1.0.36"]}),
        "resolution profile",
    )?;
    require(
        lock["registries"] == json!([{"id":"finance","snapshot":"finance-snapshot"}]),
        "registry link",
    )?;
    let parent_json = |path: &str| -> Result<Value> {
        Ok(serde_json::from_slice(&fs::read(
            source.join("spec/package/mck").join(path),
        )?)?)
    };
    let old = parent_json("fixtures/two-libraries/lock-core.json")?;
    let old_root = old["root"].as_str().ok_or("old root")?;
    require(
        lock["graph"]["root"] == old["nodes"][old_root]["release"],
        "graph root",
    )?;
    let nodes = lock["graph"]["nodes"].as_array().ok_or("lock nodes")?;
    require(
        nodes.len() == 2 && nodes[0]["release"] == lock["graph"]["root"],
        "two nodes, root first",
    )?;
    for node in nodes {
        let prior = old["nodes"]
            .as_object()
            .ok_or("prior nodes")?
            .values()
            .find(|p| p["release"] == node["release"])
            .ok_or("prior node")?;
        for field in [
            "release",
            "irPackageName",
            "manifestDigest",
            "contentDigest",
        ] {
            require(node[field] == prior[field], "prior graph identity")?;
        }
        let bindings: Vec<_> = prior["bindings"].as_object().ok_or("prior bindings")?.iter().map(|(name,id)| json!({"irPackageName":name,"target":old["nodes"][id.as_str().unwrap()]["release"]})).collect();
        require(node["bindings"] == json!(bindings), "graph bindings")?;
    }
    let rule = &policy["publisherRules"][0];
    let repository = &policy["repositories"][0];
    require(
        rule["namespace"] == "example.com/finance"
            && rule["threshold"] == 1
            && policy["continuedUse"] == "previous-authorization",
        "publisher policy",
    )?;
    let keys = rule["publicKeys"]
        .as_array()
        .ok_or("publisher keys")?
        .iter()
        .map(|v| v.as_str().map(String::from).ok_or("publisher key"))
        .collect::<std::result::Result<Vec<_>, _>>()?;
    require(
        keys.len() == 2 && keys[0] < keys[1],
        "distinct sorted publishers",
    )?;
    let root_bytes = bytes(files, "registry/metadata/1.root.json")?;
    let root = document(files, "registry/metadata/1.root.json")?;
    require(
        repository["identity"] == digest(&canonical(&root["signed"])?),
        "repository identity",
    )?;
    require(
        repository["bootstrapRoot"] == json!({"version":1,"digest":digest(root_bytes)}),
        "bootstrap root",
    )?;
    require(
        repository["namespaces"] == json!(["example.com/finance"]),
        "repository namespaces",
    )?;
    let mut distinct: BTreeSet<_> = keys.iter().cloned().collect();
    for key in root["signed"]["keys"]
        .as_object()
        .ok_or("root keys")?
        .values()
    {
        distinct.insert(
            key["keyval"]["public"]
                .as_str()
                .ok_or("role public key")?
                .into(),
        );
    }
    require(distinct.len() == 6, "six distinct role and publisher keys")?;
    let targets_doc = document(files, "registry/metadata/1.targets.json")?;
    let targets = targets_doc["signed"]["targets"]
        .as_object()
        .ok_or("targets")?;
    require(
        targets.keys().map(String::as_str).collect::<Vec<_>>()
            == [
                "records/eligibility-1.2.0.json",
                "records/loan-rules-1.0.0.json",
                "statements/eligibility-1.2.0.json",
                "statements/loan-rules-1.0.0.json",
            ],
        "four expected targets",
    )?;
    let acquisitions = lock["acquisitions"].as_array().ok_or("acquisitions")?;
    require(acquisitions.len() == 2, "two acquisitions")?;
    for acquisition in acquisitions {
        let record_path = physical(&acquisition["record"])?;
        let record = document(files, &record_path)?;
        schemas.validate("registry-record", VERSION, "", &record)?;
        let mut canonical_record = canonical(&record)?;
        canonical_record.push(b'\n');
        require(
            bytes(files, &record_path)? == canonical_record,
            "canonical record with one LF",
        )?;
        require(
            record["release"] == acquisition["release"]
                && record["source"] == acquisition["source"]
                && acquisition["registry"] == "finance",
            "acquisition record",
        )?;
        let evidence = lock["evidence"]
            .as_array()
            .ok_or("evidence")?
            .iter()
            .find(|e| e["id"] == acquisition["statement"])
            .ok_or("statement evidence")?;
        require(
            evidence["kind"] == "release-statement" && evidence["registry"] == "finance",
            "statement evidence role",
        )?;
        require(
            record["statement"] == json!({"path":evidence["path"],"digest":evidence["digest"]}),
            "statement evidence reference",
        )?;
        let envelope = document(files, &physical(&record["statement"])?)?;
        require(
            verify_dsse(&envelope, &keys, 2),
            "both independent publishers verify",
        )?;
        let payload_bytes = STANDARD.decode(envelope["payload"].as_str().ok_or("DSSE payload")?)?;
        let payload: Value = serde_json::from_slice(&payload_bytes)?;
        schemas.validate("release-statement", VERSION, "", &payload)?;
        require(
            payload_bytes == canonical(&payload)?,
            "canonical statement, no LF",
        )?;
        let mut record_payload = record.clone();
        record_payload.as_object_mut().unwrap().remove("source");
        record_payload.as_object_mut().unwrap().remove("statement");
        record_payload["kind"] = "LibraryReleaseStatement".into();
        require(payload == record_payload, "record/statement agreement")?;
        let bundle = format!(
            "registry/{}",
            record["source"]["path"].as_str().ok_or("bundle path")?
        );
        let manifest = document(files, &format!("{bundle}/manifest.json"))?;
        schemas.validate("library-manifest", "0.1.0-draft.1", "", &manifest)?;
        let normalized = canonical(&manifest)?;
        let mut content = b"morphir-package-content:0.1.0-draft.1\n".to_vec();
        content.extend(&normalized);
        require(
            record["manifestDigest"] == digest(&normalized)
                && record["contentDigest"] == digest(&content),
            "normalized digests",
        )?;
        require(
            record["release"]
                == json!({"packagePath":manifest["packagePath"],"version":manifest["version"]})
                && record["irPackageName"] == manifest["ir"]["packageName"],
            "manifest identity",
        )?;
        let dependencies: Vec<_> = manifest["dependencies"]
            .as_object()
            .ok_or("dependencies")?
            .iter()
            .map(|(name, value)| {
                let mut v = value.clone();
                v["irPackageName"] = name.clone().into();
                v
            })
            .collect();
        require(
            record["dependencies"] == json!(dependencies),
            "manifest dependencies",
        )?;
        let package_name = record["release"]["packagePath"]
            .as_str()
            .and_then(|p| p.rsplit('/').next())
            .ok_or("package name")?;
        for path in std::iter::once("manifest.json").chain(
            manifest["content"]
                .as_object()
                .unwrap()
                .keys()
                .map(String::as_str),
        ) {
            let stored = bytes(files, &format!("{bundle}/{path}"))?;
            require(
                stored
                    == fs::read(source.join(format!(
                        "spec/package/mck/fixtures/two-libraries/{package_name}/{path}"
                    )))?,
                "original bundle bytes",
            )?;
            if path != "manifest.json" {
                require(
                    manifest["content"][path] == digest(stored),
                    "declared content digest",
                )?;
            }
        }
        let ir = document(files, &format!("{bundle}/ir.json"))?;
        let library = &ir["distribution"]["Library"];
        require(
            library["packageName"] == manifest["ir"]["packageName"],
            "IR package identity",
        )?;
        require(
            library["dependencies"]
                .as_object()
                .ok_or("IR dependencies")?
                .keys()
                .map(String::as_str)
                .collect::<Vec<_>>()
                == dependencies
                    .iter()
                    .map(|d| d["irPackageName"].as_str().unwrap())
                    .collect::<Vec<_>>(),
            "IR dependencies",
        )?;
        if package_name == "loan-rules" {
            require(
                String::from_utf8_lossy(bytes(files, &format!("{bundle}/ir.json"))?)
                    .contains("\"Reference\": \"example/eligibility:decision#default-decision\""),
                "cross-library reference",
            )?;
        }
        let node = nodes
            .iter()
            .find(|n| n["release"] == record["release"])
            .ok_or("matching graph node")?;
        for field in ["irPackageName", "manifestDigest", "contentDigest"] {
            require(node[field] == record[field], "graph record identity")?;
        }
        for (reference, kind) in [
            (&acquisition["record"], "LibraryRelease"),
            (&record["statement"], "LibraryReleaseStatement"),
        ] {
            let stored = bytes(files, &physical(reference)?)?;
            let target = &targets[reference["path"].as_str().ok_or("target reference")?];
            require(
                reference["digest"] == digest(stored)
                    && target["length"] == stored.len()
                    && target["hashes"]["sha256"] == digest(stored)[7..],
                "target reference hash/length",
            )?;
            let mut custom =
                json!({"formatVersion":VERSION,"kind":kind,"release":record["release"]});
            if kind == "LibraryRelease" {
                custom["status"] = "active".into();
            }
            require(
                target["custom"]["morphir"] == custom,
                "target Morphir custom fields",
            )?;
        }
    }
    for item in lock["evidence"].as_array().unwrap() {
        let path = if item["kind"] == "release-statement" {
            physical(item)?
        } else {
            format!("registry/{}", item["path"].as_str().ok_or("evidence path")?)
        };
        require(
            item["registry"] == "finance" && item["digest"] == digest(bytes(files, &path)?),
            "evidence digest",
        )?;
    }
    require(
        bytes(files, "registry/metadata/timestamp.json")?
            == bytes(files, "registry/metadata/1.timestamp.json")?,
        "timestamp alias",
    )?;
    let tree = document(files, "view-one.json")?;
    let mut seen_files = BTreeMap::new();
    let mut seen_dirs = BTreeSet::new();
    let entries = tree["entries"].as_array().ok_or("tree entries")?;
    let paths = entries
        .iter()
        .map(|e| e["path"].as_str().ok_or("tree path"))
        .collect::<std::result::Result<Vec<_>, _>>()?;
    require(paths.windows(2).all(|w| w[0] < w[1]), "sorted unique tree")?;
    for entry in entries {
        let path = entry["path"].as_str().unwrap();
        if entry["kind"] == "directory" {
            seen_dirs.insert(path);
        } else {
            seen_files.insert(
                path,
                decode_hex(entry["bytes"]["value"].as_str().ok_or("tree bytes")?)
                    .ok_or("tree hex")?,
            );
        }
    }
    let registry_files: BTreeMap<_, _> = files
        .iter()
        .filter_map(|(p, b)| p.strip_prefix("registry/").map(|p| (p, b.clone())))
        .collect();
    require(
        seen_files == registry_files,
        "tree contains exact registry bytes",
    )?;
    for path in paths {
        for (index, _) in path.match_indices('/') {
            require(
                seen_dirs.contains(&path[..index]),
                "tree ancestor directory",
            )?;
        }
    }
    require(
        document(files, "empty-cache.json")? == json!({"entries":[]}),
        "empty cache",
    )?;
    let root_hex: String = root_bytes.iter().map(|b| format!("{b:02x}")).collect();
    require(
        document(files, "configuration-one.json")?
            == json!({"bindings":[{"alias":"finance","registryRoot":"finance","identity":repository["identity"]}],"bootstrapRoots":[{"identity":repository["identity"],"version":"1","bytes":{"kind":"hex","value":root_hex}}]}),
        "configuration binds exact root",
    )?;
    require(root_hex.len() > 4000, "long root hex fixture")?;
    schemas.validate(
        "local-registry-case",
        VERSION,
        "#/$defs/Bytes",
        &json!({"kind":"hex","value":root_hex}),
    )?;
    require(
        schemas
            .validate(
                "local-registry-case",
                VERSION,
                "#/$defs/Bytes",
                &json!({"kind":"hex","value":&root_hex[1..]}),
            )
            .is_err(),
        "odd hex rejected",
    )?;
    require(
        schemas
            .validate(
                "local-registry-case",
                VERSION,
                "#/$defs/Bytes",
                &json!({"kind":"hex","value":format!("{}z",&root_hex[..root_hex.len()-1])}),
            )
            .is_err(),
        "nonhex rejected",
    )?;
    let index = parent_json("local-registry-cases.json")?;
    schemas.validate("local-registry-case", VERSION, "#/$defs/Index", &index)?;
    let bound: Vec<_> = index["assets"]
        .as_array()
        .ok_or("asset index")?
        .iter()
        .filter(|a| a["kind"] == "bound")
        .collect();
    require(
        bound
            .iter()
            .map(|a| a["id"].as_str().unwrap())
            .collect::<Vec<_>>()
            == [
                "view-one",
                "empty-cache",
                "configuration-one",
                "policy-one",
                "lock-two",
                "observations-wire-valid-two-node",
            ],
        "six unchanged bindings",
    )?;
    for asset in bound {
        let bytes = fs::read(
            source
                .join("spec/package/mck")
                .join(asset["path"].as_str().ok_or("asset path")?),
        )?;
        let expected_length = bytes.len().to_string();
        require(
            asset["length"].as_str() == Some(expected_length.as_str())
                && asset["sha256"] == digest(&bytes),
            "bound asset bytes",
        )?;
    }
    let observations =
        parent_json("fixtures/local-registry/expected/observations-wire-valid-two-node.json")?;
    schemas.validate(
        "local-registry-case",
        VERSION,
        "#/$defs/Observations",
        &observations,
    )?;
    let wire = parent_json("fixtures/local-registry/cases/wire.json")?;
    schemas.validate("local-registry-case", VERSION, "", &wire)?;
    let scenario = wire["cases"]
        .as_array()
        .ok_or("wire cases")?
        .iter()
        .find(|c| c["id"] == "local-registry.wire.valid-two-node")
        .ok_or("valid wire scenario")?;
    require(
        scenario["operations"][0]["expected"]["result"]["graph"] == lock["graph"],
        "frozen expected graph",
    )?;
    require(
        scenario["expectedObservations"]["asset"] == "observations-wire-valid-two-node",
        "frozen observations binding",
    )?;
    for assertion in scenario["expectedObservations"]["assertions"]
        .as_array()
        .ok_or("observation assertions")?
    {
        require(
            observations.pointer(assertion["pointer"].as_str().ok_or("observation pointer")?)
                == Some(&assertion["equals"]),
            "frozen observation assertion",
        )?;
    }
    Ok(())
}
