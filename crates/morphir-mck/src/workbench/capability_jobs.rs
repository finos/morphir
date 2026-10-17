//! Closed immutable-job fixture infrastructure. Model, argument and supplied
//! completion source stay opaque; the production adapter owns planning/execution.
use serde_json::Value;
use std::sync::OnceLock;

fn schema_validator(schema: &str) -> jsonschema::Validator {
    let mut options = jsonschema::options();
    options.with_retriever(super::contract::OfflineOnly);
    for source in [
        include_str!("../../../../spec/workbench/schemas/value.schema.json"),
        include_str!("../../../../spec/workbench/schemas/outcome-value.schema.json"),
        include_str!("../../../../spec/workbench/draft.5/schemas/terminal-outcomes.schema.json"),
        include_str!("../../../../spec/workbench/draft.3/schemas/value-type.schema.json"),
        include_str!("../../../../spec/workbench/draft.3/schemas/definitions.schema.json"),
        include_str!("../../../../spec/workbench/draft.3/schemas/manifest.schema.json"),
        include_str!("../../../../spec/workbench/jobs/draft.1/schemas/identity.schema.json"),
        include_str!("../../../../spec/workbench/jobs/draft.1/schemas/receipt.schema.json"),
        include_str!("../../../../spec/workbench/jobs/draft.1/schemas/offer.schema.json"),
        include_str!("../../../../spec/workbench/job-plan/draft.1/schemas/plan.schema.json"),
        include_str!("../../../../spec/workbench/admission/draft.1/schemas/selection.schema.json"),
        include_str!("../../../../spec/workbench/draft.13/schemas/mck-input.schema.json"),
        include_str!(
            "../../../../spec/workbench/draft.13/schemas/capability-jobs-projection.schema.json"
        ),
        include_str!("../../../../spec/workbench/draft.13/schemas/mck-observation.schema.json"),
        include_str!("../../../../spec/workbench/draft.13/schemas/mck-capabilities.schema.json"),
    ] {
        let value: Value = serde_json::from_str(source).expect("capability jobs schema JSON");
        options.with_resource(
            value["$id"].as_str().expect("capability jobs schema id"),
            jsonschema::Resource::from_contents(value.clone())
                .expect("capability jobs schema resource"),
        );
    }
    options
        .build(&serde_json::from_str(schema).expect("capability jobs schema JSON"))
        .expect("capability jobs schema")
}

macro_rules! shape_validator {
    ($name:ident, $schema:literal) => {
        pub(super) fn $name(value: &Value) -> Result<(), String> {
            static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
            VALIDATOR
                .get_or_init(|| schema_validator(include_str!($schema)))
                .validate(value)
                .map_err(|e| {
                    format!(
                        "invalid capability jobs {} at {}: {e}",
                        stringify!($name),
                        e.instance_path
                    )
                })
        }
    };
}
shape_validator!(
    validate_corpus_shape,
    "../../../../spec/workbench/draft.13/schemas/mck-corpus.schema.json"
);
shape_validator!(
    validate_observation_shape,
    "../../../../spec/workbench/draft.13/schemas/mck-observation.schema.json"
);
shape_validator!(
    validate_report_shape,
    "../../../../spec/workbench/draft.13/schemas/mck-report.schema.json"
);
shape_validator!(
    validate_projection_shape,
    "../../../../spec/workbench/draft.13/schemas/capability-jobs-projection.schema.json"
);

pub(super) fn validate_input(value: &Value) -> Result<(), String> {
    super::contract::encoded_size(value, 1048576)?;
    Ok(())
}

pub(super) fn projection(value: &Value) -> Result<Value, String> {
    super::contract::encoded_size(value, super::contract::MAX_VALUE_BYTES)?;
    validate_projection_shape(value)?;
    if let Some(code) = value["failure"]["code"].as_str() {
        super::contract::identity(code, 128)?;
    }
    let mut projected = value.clone();
    let mut plans = std::collections::BTreeSet::new();
    let mut identities = std::collections::BTreeSet::new();
    for job in projected["jobs"]
        .as_array_mut()
        .expect("schema checked jobs")
    {
        let plan = &job["plan"];
        super::contract::identity(
            plan["planId"].as_str().expect("schema checked plan id"),
            128,
        )?;
        for field in ["hostId", "sessionId", "providerId", "jobId", "snapshotId"] {
            super::contract::identity(
                plan["identity"][field]
                    .as_str()
                    .expect("schema checked identity"),
                128,
            )?;
        }
        if plan["identity"] != job["receipt"]["identity"] {
            return Err("job plan and receipt identities differ".into());
        }
        let identity = ["hostId", "sessionId", "providerId", "jobId", "snapshotId"].map(|field| {
            plan["identity"][field]
                .as_str()
                .expect("schema checked identity")
                .to_owned()
        });
        if !plans.insert(
            plan["planId"]
                .as_str()
                .expect("schema checked plan id")
                .to_owned(),
        ) || !identities.insert(identity)
        {
            return Err("duplicate accepted job or plan identity".into());
        }
        if !job["receipt"]["outcomes"].is_null() {
            job["receipt"]["outcomes"] = super::outcomes::projection(&job["receipt"]["outcomes"])?;
        }
    }
    for observation in projected["observations"]
        .as_array()
        .expect("schema checked observations")
    {
        if let Some(code) = observation["code"].as_str() {
            super::contract::identity(code, 128)?;
        }
        if let Some(plan_id) = observation["view"]["planId"].as_str() {
            super::contract::identity(plan_id, 128)?;
        }
    }
    Ok(projected)
}
