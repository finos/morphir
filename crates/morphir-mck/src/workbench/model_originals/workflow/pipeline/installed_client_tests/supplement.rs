//! Additive regression controls authored AFTER source-review repairs. No RED or
//! preimplementation chronology claimed; original F01-F12 remain byte exact.
use super::*;
use crate::workbench::model_originals::workflow::{
    Decode, installed_measurements::InstalledClientMeasurements,
    observation_check::InstalledClientFault as Fault,
};
use serde_json::{Value, json};
fn data() -> Value {
    serde_json::from_str(include_str!("factual_controls/unit-data.json")).unwrap()
}
fn evaluate(data: &Value) -> ObservationError {
    let source = source(CORPUS);
    let policy = policy(POLICY);
    let mut result = None;
    prepared_installed_client(
        &source,
        &policy,
        ReviewedSources::installed_client_selected(),
        |inventory, owners| {
            let document = owners.decode.literal_with_raw(&data.to_string()).unwrap().0;
            let actual =
                InstalledClientMeasurements::decode(&document, &mut owners.decode).unwrap();
            result = Some(
                inventory
                    .invocation()
                    .compiled_source()
                    .report_context()
                    .check_installed_process(&actual, &mut owners.comparison)
                    .unwrap_err(),
            );
            Ok(())
        },
    )
    .unwrap();
    result.unwrap()
}
fn change(data: &mut Value, path: &str, update: impl FnOnce(&mut Value)) {
    let field = data.pointer_mut(path).unwrap();
    let mut raw: Value = serde_json::from_str(field.as_str().unwrap()).unwrap();
    update(&mut raw);
    *field = Value::String(raw.to_string());
}
#[test]
fn supplemental_ready_record_metadata_is_checked_against_actual_adopted_bytes() {
    for key in ["byteLength", "sha256"] {
        let mut actual = data();
        change(&mut actual, "/host/events/16/event/payload", |reply| {
            let record = &mut reply["result"]["origin"]["record"];
            if key == "byteLength" {
                record[key] = json!(record[key].as_u64().unwrap() + 1)
            } else {
                record[key] = json!("0".repeat(64))
            }
        });
        assert_eq!(
            evaluate(&actual),
            ObservationError::InstalledClient(Fault::RecordAdoption)
        );
    }
    let mut actual = data();
    change(&mut actual, "/host/events/16/event/payload", |reply| {
        reply["result"]["origin"]["record"]["module"] = json!("foreign/module")
    });
    assert_eq!(
        evaluate(&actual),
        ObservationError::InstalledClient(Fault::SourceBinding)
    );
}
#[test]
fn supplemental_stdout_inventory_and_header_claims_match_actual_rpc() {
    for key in [
        "fileCount",
        "directoryCount",
        "sourceByteLength",
        "inventorySha256",
        "sourceFormatVersion",
    ] {
        let mut actual = data();
        change(&mut actual, "/processes/2/stdout/text", |claim| match key {
            "inventorySha256" => claim[key] = json!("0".repeat(64)),
            "sourceFormatVersion" => claim[key]["release"] = json!("99.0.0"),
            _ => claim[key] = json!(claim[key].as_u64().unwrap() + 1),
        });
        assert_eq!(
            evaluate(&actual),
            ObservationError::InstalledClient(Fault::ProcessClaims),
            "{key}"
        );
    }
}
#[test]
fn supplemental_connect_and_list_claims_are_correlated_to_selected_runtime_data() {
    let mut actual = data();
    change(&mut actual, "/processes/0/stdout/text", |claim| {
        claim["sources"][0]["providerId"] = json!("foreign-provider")
    });
    assert_eq!(
        evaluate(&actual),
        ObservationError::InstalledClient(Fault::ProcessClaims)
    );
    let mut actual = data();
    change(&mut actual, "/processes/1/stdout/text", |claim| {
        claim["projects"][0]["projectId"] = json!("foreign-project")
    });
    assert_eq!(
        evaluate(&actual),
        ObservationError::InstalledClient(Fault::ProcessClaims)
    );
}
#[test]
fn supplemental_complete_raw_census_cannot_omit_required_physical_parent() {
    for path in ["originals", "originals/notes"] {
        let mut actual = data();
        actual["destination"]["rawEntries"]
            .as_array_mut()
            .unwrap()
            .retain(|entry| entry["path"] != path);
        assert_eq!(
            evaluate(&actual),
            ObservationError::InstalledClient(Fault::DestinationEntries)
        );
    }
}
