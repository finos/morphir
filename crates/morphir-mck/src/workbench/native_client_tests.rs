use super::*;
use serde_json::json;

#[test]
fn native_client_negotiates_only_its_exact_json_operation() {
    let caps = json!({"suite":"workbench","contractVersion":"0.1.0-draft.9",
        "binding":"production-client","language":"typescript",
        "operations":["run-native-client"],"formats":["json"]});
    Capabilities::parse(caps.clone(), "0.1.0-draft.9").unwrap();
    for (field, value) in [
        ("operations", json!([])),
        ("operations", json!(["validate-native-reply"])),
        ("formats", json!(["ion-text"])),
        ("contractVersion", json!("0.1.0-draft.9+local")),
    ] {
        let mut bad = caps.clone();
        bad[field] = value;
        assert!(Capabilities::parse(bad, "0.1.0-draft.9").is_err());
    }
}

#[test]
fn native_client_corpus_uses_fixed_opaque_scenarios_and_recomputed_reports() {
    let root =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/workbench/mck/draft.9");
    let corpus = load(&root).unwrap();
    assert_eq!(corpus.case_count(), 21);
    struct Replay {
        replies: std::collections::VecDeque<serde_json::Value>,
    }
    impl Testee for Replay {
        fn exchange(&mut self, request: &serde_json::Value) -> Result<serde_json::Value, String> {
            assert!(request.get("expected").is_none() && request.get("caseId").is_none());
            self.replies.pop_front().ok_or("exhausted".into())
        }
    }
    let caps = json!({"suite":"workbench","contractVersion":"0.1.0-draft.9","binding":"transcript",
        "language":"test","operations":["run-native-client"],"formats":["json"]});
    let mut replay = Replay {
        replies: std::iter::once(caps)
            .chain(
                corpus
                    .cases
                    .iter()
                    .map(|c| serde_json::to_value(&c.expected).unwrap()),
            )
            .collect(),
    };
    let report = execute(&corpus, &mut replay);
    assert!(report.qualified, "{:?}", report.errors);
    check_report(&root, &report).unwrap();
}
