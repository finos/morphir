use morphir_mck::package::{Contract, Operation, load_kit};
use serde_json::json;
use std::path::PathBuf;

fn kit(contract: Contract) -> morphir_mck::package::Kit {
    load_kit(
        &PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../spec/package/mck"),
        contract,
    )
}

#[test]
fn integrity_response_fields_are_closed_and_operation_specific() {
    let kit = kit(Contract::Integrity);
    assert!(
        kit.project_response(Operation::Validate, &json!({"ok":true,"valid":true}))
            .is_ok()
    );
    for value in [
        json!({"ok":true,"valid":true,"extra":1}),
        json!({"ok":false,"error":"invalid-document"}),
        json!({"ok":true,"valid":1}),
    ] {
        assert!(kit.project_response(Operation::Validate, &value).is_err());
    }
    assert!(
        kit.project_response(
            Operation::Normalize,
            &json!({"ok":false,"error":"invalid-document"})
        )
        .is_ok()
    );
    assert!(
        kit.project_response(
            Operation::HashBytes,
            &json!({"ok":true,"digest":"sha256:bad"})
        )
        .is_err()
    );
}

#[test]
fn resolution_projection_ignores_collection_order_but_checks_full_results() {
    let kit = kit(Contract::Resolution);
    let expected = kit
        .cases
        .iter()
        .map(|case| case.expected())
        .find(|value| {
            value["graph"]["nodes"]
                .as_array()
                .is_some_and(|nodes| nodes.len() > 1)
        })
        .unwrap();
    let mut reordered = expected.clone();
    reordered["graph"]["nodes"]
        .as_array_mut()
        .unwrap()
        .reverse();
    for node in reordered["graph"]["nodes"].as_array_mut().unwrap() {
        node["bindings"].as_array_mut().unwrap().reverse();
    }
    assert_eq!(
        kit.project_response(Operation::ResolveLibrary, expected)
            .unwrap(),
        kit.project_response(Operation::ResolveLibrary, &reordered)
            .unwrap()
    );
    let mut changed = expected.clone();
    changed["graph"]["nodes"][0]["manifestDigest"] = json!(format!("sha256:{}", "f".repeat(64)));
    assert_ne!(
        kit.project_response(Operation::ResolveLibrary, expected)
            .unwrap(),
        kit.project_response(Operation::ResolveLibrary, &changed)
            .unwrap()
    );
}

#[test]
fn graph_semantics_reject_duplicate_missing_dangling_cyclic_and_unreachable_nodes() {
    let kit = kit(Contract::Resolution);
    let expected = kit
        .cases
        .iter()
        .map(|case| case.expected())
        .find(|value| {
            value["graph"]["nodes"]
                .as_array()
                .is_some_and(|nodes| nodes.len() > 1)
        })
        .unwrap();
    let mut duplicate = expected.clone();
    let node = duplicate["graph"]["nodes"][0].clone();
    duplicate["graph"]["nodes"]
        .as_array_mut()
        .unwrap()
        .push(node);
    assert!(
        kit.project_response(Operation::ResolveLibrary, &duplicate)
            .is_err()
    );
    let mut missing = expected.clone();
    missing["graph"]["root"]["version"] = json!("999.0.0");
    assert!(
        kit.project_response(Operation::ResolveLibrary, &missing)
            .is_err()
    );
    let mut unreachable = expected.clone();
    for node in unreachable["graph"]["nodes"].as_array_mut().unwrap() {
        node["bindings"] = json!([]);
    }
    assert!(
        kit.project_response(Operation::ResolveLibrary, &unreachable)
            .is_err()
    );
    let mut cyclic = expected.clone();
    let root = cyclic["graph"]["root"].clone();
    let root_node = cyclic["graph"]["nodes"]
        .as_array()
        .unwrap()
        .iter()
        .find(|node| node["release"] == root)
        .unwrap();
    let binding = json!({"irPackageName":root_node["irPackageName"],"target":root});
    for node in cyclic["graph"]["nodes"].as_array_mut().unwrap() {
        if node["release"] == root {
            node["bindings"]
                .as_array_mut()
                .unwrap()
                .push(binding.clone());
        }
    }
    assert!(
        kit.project_response(Operation::ResolveLibrary, &cyclic)
            .is_err()
    );
}

#[test]
fn resolution_witness_invariants_are_checked_before_comparison() {
    let kit = kit(Contract::Resolution);
    let expected = kit
        .cases
        .iter()
        .map(|case| case.expected())
        .find(|value| {
            value["diagnostic"]["witness"]["nodes"]
                .as_array()
                .is_some_and(|nodes| nodes.len() > 1)
        })
        .unwrap();
    let mut duplicate = expected.clone();
    let node = duplicate["diagnostic"]["witness"]["nodes"][0].clone();
    duplicate["diagnostic"]["witness"]["nodes"]
        .as_array_mut()
        .unwrap()
        .push(node);
    assert!(
        kit.project_response(Operation::ResolveLibrary, &duplicate)
            .is_err()
    );
    let mut no_root = expected.clone();
    no_root["diagnostic"]["witness"]["nodes"]
        .as_array_mut()
        .unwrap()
        .retain(|node| node["occurrence"] != json!([]));
    assert!(
        kit.project_response(Operation::ResolveLibrary, &no_root)
            .is_err()
    );
    let mut unbound = expected.clone();
    for node in unbound["diagnostic"]["witness"]["nodes"]
        .as_array_mut()
        .unwrap()
    {
        node["bindings"] = json!([]);
    }
    assert!(
        kit.project_response(Operation::ResolveLibrary, &unbound)
            .is_err()
    );
    let mut reordered = expected.clone();
    reordered["diagnostic"]["witness"]["nodes"]
        .as_array_mut()
        .unwrap()
        .reverse();
    assert_eq!(
        kit.project_response(Operation::ResolveLibrary, expected)
            .unwrap(),
        kit.project_response(Operation::ResolveLibrary, &reordered)
            .unwrap()
    );
}

#[test]
fn nested_unknown_fields_and_unknown_resolution_diagnostics_are_rejected() {
    let kit = kit(Contract::Resolution);
    for value in [
        json!({"ok":false,"diagnostic":{"code":"unexpected","violations":[]}}),
        json!({"ok":false,"diagnostic":{"code":"invalid-input","violations":[]}}),
        json!({"ok":false,"diagnostic":{"code":"invalid-input","violations":[{"pointer":"","rule":"malformed-json","unknown":true}]}}),
    ] {
        assert!(
            kit.project_response(Operation::ResolveLibrary, &value)
                .is_err()
        );
    }
}
