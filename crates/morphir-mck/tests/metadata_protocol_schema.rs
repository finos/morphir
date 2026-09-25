use jsonschema::validator_for;
use serde_json::{Value, json};

fn schema() -> Value {
    serde_json::from_str(include_str!(
        "../../../spec/ir/mck/metadata-protocol-draft.schema.json"
    ))
    .unwrap()
}

fn capability() -> Value {
    json!({
        "id": 1,
        "suite": "metadata",
        "contractVersion": "0.1.0-draft.1",
        "implementation": "test-binding",
        "implementationVersion": "0.1.0",
        "claims": [{
            "operation": "normalize",
            "profile": "json",
            "layout": "single",
            "irRevision": "4.0.0"
        }]
    })
}

fn run_request() -> Value {
    json!({
        "id": 2,
        "op": "run",
        "caseId": "metadata-0001",
        "operation": "normalize",
        "targets": [{"profile": "json", "layout": "single", "irRevision": "4.0.0"}],
        "given": {"carrier": "attributesFacts", "facts": {"deprecated": true}},
        "schemaClosure": "metadata-fixtures/schema-closure.json",
        "fixtures": [{
            "path": "metadata-fixtures/schema-closure.json",
            "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
            "contentBase64": "e30K"
        }]
    })
}

#[test]
fn draft_schema_accepts_each_closed_exchange_shape() {
    let validator = validator_for(&schema()).unwrap();
    let messages = [
        json!({"id": 1, "op": "capabilities"}),
        capability(),
        run_request(),
        json!({"id": 2, "ok": true, "observation": {"outcome": "accepted", "facts": []}}),
        json!({"id": 3, "ok": false, "error": {"code": "invalid_request", "message": "bad input"}}),
        json!({"id": 4, "op": "exit"}),
    ];
    for message in messages {
        assert!(validator.is_valid(&message), "rejected {message}");
    }
}

#[test]
fn draft_schema_rejects_broad_or_ambiguous_claims() {
    let validator = validator_for(&schema()).unwrap();
    let mut invalid = capability();
    invalid["contractVersion"] = json!(1);
    assert!(!validator.is_valid(&invalid));
    let mut invalid = capability();
    invalid["claims"][0]["irRevision"] = json!("4");
    assert!(!validator.is_valid(&invalid));
    let mut invalid = capability();
    invalid["claims"][0]["irRevision"] = json!("4.1.0-draft.1");
    assert!(!validator.is_valid(&invalid));
    let mut invalid = capability();
    invalid["claims"][0]["irRevision"] = json!("04.1.0");
    assert!(!validator.is_valid(&invalid));
    let mut invalid = capability();
    invalid["claims"][0]["irRevision"] = json!("2.0.0");
    assert!(!validator.is_valid(&invalid));
    let mut invalid = run_request();
    invalid["targets"][0]["irRevision"] = json!("2.0.0");
    assert!(!validator.is_valid(&invalid));
    let mut invalid = capability();
    invalid["claims"][0]["profile"] = json!("toml");
    assert!(!validator.is_valid(&invalid));
    let mut invalid = capability();
    invalid["claims"][0]["layout"] = json!("datagram");
    assert!(!validator.is_valid(&invalid));
    let mut invalid = capability();
    invalid["claims"][0]["profile"] = json!("ion");
    invalid["claims"][0]["layout"] = json!("single");
    assert!(!validator.is_valid(&invalid));
    let mut invalid = capability();
    invalid["claims"][0]["ionVersion"] = json!("0.1.0-draft.99");
    assert!(!validator.is_valid(&invalid));
    let mut invalid = capability();
    invalid["claims"][0]["profile"] = json!("ion");
    invalid["claims"][0]["layout"] = json!("datagram");
    assert!(!validator.is_valid(&invalid));
    let mut invalid = capability();
    invalid["claims"][0]["unexpected"] = json!(true);
    assert!(!validator.is_valid(&invalid));
}

#[test]
fn draft_schema_requires_explicit_fixture_bytes_and_closed_observations() {
    let validator = validator_for(&schema()).unwrap();
    let mut invalid = run_request();
    invalid["fixtures"][0]
        .as_object_mut()
        .unwrap()
        .remove("contentBase64");
    assert!(!validator.is_valid(&invalid));
    let mut invalid = run_request();
    invalid["given"] = json!("metadata-fixtures/schema-closure.json");
    assert!(!validator.is_valid(&invalid));
    let mut invalid = run_request();
    invalid["targets"][0]["layout"] = json!("unknown");
    assert!(!validator.is_valid(&invalid));
    let invalid =
        json!({"id": 2, "ok": true, "observation": {"outcome": "accepted", "invented": true}});
    assert!(!validator.is_valid(&invalid));
}

#[test]
fn profile_equivalence_requires_multiple_explicit_targets() {
    let validator = validator_for(&schema()).unwrap();
    let mut request = run_request();
    request["operation"] = json!("profileEquivalence");
    assert!(!validator.is_valid(&request));
    request["targets"] = json!([
        {"profile": "json", "layout": "single", "irRevision": "4.0.0"},
        {"profile": "yaml", "layout": "single", "irRevision": "4.0.0"},
        {"profile": "ion", "layout": "datagram", "irRevision": "4.0.0", "ionVersion": "0.1.0-draft.99"}
    ]);
    assert!(validator.is_valid(&request));
}

#[test]
fn ion_claim_needs_an_exact_ion_version_and_own_layout() {
    let validator = validator_for(&schema()).unwrap();
    for layout in ["datagram", "record", "tree"] {
        let mut response = capability();
        response["claims"][0]["profile"] = json!("ion");
        response["claims"][0]["layout"] = json!(layout);
        response["claims"][0]["ionVersion"] = json!("0.1.0-draft.99");
        assert!(validator.is_valid(&response), "rejected {layout}");
    }
}

#[test]
fn numeric_v1_capabilities_are_distinct_from_metadata_capabilities() {
    let metadata_validator = validator_for(&schema()).unwrap();
    let v1_schema: Value =
        serde_json::from_str(include_str!("../../../spec/ir/mck/protocol.schema.json")).unwrap();
    let v1_validator = validator_for(&v1_schema).unwrap();
    let examples: Value =
        serde_json::from_str(include_str!("../../../spec/ir/mck/protocol.example.json")).unwrap();
    let reply = examples
        .as_array()
        .unwrap()
        .iter()
        .find(|entry| entry["message"]["contractVersion"] == 1)
        .unwrap()["message"]
        .clone();
    assert!(v1_validator.is_valid(&reply));
    assert!(!metadata_validator.is_valid(&reply));
}

#[test]
fn oversized_ir_component_requires_semantic_rejection_after_schema_validation() {
    let validator = validator_for(&schema()).unwrap();
    let mut claim = capability();
    claim["claims"][0]["irRevision"] = json!("4.4294967296.0");
    assert!(validator.is_valid(&claim));

    let version = semver::Version::parse("4.4294967296.0").unwrap();
    assert!(u32::try_from(version.minor).is_err());
    let boundary = semver::Version::parse("4.4294967295.0").unwrap();
    assert!(u32::try_from(boundary.minor).is_ok());
}

#[test]
fn every_reference_expectation_is_a_valid_observation() {
    let validator = validator_for(&schema()).unwrap();
    let corpus: Value = serde_json::from_str(include_str!(
        "../../../spec/ir/mck/metadata-contract-draft.json"
    ))
    .unwrap();
    for case in corpus["cases"].as_array().unwrap() {
        let message = json!({"id": 1, "ok": true, "observation": case["expected"]});
        assert!(validator.is_valid(&message), "{}: {message}", case["id"]);
    }
}
