use std::borrow::Cow;
use std::collections::BTreeMap;

use morphir_mck::kit::embedded::embedded_source;
use morphir_mck::kit::snapshot::collect;
use morphir_mck::kit::{KitSource, load_kit};
use morphir_mck::schema;
use serde_json::{Value, json};

const CORPUS: &str = "spec/ir/mck/metadata-contract-draft.json";
const SCHEMA: &str = "spec/ir/mck/metadata-contract-draft.schema.json";
const CLOSURE: &str = "spec/ir/mck/metadata-fixtures/schema-closure.json";
const PUBLISHED_LIFECYCLE: &str =
    "spec/ir/mck/metadata-fixtures/contexts/lifecycle-published.jsonld";

fn files() -> BTreeMap<String, Cow<'static, [u8]>> {
    collect(&load_kit(embedded_source()).unwrap())
        .unwrap()
        .files
        .into_iter()
        .map(|(path, bytes)| (path, Cow::Owned(bytes)))
        .collect()
}

fn changed(
    mut files: BTreeMap<String, Cow<'static, [u8]>>,
    path: &str,
    edit: impl FnOnce(&mut Value),
) -> BTreeMap<String, Cow<'static, [u8]>> {
    let mut value: Value = serde_json::from_slice(&files[path]).unwrap();
    edit(&mut value);
    files.insert(path.into(), Cow::Owned(serde_json::to_vec(&value).unwrap()));
    files
}

fn error(files: BTreeMap<String, Cow<'static, [u8]>>) -> String {
    let kit = load_kit(KitSource::map("metadata admission", files)).unwrap();
    assert!(
        !kit.errors.is_empty(),
        "metadata corruption passed mck check"
    );
    let schema_error = schema::check(&kit).unwrap_err().to_string();
    assert!(schema_error.contains("metadata"));
    kit.errors
        .iter()
        .map(|e| e.message.as_str())
        .collect::<Vec<_>>()
        .join("\n")
}

#[test]
fn embedded_metadata_corpus_is_admitted() {
    let kit = load_kit(embedded_source()).unwrap();
    assert!(kit.errors.is_empty(), "{:?}", kit.errors);
    assert!(schema::check(&kit).unwrap().is_success());
}

#[test]
fn older_corpus_and_schema_without_targets_return_a_kit_error() {
    let old_schema = changed(files(), SCHEMA, |value| {
        value["$defs"]["case"]["required"]
            .as_array_mut()
            .unwrap()
            .retain(|field| field != "targets");
    });
    let old_pair = changed(old_schema, CORPUS, |value| {
        for case in value["cases"].as_array_mut().unwrap() {
            case.as_object_mut().unwrap().remove("targets");
        }
    });
    let message = error(old_pair);
    assert!(message.contains("metadata-0001"), "{message}");
    assert!(message.contains("targets"), "{message}");
}

#[test]
fn looser_schema_cannot_make_malformed_or_unknown_profiles_panic() {
    for profile in [json!(7), json!("toml")] {
        let loose_schema = changed(files(), SCHEMA, |value| {
            value["$defs"]["target"]["properties"]["profile"] = json!({});
        });
        let loose_pair = changed(loose_schema, CORPUS, |value| {
            let case = &mut value["cases"][17];
            case["targets"][2]["profile"] = profile;
            case["targets"][2]["layout"] = json!("single");
            case["targets"][2]
                .as_object_mut()
                .unwrap()
                .remove("ionVersion");
            let ion = case["given"]["fixtures"]
                .as_object_mut()
                .unwrap()
                .remove("ion")
                .unwrap();
            case["given"]["fixtures"]["toml"] = ion;
        });
        let message = error(loose_pair);
        assert!(message.contains("metadata-0018"), "{message}");
        assert!(message.contains("profile"), "{message}");
    }
}

#[test]
fn every_reference_case_has_its_exact_profile_targets() {
    let corpus: Value = serde_json::from_slice(&files()[CORPUS]).unwrap();
    let cases = corpus["cases"].as_array().unwrap();
    assert_eq!(cases.len(), 73);
    for case in cases {
        let id = case["id"].as_str().unwrap();
        let expected = if id == "metadata-0018" {
            json!([
                {"profile":"json","layout":"single","irRevision":"4.1.0"},
                {"profile":"yaml","layout":"single","irRevision":"4.1.0"},
                {"profile":"ion","layout":"record","irRevision":"4.1.0","ionVersion":"0.1.0-draft.2"}
            ])
        } else {
            json!([{"profile":"json","layout":"single","irRevision":"4.1.0"}])
        };
        assert_eq!(case["targets"], expected, "{id}");
    }
}

#[test]
fn profile_equivalence_targets_must_match_named_fixtures() {
    let message = error(changed(files(), CORPUS, |value| {
        let case = &mut value["cases"][17];
        case["targets"].as_array_mut().unwrap().remove(1);
    }));
    assert!(message.contains("metadata-0018"), "{message}");
    assert!(message.contains("fixtures"), "{message}");
}

#[test]
fn profile_equivalence_layouts_must_match_the_reference_fixtures() {
    for (index, layout) in [(0, "tree"), (2, "datagram")] {
        let message = error(changed(files(), CORPUS, |value| {
            value["cases"][17]["targets"][index]["layout"] = json!(layout);
        }));
        assert!(message.contains("metadata-0018"), "{message}");
        assert!(message.contains("layout"), "{message}");
    }
}

#[test]
fn profile_equivalence_fixtures_must_be_confined_existing_files() {
    for path in [
        Value::Null,
        json!("elsewhere/value.yaml"),
        json!("metadata-fixtures/../profiles/value.yaml"),
        json!("metadata-fixtures/profiles/missing.yaml"),
        json!("metadata-fixtures/profiles/value.json"),
    ] {
        let message = error(changed(files(), CORPUS, |value| {
            value["cases"][17]["given"]["fixtures"]["yaml"] = path;
        }));
        assert!(message.contains("metadata-0018"), "{message}");
        assert!(message.contains("fixture"), "{message}");
    }
}

#[test]
fn ordinary_cases_cannot_claim_other_profiles() {
    let message = error(changed(files(), CORPUS, |value| {
        value["cases"][0]["targets"] = json!([
            {"profile":"json","layout":"single","irRevision":"4.1.0"},
            {"profile":"yaml","layout":"single","irRevision":"4.1.0"}
        ]);
    }));
    assert!(message.contains("targets"), "{message}");
}

#[test]
fn targets_require_exact_revisions_and_profile_layouts() {
    let message = error(changed(files(), CORPUS, |value| {
        value["cases"][0]["targets"][0]["irRevision"] = json!("4.0.0");
    }));
    assert!(message.contains("targets"), "{message}");

    let message = error(changed(files(), CORPUS, |value| {
        value["cases"][17]["targets"][2]["ionVersion"] = json!("0.1.0-draft.1");
    }));
    assert!(message.contains("targets"), "{message}");

    let message = error(changed(files(), CORPUS, |value| {
        value["cases"][17]["targets"][2]["layout"] = json!("single");
    }));
    assert!(message.contains("targets"), "{message}");
}

#[test]
fn duplicate_profile_targets_cannot_reuse_one_fixture() {
    let message = error(changed(files(), CORPUS, |value| {
        value["cases"][17]["targets"]
            .as_array_mut()
            .unwrap()
            .push(json!({
                "profile":"json", "layout":"tree", "irRevision":"4.1.0"
            }));
    }));
    assert!(message.contains("metadata-0018"), "{message}");
    assert!(message.contains("fixtures"), "{message}");
}

#[test]
fn corpus_schema_is_enforced_by_both_check_commands() {
    let message = error(changed(files(), CORPUS, |value| {
        value["cases"][0]["id"] = json!("wrong-id");
    }));
    assert!(
        message.contains("metadata-contract-draft.json"),
        "{message}"
    );
    assert!(message.contains("id"), "{message}");
}

#[test]
fn duplicate_metadata_case_ids_are_rejected() {
    let message = error(changed(files(), CORPUS, |value| {
        value["cases"][1]["id"] = value["cases"][0]["id"].clone();
    }));
    assert!(message.contains("duplicate metadata case id"), "{message}");
}

#[test]
fn referenced_schema_closure_must_exist_and_have_declarations() {
    let mut missing = files();
    missing.remove(CLOSURE);
    let message = error(missing);
    assert!(message.contains("schema-closure.json"), "{message}");

    let message = error(changed(files(), CLOSURE, |value| {
        value["predicates"] = json!([]);
    }));
    assert!(message.contains("predicates"), "{message}");
}

#[test]
fn context_content_address_must_match_exact_fixture_bytes() {
    let message = error(changed(files(), CORPUS, |value| {
        let case = value["cases"]
            .as_array_mut()
            .unwrap()
            .iter_mut()
            .find(|case| case["id"] == "metadata-0024")
            .unwrap();
        case["given"]["resource"] = json!(format!("morphir://context/sha256/{}", "0".repeat(64)));
    }));
    assert!(message.contains("metadata-0024"), "{message}");
    assert!(message.contains("digest"), "{message}");
}

#[test]
fn a_declared_metadata_schema_requires_its_corpus() {
    let mut missing = files();
    missing.remove(CORPUS);
    let message = error(missing);
    assert!(
        message.contains("metadata-contract-draft.json"),
        "{message}"
    );
}

#[test]
fn published_context_digest_must_match_fixture_bytes() {
    let mut changed = files();
    changed.insert(
        PUBLISHED_LIFECYCLE.into(),
        Cow::Owned(b"{\"@context\":{}}\n".to_vec()),
    );
    let message = error(changed);
    assert!(message.contains("metadata-0020"), "{message}");
    assert!(message.contains("digest"), "{message}");
}

#[test]
fn closure_predicate_types_must_resolve_to_declared_data_types() {
    let message = error(changed(files(), CLOSURE, |value| {
        value["predicates"][3]["object"]["type"] =
            json!("morphir://ir/pkg/acme/metadata?format=4.0.0#/module/naming/type/missing");
    }));
    assert!(message.contains("undeclared data type"), "{message}");
}

#[test]
fn accepted_expected_facts_must_use_declared_predicates() {
    let message = error(changed(files(), CORPUS, |value| {
        value["cases"][0]["expected"]["facts"][0]["predicate"] =
            json!("morphir://ir/pkg/acme/metadata?format=4.0.0#/module/naming/value/missing");
    }));
    assert!(message.contains("metadata-0001"), "{message}");
    assert!(message.contains("undeclared predicate"), "{message}");
}

#[test]
fn required_interpreters_need_stable_ids() {
    let message = error(changed(files(), CLOSURE, |value| {
        value["predicates"][3]["interpretation"] = json!({"kind":"required"});
    }));
    assert!(message.contains("interpretation"), "{message}");
}

#[test]
fn fact_payload_strings_are_not_fixture_references() {
    let input = changed(files(), CORPUS, |value| {
        value["cases"][1]["given"]["facts"]["aliases"][0] =
            json!("metadata-fixtures/contexts/absent-literal.jsonld");
    });
    let kit = load_kit(KitSource::map("literal fact", input)).unwrap();
    assert!(kit.errors.is_empty(), "{:?}", kit.errors);
}

#[test]
fn accepted_content_addressed_imports_match_resolver_bytes() {
    let message = error(changed(files(), CORPUS, |value| {
        value["cases"][7]["given"]["imports"][1] =
            json!(format!("morphir://context/sha256/{}", "0".repeat(64)));
    }));
    assert!(message.contains("metadata-0008"), "{message}");
    assert!(message.contains("digest"), "{message}");
}

#[test]
fn data_types_need_shapes_and_nested_references() {
    let message = error(changed(files(), CLOSURE, |value| {
        value["dataTypes"][0]
            .as_object_mut()
            .unwrap()
            .remove("shape");
    }));
    assert!(message.contains("shape"), "{message}");

    let message = error(changed(files(), CLOSURE, |value| {
        value["dataTypes"][0]["shape"]["body"]["fields"]["frontend"]["arguments"][0]["type"] =
            json!("morphir://ir/pkg/acme/metadata?format=4.0.0#/module/naming/type/missing");
    }));
    assert!(message.contains("undeclared data type"), "{message}");
}

#[test]
fn closure_declarations_need_the_correct_role() {
    let message = error(changed(files(), CLOSURE, |value| {
        value["predicates"][0]["declarationRole"] = json!("TypeSpecification");
    }));
    assert!(message.contains("declarationRole"), "{message}");
}

#[test]
fn record_data_shapes_must_be_closed() {
    let message = error(changed(files(), CLOSURE, |value| {
        value["dataTypes"][0]["shape"]["body"]["closed"] = json!(false);
    }));
    assert!(message.contains("closed"), "{message}");
}

#[test]
fn string_keyed_dict_encoding_requires_string_keys() {
    let message = error(changed(files(), CLOSURE, |value| {
        value["dataTypes"][0]["shape"]["body"]["fields"]["frontend"]["arguments"][0]["type"] =
            json!("morphir/SDK:basics#int");
    }));
    assert!(message.contains("string-keyed-object"), "{message}");

    let kit = load_kit(KitSource::map("integer dict without encoding", files())).unwrap();
    assert!(kit.errors.is_empty(), "{:?}", kit.errors);
}

#[test]
fn direct_predicate_data_types_must_use_known_sdk_types() {
    let message = error(changed(files(), CLOSURE, |value| {
        value["predicates"][0]["object"]["type"] = json!("morphir/SDK:unknown#unknown");
    }));
    assert!(message.contains("undeclared data type"), "{message}");
}

#[test]
fn predicate_subjects_must_name_supported_node_kinds() {
    let message = error(changed(files(), CLOSURE, |value| {
        value["predicates"][0]["subjects"] = json!(["NotANodeKind"]);
    }));
    assert!(message.contains("subjects"), "{message}");
}

#[test]
fn node_object_targets_must_name_supported_node_kinds() {
    let message = error(changed(files(), CLOSURE, |value| {
        value["predicates"][2]["object"]["targetKind"] = json!("NotANodeKind");
    }));
    assert!(message.contains("targetKind"), "{message}");
}
