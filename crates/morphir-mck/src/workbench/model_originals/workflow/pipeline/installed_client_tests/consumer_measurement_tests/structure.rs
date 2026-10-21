//! Additive DATA controls from the same byte-exact actual52 reports.
use super::*;
fn change_outer_close(report: &mut Value, change: impl FnOnce(&mut Value)) {
    let mut change = Some(change);
    let mut found = 0;
    for endpoint in record(report)["endpoints"].as_array_mut().unwrap() {
        if endpoint["role"] != "outer" {
            continue;
        }
        for row in endpoint["frames"].as_array_mut().unwrap() {
            let mut body: Value = serde_json::from_str(row["literal"].as_str().unwrap()).unwrap();
            if body["kind"] == "close" {
                change.take().unwrap()(&mut body);
                row["literal"] = body.to_string().into();
                found += 1;
            }
        }
    }
    assert_eq!(found, 1);
}
fn started() -> Value {
    json!({"kind":"started","wait":{"kind":"waited","rawStatus":"0"},"stdout":{"kind":"owned","read":{"kind":"complete","byteLength":"1"},"disposal":{"kind":"disposed"}},"stderr":{"kind":"owned","read":{"kind":"complete","byteLength":"0"},"disposal":{"kind":"disposed"}}})
}
#[test]
fn issued_clock_requires_the_selected_actual_runtime_bytes() {
    let mut report = node();
    measurement(&mut report)["implementation"]["runtime"]["sha256"] = json!("0".repeat(64));
    exact(&report, "InstalledClient(ConsumerClock)");
}
#[test]
fn node_outer_close_cannot_claim_a_delegated_helper() {
    let mut report = node();
    change_outer_close(&mut report, |close| close["helper"] = started());
    exact(&report, "InstalledClient(ConsumerAssociation)");
}
#[test]
fn native_outer_close_cannot_claim_in_process_helper() {
    let mut report = native();
    change_outer_close(&mut report, |close| {
        close["helper"] = json!({"kind":"in-process"})
    });
    exact(&report, "InstalledClient(ConsumerAssociation)");
}
#[test]
fn native_helper_started_binds_the_selected_program() {
    let mut report = native();
    let mut found = 0;
    for endpoint in record(&mut report)["endpoints"].as_array_mut().unwrap() {
        for row in endpoint["frames"].as_array_mut().unwrap() {
            let mut body: Value = serde_json::from_str(row["literal"].as_str().unwrap()).unwrap();
            if body["kind"] == "helper-started" {
                body["launch"]["program"] =
                    json!({"kind":"unix-bytes","bytes":{"kind":"utf8","text":"/foreign/node"}});
                row["literal"] = body.to_string().into();
                found += 1;
            }
        }
    }
    assert_eq!(found, 1);
    exact(&report, "InstalledClient(ConsumerAssociation)");
}
#[test]
fn healthy_native_helper_wait_must_support_the_returned_business_facts() {
    let mut report = native();
    change_outer_close(&mut report, |close| {
        close["helper"]["wait"]["rawStatus"] = json!("256")
    });
    exact(&report, "InstalledClient(ConsumerHelper)");
}
#[test]
fn healthy_native_helper_short_eof_is_not_complete_output() {
    let mut report = native();
    change_outer_close(&mut report, |close| {
        close["helper"]["stdout"]["read"]["kind"] = json!("short-read")
    });
    exact(&report, "InstalledClient(ConsumerHelper)");
}
#[test]
fn healthy_native_helper_disposal_failure_is_not_a_joined_success() {
    let mut report = native();
    change_outer_close(&mut report, |close| {
        close["helper"]["stdout"]["disposal"] =
            json!({"kind":"failed","operation":"close","errorCode":"9"})
    });
    exact(&report, "InstalledClient(ConsumerHelper)");
}
#[test]
fn healthy_close_counts_correlate_to_its_actual_fact_rows() {
    let mut report = node();
    change_outer_close(&mut report, |close| close["startedFactFrames"] = json!(1));
    exact(&report, "InstalledClient(ConsumerTranscript)");
}
#[test]
fn written_ack_size_is_the_unique_sequence_encoding() {
    let mut report = node();
    record(&mut report)["endpoints"][0]["frames"][0]["delivery"]["total"] = json!(61);
    exact(&report, "InstalledClient(ConsumerTranscript)");
}
