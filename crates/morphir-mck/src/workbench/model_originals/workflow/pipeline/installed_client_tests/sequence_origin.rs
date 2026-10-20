//! Strict actual host sequence origin in synthetic UNIT DATA. No new socket,
//! authority, successful measurement or role. Existing bodies stay unchanged.
//! Child of existing pipeline::installed_client_tests::factual.
use super::*;

#[test]
fn q01_actual_one_based_sequence_and_prepared_keys_reach_unchanged_blocked_and_replay() {
    let data = unit_data();
    let events = data["host"]["events"].as_array().unwrap();
    assert_eq!(events.len(), 30);
    for (index, event) in events.iter().enumerate() {
        assert_eq!(event["sequence"], json!(index + 1));
    }
    assert_eq!(
        events[3]["event"]["preparedSequence"],
        events[2]["sequence"]
    );
    assert_eq!(evaluate(&data), ObservationError::ExpectedBlocked);
    replay(&blocked_report(&data)).unwrap();
}
#[test]
fn q02_legacy_zero_origin_and_shifted_references_are_not_compatibility() {
    let mut data = unit_data();
    for event in data["host"]["events"].as_array_mut().unwrap() {
        event["sequence"] = json!(event["sequence"].as_u64().unwrap() - 1);
        if event["event"]["kind"] == "send-outcome" {
            event["event"]["preparedSequence"] =
                json!(event["event"]["preparedSequence"].as_u64().unwrap() - 1);
        }
    }
    assert_factual(&data, InstalledClientFault::SocketOrder);
}
#[test]
fn q03_omitted_prefix_is_not_renormalized_and_omitted_auth_stays_forbidden() {
    let mut data = unit_data();
    data["host"]["events"].as_array_mut().unwrap().remove(0);
    assert_factual(&data, InstalledClientFault::SocketOrder);
    // Even rewriting the surviving keys to a contiguous1-based sequence
    // cannot invent the genuine authenticated-connection prefix.
    for event in data["host"]["events"].as_array_mut().unwrap() {
        event["sequence"] = json!(event["sequence"].as_u64().unwrap() - 1);
        if event["event"]["kind"] == "send-outcome" {
            event["event"]["preparedSequence"] =
                json!(event["event"]["preparedSequence"].as_u64().unwrap() - 1);
        }
    }
    assert_factual(&data, InstalledClientFault::SocketAssociation);
}
#[test]
fn q04_internal_gap_is_forbidden_even_outside_prepared_reference_key() {
    let mut data = unit_data();
    assert_eq!(
        data["host"]["events"][11]["event"]["kind"],
        json!("received-text")
    );
    data["host"]["events"][11]["sequence"] = json!(13);
    assert_factual(&data, InstalledClientFault::SocketOrder);
}
#[test]
fn q05_actual_event_order_cannot_be_rewritten_by_swapping_rows() {
    let mut data = unit_data();
    data["host"]["events"].as_array_mut().unwrap().swap(1, 2);
    assert_factual(&data, InstalledClientFault::SocketOrder);
}
#[test]
fn q06_prepared_reference_is_actual_key_not_private_vector_index() {
    let mut data = unit_data();
    assert_eq!(data["host"]["events"][2]["sequence"], json!(3));
    data["host"]["events"][3]["event"]["preparedSequence"] = json!(2);
    assert_factual(&data, InstalledClientFault::SocketOrder);
    let mut report: Value = serde_json::from_str(&blocked_report(&unit_data())).unwrap();
    report["records"][0]["evidence"]["measurement"]["host"]["events"][3]["event"]["preparedSequence"] =
        json!(2);
    let error = replay(&report.to_string()).unwrap_err();
    assert!(error.contains("saved first failure differs"), "{error}");
}
