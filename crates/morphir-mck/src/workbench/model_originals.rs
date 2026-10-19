//! Independent model-originals protocol boundaries used by the maintained MCK.
//! Parsing claims and identifiers never grants session, filesystem or execution
//! authority. Actual adapter observations and capture lifecycle remain separate.
use super::contract::OfflineOnly;
use serde::Deserialize;
use serde_json::Value;
use std::{collections::BTreeMap, fmt, sync::OnceLock};
use unicode_casefold::UnicodeCaseFold;
use unicode_normalization::UnicodeNormalization;

mod inventory;
pub use inventory::{Inventory, InventoryEntry, InventoryError, InventorySha256};
mod transfer;
pub use transfer::{
    CaptureExpectation, CaptureInventory, CheckedStream, Exchange, FailureCode, ProjectionRefusal,
    ProjectionStatus, RemoteFailure, RpcFailureKind, TransferError,
};
mod evidence;
pub use evidence::{
    CaptureEvidence, CheckedOriginalsEvidence, EvidenceError, ExpectedBytes, ExpectedOriginalEntry,
    ExpectedOriginals, OriginalTransfer,
};
mod projection;
pub use projection::{
    CheckedProjectionEvidence, ComparisonResource, ExpectedProjection, ModelRelease,
    ProjectionError, ProjectionWorkLimits,
};

/// Inclusive bound on the complete JSON-RPC request, before parsing.
pub const MAX_REQUEST_BYTES: usize = 16 * 1024;
const MAX_RECORD_BYTES: usize = 64 * 1024 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InvalidFrame {
    FrameLimit,
    MalformedJson,
    Shape,
    Identity,
    Range,
    Path,
    PathSet,
}
impl fmt::Display for InvalidFrame {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::FrameLimit => "model-originals frame exceeds its byte bound",
            Self::MalformedJson => "model-originals frame is not strict duplicate-free JSON",
            Self::Shape => "model-originals frame differs from the exact closed schema",
            Self::Identity => "model-originals identity exceeds UTF-8 or control bounds",
            Self::Range => "model-originals number differs from its exact range or syntax",
            Self::Path => "model-originals root path is not portable or exceeds its bound",
            Self::PathSet => "model-originals roots overlap or contain normalized aliases",
        })
    }
}
impl std::error::Error for InvalidFrame {}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RequestId(u64);
impl RequestId {
    pub fn get(self) -> u64 {
        self.0
    }
    fn parse(token: &str) -> Result<Self, InvalidFrame> {
        if token.is_empty() || !token.bytes().all(|b| b.is_ascii_digit()) {
            return Err(InvalidFrame::Range);
        }
        token.parse().map(Self).map_err(|_| InvalidFrame::Range)
    }
}
macro_rules! bounded_identity {
    ($name:ident, $limit:expr) => {
        #[derive(Debug, Clone, PartialEq, Eq)]
        pub struct $name(String);
        impl $name {
            pub fn as_str(&self) -> &str {
                &self.0
            }
            pub fn new(text: &str) -> Result<Self, InvalidFrame> {
                if text.is_empty() || text.len() > $limit || text.chars().any(char::is_control) {
                    return Err(InvalidFrame::Identity);
                }
                Ok(Self(text.to_owned()))
            }
            fn parse(value: &Value) -> Result<Self, InvalidFrame> {
                Self::new(value.as_str().ok_or(InvalidFrame::Identity)?)
            }
        }
    };
}
bounded_identity!(ProviderId, 128);
bounded_identity!(CaptureId, 128);
bounded_identity!(EntryId, 128);
bounded_identity!(SourceLocator, 4096);
bounded_identity!(ProjectId, 12288);
bounded_identity!(SessionId, 128);

macro_rules! bounded_count {
    ($name:ident, $minimum:expr, $maximum:expr) => {
        #[derive(Debug, Clone, Copy, PartialEq, Eq)]
        pub struct $name(usize);
        impl $name {
            pub fn get(self) -> usize {
                self.0
            }
            fn parse(value: &Value) -> Result<Self, InvalidFrame> {
                let count =
                    super::artifacts::integer(value, $maximum).map_err(|_| InvalidFrame::Range)?;
                if !($minimum..=$maximum).contains(&count) {
                    return Err(InvalidFrame::Range);
                }
                Ok(Self(count))
            }
        }
    };
}
bounded_count!(InventoryIndex, 0, 100064);
bounded_count!(PageSize, 1, 256);
bounded_count!(ByteOffset, 0, 67108864);
bounded_count!(ChunkSize, 1, 65536);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SourceIdentity {
    pub provider: ProviderId,
    pub locator: SourceLocator,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CaptureScope {
    Primary,
    Complete,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SemanticRequest {
    None,
    Projection,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReadTarget {
    Original { entry: EntryId },
    SemanticProjection,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Parameters {
    Capture {
        source: SourceIdentity,
        project: ProjectId,
        scope: CaptureScope,
        semantic: SemanticRequest,
    },
    Inventory {
        capture: CaptureId,
        start: InventoryIndex,
        maximum: PageSize,
    },
    Read {
        capture: CaptureId,
        target: ReadTarget,
        offset: ByteOffset,
        maximum: ChunkSize,
    },
    Release {
        capture: CaptureId,
    },
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Request {
    id: RequestId,
    parameters: Parameters,
}
impl Request {
    pub fn id(&self) -> RequestId {
        self.id
    }
    pub fn parameters(&self) -> &Parameters {
        &self.parameters
    }
    pub fn parse(raw: &str) -> Result<Self, InvalidFrame> {
        let value = parse(raw, MAX_REQUEST_BYTES)?;
        // Number normalizes negative zero. Retain the actual envelope token
        // separately after the duplicate-aware traversal above.
        #[derive(Deserialize)]
        struct RawId<'a> {
            #[serde(borrow)]
            id: &'a serde_json::value::RawValue,
        }
        let envelope: RawId<'_> = serde_json::from_str(raw).map_err(|_| InvalidFrame::Shape)?;
        let id = RequestId::parse(envelope.id.get())?;
        let params = &value["params"];
        let parameters = match value["method"].as_str() {
            Some("morphir.model-originals.capture") => Parameters::Capture {
                source: SourceIdentity {
                    provider: ProviderId::parse(&params["source"]["providerId"])?,
                    locator: SourceLocator::parse(&params["source"]["locator"])?,
                },
                project: ProjectId::parse(&params["projectId"])?,
                scope: match params["scope"].as_str() {
                    Some("primary") => CaptureScope::Primary,
                    Some("complete") => CaptureScope::Complete,
                    _ => return Err(InvalidFrame::Shape),
                },
                semantic: match params["semantic"].as_str() {
                    Some("none") => SemanticRequest::None,
                    Some("projection") => SemanticRequest::Projection,
                    _ => return Err(InvalidFrame::Shape),
                },
            },
            Some("morphir.model-originals.inventory") => Parameters::Inventory {
                capture: CaptureId::parse(&params["captureId"])?,
                start: InventoryIndex::parse(&params["startIndex"])?,
                maximum: PageSize::parse(&params["maxEntries"])?,
            },
            Some("morphir.model-originals.read") => Parameters::Read {
                capture: CaptureId::parse(&params["captureId"])?,
                target: match params["target"]["kind"].as_str() {
                    Some("original") => ReadTarget::Original {
                        entry: EntryId::parse(&params["target"]["entryId"])?,
                    },
                    Some("semantic-projection") => ReadTarget::SemanticProjection,
                    _ => return Err(InvalidFrame::Shape),
                },
                offset: ByteOffset::parse(&params["offset"])?,
                maximum: ChunkSize::parse(&params["maxBytes"])?,
            },
            Some("morphir.model-originals.release") => Parameters::Release {
                capture: CaptureId::parse(&params["captureId"])?,
            },
            _ => return Err(InvalidFrame::Shape),
        };
        // Validate exact mathematical integers before jsonschema's f64-based
        // numeric limits can encounter an extreme exponent or round a fraction.
        validate(Schema::Request, &value)?;
        Ok(Self { id, parameters })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RootPath(String);
impl RootPath {
    pub fn as_str(&self) -> &str {
        &self.0
    }
    fn parse(value: &Value) -> Result<Self, InvalidFrame> {
        let path = portable_path(value)?;
        if path.split('/').count() > 128 {
            return Err(InvalidFrame::Path);
        }
        Ok(Self(path.to_owned()))
    }
}
// Inventory descendants have their own depth relative to the selected root.
// Reusing RootPath's 128-component limit would reject valid deep descendants.
fn portable_path(value: &Value) -> Result<&str, InvalidFrame> {
    let path = value.as_str().ok_or(InvalidFrame::Path)?;
    if path.is_empty()
        || path.len() > 16000
        || path.chars().count() > 4000
        || path.encode_utf16().count() > 8000
        || path.chars().any(char::is_control)
    {
        return Err(InvalidFrame::Path);
    }
    for part in path.split('/') {
        let stem = part
            .split('.')
            .next()
            .unwrap_or_default()
            .trim_end_matches(' ')
            .to_ascii_uppercase();
        let numbered = |s: &str| {
            matches!(
                s,
                "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" | "¹" | "²" | "³"
            )
        };
        let reserved = matches!(
            stem.as_str(),
            "CON" | "PRN" | "AUX" | "NUL" | "CONIN$" | "CONOUT$"
        ) || stem.strip_prefix("COM").is_some_and(numbered)
            || stem.strip_prefix("LPT").is_some_and(numbered);
        if part.is_empty()
            || part.len() > 255
            || part.encode_utf16().count() > 255
            || matches!(part, "." | "..")
            || part.ends_with(['.', ' '])
            || part.contains(['<', '>', ':', '"', '\\', '|', '?', '*'])
            || reserved
        {
            return Err(InvalidFrame::Path);
        }
    }
    Ok(path)
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RootKind {
    File,
    Directory,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Root {
    pub kind: RootKind,
    pub path: RootPath,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Declaration {
    companions: Vec<Root>,
}
impl Declaration {
    pub fn companions(&self) -> &[Root] {
        &self.companions
    }
    /// Checks the reserved declaration value only. Absence, compile-record
    /// ownership and compatibility with the actual primary belong to the caller.
    pub fn parse(raw: &str) -> Result<Self, InvalidFrame> {
        let value = parse(raw, MAX_RECORD_BYTES)?;
        validate(Schema::Declaration, &value)?;
        let companions = value["companions"]
            .as_array()
            .ok_or(InvalidFrame::Shape)?
            .iter()
            .map(|root| {
                let kind = match root["kind"].as_str() {
                    Some("file") => RootKind::File,
                    Some("directory") => RootKind::Directory,
                    _ => return Err(InvalidFrame::Shape),
                };
                Ok(Root {
                    kind,
                    path: RootPath::parse(&root["path"])?,
                })
            })
            .collect::<Result<Vec<_>, InvalidFrame>>()?;
        let mut prefixes = BTreeMap::new();
        let mut complete = Vec::new();
        for root in &companions {
            let path = root.path.as_str();
            let key = folded(path);
            if complete.iter().any(|previous: &String| {
                key == *previous
                    || key
                        .strip_prefix(previous)
                        .is_some_and(|s| s.starts_with('/'))
                    || previous
                        .strip_prefix(&key)
                        .is_some_and(|s| s.starts_with('/'))
            }) {
                return Err(InvalidFrame::PathSet);
            }
            for end in path
                .match_indices('/')
                .map(|(i, _)| i)
                .chain(std::iter::once(path.len()))
            {
                let prefix = &path[..end];
                if let Some(previous) = prefixes.insert(folded(prefix), prefix)
                    && previous != prefix
                {
                    return Err(InvalidFrame::PathSet);
                }
            }
            complete.push(key);
        }
        Ok(Self { companions })
    }
}
fn folded(path: &str) -> String {
    path.nfkc().case_fold().nfc().collect()
}
fn parse(raw: &str, limit: usize) -> Result<Value, InvalidFrame> {
    if raw.len() > limit {
        return Err(InvalidFrame::FrameLimit);
    }
    crate::json::strict::parse_exact(raw).map_err(|_| InvalidFrame::MalformedJson)
}
enum Schema {
    Request,
    Declaration,
    Ready,
    Entry,
    Inventory,
    InventoryResult,
    ReadResult,
}
fn validate(schema: Schema, value: &Value) -> Result<(), InvalidFrame> {
    static VALIDATORS: OnceLock<[jsonschema::Validator; 7]> = OnceLock::new();
    let validators = VALIDATORS.get_or_init(|| {
        let resources = [
            include_str!("../../../../spec/workbench/model-originals/0.1.0-draft.1/schemas/definitions.schema.json"),
            include_str!("../../../../spec/workbench/model-originals/0.1.0-draft.1/schemas/request.schema.json"),
            include_str!("../../../../spec/workbench/model-originals/0.1.0-draft.1/schemas/declaration.schema.json"),
        ].map(|text|serde_json::from_str::<Value>(text).expect("fixed model originals schema"));
        let compile = |schema: &Value| {
            let mut options = jsonschema::options();
            options.with_draft(jsonschema::Draft::Draft202012).with_retriever(OfflineOnly);
            for resource in &resources {
                options.with_resource(resource["$id"].as_str().expect("schema ID"),jsonschema::Resource::from_contents(resource.clone()).expect("schema resource"));
            }
            options.build(schema).expect("fixed offline model originals schema")
        };
        let reference = |name: &str| serde_json::json!({"$ref":format!("{}#/$defs/{name}",resources[0]["$id"].as_str().expect("definitions ID"))});
        [compile(&resources[1]),compile(&resources[2]),compile(&reference("ready")),compile(&reference("entry")),compile(&reference("inventory")),compile(&reference("inventoryResult")),compile(&reference("readResult"))]
    });
    let validator = match schema {
        Schema::Request => &validators[0],
        Schema::Declaration => &validators[1],
        Schema::Ready => &validators[2],
        Schema::Entry => &validators[3],
        Schema::Inventory => &validators[4],
        Schema::InventoryResult => &validators[5],
        Schema::ReadResult => &validators[6],
    };
    validator.validate(value).map_err(|_| InvalidFrame::Shape)
}
