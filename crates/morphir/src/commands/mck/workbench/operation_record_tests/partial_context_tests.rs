//! Source-first genuine partial source/host-prefix retention, not completion.
use super::*;
use crate::commands::ui::installed_mck::TestConsumerAckCutoff;
use sha2::{Digest, Sha256};
#[test]
#[ignore = "exact52 Node + real host/ACK cut; partial association is prefix DATA"]
fn actual52_lost_release_ack_retains_source_and_host_prefix_without_completion() {
    let mut fixture = Actual52::prepare(Target::Node);
    let mut adapter = fixture
        .adapter()
        .test_with_consumer_ack_cutoff(TestConsumerAckCutoff::Release);
    let report = fixture.run(&mut adapter);
    assert_eq!(adapter.test_consumer_ack_cut_count(), 1);
    let saved: Value = serde_json::from_str(&report.to_json()).unwrap();
    let partial = &saved["records"][0]["evidence"]["consumerFailure"];
    assert_eq!(
        partial["kind"], "recorded",
        "actual terminal owner must be retained first"
    );
    let context = &partial["context"];
    assert_eq!(context["kind"], "prefix");
    assert_eq!(context["implementation"]["kind"], "observed");
    assert_eq!(context["implementation"]["source"]["head"], SOURCE52);
    let host = &context["host"];
    assert_eq!(host["association"], "invocation-credential");
    for forbidden in ["source", "workers", "destination", "scratch", "coverage"] {
        assert!(
            host.get(forbidden).is_none(),
            "partial context cannot invent {forbidden} completion"
        );
    }
    let (_, body) = fact(&partial["operation"], "release-accepted");
    let binding = &body["fact"]["binding"];
    assert_eq!(host["selection"]["sessionId"], binding["sessionId"]);
    assert_eq!(
        host["selection"]["source"]["providerId"],
        binding["providerId"]
    );
    assert_eq!(
        host["selection"]["source"]["locator"],
        binding["sourceLocator"]
    );
    assert_eq!(host["selection"]["projectId"], binding["projectId"]);
    let events = host["events"].as_array().unwrap();
    let request = body["fact"]["requestId"]
        .as_str()
        .unwrap()
        .parse::<u64>()
        .unwrap();
    let mut received = 0;
    let mut prepared = 0;
    for row in events {
        if let Some(raw) = row["event"]["payload"].as_str() {
            let payload: Value = serde_json::from_str(raw).unwrap();
            if payload["id"].as_u64() == Some(request) {
                let hash = Sha256::digest(raw.as_bytes())
                    .iter()
                    .map(|byte| format!("{byte:02x}"))
                    .collect::<String>();
                match row["event"]["kind"].as_str() {
                    Some("received-text") => {
                        assert_eq!(body["fact"]["requestSha256"], hash);
                        received += 1;
                    }
                    Some("prepared-send") => {
                        assert_eq!(body["fact"]["replySha256"], hash);
                        prepared += 1;
                    }
                    _ => {}
                }
            }
        }
    }
    assert_eq!(
        (received, prepared),
        (1, 1),
        "real unique release request/result prefix"
    );
    assert_eq!(saved["qualified"], false);
}
