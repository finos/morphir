use super::*;
use serde_json::json;

#[test]
fn capability_jobs_negotiates_the_new_exact_operation() {
    let capabilities = json!({"suite":"workbench","contractVersion":"0.1.0-draft.13",
        "binding":"job-policy-infrastructure-test","language":"test",
        "operations":["run-capability-jobs"],"formats":["json"]});
    assert!(Capabilities::parse(capabilities, "0.1.0-draft.13").is_ok());
}

fn capabilities() -> serde_json::Value {
    json!({"suite":"workbench","contractVersion":CAPABILITY_JOBS_VERSION,
        "binding":"job-infrastructure-only","language":"test",
        "operations":["run-capability-jobs"],"formats":["json"]})
}
fn fixture() -> serde_json::Value {
    serde_json::from_str::<serde_json::Value>(include_str!(
        "../../../../spec/workbench/mck/draft.13/cases.json"
    ))
    .unwrap()["cases"][0]
        .clone()
}
fn small_corpus(root: &std::path::Path, case: serde_json::Value) -> Result<Corpus, String> {
    std::fs::write(
        root.join("cases.json"),
        json!({"formatVersion":CAPABILITY_JOBS_VERSION,"cases":[case]}).to_string(),
    )
    .unwrap();
    load(root)
}
struct Reply(serde_json::Value);
impl Testee for Reply {
    fn exchange(&mut self, request: &serde_json::Value) -> Result<serde_json::Value, String> {
        assert!(request.get("expected").is_none() && request.get("caseId").is_none());
        if request["op"] == "capabilities" {
            Ok(capabilities())
        } else {
            assert_eq!(request["op"], "run-capability-jobs");
            Ok(self.0.clone())
        }
    }
}
#[test]
fn capability_jobs_rejects_adjacent_drafts_and_operation_format_expansion() {
    for (field, value) in [
        ("contractVersion", json!("0.1.0-draft.13+local")),
        ("contractVersion", json!(CAPABILITY_POLICY_VERSION)),
        ("operations", json!(["run-capability-policy"])),
        ("formats", json!(["ion-text"])),
    ] {
        let mut bad = capabilities();
        bad[field] = value;
        assert!(Capabilities::parse(bad, CAPABILITY_JOBS_VERSION).is_err());
    }
    let mut absent = capabilities();
    absent["operations"] = json!([]);
    Capabilities::parse(absent, CAPABILITY_JOBS_VERSION).unwrap();
}
#[test]
fn capability_jobs_fixed_inventory_replays_and_rechecks_without_linking_an_engine() {
    let root =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/workbench/mck/draft.13");
    let corpus = load(&root).unwrap();
    assert_eq!(corpus.case_count(), 69);
    struct Replay(std::collections::VecDeque<serde_json::Value>);
    impl Testee for Replay {
        fn exchange(&mut self, request: &serde_json::Value) -> Result<serde_json::Value, String> {
            assert!(request.get("expected").is_none() && request.get("caseId").is_none());
            self.0
                .pop_front()
                .ok_or("exhausted infrastructure replay".into())
        }
    }
    let mut replay = Replay(
        std::iter::once(capabilities())
            .chain(
                corpus
                    .cases
                    .iter()
                    .map(|c| serde_json::to_value(&c.expected).unwrap()),
            )
            .collect(),
    );
    let report = execute(&corpus, &mut replay);
    assert!(report.qualified, "{:?}", report.errors);
    check_report(&root, &Report::from_json(&report.to_json()).unwrap()).unwrap();
}
#[test]
fn capability_jobs_corpus_closes_literal_shapes_before_typed_conversion() {
    let root = tempfile::tempdir().unwrap();
    for kind in [
        "model-marker",
        "policy-marker",
        "claim-marker",
        "boundary-marker",
        "manifest",
        "fourth-replan",
    ] {
        let mut case = fixture();
        match kind{
            "model-marker"=>case["input"]["submission"]["model"]=json!({"$serde_json::private::RawValue":"\"x\""}),
            "policy-marker"=>case["input"]["submission"]["admission"]["policy"]=json!({"$serde_json::private::RawValue":"\"permissive\""}),
            "claim-marker"=>case["input"]["actions"]=json!([{"op":"claim","job":0,"selection":{"planId":"plan-1","runtime":"scheme","policy":{"$serde_json::private::RawValue":"\"permissive\""},"providerId":"scheme"}}]),
            "boundary-marker"=>case["expected"]["value"]["jobs"][0]["plan"]["boundary"]["entries"][0]["name"]=json!({"$serde_json::private::RawValue":"\"entry\""}),
            "manifest"=>case["input"]["submission"]["manifest"]=json!({}),
            "fourth-replan"=>case["input"]["actions"]=json!((0..4).map(|_|json!({"op":"replan","job":0,"selection":{"planId":"plan-1","runtime":"scheme","policy":"permissive","providerId":"scheme"}})).collect::<Vec<_>>()),_=>unreachable!()}
        assert!(small_corpus(root.path(), case).is_err(), "{kind}");
    }
    let mut opaque = fixture();
    opaque["input"]["submission"]["model"] = json!("not decoded by runner");
    opaque["input"]["submission"]["calls"][0]["inputs"]["source"] = json!("[");
    small_corpus(root.path(), opaque).unwrap();
    let text = std::fs::read_to_string(root.path().join("cases.json"))
        .unwrap()
        .replacen(
            "\"runtime\":\"scheme\"",
            "\"runtime\":\"scheme\",\"runtime\":\"scheme\"",
            1,
        );
    std::fs::write(root.path().join("cases.json"), text).unwrap();
    assert!(load(root.path()).is_err());
}
#[test]
fn capability_jobs_reports_recompute_captured_selection_context_receipts_and_inventory() {
    let root = tempfile::tempdir().unwrap();
    let case = fixture();
    let corpus = small_corpus(root.path(), case.clone()).unwrap();
    let report = execute(&corpus, &mut Reply(case["expected"].clone()));
    assert!(report.qualified);
    let saved = serde_json::to_value(&report).unwrap();
    for kind in [
        "policy",
        "runtime",
        "evaluator",
        "boundary",
        "plan-id",
        "identity",
        "receipt",
        "action",
        "qualified",
        "hash",
    ] {
        let mut bad = saved.clone();
        let plan = &mut bad["records"][0]["observed"]["value"]["jobs"][0]["plan"];
        match kind {
            "policy" => plan["admission"]["policy"] = json!("strict"),
            "runtime" => plan["runtime"] = json!("javascript"),
            "evaluator" => plan["evaluator"] = json!("other"),
            "boundary" => plan["boundary"]["entries"][0]["output"] = json!({"type":"bool"}),
            "plan-id" => plan["planId"] = json!("plan-2"),
            "identity" => plan["identity"]["snapshotId"] = json!("other"),
            "receipt" => {
                bad["records"][0]["observed"]["value"]["jobs"][0]["receipt"]["sequence"] = json!(1)
            }
            "action" => {
                bad["records"][0]["observed"]["value"]["observations"][0]["view"]["policy"] =
                    json!("strict")
            }
            "qualified" => bad["qualified"] = json!(false),
            "hash" => bad["corpusHash"] = json!("0".repeat(64)),
            _ => unreachable!(),
        }
        assert!(
            Report::from_json(&bad.to_string())
                .and_then(|r| check_report(root.path(), &r))
                .is_err(),
            "{kind}"
        );
    }
    let mut mismatch = case["expected"].clone();
    mismatch["value"]["jobs"][0]["plan"]["admission"]["policy"] = json!("strict");
    let failed = execute(&corpus, &mut Reply(mismatch));
    assert_eq!(failed.records[0].result, ResultKind::Fail);
    check_report(root.path(), &failed).unwrap();
    let malformed = execute(
        &corpus,
        &mut Reply(json!({"status":"invalid","code":"workbench.host_selection_mismatch"})),
    );
    assert_eq!(malformed.records[0].result, ResultKind::Error);
    check_report(root.path(), &malformed).unwrap();
    let mut bytes = std::fs::read(root.path().join("cases.json")).unwrap();
    bytes.push(b' ');
    std::fs::write(root.path().join("cases.json"), bytes).unwrap();
    assert!(check_report(root.path(), &report).is_err());
}
#[test]
fn capability_jobs_projection_resources_and_receipt_binding_are_checked() {
    let root = tempfile::tempdir().unwrap();
    let case = fixture();
    let corpus = small_corpus(root.path(), case.clone()).unwrap();
    for kind in [
        "identity",
        "duplicate-plan",
        "duplicate-job",
        "long-code",
        "oversized",
    ] {
        let mut value = case["expected"].clone();
        match kind {
            "identity" => {
                value["value"]["jobs"][0]["receipt"]["identity"]["jobId"] = json!("other")
            }
            "duplicate-plan" => {
                let j = value["value"]["jobs"][0].clone();
                value["value"]["jobs"].as_array_mut().unwrap().push(j);
            }
            "duplicate-job" => {
                let mut job = value["value"]["jobs"][0].clone();
                job["plan"]["planId"] = json!("plan-2");
                value["value"]["jobs"].as_array_mut().unwrap().push(job);
            }
            "long-code" => {
                value["value"]["observations"][0] = json!({"op":"inspect","job":0,"status":"invalid","code":"😀".repeat(65),"view":null})
            }
            "oversized" => {
                value["value"]["jobs"][0]["plan"]["boundary"]["entries"][0]["name"] =
                    json!("x".repeat(MAX_VALUE_BYTES))
            }
            _ => unreachable!(),
        }
        let report = execute(&corpus, &mut Reply(value));
        assert_eq!(report.records[0].result, ResultKind::Error, "{kind}");
        check_report(root.path(), &report).unwrap();
    }
}
