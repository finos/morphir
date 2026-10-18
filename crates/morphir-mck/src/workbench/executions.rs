use std::sync::OnceLock;

use serde_json::{Value, json};

use super::contract::{MAX_VALUE_BYTES, OfflineOnly, encoded_size, identity};

fn schema_validator(schema: &str) -> jsonschema::Validator {
    let mut options = jsonschema::options();
    options.with_retriever(OfflineOnly);
    for text in [
        include_str!("../../../../spec/workbench/schemas/value.schema.json"),
        include_str!("../../../../spec/workbench/draft.5/schemas/terminal-outcomes.schema.json"),
        include_str!(
            "../../../../spec/workbench/executions/0.2.0-draft.1/schemas/identity.schema.json"
        ),
        include_str!(
            "../../../../spec/workbench/executions/0.2.0-draft.1/schemas/receipt.schema.json"
        ),
        include_str!(
            "../../../../spec/workbench/draft.14/schemas/execution-projection.schema.json"
        ),
        include_str!("../../../../spec/workbench/draft.14/schemas/mck-observation.schema.json"),
        include_str!("../../../../spec/workbench/draft.14/schemas/mck-capabilities.schema.json"),
    ] {
        let value: Value = serde_json::from_str(text).expect("execution schema JSON");
        options.with_resource(
            value["$id"].as_str().expect("execution schema id"),
            jsonschema::Resource::from_contents(value.clone()).expect("execution schema resource"),
        );
    }
    let value: Value = serde_json::from_str(schema).expect("execution schema JSON");
    options.build(&value).expect("execution schema")
}

fn validate_shape(value: &Value, validator: &jsonschema::Validator) -> Result<(), String> {
    validator.validate(value).map_err(|error| {
        format!(
            "invalid execution shape at {}: {error}",
            error.instance_path
        )
    })
}

pub(super) fn validate_corpus_shape(value: &Value) -> Result<(), String> {
    static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
    validate_shape(
        value,
        VALIDATOR.get_or_init(|| {
            schema_validator(include_str!(
                "../../../../spec/workbench/draft.14/schemas/mck-corpus.schema.json"
            ))
        }),
    )
}

pub(super) fn validate_observation_shape(value: &Value) -> Result<(), String> {
    static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
    validate_shape(
        value,
        VALIDATOR.get_or_init(|| {
            schema_validator(include_str!(
                "../../../../spec/workbench/draft.14/schemas/mck-observation.schema.json"
            ))
        }),
    )
}

pub(super) fn validate_report_shape(value: &Value) -> Result<(), String> {
    static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
    validate_shape(
        value,
        VALIDATOR.get_or_init(|| {
            schema_validator(include_str!(
                "../../../../spec/workbench/draft.14/schemas/mck-report.schema.json"
            ))
        }),
    )
}

/// Validate literal observations only. Trace input stays opaque to the shared
/// runner; independent fixed expectations establish transition behavior.
pub(super) fn projection(value: &Value) -> Result<Value, String> {
    encoded_size(value, MAX_VALUE_BYTES)?;
    static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
    validate_shape(
        value,
        VALIDATOR.get_or_init(|| {
            schema_validator(include_str!(
                "../../../../spec/workbench/draft.14/schemas/execution-projection.schema.json"
            ))
        }),
    )?;
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
