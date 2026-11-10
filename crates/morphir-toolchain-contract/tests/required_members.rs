//! The schema and the reader agree on which members are required.
//!
//! For every valid document case, each object member is removed in turn, at
//! every depth. A member whose absence the reader refuses as a missing
//! member (`invalid_document` at that member) must also be required by the
//! schema, and a member the schema requires must be refused by the reader.
//! Other refusals of a removal, such as a consistency rule the schema does
//! not express, are not part of this check.

use morphir_toolchain_contract::{
    Code, canonical_sha256, read_lock, read_receipt, read_recipe, read_request, read_result,
};
use serde_json::Value;
use std::path::PathBuf;

/// The members a valid fixture may omit, by contract, in critical-path
/// spelling. `platforms.*` entries are map entries of a lock or recipe that
/// lists several platforms. `futureSection`, `host.mirrorHint` and
/// `plan.keyOrder` are unknown members some fixtures carry on purpose.
const OPTIONAL: &[&str] = &[
    "lock: critical",
    "lock: platforms.*",
    "recipe: critical",
    "recipe: hosts.builtIns",
    "recipe: hosts.platforms.*",
    "recipe: hosts.prerequisites",
    "recipe: hosts.prerequisites.platforms",
    "recipe: hosts.prerequisites.versions",
    "recipe: hosts.wasmAbis",
    "recipe: providers.platforms.*",
    "recipe: providers.prerequisites",
    "recipe: providers.prerequisites.platforms",
    "recipe: providers.prerequisites.versions",
    "request: critical",
    "request: futureSection",
    "request: futureSection.enabled",
    "request: host.mirrorHint",
    "request: platforms",
    "request: toolset.providers",
    "request: toolset.providers.abi",
    "request: toolset.providers.delivery",
    "request: toolset.providers.extensionId",
    "result: diagnostics.alternatives",
    "result: diagnostics.cause",
    "result: diagnostics.alternatives.deployment",
    "result: diagnostics.alternatives.implementation",
    "result: diagnostics.alternatives.platform",
    "result: diagnostics.instruction",
    "result: diagnostics.mirror",
    "result: diagnostics.role",
    "result: plan.components.prerequisites.versions",
    "result: plan.keyOrder",
    "result: plan.keyOrder.Z",
    "result: plan.keyOrder.a",
    "result: plan.keyOrder.a!",
    // The decomposed `e` followed by U+0301.
    "result: plan.keyOrder.e\u{301}",
    "result: plan.keyOrder.ｶ",
    "result: plan.keyOrder.𝄞",
    "result: selection",
    "result: selection.lockSha256",
];

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn fixtures() -> PathBuf {
    root().join("docs/spec/toolchain/fixtures/0.1.0-draft.1")
}

fn schema(contract: &str) -> Value {
    let file = match contract {
        "recipe" => "toolset-recipe-0.1.0-draft.1.schema.json",
        "request" => "toolchain-request-0.1.0-draft.1.schema.json",
        "lock" => "toolchain-lock-0.1.0-draft.1.schema.json",
        "receipt" => "toolchain-receipt-0.1.0-draft.1.schema.json",
        "result" => "morphirup-result-0.1.0-draft.1.schema.json",
        other => panic!("no schema for {other}"),
    };
    serde_json::from_slice(
        &std::fs::read(root().join("website/static/schemas").join(file)).unwrap(),
    )
    .unwrap()
}

fn instance(contract: &str, bytes: &[u8]) -> Value {
    if contract == "request" {
        let table: toml::Table = toml::from_str(std::str::from_utf8(bytes).unwrap()).unwrap();
        serde_json::to_value(table).unwrap()
    } else {
        serde_json::from_slice(bytes).unwrap()
    }
}

fn encode(contract: &str, value: &Value) -> Vec<u8> {
    if contract == "request" {
        toml::to_string(value).unwrap().into_bytes()
    } else {
        serde_json::to_vec(value).unwrap()
    }
}

fn read(contract: &str, bytes: &[u8]) -> Result<(), (Code, String)> {
    let refusal =
        |diagnostic: morphir_toolchain_contract::Diagnostic| (diagnostic.code, diagnostic.path);
    match contract {
        "recipe" => read_recipe(bytes).map(drop).map_err(refusal),
        "request" => read_request(bytes).map(drop).map_err(refusal),
        "lock" => read_lock(bytes).map(drop).map_err(refusal),
        "receipt" => read_receipt(bytes).map(drop).map_err(refusal),
        "result" => read_result(bytes).map(drop).map_err(refusal),
        other => panic!("unknown contract {other}"),
    }
}

/// Every object member's path, as a list of steps from the root.
fn member_paths(value: &Value, prefix: &mut Vec<Step>, out: &mut Vec<Vec<Step>>) {
    match value {
        Value::Object(map) => {
            for (key, item) in map {
                prefix.push(Step::Key(key.clone()));
                out.push(prefix.clone());
                member_paths(item, prefix, out);
                prefix.pop();
            }
        }
        Value::Array(items) => {
            for (position, item) in items.iter().enumerate() {
                prefix.push(Step::Index(position));
                member_paths(item, prefix, out);
                prefix.pop();
            }
        }
        _ => {}
    }
}

#[derive(Clone)]
enum Step {
    Key(String),
    Index(usize),
}

/// The reader's spelling of a member path.
fn spelled(steps: &[Step]) -> String {
    let mut path = String::new();
    for step in steps {
        match step {
            Step::Key(key) if path.is_empty() => path.push_str(key),
            Step::Key(key) => {
                path.push('.');
                path.push_str(key);
            }
            Step::Index(position) => path.push_str(&format!("[{position}]")),
        }
    }
    path
}

/// The critical-path spelling of a member: array elements are named through
/// their array, and platform keys by `*`.
fn generic(steps: &[Step]) -> String {
    let mut names: Vec<String> = Vec::new();
    for step in steps {
        if let Step::Key(key) = step {
            let keyed = names.last().is_some_and(|last| last == "platforms")
                && morphir_toolchain_contract::PlatformId::parse(key).is_ok();
            names.push(if keyed { "*".to_owned() } else { key.clone() });
        }
    }
    names.join(".")
}

fn without(value: &Value, steps: &[Step]) -> Value {
    let mut copy = value.clone();
    let (last, parents) = steps.split_last().unwrap();
    let mut node = &mut copy;
    for step in parents {
        node = match step {
            Step::Key(key) => &mut node[key.as_str()],
            Step::Index(position) => &mut node[*position],
        };
    }
    let Step::Key(key) = last else {
        unreachable!("only object members are removed")
    };
    node.as_object_mut().unwrap().remove(key);
    copy
}

#[test]
fn schema_and_reader_require_the_same_members() {
    let cases: Value =
        serde_json::from_slice(&std::fs::read(fixtures().join("cases.json")).unwrap()).unwrap();
    let mut failures = Vec::new();
    let mut checked = 0;
    let mut optional = std::collections::BTreeSet::new();
    for case in cases["documents"].as_array().unwrap() {
        if case["expected"] != "valid" {
            continue;
        }
        let contract = case["contract"].as_str().unwrap();
        let document = case["document"].as_str().unwrap();
        let validator = jsonschema::validator_for(&schema(contract)).unwrap();
        let original = instance(contract, &std::fs::read(fixtures().join(document)).unwrap());
        let mut paths = Vec::new();
        member_paths(&original, &mut Vec::new(), &mut paths);
        for steps in paths {
            // `plan.lock` is a complete lock document: the lock schema and
            // reader govern its members, and the lock fixtures sweep them.
            if generic(&steps).starts_with("plan.lock") {
                continue;
            }
            let mut changed = without(&original, &steps);
            // A plan member's removal changes the plan's digest; recompute
            // it so that only the removal is judged.
            if matches!(steps.first(), Some(Step::Key(key)) if key == "plan")
                && let Ok(digest) = canonical_sha256(&changed["plan"])
            {
                changed["planSha256"] = Value::String(digest.to_string());
            }
            let path = spelled(&steps);
            let missing = matches!(
                read(contract, &encode(contract, &changed)),
                Err((Code::InvalidDocument, at)) if at == path
            );
            let required_by_schema = !validator.is_valid(&changed);
            checked += 1;
            if missing && !required_by_schema {
                failures.push(format!(
                    "{document}: the reader requires {path}, the schema does not"
                ));
            }
            let accepted = read(contract, &encode(contract, &changed)).is_ok();
            if required_by_schema && accepted {
                failures.push(format!(
                    "{document}: the schema requires {path}, the reader does not"
                ));
            }
            if accepted && !required_by_schema {
                optional.insert(format!("{contract}: {}", generic(&steps)));
            }
        }
    }
    assert!(checked > 1000, "{checked} removals were checked");
    // Both validators let a document omit exactly these members, and each
    // page says so. A member that becomes optional, or stops being optional,
    // changes this list and its page together.
    let expected = OPTIONAL
        .iter()
        .map(|entry| (*entry).to_owned())
        .collect::<std::collections::BTreeSet<_>>();
    if optional != expected {
        failures.push(format!(
            "optional members changed; now optional: {:?}; no longer optional: {:?}",
            optional.difference(&expected).collect::<Vec<_>>(),
            expected.difference(&optional).collect::<Vec<_>>()
        ));
    }
    failures.sort();
    failures.dedup();
    assert!(
        failures.is_empty(),
        "{} disagreements:\n{}",
        failures.len(),
        failures.join("\n")
    );
}
