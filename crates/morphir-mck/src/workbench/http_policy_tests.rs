use super::*;
use serde_json::json;

#[test]
fn http_client_attempt_ids_observe_utf16_identity_bounds() {
    let corpus: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../spec/workbench/mck/draft.24/cases.json"
    ))
    .unwrap();
    for (characters, valid) in [(64, true), (65, false)] {
        let mut input = corpus["cases"][0]["input"].clone();
        input["actions"] = json!([{"op":"initialize","id":"😀".repeat(characters)}]);
        assert_eq!(super::http_policy::Kit::Client.input(&input).is_ok(), valid);
    }
}

#[test]
fn http_policy_versions_negotiate_exact_operations_without_native_aliases() {
    for (draft, operation) in [
        (23, "validate-http-policy-boundary"),
        (24, "run-http-policy-client"),
        (25, "run-http-policy-provider"),
    ] {
        let version = format!("0.1.0-draft.{draft}");
        let caps = json!({"suite":"workbench","contractVersion":version,"binding":"independent-fixed","language":"test","operations":[operation],"formats":["json"]});
        Capabilities::parse(caps.clone(), &version).unwrap();
        for changed in [
            json!({"operations":["run-native-policy-client"]}),
            json!({"formats":["ion-text"]}),
            json!({"contractVersion":format!("{version}+build")}),
        ] {
            let mut bad = caps.clone();
            for (k, v) in changed.as_object().unwrap() {
                bad[k] = v.clone();
            }
            assert!(Capabilities::parse(bad, &version).is_err());
        }
    }
}

#[test]
fn http_fixed_corpora_and_saved_reports_are_checked_independently() {
    struct Fixed {
        caps: serde_json::Value,
        observations: std::collections::VecDeque<serde_json::Value>,
    }
    impl Testee for Fixed {
        fn exchange(&mut self, request: &serde_json::Value) -> Result<serde_json::Value, String> {
            assert!(request.get("expected").is_none() && request.get("caseId").is_none());
            Ok(if request["op"] == "capabilities" {
                self.caps.clone()
            } else {
                self.observations.pop_front().unwrap()
            })
        }
    }
    for (draft, operation) in [
        (23, "validate-http-policy-boundary"),
        (24, "run-http-policy-client"),
        (25, "run-http-policy-provider"),
    ] {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join(format!("../../spec/workbench/mck/draft.{draft}"));
        let raw: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(path.join("cases.json")).unwrap())
                .unwrap();
        let corpus = load(&path).unwrap();
        let version = format!("0.1.0-draft.{draft}");
        let mut fixed = Fixed {
            caps: json!({"suite":"workbench","contractVersion":version,"binding":"checker-infrastructure-only","language":"test","operations":[operation],"formats":["json"]}),
            observations: raw["cases"]
                .as_array()
                .unwrap()
                .iter()
                .map(|c| c["expected"].clone())
                .collect(),
        };
        let report = execute(&corpus, &mut fixed);
        assert!(report.qualified, "{draft}: {:?}", report.errors);
        let saved = Report::from_json(&report.to_json()).unwrap();
        check_report(&path, &saved).unwrap();
        let mut forged: serde_json::Value = serde_json::from_str(&report.to_json()).unwrap();
        forged["corpusHash"] = json!("0".repeat(64));
        assert!(check_report(&path, &Report::from_json(&forged.to_string()).unwrap()).is_err());
        let mut forged: serde_json::Value = serde_json::from_str(&report.to_json()).unwrap();
        match draft {
            23 => forged["records"][0]["observed"]["value"]["policy"] = json!("permissive"),
            24 => {
                forged["records"][0]["observed"]["value"]["acceptedPlans"][0]["admission"]["policy"] =
                    json!("permissive")
            }
            25 => {
                forged["records"][0]["observed"]["value"]["executions"][0]["plan"]["admission"]["policy"] =
                    json!("permissive")
            }
            _ => unreachable!(),
        }
        assert!(
            Report::from_json(&forged.to_string()).is_err()
                || check_report(&path, &Report::from_json(&forged.to_string()).unwrap()).is_err()
        );
    }
}

#[test]
fn http_provider_observations_preserve_identity_worker_and_terminal_invariants() {
    let raw: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../spec/workbench/mck/draft.25/cases.json"
    ))
    .unwrap();
    let good = &raw["cases"][0]["expected"]["value"];
    super::http_policy::Kit::Provider.projection(good).unwrap();
    for path in [
        "/executions/0/plan/planId",
        "/executions/0/receipt/identity/snapshotId",
        "/workers/exited",
        "/executions/0/receipt/outcomes/calls/0/outcome/value/value",
    ] {
        let mut bad = good.clone();
        *bad.pointer_mut(path).unwrap() = match path {
            "/executions/0/plan/planId" => json!("😀".repeat(65)),
            "/workers/exited" => json!(2),
            "/executions/0/receipt/outcomes/calls/0/outcome/value/value" => json!("042"),
            _ => json!("rebound"),
        };
        assert!(
            super::http_policy::Kit::Provider.projection(&bad).is_err(),
            "{path}"
        );
    }
    let mut duplicate = good.clone();
    duplicate["executions"]
        .as_array_mut()
        .unwrap()
        .push(good["executions"][0].clone());
    assert!(
        super::http_policy::Kit::Provider
            .projection(&duplicate)
            .is_err()
    );
}

#[test]
fn http_provider_opaque_submission_preserves_literal_private_marker_maps() {
    let mut raw: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../spec/workbench/mck/draft.25/cases.json"
    ))
    .unwrap();
    raw["cases"].as_array_mut().unwrap().truncate(1);
    raw["cases"][0]["input"]["submission"] = json!({"$serde_json::private::Number":"123"});
    let directory = tempfile::tempdir().unwrap();
    std::fs::write(directory.path().join("cases.json"), raw.to_string()).unwrap();
    let corpus = load(directory.path()).unwrap();
    assert!(corpus.cases[0].input["submission"].is_object());
    assert_eq!(
        corpus.cases[0].input["submission"]["$serde_json::private::Number"],
        "123"
    );
}
