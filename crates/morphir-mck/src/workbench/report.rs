use std::path::Path;

use serde::{Deserialize, Deserializer, Serialize};

use super::contract::{
    Capabilities, Format, Observation, VERSION, encoded_size, identity, version,
};
use super::corpus::{Corpus, load};

pub const MAX_REPORT_BYTES: usize = 32 * 1024 * 1024;
pub const MAX_OBSERVATION_BYTES: usize = 16 * 1024 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ResultKind {
    Pass,
    Fail,
    Unsupported,
    Error,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Phase {
    Spawn,
    Capabilities,
    Exchange,
    Shutdown,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Failure {
    pub phase: Phase,
    pub message: String,
}

impl Failure {
    pub(super) fn new(phase: Phase, message: String) -> Self {
        let mut bounded = String::new();
        let mut units = 0;
        for ch in message.chars() {
            units += ch.len_utf16();
            if units > 16_384 {
                break;
            }
            bounded.push(ch);
        }
        if bounded.is_empty() {
            bounded = "unspecified adapter failure".into();
        }
        Self {
            phase,
            message: bounded,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Record {
    pub case_id: String,
    pub format: Format,
    pub result: ResultKind,
    #[serde(deserialize_with = "required_option")]
    pub observed: Option<Observation>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Report {
    pub format_version: String,
    pub suite: String,
    pub corpus_hash: String,
    #[serde(deserialize_with = "required_option")]
    pub capabilities: Option<Capabilities>,
    pub records: Vec<Record>,
    pub errors: Vec<Failure>,
    pub qualified: bool,
}

fn required_option<'de, D: Deserializer<'de>, T: Deserialize<'de>>(
    deserializer: D,
) -> Result<Option<T>, D::Error> {
    Option::deserialize(deserializer)
}

impl Report {
    pub fn adapter_error(corpus: &Corpus, message: String) -> Self {
        let mut report = Self::new(corpus);
        report.errors.push(Failure::new(Phase::Spawn, message));
        report.records = corpus
            .cases
            .iter()
            .map(|c| Record {
                case_id: c.id.clone(),
                format: c.format,
                result: ResultKind::Error,
                observed: None,
            })
            .collect();
        report
    }
    pub(super) fn new(corpus: &Corpus) -> Self {
        Self {
            format_version: VERSION.into(),
            suite: "workbench".into(),
            corpus_hash: corpus.hash.clone(),
            capabilities: None,
            records: vec![],
            errors: vec![],
            qualified: false,
        }
    }
    pub fn from_json(text: &str) -> Result<Self, String> {
        if text.len() > MAX_REPORT_BYTES {
            return Err("Workbench report exceeds 32 MiB".into());
        }
        let value = crate::json::strict::parse(text)?;
        serde_json::from_value(value).map_err(|e| e.to_string())
    }
    pub fn to_json(&self) -> String {
        // Compact JSON keeps retained observation bytes and emitted report bytes
        // under the same predictable bound, independent of nesting whitespace.
        format!(
            "{}\n",
            serde_json::to_string(self).expect("report serializes")
        )
    }
    pub fn summary_line(&self) -> String {
        let count = |result| self.records.iter().filter(|r| r.result == result).count();
        format!(
            "{} pass, {} fail, {} unsupported, {} error",
            count(ResultKind::Pass),
            count(ResultKind::Fail),
            count(ResultKind::Unsupported),
            count(ResultKind::Error)
        )
    }
    pub(super) fn finish(&mut self) {
        self.qualified = self.errors.is_empty()
            && !self.records.is_empty()
            && self.records.iter().all(|r| r.result == ResultKind::Pass);
    }
}

/// Validate recorded observations against a freshly admitted corpus. Qualification
/// is computed again instead of trusting the report's result or qualified fields.
pub fn check_report(root: &Path, report: &Report) -> Result<(), String> {
    let corpus = load(root)?;
    version(&report.format_version)?;
    if report.suite != "workbench" || report.corpus_hash != corpus.hash {
        return Err("Workbench suite/corpus identity differs".into());
    }
    if report.records.len() != corpus.cases.len() {
        return Err("report record inventory count differs".into());
    }
    if report.errors.len() > 3 {
        return Err("report has too many session failures".into());
    }
    for failure in &report.errors {
        identity(&failure.message, 16384)?;
    }
    let negotiation_failed = report
        .errors
        .iter()
        .any(|e| matches!(e.phase, Phase::Spawn | Phase::Capabilities));
    if report.capabilities.is_none() != negotiation_failed {
        return Err("capabilities and negotiation failure disagree".into());
    }
    if let Some(caps) = &report.capabilities {
        caps.validate()?;
    }
    let exchange_failed = report.errors.iter().any(|e| e.phase == Phase::Exchange);
    let mut seen_exchange_error = false;
    let mut observation_budget = MAX_OBSERVATION_BYTES;
    for (case, record) in corpus.cases.iter().zip(&report.records) {
        if case.id != record.case_id || case.format != record.format {
            return Err("report record identity/order differs".into());
        }
        let supported = report
            .capabilities
            .as_ref()
            .is_some_and(|c| c.supports(case.format));
        let expected = if negotiation_failed {
            if record.observed.is_some() {
                return Err("failed negotiation contains an observation".into());
            }
            ResultKind::Error
        } else if !supported {
            if record.observed.is_some() {
                return Err("unsupported case contains an observation".into());
            }
            ResultKind::Unsupported
        } else if let Some(observed) = &record.observed {
            let bytes = encoded_size(observed, observation_budget)?;
            observation_budget -= bytes;
            if seen_exchange_error {
                return Err("observation follows failed exchange".into());
            }
            if case.expected.matches(observed)? {
                ResultKind::Pass
            } else {
                ResultKind::Fail
            }
        } else {
            if !exchange_failed {
                return Err("claimed case is missing its observation".into());
            }
            seen_exchange_error = true;
            ResultKind::Error
        };
        if expected != record.result {
            return Err(format!("forged case result {}", case.id));
        }
    }
    if exchange_failed != seen_exchange_error {
        return Err("exchange error and record inventory disagree".into());
    }
    let qualified =
        report.errors.is_empty() && report.records.iter().all(|r| r.result == ResultKind::Pass);
    if qualified != report.qualified {
        return Err("forged qualification".into());
    }
    encoded_size(report, MAX_REPORT_BYTES - 1)?;
    Ok(())
}
