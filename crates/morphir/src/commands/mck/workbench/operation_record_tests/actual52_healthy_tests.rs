//! Actual host + consumer52, not frozen014 or zero-business reference.
use super::*;

fn healthy(target: Target) {
    let mut fixture = Actual52::prepare(target);
    let mut adapter = fixture.adapter();
    let report = fixture.run(&mut adapter);
    let raw = report.to_json();
    let saved: Value = serde_json::from_str(&raw).unwrap();
    assert_eq!(saved["formatVersion"], "0.1.0-draft.31");
    assert_eq!(saved["qualified"], false);
    assert_eq!(
        saved["records"][0]["evidence"]["kind"],
        "client-process-measured"
    );
    let measurement = &saved["records"][0]["evidence"]["measurement"];
    assert_eq!(measurement["implementation"]["source"]["head"], SOURCE52);
    let record = &measurement["consumerObservation"];
    assert_eq!(record["kind"], "recorded");
    assert_eq!(record["completion"], json!({"kind":"drained"}));
    assert_eq!(record["association"]["actionIndex"], 8);
    assert_eq!(record["association"]["command"], "publish");
    let publish = measurement["processes"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|p| p["command"] == "publish")
        .collect::<Vec<_>>();
    assert_eq!(publish.len(), 1);
    assert_eq!(
        record["association"]["processOrdinal"],
        publish[0]["processOrdinal"]
    );
    assert_eq!(
        publish[0]["completion"],
        json!({"kind":"finished","exit":{"kind":"code","value":0}})
    );
    let outer = frames(record, "outer");
    let helper = frames(record, "transfer-helper");
    assert_eq!(
        (outer.len(), helper.len()),
        match target {
            Target::Node => (4, 3),
            Target::Native => (5, 3),
        }
    );
    for row in outer.iter().chain(helper) {
        assert_eq!(row["delivery"]["kind"], "written");
        assert!(row["delivery"]["total"].as_u64().unwrap() > 4);
    }
    for (field, kind) in [
        ("clientReleaseAcceptance", "release-accepted"),
        ("dynamicCommit", "destination-commit-finished"),
        ("dynamicScratchCleanup", "scratch-cleanup-finished"),
    ] {
        assert_eq!(measurement[field]["kind"], "observed");
        let (_, body) = fact(record, kind);
        assert_eq!(measurement[field]["frameRef"]["sequence"], body["sequence"]);
    }
    assert_eq!(measurement["host"]["source"]["kind"], "sealed-complete");
    assert_eq!(measurement["host"]["workers"]["kind"], "joined-cleanup");
    assert_eq!(
        saved["errors"],
        json!([{"phase":"observation","code":"expected-blocked","message":"expected workflow is explicitly blocked"}])
    );
    check_report_configured(
        &fixture.kit,
        &Report::from_json(&raw).unwrap(),
        &fixture.configuration,
    )
    .expect("actual measured31 integrity accepted, still unqualified");
    saved_operation_mutations::refuse_actual_mutations(&fixture, &saved);
    assert_eq!(
        std::fs::read_to_string(fixture.root.path().join("report.json")).unwrap(),
        raw
    );
}
#[test]
#[ignore = "requires root-owned exact52 explicit five inputs/V3; genuine host and consumer"]
fn actual52_node_exports_source_bound_operation_and_saved_measurement() {
    healthy(Target::Node);
}
#[test]
#[ignore = "requires root-owned exact52 explicit five inputs/V3; genuine C owner/helper/host"]
fn actual52_native_exports_source_bound_operation_and_saved_measurement() {
    healthy(Target::Native);
}
