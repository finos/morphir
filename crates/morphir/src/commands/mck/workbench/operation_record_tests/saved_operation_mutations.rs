//! Pure test mutations only AFTER a real source-bound healthy report is accepted.
//! These values cannot issue process, source, endpoint, ACK or comparison owners.
use super::*;
const MEASUREMENT: &str = "/records/0/evidence/measurement";
const RECORD: &str = "/records/0/evidence/measurement/consumerObservation";

pub(super) fn refuse_actual_mutations(fixture: &Actual52, measured: &Value) {
    for (name, suffix, value) in [
        (
            "foreign-process",
            "/association/processOrdinal",
            json!(u64::MAX),
        ),
        ("wrong-action", "/association/actionIndex", json!(5)),
        ("clock-reversed", "/clock/endNs", json!("0")),
        ("foreign-role", "/endpoints/1/role", json!("outer")),
        (
            "close-not-drain",
            "/endpoints/0/terminal",
            json!({"kind":"close-ack-written"}),
        ),
    ] {
        let mut changed = measured.clone();
        *changed
            .pointer_mut(&format!("{RECORD}{suffix}"))
            .expect(name) = value;
        refuse(fixture, &changed, name);
    }
    for (name, field, value) in [
        (
            "missing-release",
            "clientReleaseAcceptance",
            json!("unobserved"),
        ),
        ("missing-commit", "dynamicCommit", json!("unobserved")),
        (
            "missing-cleanup",
            "dynamicScratchCleanup",
            json!("unobserved"),
        ),
    ] {
        let mut changed = measured.clone();
        *changed
            .pointer_mut(&format!("{MEASUREMENT}/{field}"))
            .expect(name) = value;
        refuse(fixture, &changed, name);
    }
    let mut changed = measured.clone();
    let delivery = changed
        .pointer_mut(&format!("{RECORD}/endpoints/0/frames/0/delivery"))
        .unwrap();
    let total = delivery["total"].clone();
    *delivery = json!({"kind":"prefix","written":0,"total":total});
    refuse(fixture, &changed, "ack-not-written");
    for (name, kind, member, value) in [
        (
            "release-request-hash",
            "release-accepted",
            "requestSha256",
            json!("0".repeat(64)),
        ),
        (
            "release-reply-hash",
            "release-accepted",
            "replySha256",
            json!("0".repeat(64)),
        ),
        (
            "commit-outcome",
            "destination-commit-finished",
            "outcome",
            json!("raised"),
        ),
        (
            "cleanup-outcome",
            "scratch-cleanup-finished",
            "outcome",
            json!("raised"),
        ),
    ] {
        let mut changed = measured.clone();
        let endpoints = changed
            .pointer_mut(&format!("{RECORD}/endpoints"))
            .unwrap()
            .as_array_mut()
            .unwrap();
        let mut found = 0;
        for endpoint in endpoints {
            for row in endpoint["frames"].as_array_mut().unwrap() {
                let mut body: Value =
                    serde_json::from_str(row["literal"].as_str().unwrap()).unwrap();
                if body["kind"] == "fact" && body["fact"]["kind"] == kind {
                    body["fact"][member] = value.clone();
                    row["literal"] = body.to_string().into();
                    found += 1;
                }
            }
        }
        assert_eq!(found, 1, "one real cached fact prerequisite");
        refuse(fixture, &changed, name);
    }
    for (name, suffix, value) in [
        ("future-record", "/version", json!("0.1.0-draft.2")),
        ("unknown-record-key", "/unexpected", json!(true)),
    ] {
        let mut changed = measured.clone();
        if suffix == "/unexpected" {
            changed.pointer_mut(RECORD).unwrap()["unexpected"] = value;
        } else {
            *changed.pointer_mut(&format!("{RECORD}{suffix}")).unwrap() = value;
        }
        let report = Report::from_json(&changed.to_string()).expect("raw envelope stays valid");
        assert_eq!(
            check_report_configured(&fixture.kit, &report, &fixture.configuration),
            Err("saved report decode refused".to_owned()),
            "strict configured record reader cause {name}"
        );
    }
    let mut disabled: Value = serde_json::from_str(&fixture.policy_text).unwrap();
    disabled
        .as_object_mut()
        .unwrap()
        .remove("consumerObservation");
    let disabled = RunConfiguration::from_json(&disabled.to_string()).unwrap();
    assert!(
        check_report_configured(
            &fixture.kit,
            &Report::from_json(&measured.to_string()).unwrap(),
            &disabled
        )
        .is_err()
    );
}
fn refuse(fixture: &Actual52, changed: &Value, name: &str) {
    match Report::from_json(&changed.to_string()) {
        Err(_) => (),
        Ok(report) => assert!(
            check_report_configured(&fixture.kit, &report, &fixture.configuration).is_err(),
            "actual report mutation must refuse: {name}"
        ),
    }
}
