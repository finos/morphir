//! Independent additive source-first review controls, frozen before repairs. No
//! runtime or original-role credit; original F01-F12 remain byte exact.
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
fn reviewed_capture_connection_owns_inventory_read_and_release() {
    let mut actual = data();
    for event in actual["host"]["events"]
        .as_array_mut()
        .unwrap()
        .iter_mut()
        .skip(18)
    {
        event["connection"] = json!(0);
    }
    assert_eq!(
        evaluate(&actual),
        ObservationError::InstalledClient(Fault::SocketAssociation)
    );
}
#[test]
fn reviewed_selected_project_must_exist_in_actual_workspace_open_snapshot() {
    let mut actual = data();
    for index in [5, 12] {
        change(
            &mut actual,
            &format!("/host/events/{index}/event/payload"),
            |reply| reply["result"]["snapshot"]["projects"] = json!([]),
        );
    }
    assert_eq!(
        evaluate(&actual),
        ObservationError::InstalledClient(Fault::SocketFrame)
    );
}
