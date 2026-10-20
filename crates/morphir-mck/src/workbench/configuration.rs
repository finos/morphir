use super::model_originals::workflow::pipeline::Policy;
use crate::json::strict::Document;

/// Explicit caller-owned checker configuration. No source, report or adapter
/// supplies these limits, and no selected production default is installed.
pub struct RunConfiguration {
    pub(super) mode: Configuration,
}
/// Existing adapter framing selected by a validated checker configuration.
/// This is a pure choice; only the actual session factory starts a process.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AdapterProtocol {
    HistoricalNewline,
    ContentLength,
}
pub(super) enum Configuration {
    Historical,
    ModelOriginals(Box<Policy>),
}
impl RunConfiguration {
    pub fn adapter_protocol(&self) -> AdapterProtocol {
        match self.mode {
            Configuration::Historical => AdapterProtocol::HistoricalNewline,
            Configuration::ModelOriginals(_) => AdapterProtocol::ContentLength,
        }
    }
    pub fn from_json(raw: &str) -> Result<Self, String> {
        if raw.len() > super::MAX_REPORT_BYTES {
            return Err("policy exceeds bounded wire input".into());
        }
        // Existing bounded JSON infrastructure, not a selected reader policy.
        // Only configuration is decoded here; opaque source/evidence is not.
        let document = Document::parse_exact(raw.as_bytes())?;
        let Document::Object(fields) = &document else {
            return Err("policy requires object".into());
        };
        let kind = fields
            .iter()
            .find(|(key, _)| key == "kind")
            .map(|(_, value)| value);
        let mode = match kind {
            Some(Document::String(kind)) if kind == "historical" && fields.len() == 1 => {
                Configuration::Historical
            }
            Some(Document::String(kind)) if kind == "model-originals" => {
                Configuration::ModelOriginals(Box::new(Policy::from_document(&document)?))
            }
            _ => return Err("policy has unknown kind or fields".into()),
        };
        Ok(Self { mode })
    }
}
