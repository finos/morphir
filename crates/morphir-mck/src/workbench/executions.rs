use std::sync::OnceLock;

use serde_json::{Value, json};

use super::contract::{MAX_VALUE_BYTES, OfflineOnly, encoded_size, identity};

/// Admit canonical observations only. Execution inputs and actions remain opaque to
/// the shared runner; independent fixed goldens establish transition behavior.
pub(super) fn projection(value: &Value) -> Result<Value, String> {
    encoded_size(value, MAX_VALUE_BYTES)?;
    static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
    let validator = VALIDATOR.get_or_init(|| {
        let resources = [
            include_str!("../../../../spec/workbench/schemas/value.schema.json"),
            include_str!(
                "../../../../spec/workbench/draft.5/schemas/terminal-outcomes.schema.json"
            ),
            include_str!(
                "../../../../spec/workbench/executions/0.2.0-draft.1/schemas/identity.schema.json"
            ),
            include_str!(
                "../../../../spec/workbench/executions/0.2.0-draft.1/schemas/receipt.schema.json"
            ),
        ];
        let mut options = jsonschema::options();
        options.with_retriever(OfflineOnly);
        for text in resources {
            let resource: Value = serde_json::from_str(text).expect("Workbench schema JSON");
            options.with_resource(
                resource["$id"].as_str().expect("Workbench schema id"),
                jsonschema::Resource::from_contents(resource.clone())
                    .expect("Workbench schema resource"),
            );
        }
        let schema: Value = serde_json::from_str(include_str!(
            "../../../../spec/workbench/draft.14/schemas/execution-projection.schema.json"
        ))
        .expect("Workbench execution projection schema JSON");
        options
            .build(&schema)
            .expect("Workbench execution projection schema")
    });
    validator
        .validate(value)
        .map_err(|e| format!("invalid execution projection at {}: {e}", e.instance_path))?;
    for field in [
        "hostId",
        "sessionId",
        "providerId",
        "executionId",
        "snapshotId",
    ] {
        identity(
            value["identity"][field]
                .as_str()
                .expect("schema-checked execution identity"),
            128,
        )?;
    }
    if value["identity"] != value["receipt"]["identity"] {
        return Err("execution projection and receipt identities differ".into());
    }
    let receipt = &value["receipt"];
    let final_view = json!({
        "sequence":receipt["sequence"], "state":receipt["state"],
        "cancelRequested":receipt["cancelRequested"], "connected":value["connected"],
        "cancelAction":value["cancelAction"]
    });
    check_view(&final_view)?;
    let observations = value["observations"]
        .as_array()
        .expect("schema-checked observations");
    for observation in observations {
        check_view(&observation["view"])?;
        if observation["status"] == "invalid" {
            identity(
                observation["code"].as_str().expect("schema-checked code"),
                128,
            )?;
        }
    }
    if let Some(last) = observations.last()
        && last["view"] != final_view
    {
        return Err(
            "final execution observation view differs from final receipt and local state".into(),
        );
    }
    let mut projected = value.clone();
    if !receipt["outcomes"].is_null() {
        projected["receipt"]["outcomes"] = super::outcomes::projection(&receipt["outcomes"])?;
    }
    Ok(projected)
}

/// These are consistency checks on one published view, not a transition reducer.
fn check_view(view: &Value) -> Result<(), String> {
    let state = view["state"].as_str().expect("schema-checked state");
    let connected = view["connected"]
        .as_bool()
        .expect("schema-checked connection");
    let requested = view["cancelRequested"]
        .as_bool()
        .expect("schema-checked acknowledgement");
    let action = view["cancelAction"]
        .as_str()
        .expect("schema-checked cancel action");
    let consistent = match action {
        "already-terminal" => state == "terminal",
        "disconnected" => state != "terminal" && !connected,
        "send" => state != "terminal" && connected && !requested,
        "pending" => state != "terminal" && connected && requested,
        "unavailable" => state != "terminal" && connected && !requested,
        _ => unreachable!("schema-checked cancel action"),
    };
    if !consistent || (state == "terminal" && action != "already-terminal") {
        return Err("execution view has contradictory state and cancellation action".into());
    }
    Ok(())
}
