// Copyright 2026 FINOS
// SPDX-License-Identifier: Apache-2.0
//! Independent public-key authoring. Graph choices below are reviewed constants,
//! not resolver output. No package runtime is linked or called.
#[path = "../tests/support/package_fixture/mod.rs"]
#[allow(dead_code, unused_imports)]
pub mod fixture;
use fixture::{
    Files, Result,
    ordered::{canonical, pretty},
    signing::{digest, dsse, hash, tuf},
};
use serde_json::{Value, json};
use std::{collections::BTreeMap, path::Path};
const VERSION: &str = "0.1.0-draft.3";
fn bytes(v: &Value) -> Vec<u8> {
    pretty(&v.clone().into())
}
fn release(name: &str, version: &str) -> Value {
    json!({"packagePath":format!("example.com/finance/{name}"),"version":version})
}
fn requirement(name: &str, min: &str, max: &str) -> Value {
    json!({"packagePath":format!("example.com/finance/{name}"),"versionRange":{"minimumInclusive":min,"maximumExclusive":max}})
}
fn dependencies(name: &str, version: &str) -> Value {
    match (name, version) {
        ("loan-rules", _) => {
            json!({"example/eligibility":requirement("eligibility","1.0.0","2.0.0"),"example/sibling":requirement("sibling","1.0.0","3.0.0")})
        }
        ("eligibility", "1.2.0") => json!({"example/child":requirement("child","1.0.0","2.0.0")}),
        ("eligibility", "1.4.0") => {
            json!({"example/child":requirement("child","1.1.0","2.0.0"),"example/sibling":requirement("sibling","2.0.0","3.0.0")})
        }
        ("eligibility", _) => json!({"example/child":requirement("child","1.1.0","2.0.0")}),
        _ => json!({}),
    }
}
fn link(data: &[u8], version: u64) -> Value {
    json!({"version":version,"length":data.len(),"hashes":{"sha256":hash(data)}})
}
fn metadata(files: &mut Files, targets: Value, version: u64, prefix: &str, expires: &str) {
    for role in ["targets", "snapshot", "timestamp"] {
        let mut body =
            json!({"_type":role,"spec_version":"1.0.36","version":version,"expires":expires});
        if role == "targets" {
            body["targets"] = targets.clone();
        } else {
            let child = if role == "snapshot" {
                "targets"
            } else {
                "snapshot"
            };
            body["meta"] = json!({format!("{child}.json"):link(&files[&format!("{prefix}/{version}.{child}.json")],version)});
        }
        files.insert(
            format!("{prefix}/{version}.{role}.json"),
            pretty(&tuf(body.into(), role)),
        );
    }
    files.insert(
        format!("{prefix}/timestamp.json"),
        files[&format!("{prefix}/{version}.timestamp.json")].clone(),
    );
}
/// Frozen selection supplied explicitly, so authoring cannot choose a graph.
fn lock(
    files: &Files,
    records: &BTreeMap<String, Value>,
    selected: &[(&str, &str)],
    version: u64,
    prefix: &str,
) -> Value {
    let mut nodes = Vec::new();
    let mut acquisitions = Vec::new();
    let mut evidence = Vec::new();
    let mut sorted = selected.to_vec();
    sorted.sort();
    for (index, (name, ver)) in sorted.iter().enumerate() {
        let record = &records[&format!("{name}-{ver}")];
        let statement = format!("statement-{index}");
        let record_path = format!("records/{name}-{ver}.json");
        let record_bytes = {
            let mut b = canonical(record);
            b.push(b'\n');
            b
        };
        acquisitions.push(json!({"release":record["release"],"registry":"local","record":{"path":record_path,"digest":digest(&record_bytes)},"source":record["source"],"statement":statement}));
        evidence.push(json!({"id":statement,"kind":"release-statement","registry":"local","path":record["statement"]["path"],"digest":record["statement"]["digest"]}));
    }
    for (name, ver) in selected {
        let record = &records[&format!("{name}-{ver}")];
        let bindings: Vec<_> = record["dependencies"]
            .as_array()
            .unwrap()
            .iter()
            .map(|dep| {
                let target = selected
                    .iter()
                    .find(|(name, _)| dep["packagePath"] == format!("example.com/finance/{name}"))
                    .unwrap();
                json!({"irPackageName":dep["irPackageName"],"target":release(target.0,target.1)})
            })
            .collect();
        nodes.push(json!({"release":record["release"],"irPackageName":record["irPackageName"],"manifestDigest":record["manifestDigest"],"contentDigest":record["contentDigest"],"bindings":bindings}));
    }
    for role in ["root", "snapshot", "targets", "timestamp"] {
        let v = if role == "root" { 1 } else { version };
        let path = format!("metadata/{v}.{role}.json");
        let physical = if role == "root" {
            "registry/metadata/1.root.json".to_owned()
        } else {
            format!("{prefix}/{v}.{role}.json")
        };
        evidence.push(json!({"id":role,"kind":format!("tuf-{role}"),"registry":"local","path":path,"digest":digest(&files[&physical])}));
    }
    evidence.sort_by(|a, b| a["id"].as_str().cmp(&b["id"].as_str()));
    json!({"formatVersion":VERSION,"kind":"LibraryLock","resolution":{"policy":"flat-library:0.1.0-draft.2","profile":"local-library","requiredCapabilities":["dsse-ed25519","local-directory","tuf-1.0.36"]},"graph":{"root":release("loan-rules","1.0.0"),"nodes":nodes},"registries":[{"id":"local","snapshot":"snapshot"}],"acquisitions":acquisitions,"evidence":evidence})
}
pub fn generate(source: &Path) -> Result<Files> {
    let base = fixture::mvp::generate_mvp(source)?;
    let mut files = Files::new();
    for p in ["registry/metadata/1.root.json", "trust-policy.json"] {
        files.insert(p.into(), base[p].clone());
    }
    let original: Value = serde_json::from_slice(&std::fs::read(
        source.join("spec/package/mck/fixtures/two-libraries/eligibility/ir.json"),
    )?)?;
    let root_ir: Value = serde_json::from_slice(&std::fs::read(
        source.join("spec/package/mck/fixtures/two-libraries/loan-rules/ir.json"),
    )?)?;
    let dependency_spec = serde_json::to_string(
        &root_ir["distribution"]["Library"]["dependencies"]["example/eligibility"],
    )?;
    let mut records = BTreeMap::new();
    let mut targets = json!({});
    for (name, versions) in [
        ("loan-rules", vec!["1.0.0"]),
        ("eligibility", vec!["1.2.0", "1.3.0", "1.4.0", "1.9.0"]),
        ("child", vec!["1.0.0", "1.1.0"]),
        ("sibling", vec!["1.0.0", "1.1.0", "2.0.0"]),
    ] {
        for version in versions {
            let deps = dependencies(name, version);
            let mut ir: Value = if name == "loan-rules" {
                root_ir.clone()
            } else {
                serde_json::from_str(
                    &serde_json::to_string(&original)?
                        .replace("example/eligibility", &format!("example/{name}")),
                )?
            };
            let mut ir_dependencies = serde_json::Map::new();
            for dependency in deps.as_object().unwrap().keys() {
                ir_dependencies.insert(
                    dependency.clone(),
                    serde_json::from_str(
                        &dependency_spec.replace("example/eligibility", dependency),
                    )?,
                );
            }
            ir["distribution"]["Library"]["dependencies"] = ir_dependencies.into();
            let exports = if name == "loan-rules" {
                json!({"eligibility":"eligibility"})
            } else {
                json!({"decision":"decision"})
            };
            let ir_bytes = bytes(&ir);
            let manifest = json!({"formatVersion":"0.1.0-draft.1","kind":"Library","packagePath":format!("example.com/finance/{name}"),"version":version,"ir":{"formatVersion":"4","packageName":format!("example/{name}"),"payload":{"path":"ir.json","mediaType":"application/json","profile":"classic"}},"dependencies":deps,"exports":exports,"content":{"ir.json":digest(&ir_bytes)}});
            let normalized = canonical(&manifest);
            let mut content = b"morphir-package-content:0.1.0-draft.1\n".to_vec();
            content.extend(&normalized);
            let bundle = format!("bundles/{}", hash(&content));
            files.insert(format!("registry/{bundle}/manifest.json"), bytes(&manifest));
            files.insert(format!("registry/{bundle}/ir.json"), ir_bytes);
            let dependencies: Vec<_> = deps
                .as_object()
                .unwrap()
                .iter()
                .map(|(name, value)| {
                    let mut v = value.clone();
                    v["irPackageName"] = name.clone().into();
                    v
                })
                .collect();
            let payload = json!({"formatVersion":VERSION,"kind":"LibraryReleaseStatement","release":release(name,version),"irPackageName":format!("example/{name}"),"dependencies":dependencies,"manifestDigest":digest(&normalized),"contentDigest":digest(&content)});
            let envelope = pretty(&dsse(&canonical(&payload), &["publisher-a", "publisher-b"]));
            let mut record = payload.clone();
            record["kind"] = "LibraryRegistryRecord".into();
            record["source"] = json!({"kind":"registry-directory","path":bundle});
            record["statement"] = json!({"path":format!("statements/{name}-{version}.json"),"digest":digest(&envelope)});
            let mut record_bytes = canonical(&record);
            record_bytes.push(b'\n');
            for (directory, data, kind) in [
                ("records", record_bytes, "LibraryRelease"),
                ("statements", envelope, "LibraryReleaseStatement"),
            ] {
                let path = format!("{directory}/{name}-{version}.json");
                files.insert(
                    format!(
                        "registry/targets/{directory}/{}.{name}-{version}.json",
                        hash(&data)
                    ),
                    data.clone(),
                );
                let mut custom =
                    json!({"formatVersion":VERSION,"kind":kind,"release":release(name,version)});
                if directory == "records" {
                    custom["status"] = if version == "1.9.0" {
                        "yanked"
                    } else {
                        "active"
                    }
                    .into();
                }
                targets[&path] = json!({"length":data.len(),"hashes":{"sha256":hash(&data)},"custom":{"morphir":custom}});
            }
            records.insert(format!("{name}-{version}"), record);
        }
    }
    let old = [
        ("loan-rules", "1.0.0"),
        ("child", "1.0.0"),
        ("eligibility", "1.2.0"),
        ("sibling", "1.0.0"),
    ];
    let updated = [
        ("loan-rules", "1.0.0"),
        ("child", "1.1.0"),
        ("eligibility", "1.3.0"),
        ("sibling", "1.0.0"),
    ];
    let old_targets: serde_json::Map<String, Value> = targets
        .as_object()
        .unwrap()
        .iter()
        .filter(|(_, v)| {
            old.iter()
                .any(|(n, ver)| v["custom"]["morphir"]["release"] == release(n, ver))
        })
        .map(|(k, v)| (k.clone(), v.clone()))
        .collect();
    metadata(
        &mut files,
        old_targets.into(),
        1,
        "registry/metadata",
        "2020-01-01T00:00:00Z",
    );
    files.insert(
        "morphir.lock".into(),
        bytes(&lock(&files, &records, &old, 1, "registry/metadata")),
    );
    // Conflict release is present only in its separately signed repository view.
    let mut current = targets.clone();
    for dir in ["records", "statements"] {
        current
            .as_object_mut()
            .unwrap()
            .remove(&format!("{dir}/eligibility-1.4.0.json"));
    }
    metadata(
        &mut files,
        current.clone(),
        2,
        "registry/metadata",
        "2100-01-01T00:00:00Z",
    );
    files.insert(
        "expected/update.lock.json".into(),
        bytes(&lock(&files, &records, &updated, 2, "registry/metadata")),
    );
    files.insert(
        "expected/exact-old.lock.json".into(),
        bytes(&lock(&files, &records, &old, 2, "registry/metadata")),
    );
    metadata(
        &mut files,
        targets,
        2,
        "variants/scope-conflict",
        "2100-01-01T00:00:00Z",
    );
    for (name, status) in [
        ("yanked-frozen", "yanked"),
        ("yanked-root", "yanked"),
        ("revoked-frozen", "revoked"),
    ] {
        let mut target = current.clone();
        target[if name == "yanked-root" {
            "records/loan-rules-1.0.0.json"
        } else {
            "records/sibling-1.0.0.json"
        }]["custom"]["morphir"]["status"] = status.into();
        metadata(
            &mut files,
            target,
            2,
            &format!("variants/{name}"),
            "2100-01-01T00:00:00Z",
        );
        if status == "yanked" {
            files.insert(
                format!("expected/{name}.lock.json"),
                bytes(&lock(
                    &files,
                    &records,
                    &updated,
                    2,
                    &format!("variants/{name}"),
                )),
            );
        }
    }
    let timestamp: Value = serde_json::from_slice(&files["registry/metadata/timestamp.json"])?;
    let mut body = timestamp["signed"].clone();
    body["expires"] = "2020-01-01T00:00:00Z".into();
    files.insert(
        "variants/expired-timestamp.json".into(),
        pretty(&tuf(body.into(), "timestamp")),
    );
    Ok(files)
}
fn main() -> Result<()> {
    let args = fixture::parse_arguments(std::env::args().skip(1))?;
    let generated = generate(&args.source)?;
    match args.destination {
        fixture::Destination::Check(path) => fixture::check_files(&path, &generated)?,
        fixture::Destination::Output(path) => {
            fixture::write_files(&path, &generated, &args.source)?
        }
    }
    println!(
        "Scoped update fixture: {} independently authored files",
        generated.len()
    );
    Ok(())
}
