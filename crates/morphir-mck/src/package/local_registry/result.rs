use super::super::{Operation, projection, schemas::Catalog};
use super::validation::*;
use serde_json::{Value, json};
use std::{cmp::Ordering, collections::BTreeMap, sync::OnceLock};
pub(super) fn maximum(resource: &str) -> Option<&'static str> {
    Some(match resource {
        "manifest-bytes" | "record-bytes" | "statement-bytes" | "envelope-bytes"
        | "policy-bytes" | "root-bytes" | "timestamp-bytes" | "snapshot-bytes" => "1048576",
        "lock-bytes" | "targets-bytes" => "16777216",
        "metadata-bytes" | "file-bytes" => "268435456",
        "publisher-keys" | "role-keys" | "signatures" | "json-depth" => "64",
        "registries" | "root-rotations" | "path-components" => "32",
        "bundle-bytes" => "1073741824",
        "operation-content-bytes" => "8589934592",
        "declared-files" => "4096",
        "bundle-entries" => "65536",
        "operation-entries" => "1048576",
        "graph-nodes" | "node-bindings" => "512",
        "graph-bindings" => "32768",
        "catalog-releases" => "4096",
        "evidence-entries" => "2048",
        "target-entries" => "8192",
        "publisher-rules" | "namespace-grants" => "1024",
        "tuf-keys" => "256",
        "path-bytes" => "240",
        "component-bytes" => "128",
        _ => return None,
    })
}
fn resolution_catalog() -> &'static Catalog {
    static CATALOG: OnceLock<Catalog> = OnceLock::new();
    CATALOG.get_or_init(|| {
        let sources = [
            (
                "schemas/library-manifest.schema.json",
                include_str!("../../../../../spec/package/schemas/library-manifest.schema.json"),
            ),
            (
                "schemas/lock-core.schema.json",
                include_str!("../../../../../spec/package/schemas/lock-core.schema.json"),
            ),
            (
                "schemas/resolution-input.schema.json",
                include_str!("../../../../../spec/package/schemas/resolution-input.schema.json"),
            ),
            (
                "schemas/resolution-result.schema.json",
                include_str!("../../../../../spec/package/schemas/resolution-result.schema.json"),
            ),
        ];
        Catalog::compile(
            &sources
                .into_iter()
                .map(|(name, source)| {
                    (
                        name.into(),
                        serde_json::from_str(source).expect("checked-in schema"),
                    )
                })
                .collect::<BTreeMap<_, _>>(),
        )
        .expect("checked-in schemas compile")
    })
}
fn validate_resolution(value: &Value, label: &str) -> Result<(), String> {
    let projected = projection::project(Operation::ResolveLibrary, value, resolution_catalog())?;
    equal(value, &projected, label)
}
pub(super) fn validate(
    value: &Value,
    operation: Option<&Value>,
    parse: bool,
) -> Result<(), String> {
    if value["ok"] == true {
        if parse {
            return Err("parse cases require rejection".into());
        }
        if let Some(operation) = operation {
            let expected = match text(&operation["name"])? {
                "publish-library" => "publication",
                "refresh-library-registry" => "registry-refreshed",
                _ => "graph-ready",
            };
            equal(&value["kind"], &json!(expected), "operation/result kind")?;
            if value["kind"] == "registry-refreshed" {
                equal(
                    &value["registry"],
                    &operation["input"]["registry"],
                    "refreshed registry",
                )?;
            }
        }
        if value["kind"] == "graph-ready" {
            validate_resolution(
                &json!({"ok":true,"graph":value["graph"]}),
                "graph presentation",
            )?;
            equal(
                &value["verified"],
                &Value::Array(
                    list(&value["graph"]["nodes"])?
                        .iter()
                        .map(|node| node["release"].clone())
                        .collect(),
                ),
                "graph/verified output",
            )?;
            if let Some(operation) = operation
                && ["resolve-library", "update-library"].contains(&text(&operation["name"])?)
            {
                equal(
                    &value["graph"]["root"],
                    &operation["input"]["root"],
                    "requested graph root",
                )?;
            }
        }
        return Ok(());
    }
    let diagnostic = &value["diagnostic"];
    let code = text(&diagnostic["code"])?;
    let witnesses = list(&diagnostic["witnesses"])?;
    if ["io-failure", "resource-limit", "unsafe-path"].contains(&code) && witnesses.len() != 1 {
        return Err("fatal diagnostic requires exactly one witness".into());
    }
    sorted(witnesses, "diagnostic witnesses")?;
    let category = match code {
        "invalid-input" | "resolution-invalid" => "invalid-input",
        "unsupported-profile"
        | "unsupported-source"
        | "unsupported-capability"
        | "unsupported-payload-type"
        | "capability-unavailable"
        | "filesystem-unsupported"
        | "resolution-unsupported"
        | "record-replacement-unsupported" => "unsupported-capability",
        "missing-content" | "io-failure" | "commit-outcome-uncertain" => "operational-failure",
        _ => "domain-rejection",
    };
    equal(
        &diagnostic["category"],
        &json!(category),
        "diagnostic category",
    )?;
    for witness in witnesses {
        let kind = text(&witness["kind"])?;
        match kind {
            "authority" => {
                let rule = match code {
                    "unauthorized-repository" => "namespace-denied",
                    "unauthorized-publisher" => "publisher-rule-missing",
                    "previous-authorization-ineligible" => "previous-grant-ineligible",
                    "release-revoked" => "revoked",
                    "freshness-required" => "fresh-view-required",
                    _ => return Err("authority rule mismatch".into()),
                };
                equal(&witness["rule"], &json!(rule), "authority rule")?;
            }
            "repository-authority" => {
                if code != "unauthorized-repository" || witness["rule"] != "repository-unconfigured"
                {
                    return Err("repository authority rule mismatch".into());
                }
            }
            "resource" => {
                let max = decimal(&witness["maximum"])?;
                if decimal(&witness["observed"])? != successor(max) {
                    return Err("resource maximum + 1 mismatch".into());
                }
                let profile = maximum(text(&witness["resource"])?)
                    .ok_or("resource profile maximum mismatch")?;
                if if witness["scope"] == "profile" {
                    max != profile
                } else {
                    decimal_cmp(max, profile) != Ordering::Less
                } {
                    return Err("resource profile maximum mismatch".into());
                }
                if let Some(operation) = operation {
                    let limit = list(&operation["limits"])?
                        .iter()
                        .find(|l| l["resource"] == witness["resource"]);
                    let effective = match limit {
                        Some(limit) => decimal(&limit["maximum"])?,
                        None => profile,
                    };
                    if max != effective {
                        return Err("resource caller maximum mismatch".into());
                    }
                }
            }
            "resolver" => {
                validate_resolution(
                    &json!({"ok":false,"diagnostic":witness["diagnostic"]}),
                    "resolver witness ordering",
                )?;
                let category = match text(&witness["diagnostic"]["code"])? {
                    "invalid-input" | "invalid-lock" => "resolution-invalid",
                    "unsupported-capability" => "resolution-unsupported",
                    _ => "resolution-rejected",
                };
                if code != category {
                    return Err("resolver category mismatch".into());
                }
            }
            "time" => {
                let at = text(&witness["at"])?;
                let boundary = text(&witness["boundary"])?;
                if if code == "metadata-expired" {
                    witness["role"] == "clock" || at < boundary
                } else {
                    code != "trusted-time-unavailable"
                        || witness["role"] != "clock"
                        || at >= boundary
                } {
                    return Err("time diagnostic relationship mismatch".into());
                }
            }
            "rollback" => {
                let order = decimal_cmp(
                    decimal(&witness["received"])?,
                    decimal(&witness["trusted"])?,
                );
                let publication = diagnostic["phase"] == "publication"
                    && witness["role"] != "root"
                    && operation.is_none_or(|o| o["name"] == "publish-library");
                if order == Ordering::Greater || (order == Ordering::Equal && !publication) {
                    return Err("role version rollback relationship mismatch".into());
                }
            }
            "continuity" => {
                let missing = list(&witness["missingVersions"])?;
                for version in missing {
                    decimal(version)?;
                }
                sorted_by(missing, "missing root versions", decimal_cmp)?;
                let from = decimal(&witness["fromVersion"])?;
                let through = decimal(&witness["throughVersion"])?;
                if decimal_cmp(from, through) == Ordering::Greater
                    || missing.iter().any(|v| {
                        let v = v.as_str().expect("decimal");
                        decimal_cmp(v, from) == Ordering::Less
                            || decimal_cmp(v, through) == Ordering::Greater
                    })
                {
                    return Err("root continuity version range mismatch".into());
                }
            }
            "revision" => {
                if witness["expected"] == witness["actual"] {
                    return Err("revision conflict requires different revisions".into());
                }
            }
            "digest" | "length" | "replacement" | "immutable" => {
                let expected = witness.get("expected").unwrap_or(&witness["existing"]);
                let actual = witness.get("actual").unwrap_or(&witness["proposed"]);
                if expected == actual {
                    return Err(format!("{kind} conflict requires different values"));
                }
            }
            "authentication" => {
                if decimal_cmp(
                    decimal(&witness["verified"])?,
                    decimal(&witness["required"])?,
                ) != Ordering::Less
                {
                    return Err("authentication failure reached threshold".into());
                }
            }
            "views" => sorted(list(&witness["snapshots"])?, "conflicting views")?,
            "catalog" => {
                let keys = list(&witness["candidates"])?
                    .iter()
                    .map(|c| {
                        Ok(json!(format!(
                            "{}\0{}\0{}",
                            text(&c["repository"])?,
                            text(&c["snapshot"])?,
                            text(&c["record"])?
                        )))
                    })
                    .collect::<Result<Vec<_>, String>>()?;
                sorted(&keys, "catalog candidates")?;
            }
            "release-conflict"
                if witness["existingManifest"] == witness["proposedManifest"]
                    && witness["existingContent"] == witness["proposedContent"] =>
            {
                return Err("release conflict requires changed content identity".into());
            }
            _ => {}
        }
    }
    Ok(())
}
