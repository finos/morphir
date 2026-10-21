//! Actual failed-prefix DATA and cause-specific source/host correlation controls.
mod invariants;
use super::*;
use crate::workbench::model_originals::workflow::pipeline::installed::adapter::processes::StoredConsumerPartial;
fn actual_partial() -> Value {
    genuine(
        include_str!("../consumer_operation_controls/node-release-ack-loss.json"),
        "bffb37b6617943a773f25e791da7f7bd3603d4d384e9c4bc8919bc9a8f775927",
    )
}
fn raw(report: &mut Value) -> &mut Value {
    &mut report["records"][0]["evidence"]["consumerFailure"]
}
fn evaluate(report: &Value) -> Result<(), ObservationError> {
    let source = source(CORPUS);
    let configuration: Value = serde_json::from_str(CONFIGURATION).unwrap();
    let policy = policy(&configuration["checker"].to_string());
    let text = report["records"][0]["evidence"]["consumerFailure"].to_string();
    let mut result = None;
    prepared_installed_client(
        &source,
        &policy,
        ReviewedSources::installed_client_selected(),
        |inventory, owners| {
            let document = owners.decode.literal_with_raw(&text).unwrap().0;
            let actual = StoredConsumerPartial::decode(&document, &mut owners.decode)
                .expect("strict actual partial DATA shape");
            let invocation = inventory.invocation();
            result = Some(actual.check(
                invocation.compiled_source().installed().unwrap(),
                &mut owners.comparison,
            ));
            Ok(())
        },
    )
    .unwrap();
    result.unwrap()
}
fn exact(report: &Value, expected: &str) {
    assert_eq!(
        format!(
            "{:?}",
            evaluate(report).expect_err("unverified partial mutation")
        ),
        expected
    )
}
#[test]
fn actual_failed_prefix_is_consistent_without_completed_source_or_worker_claims() {
    evaluate(&actual_partial()).unwrap();
}
#[test]
fn partial_operation_cannot_reference_an_unrelated_process() {
    let mut report = actual_partial();
    raw(&mut report)["operation"]["association"]["processOrdinal"] = json!(u64::MAX);
    exact(&report, "InstalledClient(ConsumerAssociation)");
}
#[test]
fn partial_source_census_requires_its_actual_digest() {
    let mut report = actual_partial();
    raw(&mut report)["context"]["implementation"]["source"]["sha256"] = json!("0".repeat(64));
    exact(&report, "InstalledClient(ImplementationDigest)");
}
#[test]
fn partial_release_binds_the_parent_selected_session() {
    let mut report = actual_partial();
    raw(&mut report)["context"]["host"]["selection"]["sessionId"] = json!("foreign-session");
    exact(&report, "InstalledClient(ConsumerRelease)");
}
#[test]
fn partial_retained_release_still_requires_the_actual_reply_hash() {
    let mut report = actual_partial();
    let mut found = 0;
    for endpoint in raw(&mut report)["operation"]["endpoints"]
        .as_array_mut()
        .unwrap()
    {
        for row in endpoint["frames"].as_array_mut().unwrap() {
            let mut body: Value = serde_json::from_str(row["literal"].as_str().unwrap()).unwrap();
            if body["kind"] == "fact" && body["fact"]["kind"] == "release-accepted" {
                body["fact"]["replySha256"] = json!("0".repeat(64));
                row["literal"] = body.to_string().into();
                found += 1;
            }
        }
    }
    assert_eq!(found, 1);
    exact(&report, "InstalledClient(ConsumerRelease)");
}
#[test]
fn partial_business_ack_is_not_a_retained_close() {
    let mut report = actual_partial();
    let mut found = 0;
    for endpoint in raw(&mut report)["operation"]["endpoints"]
        .as_array_mut()
        .unwrap()
    {
        if endpoint["role"] == "transfer-helper" {
            assert_eq!(endpoint["terminal"]["kind"], "receiving");
            endpoint["terminal"] = json!({"kind":"close-retained"});
            found += 1;
        }
    }
    assert_eq!(found, 1);
    exact(&report, "InstalledClient(ConsumerTranscript)");
}
