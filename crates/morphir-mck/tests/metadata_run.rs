use morphir_mck::kit::{KitSource, embedded::embedded_source, load_kit};
use morphir_mck::metadata::run::{MetadataTestee, run_kit};
use regex::Regex;
use serde_json::{Map, Value, json};

struct Replying {
    replies: Vec<Value>,
    requests: Vec<Value>,
}

impl MetadataTestee for Replying {
    fn exchange(&mut self, request: &Value) -> Result<Map<String, Value>, String> {
        self.requests.push(request.clone());
        Ok(self.replies.remove(0).as_object().unwrap().clone())
    }
}

fn kit() -> morphir_mck::kit::Kit {
    load_kit(embedded_source()).unwrap()
}

fn caps(claims: Value) -> Value {
    json!({"suite":"metadata","contractVersion":"0.1.0-draft.1","implementation":"fixture","implementationVersion":"1.0.0","claims":claims})
}

#[test]
fn unclaimed_cases_skip_without_run_requests() {
    let mut adapter = Replying {
        replies: vec![caps(json!([]))],
        requests: vec![],
    };
    let run = run_kit(
        &kit(),
        &mut adapter,
        Some(&Regex::new("^metadata-0001$").unwrap()),
    );
    assert_eq!(adapter.requests.len(), 1);
    assert_eq!(run.records.len(), 1);
    assert_eq!(run.records[0].result, "skipped");
    assert!(run.failure.is_none());
}

#[test]
fn complete_tuple_claim_runs_and_matches_literal_observation() {
    let corpus: Value = serde_json::from_str(include_str!(
        "../../../spec/ir/mck/metadata-contract-draft.json"
    ))
    .unwrap();
    let case = &corpus["cases"][0];
    assert_eq!(case["id"], "metadata-0001");
    let mut adapter = Replying {
        replies: vec![
            caps(
                json!([{"operation":case["operation"],"profile":"json","layout":"single","irRevision":"4.1.0"}]),
            ),
            json!({"ok":true,"observation":case["expected"]}),
        ],
        requests: vec![],
    };
    let run = run_kit(
        &kit(),
        &mut adapter,
        Some(&Regex::new("^metadata-0001$").unwrap()),
    );
    assert_eq!(adapter.requests.len(), 2);
    assert_eq!(adapter.requests[1]["given"], case["given"]);
    assert_eq!(run.records[0].result, "pass", "{:?}", run.records);
}

fn report_for(
    run: &morphir_mck::metadata::run::MetadataRun,
) -> morphir_mck::metadata::report::MetadataReport {
    use morphir_mck::kit::manifest::LockSource;
    use morphir_mck::kit::snapshot::collect;
    let kit = kit();
    let digest = collect(&kit)
        .unwrap()
        .lock(LockSource::Local { revision: None })
        .snapshot_digest;
    morphir_mck::metadata::report::assemble(
        run,
        json!({
            "version":"test","source":"embedded","revision":null,"snapshotDigest":digest.as_str(),
            "corpusHash":null,"modified":false
        }),
        vec!["fixture-adapter".into()],
        Some("^metadata-0001$"),
        false,
        "2026-09-25T00:00:00Z",
        (None, None),
    )
    .unwrap()
}

#[test]
fn all_skipped_metadata_report_fails_independent_qualification() {
    let mut adapter = Replying {
        replies: vec![caps(json!([]))],
        requests: vec![],
    };
    let run = run_kit(
        &kit(),
        &mut adapter,
        Some(&Regex::new("^metadata-0001$").unwrap()),
    );
    let report = report_for(&run);
    let allowed = morphir_mck::report::check::AllowedFailures::from_json("{\"cases\":[]}").unwrap();
    let error =
        morphir_mck::metadata::report::check(&report, &kit(), &allowed, Some("^metadata-0001$"))
            .unwrap_err();
    assert!(error.contains("no passing"), "{error}");
}

#[test]
fn malformed_capabilities_are_failure_not_skip() {
    let mut adapter = Replying {
        replies: vec![json!({"error":"unsupported operation"})],
        requests: vec![],
    };
    let run = run_kit(
        &kit(),
        &mut adapter,
        Some(&Regex::new("^metadata-0001$").unwrap()),
    );
    assert_eq!(run.records[0].result, "kit-error");
    assert!(run.failure.is_some());
}

#[test]
fn valid_v1_capabilities_skip_without_metadata_run() {
    let old = json!({"contractVersion":1,"binding":"old","language":"rust",
        "formatVersions":"[4.0.0,4.1.0)","versions":[4],"profiles":["json"],
        "layouts":["single"],"paths":["current","pinned"],"nodes":["Type"]});
    let mut adapter = Replying {
        replies: vec![old],
        requests: vec![],
    };
    let run = run_kit(
        &kit(),
        &mut adapter,
        Some(&Regex::new("^metadata-0001$").unwrap()),
    );
    assert!(run.failure.is_none(), "{:?}", run.failure);
    assert_eq!(run.records[0].result, "skipped");
    assert_eq!(adapter.requests.len(), 1);
}

#[test]
fn numerically_integral_v1_capabilities_skip_without_run_requests() {
    let filter = Regex::new("^metadata-0001$").unwrap();
    for spelling in ["1.0", "1e0"] {
        let reply: Value = serde_json::from_str(&format!(
            r#"{{"contractVersion":{spelling},"binding":"old","language":"rust","formatVersions":"[4.0.0,4.1.0)","versions":[4],"profiles":["json"],"layouts":["single"],"paths":["current","pinned"],"nodes":["Type"]}}"#
        ))
        .unwrap();
        assert!(morphir_mck::transport::protocol::parse_capabilities(&reply).is_ok());
        let mut adapter = Replying {
            replies: vec![reply],
            requests: vec![],
        };
        let run = run_kit(&kit(), &mut adapter, Some(&filter));
        assert!(run.failure.is_none(), "{spelling}: {:?}", run.failure);
        assert_eq!(run.records[0].result, "skipped");
        assert_eq!(adapter.requests.len(), 1);
    }
}

#[test]
fn wrong_response_variant_is_an_exchange_failure() {
    let mut adapter = Replying {
        replies: vec![
            caps(
                json!([{"operation":"normalize","profile":"json","layout":"single","irRevision":"4.1.0"}]),
            ),
            json!({"op":"exit"}),
        ],
        requests: vec![],
    };
    let run = run_kit(
        &kit(),
        &mut adapter,
        Some(&Regex::new("^metadata-0001$").unwrap()),
    );
    assert_eq!(adapter.requests.len(), 2);
    assert_eq!(run.records[0].result, "kit-error");
    assert!(run.failure.as_deref().unwrap().contains("run response"));
}

#[test]
fn malformed_corpus_is_a_kit_failure_without_adapter_exchange() {
    let KitSource::Map { label, mut files } = embedded_source() else {
        panic!("embedded kit is a map")
    };
    files.insert(
        "spec/ir/mck/metadata-contract-draft.json".into(),
        std::borrow::Cow::Owned(b"{\"status\":\"reference\"}".to_vec()),
    );
    let malformed = load_kit(KitSource::map(label, files)).unwrap();
    assert!(!malformed.errors.is_empty());
    let mut adapter = Replying {
        replies: vec![],
        requests: vec![],
    };
    let run = run_kit(&malformed, &mut adapter, None);
    assert!(run.failure.is_some());
    assert!(adapter.requests.is_empty());
}

#[test]
fn fact_object_member_order_does_not_change_observation() {
    fn reversed_object_keys(value: &Value) -> Value {
        match value {
            Value::Object(map) => Value::Object(
                map.iter()
                    .rev()
                    .map(|(key, item)| (key.clone(), reversed_object_keys(item)))
                    .collect(),
            ),
            Value::Array(items) => Value::Array(items.iter().map(reversed_object_keys).collect()),
            _ => value.clone(),
        }
    }
    let corpus: Value = serde_json::from_str(include_str!(
        "../../../spec/ir/mck/metadata-contract-draft.json"
    ))
    .unwrap();
    let case = corpus["cases"]
        .as_array()
        .unwrap()
        .iter()
        .find(|case| case["id"] == "metadata-0004")
        .unwrap();
    assert!(
        case["expected"]["facts"][0]["object"]["@value"]
            .as_object()
            .unwrap()
            .len()
            > 1
    );
    let observed = reversed_object_keys(&case["expected"]);
    let mut adapter = Replying {
        replies: vec![
            caps(
                json!([{"operation":"normalize","profile":"json","layout":"single","irRevision":"4.1.0"}]),
            ),
            json!({"ok":true,"observation":observed}),
        ],
        requests: vec![],
    };
    let run = run_kit(
        &kit(),
        &mut adapter,
        Some(&Regex::new("^metadata-0004$").unwrap()),
    );
    assert_eq!(run.records[0].result, "pass", "{:?}", run.records);
}

#[test]
fn json_array_order_inside_a_fact_remains_significant() {
    let corpus: Value = serde_json::from_str(include_str!(
        "../../../spec/ir/mck/metadata-contract-draft.json"
    ))
    .unwrap();
    let case = corpus["cases"]
        .as_array()
        .unwrap()
        .iter()
        .find(|case| case["id"] == "metadata-0050")
        .unwrap();
    let mut observed = case["expected"].clone();
    observed["facts"][0]["object"]["@value"]
        .as_array_mut()
        .unwrap()
        .reverse();
    let mut adapter = Replying {
        replies: vec![
            caps(
                json!([{"operation":"normalize","profile":"json","layout":"single","irRevision":"4.1.0"}]),
            ),
            json!({"ok":true,"observation":observed}),
        ],
        requests: vec![],
    };
    let run = run_kit(
        &kit(),
        &mut adapter,
        Some(&Regex::new("^metadata-0050$").unwrap()),
    );
    assert_eq!(run.records[0].result, "fail", "{:?}", run.records);
    assert!(run.failure.is_none());
}

#[test]
fn incomplete_tuple_does_not_claim_case() {
    let mut adapter = Replying {
        replies: vec![caps(
            json!([{"operation":"normalize","profile":"yaml","layout":"single","irRevision":"4.1.0"}]),
        )],
        requests: vec![],
    };
    let run = run_kit(
        &kit(),
        &mut adapter,
        Some(&Regex::new("^metadata-0001$").unwrap()),
    );
    assert_eq!(run.records[0].result, "skipped");
    assert_eq!(adapter.requests.len(), 1);
}

#[test]
fn recursive_local_context_imports_are_sent_as_exact_fixture_bytes() {
    let corpus: Value = serde_json::from_str(include_str!(
        "../../../spec/ir/mck/metadata-contract-draft.json"
    ))
    .unwrap();
    let case = corpus["cases"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["id"] == "metadata-0033")
        .unwrap();
    let mut adapter = Replying {
        replies: vec![
            caps(
                json!([{"operation":"resolveContext","profile":"json","layout":"single","irRevision":"4.1.0"}]),
            ),
            json!({"ok":true,"observation":case["expected"]}),
        ],
        requests: vec![],
    };
    let run = run_kit(
        &kit(),
        &mut adapter,
        Some(&Regex::new("^metadata-0033$").unwrap()),
    );
    assert_eq!(run.records[0].result, "pass", "{:?}", run.records);
    let paths = adapter.requests[1]["fixtures"]
        .as_array()
        .unwrap()
        .iter()
        .map(|f| f["path"].as_str().unwrap())
        .collect::<Vec<_>>();
    assert_eq!(
        paths,
        vec![
            "metadata-fixtures/contexts/lifecycle.jsonld",
            "metadata-fixtures/contexts/nested/recursive-leaf.jsonld",
            "metadata-fixtures/contexts/recursive-root.jsonld",
            "metadata-fixtures/schema-closure.json",
        ]
    );
}

#[test]
fn fact_order_is_set_valued_but_duplicate_observation_fails() {
    let corpus: Value = serde_json::from_str(include_str!(
        "../../../spec/ir/mck/metadata-contract-draft.json"
    ))
    .unwrap();
    let case = corpus["cases"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["id"] == "metadata-0002")
        .unwrap();
    let claim =
        json!([{"operation":"normalize","profile":"json","layout":"single","irRevision":"4.1.0"}]);
    let mut reversed = case["expected"].clone();
    reversed["facts"].as_array_mut().unwrap().reverse();
    let mut adapter = Replying {
        replies: vec![
            caps(claim.clone()),
            json!({"ok":true,"observation":reversed}),
        ],
        requests: vec![],
    };
    let run = run_kit(
        &kit(),
        &mut adapter,
        Some(&Regex::new("^metadata-0002$").unwrap()),
    );
    assert_eq!(run.records[0].result, "pass");

    let mut repeated = case["expected"].clone();
    repeated["facts"][1] = repeated["facts"][0].clone();
    let mut adapter = Replying {
        replies: vec![caps(claim), json!({"ok":true,"observation":repeated})],
        requests: vec![],
    };
    let run = run_kit(
        &kit(),
        &mut adapter,
        Some(&Regex::new("^metadata-0002$").unwrap()),
    );
    assert_eq!(run.records[0].result, "fail");
    assert!(
        run.records[0]
            .message
            .as_deref()
            .unwrap()
            .contains("duplicate")
    );
}

#[test]
fn claimed_unsupported_operation_is_an_exchange_failure() {
    let mut adapter = Replying {
        replies: vec![
            caps(
                json!([{"operation":"normalize","profile":"json","layout":"single","irRevision":"4.1.0"}]),
            ),
            json!({"ok":false,"error":{"code":"unsupported_operation","message":"no handler"}}),
        ],
        requests: vec![],
    };
    let run = run_kit(
        &kit(),
        &mut adapter,
        Some(&Regex::new("^metadata-0001$").unwrap()),
    );
    assert_eq!(run.records[0].result, "kit-error");
    assert!(run.failure.unwrap().contains("unsupported_operation"));
}

#[test]
fn passing_metadata_report_checks_against_independent_inventory() {
    let corpus: Value = serde_json::from_str(include_str!(
        "../../../spec/ir/mck/metadata-contract-draft.json"
    ))
    .unwrap();
    let case = &corpus["cases"][0];
    let mut adapter = Replying {
        replies: vec![
            caps(
                json!([{"operation":"normalize","profile":"json","layout":"single","irRevision":"4.1.0"}]),
            ),
            json!({"ok":true,"observation":case["expected"]}),
        ],
        requests: vec![],
    };
    let run = run_kit(
        &kit(),
        &mut adapter,
        Some(&Regex::new("^metadata-0001$").unwrap()),
    );
    let report = report_for(&run);
    let allowed = morphir_mck::report::check::AllowedFailures::from_json("{\"cases\":[]}").unwrap();
    let checked =
        morphir_mck::metadata::report::check(&report, &kit(), &allowed, Some("^metadata-0001$"))
            .unwrap();
    assert_eq!(checked.records, 1);
    let mut forged = report.value().clone();
    forged["records"][0]["result"] = json!("skipped");
    forged["records"][0]["message"] = json!("unsupported metadata target tuple");
    let forged = morphir_mck::metadata::report::MetadataReport::from_value(forged).unwrap();
    assert!(
        morphir_mck::metadata::report::check(&forged, &kit(), &allowed, Some("^metadata-0001$"))
            .is_err()
    );
    let unknown =
        morphir_mck::report::check::AllowedFailures::from_json("{\"cases\":[\"metadata-9999\"]}")
            .unwrap();
    assert!(
        morphir_mck::metadata::report::check(&report, &kit(), &unknown, Some("^metadata-0001$"))
            .is_err()
    );
}

#[test]
fn profile_equivalence_requires_every_target_tuple() {
    let corpus: Value = serde_json::from_str(include_str!(
        "../../../spec/ir/mck/metadata-contract-draft.json"
    ))
    .unwrap();
    let case = corpus["cases"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["id"] == "metadata-0018")
        .unwrap();
    let targets = case["targets"].as_array().unwrap();
    let to_claim = |target: &Value| {
        let mut claim = target.clone();
        claim["operation"] = json!("profileEquivalence");
        claim
    };
    let claims = targets.iter().map(to_claim).collect::<Vec<_>>();
    let mut adapter = Replying {
        replies: vec![caps(json!([claims[0]]))],
        requests: vec![],
    };
    let run = run_kit(
        &kit(),
        &mut adapter,
        Some(&Regex::new("^metadata-0018$").unwrap()),
    );
    assert_eq!(run.records[0].result, "skipped");
    assert_eq!(adapter.requests.len(), 1);

    let mut adapter = Replying {
        replies: vec![
            caps(json!(claims)),
            json!({"ok":true,"observation":case["expected"]}),
        ],
        requests: vec![],
    };
    let run = run_kit(
        &kit(),
        &mut adapter,
        Some(&Regex::new("^metadata-0018$").unwrap()),
    );
    assert_eq!(run.records[0].result, "pass", "{:?}", run.records);
    assert_eq!(adapter.requests[1]["targets"], case["targets"]);
    assert_eq!(adapter.requests[1]["fixtures"].as_array().unwrap().len(), 4);
}

#[test]
fn malformed_v1_reply_and_noncanonical_metadata_versions_fail_negotiation() {
    let malformed_v1 = json!({"contractVersion":1,"binding":"old"});
    let excessive_ir = json!([{"operation":"normalize","profile":"json","layout":"single","irRevision":"4.4294967296.0"}]);
    let noncanonical_ion = json!([{"operation":"normalize","profile":"ion","layout":"record","irRevision":"4.1.0","ionVersion":"01.0.0-draft.2"}]);
    let filter = Regex::new("^metadata-0001$").unwrap();
    for reply in [malformed_v1, caps(excessive_ir), caps(noncanonical_ion)] {
        let mut adapter = Replying {
            replies: vec![reply],
            requests: vec![],
        };
        let run = run_kit(&kit(), &mut adapter, Some(&filter));
        assert!(run.failure.is_some());
        assert_eq!(run.records[0].result, "kit-error");
    }
}

#[test]
fn metadata_report_rejects_negotiation_session_disagreement() {
    let mut adapter = Replying {
        replies: vec![caps(json!([]))],
        requests: vec![],
    };
    let run = run_kit(
        &kit(),
        &mut adapter,
        Some(&Regex::new("^metadata-0001$").unwrap()),
    );
    let mut value = report_for(&run).value().clone();
    value["adapter"]["negotiation"] = json!({"status":"failed","message":"bad handshake"});
    assert!(morphir_mck::metadata::report::MetadataReport::from_value(value).is_err());
}

#[test]
fn fixture_bytes_are_frozen_before_adapter_exchange() {
    use morphir_mck::kit::KitSource;
    let source = embedded_source();
    let work = tempfile::tempdir().unwrap();
    let snapshot = morphir_mck::kit::snapshot::collect(&load_kit(source.clone()).unwrap()).unwrap();
    for (path, bytes) in snapshot.files {
        let destination = work.path().join(&path);
        std::fs::create_dir_all(destination.parent().unwrap()).unwrap();
        std::fs::write(destination, bytes).unwrap();
    }
    let kit = load_kit(KitSource::directory(
        &work.path().join("spec/ir/mck"),
        Some(work.path()),
    ))
    .unwrap();
    assert!(kit.errors.is_empty(), "{:?}", kit.errors);
    let expected = source
        .read("spec/ir/mck/metadata-fixtures/schema-closure.json")
        .unwrap()
        .unwrap();
    let digest = morphir_mck::kit::hash::sha256_hex(&expected);
    struct Changing {
        path: std::path::PathBuf,
        replies: Vec<Value>,
        request: Option<Value>,
    }
    impl MetadataTestee for Changing {
        fn exchange(&mut self, request: &Value) -> Result<Map<String, Value>, String> {
            if request["op"] == "capabilities" {
                std::fs::write(&self.path, "{}\n").unwrap();
            } else {
                self.request = Some(request.clone());
            }
            Ok(self.replies.remove(0).as_object().unwrap().clone())
        }
    }
    let corpus: Value = serde_json::from_str(include_str!(
        "../../../spec/ir/mck/metadata-contract-draft.json"
    ))
    .unwrap();
    let mut adapter = Changing {
        path: work
            .path()
            .join("spec/ir/mck/metadata-fixtures/schema-closure.json"),
        replies: vec![
            caps(
                json!([{"operation":"normalize","profile":"json","layout":"single","irRevision":"4.1.0"}]),
            ),
            json!({"ok":true,"observation":corpus["cases"][0]["expected"]}),
        ],
        request: None,
    };
    let run = run_kit(
        &kit,
        &mut adapter,
        Some(&Regex::new("^metadata-0001$").unwrap()),
    );
    assert_eq!(run.records[0].result, "pass", "{:?}", run.records);
    let fixtures = adapter.request.unwrap()["fixtures"]
        .as_array()
        .unwrap()
        .clone();
    let closure = fixtures
        .iter()
        .find(|f| f["path"] == "metadata-fixtures/schema-closure.json")
        .unwrap();
    assert_eq!(closure["sha256"], digest.as_str());
}
