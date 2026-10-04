use std::collections::BTreeSet;
use std::sync::OnceLock;

use semver::{Version, VersionReq};
use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const VERSION: &str = "0.1.0-draft.1";
pub const ADMISSION_VERSION: &str = "0.1.0-draft.2";
pub const INVOCATION_VERSION: &str = "0.1.0-draft.3";
pub const MAX_VALUE_BYTES: usize = 1024 * 1024;

pub(super) fn encoded_size(value: &impl Serialize, limit: usize) -> Result<usize, String> {
    struct Counter {
        bytes: usize,
        limit: usize,
    }
    impl std::io::Write for Counter {
        fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
            let total = self
                .bytes
                .checked_add(bytes.len())
                .ok_or_else(|| std::io::Error::other("encoded byte budget exceeded"))?;
            if total > self.limit {
                return Err(std::io::Error::other("encoded byte budget exceeded"));
            }
            self.bytes = total;
            Ok(bytes.len())
        }
        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }
    let mut counter = Counter { bytes: 0, limit };
    serde_json::to_writer(&mut counter, value).map_err(|e| e.to_string())?;
    Ok(counter.bytes)
}

pub(super) fn version(text: &str) -> Result<(), String> {
    let parsed = Version::parse(text).map_err(|e| e.to_string())?;
    let supported = ["=0.1.0-draft.1", "=0.1.0-draft.2", "=0.1.0-draft.3"]
        .map(|v| VersionReq::parse(v).expect("fixed draft requirement"));
    if parsed.to_string() != text
        || !parsed.build.is_empty()
        || !supported.iter().any(|v| v.matches(&parsed))
    {
        return Err(format!("unsupported Workbench draft {text}"));
    }
    Ok(())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum Format {
    #[serde(rename = "json")]
    Json,
    #[serde(rename = "ion-text")]
    IonText,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum Operation {
    #[serde(rename = "decode-value")]
    DecodeValue,
    #[serde(rename = "validate-value")]
    ValidateValue,
    #[serde(rename = "validate-invocations")]
    ValidateInvocations,
}

impl Operation {
    pub(super) fn validate_version(self, version: &str) -> Result<(), String> {
        if (version == VERSION && self != Self::DecodeValue)
            || (version == ADMISSION_VERSION && self == Self::ValidateInvocations)
        {
            return Err("operation is not defined by this Workbench draft".into());
        }
        Ok(())
    }
}

pub(super) fn present_operation<'de, D: serde::Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<Operation>, D::Error> {
    Operation::deserialize(deserializer).map(Some)
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Capabilities {
    pub suite: String,
    pub contract_version: String,
    pub binding: String,
    pub language: String,
    pub operations: Vec<Operation>,
    pub formats: Vec<Format>,
}

pub(super) fn identity(value: &str, limit: usize) -> Result<(), String> {
    if value.is_empty() || value.encode_utf16().count() > limit {
        return Err(format!("identity must contain 1 to {limit} UTF-16 units"));
    }
    Ok(())
}

impl Capabilities {
    pub(super) fn parse(value: Value, expected_version: &str) -> Result<Self, String> {
        let caps: Self = serde_json::from_value(value).map_err(|e| e.to_string())?;
        caps.validate()?;
        if caps.contract_version != expected_version {
            return Err("adapter returned a different Workbench draft".into());
        }
        Ok(caps)
    }

    pub(super) fn validate(&self) -> Result<(), String> {
        version(&self.contract_version)?;
        if self.suite != "workbench" {
            return Err("Workbench capabilities required".into());
        }
        for operation in &self.operations {
            operation.validate_version(&self.contract_version)?;
        }
        identity(&self.binding, 256)?;
        identity(&self.language, 128)?;
        if self.operations.iter().collect::<BTreeSet<_>>().len() != self.operations.len()
            || self.formats.iter().collect::<BTreeSet<_>>().len() != self.formats.len()
        {
            return Err("duplicate capability claim".into());
        }
        Ok(())
    }

    pub fn supports(&self, operation: Operation, format: Format) -> bool {
        self.operations.contains(&operation) && self.formats.contains(&format)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "status", rename_all = "lowercase", deny_unknown_fields)]
pub enum Observation {
    Ok { value: Value },
    Invalid { code: String },
}

impl Observation {
    pub(super) fn parse(value: Value) -> Result<Self, String> {
        let observation: Self = serde_json::from_value(value).map_err(|e| e.to_string())?;
        Ok(observation)
    }

    pub(super) fn validate_for(&self, operation: Operation) -> Result<(), String> {
        match self {
            Self::Ok { value } => {
                projection_for(value, operation)?;
            }
            Self::Invalid { code } => identity(code, 128)?,
        }
        if operation == Operation::ValidateValue
            && matches!(self, Self::Ok { value } if value["type"] == "model-error")
        {
            return Err("argument admission cannot succeed with a model-error".into());
        }
        Ok(())
    }

    pub(super) fn matches(&self, other: &Self, operation: Operation) -> Result<bool, String> {
        self.validate_for(operation)?;
        other.validate_for(operation)?;
        match (self, other) {
            (Self::Ok { value: left }, Self::Ok { value: right }) => {
                Ok(projection_for(left, operation)? == projection_for(right, operation)?)
            }
            _ => Ok(self == other),
        }
    }
}

fn projection_for(value: &Value, operation: Operation) -> Result<Value, String> {
    if operation == Operation::ValidateInvocations {
        invocation_projection(value)
    } else {
        projection(value)
    }
}

/// Validate only the published invocation projection. Inputs/manifests are never
/// decoded here. Extension bytes are opaque ordered evidence, not re-serialized Ion.
fn invocation_projection(value: &Value) -> Result<Value, String> {
    encoded_size(value, MAX_VALUE_BYTES)?;
    static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
    let validator = VALIDATOR.get_or_init(|| {
        let value_schema: Value = serde_json::from_str(include_str!(
            "../../../../spec/workbench/schemas/value.schema.json"
        ))
        .expect("Workbench value schema JSON");
        let schema: Value = serde_json::from_str(include_str!(
            "../../../../spec/workbench/schemas/invocations.schema.json"
        ))
        .expect("Workbench invocation schema JSON");
        jsonschema::options()
            .with_retriever(OfflineOnly)
            .with_resource(
                value_schema["$id"].as_str().expect("value schema id"),
                jsonschema::Resource::from_contents(value_schema.clone()).expect("schema resource"),
            )
            .build(&schema)
            .expect("Workbench invocation schema")
    });
    validator
        .validate(value)
        .map_err(|e| format!("invalid invocation projection at {}: {e}", e.instance_path))?;
    let mut projected = value.clone();
    let mut ids = BTreeSet::new();
    for call in projected["calls"]
        .as_array_mut()
        .expect("schema-checked calls")
    {
        let id = call["id"].as_str().expect("schema-checked call id");
        identity(id, 128)?;
        identity(call["entry"].as_str().expect("schema-checked entry"), 1024)?;
        if !ids.insert(id.to_owned()) {
            return Err("duplicate invocation call id".into());
        }
        let mut budget = 100_000_usize;
        for argument in call["arguments"]
            .as_array_mut()
            .expect("schema-checked arguments")
        {
            check_projection_limits(argument, 0, &mut budget)?;
            sort_records(argument, 0, &mut 0)?;
        }
    }
    Ok(projected)
}

/// Validate the canonical output projection. The kit never decodes input values or derives
/// expectations from the implementation under test. Lists and tuples stay ordered;
/// record fields compare by name, recursively, without erasing duplicate names.
pub(super) fn projection(value: &Value) -> Result<Value, String> {
    encoded_size(value, MAX_VALUE_BYTES)?;
    let mut budget = 100_000_usize;
    check_projection_limits(value, 0, &mut budget)?;
    static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
    let validator = VALIDATOR.get_or_init(|| {
        let value_schema: Value = serde_json::from_str(include_str!(
            "../../../../spec/workbench/schemas/value.schema.json"
        ))
        .expect("Workbench value schema JSON");
        let schema: Value = serde_json::from_str(include_str!(
            "../../../../spec/workbench/schemas/outcome-value.schema.json"
        ))
        .expect("Workbench outcome value schema JSON");
        jsonschema::options()
            .with_retriever(OfflineOnly)
            .with_resource(
                value_schema["$id"]
                    .as_str()
                    .expect("Workbench value schema id"),
                jsonschema::Resource::from_contents(value_schema.clone())
                    .expect("Workbench schema resource"),
            )
            .build(&schema)
            .expect("Workbench value schema")
    });
    validator
        .validate(value)
        .map_err(|e| format!("invalid typed value projection at {}: {e}", e.instance_path))?;
    let mut projected = value.clone();
    let mut nodes = 0_usize;
    sort_records(&mut projected, 0, &mut nodes)?;
    Ok(projected)
}

struct OfflineOnly;
impl jsonschema::Retrieve for OfflineOnly {
    fn retrieve(
        &self,
        uri: &jsonschema::Uri<&str>,
    ) -> Result<Value, Box<dyn std::error::Error + Send + Sync>> {
        Err(format!("reference outside the offline Workbench catalog: {uri}").into())
    }
}

fn canonical_integer(text: &str, signed: bool) -> Result<(), String> {
    let digits = if signed {
        text.strip_prefix('-').unwrap_or(text)
    } else {
        text
    };
    if digits.is_empty()
        || !digits.bytes().all(|b| b.is_ascii_digit())
        || (digits.len() > 1 && digits.starts_with('0'))
        || text == "-0"
    {
        return Err("noncanonical integer output projection".into());
    }
    Ok(())
}

/// These guards admit expected/output projections, not encoded inputs. Decimal
/// admission checks its normalized exponent but leaves the original scale intact.
fn check_projection_limits(value: &Value, depth: usize, budget: &mut usize) -> Result<(), String> {
    if depth > 64 {
        return Err("typed value projection exceeds depth budget".into());
    }
    *budget = budget
        .checked_sub(1)
        .ok_or("typed value projection exceeds aggregate budget")?;
    match value.get("type").and_then(Value::as_str) {
        Some("int") => {
            if let Some(text) = value.get("value").and_then(Value::as_str) {
                canonical_integer(text, true)?;
            }
        }
        Some("float64") => {
            if let Some(text) = value.get("bits").and_then(Value::as_str) {
                canonical_integer(text, false)?;
                text.parse::<u64>()
                    .map_err(|_| "Float64 output bits exceed UInt64")?;
            }
        }
        Some("decimal") => {
            if let Some(text) = value.get("coefficient").and_then(Value::as_str) {
                canonical_integer(text, true)?;
                if text != "0"
                    && let Some(exponent) = value.get("exponent").and_then(|v| {
                        v.as_i64().or_else(|| {
                            v.as_f64()
                                .filter(|f| f.fract() == 0.0 && (-10000.0..=10000.0).contains(f))
                                .map(|f| f as i64)
                        })
                    })
                {
                    let zeros = text.bytes().rev().take_while(|b| *b == b'0').count();
                    let normalized = exponent
                        .checked_add(zeros as i64)
                        .ok_or("Decimal exponent overflow")?;
                    if !(-32..=10_000).contains(&normalized) {
                        return Err("Decimal output projection exceeds normalized precision".into());
                    }
                }
            }
        }
        Some("text" | "character") => {
            if let Some(units) = value.get("units").and_then(Value::as_array) {
                *budget = budget
                    .checked_sub(units.len())
                    .ok_or("typed value projection exceeds aggregate budget")?;
            }
        }
        Some("custom") => {
            for key in ["owner", "tag"] {
                if let Some(text) = value.get(key).and_then(Value::as_str) {
                    identity(text, 1024)?;
                }
            }
        }
        _ => {}
    }
    if let Some(fields) = value.get("fields").and_then(Value::as_array) {
        for field in fields {
            if let Some(name) = field.get("name").and_then(Value::as_str) {
                identity(name, 1024)?;
            }
            if let Some(child) = field.get("value") {
                check_projection_limits(child, depth + 1, budget)?;
            }
        }
    }
    if let Some(items) = value.get("items").and_then(Value::as_array) {
        for child in items {
            check_projection_limits(child, depth + 1, budget)?;
        }
    }
    if let Some(child) = value.get("value").filter(|v| v.is_object()) {
        check_projection_limits(child, depth + 1, budget)?;
    }
    Ok(())
}

fn sort_records(value: &mut Value, depth: usize, nodes: &mut usize) -> Result<(), String> {
    *nodes += 1;
    if depth > 64 || *nodes > 100_000 {
        return Err("typed value projection exceeds depth/node budget".into());
    }
    if value["type"] == "record" {
        let fields = value["fields"]
            .as_array_mut()
            .expect("schema-checked fields");
        let mut names = BTreeSet::new();
        for field in fields.iter_mut() {
            let name = field["name"].as_str().expect("schema-checked name");
            if !names.insert(name.to_owned()) {
                return Err("duplicate record field name".into());
            }
            sort_records(&mut field["value"], depth + 1, nodes)?;
        }
        fields.sort_by(|a, b| a["name"].as_str().cmp(&b["name"].as_str()));
    } else {
        if let Some(items) = value.get_mut("items").and_then(Value::as_array_mut) {
            for item in items {
                sort_records(item, depth + 1, nodes)?;
            }
        }
        if let Some(child) = value.get_mut("value").filter(|v| v.is_object()) {
            sort_records(child, depth + 1, nodes)?;
        }
    }
    Ok(())
}
