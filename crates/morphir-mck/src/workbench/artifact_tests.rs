use super::*;
use serde_json::{Value, json};

fn manifest(generation: &str, artifact: &str, session: &str) -> Value {
    json!({"status":"ready","profile":"morphir/workbench/artifacts","contractVersion":"0.1.0-draft.1","sessionId":session,"providerId":"playground","generationId":generation,"producer":{"id":"artifact-fixture","version":"0.1.0"},"target":"fixture","irVersion":"4","artifacts":[{"id":artifact,"path":"one.bin","kind":"binary","byteLength":1,"sha256":"6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d"}],"diagnostics":[]})
}
fn transcript(generation: &str, artifact: &str, session: &str) -> Value {
    json!({"sessionId":session,"providerId":"playground","events":[
        {"event":"connected","connection":"c1","status":"accepted"},
        {"event":"initialized","connection":"c1","status":"initialized"},
        {"event":"generated","connection":"c1","generation":"g1","requestId":"2","reply":json!({"jsonrpc":"2.0","id":2,"result":manifest(generation,artifact,session)}).to_string()},
        {"event":"read","connection":"c1","requestId":"3","reply":json!({"jsonrpc":"2.0","id":3,"result":{"profile":"morphir/workbench/artifacts","contractVersion":"0.1.0-draft.1","generationId":generation,"artifactId":artifact,"offset":0,"nextOffset":1,"content":"AA=="}}).to_string()},
        {"event":"released","connection":"c1","generation":"g1","requestId":"4","reply":"{\"jsonrpc\":\"2.0\",\"id\":4,\"result\":{}}"},
        {"event":"closed","connection":"c1"},
        {"event":"usage","invocations":1,"reservedBytes":0,"reservedGenerations":0,"activeInvocations":0}
    ]})
}
#[test]
fn artifact_mck_qualifies_only_exact_server_role() {
    let caps = json!({"suite":"workbench","contractVersion":"0.1.0-draft.28","binding":"test","language":"rust","operations":["artifact-server"],"formats":["json"]});
    Capabilities::parse(caps.clone(), "0.1.0-draft.28").unwrap();
    for (field, bad) in [
        ("contractVersion", json!("0.1.0-draft.27")),
        ("operations", json!(["worksheet-evaluate"])),
        ("formats", json!(["ion-text"])),
    ] {
        let mut value = caps.clone();
        value[field] = bad;
        assert!(Capabilities::parse(value, "0.1.0-draft.28").is_err());
    }
}
#[test]
fn artifact_mck_normalizes_only_validated_opaque_handles() {
    let a = super::artifacts::projection(&transcript("gen-a", "artifact-a", "session-a")).unwrap();
    let b =
        super::artifacts::projection(&transcript("opaque-b", "another-b", "session-b")).unwrap();
    assert_eq!(a, b);
    for pointer in ["/sessionId", "/providerId"] {
        let mut bad = transcript("gen-a", "artifact-a", "session-a");
        *bad.pointer_mut(pointer).unwrap() = json!("wrong");
        assert!(super::artifacts::projection(&bad).is_err());
    }
}
#[test]
fn artifact_mck_rejects_corrupt_raw_context_lengths_base64_and_versions() {
    let good = transcript("gen-a", "artifact-a", "session-a");
    for (event, pointer, bad) in [
        (2, "/id", json!(99)),
        (2, "/result/sessionId", json!("wrong")),
        (2, "/result/producer/version", json!("9007199254740992.0.0")),
        (2, "/result/artifacts/0/byteLength", json!(16777217)),
        (3, "/result/generationId", json!("stolen")),
        (3, "/result/nextOffset", json!(0)),
        (3, "/result/content", json!("AB==")),
        (3, "/result/content", json!("AA")),
    ] {
        let mut value = good.clone();
        let mut reply: Value =
            serde_json::from_str(value["events"][event]["reply"].as_str().unwrap()).unwrap();
        *reply.pointer_mut(pointer).unwrap() = bad;
        value["events"][event]["reply"] = json!(reply.to_string());
        assert!(super::artifacts::projection(&value).is_err(), "{pointer}");
    }
}
#[test]
fn artifact_mck_preserves_duplicate_and_literal_number_evidence() {
    for reply in [
        "{\"jsonrpc\":\"2.0\",\"id\":3,\"id\":3,\"result\":{}}",
        "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"$serde_json::private::RawValue\":\"{}\"}}",
    ] {
        let mut value = transcript("gen-a", "artifact-a", "session-a");
        value["events"][3]["reply"] = json!(reply);
        assert!(super::artifacts::projection(&value).is_err());
    }
}

fn kit() -> std::path::PathBuf {
    std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../spec/workbench/mck/draft.28/server")
}
struct AuthoredEvidence(std::collections::VecDeque<Value>);
impl Testee for AuthoredEvidence {
    fn exchange(&mut self, request: &Value) -> Result<Value, String> {
        assert!(request.get("expected").is_none() && request.get("caseId").is_none());
        if request["op"] == "capabilities" {
            Ok(
                json!({"suite":"workbench","contractVersion":"0.1.0-draft.28","binding":"checker-infrastructure-only","language":"rust","operations":["artifact-server"],"formats":["json"]}),
            )
        } else {
            self.0
                .pop_front()
                .ok_or_else(|| "missing authored evidence".into())
        }
    }
}
/// This tests only the shared runner/checker. It is not a production server
/// adapter and does not establish artifact-host or process compatibility.
#[test]
fn artifact_mck_authored_corpus_and_report_checker_are_self_consistent() {
    let corpus = load(&kit()).unwrap();
    assert_eq!(corpus.case_count(), 103);
    let canonical = load(kit().parent().unwrap()).unwrap();
    let selected = canonical
        .cases
        .iter()
        .filter(|case| case.operation() == Operation::ArtifactServer)
        .collect::<Vec<_>>();
    assert_eq!(selected.len(), corpus.case_count());
    for (left, right) in selected.into_iter().zip(&corpus.cases) {
        assert_eq!(left.id, right.id);
        assert_eq!(left.input, right.input);
        assert_eq!(left.expected, right.expected);
    }
    let answers = corpus
        .cases
        .iter()
        .map(|case| serde_json::to_value(&case.expected).unwrap())
        .collect();
    let report = execute(&corpus, &mut AuthoredEvidence(answers));
    assert!(report.qualified, "{:?}", report.errors);
    let saved = serde_json::to_string(&report).unwrap();
    let checked = Report::from_json(&saved).unwrap();
    check_report(&kit(), &checked).unwrap();
    for (pointer, bad) in [
        ("/records/0/result", json!("fail")),
        ("/qualified", json!(false)),
        ("/records/0/observed/value/events/3/invocations", json!(0)),
        (
            "/records/1/observed/value/events/4/sha256",
            json!("0000000000000000000000000000000000000000000000000000000000000000"),
        ),
        (
            "/records/1/observed/value/events/4/chunks/0/nextOffset",
            json!(0),
        ),
    ] {
        let mut forged = serde_json::to_value(&report).unwrap();
        *forged.pointer_mut(pointer).unwrap() = bad;
        let result = Report::from_json(&serde_json::to_string(&forged).unwrap())
            .and_then(|report| check_report(&kit(), &report));
        assert!(result.is_err(), "forged {pointer}");
    }
}
#[test]
fn artifact_mck_bounds_fixture_work_before_adapter_execution() {
    let corpus = load(&kit()).unwrap();
    let original = &corpus
        .cases
        .iter()
        .find(|case| case.id == "bytes-indexed-16777216-0")
        .unwrap()
        .input;
    let mut bad = original.clone();
    bad["actions"][4]["maxBytes"] = json!(1);
    assert!(super::artifacts::validate_input(&bad).is_err());
    let mut bad = original.clone();
    let action = bad["actions"][2].clone();
    for _ in 0..8 {
        bad["actions"].as_array_mut().unwrap().push(action.clone());
    }
    assert!(super::artifacts::validate_input(&bad).is_err());
}

#[test]
fn artifact_mck_manifest_budget_reserves_maximum_rpc_id_before_ready() {
    let oversized =
        include_str!("../../../../spec/workbench/mck/draft.28/independent/manifest-131073.jsonrpc");
    let small_id = oversized.replacen("18446744073709551615", "2", 1);
    assert!(small_id.len() < 131072);
    let mut evidence = transcript("unused", "unused", "session-fixture");
    evidence["events"].as_array_mut().unwrap().truncate(3);
    evidence["events"][2]["reply"] = json!(small_id);
    assert!(super::artifacts::projection(&evidence).is_err());
}

#[test]
fn artifact_mck_sized_frames_reject_prefix_overflow_before_expansion() {
    let fixture: Value = serde_json::from_str(include_str!(
        "../../../../spec/workbench/mck/draft.28/server/cases.json"
    ))
    .unwrap();
    let mut input = fixture["cases"]
        .as_array()
        .unwrap()
        .iter()
        .find(|case| case["id"] == "frame-control-16384")
        .unwrap()["input"]
        .clone();
    input["actions"][2]["size"] = json!(1);
    assert!(super::artifacts::validate_input(&input).is_err());
}

fn raw_generation_budget_case() -> Value {
    let authored: Value = serde_json::from_str(include_str!(
        "../../../../spec/workbench/mck/draft.28/server/cases.json"
    ))
    .unwrap();
    let mut case = authored["cases"]
        .as_array()
        .unwrap()
        .iter()
        .find(|case| case["id"] == "aggregate-64MiB-exact")
        .unwrap()
        .clone();
    // Opaque raw strings are not classified by the runner. Each can reach the
    // generator, even when another raw string would release its generation.
    let frame = r#"{"jsonrpc":"2.0","id":2,"method":"morphir.artifacts.generate","params":{"contractVersion":"0.1.0-draft.1","providerId":"playground","generation":{"ir":{"formatVersion":4},"irVersion":"4","target":"fixture","options":{}}}}"#;
    case["input"]["actions"] = json!([
        {"action":"raw","connection":"c1","frame":frame},
        {"action":"raw","connection":"c1","frame":frame}
    ]);
    case
}
#[test]
fn artifact_mck_opaque_raw_actions_reserve_possible_generation_expansion() {
    let case = raw_generation_budget_case();
    assert_eq!(
        super::artifacts::validate_input(&case["input"]).unwrap(),
        128 * 1024 * 1024
    );
    let mut over = case["input"].clone();
    let action = over["actions"][0].clone();
    over["actions"].as_array_mut().unwrap().push(action);
    assert!(super::artifacts::validate_input(&over).is_err());
}
#[test]
fn artifact_mck_raw_expansion_is_aggregated_before_adapter_start() {
    let case = raw_generation_budget_case();
    let temp = tempfile::tempdir().unwrap();
    for (count, accepted) in [(4, true), (5, false)] {
        let cases = (0..count)
            .map(|index| {
                let mut case = case.clone();
                case["id"] = json!(format!("raw-budget-{index}"));
                case
            })
            .collect::<Vec<_>>();
        std::fs::write(
            temp.path().join("cases.json"),
            serde_json::to_vec(&json!({"formatVersion":"0.1.0-draft.28","cases":cases})).unwrap(),
        )
        .unwrap();
        assert_eq!(load(temp.path()).is_ok(), accepted, "{count} cases");
    }
}

#[test]
fn artifact_mck_saved_rpc_error_codes_require_exact_signed_i32() {
    let authored: Value = serde_json::from_str(include_str!(
        "../../../../spec/workbench/mck/draft.28/server/cases.json"
    ))
    .unwrap();
    let case = authored["cases"]
        .as_array()
        .unwrap()
        .iter()
        .find(|case| case["id"] == "numeric-negative-offset")
        .unwrap()
        .clone();
    let temp = tempfile::tempdir().unwrap();
    std::fs::write(
        temp.path().join("cases.json"),
        serde_json::to_vec(&json!({"formatVersion":"0.1.0-draft.28","cases":[case]})).unwrap(),
    )
    .unwrap();
    let corpus = load(temp.path()).unwrap();
    let answers = corpus
        .cases
        .iter()
        .map(|case| serde_json::to_value(&case.expected).unwrap())
        .collect();
    let baseline = execute(&corpus, &mut AuthoredEvidence(answers));
    assert!(baseline.qualified);
    for (token, valid, matches) in [
        ("2147483648", false, false),
        ("-2147483649", false, false),
        ("-32602.0", true, true),
        ("-32602e0", true, true),
        ("2147483647", true, false),
        ("-2147483648", true, false),
        ("-2147483648.0", true, false),
        ("-0.0", true, false),
        ("-32602.5", false, false),
        ("1e-9999", false, false),
        ("-1e-9999", false, false),
    ] {
        let mut forged = serde_json::to_value(&baseline).unwrap();
        let raw = forged["records"][0]["observed"]["value"]["events"][4]["reply"]
            .as_str()
            .unwrap();
        assert!(raw.contains("\"code\":-32602"));
        forged["records"][0]["observed"]["value"]["events"][4]["reply"] =
            json!(raw.replacen("\"code\":-32602", &format!("\"code\":{token}"), 1));
        forged["records"][0]["result"] = json!(if matches { "pass" } else { "fail" });
        forged["qualified"] = json!(matches);
        let checked = Report::from_json(&serde_json::to_string(&forged).unwrap())
            .and_then(|report| check_report(temp.path(), &report));
        assert_eq!(checked.is_ok(), valid, "token {token}: {checked:?}");
    }
}
