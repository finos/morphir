use super::corpus::{Corpus, CorpusStorage};
use super::model_originals::workflow::pipeline::{self, StoredReport};
use super::report::{HistoricalReport, check_historical_report};
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use std::path::Path;

/// Closed report families. A selected raw report remains untrusted until the
/// configured shared replay checks it against freshly prepared source.
#[derive(Debug, Clone)]
pub struct Report {
    pub(super) storage: ReportStorage,
}
#[derive(Debug, Clone)]
pub(super) enum ReportStorage {
    Historical(Box<HistoricalReport>),
    ModelOriginals(StoredReport),
}
impl Serialize for Report {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        match &self.storage {
            ReportStorage::Historical(report) => report.serialize(s),
            ReportStorage::ModelOriginals(report) => {
                let raw: &serde_json::value::RawValue =
                    serde_json::from_str(report.text()).map_err(serde::ser::Error::custom)?;
                raw.serialize(s)
            }
        }
    }
}
impl<'de> Deserialize<'de> for Report {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let raw = Box::<serde_json::value::RawValue>::deserialize(d)?;
        Self::from_json(raw.get()).map_err(serde::de::Error::custom)
    }
}
impl Report {
    pub(super) fn historical(report: HistoricalReport) -> Self {
        Self {
            storage: ReportStorage::Historical(Box::new(report)),
        }
    }
    pub(super) fn selected(report: StoredReport) -> Self {
        Self {
            storage: ReportStorage::ModelOriginals(report),
        }
    }
    pub fn adapter_error(corpus: &Corpus, message: String) -> Result<Self, String> {
        match &corpus.storage {
            CorpusStorage::Historical(corpus) => Ok(Self::historical(
                HistoricalReport::adapter_error(corpus, message),
            )),
            CorpusStorage::ModelOriginals(_) => Err(pipeline::MISSING_POLICY.into()),
        }
    }
    /// Explicit view of the historical public wire model. It is never a Deref
    /// fallback or fabricated historical data for a selected report.
    pub fn as_historical(&self) -> Option<&HistoricalReport> {
        match &self.storage {
            ReportStorage::Historical(report) => Some(report),
            ReportStorage::ModelOriginals(_) => None,
        }
    }
    pub(super) fn as_historical_mut(&mut self) -> Option<&mut HistoricalReport> {
        match &mut self.storage {
            ReportStorage::Historical(report) => Some(report),
            ReportStorage::ModelOriginals(_) => None,
        }
    }
    pub fn qualified(&self) -> bool {
        match &self.storage {
            ReportStorage::Historical(report) => report.qualified,
            ReportStorage::ModelOriginals(report) => report.qualified(),
        }
    }
    pub fn from_json(text: &str) -> Result<Self, String> {
        if text.len() > super::MAX_REPORT_BYTES {
            return Err("Workbench report exceeds32MiB".into());
        }
        if pipeline::recognizes(text)? {
            StoredReport::from_json(text).map(Self::selected)
        } else {
            HistoricalReport::from_json(text).map(Self::historical)
        }
    }
    pub fn to_json(&self) -> String {
        match &self.storage {
            ReportStorage::Historical(report) => report.to_json(),
            ReportStorage::ModelOriginals(report) => report.text().to_owned(),
        }
    }
    pub fn summary_line(&self) -> String {
        match &self.storage {
            ReportStorage::Historical(report) => report.summary_line(),
            ReportStorage::ModelOriginals(report) => report.summary(),
        }
    }
}
pub fn check_report(root: &Path, report: &Report) -> Result<(), String> {
    match &report.storage {
        ReportStorage::Historical(report) => check_historical_report(root, report),
        ReportStorage::ModelOriginals(_) => Err(pipeline::MISSING_POLICY.into()),
    }
}
