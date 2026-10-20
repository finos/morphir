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
    NativeOriginals {
        checker: Box<Policy>,
        observation: NativeObservationLimits,
    },
}
/// Explicit finite caller policy, not a source grant or observation result.
pub struct NativeObservationLimits {
    source_attempts: u64,
    source_read_calls: u64,
    source_returned_bytes: u64,
    source_files: usize,
    worker_attempts: u64,
    worker_updates: u64,
    host_updates: u64,
}
impl NativeObservationLimits {
    pub fn source_attempts(&self) -> u64 {
        self.source_attempts
    }
    pub fn source_read_calls(&self) -> u64 {
        self.source_read_calls
    }
    pub fn source_returned_bytes(&self) -> u64 {
        self.source_returned_bytes
    }
    pub fn source_files(&self) -> usize {
        self.source_files
    }
    pub fn worker_attempts(&self) -> u64 {
        self.worker_attempts
    }
    pub fn worker_updates(&self) -> u64 {
        self.worker_updates
    }
    pub fn host_updates(&self) -> u64 {
        self.host_updates
    }
    fn from_document(value: &Document) -> Result<Self, String> {
        use super::model_originals::workflow::pipeline::policy::{closed, get};
        fn count(value: &Document) -> Result<u64, String> {
            let Document::Number(number) = value else {
                return Err("native observation count requires canonical u64".into());
            };
            let token = number.as_str();
            if token.is_empty()
                || !token.bytes().all(|byte| byte.is_ascii_digit())
                || (token.len() > 1 && token.starts_with('0'))
            {
                return Err("native observation count requires canonical u64".into());
            }
            token
                .parse()
                .map_err(|_| "native observation count exceeds u64".into())
        }
        let fields = closed(value, &["source", "workers", "host"])?;
        let source = closed(
            get(fields, "source")?,
            &["attempts", "readCalls", "returnedBytes", "files"],
        )?;
        let workers = closed(get(fields, "workers")?, &["attempts", "updates"])?;
        let host = closed(get(fields, "host")?, &["updates"])?;
        Ok(Self {
            source_attempts: count(get(source, "attempts")?)?,
            source_read_calls: count(get(source, "readCalls")?)?,
            source_returned_bytes: count(get(source, "returnedBytes")?)?,
            source_files: usize::try_from(count(get(source, "files")?)?)
                .map_err(|_| "native witness count exceeds usize")?,
            worker_attempts: count(get(workers, "attempts")?)?,
            worker_updates: count(get(workers, "updates")?)?,
            host_updates: count(get(host, "updates")?)?,
        })
    }
}
impl RunConfiguration {
    pub fn native_observation_limits(&self) -> Option<&NativeObservationLimits> {
        match &self.mode {
            Configuration::NativeOriginals { observation, .. } => Some(observation),
            _ => None,
        }
    }
    pub fn adapter_protocol(&self) -> AdapterProtocol {
        match self.mode {
            Configuration::Historical => AdapterProtocol::HistoricalNewline,
            Configuration::ModelOriginals(_) => AdapterProtocol::ContentLength,
            Configuration::NativeOriginals { .. } => AdapterProtocol::ContentLength,
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
            Some(Document::String(kind)) if kind == "model-originals-native" => {
                use super::model_originals::workflow::pipeline::policy::{closed, get};
                let fields = closed(&document, &["kind", "checker", "observation"])?;
                // Only the new observation policy has canonical-token rules.
                // Borrow its original subtree after the shared duplicate/shape
                // check, preserving all historical checker count semantics.
                #[derive(serde::Deserialize)]
                struct RawObservation<'a> {
                    #[serde(borrow)]
                    observation: &'a serde_json::value::RawValue,
                }
                let raw: RawObservation<'_> = serde_json::from_str(raw)
                    .map_err(|_| "native observation policy is not JSON")?;
                let observation =
                    Document::parse_unsigned_counts(raw.observation.get().as_bytes())?;
                Configuration::NativeOriginals {
                    checker: Box::new(Policy::from_document(get(fields, "checker")?)?),
                    observation: NativeObservationLimits::from_document(&observation)?,
                }
            }
            _ => return Err("policy has unknown kind or fields".into()),
        };
        Ok(Self { mode })
    }
}
