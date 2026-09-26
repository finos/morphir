use std::borrow::Cow;
use std::collections::BTreeMap;

use morphir_mck::kit::embedded::embedded_source;
use morphir_mck::kit::snapshot::collect;
use morphir_mck::kit::{Kit, KitSource, load_kit};
use morphir_mck::schema::check;
use serde_json::{Value, json};

fn files() -> BTreeMap<String, Cow<'static, [u8]>> {
    collect(&load_kit(embedded_source()).unwrap())
        .unwrap()
        .files
        .into_iter()
        .map(|(k, v)| (k, Cow::Owned(v)))
        .collect()
}
fn kit(files: BTreeMap<String, Cow<'static, [u8]>>) -> Kit {
    load_kit(KitSource::map("schema fixture", files)).unwrap()
}
fn change_json(
    files: &mut BTreeMap<String, Cow<'static, [u8]>>,
    path: &str,
    edit: impl FnOnce(&mut Value),
) {
    let mut value = serde_json::from_slice(&files[path]).unwrap();
    edit(&mut value);
    files.insert(path.into(), Cow::Owned(serde_json::to_vec(&value).unwrap()));
}
fn single_case(text: &str) -> Kit {
    let mut files = files();
    files.retain(|path, _| !(path.starts_with("spec/ir/mck/") && path.ends_with(".feature")));
    files.insert(
        "spec/ir/mck/types.feature".into(),
        Cow::Owned(text.as_bytes().to_vec()),
    );
    kit(files)
}

#[test]
fn fixed_corpus_preserves_all_schema_gate_outcomes() {
    let report = check(&load_kit(embedded_source()).unwrap()).unwrap();
    assert!(report.is_success(), "{report:?}");
    assert_eq!(report.accepted_fences(), 181);
    assert_eq!(report.rejected_fences(), 13);
    assert_eq!(report.schema_count, 8);
    assert_eq!(report.example_count, 4);
    assert_eq!(report.protocol_count, 10);
}

#[test]
fn canonical_shapes_and_unknown_targets_cannot_silently_pass() {
    let good = single_case(
        "@node:Type\nFeature: Types\n  Scenario: types-0001 Unit\n    Then its canonical JSON spelling is {\"Unit\":{}}\n",
    );
    assert!(check(&good).unwrap().is_success());
    let bad = single_case(
        "@node:Type\nFeature: Types\n  Scenario: types-0001 Unit\n    Then its canonical JSON spelling is {\"Unit\":7}\n",
    );
    let report = check(&bad).unwrap();
    assert!(!report.is_success());
    assert!(report.to_string().contains("types-0001"));
    assert!(report.to_string().contains("spec/ir/mck/types.feature:4"));
    let unknown = single_case(
        "@node:NewNode\nFeature: Types\n  Scenario: types-0001 Unit\n    Then its canonical JSON spelling is {}\n",
    );
    assert!(
        check(&unknown)
            .unwrap_err()
            .to_string()
            .contains("unknown node kind")
    );
}

#[test]
fn invalid_schema_and_missing_catalog_input_fail_before_validation() {
    let mut bad = files();
    change_json(&mut bad, "website/static/schemas/morphir-ir-v4.json", |v| {
        v["type"] = json!(42)
    });
    assert!(check(&kit(bad)).unwrap_err().to_string().contains("schema"));
    let mut missing = files();
    missing.remove("website/static/schemas/morphir-ir-v4.json");
    assert!(
        check(&kit(missing))
            .unwrap_err()
            .to_string()
            .contains("morphir-ir-v4.json")
    );
}

#[test]
fn schemas_cannot_fetch_remote_or_local_references() {
    for reference in [
        "https://example.invalid/remote.json",
        "file:///outside-catalog.json",
    ] {
        let mut input = files();
        change_json(&mut input, "spec/mck/provenance.schema.json", |v| {
            v["$ref"] = json!(reference)
        });
        assert!(
            check(&kit(input))
                .unwrap_err()
                .to_string()
                .contains("outside the offline catalog")
        );
    }
}

#[test]
fn protocol_sequence_and_root_schema_are_both_checked() {
    let mut mismatch = files();
    change_json(&mut mismatch, "spec/ir/mck/protocol.example.json", |v| {
        v[1]["message"]["id"] = json!(999)
    });
    assert!(
        check(&kit(mismatch))
            .unwrap()
            .to_string()
            .contains("does not answer")
    );
    let mut root = files();
    change_json(&mut root, "spec/ir/mck/protocol.schema.json", |v| {
        v["oneOf"]
            .as_array_mut()
            .unwrap()
            .push(json!({"$ref":"#/definitions/Request"}));
    });
    let report = check(&kit(root)).unwrap();
    assert!(!report.is_success());
    assert!(report.to_string().contains("root schema"));
}

#[test]
fn different_large_integer_protocol_ids_do_not_round_to_a_match() {
    let mut input = files();
    change_json(&mut input, "spec/ir/mck/protocol.example.json", |v| {
        v[0]["message"]["id"] = json!(9_007_199_254_740_992_u64);
        v[1]["message"]["id"] = json!(9_007_199_254_740_993_u64);
    });
    assert!(
        check(&kit(input))
            .unwrap()
            .to_string()
            .contains("does not answer")
    );
}

#[test]
fn unsafe_decimal_protocol_ids_cannot_round_into_the_pending_id() {
    let mut input = files();
    let path = "spec/ir/mck/protocol.example.json";
    let text = std::str::from_utf8(&input[path])
        .unwrap()
        .replacen("\"id\": 1", "\"id\": 9007199254740992", 1)
        .replacen("\"id\": 1", "\"id\": 9007199254740993.0", 1);
    input.insert(path.into(), Cow::Owned(text.into_bytes()));
    assert!(
        check(&kit(input))
            .unwrap()
            .to_string()
            .contains("does not answer")
    );
}
