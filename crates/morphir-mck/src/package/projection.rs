//! Contract result validation and the explicitly unordered collections only.
use super::{
    Operation,
    json::{digest, fields, string},
    schemas::Catalog,
};
use serde_json::Value;
use std::{
    cmp::Ordering,
    collections::{BTreeMap, BTreeSet},
    sync::OnceLock,
};

// The protocol's structural boundary remains closed even if a kit supplies a
// permissive replacement schema. These are specification schemas, not a codec.
fn protocol_catalog() -> &'static Catalog {
    static CATALOG: OnceLock<Catalog> = OnceLock::new();
    CATALOG.get_or_init(|| {
        let sources = [
            (
                "schemas/library-manifest.schema.json",
                include_str!("../../../../spec/package/schemas/library-manifest.schema.json"),
            ),
            (
                "schemas/lock-core.schema.json",
                include_str!("../../../../spec/package/schemas/lock-core.schema.json"),
            ),
            (
                "schemas/resolution-input.schema.json",
                include_str!("../../../../spec/package/schemas/resolution-input.schema.json"),
            ),
            (
                "schemas/resolution-result.schema.json",
                include_str!("../../../../spec/package/schemas/resolution-result.schema.json"),
            ),
            (
                "schemas/resolution-case.schema.json",
                include_str!("../../../../spec/package/schemas/resolution-case.schema.json"),
            ),
        ];
        Catalog::compile(
            &sources
                .into_iter()
                .map(|(name, text)| {
                    (
                        name.into(),
                        super::json::parse(text).expect("checked-in schema"),
                    )
                })
                .collect(),
        )
        .expect("checked-in package protocol schemas compile")
    })
}
pub(super) fn project(
    operation: Operation,
    value: &Value,
    catalog: &Catalog,
) -> Result<Value, String> {
    if operation == Operation::ResolveLibrary {
        catalog.validate("schemas/resolution-result.schema.json", value)?;
        protocol_catalog().validate("schemas/resolution-result.schema.json", value)?;
        if value["ok"] == true {
            validate_graph(&value["graph"])?;
        }
        if let Some(witness) = value["diagnostic"].get("witness") {
            validate_witness(witness)?;
        }
        let mut result = value.clone();
        project_resolution(&mut result);
        return Ok(result);
    }
    if operation == Operation::Normalize && value["ok"] == false {
        fields(value, &["ok", "error"], &[])?;
        if value["error"] != "invalid-document" {
            return Err("unknown package error".into());
        }
        return Ok(value.clone());
    }
    if value["ok"] != true {
        return Err(format!(
            "package adapter did not return a result for {}",
            operation.as_str()
        ));
    }
    match operation {
        Operation::Normalize => {
            fields(
                value,
                &["ok", "canonical", "manifestDigest", "packageContentDigest"],
                &[],
            )?;
            string(&value["canonical"])?;
            digest(&value["manifestDigest"])?;
            digest(&value["packageContentDigest"])?;
        }
        Operation::HashBytes => {
            fields(value, &["ok", "digest"], &[])?;
            digest(&value["digest"])?;
        }
        Operation::Validate | Operation::VerifyLibrarySet => {
            fields(value, &["ok", "valid"], &[])?;
            if !value["valid"].is_boolean() {
                return Err("expected boolean validation result".into());
            }
        }
        Operation::ResolveLibrary => unreachable!(),
    }
    Ok(value.clone())
}
fn text(value: &Value) -> &str {
    value.as_str().expect("protocol schema checked string")
}
fn list(value: &Value) -> &[Value] {
    value.as_array().expect("protocol schema checked array")
}
fn release_key(value: &Value) -> String {
    format!(
        "{}\0{}",
        text(&value["packagePath"]),
        text(&value["version"])
    )
}
fn validate_graph(graph: &Value) -> Result<(), String> {
    let nodes = list(&graph["nodes"]);
    if nodes.is_empty() {
        return Err("resolution graph must contain nodes".into());
    }
    let mut identities = BTreeMap::new();
    let mut paths = BTreeSet::new();
    let mut names = BTreeSet::new();
    for node in nodes {
        if identities
            .insert(release_key(&node["release"]), node)
            .is_some()
            || !paths.insert(text(&node["release"]["packagePath"]))
            || !names.insert(text(&node["irPackageName"]))
        {
            return Err("duplicate resolution graph identity".into());
        }
        unique_bindings(node)?;
    }
    let root = release_key(&graph["root"]);
    if !identities.contains_key(&root) {
        return Err("resolution graph root is missing".into());
    }
    for node in nodes {
        for binding in list(&node["bindings"]) {
            let target = identities
                .get(&release_key(&binding["target"]))
                .ok_or("resolution graph has a dangling binding")?;
            if binding["irPackageName"] != target["irPackageName"] {
                return Err("resolution graph binding name does not match its target node".into());
            }
        }
    }
    let mut visiting = BTreeSet::new();
    let mut visited = BTreeSet::new();
    let mut work = vec![(root, false)];
    while let Some((key, leaving)) = work.pop() {
        if leaving {
            visiting.remove(&key);
            visited.insert(key);
            continue;
        }
        if visiting.contains(&key) {
            return Err("resolution graph contains a cycle".into());
        }
        if visited.contains(&key) {
            continue;
        }
        visiting.insert(key.clone());
        work.push((key.clone(), true));
        for binding in list(&identities[&key]["bindings"]) {
            work.push((release_key(&binding["target"]), false));
        }
    }
    if visited.len() != nodes.len() {
        return Err("resolution graph contains unreachable nodes".into());
    }
    Ok(())
}
fn unique_bindings(node: &Value) -> Result<(), String> {
    let mut names = BTreeSet::new();
    for binding in list(&node["bindings"]) {
        if !names.insert(text(&binding["irPackageName"])) {
            return Err("duplicate resolution binding".into());
        }
    }
    Ok(())
}
fn occurrence_key(value: &Value) -> String {
    value.to_string()
}
fn validate_witness(witness: &Value) -> Result<(), String> {
    let nodes = list(&witness["nodes"]);
    if nodes.is_empty() {
        return Err("resolution witness must contain nodes".into());
    }
    let mut identities = BTreeMap::new();
    for node in nodes {
        if identities
            .insert(occurrence_key(&node["occurrence"]), node)
            .is_some()
        {
            return Err("duplicate resolution witness occurrence".into());
        }
        unique_bindings(node)?;
    }
    if !identities.contains_key("[]") {
        return Err("resolution witness root occurrence is missing".into());
    }
    for node in nodes {
        for binding in list(&node["bindings"]) {
            let mut expected = list(&node["occurrence"]).to_vec();
            expected.push(binding["irPackageName"].clone());
            if binding["targetOccurrence"] != Value::Array(expected) {
                return Err(
                    "resolution witness binding has a noncanonical target occurrence".into(),
                );
            }
            if !identities.contains_key(&occurrence_key(&binding["targetOccurrence"])) {
                return Err("resolution witness has a dangling binding".into());
            }
        }
    }
    let mut visited = BTreeSet::new();
    let mut ancestors = BTreeSet::new();
    let mut work = vec![("[]".to_owned(), false)];
    while let Some((key, leaving)) = work.pop() {
        let node = identities[&key];
        let release = release_key(&node["release"]);
        if leaving {
            ancestors.remove(&release);
            continue;
        }
        if ancestors.contains(&release) {
            return Err("resolution witness repeats a release on an ancestor path".into());
        }
        if !visited.insert(key.clone()) {
            continue;
        }
        ancestors.insert(release);
        work.push((key, true));
        for binding in list(&node["bindings"]) {
            work.push((occurrence_key(&binding["targetOccurrence"]), false));
        }
    }
    if visited.len() != nodes.len() {
        return Err("resolution witness contains unreachable occurrences".into());
    }
    Ok(())
}
fn version_cmp(left: &Value, right: &Value) -> Ordering {
    text(left)
        .split('.')
        .zip(text(right).split('.'))
        .map(|(a, b)| a.len().cmp(&b.len()).then_with(|| a.cmp(b)))
        .find(|order| !order.is_eq())
        .unwrap_or(Ordering::Equal)
}
fn release_cmp(left: &Value, right: &Value) -> Ordering {
    text(&left["packagePath"])
        .cmp(text(&right["packagePath"]))
        .then_with(|| version_cmp(&right["version"], &left["version"]))
}
fn sort_field(value: &mut Value, field: &str, compare: impl FnMut(&Value, &Value) -> Ordering) {
    value[field]
        .as_array_mut()
        .expect("validated array")
        .sort_by(compare);
}
fn by_text(field: &'static str) -> impl Fn(&Value, &Value) -> Ordering {
    move |a, b| text(&a[field]).cmp(text(&b[field]))
}
fn project_release(value: &mut Value) {
    sort_field(value, "dependencies", by_text("irPackageName"));
}
fn project_resolution(value: &mut Value) {
    if value["ok"] == true {
        let graph = &mut value["graph"];
        let root = graph["root"].clone();
        for node in graph["nodes"].as_array_mut().expect("validated nodes") {
            sort_field(node, "bindings", by_text("irPackageName"));
        }
        sort_field(graph, "nodes", |a, b| {
            (b["release"] == root)
                .cmp(&(a["release"] == root))
                .then_with(|| release_cmp(&a["release"], &b["release"]))
        });
        return;
    }
    let diagnostic = &mut value["diagnostic"];
    match text(&diagnostic["code"]) {
        "invalid-input" | "invalid-lock" => sort_field(diagnostic, "violations", |a, b| {
            by_text("pointer")(a, b).then_with(|| by_text("rule")(a, b))
        }),
        "incomplete-input" => sort_field(diagnostic, "missing", |a, b| {
            by_text("kind")(a, b).then_with(|| {
                if a["kind"] == "catalog" {
                    by_text("packagePath")(a, b)
                } else {
                    release_cmp(&a["release"], &b["release"])
                }
            })
        }),
        "update-scope-conflict" | "unsupported-capability" => {
            sort_field(diagnostic, "changedPins", |a, b| {
                text(&a["previous"]["packagePath"])
                    .cmp(text(&b["previous"]["packagePath"]))
                    .then_with(|| {
                        if a["kind"] == "changed" && b["kind"] == "changed" {
                            version_cmp(&b["selected"]["version"], &a["selected"]["version"])
                        } else {
                            by_text("kind")(a, b)
                        }
                    })
            });
            let witness = &mut diagnostic["witness"];
            for node in witness["nodes"].as_array_mut().expect("validated nodes") {
                sort_field(node, "bindings", by_text("irPackageName"));
            }
            sort_field(witness, "nodes", |a, b| {
                list(&a["occurrence"])
                    .iter()
                    .map(text)
                    .cmp(list(&b["occurrence"]).iter().map(text))
            });
        }
        "unsatisfiable-requirements" => {
            project_release(&mut diagnostic["root"]);
            for catalog in diagnostic["catalogs"]
                .as_array_mut()
                .expect("validated catalogs")
            {
                for release in catalog["releases"]
                    .as_array_mut()
                    .expect("validated releases")
                {
                    project_release(release);
                }
                sort_field(catalog, "releases", |a, b| {
                    version_cmp(&b["release"]["version"], &a["release"]["version"])
                });
            }
            sort_field(diagnostic, "catalogs", by_text("packagePath"));
            sort_field(diagnostic, "targets", by_text("packagePath"));
        }
        _ => unreachable!("validated diagnostic code"),
    }
}
