//! Closed offline catalog. Adapters receive schemas for integrity requests only.
use jsonschema::{Resource, Retrieve, Uri, Validator};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};

pub(super) const INTEGRITY: &[&str] = &[
    "schemas/library-manifest.schema.json",
    "schemas/lock-core.schema.json",
];
pub(super) const RESOLUTION: &[&str] = &[
    "schemas/library-manifest.schema.json",
    "schemas/lock-core.schema.json",
    "schemas/resolution-input.schema.json",
    "schemas/resolution-result.schema.json",
    "schemas/resolution-case.schema.json",
];
struct OfflineOnly;
impl Retrieve for OfflineOnly {
    fn retrieve(&self, uri: &Uri<&str>) -> Result<Value, Box<dyn std::error::Error + Send + Sync>> {
        Err(format!("reference outside the offline package catalog: {uri}").into())
    }
}
pub(super) struct Catalog {
    validators: BTreeMap<String, Validator>,
}
impl Catalog {
    pub fn compile(schemas: &BTreeMap<String, Value>) -> Result<Self, String> {
        let mut ids = BTreeSet::new();
        for (name, schema) in schemas {
            if schema["$schema"] != "https://json-schema.org/draft/2020-12/schema" {
                return Err(format!("{name}: unsupported schema dialect"));
            }
            let id = schema["$id"]
                .as_str()
                .ok_or_else(|| format!("{name}: schema requires $id"))?;
            if !ids.insert(id) {
                return Err(format!("duplicate schema $id {id}"));
            }
        }
        let mut validators = BTreeMap::new();
        for (name, schema) in schemas {
            let mut options = jsonschema::options();
            options.with_retriever(OfflineOnly);
            for resource in schemas.values() {
                options.with_resource(
                    resource["$id"].as_str().expect("validated id"),
                    Resource::from_contents(resource.clone()).map_err(|e| e.to_string())?,
                );
            }
            validators.insert(
                name.clone(),
                options.build(schema).map_err(|e| format!("{name}: {e}"))?,
            );
        }
        Ok(Self { validators })
    }
    pub fn validate(&self, name: &str, value: &Value) -> Result<(), String> {
        let validator = self
            .validators
            .get(name)
            .ok_or_else(|| format!("missing schema {name}"))?;
        validator
            .validate(value)
            .map_err(|error| format!("{name}: {} at {}", error, error.instance_path))
    }
}
