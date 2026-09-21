//! The consolidated draft report. Validation is confined to this report schema;
//! adapter capabilities retain their independent version-1 protocol contract.

use std::fmt;
use std::ops::Deref;
use std::sync::OnceLock;

use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::Value;

use super::{Outcome, Record, Summary};
use crate::transport::protocol::{self, Capabilities, parse_capabilities};

pub const CONTRACT_VERSION: &str = "2.0.0-draft.1";
pub const SCHEMA: &str = include_str!("../../../../spec/ir/mck/report-draft.schema.json");

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReportError(pub String);

impl fmt::Display for ReportError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}
impl std::error::Error for ReportError {}

/// A report validated against the draft schema and its semantic constraints.
/// Fields can be inspected through `Deref`, but construction uses the reader.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(transparent)]
pub struct DraftReport(ReportData);

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ReportData {
    pub contract_version: String,
    pub suite: Suite,
    pub started_at: String,
    pub driver: Driver,
    pub kit: Kit,
    pub adapter: Adapter,
    pub selection: Selection,
    pub execution: Execution,
    pub records: Vec<Record>,
}

impl Deref for DraftReport {
    type Target = ReportData;
    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Suite {
    Ir,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Driver {
    pub name: String,
    pub version: String,
    pub commit: Option<String>,
    pub dirty: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Kit {
    pub version: String,
    pub source: KitSource,
    pub revision: Option<String>,
    pub snapshot_digest: Option<String>,
    pub corpus_hash: Option<String>,
    pub modified: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum KitSource {
    Embedded,
    Vendored,
    Local,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Adapter {
    pub command: Vec<String>,
    pub negotiation: Negotiation,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "status", rename_all = "lowercase", deny_unknown_fields)]
pub enum Negotiation {
    Succeeded {
        capabilities: NegotiatedCapabilities,
    },
    Failed {
        message: String,
    },
}

/// Keeps the parsed protocol capabilities once, including the validated support
/// table. Serialization reconstructs their wire shape without caching JSON.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NegotiatedCapabilities(Capabilities);

impl NegotiatedCapabilities {
    pub fn from_capabilities(capabilities: &Capabilities) -> Result<Self, ReportError> {
        let candidate = Self(capabilities.clone());
        let value = serde_json::to_value(&candidate).map_err(json_error)?;
        parse_capabilities(&value)
            .map(Self)
            .map_err(|e| ReportError(e.to_string()))
    }

    pub fn as_capabilities(&self) -> &Capabilities {
        &self.0
    }
}

impl Serialize for NegotiatedCapabilities {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        use serde::ser::SerializeStruct;
        let c = &self.0;
        let mut out = serializer.serialize_struct("Capabilities", 9)?;
        out.serialize_field("contractVersion", &protocol::CONTRACT_VERSION)?;
        out.serialize_field("binding", &c.binding)?;
        out.serialize_field("language", &c.language)?;
        out.serialize_field("formatVersions", &c.format_versions)?;
        out.serialize_field("versions", &c.versions)?;
        out.serialize_field("profiles", &c.profiles)?;
        out.serialize_field("layouts", &c.layouts)?;
        out.serialize_field("paths", &c.paths)?;
        out.serialize_field("nodes", &c.nodes)?;
        out.end()
    }
}

impl<'de> Deserialize<'de> for NegotiatedCapabilities {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let value = Value::deserialize(deserializer)?;
        parse_capabilities(&value)
            .map(Self)
            .map_err(serde::de::Error::custom)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase", deny_unknown_fields)]
pub enum Selection {
    All,
    Filter {
        syntax: FilterSyntax,
        pattern: String,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum FilterSyntax {
    #[serde(rename = "rust-regex")]
    RustRegex,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Execution {
    pub strict: bool,
    pub session: Session,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "status", rename_all = "lowercase", deny_unknown_fields)]
pub enum Session {
    Finished,
    Failed { errors: Vec<SessionError> },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SessionError {
    pub phase: SessionPhase,
    pub message: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SessionPhase {
    Spawn,
    Capabilities,
    Exchange,
    Shutdown,
}

fn json_error(error: serde_json::Error) -> ReportError {
    ReportError(error.to_string())
}

fn validator() -> &'static jsonschema::Validator {
    static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
    VALIDATOR.get_or_init(|| {
        let schema: Value = serde_json::from_str(SCHEMA).expect("embedded report schema is JSON");
        jsonschema::draft7::options()
            .should_validate_formats(true)
            .build(&schema)
            .expect("embedded report schema is valid and self-contained")
    })
}

/// JSON Schema integers include spellings such as 4.0 and 4e0. Serde's
/// integer visitors only accept integer-encoded JSON numbers, so normalize the
/// record fields after schema validation has checked integrality and sign.
fn normalize_record_numbers(mut value: Value) -> Result<Value, ReportError> {
    let records = value["records"]
        .as_array_mut()
        .expect("schema checked records");
    for (index, record) in records.iter_mut().enumerate() {
        for (field, upper_exclusive) in [
            ("irVersion", 2_f64.powi(63)),
            ("fenceIndex", 2_f64.powi(usize::BITS as i32)),
        ] {
            let Some(number) = record[field].as_number().filter(|number| number.is_f64()) else {
                continue;
            };
            let number = number.as_f64().expect("floating-point JSON number");
            // Powers of two are exact f64 values. Comparing against an
            // inclusive MAX cast to f64 would round up and accept overflow.
            if number >= upper_exclusive {
                return Err(ReportError(format!(
                    "records[{index}].{field}: integer exceeds the supported range"
                )));
            }
            record[field] = Value::from(number as u64);
        }
    }
    Ok(value)
}

impl DraftReport {
    pub fn from_json(text: &str) -> Result<Self, ReportError> {
        Self::from_value(serde_json::from_str(text).map_err(json_error)?)
    }

    pub fn from_value(value: Value) -> Result<Self, ReportError> {
        validator()
            .validate(&value)
            .map_err(|error| ReportError(format!("{}: {error}", error.instance_path)))?;
        let report =
            Self(serde_json::from_value(normalize_record_numbers(value)?).map_err(json_error)?);
        report.validate_semantics()?;
        Ok(report)
    }

    fn validate_semantics(&self) -> Result<(), ReportError> {
        if let Selection::Filter { pattern, .. } = &self.selection {
            regex::Regex::new(pattern)
                .map_err(|e| ReportError(format!("selection.pattern: {e}")))?;
        }
        let negotiation_error = match &self.execution.session {
            Session::Finished => false,
            Session::Failed { errors } => errors
                .iter()
                .any(|e| matches!(e.phase, SessionPhase::Spawn | SessionPhase::Capabilities)),
        };
        if matches!(self.adapter.negotiation, Negotiation::Failed { .. }) != negotiation_error {
            return Err(ReportError("adapter.negotiation and execution.session disagree: failed negotiation requires a spawn or capabilities error".into()));
        }
        if matches!(self.adapter.negotiation, Negotiation::Failed { .. })
            && self
                .records
                .iter()
                .any(|record| record.result != Outcome::KitError)
        {
            return Err(ReportError(
                "records: failed negotiation permits only kit-error outcomes".into(),
            ));
        }
        Ok(())
    }

    pub fn summary(&self) -> Summary {
        self.records
            .iter()
            .fold(Summary::default(), |mut summary, record| {
                match record.result {
                    Outcome::Pass => summary.pass += 1,
                    Outcome::Fail => summary.fail += 1,
                    Outcome::KitError => summary.kit_error += 1,
                    Outcome::Skipped => summary.skipped += 1,
                }
                summary
            })
    }

    pub fn summary_line(&self) -> String {
        let s = self.summary();
        format!(
            "{} pass, {} fail, {} kit-error, {} skipped",
            s.pass, s.fail, s.kit_error, s.skipped
        )
    }

    pub fn to_json(&self) -> String {
        format!("{}\n", crate::json::to_tab_json(self))
    }
}

impl<'de> Deserialize<'de> for DraftReport {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        Self::from_value(Value::deserialize(deserializer)?).map_err(serde::de::Error::custom)
    }
}
