//! Closed, offline catalog of the suite's schemas and entry points.
use std::collections::{BTreeMap, BTreeSet};

use jsonschema::{Draft, Resource, Retrieve, Uri, Validator};
use serde_json::{Value, json};

use super::SchemaError;
use crate::kit::KitSource;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub(super) enum Schema {
    Ir,
    Tree,
    LegacyReport,
    DraftReport,
    Protocol,
    Vocabulary,
    Lock,
    Provenance,
}

impl Schema {
    pub const ALL: [Self; 8] = [
        Self::Ir,
        Self::Tree,
        Self::LegacyReport,
        Self::DraftReport,
        Self::Protocol,
        Self::Vocabulary,
        Self::Lock,
        Self::Provenance,
    ];
    pub fn path(self) -> &'static str {
        match self {
            Self::Ir => "website/static/schemas/morphir-ir-v4.json",
            Self::Tree => "website/static/schemas/morphir-ir-v4-document-tree-files.json",
            Self::LegacyReport => "spec/ir/mck/report.schema.json",
            Self::DraftReport => "spec/ir/mck/report-draft.schema.json",
            Self::Protocol => "spec/ir/mck/protocol.schema.json",
            Self::Vocabulary => "spec/mck/vocabulary.schema.json",
            Self::Lock => "spec/mck/mck-kit.lock.schema.json",
            Self::Provenance => "spec/mck/provenance.schema.json",
        }
    }
}

pub(super) const EXAMPLES: &[(Schema, &str)] = &[
    (Schema::LegacyReport, "spec/ir/mck/report.example.json"),
    (Schema::DraftReport, "spec/ir/mck/report-draft.example.json"),
    (Schema::Vocabulary, "spec/mck/vocabulary.json"),
    (Schema::Lock, "spec/mck/mck-kit.lock.example.json"),
];

pub(super) fn node_target(node: &str) -> Option<(Schema, &'static str)> {
    let definition = match node {
        "Distribution" => return Some((Schema::Ir, "")),
        "FormatVersion" => "FormatVersion",
        "Name" => "Name",
        "Path" => "Path",
        "FQName" => "FQName",
        "Type" => "Type",
        "Value" => "Value",
        "Pattern" => "Pattern",
        "Literal" => "Literal",
        "TypeSpecification" => "TypeSpecification",
        "TypeDefinition" => "TypeDefinition",
        "ValueSpecification" => "ValueSpecification",
        "ValueDefinition" => "ValueDefinition",
        "ModuleSpecification" => "ModuleSpecification",
        "ModuleDefinition" => "ModuleDefinition",
        "AccessControlledTypeDefinition" => "AccessControlledTypeDefinition",
        "AccessControlledValueDefinition" => "AccessControlledValueDefinition",
        "DistributionManifestFile" => return Some((Schema::Tree, "DistributionManifestFile")),
        "ModuleManifestFile" => return Some((Schema::Tree, "ModuleManifestFile")),
        "TypeDefinitionFile" => return Some((Schema::Tree, "TypeDefinitionFile")),
        "ValueDefinitionFile" => return Some((Schema::Tree, "ValueDefinitionFile")),
        _ => return None,
    };
    Some((Schema::Ir, definition))
}

pub(super) fn read_json(source: &KitSource, path: &str) -> Result<Value, SchemaError> {
    let bytes = source
        .read(path)
        .map_err(|e| SchemaError(format!("{path}: {e}")))?
        .ok_or_else(|| SchemaError(format!("missing offline catalog input {path}")))?;
    serde_json::from_slice(&bytes).map_err(|e| SchemaError(format!("{path}: invalid JSON: {e}")))
}

struct OfflineOnly;
impl Retrieve for OfflineOnly {
    fn retrieve(&self, uri: &Uri<&str>) -> Result<Value, Box<dyn std::error::Error + Send + Sync>> {
        Err(format!("reference outside the offline catalog: {uri}").into())
    }
}

pub(super) struct Catalog {
    schemas: BTreeMap<Schema, Value>,
    validators: BTreeMap<(Schema, &'static str), Validator>,
}

impl Catalog {
    pub fn load(source: &KitSource) -> Result<Self, SchemaError> {
        let schemas = Schema::ALL
            .into_iter()
            .map(|schema| Ok((schema, read_json(source, schema.path())?)))
            .collect::<Result<BTreeMap<_, _>, SchemaError>>()?;
        let mut ids = BTreeSet::new();
        for (schema, value) in &schemas {
            let id = value["$id"]
                .as_str()
                .ok_or_else(|| SchemaError(format!("{}: schema requires $id", schema.path())))?;
            if !ids.insert(id) {
                return Err(SchemaError(format!(
                    "{}: duplicate schema $id {id}",
                    schema.path()
                )));
            }
            match value["$schema"].as_str() {
                Some(
                    "http://json-schema.org/draft-07/schema#"
                    | "https://json-schema.org/draft/2020-12/schema",
                ) => {}
                _ => {
                    return Err(SchemaError(format!(
                        "{}: unsupported schema dialect",
                        schema.path()
                    )));
                }
            }
        }
        let mut catalog = Self {
            schemas,
            validators: BTreeMap::new(),
        };
        // Building each original schema validates its entire metaschema before instances.
        for schema in Schema::ALL {
            catalog.validator(schema, "")?;
        }
        Ok(catalog)
    }

    pub fn validator(
        &mut self,
        schema: Schema,
        definition: &'static str,
    ) -> Result<&Validator, SchemaError> {
        if !self.validators.contains_key(&(schema, definition)) {
            let original = &self.schemas[&schema];
            if !definition.is_empty()
                && original
                    .pointer(&format!("/definitions/{definition}"))
                    .is_none()
            {
                return Err(SchemaError(format!(
                    "{}: missing definition {definition}",
                    schema.path()
                )));
            }
            let mut options = jsonschema::options();
            options.with_retriever(OfflineOnly);
            for (key, value) in &self.schemas {
                let resource = Resource::from_contents(value.clone())
                    .map_err(|e| SchemaError(format!("{}: {e}", key.path())))?;
                options.with_resource(value["$id"].as_str().expect("validated id"), resource);
            }
            // Match the existing CLI's dialect defaults for format annotations.
            let input = if definition.is_empty() {
                original.clone()
            } else {
                let draft = if original["$schema"] == "https://json-schema.org/draft/2020-12/schema"
                {
                    Draft::Draft202012
                } else {
                    Draft::Draft7
                };
                options.with_draft(draft);
                json!({"$ref":format!("{}#/definitions/{definition}", original["$id"].as_str().expect("validated id"))})
            };
            let validator = options
                .build(&input)
                .map_err(|e| SchemaError(format!("{} schema: {e}", schema.path())))?;
            self.validators.insert((schema, definition), validator);
        }
        Ok(&self.validators[&(schema, definition)])
    }
}
