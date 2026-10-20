//! Closed original-byte protocol values. Labels never grant filesystem access.
use base64::{Engine as _, engine::general_purpose::STANDARD};
use serde_json::{Map, Value, json};

use super::{CaptureError, CaptureId, CaptureScope, CapturedSources, SourceKind};

pub(crate) const PROFILE: &str = "morphir/workbench/model-originals";
pub(crate) const MAX_REQUEST_BYTES: usize = 16 * 1024;
pub(crate) const MAX_REPLY_BYTES: usize = 128 * 1024;

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub(crate) enum WireError {
    InvalidRequest,
    InvalidIdentity,
    InvalidRange,
    Unavailable,
    ReplyLimit,
    Capture(CaptureError),
}
impl From<CaptureError> for WireError {
    fn from(error: CaptureError) -> Self {
        Self::Capture(error)
    }
}
impl WireError {
    pub(crate) fn code(self) -> &'static str {
        match self {
            Self::InvalidRequest => "model_originals.invalid_request",
            Self::InvalidIdentity => "model_originals.invalid_identity",
            Self::InvalidRange => "model_originals.invalid_range",
            Self::Unavailable => "model_originals.unavailable",
            Self::ReplyLimit => "model_originals.reply_limit",
            Self::Capture(error) => match error {
                CaptureError::InvalidPath => "model_originals.invalid_path",
                CaptureError::InvalidPathSet => "model_originals.invalid_path_set",
                CaptureError::InvalidDeclaration => "model_originals.invalid_declaration",
                CaptureError::SourceLimit => "model_originals.source_limit",
                CaptureError::RecordLimit | CaptureError::InventoryLimit => {
                    "model_originals.inventory_limit"
                }
                CaptureError::Timeout => "model_originals.timeout",
                CaptureError::Capacity => "model_originals.capacity",
                CaptureError::ActiveCapture => "model_originals.active_capture",
                CaptureError::UnknownHandle => "model_originals.unknown_handle",
                CaptureError::InvalidIdentity => "model_originals.invalid_identity",
                CaptureError::UnsupportedRepresentation => "model_originals.unavailable",
                CaptureError::InvalidRecord | CaptureError::CaptureFailed => {
                    "model_originals.capture_failed"
                }
            },
        }
    }
}

#[derive(Debug, Clone)]
pub(crate) struct Binding {
    session: String,
    provider: String,
    locator: String,
    project: String,
}
impl Binding {
    pub(crate) fn new(
        session: &str,
        provider: &str,
        locator: &str,
        project: &str,
    ) -> Result<Self, WireError> {
        Ok(Self {
            session: identity(session, 128)?,
            provider: identity(provider, 128)?,
            locator: identity(locator, 4096)?,
            project: identity(project, 12288)?,
        })
    }
    pub(crate) fn retained_bound() -> usize {
        std::mem::size_of::<Self>()
            + std::mem::size_of::<super::RetainedEvidenceCredit>()
            + 128
            + 128
            + 4096
            + 12288
    }
    fn json(&self) -> Value {
        json!({"sessionId": self.session, "source": {"providerId": self.provider, "locator": self.locator}, "projectId": self.project})
    }
}

pub(crate) enum SemanticRequest {
    None,
    Projection,
}
pub(crate) enum Target {
    Original(String),
    Projection,
}
pub(crate) enum Parameters {
    Capture {
        provider: String,
        locator: String,
        project: String,
        scope: CaptureScope,
        semantic: SemanticRequest,
    },
    Inventory {
        capture: CaptureId,
        start: usize,
        maximum: usize,
    },
    Read {
        capture: CaptureId,
        target: Target,
        offset: usize,
        maximum: usize,
    },
    Release {
        capture: CaptureId,
    },
}
fn identity(text: &str, limit: usize) -> Result<String, WireError> {
    if text.is_empty() || text.len() > limit || text.chars().any(char::is_control) {
        return Err(WireError::InvalidIdentity);
    }
    Ok(text.to_owned())
}
fn string(value: &Value, limit: usize) -> Result<String, WireError> {
    identity(value.as_str().ok_or(WireError::InvalidIdentity)?, limit)
}
fn object(value: &Value, fields: &[&str]) -> Result<Map<String, Value>, WireError> {
    let map = value.as_object().ok_or(WireError::InvalidRequest)?;
    if map.len() != fields.len() || fields.iter().any(|key| !map.contains_key(*key)) {
        return Err(WireError::InvalidRequest);
    }
    Ok(map.clone())
}
fn count(value: &Value, min: usize, max: usize) -> Result<usize, WireError> {
    super::super::artifacts::exact_bounded_integer(value, max)
        .filter(|value| *value >= min)
        .ok_or(WireError::InvalidRange)
}
pub(crate) fn decode(method: &str, params: &Value) -> Result<Parameters, WireError> {
    let fields: &[&str] = match method {
        "morphir.model-originals.capture" => &[
            "contractVersion",
            "source",
            "projectId",
            "scope",
            "semantic",
        ],
        "morphir.model-originals.inventory" => {
            &["contractVersion", "captureId", "startIndex", "maxEntries"]
        }
        "morphir.model-originals.read" => &[
            "contractVersion",
            "captureId",
            "target",
            "offset",
            "maxBytes",
        ],
        "morphir.model-originals.release" => &["contractVersion", "captureId"],
        _ => return Err(WireError::InvalidRequest),
    };
    let p = object(params, fields)?;
    if p["contractVersion"] != super::CONTRACT_VERSION {
        return Err(WireError::Unavailable);
    }
    match method {
        "morphir.model-originals.capture" => {
            let source = object(&p["source"], &["providerId", "locator"])?;
            Ok(Parameters::Capture {
                provider: string(&source["providerId"], 128)?,
                locator: string(&source["locator"], 4096)?,
                project: string(&p["projectId"], 12288)?,
                scope: match p["scope"].as_str() {
                    Some("primary") => CaptureScope::Primary,
                    Some("complete") => CaptureScope::Complete,
                    _ => return Err(WireError::InvalidRequest),
                },
                semantic: match p["semantic"].as_str() {
                    Some("none") => SemanticRequest::None,
                    Some("projection") => SemanticRequest::Projection,
                    _ => return Err(WireError::InvalidRequest),
                },
            })
        }
        "morphir.model-originals.inventory" => Ok(Parameters::Inventory {
            capture: CaptureId::parse(&string(&p["captureId"], 128)?)?,
            start: count(&p["startIndex"], 0, super::MAX_ENTRIES)?,
            maximum: count(&p["maxEntries"], 1, 256)?,
        }),
        "morphir.model-originals.read" => {
            let kind = p["target"]["kind"]
                .as_str()
                .ok_or(WireError::InvalidRequest)?;
            let target = match kind {
                "original" => {
                    let t = object(&p["target"], &["kind", "entryId"])?;
                    Target::Original(string(&t["entryId"], 128)?)
                }
                "semantic-projection" => {
                    object(&p["target"], &["kind"])?;
                    Target::Projection
                }
                _ => return Err(WireError::InvalidRequest),
            };
            Ok(Parameters::Read {
                capture: CaptureId::parse(&string(&p["captureId"], 128)?)?,
                target,
                offset: count(&p["offset"], 0, super::MAX_SOURCE_BYTES)?,
                maximum: count(&p["maxBytes"], 1, 65536)?,
            })
        }
        _ => Ok(Parameters::Release {
            capture: CaptureId::parse(&string(&p["captureId"], 128)?)?,
        }),
    }
}

fn envelope_size(result: &Value) -> usize {
    serde_json::to_vec(&json!({"jsonrpc":"2.0", "id":u64::MAX, "result":result}))
        .expect("JSON value")
        .len()
}
pub(crate) fn bounded(result: Value) -> Result<Value, WireError> {
    if envelope_size(&result) > MAX_REPLY_BYTES {
        Err(WireError::ReplyLimit)
    } else {
        Ok(result)
    }
}
pub(crate) fn ready(
    binding: &Binding,
    id: &CaptureId,
    sources: &CapturedSources,
    source_version: Value,
    semantic: SemanticRequest,
) -> Result<Value, WireError> {
    let record = sources.record();
    let files = sources
        .entries()
        .iter()
        .filter(|entry| entry.kind() == SourceKind::File)
        .count();
    bounded(json!({
        "profile":PROFILE,"contractVersion":super::CONTRACT_VERSION,"status":"ready","binding":binding.json(),"captureId":id,
        "coverage":match sources.coverage() { CaptureScope::Primary => json!({"kind":"primary"}), CaptureScope::Complete => json!({"kind":"complete","declaration":super::CONTRACT_VERSION}) },
        "origin":{"kind":"compiled","record":{"byteLength":record.byte_length(),"sha256":record.sha256(),"schema":1,"task":"compile","module":record.module().as_str(),"ir":record.descriptor().as_devkit_descriptor()}},
        "primary":sources.primary(),"companions":sources.companions(),"sourceFormatVersion":source_version,"projection":match semantic { SemanticRequest::None => json!({"status":"not-requested"}), SemanticRequest::Projection => json!({"status":"unavailable","reason":"unsupported_representation"}) },
        "inventory":{"entryCount":sources.entries().len(),"fileCount":files,"directoryCount":sources.entries().len()-files,"sourceByteLength":sources.source_byte_length(),"sha256":sources.inventory_sha256()}
    }))
}
pub(crate) fn inventory(
    binding: &Binding,
    id: &CaptureId,
    sources: &CapturedSources,
    start: usize,
    maximum: usize,
) -> Result<Value, WireError> {
    if start > sources.entries().len() || !(1..=256).contains(&maximum) {
        return Err(WireError::InvalidRange);
    }
    let page = |entries: Vec<Value>| {
        let next = start + entries.len();
        json!({"profile":PROFILE,"contractVersion":super::CONTRACT_VERSION,"binding":binding.json(),"captureId":id,"inventorySha256":sources.inventory_sha256(),"startIndex":start,"entries":entries,"next":if next == sources.entries().len() { json!({"kind":"complete"}) } else { json!({"kind":"more","startIndex":next}) }})
    };
    let mut entries = Vec::new();
    for entry in sources.entries().iter().skip(start).take(maximum) {
        entries.push(match entry.kind() {
            SourceKind::Directory => json!({"kind":"directory","entryId":entry.entry_id(),"path":entry.path()}),
            SourceKind::File => json!({"kind":"file","entryId":entry.entry_id(),"path":entry.path(),"byteLength":entry.byte_length().expect("file"),"sha256":entry.sha256().expect("file")}),
        });
        if envelope_size(&page(entries.clone())) > MAX_REPLY_BYTES {
            entries.pop();
            if entries.is_empty() {
                return Err(WireError::ReplyLimit);
            }
            break;
        }
    }
    bounded(page(entries))
}
pub(crate) fn read(
    binding: &Binding,
    id: &CaptureId,
    sources: &CapturedSources,
    target: Target,
    offset: usize,
    maximum: usize,
) -> Result<Value, WireError> {
    if !(1..=65536).contains(&maximum) {
        return Err(WireError::InvalidRange);
    }
    let Target::Original(entry_id) = target else {
        return Err(WireError::Unavailable);
    };
    let entry = sources
        .entries()
        .iter()
        .find(|entry| entry.entry_id() == entry_id)
        .ok_or(CaptureError::UnknownHandle)?;
    let bytes = sources
        .file_bytes(entry.path())
        .ok_or(WireError::InvalidRange)?;
    if offset > bytes.len() {
        return Err(WireError::InvalidRange);
    }
    let end = bytes.len().min(offset + maximum);
    bounded(
        json!({"profile":PROFILE,"contractVersion":super::CONTRACT_VERSION,"binding":binding.json(),"captureId":id,"target":{"kind":"original","entryId":entry_id},"offset":offset,"nextOffset":end,"content":STANDARD.encode(&bytes[offset..end])}),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn counts_are_mathematical_integers_without_rounding() {
        let p = |offset: &str| {
            morphir_mck::json::parse_exact_document(&format!(r#"{{"contractVersion":"0.1.0-draft.1","captureId":"c","target":{{"kind":"original","entryId":"e"}},"offset":{offset},"maxBytes":1}}"#)).unwrap()
        };
        for offset in ["0", "1.0", "10e-1"] {
            assert!(decode("morphir.model-originals.read", &p(offset)).is_ok());
        }
        for offset in [
            "0.00000000000000000001",
            "67108864.00000000001",
            "1e999999",
            "1e9223372036854775807",
        ] {
            assert!(matches!(
                decode("morphir.model-originals.read", &p(offset)),
                Err(WireError::InvalidRange)
            ));
        }
    }
    #[test]
    fn source_pair_and_targets_are_closed() {
        let mut p = json!({"contractVersion":"0.1.0-draft.1","source":{"providerId":"p","locator":"l"},"projectId":"project","scope":"complete","semantic":"none"});
        assert!(decode("morphir.model-originals.capture", &p).is_ok());
        p["source"]["path"] = json!("/outside");
        assert!(matches!(
            decode("morphir.model-originals.capture", &p),
            Err(WireError::InvalidRequest)
        ));
    }
}
