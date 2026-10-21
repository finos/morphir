//! Request IDs belong to a connection, never to the whole host transcript.
use super::*;
fn release_id(report: &Value) -> u64 {
    report.pointer(MEASUREMENT).unwrap()["clientReleaseAcceptance"]["requestId"]
        .as_str()
        .unwrap()
        .parse()
        .unwrap()
}
#[test]
fn earlier_connection_may_reuse_the_selected_release_id_for_initialize() {
    let mut report = node();
    let release = release_id(&report);
    let mut earlier = None;
    let mut changed = 0;
    for event in measurement(&mut report)["host"]["events"]
        .as_array_mut()
        .unwrap()
    {
        let kind = event["event"]["kind"].as_str().unwrap().to_owned();
        if !matches!(kind.as_str(), "received-text" | "prepared-send") {
            continue;
        }
        let mut payload: Value =
            serde_json::from_str(event["event"]["payload"].as_str().unwrap()).unwrap();
        if earlier.is_none() && payload["method"] == "morphir.session.initialize" {
            earlier = Some((
                event["connection"].as_u64().unwrap(),
                payload["id"].as_u64().unwrap(),
            ));
        }
        if let Some((connection, id)) = earlier
            && event["connection"].as_u64() == Some(connection)
            && payload["id"].as_u64() == Some(id)
        {
            payload["id"] = json!(release);
            event["event"]["payload"] = payload.to_string().into();
            changed += 1;
        }
    }
    assert_eq!(
        changed, 2,
        "one actual earlier initialize request and prepared reply"
    );
    exact(&report, "ExpectedBlocked");
}
#[test]
fn selected_release_connection_still_requires_a_release_method() {
    let mut report = node();
    let release = release_id(&report);
    let mut changed = 0;
    for event in measurement(&mut report)["host"]["events"]
        .as_array_mut()
        .unwrap()
    {
        if event["event"]["kind"] != "received-text" {
            continue;
        }
        let mut payload: Value =
            serde_json::from_str(event["event"]["payload"].as_str().unwrap()).unwrap();
        if payload["id"].as_u64() == Some(release)
            && payload["method"] == "morphir.model-originals.release"
        {
            payload["method"] = json!("morphir.session.initialize");
            event["event"]["payload"] = payload.to_string().into();
            changed += 1;
        }
    }
    assert_eq!(changed, 1, "one actual selected release request");
    exact(&report, "InstalledClient(SocketFrame)");
}
#[test]
fn selected_connection_may_reuse_a_completed_initialize_id_for_release() {
    let mut report = node();
    let release = release_id(&report);
    let events = measurement(&mut report)["host"]["events"]
        .as_array_mut()
        .unwrap();
    let connection = events
        .iter()
        .find_map(|event| {
            if event["event"]["kind"] != "received-text" {
                return None;
            }
            let body: Value =
                serde_json::from_str(event["event"]["payload"].as_str().unwrap()).unwrap();
            (body["method"] == "morphir.model-originals.release")
                .then(|| event["connection"].as_u64().unwrap())
        })
        .unwrap();
    let mut initialize_id = None;
    let mut changed = 0;
    for event in events {
        if event["connection"].as_u64() != Some(connection) {
            continue;
        }
        if !matches!(
            event["event"]["kind"].as_str(),
            Some("received-text" | "prepared-send")
        ) {
            continue;
        }
        let mut body: Value =
            serde_json::from_str(event["event"]["payload"].as_str().unwrap()).unwrap();
        if body["method"] == "morphir.session.initialize" {
            initialize_id = body["id"].as_u64();
        }
        if initialize_id.is_some() && body["id"].as_u64() == initialize_id {
            body["id"] = json!(release);
            event["event"]["payload"] = body.to_string().into();
            changed += 1;
        }
    }
    assert_eq!(
        changed, 2,
        "one completed initialize request/reply on selected connection"
    );
    exact(&report, "ExpectedBlocked");
}
