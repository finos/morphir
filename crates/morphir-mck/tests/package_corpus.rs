use morphir_mck::package::{Contract, load_kit};
use std::path::PathBuf;

fn corpus() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../spec/package/mck")
}

#[test]
fn frozen_integrity_and_resolution_corpora_load_without_an_implementation() {
    for (contract, count) in [(Contract::Integrity, 80), (Contract::Resolution, 78)] {
        let kit = load_kit(&corpus(), contract);
        assert!(kit.errors.is_empty(), "{:?}", kit.errors);
        assert_eq!(kit.cases.len(), count);
        assert_eq!(kit.contract, contract);
        assert_eq!(
            kit.content_hash.as_str(),
            match contract {
                Contract::Integrity =>
                    "sha256-72b6593c99af919076e59208b833771394d659838e28ee4c23554ee7f5590e23",
                Contract::Resolution =>
                    "sha256-8dfed22a389bd08e945b35213586b0709f2cf11f5426199bcec746007443b08b",
            }
        );
    }
}

#[test]
fn unsupported_contracts_are_rejected() {
    assert_eq!(
        "0.1.0-draft.1".parse::<Contract>().unwrap(),
        Contract::Integrity
    );
    assert_eq!(
        "0.1.0-draft.2".parse::<Contract>().unwrap(),
        Contract::Resolution
    );
    assert!("0.1.0-draft.3".parse::<Contract>().is_err());
}

fn copy_tree(source: &std::path::Path, target: &std::path::Path) {
    std::fs::create_dir_all(target).unwrap();
    for entry in std::fs::read_dir(source).unwrap() {
        let entry = entry.unwrap();
        if entry.file_type().unwrap().is_dir() {
            copy_tree(&entry.path(), &target.join(entry.file_name()));
        } else {
            std::fs::copy(entry.path(), target.join(entry.file_name())).unwrap();
        }
    }
}

fn changed_kit(
    contract: Contract,
    file: &str,
    change: impl FnOnce(String) -> String,
) -> morphir_mck::package::Kit {
    let temp = tempfile::tempdir().unwrap();
    copy_tree(corpus().parent().unwrap(), temp.path());
    let path = temp.path().join(file);
    std::fs::write(&path, change(std::fs::read_to_string(&path).unwrap())).unwrap();
    load_kit(&temp.path().join("mck"), contract)
}

#[test]
fn duplicate_keys_and_unknown_corpus_fields_are_kit_errors() {
    for addition in ["\"formatVersion\":\"0.1.0-draft.1\",", "\"unknown\":true,"] {
        let kit = changed_kit(Contract::Integrity, "mck/digest-vectors.json", |text| {
            text.replacen('{', &format!("{{{addition}"), 1)
        });
        assert!(!kit.errors.is_empty());
        assert!(kit.cases.is_empty());
    }
}

#[test]
fn resolution_fixture_paths_and_expected_results_are_validated() {
    let kit = changed_kit(Contract::Resolution, "mck/resolution-cases.json", |text| {
        text.replace("fixtures/resolution/basic.json", "../outside.json")
    });
    assert!(!kit.errors.is_empty());
    let kit = changed_kit(
        Contract::Resolution,
        "mck/fixtures/resolution/basic.json",
        |text| {
            let mut value: serde_json::Value = serde_json::from_str(&text).unwrap();
            value["cases"][0]["expected"]["graph"]["nodes"] = serde_json::json!([]);
            value.to_string()
        },
    );
    assert!(!kit.errors.is_empty());
}

#[test]
fn unresolved_schema_references_are_rejected_offline() {
    let kit = changed_kit(
        Contract::Integrity,
        "schemas/library-manifest.schema.json",
        |_| {
            r#"{"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"https://example.invalid/test","$ref":"https://example.invalid/missing"}"#.into()
        },
    );
    assert!(!kit.errors.is_empty());
}

#[test]
fn renamed_corpus_directory_is_resolved_from_the_supplied_location() {
    let temp = tempfile::tempdir().unwrap();
    copy_tree(corpus().parent().unwrap(), temp.path());
    std::fs::rename(temp.path().join("mck"), temp.path().join("cases")).unwrap();
    let kit = load_kit(&temp.path().join("cases"), Contract::Resolution);
    assert!(kit.errors.is_empty(), "{:?}", kit.errors);
    assert_eq!(kit.cases.len(), 78);
}

#[test]
fn invalid_utf8_bom_empty_collections_and_duplicate_case_ids_fail_loading() {
    for transform in [
        |text: String| format!("\u{feff}{text}"),
        |text: String| {
            let mut value: serde_json::Value = serde_json::from_str(&text).unwrap();
            value["cases"] = serde_json::json!([]);
            value.to_string()
        },
        |text: String| {
            let mut value: serde_json::Value = serde_json::from_str(&text).unwrap();
            value["cases"][1]["id"] = value["cases"][0]["id"].clone();
            value.to_string()
        },
    ] {
        let kit = changed_kit(Contract::Integrity, "mck/digest-vectors.json", transform);
        assert!(!kit.errors.is_empty());
        assert!(kit.cases.is_empty());
    }
    let temp = tempfile::tempdir().unwrap();
    copy_tree(corpus().parent().unwrap(), temp.path());
    std::fs::write(temp.path().join("mck/digest-vectors.json"), [0xff]).unwrap();
    assert!(
        !load_kit(&temp.path().join("mck"), Contract::Integrity)
            .errors
            .is_empty()
    );
}

#[test]
fn malformed_expectations_mutations_and_fixture_references_fail_loading() {
    for (file, field, replacement) in [
        (
            "mck/digest-vectors.json",
            "manifestDigest",
            serde_json::json!("sha256:bad"),
        ),
        (
            "mck/schema-cases.json",
            "schema",
            serde_json::json!("unknown"),
        ),
        (
            "mck/schema-cases.json",
            "fixture",
            serde_json::json!("unknown"),
        ),
        (
            "mck/schema-cases.json",
            "replace",
            serde_json::json!({"path":[],"value":0}),
        ),
        (
            "mck/schema-cases.json",
            "remove",
            serde_json::json!(["missing"]),
        ),
        (
            "mck/library-cases.json",
            "expected",
            serde_json::json!("maybe"),
        ),
    ] {
        let kit = changed_kit(Contract::Integrity, file, |text| {
            let mut value: serde_json::Value = serde_json::from_str(&text).unwrap();
            value["cases"][0][field] = replacement;
            value.to_string()
        });
        assert!(!kit.errors.is_empty(), "{file} {field}");
        assert!(kit.cases.is_empty());
    }
}

#[cfg(unix)]
#[test]
fn corpus_files_cannot_escape_through_symlinks() {
    for contract in [Contract::Integrity, Contract::Resolution] {
        let temp = tempfile::tempdir().unwrap();
        copy_tree(corpus().parent().unwrap(), temp.path());
        let outside = tempfile::tempdir().unwrap();
        let target = match contract {
            Contract::Integrity => "mck/fixtures/two-libraries/eligibility/manifest.json",
            Contract::Resolution => "mck/fixtures/resolution/basic.json",
        };
        std::fs::copy(
            temp.path().join(target),
            outside.path().join("outside.json"),
        )
        .unwrap();
        std::fs::remove_file(temp.path().join(target)).unwrap();
        std::os::unix::fs::symlink(
            outside.path().join("outside.json"),
            temp.path().join(target),
        )
        .unwrap();
        let kit = load_kit(&temp.path().join("mck"), contract);
        assert!(
            kit.errors
                .iter()
                .any(|error| error.contains("not confined")),
            "{:?}",
            kit.errors
        );
    }
}

fn canonical(value: &serde_json::Value) -> String {
    match value {
        serde_json::Value::Array(values) => format!(
            "[{}]",
            values.iter().map(canonical).collect::<Vec<_>>().join(",")
        ),
        serde_json::Value::Object(object) => {
            let mut entries: Vec<_> = object.iter().collect();
            entries.sort_by(|(a, _), (b, _)| a.encode_utf16().cmp(b.encode_utf16()));
            format!(
                "{{{}}}",
                entries
                    .into_iter()
                    .map(|(key, value)| format!(
                        "{}:{}",
                        serde_json::to_string(key).unwrap(),
                        canonical(value)
                    ))
                    .collect::<Vec<_>>()
                    .join(",")
            )
        }
        _ => value.to_string(),
    }
}

#[test]
fn every_request_and_projected_expectation_matches_the_pinned_typescript_loader() {
    let frozen: serde_json::Value = serde_json::from_str(include_str!(
        "../../../spec/mck/baseline/package-cases.json"
    ))
    .unwrap();
    for baseline in frozen["contracts"].as_array().unwrap() {
        let contract = baseline["contractVersion"]
            .as_str()
            .unwrap()
            .parse()
            .unwrap();
        let kit = load_kit(&corpus(), contract);
        assert!(kit.errors.is_empty(), "{:?}", kit.errors);
        assert_eq!(kit.content_hash.as_str(), baseline["contentHash"]);
        assert_eq!(kit.cases.len(), baseline["cases"].as_array().unwrap().len());
        let hash = |value: &serde_json::Value| {
            format!(
                "sha256-{}",
                morphir_mck::kit::hash::sha256_hex(canonical(value).as_bytes())
            )
        };
        for (case, expected) in kit.cases.iter().zip(baseline["cases"].as_array().unwrap()) {
            assert_eq!(case.id, expected["id"]);
            assert_eq!(
                hash(&serde_json::to_value(&case.request).unwrap()),
                expected["requestHash"],
                "{} request",
                case.id
            );
            let projected = kit
                .project_response(case.request.operation(), case.expected())
                .unwrap();
            assert_eq!(
                hash(&projected),
                expected["expectedHash"],
                "{} expectation",
                case.id
            );
        }
    }
}
