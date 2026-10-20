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
        private_record: RecordRetentionLimits,
    },
    InstalledOriginals {
        checker: Box<Policy>,
        observation: NativeObservationLimits,
        private_record: RecordRetentionLimits,
        installed_observation: InstalledObservationLimits,
    },
}
/// Explicit cumulative native-record Vec capacity, separate from all existing
/// source/work/serialized-capture policies. Zero installs no positive credit.
pub struct RecordRetentionLimits {
    retained_bytes: u64,
}
/// Explicit whole-run permissions for retained installed-client observation.
/// Zero provides no positive credit. These are neither OS grants nor measured
/// reads, process starts, current residency, allocator peaks or RSS bounds.
pub struct InstalledObservationLimits {
    retained_bytes: u64,
    stdout_prefix_bytes: u64,
    stderr_prefix_bytes: u64,
    snapshot_read_bytes: u64,
    byte_visits: u64,
    records: u64,
}
impl InstalledObservationLimits {
    pub fn retained_bytes(&self) -> u64 {
        self.retained_bytes
    }
    pub fn stdout_prefix_bytes(&self) -> u64 {
        self.stdout_prefix_bytes
    }
    pub fn stderr_prefix_bytes(&self) -> u64 {
        self.stderr_prefix_bytes
    }
    pub fn snapshot_read_bytes(&self) -> u64 {
        self.snapshot_read_bytes
    }
    pub fn byte_visits(&self) -> u64 {
        self.byte_visits
    }
    pub fn records(&self) -> u64 {
        self.records
    }
    /// The caller must preserve unsigned count tokens with the existing
    /// Document::parse_unsigned_counts boundary. No selected dispatch or
    /// production default is introduced by this component-only parser.
    pub(super) fn from_document(value: &Document) -> Result<Self, String> {
        use super::model_originals::workflow::pipeline::policy::{closed, get};
        fn count(value: &Document) -> Result<u64, String> {
            let Document::Number(number) = value else {
                return Err("installed observation count requires canonical u64".into());
            };
            let token = number.as_str();
            if token.is_empty()
                || !token.bytes().all(|byte| byte.is_ascii_digit())
                || (token.len() > 1 && token.starts_with('0'))
            {
                return Err("installed observation count requires canonical u64".into());
            }
            token
                .parse()
                .map_err(|_| "installed observation count exceeds u64".into())
        }
        let fields = closed(
            value,
            &[
                "rpcFrames",
                "retainedBytes",
                "stdoutPrefixBytes",
                "stderrPrefixBytes",
                "snapshotReadBytes",
                "byteVisits",
                "records",
            ],
        )?;
        if !matches!(get(fields, "rpcFrames")?, Document::String(mode) if mode == "checker-capture")
        {
            return Err("installed observation requires checker-capture RPC permission".into());
        }
        Ok(Self {
            retained_bytes: count(get(fields, "retainedBytes")?)?,
            stdout_prefix_bytes: count(get(fields, "stdoutPrefixBytes")?)?,
            stderr_prefix_bytes: count(get(fields, "stderrPrefixBytes")?)?,
            snapshot_read_bytes: count(get(fields, "snapshotReadBytes")?)?,
            byte_visits: count(get(fields, "byteVisits")?)?,
            records: count(get(fields, "records")?)?,
        })
    }
}
impl RecordRetentionLimits {
    pub fn retained_bytes(&self) -> u64 {
        self.retained_bytes
    }
    fn from_document(value: &Document) -> Result<Self, String> {
        use super::model_originals::workflow::pipeline::policy::{closed, get};
        let fields = closed(value, &["retainedBytes"])?;
        let Document::Number(number) = get(fields, "retainedBytes")? else {
            return Err("record retention requires canonical u64".into());
        };
        let token = number.as_str();
        if token.is_empty()
            || !token.bytes().all(|byte| byte.is_ascii_digit())
            || (token.len() > 1 && token.starts_with('0'))
        {
            return Err("record retention requires canonical u64".into());
        }
        Ok(Self {
            retained_bytes: token.parse().map_err(|_| "record retention exceeds u64")?,
        })
    }
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
    pub fn installed_observation_limits(&self) -> Option<&InstalledObservationLimits> {
        match &self.mode {
            Configuration::InstalledOriginals {
                installed_observation,
                ..
            } => Some(installed_observation),
            _ => None,
        }
    }
    pub fn private_record_limits(&self) -> Option<&RecordRetentionLimits> {
        match &self.mode {
            Configuration::NativeOriginals { private_record, .. }
            | Configuration::InstalledOriginals { private_record, .. } => Some(private_record),
            _ => None,
        }
    }
    pub fn native_observation_limits(&self) -> Option<&NativeObservationLimits> {
        match &self.mode {
            Configuration::NativeOriginals { observation, .. }
            | Configuration::InstalledOriginals { observation, .. } => Some(observation),
            _ => None,
        }
    }
    pub fn adapter_protocol(&self) -> AdapterProtocol {
        match self.mode {
            Configuration::Historical => AdapterProtocol::HistoricalNewline,
            Configuration::ModelOriginals(_) => AdapterProtocol::ContentLength,
            Configuration::NativeOriginals { .. } | Configuration::InstalledOriginals { .. } => {
                AdapterProtocol::ContentLength
            }
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
                let fields = closed(
                    &document,
                    &["kind", "checker", "observation", "privateRecord"],
                )?;
                // Only the new observation policy has canonical-token rules.
                // Borrow its original subtree after the shared duplicate/shape
                // check, preserving all historical checker count semantics.
                #[derive(serde::Deserialize)]
                struct RawObservation<'a> {
                    #[serde(borrow)]
                    observation: &'a serde_json::value::RawValue,
                    #[serde(borrow, rename = "privateRecord")]
                    private_record: &'a serde_json::value::RawValue,
                }
                let raw: RawObservation<'_> = serde_json::from_str(raw)
                    .map_err(|_| "native observation policy is not JSON")?;
                let observation =
                    Document::parse_unsigned_counts(raw.observation.get().as_bytes())?;
                let private_record =
                    Document::parse_unsigned_counts(raw.private_record.get().as_bytes())?;
                Configuration::NativeOriginals {
                    checker: Box::new(Policy::from_document(get(fields, "checker")?)?),
                    observation: NativeObservationLimits::from_document(&observation)?,
                    private_record: RecordRetentionLimits::from_document(&private_record)?,
                }
            }
            Some(Document::String(kind)) if kind == "model-originals-installed-client" => {
                use super::model_originals::workflow::pipeline::policy::{closed, get};
                let fields = closed(
                    &document,
                    &[
                        "kind",
                        "checker",
                        "observation",
                        "privateRecord",
                        "installedObservation",
                    ],
                )?;
                #[derive(serde::Deserialize)]
                struct RawInstalled<'a> {
                    #[serde(borrow)]
                    observation: &'a serde_json::value::RawValue,
                    #[serde(borrow, rename = "privateRecord")]
                    private_record: &'a serde_json::value::RawValue,
                    #[serde(borrow, rename = "installedObservation")]
                    installed_observation: &'a serde_json::value::RawValue,
                }
                let raw: RawInstalled<'_> = serde_json::from_str(raw)
                    .map_err(|_| "installed observation policy is not JSON")?;
                Configuration::InstalledOriginals {
                    checker: Box::new(Policy::from_document(get(fields, "checker")?)?),
                    observation: NativeObservationLimits::from_document(
                        &Document::parse_unsigned_counts(raw.observation.get().as_bytes())?,
                    )?,
                    private_record: RecordRetentionLimits::from_document(
                        &Document::parse_unsigned_counts(raw.private_record.get().as_bytes())?,
                    )?,
                    installed_observation: InstalledObservationLimits::from_document(
                        &Document::parse_unsigned_counts(
                            raw.installed_observation.get().as_bytes(),
                        )?,
                    )?,
                }
            }
            _ => return Err("policy has unknown kind or fields".into()),
        };
        Ok(Self { mode })
    }
}
