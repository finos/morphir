use super::*;
use serde_json::{Value, json};

#[test]
fn native_policy_kits_negotiate_exactly_without_broadening_frozen_operations() {
    for (draft, operation) in [
        (20, "validate-native-policy-boundary"),
        (21, "run-native-policy-client"),
        (22, "run-native-policy-owner"),
    ] {
        let version = format!("0.1.0-draft.{draft}");
        let caps = json!({"suite":"workbench","contractVersion":version,"binding":"independent-fixed","language":"test","operations":[operation],"formats":["json"]});
        Capabilities::parse(caps.clone(), &version).unwrap();
        for other in [
            "0.1.0-draft.15",
            "0.1.0-draft.16",
            "0.1.0-draft.17",
            "0.1.0-draft.18",
            "0.1.0-draft.19",
        ] {
            let mut bad = caps.clone();
            bad["contractVersion"] = json!(other);
            assert!(Capabilities::parse(bad, other).is_err());
        }
        for (field, value) in [
            ("formats", json!(["ion-text"])),
            ("operations", json!([])),
            ("contractVersion", json!(format!("{version}+local"))),
        ] {
            let mut bad = caps.clone();
            bad[field] = value;
            assert!(Capabilities::parse(bad, &version).is_err());
        }
    }
}

#[test]
fn native_policy_boundary_keeps_source_opaque_and_rejects_fixture_extras() {
    let root = tempfile::tempdir().unwrap();
    let make = |input: Value| json!({"formatVersion":"0.1.0-draft.20","cases":[{"id":"opaque","operation":"validate-native-policy-boundary","format":"json","input":input,"expected":{"status":"ok","value":{"frameAccepted":true}}}]});
    for (input, valid) in [
        (
            json!({"kind":"request","encoding":"utf8","source":"not JSON"}),
            true,
        ),
        (
            json!({"kind":"request","encoding":"utf8","source":"{}","expectedOperation":"session.open"}),
            false,
        ),
        (
            json!({"kind":"reply","encoding":"utf8","source":"{}"}),
            false,
        ),
        (
            json!({"kind":"request","encoding":"hex","source":"f"}),
            false,
        ),
    ] {
        std::fs::write(root.path().join("cases.json"), make(input).to_string()).unwrap();
        assert_eq!(load(root.path()).is_ok(), valid);
    }
}

#[test]
fn native_policy_parent_owned_corpora_and_saved_reports_are_checked_independently() {
    struct Fixed {
        caps: Value,
        observations: std::collections::VecDeque<Value>,
    }
    impl Testee for Fixed {
        fn exchange(&mut self, request: &Value) -> Result<Value, String> {
            assert!(request.get("expected").is_none() && request.get("caseId").is_none());
            if request["op"] == "capabilities" {
                Ok(self.caps.clone())
            } else {
                Ok(self.observations.pop_front().unwrap())
            }
        }
    }
    for (draft, operation) in [
        (20, "validate-native-policy-boundary"),
        (21, "run-native-policy-client"),
        (22, "run-native-policy-owner"),
    ] {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join(format!("../../spec/workbench/mck/draft.{draft}"));
        let raw: Value =
            serde_json::from_str(&std::fs::read_to_string(path.join("cases.json")).unwrap())
                .unwrap();
        let corpus = load(&path).unwrap();
        let version = format!("0.1.0-draft.{draft}");
        let mut adapter = Fixed {
            caps: json!({"suite":"workbench","contractVersion":version,"binding":"checker-fixture","language":"test","operations":[operation],"formats":["json"]}),
            observations: raw["cases"]
                .as_array()
                .unwrap()
                .iter()
                .map(|c| {
                    let mut observed = c["expected"].clone();
                    if let Some(results) = observed
                        .get_mut("value")
                        .and_then(|v| v.get_mut("results"))
                        .and_then(Value::as_array_mut)
                    {
                        for result in results {
                            if let Some(allowed) = result["reply"]["effect"].as_array() {
                                result["reply"]["effect"] = allowed[0].clone();
                            }
                        }
                    }
                    observed
                })
                .collect(),
        };
        let report = execute(&corpus, &mut adapter);
        assert!(report.qualified, "{draft}: {:?}", report.errors);
        let saved = Report::from_json(&report.to_json()).unwrap();
        check_report(&path, &saved).unwrap();
        let mut forged: Value = serde_json::from_str(&report.to_json()).unwrap();
        forged["corpusHash"] = json!("0".repeat(64));
        assert!(check_report(&path, &Report::from_json(&forged.to_string()).unwrap()).is_err());
    }
}

#[test]
fn native_policy_observation_identity_bounds_and_inventory_uniqueness_are_preserved() {
    let raw: Value = serde_json::from_str(include_str!(
        "../../../../spec/workbench/mck/draft.21/cases.json"
    ))
    .unwrap();
    let good = raw["cases"]
        .as_array()
        .unwrap()
        .iter()
        .find(|case| {
            !case["expected"]["value"]["acceptedPlans"]
                .as_array()
                .unwrap()
                .is_empty()
        })
        .unwrap()["expected"]["value"]
        .clone();
    super::native_policy_client::projection(&good).unwrap();
    for duplicate in [true, false] {
        let mut bad = good.clone();
        if duplicate {
            let plan = bad["acceptedPlans"][0].clone();
            bad["acceptedPlans"].as_array_mut().unwrap().push(plan);
        } else {
            bad["acceptedPlans"][0]["planId"] = json!("😀".repeat(65));
        }
        assert!(super::native_policy_client::projection(&bad).is_err());
    }
}

#[test]
fn native_policy_inventory_does_not_rebind_an_execution_to_another_snapshot() {
    let raw: Value = serde_json::from_str(include_str!(
        "../../../../spec/workbench/mck/draft.21/cases.json"
    ))
    .unwrap();
    let mut projection = raw["cases"]
        .as_array()
        .unwrap()
        .iter()
        .find(|case| {
            !case["expected"]["value"]["acceptedPlans"]
                .as_array()
                .unwrap()
                .is_empty()
        })
        .unwrap()["expected"]["value"]
        .clone();
    let mut rebound = projection["acceptedPlans"][0].clone();
    rebound["identity"]["snapshotId"] = json!("different-snapshot");
    rebound["planId"] = json!("different-plan");
    projection["acceptedPlans"]
        .as_array_mut()
        .unwrap()
        .push(rebound);
    assert!(super::native_policy_client::projection(&projection).is_err());
}
