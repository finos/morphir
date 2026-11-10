//! Runs the fixed `0.1.0-draft.1` conformance cases through the published
//! JSON Schemas and the reference readers.
//!
//! The cases live in `docs/spec/toolchain/fixtures/0.1.0-draft.1/cases.json`.
//! Each names a document, the contract it claims to follow, and either
//! `valid` or the exact diagnostic code and member path a reader reports.

use morphir_toolchain_contract::{
    Code, Operation, PlatformId, canonical_json, canonical_sha256, read_lock, read_receipt,
    read_recipe, read_request, read_result, resolve_closure, understood,
};
use serde_json::Value;
use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

fn repository_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn fixtures() -> PathBuf {
    repository_root().join("docs/spec/toolchain/fixtures/0.1.0-draft.1")
}

fn read(path: &Path) -> Vec<u8> {
    std::fs::read(path).unwrap_or_else(|error| panic!("failed to read {}: {error}", path.display()))
}

fn cases() -> Value {
    serde_json::from_slice(&read(&fixtures().join("cases.json"))).expect("cases.json is JSON")
}

const SCHEMAS: &[(&str, &str)] = &[
    ("recipe", "toolset-recipe-0.1.0-draft.1.schema.json"),
    ("request", "toolchain-request-0.1.0-draft.1.schema.json"),
    ("lock", "toolchain-lock-0.1.0-draft.1.schema.json"),
    ("receipt", "toolchain-receipt-0.1.0-draft.1.schema.json"),
    ("result", "morphirup-result-0.1.0-draft.1.schema.json"),
];

fn schema(contract: &str) -> Value {
    let (_, file) = SCHEMAS
        .iter()
        .find(|(name, _)| *name == contract)
        .unwrap_or_else(|| panic!("no schema for contract {contract}"));
    let path = repository_root().join("website/static/schemas").join(file);
    serde_json::from_slice(&read(&path))
        .unwrap_or_else(|error| panic!("{} is not JSON: {error}", path.display()))
}

/// The JSON instance a schema validates: TOML requests are read as TOML.
fn instance(contract: &str, bytes: &[u8]) -> Option<Value> {
    if contract == "request" {
        let text = std::str::from_utf8(bytes).ok()?;
        let table: toml::Table = toml::from_str(text).ok()?;
        serde_json::to_value(table).ok()
    } else {
        serde_json::from_slice(bytes).ok()
    }
}

fn outcome(contract: &str, bytes: &[u8]) -> Result<(), (Code, String)> {
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

fn expected(case: &Value) -> Result<(), (String, String)> {
    match &case["expected"] {
        Value::String(valid) if valid == "valid" => Ok(()),
        Value::Object(refusal) => Err((
            refusal["code"].as_str().expect("expected code").to_owned(),
            refusal["path"].as_str().expect("expected path").to_owned(),
        )),
        other => panic!("unexpected expectation {other}"),
    }
}

#[test]
fn every_document_case_matches_its_reader_and_schema() {
    let cases = cases();
    assert_eq!(cases["contractVersion"], "0.1.0-draft.1");
    let mut failures = Vec::new();
    for case in cases["documents"].as_array().expect("document cases") {
        let contract = case["contract"].as_str().unwrap();
        let document = case["document"].as_str().unwrap();
        let bytes = read(&fixtures().join(document));
        let actual =
            outcome(contract, &bytes).map_err(|(code, path)| (code.as_str().to_owned(), path));
        let wanted = expected(case);
        if actual != wanted {
            failures.push(format!(
                "{document}: reader gave {actual:?}, expected {wanted:?}"
            ));
        }

        let schema_expectation =
            case["schema"]
                .as_str()
                .unwrap_or(if wanted.is_ok() { "accepts" } else { "rejects" });
        // Where the schema is looser than the reader, the case says why.
        let looser = wanted.is_err() && schema_expectation == "accepts";
        let gap = case["schemaGap"]
            .as_str()
            .is_some_and(|text| !text.trim().is_empty());
        if looser != gap {
            failures.push(format!(
                "{document}: a refusal the schema accepts states a schemaGap, and no other case does"
            ));
        }
        if schema_expectation == "unparsable" {
            assert!(instance(contract, &bytes).is_none(), "{document} parses");
            continue;
        }
        let instance = instance(contract, &bytes)
            .unwrap_or_else(|| panic!("{document} is not a parsable {contract}"));
        let validator = jsonschema::validator_for(&schema(contract)).expect("schema compiles");
        let accepted = validator.is_valid(&instance);
        if accepted != (schema_expectation == "accepts") {
            let errors = validator
                .iter_errors(&instance)
                .map(|error| format!("{} at {}", error, error.instance_path))
                .collect::<Vec<_>>();
            failures.push(format!(
                "{document}: schema {} but the case says it {schema_expectation}; {errors:?}",
                if accepted { "accepted" } else { "rejected" }
            ));
        }
    }
    assert!(
        failures.is_empty(),
        "{} failing cases:\n{}",
        failures.len(),
        failures.join("\n")
    );
}

fn summary(closure: &morphir_toolchain_contract::PlatformClosure) -> Value {
    Value::Array(
        closure
            .providers()
            .iter()
            .map(|provider| {
                let (operation, member, id) = match provider.operation() {
                    Operation::Compile { language } => ("compile", "language", language),
                    Operation::Generate { target } => ("generate", "target", target),
                };
                serde_json::json!({
                    "operation": operation,
                    member: id.as_str(),
                    "delivery": provider.delivery().kind().as_str(),
                    "extensionId": provider.extension_id().as_str(),
                    "version": provider.version().to_string()
                })
            })
            .collect(),
    )
}

#[test]
fn every_binding_case_matches_the_reference_checks() {
    let mut failures = Vec::new();
    for case in cases()["bindings"].as_array().expect("binding cases") {
        let name = case["name"].as_str().unwrap();
        let file = |key: &str| read(&fixtures().join(case[key].as_str().unwrap()));
        let lock = || {
            let bytes = file("lock");
            let lock = read_lock(&bytes).unwrap_or_else(|error| panic!("{name}: {error}"));
            (bytes, lock)
        };
        let actual = match case["kind"].as_str().unwrap() {
            "lock-request" => {
                let request = read_request(&file("request"))
                    .unwrap_or_else(|error| panic!("{name}: {error}"));
                lock().1.check_request(&request)
            }
            "lock-platform" => {
                let platform = PlatformId::parse(case["platform"].as_str().unwrap()).unwrap();
                lock().1.closure(platform).map(drop)
            }
            "receipt-lock" => {
                let receipt = read_receipt(&file("receipt"))
                    .unwrap_or_else(|error| panic!("{name}: {error}"));
                let (bytes, lock) = lock();
                receipt.check_lock(&bytes, &lock)
            }
            "resolve" => {
                let recipe = read_recipe(&file("recipe")).unwrap();
                let request = read_request(&file("request")).unwrap();
                let platform = PlatformId::parse(case["platform"].as_str().unwrap()).unwrap();
                resolve_closure(&recipe, &request, platform).map(|closure| {
                    if summary(&closure) != case["expected"]["providers"] {
                        failures.push(format!("{name}: resolved {}", summary(&closure)));
                    }
                })
            }
            "plan-canonical" => {
                let result: Value = serde_json::from_slice(&file("result")).unwrap();
                let canonical = canonical_json(&result["plan"]).unwrap();
                if canonical != file("canonical") {
                    failures.push(format!("{name}: the canonical plan bytes differ"));
                }
                if canonical_sha256(&result["plan"]).unwrap().to_string() != result["planSha256"] {
                    failures.push(format!(
                        "{name}: planSha256 is not the digest of those bytes"
                    ));
                }
                read_result(&file("result")).map(drop)
            }
            other => panic!("unknown binding kind {other}"),
        }
        .map_err(|diagnostic| (diagnostic.code.as_str().to_owned(), diagnostic.path));
        let wanted = match &case["expected"] {
            Value::Object(object) if object.contains_key("providers") => Ok(()),
            _ => expected(case),
        };
        if actual != wanted {
            failures.push(format!("{name}: gave {actual:?}, expected {wanted:?}"));
        }
    }
    assert!(
        failures.is_empty(),
        "{} failing bindings:\n{}",
        failures.len(),
        failures.join("\n")
    );
}

/// Every stable code has exactly one result diagnostic kind, and every kind
/// reports at least one code, so a result can report any refusal.
#[test]
fn every_stable_code_has_a_result_diagnostic_kind() {
    let kinds = Code::ALL
        .iter()
        .map(|code| code.kind())
        .collect::<std::collections::HashSet<_>>();
    assert_eq!(kinds.len(), 9);
    for code in Code::ALL {
        assert_eq!(Code::parse(code.as_str()), Some(*code));
    }
    // The result schema lists, for each kind, exactly the codes that belong to it.
    let schema = schema("result");
    let rules = schema["$defs"]["diagnostic"]["allOf"].as_array().unwrap();
    let mut listed = 0;
    for rule in rules {
        let Some(kind) = rule["if"]["properties"]["kind"]["const"].as_str() else {
            continue;
        };
        let codes = rule["then"]["properties"]["code"]["enum"]
            .as_array()
            .unwrap()
            .iter()
            .map(|code| code.as_str().unwrap())
            .collect::<BTreeSet<_>>();
        let expected = Code::ALL
            .iter()
            .filter(|code| code.kind().as_str() == kind)
            .map(|code| code.as_str())
            .collect::<BTreeSet<_>>();
        assert_eq!(codes, expected, "{kind}");
        listed += codes.len();
    }
    assert_eq!(listed, Code::ALL.len());
}
#[test]
fn every_fixture_document_is_a_listed_case() {
    let cases = cases();
    let mut listed = BTreeSet::new();
    for case in cases["documents"].as_array().unwrap() {
        listed.insert(case["document"].as_str().unwrap().to_owned());
    }
    for case in cases["bindings"].as_array().unwrap() {
        for key in [
            "lock",
            "request",
            "receipt",
            "recipe",
            "result",
            "canonical",
        ] {
            if let Some(path) = case[key].as_str() {
                listed.insert(path.to_owned());
            }
        }
    }
    let mut unlisted = Vec::new();
    for contract in ["recipe", "request", "lock", "receipt", "result"] {
        let mut pending = vec![fixtures().join(contract)];
        while let Some(directory) = pending.pop() {
            for entry in std::fs::read_dir(&directory).unwrap() {
                let path = entry.unwrap().path();
                if path.is_dir() {
                    pending.push(path);
                    continue;
                }
                let relative = path
                    .strip_prefix(fixtures())
                    .unwrap()
                    .to_string_lossy()
                    .replace('\\', "/");
                if !listed.contains(&relative) {
                    unlisted.push(relative);
                }
            }
        }
    }
    assert!(unlisted.is_empty(), "fixtures without a case: {unlisted:?}");
}

#[test]
fn schemas_list_exactly_the_critical_paths_each_reader_understands() {
    for (contract, paths) in [
        ("recipe", understood::RECIPE),
        ("request", understood::REQUEST),
        ("lock", understood::LOCK),
        ("receipt", understood::RECEIPT),
        ("result", understood::RESULT),
    ] {
        let schema = schema(contract);
        let listed = schema["properties"]["critical"]["items"]["enum"]
            .as_array()
            .unwrap_or_else(|| panic!("{contract} schema lists understood critical paths"))
            .iter()
            .map(|path| path.as_str().unwrap())
            .collect::<BTreeSet<_>>();
        assert_eq!(
            listed,
            paths.iter().copied().collect::<BTreeSet<_>>(),
            "{contract}"
        );
        assert_eq!(
            schema["properties"]["schemaVersion"]["const"], "0.1.0-draft.1",
            "{contract} schema names its exact draft"
        );
    }
}
