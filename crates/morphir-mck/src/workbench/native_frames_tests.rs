use super::*;
use serde_json::{Value, json};

const DRAFT: &str = "0.1.0-draft.7";

fn operation() -> Operation {
    serde_json::from_value(json!("validate-native-frame")).unwrap()
}

fn capabilities() -> Value {
    json!({"suite":"workbench","contractVersion":DRAFT,"binding":"transcript",
        "language":"test","operations":["validate-native-frame"],"formats":["json"]})
}

fn corpus_file(root: &std::path::Path, input: Value) {
    std::fs::write(
        root.join("cases.json"),
        json!({"formatVersion":DRAFT,"cases":[{
        "id":"frame","operation":"validate-native-frame","format":"json","input":input,
        "expected":{"status":"ok","value":{"frameAccepted":true}}}]})
        .to_string(),
    )
    .unwrap();
}

#[test]
fn native_frames_exact_negotiation_and_closed_projection() {
    let op = operation();
    Capabilities::parse(capabilities(), DRAFT).unwrap();
    for version in [
        VERSION,
        ADMISSION_VERSION,
        INVOCATION_VERSION,
        OUTPUT_VERSION,
        OUTCOMES_VERSION,
        JOBS_VERSION,
        "0.1.0-draft.8",
        "0.1.0-draft.7+local",
        "v0.1.0-draft.7",
    ] {
        let mut caps = capabilities();
        caps["contractVersion"] = json!(version);
        assert!(Capabilities::parse(caps, version).is_err(), "{version}");
    }
    for (field, value) in [
        ("operations", json!([])),
        ("operations", json!(["reduce-job"])),
        (
            "operations",
            json!(["validate-native-frame", "decode-value"]),
        ),
        ("formats", json!([])),
        ("formats", json!(["ion-text"])),
        ("formats", json!(["json", "ion-text"])),
    ] {
        let mut caps = capabilities();
        caps[field] = value;
        assert!(Capabilities::parse(caps, DRAFT).is_err());
    }
    for value in [
        json!({"frameAccepted":false}),
        json!({"frameAccepted":true,"extra":1}),
        json!({}),
        json!({"type":"unit"}),
        json!(true),
    ] {
        assert!(Observation::Ok { value }.validate_for(op).is_err());
    }
    Observation::Ok {
        value: json!({"frameAccepted":true}),
    }
    .validate_for(op)
    .unwrap();
    for code in [
        "native.frame.limit",
        "native.frame.utf8",
        "native.frame.json",
        "native.frame.shape",
        "native.frame.model",
        "native.frame.arguments",
    ] {
        Observation::Invalid { code: code.into() }
            .validate_for(op)
            .unwrap();
    }
    assert!(
        Observation::Invalid {
            code: "native.frame.other".into()
        }
        .validate_for(op)
        .is_err()
    );
    assert!(
        Observation::Ok {
            value: json!({"frameAccepted":true})
        }
        .validate_for(Operation::ReduceJob)
        .is_err()
    );
}

#[test]
fn native_frames_compact_envelope_is_closed_bounded_and_source_is_opaque() {
    let root = tempfile::tempdir().unwrap();
    for input in [
        json!({"encoding":"utf8","source":"not JSON"}),
        json!({"encoding":"hex","source":"C328"}),
        json!({"encoding":"utf8","source":"{}","generate":{"prefix":{"repeat":" ","count":1.0}}}),
        json!({"encoding":"utf8","source":"{}","generate":{"prefix":{"repeat":" ","count":1048576}}}),
    ] {
        corpus_file(root.path(), input);
        load(root.path()).unwrap();
    }
    for input in [
        json!(null),
        json!({"encoding":"base64","source":""}),
        json!({"encoding":"hex","source":"f"}),
        json!({"encoding":"hex","source":"gg"}),
        json!({"encoding":"utf8","source":"","extra":1}),
        json!({"encoding":"utf8","source":"","generate":null}),
        json!({"encoding":"utf8","source":"","generate":{"prefix":{"repeat":"\n","count":1}}}),
        json!({"encoding":"utf8","source":"","generate":{"prefix":{"repeat":" ","count":-1}}}),
        json!({"encoding":"utf8","source":"","generate":{"prefix":{"repeat":" ","count":1048577}}}),
        json!({"encoding":"utf8","source":"","generate":{"prefix":{"repeat":" ","count":1.5}}}),
        json!({"encoding":"utf8","source":"x".repeat(MAX_VALUE_BYTES)}),
    ] {
        corpus_file(root.path(), input.clone());
        assert!(load(root.path()).is_err(), "{input}");
    }
}

#[test]
fn native_frames_compact_count_preserves_exact_decimal_integer_semantics() {
    let root = tempfile::tempdir().unwrap();
    for (number, valid) in [
        ("1.0", true),
        ("1e0", true),
        ("10e-1", true),
        ("-0", true),
        ("104857600000000000000e-14", true),
        ("1.00000000000000001", false),
        ("1048576.00000000001", false),
        ("1e-999", false),
        ("-1e-999", false),
        ("1e9999999999999999999999999", false),
    ] {
        let input=serde_json::from_str(&format!("{{\"encoding\":\"utf8\",\"source\":\"{{}}\",\"generate\":{{\"prefix\":{{\"repeat\":\" \",\"count\":{number}}}}}}}")).unwrap();
        corpus_file(root.path(), input);
        assert_eq!(load(root.path()).is_ok(), valid, "{number}");
    }
}

#[test]
fn native_frames_corpus_rejects_literal_serde_private_objects_before_adapter_start() {
    let root = tempfile::tempdir().unwrap();
    for count in [
        r#"{"$serde_json::private::Number":"1"}"#,
        r#"{"$serde_json::private::Number":{"$serde_json::private::Number":"1"}}"#,
        r#"{"$serde_json::private::RawValue":"1"}"#,
    ] {
        let text = format!(
            r#"{{"formatVersion":"0.1.0-draft.7","cases":[{{"id":"frame","operation":"validate-native-frame","format":"json","input":{{"encoding":"utf8","source":"{{}}","generate":{{"prefix":{{"repeat":" ","count":{count}}}}}}},"expected":{{"status":"ok","value":{{"frameAccepted":true}}}}}}]}}"#
        );
        std::fs::write(root.path().join("cases.json"), text).unwrap();
        assert!(load(root.path()).is_err(), "{count}");
    }
    corpus_file(
        root.path(),
        json!({"encoding":"utf8","source":"{}","generate":{"prefix":{
        "repeat":" ","count":{"$serde_json::private::Number":"1"}}}}),
    );
    assert!(load(root.path()).is_err());
    for input in [
        json!({"encoding":{"$serde_json::private::RawValue":"\"utf8\""},"source":"{}"}),
        json!({"encoding":"utf8","source":{"$serde_json::private::RawValue":"\"{}\""}}),
    ] {
        corpus_file(root.path(), input);
        assert!(load(root.path()).is_err());
    }
    let text = r#"{"formatVersion":"0.1.0-draft.7","cases":[{"id":"frame","operation":"validate-native-frame","format":"json","input":{"encoding":"utf8","source":"{}"},"expected":{"status":"ok","value":{"frameAccepted":{"$serde_json::private::RawValue":"true"}}}}]}"#;
    std::fs::write(root.path().join("cases.json"), text).unwrap();
    assert!(load(root.path()).is_err());
}

struct Replay {
    replies: std::collections::VecDeque<Value>,
    requests: Vec<Value>,
}
impl Testee for Replay {
    fn exchange(&mut self, request: &Value) -> Result<Value, String> {
        self.requests.push(request.clone());
        self.replies
            .pop_front()
            .ok_or_else(|| "adapter failed".into())
    }
}

#[test]
fn native_frames_fixed_transcript_checks_reports_without_decoding_native_inputs() {
    let root =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/workbench/mck/draft.7");
    let corpus = load(&root).unwrap();
    assert!(corpus.case_count() >= 40);
    assert!(
        corpus
            .cases
            .iter()
            .any(|c| matches!(c.expected, Observation::Ok { .. }))
    );
    assert!(
        corpus
            .cases
            .iter()
            .any(|c| matches!(c.expected, Observation::Invalid { .. }))
    );
    let mut adapter = Replay {
        replies: std::iter::once(capabilities())
            .chain(
                corpus
                    .cases
                    .iter()
                    .map(|c| serde_json::to_value(&c.expected).unwrap()),
            )
            .collect(),
        requests: vec![],
    };
    let report = execute(&corpus, &mut adapter);
    assert!(report.qualified, "{:?}", report.errors);
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
            .all(|r| r["op"] == "validate-native-frame" && r["format"] == "json")
    );
    let saved = serde_json::to_value(&report).unwrap();
    for change in [
        "qualified",
        "result",
        "operation",
        "format",
        "hash",
        "projection",
        "code",
        "capabilities",
    ] {
        let mut forged = saved.clone();
        match change {
            "qualified" => forged["qualified"] = json!(false),
            "result" => forged["records"][0]["result"] = json!("fail"),
            "operation" => forged["records"][0]["operation"] = json!("reduce-job"),
            "format" => forged["records"][0]["format"] = json!("ion-text"),
            "hash" => forged["corpusHash"] = json!("0".repeat(64)),
            "projection" => {
                forged["records"][0]["observed"] =
                    json!({"status":"ok","value":{"frameAccepted":false}})
            }
            "code" => {
                forged["records"][0]["observed"] =
                    json!({"status":"invalid","code":"native.frame.other"})
            }
            "capabilities" => forged["capabilities"]["contractVersion"] = json!(JOBS_VERSION),
            _ => unreachable!(),
        }
        assert!(
            check_report(&root, &Report::from_json(&forged.to_string()).unwrap()).is_err(),
            "{change}"
        );
    }
    let bytes = std::fs::read(root.join("cases.json")).unwrap();
    let changed = tempfile::tempdir().unwrap();
    let mut changed_bytes = bytes;
    changed_bytes.push(b' ');
    std::fs::write(changed.path().join("cases.json"), changed_bytes).unwrap();
    assert!(check_report(changed.path(), &report).is_err());
}

#[test]
fn native_frames_adapter_faults_are_errors_and_valid_differences_are_failures() {
    let root = tempfile::tempdir().unwrap();
    corpus_file(root.path(), json!({"encoding":"utf8","source":"{}"}));
    let corpus = load(root.path()).unwrap();
    for reply in [
        None,
        Some(json!({"status":"ok","value":{"frameAccepted":false}})),
        Some(json!({"status":"invalid","code":"adapter.error"})),
    ] {
        let mut adapter = Replay {
            replies: std::iter::once(capabilities()).chain(reply).collect(),
            requests: vec![],
        };
        let report = execute(&corpus, &mut adapter);
        assert_eq!(report.records[0].result, ResultKind::Error);
        assert_eq!(report.errors[0].phase, Phase::Exchange);
        check_report(root.path(), &report).unwrap();
    }
    let mut adapter = Replay {
        replies: [
            capabilities(),
            json!({"status":"invalid","code":"native.frame.shape"}),
        ]
        .into(),
        requests: vec![],
    };
    let report = execute(&corpus, &mut adapter);
    assert_eq!(report.records[0].result, ResultKind::Fail);
    assert!(report.errors.is_empty());
    check_report(root.path(), &report).unwrap();
}
