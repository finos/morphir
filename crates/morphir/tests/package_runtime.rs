//! Fixed parent fixtures exercise runtime helpers without becoming MCK expectations.
use std::path::{Path, PathBuf};

use base64::{Engine, engine::general_purpose::STANDARD};
use morphir_package::local_registry::assurance::{
    parse_restore_assurance_receipt, parse_restore_assurance_request, with_restore_assurance,
};
use morphir_package::local_registry::{
    ObjectSubject, Subject, decode_library_lock, decode_registry_record, decode_release_statement,
    decode_trust_policy, prepare_publisher_envelope, verify_publisher_signatures,
};
use morphir_package::resolution::{PackagePath, ReleaseId};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};

fn source() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn read_json(path: &Path) -> Value {
    serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap()
}

fn digest(bytes: &[u8]) -> String {
    let hex = Sha256::digest(bytes)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>();
    format!("sha256:{hex}")
}

fn target(fixture: &Path, logical: &str, digest: &str) -> PathBuf {
    let (directory, leaf) = logical.rsplit_once('/').unwrap();
    fixture
        .join("registry/targets")
        .join(directory)
        .join(format!(
            "{}.{leaf}",
            digest.strip_prefix("sha256:").unwrap()
        ))
}

fn assert_lock_rejection(bytes: &[u8], expected: &Value, id: &str) {
    let diagnostic = decode_library_lock(bytes).expect_err(id);
    assert_eq!(
        json!({"ok": false, "diagnostic": diagnostic}),
        *expected,
        "{id}"
    );
}

#[test]
fn decode_lock_matches_all_four_frozen_raw_probes() {
    let wire =
        read_json(&source().join("spec/package/mck/fixtures/local-registry/cases/wire.json"));
    let cases = wire["cases"].as_array().unwrap();
    let probes = cases.iter().filter(|case| case["kind"] == "parse");
    let mut count = 0;
    for case in probes {
        assert_eq!(case["target"], "lock");
        assert_eq!(case["input"]["kind"], "hex");
        assert_eq!(case["expected"]["kind"], "inline");
        let hex = case["input"]["value"].as_str().unwrap();
        assert!(hex.is_ascii() && hex.len().is_multiple_of(2));
        let bytes = (0..hex.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap())
            .collect::<Vec<_>>();
        assert_lock_rejection(
            &bytes,
            &case["expected"]["result"],
            case["id"].as_str().unwrap(),
        );
        count += 1;
    }
    assert_eq!(count, 4);
}

#[test]
fn decode_lock_matches_six_frozen_signed_lock_mutations() {
    let corpus = source().join("spec/package/mck/fixtures/local-registry");
    let wire = read_json(&corpus.join("cases/wire.json"));
    let lock = read_json(&corpus.join("assets/signed/morphir.lock"));
    assert_eq!(lock["acquisitions"].as_array().unwrap().len(), 2);
    // Apply only the mutations specified by the frozen parent cases. Their
    // scenario assets remain pending: this checks decoding, not execution.
    for mutation in [
        "duplicate-acquisition",
        "missing-acquisition",
        "unsupported-source",
        "absolute-path",
        "unknown-capability",
        "missing-evidence-reference",
    ] {
        let mut input = lock.clone();
        match mutation {
            "duplicate-acquisition" => {
                let duplicate = input["acquisitions"][0].clone();
                input["acquisitions"]
                    .as_array_mut()
                    .unwrap()
                    .push(duplicate);
            }
            "missing-acquisition" => {
                input["acquisitions"].as_array_mut().unwrap().remove(0);
            }
            "unsupported-source" => input["acquisitions"][0]["source"]["kind"] = json!("archive"),
            "absolute-path" => {
                input["acquisitions"][0]["source"]["path"] = json!("/tmp/eligibility");
            }
            "unknown-capability" => input["resolution"]["requiredCapabilities"]
                .as_array_mut()
                .unwrap()
                .push(json!("future-signatures")),
            "missing-evidence-reference" => {
                input["acquisitions"][0]["statement"] = json!("absent-statement");
            }
            _ => unreachable!(),
        }
        let id = format!("local-registry.wire.{mutation}");
        let case = wire["cases"]
            .as_array()
            .unwrap()
            .iter()
            .find(|case| case["id"] == id)
            .unwrap();
        let operations = case["operations"].as_array().unwrap();
        assert_eq!(operations.len(), 1, "{id}");
        assert_eq!(operations[0]["expected"]["kind"], "inline", "{id}");
        assert_lock_rejection(
            &serde_json::to_vec(&input).unwrap(),
            &operations[0]["expected"]["result"],
            &id,
        );
    }
}

#[test]
fn publisher_preserves_both_keys_exact_bytes_and_requested_release_binding() {
    let source = source();
    let fixture = source.join("spec/package/mck/fixtures/local-registry/assets/signed");
    let description = read_json(&fixture.join("fixture-description.json"));
    let mut expected_keys = description["publicKeys"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|key| matches!(key["label"].as_str(), Some("publisher-a" | "publisher-b")))
        .map(|key| key["publicKey"].as_str().unwrap().to_owned())
        .collect::<Vec<_>>();
    expected_keys.sort();
    assert_eq!(expected_keys.len(), 2);
    let lock = decode_library_lock(&std::fs::read(fixture.join("morphir.lock")).unwrap()).unwrap();
    let policy =
        decode_trust_policy(&std::fs::read(fixture.join("trust-policy.json")).unwrap()).unwrap();
    assert_eq!(lock.acquisitions().len(), 2);
    for acquisition in lock.acquisitions() {
        let evidence = lock
            .evidence()
            .iter()
            .find(|entry| entry.id() == acquisition.statement())
            .unwrap();
        let reference = evidence.reference();
        let envelope = std::fs::read(target(
            &fixture,
            reference.path().as_str(),
            reference.digest().as_str(),
        ))
        .unwrap();
        assert_eq!(digest(&envelope), reference.digest().as_str());
        let subject = ObjectSubject {
            registry: acquisition.registry().clone(),
            path: reference.path().clone(),
        };
        let prepared = prepare_publisher_envelope(&envelope, &subject).unwrap();
        let verified =
            verify_publisher_signatures(&prepared, acquisition.release(), &policy).unwrap();
        assert_eq!(
            verified
                .verified_keys()
                .iter()
                .map(|key| key.as_str())
                .collect::<Vec<_>>(),
            expected_keys
        );
        assert_eq!(verified.publisher_rule().threshold(), 1);
        assert_eq!(verified.envelope_bytes(), envelope);
        let envelope_json: Value = serde_json::from_slice(&envelope).unwrap();
        let expected_payload = STANDARD
            .decode(envelope_json["payload"].as_str().unwrap())
            .unwrap();
        assert_eq!(verified.payload_bytes(), expected_payload);
        let name = acquisition
            .release()
            .package_path()
            .as_str()
            .rsplit('/')
            .next()
            .unwrap();
        let unsigned_path = format!(
            "spec/package/mck/fixtures/local-registry/unsigned/{name}-statement-payload.json"
        );
        let unsigned = std::fs::read(source.join(&unsigned_path)).unwrap();
        assert_eq!(
            json!(digest(&unsigned)),
            description["inputDigests"][&unsigned_path]
        );
        assert_eq!(
            serde_json::from_slice::<Value>(&expected_payload).unwrap(),
            serde_json::from_slice::<Value>(&unsigned).unwrap()
        );
        let statement =
            decode_release_statement(verified.payload_bytes(), &Subject::from(&subject)).unwrap();
        assert_eq!(statement.release(), acquisition.release());
        let requested_a = ReleaseId::new(
            PackagePath::parse("example.com/finance/requested-a").unwrap(),
            acquisition.release().version().clone(),
        );
        let for_a = verify_publisher_signatures(&prepared, &requested_a, &policy).unwrap();
        assert_eq!(for_a.requested_release(), &requested_a);
        assert_ne!(for_a.requested_release(), statement.release());
        assert_eq!(for_a.payload_bytes(), expected_payload);
        let mut noncanonical = expected_payload.clone();
        noncanonical.push(b' ');
        assert!(decode_release_statement(&noncanonical, &Subject::from(&subject)).is_err());
        let record_ref = acquisition.record();
        let record_bytes = std::fs::read(target(
            &fixture,
            record_ref.path().as_str(),
            record_ref.digest().as_str(),
        ))
        .unwrap();
        assert_eq!(digest(&record_bytes), record_ref.digest().as_str());
        let record_subject = Subject::Object {
            registry: acquisition.registry().clone(),
            path: record_ref.path().clone(),
        };
        let record = decode_registry_record(&record_bytes, &record_subject).unwrap();
        assert_eq!(record.release_record().release(), acquisition.release());
    }
}

#[test]
fn assurance_matches_all_fixed_parent_vectors() {
    let source = source().join("spec/package");
    let vectors = read_json(&source.join("mck/restore-assurance-preflight-vectors.json"));
    let request_schema = jsonschema::validator_for(&read_json(
        &source.join("schemas/package-restore-assurance-protocol.schema.json"),
    ))
    .unwrap();
    let receipt_schema = jsonschema::validator_for(&read_json(
        &source.join("schemas/package-restore-assurance-report.schema.json"),
    ))
    .unwrap();
    assert_eq!(vectors["profile"], "restore-filesystem-assurance");
    assert_eq!(vectors["profileVersion"], "0.1.0-draft.1");
    let cases = vectors["cases"].as_array().unwrap();
    assert_eq!(cases.len(), 6);
    let mut ids = std::collections::BTreeSet::new();
    for case in cases {
        assert!(ids.insert(case["id"].as_str().unwrap()));
        let request = json!({"selection":case["selection"],"provider":case["provider"]});
        assert!(request_schema.is_valid(&request), "{}", case["id"]);
        assert_eq!(
            serde_json::to_value(parse_restore_assurance_request(&request).unwrap()).unwrap(),
            request
        );
        let expected = &case["expected"]["receipt"];
        assert!(receipt_schema.is_valid(expected));
        assert_eq!(
            serde_json::to_value(parse_restore_assurance_receipt(expected).unwrap()).unwrap(),
            *expected
        );
        let mut accesses = 0;
        let result = with_restore_assurance(&case["selection"], &case["provider"], |_| {
            accesses += 1;
            Ok::<_, ()>(())
        })
        .unwrap();
        let receipt = serde_json::to_value(result.receipt()).unwrap();
        assert!(receipt_schema.is_valid(&receipt));
        assert_eq!(receipt, *expected, "{}", case["id"]);
        assert_eq!(
            json!(accesses),
            case["expected"]["accesses"],
            "{}",
            case["id"]
        );
    }
}

fn malformed_values(value: &Value) -> Vec<Value> {
    let mut variants = vec![Value::Null];
    match value {
        Value::Object(fields) => {
            let mut extra = value.clone();
            extra["extra"] = json!(true);
            variants.push(extra);
            for (key, child) in fields {
                let mut missing = value.clone();
                missing.as_object_mut().unwrap().remove(key);
                variants.push(missing);
                for mutation in malformed_values(child) {
                    let mut copy = value.clone();
                    copy[key] = mutation;
                    variants.push(copy);
                }
            }
        }
        Value::Array(items) => {
            variants.extend([json!({}), json!([])]);
            for (i, child) in items.iter().enumerate() {
                for mutation in malformed_values(child) {
                    let mut copy = value.clone();
                    copy[i] = mutation;
                    variants.push(copy);
                }
            }
        }
        Value::String(_) => {
            variants.extend([json!(""), json!(1), json!(true), json!([]), json!({})])
        }
        _ => {}
    }
    variants
}

#[test]
fn assurance_schemas_and_parsers_reject_malformed_fixed_vectors() {
    let source = source().join("spec/package");
    let vectors = read_json(&source.join("mck/restore-assurance-preflight-vectors.json"));
    let request_schema = jsonschema::validator_for(&read_json(
        &source.join("schemas/package-restore-assurance-protocol.schema.json"),
    ))
    .unwrap();
    let receipt_schema = jsonschema::validator_for(&read_json(
        &source.join("schemas/package-restore-assurance-report.schema.json"),
    ))
    .unwrap();
    for case in vectors["cases"].as_array().unwrap() {
        let request = json!({"selection":case["selection"], "provider":case["provider"]});
        for malformed in malformed_values(&request) {
            assert!(
                !request_schema.is_valid(&malformed),
                "schema accepts {malformed}"
            );
            assert!(
                parse_restore_assurance_request(&malformed).is_err(),
                "parser accepts {malformed}"
            );
        }
        for malformed in malformed_values(&case["expected"]["receipt"]) {
            assert!(
                !receipt_schema.is_valid(&malformed),
                "schema accepts {malformed}"
            );
            assert!(
                parse_restore_assurance_receipt(&malformed).is_err(),
                "parser accepts {malformed}"
            );
        }
    }
}
