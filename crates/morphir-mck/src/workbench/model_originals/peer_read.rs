//! Compact independently authored peer INPUT, never measured SUT evidence.
//! A production adapter must separately match each real pending port effect and
//! retain its complete actual request/reply/lifecycle transcript. Parsing a raw
//! request here grants no pending-effect, capture or connection authority.
use super::{FixtureBytes, MAX_REQUEST_BYTES, Parameters, ReadTarget, Request};
use base64::{Engine, engine::general_purpose::STANDARD};
use serde::Deserialize;
use serde_json::{Value, json};
use std::fmt;

const MAX_ROWS: usize = 8192;
const MAX_REPLY_BYTES: usize = 128 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PeerReadResource {
    SavedBytes,
    Rows,
    WindowBytes,
    WireBytes,
    ObserverBytes,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PeerReadError {
    Json,
    Shape,
    Alias,
    Range,
    Request,
    Effect,
    Exhausted,
    Resource(PeerReadResource),
}
impl fmt::Display for PeerReadError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Json => f.write_str("peer read input is not strict duplicate-free JSON"),
            Self::Shape => f.write_str("peer read input differs from its closed representation"),
            Self::Alias => {
                f.write_str("peer read alias is invalid or has no matching input fixture")
            }
            Self::Range => f.write_str("peer read range or complete work overflows its bounds"),
            Self::Request => {
                f.write_str("peer read request differs from the independently authored plan")
            }
            Self::Effect => {
                f.write_str("peer read attempt, kind or ordinal differs from the next row")
            }
            Self::Exhausted => f.write_str("peer read run has already supplied all its rows"),
            Self::Resource(resource) => write!(f, "peer read input exceeds its {resource:?} bound"),
        }
    }
}
impl std::error::Error for PeerReadError {}

#[derive(Debug, Clone, PartialEq, Eq)]
struct Alias(String);
impl Alias {
    fn parse(text: &str) -> Result<Self, PeerReadError> {
        if text.is_empty()
            || text.len() > 64
            || !text.as_bytes()[0].is_ascii_alphabetic()
            || !text
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-'))
        {
            return Err(PeerReadError::Alias);
        }
        Ok(Self(text.to_owned()))
    }
}
/// Membership in a caller's independently authored INPUT fixture table. The
/// caller must not resolve these aliases against expected or observed output.
pub struct InputByteFixture<'a> {
    alias: Alias,
    bytes: &'a FixtureBytes,
}
impl<'a> InputByteFixture<'a> {
    pub fn new(alias: &str, bytes: &'a FixtureBytes) -> Result<Self, PeerReadError> {
        Ok(Self {
            alias: Alias::parse(alias)?,
            bytes,
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
pub enum ReadEffectKind {
    #[serde(rename = "read-original")]
    Original,
    #[serde(rename = "read-projection")]
    Projection,
}
impl ReadEffectKind {
    fn matches(self, target: &ReadTarget) -> bool {
        matches!(
            (self, target),
            (Self::Original, ReadTarget::Original { .. })
                | (Self::Projection, ReadTarget::SemanticProjection)
        )
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Ordinal(usize);
impl Ordinal {
    fn new(value: usize) -> Result<Self, PeerReadError> {
        if value < MAX_ROWS {
            Ok(Self(value))
        } else {
            Err(PeerReadError::Range)
        }
    }
}
/// Validated literal observation of a read request. This is deliberately not a
/// token authorizing delivery to an actual production pending effect.
pub struct ObservedRead {
    attempt: Alias,
    kind: ReadEffectKind,
    ordinal: Ordinal,
    request: Request,
    raw: String,
}
impl ObservedRead {
    pub fn parse(
        attempt: &str,
        kind: ReadEffectKind,
        ordinal: usize,
        raw: &str,
    ) -> Result<Self, PeerReadError> {
        let request = Request::parse(raw).map_err(|_| PeerReadError::Request)?;
        if !matches!(request.parameters(), Parameters::Read { .. }) {
            return Err(PeerReadError::Request);
        }
        Ok(Self {
            attempt: Alias::parse(attempt)?,
            kind,
            ordinal: Ordinal::new(ordinal)?,
            request,
            raw: raw.to_owned(),
        })
    }
    pub fn raw_request(&self) -> &str {
        &self.raw
    }
}

/// Explicit checker policy for one run. Zero denies the named resource. These
/// bounds do not establish host quotas, whole-case work or actual process RSS.
#[derive(Debug, Clone, Copy)]
pub struct PeerReadBounds {
    pub saved_bytes: usize,
    pub rows: usize,
    pub window_bytes: usize,
    pub wire_bytes: usize,
    pub observer_bytes: usize,
}
/// Complete upper bounds before rendering any row. Window bytes count input
/// copies. Wire bytes include the request maximum and response upper bound.
/// Observer bytes count window/base64/frame byte visits, excluding JSON parser
/// internals and SUT decoding. Whole-case checking must aggregate all runs,
/// unique source definitions, measured observations and actual SUT work.
#[derive(Debug, Clone, Copy)]
pub struct PeerReadWork {
    rows: usize,
    window_bytes: usize,
    wire_bytes: usize,
    observer_bytes: usize,
}
impl PeerReadWork {
    pub fn rows(self) -> usize {
        self.rows
    }
    pub fn window_bytes(self) -> usize {
        self.window_bytes
    }
    pub fn wire_bytes(self) -> usize {
        self.wire_bytes
    }
    pub fn observer_bytes(self) -> usize {
        self.observer_bytes
    }
    fn check(self, bounds: PeerReadBounds) -> Result<(), PeerReadError> {
        for (used, limit, resource) in [
            (self.rows, bounds.rows, PeerReadResource::Rows),
            (
                self.window_bytes,
                bounds.window_bytes,
                PeerReadResource::WindowBytes,
            ),
            (
                self.wire_bytes,
                bounds.wire_bytes,
                PeerReadResource::WireBytes,
            ),
            (
                self.observer_bytes,
                bounds.observer_bytes,
                PeerReadResource::ObserverBytes,
            ),
        ] {
            if used > limit {
                return Err(PeerReadError::Resource(resource));
            }
        }
        Ok(())
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SavedRun {
    kind: String,
    attempt: String,
    effect_kind: ReadEffectKind,
    first_ordinal: usize,
    source: String,
    expected_request: SavedRequest,
    window: SavedWindow,
    reply_parts: Vec<Part>,
}
#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SavedRequest {
    method: String,
    contract_version: String,
    capture_id: String,
    target: Value,
    max_bytes: usize,
}
#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SavedWindow {
    first_offset: usize,
    after_offset: usize,
    chunk_bytes: usize,
    rows: usize,
}
#[derive(Deserialize)]
#[serde(tag = "kind", rename_all = "kebab-case", deny_unknown_fields)]
enum Part {
    Literal { text: String },
    CorrelatedRequestId,
    RowOffset,
    RowNextOffset,
    Base64Window,
}
enum Progress {
    Next(usize),
    Complete,
}
pub struct PeerReadRun<'a> {
    fixture: InputByteFixture<'a>,
    attempt: Alias,
    kind: ReadEffectKind,
    first: Ordinal,
    expected: Parameters,
    window: SavedWindow,
    parts: Vec<Part>,
    work: PeerReadWork,
    progress: Progress,
}
impl<'a> PeerReadRun<'a> {
    pub fn parse(
        text: &str,
        fixture: InputByteFixture<'a>,
        bounds: PeerReadBounds,
    ) -> Result<Self, PeerReadError> {
        if text.len() > bounds.saved_bytes {
            return Err(PeerReadError::Resource(PeerReadResource::SavedBytes));
        }
        let mut value = crate::json::strict::parse_exact(text).map_err(|_| PeerReadError::Json)?;
        normalize_count(&mut value, &["firstOrdinal"])?;
        for field in ["firstOffset", "afterOffset", "chunkBytes", "rows"] {
            normalize_count(&mut value, &["window", field])?;
        }
        normalize_count(&mut value, &["expectedRequest", "maxBytes"])?;
        let saved: SavedRun = serde_json::from_value(value).map_err(|_| PeerReadError::Shape)?;
        if saved.kind != "read-run" {
            return Err(PeerReadError::Shape);
        }
        let attempt = Alias::parse(&saved.attempt)?;
        let first = Ordinal::new(saved.first_ordinal)?;
        if Alias::parse(&saved.source)? != fixture.alias {
            return Err(PeerReadError::Alias);
        }
        let window = saved.window;
        let length = fixture.bytes.byte_length();
        if length > 64 * 1024 * 1024
            || window.first_offset >= window.after_offset
            || window.after_offset > length
            || !(1..=65536).contains(&window.chunk_bytes)
            || !(1..=MAX_ROWS).contains(&window.rows)
        {
            return Err(PeerReadError::Range);
        }
        let span = window.after_offset - window.first_offset;
        if span.div_ceil(window.chunk_bytes) != window.rows
            || (window.after_offset < length && !span.is_multiple_of(window.chunk_bytes))
            || first
                .0
                .checked_add(window.rows)
                .is_none_or(|end| end > MAX_ROWS)
        {
            return Err(PeerReadError::Range);
        }
        let request = saved.expected_request;
        if request.method != "morphir.model-originals.read"
            || request.contract_version != "0.1.0-draft.1"
            || request.max_bytes != window.chunk_bytes
        {
            return Err(PeerReadError::Request);
        }
        let raw = json!({"jsonrpc":"2.0","id":0,"method":request.method,"params":{
            "contractVersion":request.contract_version,"captureId":request.capture_id,"target":request.target,
            "offset":window.first_offset,"maxBytes":request.max_bytes
        }}).to_string();
        let expected = Request::parse(&raw)
            .map_err(|_| PeerReadError::Request)?
            .parameters;
        if !matches!(&expected, Parameters::Read {target, ..} if saved.effect_kind.matches(target))
        {
            return Err(PeerReadError::Request);
        }
        if saved.reply_parts.is_empty()
            || saved.reply_parts.len() > 32
            || saved
                .reply_parts
                .iter()
                .any(|part| matches!(part, Part::Literal {text} if text.len() > 16 * 1024))
        {
            return Err(PeerReadError::Shape);
        }
        let mut work = PeerReadWork {
            rows: window.rows,
            window_bytes: 0,
            wire_bytes: 0,
            observer_bytes: 0,
        };
        for row in 0..window.rows {
            let offset = window.first_offset + row * window.chunk_bytes;
            let size = window.chunk_bytes.min(length - offset);
            let next = offset + size;
            let payload = size
                .div_ceil(3)
                .checked_mul(4)
                .ok_or(PeerReadError::Range)?;
            let frame = frame_length(&saved.reply_parts, 20, offset, next, payload)?;
            if frame > MAX_REPLY_BYTES {
                return Err(PeerReadError::Range);
            }
            work.window_bytes = add(work.window_bytes, size)?;
            work.wire_bytes = add(work.wire_bytes, add(MAX_REQUEST_BYTES, frame)?)?;
            work.observer_bytes = add(
                work.observer_bytes,
                add(add(mul(size, 3)?, payload)?, mul(frame, 2)?)?,
            )?;
        }
        work.check(bounds)?;
        Ok(Self {
            fixture,
            attempt,
            kind: saved.effect_kind,
            first,
            expected,
            window,
            parts: saved.reply_parts,
            work,
            progress: Progress::Next(0),
        })
    }
    pub fn work(&self) -> PeerReadWork {
        self.work
    }
    /// Render one independently authored INPUT reply after matching the next
    /// literal request. Rejection never advances this run. Actual delivery,
    /// cancellation, ownership and cleanup belong to the production driver.
    pub fn reply(&mut self, observed: &ObservedRead) -> Result<String, PeerReadError> {
        let row = match self.progress {
            Progress::Next(row) => row,
            Progress::Complete => return Err(PeerReadError::Exhausted),
        };
        if self.attempt != observed.attempt
            || self.kind != observed.kind
            || self.first.0 + row != observed.ordinal.0
        {
            return Err(PeerReadError::Effect);
        }
        let offset = self.window.first_offset + row * self.window.chunk_bytes;
        let size = self
            .window
            .chunk_bytes
            .min(self.fixture.bytes.byte_length() - offset);
        let next = offset + size;
        match (&self.expected, observed.request.parameters()) {
            (
                Parameters::Read {
                    capture,
                    target,
                    maximum,
                    ..
                },
                Parameters::Read {
                    capture: actual_capture,
                    target: actual_target,
                    offset: actual_offset,
                    maximum: actual_maximum,
                },
            ) if capture == actual_capture
                && target == actual_target
                && maximum == actual_maximum
                && offset == actual_offset.get() => {}
            _ => return Err(PeerReadError::Request),
        }
        let mut bytes = vec![0; size];
        self.fixture
            .bytes
            .fill_window(offset, &mut bytes)
            .map_err(|_| PeerReadError::Range)?;
        let payload = STANDARD.encode(&bytes);
        let id = observed.request.id().get().to_string();
        let capacity = frame_length(&self.parts, id.len(), offset, next, payload.len())?;
        let mut reply = String::with_capacity(capacity);
        for part in &self.parts {
            match part {
                Part::Literal { text } => reply.push_str(text),
                Part::CorrelatedRequestId => reply.push_str(&id),
                Part::RowOffset => reply.push_str(&offset.to_string()),
                Part::RowNextOffset => reply.push_str(&next.to_string()),
                Part::Base64Window => reply.push_str(&payload),
            }
        }
        self.progress = if row + 1 == self.window.rows {
            Progress::Complete
        } else {
            Progress::Next(row + 1)
        };
        Ok(reply)
    }
}
fn frame_length(
    parts: &[Part],
    id_width: usize,
    offset: usize,
    next: usize,
    payload: usize,
) -> Result<usize, PeerReadError> {
    parts.iter().try_fold(0, |total, part| {
        let size = match part {
            Part::Literal { text } => text.len(),
            Part::CorrelatedRequestId => id_width,
            Part::RowOffset => offset.to_string().len(),
            Part::RowNextOffset => next.to_string().len(),
            Part::Base64Window => payload,
        };
        add(total, size)
    })
}
fn add(a: usize, b: usize) -> Result<usize, PeerReadError> {
    a.checked_add(b).ok_or(PeerReadError::Range)
}
fn mul(a: usize, b: usize) -> Result<usize, PeerReadError> {
    a.checked_mul(b).ok_or(PeerReadError::Range)
}
fn normalize_count(value: &mut Value, path: &[&str]) -> Result<(), PeerReadError> {
    let mut slot = value;
    for key in path {
        slot = slot.get_mut(*key).ok_or(PeerReadError::Shape)?;
    }
    let count =
        super::super::artifacts::integer(slot, usize::MAX).map_err(|_| PeerReadError::Range)?;
    *slot = json!(count);
    Ok(())
}
