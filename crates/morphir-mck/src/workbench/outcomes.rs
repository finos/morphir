use std::collections::BTreeSet;
use std::sync::OnceLock;

use serde_json::Value;

use super::contract::{MAX_VALUE_BYTES, OfflineOnly, encoded_size, identity};

/// Admit only canonical observations. The runner never decodes an input envelope
/// or uses implementation output to author expectations or infer execution success.
pub(super) fn projection(value: &Value) -> Result<Value, String> {
    encoded_size(value, MAX_VALUE_BYTES)?;
    static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
    let validator = VALIDATOR.get_or_init(|| {
        let values: Value = serde_json::from_str(include_str!(
            "../../../../spec/workbench/schemas/value.schema.json"
        ))
        .expect("Workbench value schema JSON");
        let outcomes: Value = serde_json::from_str(include_str!(
            "../../../../spec/workbench/draft.5/schemas/terminal-outcomes.schema.json"
        ))
        .expect("Workbench terminal schema JSON");
        jsonschema::options()
            .with_retriever(OfflineOnly)
            .with_resource(
                values["$id"].as_str().expect("value schema id"),
                jsonschema::Resource::from_contents(values.clone()).expect("value schema resource"),
            )
            .build(&outcomes)
            .expect("Workbench terminal schema")
    });
    validator
        .validate(value)
        .map_err(|e| format!("invalid terminal projection at {}: {e}", e.instance_path))?;
    let mut projected = value.clone();
    let mut ids = BTreeSet::new();
    for call in projected["calls"]
        .as_array_mut()
        .expect("schema-checked calls")
    {
        let id = call["id"].as_str().expect("schema-checked id");
        identity(id, 128)?;
        if !ids.insert(id.to_owned()) {
            return Err("duplicate terminal call id".into());
        }
        let outcome = &mut call["outcome"];
        match outcome["status"].as_str().expect("schema-checked status") {
            "returned" => outcome["value"] = super::contract::projection(&outcome["value"])?,
            "failed" => failure(&outcome["failure"], false)?,
            "model-error" | "cancelled" => {}
            _ => unreachable!("schema-checked terminal"),
        }
    }
    if !projected["cleanup"].is_null() {
        failure(&projected["cleanup"], true)?;
    }
    Ok(projected)
}

fn failure(value: &Value, cleanup: bool) -> Result<(), String> {
    let code = value["code"].as_str().expect("schema-checked failure code");
    identity(code, 128)?;
    if value["message"]
        .as_str()
        .expect("schema-checked message")
        .encode_utf16()
        .count()
        > 512
    {
        return Err("failure message exceeds UTF-16 limit".into());
    }
    if !cleanup
        && matches!(
            code,
            "execution.cancelled"
                | "sdk.division_by_zero"
                | "sdk.invalid_number"
                | "sdk.out_of_range"
                | "sdk.invalid_comparison"
                | "sdk.unrepresentable_text"
        )
    {
        return Err("cancellation and SDK model errors require their own terminal variant".into());
    }
    Ok(())
}
