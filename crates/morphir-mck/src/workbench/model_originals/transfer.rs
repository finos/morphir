//! Independent transport evidence. Supplied expectations bind observations; they
//! do not authenticate a connection, grant a filesystem capability or publish an
//! original/model owner. Those decisions require actual host/client evidence.
use super::inventory::{EntryContent, Summary, count, hash, ready_metadata};
use super::{
    CaptureId, EntryId, InvalidFrame, Inventory, InventoryEntry, InventoryError, InventoryIndex,
    Parameters, ProjectId, ProviderId, ReadTarget, Request, RequestId, Root, Schema, SessionId,
    SourceIdentity, SourceLocator, parse, validate,
};
use base64::{Engine as _, engine::general_purpose::STANDARD};
use serde::Deserialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::fmt;

const MAX_REPLY_BYTES: usize = 128 * 1024;
const MAX_SOURCE_BYTES: usize = 64 * 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransferError {
    Frame(InvalidFrame),
    Inventory(InventoryError),
    Method,
    RequestIdentity,
    Binding,
    Capture,
    Progress,
    Pagination,
    Encoding,
    Target,
    ContentDigest,
    MetadataBudget,
    Refused(RemoteFailure),
}
impl From<InvalidFrame> for TransferError {
    fn from(error: InvalidFrame) -> Self {
        Self::Frame(error)
    }
}
impl From<InventoryError> for TransferError {
    fn from(error: InventoryError) -> Self {
        Self::Inventory(error)
    }
}
impl fmt::Display for TransferError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Frame(_) => "invalid model-originals transfer frame",
            Self::Inventory(_) => "inconsistent model-originals inventory",
            Self::Method => "exchange has the wrong model-originals method",
            Self::RequestIdentity => "reply does not preserve the exact request identity",
            Self::Binding => "reply differs from its expected session/source/project binding",
            Self::Capture => "exchange differs from its expected capture",
            Self::Progress => "exchange does not make exact contiguous progress",
            Self::Pagination => "inventory page is not the largest permitted prefix",
            Self::Encoding => "reply does not use the required compact encoding",
            Self::Target => "read target has no matching original/projection descriptor",
            Self::ContentDigest => "actual transferred bytes differ from the declared digest",
            Self::MetadataBudget => "inventory metadata strings exceed their bound",
            Self::Refused(_) => {
                "exchange returned a remote refusal instead of the expected success"
            }
        })
    }
}
impl std::error::Error for TransferError {}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RpcFailureKind {
    ParseError,
    InvalidParameters,
    ServerError,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FailureCode {
    InvalidRequest,
    InvalidIdentity,
    InvalidPath,
    InvalidPathSet,
    InvalidRange,
    InvalidDeclaration,
    Unavailable,
    UnknownHandle,
    ActiveCapture,
    Capacity,
    SourceLimit,
    InventoryLimit,
    ReplyLimit,
    CaptureFailed,
    Timeout,
}
impl FailureCode {
    fn parse(value: &Value) -> Result<Self, InvalidFrame> {
        Ok(match value.as_str().ok_or(InvalidFrame::Shape)? {
            "model_originals.invalid_request" => Self::InvalidRequest,
            "model_originals.invalid_identity" => Self::InvalidIdentity,
            "model_originals.invalid_path" => Self::InvalidPath,
            "model_originals.invalid_path_set" => Self::InvalidPathSet,
            "model_originals.invalid_range" => Self::InvalidRange,
            "model_originals.invalid_declaration" => Self::InvalidDeclaration,
            "model_originals.unavailable" => Self::Unavailable,
            "model_originals.unknown_handle" => Self::UnknownHandle,
            "model_originals.active_capture" => Self::ActiveCapture,
            "model_originals.capacity" => Self::Capacity,
            "model_originals.source_limit" => Self::SourceLimit,
            "model_originals.inventory_limit" => Self::InventoryLimit,
            "model_originals.reply_limit" => Self::ReplyLimit,
            "model_originals.capture_failed" => Self::CaptureFailed,
            "model_originals.timeout" => Self::Timeout,
            _ => return Err(InvalidFrame::Shape),
        })
    }
}
#[derive(Debug, Clone, PartialEq, Eq)]
struct ReplyMessage(String);
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RemoteFailure {
    rpc: RpcFailureKind,
    code: FailureCode,
    message: ReplyMessage,
}
impl RemoteFailure {
    pub fn rpc_kind(&self) -> RpcFailureKind {
        self.rpc
    }
    pub fn code(&self) -> FailureCode {
        self.code
    }
    pub fn message(&self) -> &str {
        &self.message.0
    }
    fn parse(value: &Value) -> Result<Self, InvalidFrame> {
        let fields = value.as_object().ok_or(InvalidFrame::Shape)?;
        let data = value["data"].as_object().ok_or(InvalidFrame::Shape)?;
        if fields.len() != 3
            || data.len() != 3
            || value["data"]["profile"] != "morphir/workbench/model-originals"
            || value["data"]["contractVersion"] != "0.1.0-draft.1"
        {
            return Err(InvalidFrame::Shape);
        }
        // Error numbers use exact mathematical integers, never an f64 cast.
        let number = super::super::artifacts::signed_rpc_code(&value["code"])
            .map_err(|_| InvalidFrame::Range)?;
        let rpc = match number {
            -32700 => RpcFailureKind::ParseError,
            -32602 => RpcFailureKind::InvalidParameters,
            -32000 => RpcFailureKind::ServerError,
            _ => return Err(InvalidFrame::Range),
        };
        let message = value["message"].as_str().ok_or(InvalidFrame::Shape)?;
        if message.chars().count() > 512 || message.encode_utf16().count() > 512 {
            return Err(InvalidFrame::Range);
        }
        Ok(Self {
            rpc,
            code: FailureCode::parse(&value["data"]["code"])?,
            message: ReplyMessage(message.to_owned()),
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct Binding {
    session: SessionId,
    source: SourceIdentity,
    project: ProjectId,
}
impl Binding {
    fn parse(value: &Value) -> Result<Self, InvalidFrame> {
        let fields = value.as_object().ok_or(InvalidFrame::Shape)?;
        let source = value["source"].as_object().ok_or(InvalidFrame::Shape)?;
        if fields.len() != 3 || source.len() != 2 {
            return Err(InvalidFrame::Shape);
        }
        Ok(Self {
            session: SessionId::parse(&value["sessionId"])?,
            source: SourceIdentity {
                provider: ProviderId::parse(&value["source"]["providerId"])?,
                locator: SourceLocator::parse(&value["source"]["locator"])?,
            },
            project: ProjectId::parse(&value["projectId"])?,
        })
    }
    fn wire_value(&self) -> Value {
        json!({"sessionId":self.session.as_str(),"source":{"providerId":self.source.provider.as_str(),"locator":self.source.locator.as_str()},"projectId":self.project.as_str()})
    }
}
// Byte integrity metadata only. The closed ReadTarget carries the original or
// projection role; a descriptor supplies no decode or adoption authority.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct ByteContentDescriptor {
    length: usize,
    digest: [u8; 32],
}

/// A caller-supplied expected ready description. Its binding must come from the
/// independently authored fixture/current connection, not from an untrusted page.
#[derive(Debug, Clone)]
pub struct CaptureExpectation {
    binding: Binding,
    capture: CaptureId,
    roots: Vec<Root>,
    summary: Summary,
    projection_bytes: Option<ByteContentDescriptor>,
}
impl CaptureExpectation {
    pub fn parse(ready: &str) -> Result<Self, TransferError> {
        let ready = parse(ready, MAX_REPLY_BYTES)?;
        let (roots, summary) = ready_metadata(&ready)?;
        let binding = Binding::parse(&ready["binding"])?;
        let capture = CaptureId::parse(&ready["captureId"])?;
        let projection_bytes = if ready["projection"]["status"] == "available" {
            Some(ByteContentDescriptor {
                length: count(&ready["projection"]["byteLength"], MAX_SOURCE_BYTES)?,
                digest: hash(&ready["projection"]["sha256"])?,
            })
        } else {
            None
        };
        Ok(Self {
            binding,
            capture,
            roots,
            summary,
            projection_bytes,
        })
    }
    pub fn verify_inventory(
        &self,
        exchanges: &[Exchange<'_>],
    ) -> Result<CaptureInventory, TransferError> {
        let mut entries = Vec::new();
        let mut next = PageNext::More(InventoryIndex(0));
        let mut strings = self
            .roots
            .iter()
            .map(|root| root.path.as_str().len())
            .sum::<usize>();
        for exchange in exchanges {
            let page = self.page(exchange)?;
            if next != PageNext::More(page.start) {
                return Err(TransferError::Progress);
            }
            for entry in &page.entries {
                strings = strings
                    .checked_add(entry.path().len())
                    .and_then(|n| n.checked_add(entry.id().as_str().len()))
                    .filter(|n| *n <= MAX_SOURCE_BYTES)
                    .ok_or(TransferError::MetadataBudget)?;
            }
            entries.extend(page.entries);
            next = page.next;
        }
        if exchanges.is_empty() || next != PageNext::Complete {
            return Err(TransferError::Progress);
        }
        let inventory = Inventory::assemble(&self.roots, self.summary.clone(), entries)?;
        let captured = CaptureInventory {
            expected: self.clone(),
            inventory,
        };
        for exchange in exchanges {
            captured.check_page(exchange)?;
        }
        Ok(captured)
    }
    fn context(&self, result: &Value) -> Result<(), TransferError> {
        if Binding::parse(&result["binding"])? != self.binding {
            return Err(TransferError::Binding);
        }
        if CaptureId::parse(&result["captureId"])? != self.capture {
            return Err(TransferError::Capture);
        }
        Ok(())
    }
    fn page(&self, exchange: &Exchange<'_>) -> Result<Page, TransferError> {
        let Parameters::Inventory {
            capture,
            start,
            maximum,
        } = exchange.request.parameters()
        else {
            return Err(TransferError::Method);
        };
        if capture != &self.capture {
            return Err(TransferError::Capture);
        }
        let result = reply(exchange)?;
        // Deterministic compact emission and pessimistic-ID sizing are page
        // rules. The general raw-reply bound still accepts the original exact
        // byte-limit fixtures, including valid padding on a non-page reply.
        compact(exchange.reply)?;
        if exchange.reply.len() - exchange.request.id().get().to_string().len() + 20
            > MAX_REPLY_BYTES
        {
            return Err(InvalidFrame::FrameLimit.into());
        }
        let page_start = InventoryIndex::parse(&result["startIndex"])?;
        let values = result["entries"].as_array().ok_or(InvalidFrame::Shape)?;
        if values.len() > maximum.get() || values.len() > 256 {
            return Err(TransferError::Progress);
        }
        let entries = values
            .iter()
            .map(InventoryEntry::parse)
            .collect::<Result<Vec<_>, _>>()?;
        let next = match result["next"]["kind"].as_str() {
            Some("more") => PageNext::More(InventoryIndex::parse(&result["next"]["startIndex"])?),
            Some("complete") => PageNext::Complete,
            _ => return Err(InvalidFrame::Shape.into()),
        };
        // Preflight a forbidden numeric member even on a malformed next variant.
        if let Some(index) = result["next"].get("startIndex") {
            count(index, 100064)?;
        }
        validate(Schema::InventoryResult, &result)?;
        self.context(&result)?;
        if hash(&result["inventorySha256"])? != self.summary.digest.0 {
            return Err(TransferError::ContentDigest);
        }
        let end = page_start
            .get()
            .checked_add(entries.len())
            .ok_or(TransferError::Progress)?;
        if page_start != *start
            || end > self.summary.entries
            || match next {
                PageNext::More(index) => {
                    entries.is_empty() || index.get() != end || end >= self.summary.entries
                }
                PageNext::Complete => end != self.summary.entries,
            }
        {
            return Err(TransferError::Progress);
        }
        Ok(Page {
            start: page_start,
            entries,
            next,
        })
    }
    fn page_value(&self, start: usize, entries: Value, next: Value) -> Value {
        json!({"profile":"morphir/workbench/model-originals","contractVersion":"0.1.0-draft.1","binding":self.binding.wire_value(),"captureId":self.capture.as_str(),"inventorySha256":self.summary.digest.to_hex(),"startIndex":start,"entries":entries,"next":next})
    }
}

/// Literal request/reply evidence. Requests have already crossed the exact raw
/// request boundary; replies remain raw until the independent check below.
pub struct Exchange<'a> {
    pub request: &'a Request,
    pub reply: &'a str,
}
struct Page {
    start: InventoryIndex,
    entries: Vec<InventoryEntry>,
    next: PageNext,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum PageNext {
    More(InventoryIndex),
    Complete,
}

/// An inventory tied to the pages' exact expected binding and capture. It remains
/// metadata evidence; authenticated source and adoption authority are separate.
#[derive(Debug, Clone)]
pub struct CaptureInventory {
    expected: CaptureExpectation,
    inventory: Inventory,
}
impl CaptureInventory {
    pub fn inventory(&self) -> &Inventory {
        &self.inventory
    }
    pub fn check_page(&self, exchange: &Exchange<'_>) -> Result<(), TransferError> {
        let page = self.expected.page(exchange)?;
        let Parameters::Inventory { maximum, .. } = exchange.request.parameters() else {
            return Err(TransferError::Method);
        };
        let end = page.start.get() + page.entries.len();
        if self.inventory.entries().get(page.start.get()..end) != Some(page.entries.as_slice()) {
            return Err(TransferError::Progress);
        }
        let maximum_count = self.page_count(page.start.get(), maximum.get())?;
        if page.entries.len() != maximum_count {
            return Err(TransferError::Pagination);
        }
        Ok(())
    }
    fn page_count(&self, start: usize, maximum: usize) -> Result<usize, TransferError> {
        let entries = self
            .inventory
            .entries()
            .get(start..)
            .ok_or(TransferError::Progress)?;
        if entries.is_empty() {
            return Ok(0);
        }
        let complete = json!({"kind":"complete"});
        let base = wire_size(
            &json!({"jsonrpc":"2.0","id":u64::MAX,"result":self.expected.page_value(start,json!([]),complete.clone())}),
        )?;
        let complete_size = wire_size(&complete)?;
        let mut entry_bytes = 0usize;
        let mut fitting = 0;
        for (index, entry) in entries.iter().take(maximum).enumerate() {
            entry_bytes = entry_bytes
                .checked_add(wire_size(&entry.wire_value())?)
                .ok_or(TransferError::Pagination)?;
            let count = index + 1;
            let next_size = if start + count == self.inventory.entries().len() {
                complete_size
            } else {
                wire_size(&json!({"kind":"more","startIndex":start+count}))?
            };
            let candidate = base - complete_size + next_size + entry_bytes + count - 1;
            if candidate <= MAX_REPLY_BYTES {
                fitting = count;
            }
        }
        if fitting == 0 {
            return Err(TransferError::Pagination);
        }
        Ok(fitting)
    }
    fn descriptor(&self, target: &ReadTarget) -> Result<ByteContentDescriptor, TransferError> {
        match target {
            ReadTarget::Original { entry } => {
                let entry = self
                    .inventory
                    .entries()
                    .iter()
                    .find(|candidate| candidate.id() == entry)
                    .ok_or(TransferError::Target)?;
                match entry.content() {
                    EntryContent::File {
                        byte_length,
                        sha256,
                    } => Ok(ByteContentDescriptor {
                        length: *byte_length,
                        digest: sha256.0,
                    }),
                    EntryContent::Directory => Err(TransferError::Target),
                }
            }
            ReadTarget::SemanticProjection => {
                self.expected.projection_bytes.ok_or(TransferError::Target)
            }
        }
    }
    pub fn verify_stream(
        &self,
        target: &ReadTarget,
        exchanges: &[Exchange<'_>],
    ) -> Result<CheckedStream, TransferError> {
        let ByteContentDescriptor { length, digest } = self.descriptor(target)?;
        if exchanges.is_empty() {
            return Err(TransferError::Progress);
        }
        let mut bytes = Vec::with_capacity(length);
        let mut hasher = Sha256::new();
        for exchange in exchanges {
            let Parameters::Read {
                capture,
                target: requested,
                offset,
                maximum,
            } = exchange.request.parameters()
            else {
                return Err(TransferError::Method);
            };
            if capture != &self.expected.capture {
                return Err(TransferError::Capture);
            }
            if requested != target {
                return Err(TransferError::Target);
            }
            if offset.get() != bytes.len() || offset.get() > length {
                return Err(TransferError::Progress);
            }
            let result = reply(exchange)?;
            let start = count(&result["offset"], MAX_SOURCE_BYTES)?;
            let next = count(&result["nextOffset"], MAX_SOURCE_BYTES)?;
            validate(Schema::ReadResult, &result)?;
            self.expected.context(&result)?;
            let actual_target = match result["target"]["kind"].as_str() {
                Some("original") => ReadTarget::Original {
                    entry: EntryId::parse(&result["target"]["entryId"])?,
                },
                Some("semantic-projection") => ReadTarget::SemanticProjection,
                _ => return Err(InvalidFrame::Shape.into()),
            };
            if &actual_target != target {
                return Err(TransferError::Target);
            }
            let encoded = result["content"].as_str().ok_or(InvalidFrame::Shape)?;
            let expected_length = maximum.get().min(length - offset.get());
            // The schema has already established the padded alphabet/shape.
            // Account actual decoded length before decoder allocation: 87384
            // encoded bytes can otherwise represent as many as 65538 bytes.
            let padding = encoded
                .bytes()
                .rev()
                .take_while(|byte| *byte == b'=')
                .count();
            if encoded.len() / 4 * 3 - padding != expected_length {
                return Err(TransferError::Progress);
            }
            let chunk = STANDARD
                .decode(encoded)
                .map_err(|_| TransferError::Encoding)?;
            if STANDARD.encode(&chunk) != encoded {
                return Err(TransferError::Encoding);
            }
            if start != offset.get()
                || chunk.len() != expected_length
                || next != start + expected_length
            {
                return Err(TransferError::Progress);
            }
            hasher.update(&chunk);
            bytes.extend_from_slice(&chunk);
        }
        if bytes.len() != length {
            return Err(TransferError::Progress);
        }
        if <[u8; 32]>::from(hasher.finalize()) != digest {
            return Err(TransferError::ContentDigest);
        }
        Ok(CheckedStream {
            target: target.clone(),
            bytes,
        })
    }
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CheckedStream {
    target: ReadTarget,
    bytes: Vec<u8>,
}
impl CheckedStream {
    pub fn target(&self) -> &ReadTarget {
        &self.target
    }
    pub fn bytes(&self) -> &[u8] {
        &self.bytes
    }
}

fn wire_size(value: &Value) -> Result<usize, TransferError> {
    super::super::contract::encoded_size(value, usize::MAX).map_err(|_| TransferError::Pagination)
}
fn reply(exchange: &Exchange<'_>) -> Result<Value, TransferError> {
    let mut value = parse(exchange.reply, MAX_REPLY_BYTES)?;
    let fields = value.as_object().ok_or(InvalidFrame::Shape)?;
    if fields.len() != 3
        || value["jsonrpc"] != "2.0"
        || !fields.contains_key("id")
        || !(fields.contains_key("result") ^ fields.contains_key("error"))
    {
        return Err(InvalidFrame::Shape.into());
    }
    #[derive(Deserialize)]
    struct RawId<'a> {
        #[serde(borrow)]
        id: &'a serde_json::value::RawValue,
    }
    let raw: RawId<'_> = serde_json::from_str(exchange.reply).map_err(|_| InvalidFrame::Shape)?;
    if RequestId::parse(raw.id.get())? != exchange.request.id() {
        return Err(TransferError::RequestIdentity);
    }
    if let Some(error) = value.get("error") {
        return Err(TransferError::Refused(RemoteFailure::parse(error)?));
    }
    Ok(value
        .as_object_mut()
        .ok_or(InvalidFrame::Shape)?
        .remove("result")
        .ok_or(InvalidFrame::Shape)?)
}
fn compact(raw: &str) -> Result<(), TransferError> {
    let mut quoted = false;
    let mut bytes = raw.bytes();
    while let Some(byte) = bytes.next() {
        if quoted {
            match byte {
                b'"' => quoted = false,
                b'\\' if bytes.next() == Some(b'u') => {
                    let digits = bytes.by_ref().take(4).collect::<Vec<_>>();
                    let hex = std::str::from_utf8(&digits).map_err(|_| TransferError::Encoding)?;
                    if u16::from_str_radix(hex, 16).map_err(|_| TransferError::Encoding)? > 127 {
                        return Err(TransferError::Encoding);
                    }
                }
                _ => {}
            }
        } else if byte == b'"' {
            quoted = true;
        } else if byte.is_ascii_whitespace() {
            return Err(TransferError::Encoding);
        }
    }
    Ok(())
}
