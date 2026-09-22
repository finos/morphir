use super::{result::maximum, semantics::Validated, validation::*};
use crate::kit::hash::{is_sha256_hex, sha256_hex};
use serde_json::{Value, json};
use std::{
    cmp::Ordering,
    collections::{BTreeMap, BTreeSet},
};
#[derive(Clone, Copy, PartialEq, Eq)]
enum OperationState {
    Running,
    Joined,
    Terminated,
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum BarrierState {
    Declared,
    Held,
    Released,
    Terminated,
}
struct Barrier {
    operation: String,
    state: BarrierState,
    fault: bool,
}
fn known(value: &Value, ids: &[String], label: &str) -> Result<(), String> {
    let id = text(value)?;
    if !ids.iter().any(|known| known == id) {
        return Err(format!("unknown {label} {id}"));
    }
    Ok(())
}
fn ids(entries: &[Value]) -> Result<Vec<String>, String> {
    entries
        .iter()
        .map(|e| text(&e["id"]).map(str::to_owned))
        .collect()
}
fn bytes(value: &Value, validated: &Validated) -> Result<Option<Vec<u8>>, String> {
    if value["kind"] == "hex" {
        let hex = text(&value["value"])?;
        if !hex.len().is_multiple_of(2) || !hex.is_ascii() {
            return Err("invalid hex bytes".into());
        }
        Ok(Some(
            (0..hex.len())
                .step_by(2)
                .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).map_err(|e| e.to_string()))
                .collect::<Result<_, _>>()?,
        ))
    } else {
        Ok(validated.bytes.get(text(&value["asset"])?).cloned())
    }
}
fn expected<'a>(
    operation: &'a Value,
    validated: &'a Validated,
) -> Result<Option<&'a Value>, String> {
    let expected = &operation["expected"];
    Ok(match text(&expected["kind"])? {
        "inline" => Some(&expected["result"]),
        "asset" => validated.documents.get(text(&expected["asset"])?),
        _ => None,
    })
}
fn alias(
    value: &Value,
    actor: &Value,
    aliases: &BTreeMap<String, Vec<String>>,
) -> Result<(), String> {
    // A pending configuration cannot establish alias membership.
    if let Some(configured) = aliases.get(text(actor)?) {
        known(value, configured, "actor registry alias")?;
    }
    Ok(())
}
pub(super) fn validate(entry: &Value, validated: &Validated) -> Result<(), String> {
    let setup = &entry["setup"];
    let actors = list(&setup["actors"])?;
    let registries = list(&setup["registries"])?;
    let operations = list(&entry["operations"])?;
    for (entries, label) in [
        (actors, "actor ID"),
        (registries, "registry ID"),
        (operations, "operation ID"),
    ] {
        unique(entries.iter().map(|e| &e["id"]), label)?;
    }
    let actor_ids = ids(actors)?;
    let registry_ids = ids(registries)?;
    let by_operation = operations
        .iter()
        .map(|op| Ok((text(&op["id"])?.to_owned(), op)))
        .collect::<Result<BTreeMap<_, _>, String>>()?;
    let mut aliases = BTreeMap::new();
    for actor in actors {
        if let Some(configuration) = validated
            .documents
            .get(text(&actor["configuration"]["asset"])?)
        {
            let bindings = list(&configuration["bindings"])?;
            aliases.insert(
                text(&actor["id"])?.to_owned(),
                bindings
                    .iter()
                    .map(|b| text(&b["alias"]).map(str::to_owned))
                    .collect::<Result<Vec<_>, _>>()?,
            );
            for binding in bindings {
                known(
                    &binding["registryRoot"],
                    &registry_ids,
                    "configuration registry root",
                )?;
            }
        }
    }
    for operation in operations {
        known(&operation["actor"], &actor_ids, "actor")?;
        let limits = list(&operation["limits"])?;
        unique(limits.iter().map(|l| &l["resource"]), "resource limit")?;
        for limit in limits {
            let profile =
                maximum(text(&limit["resource"])?).ok_or("caller limit exceeds profile maximum")?;
            if decimal_cmp(decimal(&limit["maximum"])?, profile) == Ordering::Greater {
                return Err("caller limit exceeds profile maximum".into());
            }
        }
        let input = &operation["input"];
        if let Some(id) = input.get("registry") {
            alias(id, &operation["actor"], &aliases)?;
        }
        if let Some(registries) = input.get("registries") {
            let registries = list(registries)?;
            unique(registries, "invocation registry")?;
            for id in registries {
                alias(id, &operation["actor"], &aliases)?;
            }
        }
    }
    let policies = list(&entry["observe"]["policies"])?;
    unique(
        policies.iter().map(|p| &p["actor"]),
        "observation policy actor",
    )?;
    let mut policy_actors = policies
        .iter()
        .map(|p| text(&p["actor"]).map(str::to_owned))
        .collect::<Result<Vec<_>, _>>()?;
    policy_actors.sort();
    let mut sorted_actors = actor_ids.clone();
    sorted_actors.sort();
    if policy_actors != sorted_actors {
        return Err("complete observation policies mismatch".into());
    }
    validate_schedule(entry, &actor_ids, &registry_ids, &by_operation, &aliases)?;
    let Some(snapshot) = validated
        .documents
        .get(text(&entry["expectedObservations"]["asset"])?)
    else {
        return Ok(());
    };
    validate_security(
        entry,
        validated,
        snapshot,
        &sorted_actors,
        &aliases,
        policies,
    )?;
    let mut sorted_registries = registry_ids.to_vec();
    sorted_registries.sort();
    equal(
        &json!(
            list(&snapshot["registries"])?
                .iter()
                .map(|r| r["registry"].clone())
                .collect::<Vec<_>>()
        ),
        &json!(sorted_registries),
        "complete sorted publisher registries",
    )?;
    validate_filesystems(snapshot, &actor_ids, &registry_ids)?;
    validate_outputs(snapshot, validated, operations)
}

fn validate_schedule(
    entry: &Value,
    actor_ids: &[String],
    registry_ids: &[String],
    by_operation: &BTreeMap<String, &Value>,
    aliases: &BTreeMap<String, Vec<String>>,
) -> Result<(), String> {
    let operations = list(&entry["operations"])?;
    let root = |root: &Value| {
        known(
            &root["owner"],
            if ["registry", "publisher"].contains(&text(&root["kind"])?) {
                registry_ids
            } else {
                actor_ids
            },
            "root owner",
        )
    };
    let mut states = BTreeMap::<String, OperationState>::new();
    let mut barriers = BTreeMap::<String, Barrier>::new();
    for action in list(&entry["actions"])? {
        if let Some(actor) = action.get("actor") {
            known(actor, actor_ids, "action actor")?;
            if action["kind"] == "restart-client"
                && operations.iter().any(|o| {
                    &o["actor"] == actor
                        && o["id"]
                            .as_str()
                            .is_some_and(|id| states.get(id) == Some(&OperationState::Running))
                })
            {
                return Err("cannot restart a client with a running operation".into());
            }
        }
        if let Some(registry) = action.get("registry") {
            known(registry, registry_ids, "action registry")?;
        }
        if action["kind"] == "filesystem" {
            let change = &action["change"];
            if let Some(value) = change.get("root") {
                root(value)?;
            }
            if let Some(actor) = change.get("actor") {
                known(actor, actor_ids, "mutation actor")?;
            }
        }
        match text(&action["kind"])? {
            "start" => {
                let id = text(&action["operation"])?;
                let operation = by_operation
                    .get(id)
                    .ok_or_else(|| format!("invalid operation start {id}"))?;
                if states.insert(id.into(), OperationState::Running).is_some() {
                    return Err(format!("invalid operation start {id}"));
                }
                for checkpoint in list(&action["barriers"])? {
                    equal(&checkpoint["operation"], &json!(id), "barrier operation")?;
                    let subject = &checkpoint["subject"];
                    if let Some(registry) = subject.get("registry") {
                        alias(registry, &operation["actor"], aliases)?;
                    }
                    let step = text(&checkpoint["step"])?;
                    if [
                        "source-inventory",
                        "source-file-copy",
                        "source-recheck",
                        "staged-verification",
                        "cache-promotion",
                        "bundle-ready",
                    ]
                    .contains(&step)
                        && subject["kind"] != "object"
                    {
                        return Err("bundle checkpoint requires object subject".into());
                    }
                    if [
                        "writer-lock",
                        "predecessor-check",
                        "version-reservation",
                        "bundle-install",
                        "record-install",
                        "statement-install",
                        "targets-install",
                        "snapshot-install",
                        "retained-timestamp-install",
                        "timestamp-replace",
                        "timestamp-directory-flush",
                    ]
                    .contains(&step)
                        && operation["name"] != "publish-library"
                    {
                        return Err("publication checkpoint on nonpublication operation".into());
                    }
                    if step == "writer-lock" && subject["kind"] != "repository" {
                        return Err("writer-lock checkpoint requires repository subject".into());
                    }
                    if barriers
                        .insert(
                            canonical(checkpoint),
                            Barrier {
                                operation: id.into(),
                                state: BarrierState::Declared,
                                fault: false,
                            },
                        )
                        .is_some()
                    {
                        return Err("duplicate checkpoint declaration".into());
                    }
                }
            }
            "join" => {
                let id = text(&action["operation"])?;
                if states.get(id) != Some(&OperationState::Running)
                    || by_operation
                        .get(id)
                        .is_none_or(|o| o["expected"]["kind"] == "terminated")
                    || barriers
                        .values()
                        .any(|b| b.operation == id && b.state != BarrierState::Released)
                {
                    return Err(format!("invalid operation join {id}"));
                }
                states.insert(id.into(), OperationState::Joined);
            }
            kind => {
                if let Some(checkpoint) = action.get("checkpoint") {
                    let key = canonical(checkpoint);
                    let id = text(&checkpoint["operation"])?;
                    if !barriers.contains_key(&key)
                        || states.get(id) != Some(&OperationState::Running)
                    {
                        return Err("unknown or inactive checkpoint".into());
                    }
                    if kind == "await" {
                        if barriers[&key].state != BarrierState::Declared
                            || barriers
                                .values()
                                .any(|b| b.operation == id && b.state == BarrierState::Held)
                        {
                            return Err(
                                "checkpoint cannot be reached twice or while another is held"
                                    .into(),
                            );
                        }
                        barriers.get_mut(&key).expect("known barrier").state = BarrierState::Held;
                    } else {
                        let barrier = barriers.get_mut(&key).expect("known barrier");
                        if barrier.state != BarrierState::Held {
                            return Err("checkpoint action requires held barrier".into());
                        }
                        match kind {
                            "inject-fault" => {
                                if checkpoint["boundary"] != "before" || barrier.fault {
                                    return Err(
                                        "fault must be injected once before the step".into()
                                    );
                                }
                                barrier.fault = true;
                            }
                            "release" => barrier.state = BarrierState::Released,
                            "terminate" => {
                                let termination = &by_operation[id]["expected"];
                                if termination["kind"] != "terminated" {
                                    return Err(
                                        "termination requires terminated expectation".into()
                                    );
                                }
                                equal(
                                    &termination["checkpoint"],
                                    checkpoint,
                                    "termination checkpoint",
                                )?;
                                barrier.state = BarrierState::Terminated;
                                states.insert(id.into(), OperationState::Terminated);
                            }
                            _ => {}
                        }
                    }
                }
            }
        }
    }
    if operations.iter().any(|o| {
        !matches!(
            o["id"].as_str().and_then(|id| states.get(id)),
            Some(OperationState::Joined | OperationState::Terminated)
        )
    }) || barriers
        .values()
        .any(|b| matches!(b.state, BarrierState::Declared | BarrierState::Held))
    {
        return Err("incomplete operation/checkpoint schedule".into());
    }
    Ok(())
}

fn validate_security(
    entry: &Value,
    validated: &Validated,
    snapshot: &Value,
    sorted_actors: &[String],
    aliases: &BTreeMap<String, Vec<String>>,
    policies: &[Value],
) -> Result<(), String> {
    let security = list(&snapshot["security"])?;
    equal(
        &json!(
            security
                .iter()
                .map(|s| s["actor"].clone())
                .collect::<Vec<_>>()
        ),
        &json!(sorted_actors),
        "complete sorted security actors",
    )?;
    for item in security {
        equal(
            &item["observedAt"],
            &entry["observe"]["at"],
            "observation clock",
        )?;
        let policy = policies
            .iter()
            .find(|p| p["actor"] == item["actor"])
            .ok_or("missing observation policy")?;
        if let (Some(observed), Some(expected)) = (
            bytes(&item["policy"], validated)?,
            bytes(&policy["policy"], validated)?,
        ) && observed != expected
        {
            return Err("observation policy bytes mismatch".into());
        }
        if ["lost", "corrupt"].contains(&text(&item["condition"])?)
            && !list(&item["grants"])?.is_empty()
        {
            return Err("lost/corrupt state cannot report grants".into());
        }
        let repositories = list(&item["repositories"])?;
        sorted(
            &repositories
                .iter()
                .map(|r| r["registry"].clone())
                .collect::<Vec<_>>(),
            "security repositories",
        )?;
        for repository in repositories {
            alias(&repository["registry"], &item["actor"], aliases)?;
        }
        for field in ["grants", "revocations"] {
            let values = list(&item[field])?;
            let ordering = values
                .iter()
                .map(|v| {
                    Ok(json!(format!(
                        "{}\0{}\0{}",
                        text(&v["registry"])?,
                        text(&v["release"]["packagePath"])?,
                        text(&v["release"]["version"])?
                    )))
                })
                .collect::<Result<Vec<_>, String>>()?;
            sorted_by(&ordering, field, |a, b| {
                let a = a.split('\0').collect::<Vec<_>>();
                let b = b.split('\0').collect::<Vec<_>>();
                a[0].cmp(b[0]).then_with(|| a[1].cmp(b[1])).then_with(|| {
                    a[2].split('.')
                        .zip(b[2].split('.'))
                        .map(|(a, b)| decimal_cmp(a, b))
                        .find(|o| !o.is_eq())
                        .unwrap_or(Ordering::Equal)
                })
            })?;
            for value in values {
                alias(&value["registry"], &item["actor"], aliases)?;
                if let Some(keys) = value.get("keys") {
                    sorted(list(keys)?, "grant keys")?;
                }
            }
        }
        for grant in list(&item["grants"])? {
            if list(&item["revocations"])?
                .iter()
                .any(|r| r["registry"] == grant["registry"] && r["release"] == grant["release"])
            {
                return Err("revoked release cannot report eligible grant".into());
            }
        }
    }
    Ok(())
}

fn validate_filesystems(
    snapshot: &Value,
    actor_ids: &[String],
    registry_ids: &[String],
) -> Result<(), String> {
    let mut expected_roots = actor_ids
        .iter()
        .flat_map(|owner| {
            [
                json!({"owner":owner,"kind":"cache"}),
                json!({"owner":owner,"kind":"destination"}),
            ]
        })
        .chain(
            registry_ids
                .iter()
                .map(|owner| json!({"owner":owner,"kind":"registry"})),
        )
        .collect::<Vec<_>>();
    expected_roots.sort_by(|a, b| {
        a["owner"]
            .as_str()
            .cmp(&b["owner"].as_str())
            .then_with(|| a["kind"].as_str().cmp(&b["kind"].as_str()))
    });
    let filesystems = list(&snapshot["filesystems"])?;
    equal(
        &json!(
            filesystems
                .iter()
                .map(|f| f["root"].clone())
                .collect::<Vec<_>>()
        ),
        &json!(expected_roots),
        "complete sorted filesystem inventories",
    )?;
    for filesystem in filesystems {
        tree(filesystem)?;
        let entries = list(&filesystem["entries"])?;
        sorted(
            &entries
                .iter()
                .map(|e| e["path"].clone())
                .collect::<Vec<_>>(),
            "observed paths",
        )?;
        if filesystem["root"]["kind"] == "cache" {
            for item in entries {
                let path = text(&item["path"])?;
                let suffix = path.strip_prefix("bundles/");
                let bundle = suffix.map(|s| s.split('/').next().unwrap_or(""));
                let valid = path == "bundles"
                    || suffix.is_some_and(|s| {
                        bundle.is_some_and(is_sha256_hex)
                            && s.split_once('/').is_none_or(|(_, rest)| !rest.is_empty())
                    });
                if !valid || !["file", "directory"].contains(&text(&item["kind"])?) {
                    return Err("invalid cache projection entry".into());
                }
                if path == "bundles" || suffix.is_some_and(is_sha256_hex) {
                    if item["kind"] != "directory" {
                        return Err("cache bundle parent must be a directory".into());
                    }
                    if path != "bundles"
                        && !entries.iter().any(|e| {
                            e["path"] == format!("{path}/manifest.json") && e["kind"] == "file"
                        })
                    {
                        return Err("completed cache bundle requires manifest inventory".into());
                    }
                }
            }
        }
        if filesystem["root"]["kind"] == "destination" && !entries.is_empty() {
            return Err("unrequested destination output".into());
        }
    }
    Ok(())
}

fn validate_outputs(
    snapshot: &Value,
    validated: &Validated,
    operations: &[Value],
) -> Result<(), String> {
    let lock_ids = operations
        .iter()
        .filter_map(|o| o["input"].get("lock"))
        .filter(|lock| lock["kind"] == "asset")
        .map(|lock| text(&lock["asset"]).map(str::to_owned))
        .collect::<Result<BTreeSet<_>, _>>()?;
    equal(
        &json!(
            list(&snapshot["lockBytes"])?
                .iter()
                .map(|lock| lock["asset"].clone())
                .collect::<Vec<_>>()
        ),
        &json!(lock_ids),
        "complete input lock observations",
    )?;
    for lock in list(&snapshot["lockBytes"])? {
        if let Some(bytes) = validated.bytes.get(text(&lock["asset"])?) {
            equal(
                &lock["sha256"],
                &json!(format!("sha256:{}", sha256_hex(bytes))),
                "unchanged input lock digest",
            )?;
        }
    }
    let results = operations
        .iter()
        .map(|o| Ok((o, expected(o, validated)?)))
        .collect::<Result<Vec<_>, String>>()?;
    if results
        .iter()
        .all(|(o, r)| r.is_some() || o["expected"]["kind"] == "terminated")
    {
        let ready = results
            .iter()
            .filter_map(|(o, r)| {
                r.filter(|r| r["kind"] == "graph-ready")
                    .map(|r| json!({"operation":o["id"],"releases":r["verified"]}))
            })
            .collect::<Vec<_>>();
        equal(
            &snapshot["readyGraphs"],
            &json!(ready),
            "ready graph observations",
        )?;
    }
    Ok(())
}
