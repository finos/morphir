//! Shared HTTP fixture and observation infrastructure. Request bytes, model source,
//! authentication and execution decisions belong to the production adapter.
use serde_json::{Value, json};
use std::collections::BTreeSet;
use std::sync::OnceLock;

#[derive(Clone, Copy)]
pub(super) enum Kit {
    Boundary,
    Client,
    Provider,
}

impl Kit {
    fn draft(self) -> u8 {
        match self {
            Self::Boundary => 23,
            Self::Client => 24,
            Self::Provider => 25,
        }
    }
    fn validators(self) -> &'static Validators {
        static BOUNDARY: OnceLock<Validators> = OnceLock::new();
        static CLIENT: OnceLock<Validators> = OnceLock::new();
        static PROVIDER: OnceLock<Validators> = OnceLock::new();
        match self {
            Self::Boundary => BOUNDARY.get_or_init(|| Validators::new(self)),
            Self::Client => CLIENT.get_or_init(|| Validators::new(self)),
            Self::Provider => PROVIDER.get_or_init(|| Validators::new(self)),
        }
    }
    pub(super) fn corpus(self, value: &Value) -> Result<(), String> {
        self.validators().check(&self.validators().corpus, value)
    }
    pub(super) fn observation(self, value: &Value) -> Result<(), String> {
        self.validators()
            .check(&self.validators().observation, value)
    }
    pub(super) fn report(self, value: &Value) -> Result<(), String> {
        self.validators().check(&self.validators().report, value)
    }
    pub(super) fn input(self, value: &Value) -> Result<(), String> {
        super::contract::encoded_size(value, 1_048_576)?;
        self.validators().check(&self.validators().input, value)?;
        match self {
            Self::Boundary => {
                let mut infrastructure = value.as_object().expect("checked object").clone();
                infrastructure.remove("kind");
                infrastructure.remove("context");
                super::native_frames::validate_input(&Value::Object(infrastructure))?;
            }
            Self::Client => {
                let mut calls = BTreeSet::new();
                let mut held = BTreeSet::new();
                for call in value["invocations"]
                    .as_array()
                    .expect("checked invocations")
                {
                    let id = call["id"].as_str().expect("checked id");
                    super::contract::identity(id, 128)?;
                    if !calls.insert(id) {
                        return Err("duplicate HTTP client invocation id".into());
                    }
                    if call["held"] == true {
                        held.insert(id);
                    }
                }
                let mut attempts = BTreeSet::new();
                let mut delivered = BTreeSet::new();
                for action in value["actions"].as_array().expect("checked actions") {
                    if let Some(id) = action["id"].as_str() {
                        super::contract::identity(id, 128)?;
                        if !attempts.insert(id) {
                            return Err("duplicate HTTP client attempt id".into());
                        }
                    }
                    if let Some(id) = action["call"].as_str()
                        && (!held.contains(id) || !delivered.insert(id))
                    {
                        return Err("invalid HTTP client delivery reference".into());
                    }
                }
            }
            Self::Provider => {
                let submissions = value["actions"]
                    .as_array()
                    .expect("checked actions")
                    .iter()
                    .filter(|a| matches!(a["op"].as_str(), Some("submit" | "submit-lost-reply")))
                    .count();
                if submissions > 4 {
                    return Err("HTTP provider fixture exceeds four submit attempts".into());
                }
            }
        }
        Ok(())
    }
    pub(super) fn projection(self, value: &Value) -> Result<Value, String> {
        super::contract::encoded_size(value, super::contract::MAX_VALUE_BYTES)?;
        self.validators()
            .check(&self.validators().projection, value)?;
        super::native_policy_owner::check_integer_tokens(value)?;
        match self {
            Self::Boundary => {}
            Self::Client => super::native_policy_client::validate_plans(value)?,
            Self::Provider => {
                let plans: Vec<Value> = value["executions"]
                    .as_array()
                    .expect("checked executions")
                    .iter()
                    .map(|execution| execution["plan"].clone())
                    .collect();
                super::native_policy_client::validate_plans(&json!({"acceptedPlans":plans}))?;
                for execution in value["executions"].as_array().expect("checked executions") {
                    if execution["plan"]["identity"] != execution["receipt"]["identity"] {
                        return Err("HTTP plan and receipt identities differ".into());
                    }
                    if !execution["receipt"]["outcomes"].is_null() {
                        super::outcomes::projection(&execution["receipt"]["outcomes"])?;
                    }
                }
                let workers = &value["workers"];
                if workers["exited"].as_u64() > workers["started"].as_u64()
                    || workers["policies"]
                        .as_array()
                        .expect("checked policies")
                        .len() as u64
                        != workers["started"].as_u64().expect("checked started")
                {
                    return Err("invalid HTTP worker observation inventory".into());
                }
            }
        }
        Ok(value.clone())
    }
}

struct Validators {
    corpus: jsonschema::Validator,
    input: jsonschema::Validator,
    projection: jsonschema::Validator,
    observation: jsonschema::Validator,
    report: jsonschema::Validator,
}
impl Validators {
    fn check(&self, validator: &jsonschema::Validator, value: &Value) -> Result<(), String> {
        validator.validate(value).map_err(|e| {
            format!(
                "invalid HTTP MCK infrastructure at {}: {e}",
                e.instance_path
            )
        })
    }
    fn new(kit: Kit) -> Self {
        let schemas=[
            include_str!("../../../../spec/workbench/schemas/value.schema.json"),
            include_str!("../../../../spec/workbench/schemas/outcome-value.schema.json"),
            include_str!("../../../../spec/workbench/draft.5/schemas/terminal-outcomes.schema.json"),
            include_str!("../../../../spec/workbench/draft.3/schemas/value-type.schema.json"),
            include_str!("../../../../spec/workbench/draft.3/schemas/definitions.schema.json"),
            include_str!("../../../../spec/workbench/draft.3/schemas/manifest.schema.json"),
            include_str!("../../../../spec/workbench/admission/draft.1/schemas/selection.schema.json"),
            include_str!("../../../../spec/workbench/executions/0.2.0-draft.1/schemas/identity.schema.json"),
            include_str!("../../../../spec/workbench/executions/0.2.0-draft.1/schemas/offer.schema.json"),
            include_str!("../../../../spec/workbench/executions/0.2.0-draft.1/schemas/receipt.schema.json"),
            include_str!("../../../../spec/workbench/execution-plan/0.2.0-draft.1/schemas/plan.schema.json"),
            include_str!("../../../../spec/workbench/host/0.2.0-draft.2/schemas/submission.schema.json"),
            include_str!("../../../../spec/workbench/host/0.2.0-draft.1/schemas/identity-request.schema.json"),
            include_str!("../../../../spec/workbench/draft.23/schemas/mck-input.schema.json"),
            include_str!("../../../../spec/workbench/draft.23/schemas/http-policy-boundary-projection.schema.json"),
            include_str!("../../../../spec/workbench/draft.23/schemas/mck-observation.schema.json"),
            include_str!("../../../../spec/workbench/draft.23/schemas/mck-capabilities.schema.json"),
            include_str!("../../../../spec/workbench/draft.23/schemas/mck-corpus.schema.json"),
            include_str!("../../../../spec/workbench/draft.23/schemas/mck-report.schema.json"),
            include_str!("../../../../spec/workbench/draft.24/schemas/mck-input.schema.json"),
            include_str!("../../../../spec/workbench/draft.24/schemas/http-client-projection.schema.json"),
            include_str!("../../../../spec/workbench/draft.24/schemas/mck-observation.schema.json"),
            include_str!("../../../../spec/workbench/draft.24/schemas/mck-capabilities.schema.json"),
            include_str!("../../../../spec/workbench/draft.24/schemas/mck-corpus.schema.json"),
            include_str!("../../../../spec/workbench/draft.24/schemas/mck-report.schema.json"),
            include_str!("../../../../spec/workbench/draft.25/schemas/mck-input.schema.json"),
            include_str!("../../../../spec/workbench/draft.25/schemas/http-provider-projection.schema.json"),
            include_str!("../../../../spec/workbench/draft.25/schemas/mck-observation.schema.json"),
            include_str!("../../../../spec/workbench/draft.25/schemas/mck-capabilities.schema.json"),
            include_str!("../../../../spec/workbench/draft.25/schemas/mck-corpus.schema.json"),
            include_str!("../../../../spec/workbench/draft.25/schemas/mck-report.schema.json"),
        ].map(|text|serde_json::from_str::<Value>(text).expect("HTTP schema JSON"));
        let build = |name: &str| {
            let id = format!(
                "https://morphir.finos.org/spec/workbench/0.1.0-draft.{}/{name}.schema.json",
                kit.draft()
            );
            let schema = schemas
                .iter()
                .find(|s| s["$id"] == id)
                .expect("HTTP schema resource");
            let mut options = jsonschema::options();
            options.with_retriever(super::contract::OfflineOnly);
            for resource in &schemas {
                options.with_resource(
                    resource["$id"].as_str().expect("schema id"),
                    jsonschema::Resource::from_contents(resource.clone()).expect("schema resource"),
                );
            }
            options.build(schema).expect("HTTP schema validator")
        };
        let projection = match kit {
            Kit::Boundary => "http-policy-boundary-projection",
            Kit::Client => "http-client-projection",
            Kit::Provider => "http-provider-projection",
        };
        Self {
            corpus: build("mck-corpus"),
            input: build("mck-input"),
            projection: build(projection),
            observation: build("mck-observation"),
            report: build("mck-report"),
        }
    }
}
