//! Real actual52 failure controls. Proposed instance-only parent ACK cut,
//! only after a real business literal is cached and its unique ticket exists.
use super::*;
use crate::commands::ui::installed_mck::TestConsumerAckCutoff;

fn ack_loss(target: Target, cutoff: TestConsumerAckCutoff, kind: &str) {
    let mut fixture = Actual52::prepare(target);
    let mut adapter = fixture.adapter().test_with_consumer_ack_cutoff(cutoff);
    let report = fixture.run(&mut adapter);
    // These diagnostics come from the actual per-instance cut and consuming
    // terminal transfer. They never stand in for process/readers/host joins.
    assert_eq!(adapter.test_consumer_ack_cut_count(), 1);
    let usage = adapter
        .test_consumer_terminal_usage()
        .expect("actual terminal transfer reached");
    assert_eq!(usage.receiving_before, usage.receiving_after);
    assert_eq!(usage.decoder_before, usage.decoder_after);
    let raw = report.to_json();
    let saved: Value = serde_json::from_str(&raw).unwrap();
    assert_eq!(saved["formatVersion"], "0.1.0-draft.31");
    let first = json!({"phase":"installed-consumer","code":"io","message":"private consumer operation transport refused"});
    assert_eq!(
        saved["errors"][0], first,
        "actual write to shut down peer reports genuine I/O first"
    );
    let evidence = &saved["records"][0]["evidence"];
    assert_eq!(evidence["kind"], "attempt-failed");
    let partial = &evidence["consumerFailure"];
    assert_eq!(partial["kind"], "recorded");
    let process = &partial["process"];
    let record = &partial["operation"];
    assert_eq!(
        record["completion"],
        json!({"kind":"interrupted","firstFailure":first})
    );
    assert_eq!(
        record["association"]["processOrdinal"],
        process["processOrdinal"]
    );
    assert_eq!(process["command"], "publish");
    assert_eq!(process["actionIndex"], 8);
    assert_eq!(
        process["completion"]["kind"], "finished",
        "genuine joined process/readers, no fabricated exit0"
    );
    let (row, body) = fact(record, kind);
    if kind == "destination-commit-finished" {
        assert_eq!(
            body["fact"]["outcome"], "returned",
            "lost ACK does not erase an already returned commit fact"
        );
    }
    assert_eq!(row["delivery"]["kind"], "prefix");
    assert_eq!(row["delivery"]["written"], 0);
    assert!(row["delivery"]["total"].as_u64().unwrap() > 4);
    assert!(
        evidence.get("measurement").is_none(),
        "interrupted raw facts never become successful measurement"
    );
    assert_eq!(saved["qualified"], false);
    for row in &saved["records"].as_array().unwrap()[1..] {
        assert_eq!(
            row["evidence"],
            json!({"kind":"not-attempted","priorFailureIndex":0})
        );
    }
    check_report_configured(
        &fixture.kit,
        &Report::from_json(&raw).unwrap(),
        &fixture.configuration,
    )
    .expect("recorded genuine interrupted facts replay with exact failure/prefix, never qualify");
}
#[test]
#[ignore = "actual52 Node + independent host; requires private actual-retention ACK-cut hook"]
fn actual52_node_retains_release_fact_on_actual_lost_ack() {
    ack_loss(
        Target::Node,
        TestConsumerAckCutoff::Release,
        "release-accepted",
    );
}
#[test]
#[ignore = "actual52 Node + independent host; requires private actual-retention ACK-cut hook"]
fn actual52_node_retains_commit_fact_on_actual_lost_ack() {
    ack_loss(
        Target::Node,
        TestConsumerAckCutoff::Commit,
        "destination-commit-finished",
    );
}
#[test]
#[ignore = "actual52 native/C/helper + independent host; requires private actual-retention ACK-cut hook"]
fn actual52_native_retains_release_fact_on_actual_lost_ack() {
    ack_loss(
        Target::Native,
        TestConsumerAckCutoff::Release,
        "release-accepted",
    );
}
#[test]
#[ignore = "actual52 native/C/helper + independent host; requires private actual-retention ACK-cut hook"]
fn actual52_native_retains_commit_fact_on_actual_lost_ack() {
    ack_loss(
        Target::Native,
        TestConsumerAckCutoff::Commit,
        "destination-commit-finished",
    );
}
