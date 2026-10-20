use super::*;
use serde_json::json;

fn capabilities() -> serde_json::Value {
    json!({"suite":"workbench","contractVersion":"0.1.0-draft.16","binding":"transcript",
        "language":"test","operations":["validate-native-reply"],"formats":["json"]})
}

struct Replay {
    replies: std::collections::VecDeque<serde_json::Value>,
    requests: Vec<serde_json::Value>,
}

impl Testee for Replay {
    fn exchange(&mut self, request: &serde_json::Value) -> Result<serde_json::Value, String> {
        self.requests.push(request.clone());
        self.replies
            .pop_front()
            .ok_or("transcript exhausted".into())
    }
}

fn successful_corpus(root: &std::path::Path) -> Corpus {
    std::fs::write(root.join("cases.json"), json!({"formatVersion":"0.1.0-draft.16","cases":[{
        "id":"close","operation":"validate-native-reply","format":"json",
        "input":{"expectedOperation":"session.close","expectedSession":null,"encoding":"utf8",
                 "source":"{\"ok\":true,\"operation\":\"session.close\",\"value\":{}}"},
        "expected":{"status":"ok","value":{"replyAccepted":true,"ok":true,"operation":"session.close"}}
    }]}).to_string()).unwrap();
    load(root).unwrap()
}

#[test]
fn native_reply_literal_objects_are_exchange_errors_not_forged_successes() {
    let root = tempfile::tempdir().unwrap();
    let corpus = successful_corpus(root.path());
    let forged = json!({"status":"ok","value":{"$serde_json::private::RawValue":
        "{\"replyAccepted\":true,\"ok\":true,\"operation\":\"session.close\"}"}});
    let mut adapter = Replay {
        replies: [capabilities(), forged].into(),
        requests: vec![],
    };
    let report = execute(&corpus, &mut adapter);
    assert!(!report.qualified());
    assert_eq!(
        report
            .as_historical()
            .expect("historical report fixture")
            .records[0]
            .result,
        ResultKind::Error
    );
    assert_eq!(
        report
            .as_historical()
            .expect("historical report fixture")
            .errors[0]
            .phase,
        Phase::Exchange
    );
    check_report(root.path(), &report).unwrap();
}

#[test]
fn native_reply_saved_reports_reject_literal_forgery_before_typed_conversion() {
    let root = tempfile::tempdir().unwrap();
    let corpus = successful_corpus(root.path());
    let observation =
        json!({"status":"ok","value":{"replyAccepted":true,"ok":true,"operation":"session.close"}});
    let mut adapter = Replay {
        replies: [capabilities(), observation].into(),
        requests: vec![],
    };
    let report = execute(&corpus, &mut adapter);
    assert!(report.qualified());
    check_report(root.path(), &report).unwrap();
    let mut saved = serde_json::to_value(&report).unwrap();
    saved["records"][0]["observed"]["value"] = json!({"$serde_json::private::RawValue":
        "{\"replyAccepted\":true,\"ok\":true,\"operation\":\"session.close\"}"});
    assert!(Report::from_json(&saved.to_string()).is_err());
}

#[test]
fn native_reply_fixed_corpus_runs_and_reports_are_recomputed_without_an_oracle() {
    let root =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/workbench/mck/draft.16");
    let corpus = load(&root).unwrap();
    assert_eq!(corpus.case_count(), 185);
    let mut adapter = Replay {
        replies: std::iter::once(capabilities())
            .chain(
                corpus
                    .as_historical()
                    .expect("historical corpus fixture")
                    .cases
                    .iter()
                    .map(|c| serde_json::to_value(&c.expected).unwrap()),
            )
            .collect(),
        requests: vec![],
    };
    let report = execute(&corpus, &mut adapter);
    assert!(
        report.qualified(),
        "{:?}",
        report
            .as_historical()
            .expect("historical report fixture")
            .errors
    );
    check_report(&root, &report).unwrap();
    assert!(
        adapter
            .requests
            .iter()
            .all(|r| r.get("expected").is_none() && r.get("caseId").is_none())
    );
    assert!(
        adapter.requests[1..]
            .iter()
            .all(|r| r["op"] == "validate-native-reply" && r["format"] == "json")
    );
    let saved = serde_json::to_value(&report).unwrap();
    for key in [
        "qualified",
        "result",
        "operation",
        "format",
        "hash",
        "effect",
        "capabilities",
    ] {
        let mut forged = saved.clone();
        match key {
            "qualified" => forged["qualified"] = json!(false),
            "result" => forged["records"][0]["result"] = json!("fail"),
            "operation" => forged["records"][0]["operation"] = json!("validate-native-frame"),
            "format" => forged["records"][0]["format"] = json!("ion-text"),
            "hash" => forged["corpusHash"] = json!("0".repeat(64)),
            "effect" => {
                forged["records"][24]["observed"]["value"]["error"]["effect"] = json!("unknown")
            }
            "capabilities" => forged["capabilities"]["contractVersion"] = json!("0.1.0-draft.15"),
            _ => unreachable!(),
        }
        assert!(
            Report::from_json(&forged.to_string())
                .and_then(|r| check_report(&root, &r))
                .is_err(),
            "{key}"
        );
    }
    let changed = tempfile::tempdir().unwrap();
    let mut bytes = std::fs::read(root.join("cases.json")).unwrap();
    bytes.push(b' ');
    std::fs::write(changed.path().join("cases.json"), bytes).unwrap();
    assert!(check_report(changed.path(), &report).is_err());
}

#[test]
fn native_replies_negotiate_only_the_exact_operation_and_json() {
    Capabilities::parse(capabilities(), "0.1.0-draft.16").unwrap();
    for (field, value) in [
        ("operations", json!([])),
        ("operations", json!(["validate-native-frame"])),
        (
            "operations",
            json!(["validate-native-reply", "decode-value"]),
        ),
        ("formats", json!([])),
        ("formats", json!(["ion-text"])),
        ("formats", json!(["json", "ion-text"])),
    ] {
        let mut caps = capabilities();
        caps[field] = value;
        assert!(Capabilities::parse(caps, "0.1.0-draft.16").is_err());
    }
    for version in [
        "0.1.0-draft.15",
        "0.1.0-draft.17",
        "0.1.0-draft.16+local",
        "v0.1.0-draft.16",
    ] {
        let mut caps = capabilities();
        caps["contractVersion"] = json!(version);
        assert!(Capabilities::parse(caps, version).is_err());
    }
}

#[test]
fn native_reply_corpus_accepts_opaque_source_for_exact_draft() {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(
        root.path().join("cases.json"),
        json!({"formatVersion":"0.1.0-draft.16","cases":[{
            "id":"opaque-reply","operation":"validate-native-reply","format":"json",
            "input":{"expectedOperation":"session.open","expectedSession":null,
                     "encoding":"utf8","source":"not JSON"},
            "expected":{"status":"invalid","code":"native.reply.json"}
        }]})
        .to_string(),
    )
    .unwrap();
    let corpus = load(root.path()).expect("new reply kit admits opaque native source");
    assert_eq!(corpus.case_count(), 1);
}

#[test]
fn native_reply_observations_preserve_effects_and_have_a_closed_projection() {
    let operation: Operation = serde_json::from_value(json!("validate-native-reply")).unwrap();
    for value in [
        json!({"replyAccepted":true,"ok":true,"operation":"session.close"}),
        json!({"replyAccepted":true,"ok":false,"error":{"code":"limit","effect":"none"}}),
        json!({"replyAccepted":true,"ok":false,"error":{"code":"unavailable","effect":"unknown"}}),
    ] {
        Observation::Ok { value }.validate_for(operation).unwrap();
    }
    for value in [
        json!({"replyAccepted":true}),
        json!({"replyAccepted":true,"ok":true,"operation":"other"}),
        json!({"replyAccepted":true,"ok":false,"error":{"code":"limit","effect":"none","message":"private"}}),
        json!({"replyAccepted":true,"ok":false,"error":{"code":"limit","effect":"certain"}}),
    ] {
        assert!(Observation::Ok { value }.validate_for(operation).is_err());
    }
    assert!(
        Observation::Invalid {
            code: "native.reply.other".into()
        }
        .validate_for(operation)
        .is_err()
    );
    assert!(!Observation::Ok { value: json!({"replyAccepted":true,"ok":false,"error":{"code":"limit","effect":"none"}}) }
        .matches(&Observation::Ok { value: json!({"replyAccepted":true,"ok":false,"error":{"code":"limit","effect":"unknown"}}) }, operation).unwrap());
}

#[test]
fn native_reply_capture_and_recipe_admission_preserves_literal_tokens() {
    let root = tempfile::tempdir().unwrap();
    successful_corpus(root.path());
    let original = std::fs::read_to_string(root.path().join("cases.json")).unwrap();
    let original: serde_json::Value = serde_json::from_str(&original).unwrap();
    for session in [
        json!(""),
        json!("a".repeat(129)),
        json!("a\n"),
        json!("é"),
        json!(1),
    ] {
        let mut value = original.clone();
        value["cases"][0]["input"]["expectedSession"] = session;
        std::fs::write(root.path().join("cases.json"), value.to_string()).unwrap();
        assert!(load(root.path()).is_err());
    }
    let mut recipe = original.clone();
    recipe["cases"][0]["input"]["generate"] = json!({"prefix":{"repeat":" ","count":"COUNT"}});
    let text = recipe.to_string();
    for token in ["1e0", "10e-1", "1048576", "-0"] {
        std::fs::write(
            root.path().join("cases.json"),
            text.replace("\"COUNT\"", token),
        )
        .unwrap();
        load(root.path()).expect("exact bounded integer recipe");
    }
    for token in [
        "1e-999",
        "1.00000000000000001",
        "1048577",
        r#"{"$serde_json::private::Number":"1"}"#,
    ] {
        std::fs::write(
            root.path().join("cases.json"),
            text.replace("\"COUNT\"", token),
        )
        .unwrap();
        assert!(load(root.path()).is_err(), "{token}");
    }
    let mut oversized = original;
    oversized["cases"][0]["input"]["source"] = json!("a".repeat(1_048_576));
    std::fs::write(root.path().join("cases.json"), oversized.to_string()).unwrap();
    assert!(load(root.path()).is_err());
}

#[test]
fn native_reply_compatibility_failures_remain_checkable_without_infrastructure_errors() {
    let root = tempfile::tempdir().unwrap();
    let corpus = successful_corpus(root.path());
    let mut adapter = Replay {
        replies: [
            capabilities(),
            json!({"status":"invalid","code":"native.reply.shape"}),
        ]
        .into(),
        requests: vec![],
    };
    let report = execute(&corpus, &mut adapter);
    assert!(!report.qualified());
    assert_eq!(
        report
            .as_historical()
            .expect("historical report fixture")
            .records[0]
            .result,
        ResultKind::Fail
    );
    assert!(
        report
            .as_historical()
            .expect("historical report fixture")
            .errors
            .is_empty()
    );
    check_report(root.path(), &report).unwrap();
    let saved = serde_json::to_string(&report).unwrap();
    check_report(root.path(), &Report::from_json(&saved).unwrap()).unwrap();
}
