//! Lossless saved observations for connected capture checking. Recipes describe
//! actual reply text, never an expected stream substituted for host output.
//! This is pure evidence checking, not a second runner, host or model owner.
use super::{
    CaptureEvidence, CaptureExpectation, CheckedOriginalsEvidence, CheckedProjectionEvidence,
    EvidenceError, Exchange, ExpectedOriginals, ExpectedProjection, InvalidFrame, OriginalTransfer,
    Parameters, ProjectionError, ProjectionRefusal, ProjectionStatus, ReadTarget, Request,
    SemanticRequest, SessionId, TransferError,
};
use serde::Deserialize;
use std::{fmt, num::NonZeroUsize};

pub(super) const MAX_REPLY_BYTES: usize = 128 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TranscriptError {
    Allocation,
    Limits,
    SavedBytes,
    ExpandedBytes,
    ExchangeCount,
    MalformedJson,
    Shape,
    Recipe,
    Frame(InvalidFrame),
    Request,
    Order,
    Completion,
    ProjectionState,
    Transfer(TransferError),
    Originals(EvidenceError),
    Projection(ProjectionError),
}
impl fmt::Display for TranscriptError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Allocation => "transcript allocation refused",
            Self::Limits => "transcript limits must be finite positive counts",
            Self::SavedBytes => "saved transcript exceeds its encoded byte bound",
            Self::ExpandedBytes => "lossless transcript exceeds its expanded byte bound",
            Self::ExchangeCount => "transcript has no exchanges or exceeds its exchange bound",
            Self::MalformedJson => "transcript is not strict duplicate-free JSON",
            Self::Shape => "transcript differs from its closed representation",
            Self::Recipe => "lossless reply recipe is empty or overflows its frame bound",
            Self::Frame(_) => "transcript has an invalid literal request",
            Self::Request => "capture request differs from the independent expectation",
            Self::Order => "transcript exchanges are missing, extra or out of order",
            Self::Completion => "capture completion differs from the requested release sequence",
            Self::ProjectionState => "projection state differs from the independent expectation",
            Self::Transfer(_) => "invalid capture or release transcript",
            Self::Originals(_) => "original transcript differs from independent source facts",
            Self::Projection(_) => "projection transcript differs from independent semantics",
        })
    }
}
impl std::error::Error for TranscriptError {}

/// Caller-supplied checker bounds. Expanded bytes count each request and each
/// materialized reply once. They are not decoded bytes, parser work, host quotas
/// or measured RSS; projection comparison has its own explicit work limits.
#[derive(Debug, Clone, Copy)]
pub struct TranscriptLimits {
    saved: NonZeroUsize,
    expanded: NonZeroUsize,
    exchanges: NonZeroUsize,
}
impl TranscriptLimits {
    pub fn new(saved: usize, expanded: usize, exchanges: usize) -> Result<Self, TranscriptError> {
        Ok(Self {
            saved: NonZeroUsize::new(saved).ok_or(TranscriptError::Limits)?,
            expanded: NonZeroUsize::new(expanded).ok_or(TranscriptError::Limits)?,
            exchanges: NonZeroUsize::new(exchanges).ok_or(TranscriptError::Limits)?,
        })
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct SavedDocument {
    exchanges: Vec<SavedExchange>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct SavedExchange {
    request: String,
    reply: SavedReply,
}
#[derive(Deserialize)]
#[serde(tag = "kind", rename_all = "kebab-case", deny_unknown_fields)]
enum SavedReply {
    Literal { text: String },
    Segments { parts: Vec<ReplyPart> },
}
#[derive(Deserialize)]
#[serde(tag = "kind", rename_all = "kebab-case", deny_unknown_fields)]
enum ReplyPart {
    Literal { text: String },
    Repeat { text: String, count: usize },
}
impl SavedReply {
    fn length(&self) -> Result<usize, TranscriptError> {
        let length = match self {
            Self::Literal { text } => text.len(),
            Self::Segments { parts } => {
                if parts.is_empty() {
                    return Err(TranscriptError::Recipe);
                }
                parts.iter().try_fold(0usize, |total, part| {
                    let bytes = match part {
                        ReplyPart::Literal { text } => text.len(),
                        ReplyPart::Repeat { text, count } => {
                            if text.is_empty() || *count == 0 {
                                return Err(TranscriptError::Recipe);
                            }
                            text.len()
                                .checked_mul(*count)
                                .ok_or(TranscriptError::Recipe)?
                        }
                    };
                    total.checked_add(bytes).ok_or(TranscriptError::Recipe)
                })?
            }
        };
        if length > MAX_REPLY_BYTES {
            return Err(TranscriptError::Recipe);
        }
        Ok(length)
    }
    // All lengths and the complete aggregate were checked before any expansion.
    fn expand(self, length: usize) -> String {
        match self {
            Self::Literal { text } => text,
            Self::Segments { parts } => {
                let mut reply = String::with_capacity(length);
                for part in parts {
                    match part {
                        ReplyPart::Literal { text } => reply.push_str(&text),
                        ReplyPart::Repeat { text, count } => {
                            for _ in 0..count {
                                reply.push_str(&text);
                            }
                        }
                    }
                }
                reply
            }
        }
    }
}
struct ObservedExchange {
    request: Request,
    reply: String,
}
impl ObservedExchange {
    fn borrowed(&self) -> Exchange<'_> {
        Exchange {
            request: &self.request,
            reply: &self.reply,
        }
    }
}
/// Exact observed frames retained for deterministic run/report replay. No hash
/// assertion, caller-owned byte buffer or cached verified flag replaces a reply.
pub struct Transcript {
    exchanges: Vec<ObservedExchange>,
}
impl Transcript {
    pub fn parse(text: &str, limits: TranscriptLimits) -> Result<Self, TranscriptError> {
        if text.len() > limits.saved.get() {
            return Err(TranscriptError::SavedBytes);
        }
        let value =
            crate::json::strict::parse_exact(text).map_err(|_| TranscriptError::MalformedJson)?;
        // This vocabulary contains no arbitrary Value operands. Text stays text
        // and integer recipe counts cross a typed, non-coercing serde boundary.
        let document: SavedDocument =
            serde_json::from_value(value).map_err(|_| TranscriptError::Shape)?;
        Self::from_saved(document, limits)
    }

    /// Borrow actual literal frames without a Value/string normalization
    /// roundtrip. Caller has already reserved the complete frame spans on its
    /// own cumulative owner. Parsing and verification share the saved core.
    pub(in crate::workbench::model_originals) fn from_literal_frames(
        frames: &[(&str, &str)],
        limits: TranscriptLimits,
    ) -> Result<Self, TranscriptError> {
        if frames.is_empty() || frames.len() > limits.exchanges.get() {
            return Err(TranscriptError::ExchangeCount);
        }
        let mut bytes = 0usize;
        for (request, reply) in frames {
            if request.len() > super::MAX_REQUEST_BYTES || reply.len() > MAX_REPLY_BYTES {
                return Err(TranscriptError::Frame(InvalidFrame::FrameLimit));
            }
            bytes = bytes
                .checked_add(request.len())
                .and_then(|n| n.checked_add(reply.len()))
                .filter(|n| *n <= limits.expanded.get() && *n <= limits.saved.get())
                .ok_or(TranscriptError::ExpandedBytes)?;
        }
        fn owned(text: &str) -> Result<String, TranscriptError> {
            let mut result = String::new();
            result
                .try_reserve_exact(text.len())
                .map_err(|_| TranscriptError::Allocation)?;
            result.push_str(text);
            Ok(result)
        }
        let mut exchanges = Vec::new();
        exchanges
            .try_reserve_exact(frames.len())
            .map_err(|_| TranscriptError::Allocation)?;
        for (request, reply) in frames {
            exchanges.push(SavedExchange {
                request: owned(request)?,
                reply: SavedReply::Literal {
                    text: owned(reply)?,
                },
            });
        }
        Self::from_saved(SavedDocument { exchanges }, limits)
    }

    fn from_saved(
        document: SavedDocument,
        limits: TranscriptLimits,
    ) -> Result<Self, TranscriptError> {
        if document.exchanges.is_empty() || document.exchanges.len() > limits.exchanges.get() {
            return Err(TranscriptError::ExchangeCount);
        }
        let mut remaining = limits.expanded.get();
        let mut lengths = Vec::with_capacity(document.exchanges.len());
        for exchange in &document.exchanges {
            if exchange.request.len() > super::MAX_REQUEST_BYTES {
                return Err(TranscriptError::Frame(InvalidFrame::FrameLimit));
            }
            let length = exchange.reply.length()?;
            remaining = remaining
                .checked_sub(exchange.request.len())
                .and_then(|n| n.checked_sub(length))
                .ok_or(TranscriptError::ExpandedBytes)?;
            lengths.push(length);
        }
        let requests = document
            .exchanges
            .iter()
            .map(|e| Request::parse(&e.request).map_err(TranscriptError::Frame))
            .collect::<Result<Vec<_>, _>>()?;
        let exchanges = document
            .exchanges
            .into_iter()
            .zip(requests)
            .zip(lengths)
            .map(|((saved, request), length)| ObservedExchange {
                request,
                reply: saved.reply.expand(length),
            })
            .collect();
        Ok(Self { exchanges })
    }

    pub fn verify(
        &self,
        expected: &ConnectedCaptureExpectation<'_>,
    ) -> Result<CheckedCaptureTranscript, TranscriptError> {
        let first = self.exchanges.first().ok_or(TranscriptError::Order)?;
        if &first.request != expected.request {
            return Err(TranscriptError::Request);
        }
        let captured = CaptureExpectation::from_exchange(&first.borrowed(), expected.session)
            .map_err(TranscriptError::Transfer)?;
        let tail = self
            .exchanges
            .len()
            .checked_sub(expected.completion.release_count())
            .filter(|n| *n >= 1)
            .ok_or(TranscriptError::Completion)?;
        for release in &self.exchanges[tail..] {
            captured
                .verify_release(&release.borrowed())
                .map_err(TranscriptError::Transfer)?;
        }
        let body = &self.exchanges[1..tail];
        let page_count = body
            .iter()
            .take_while(|e| matches!(e.request.parameters(), Parameters::Inventory { .. }))
            .count();
        let pages = body[..page_count]
            .iter()
            .map(ObservedExchange::borrowed)
            .collect::<Vec<_>>();
        let mut originals = Vec::new();
        let mut projection = None;
        let mut remaining = &body[page_count..];
        while let Some(first) = remaining.first() {
            let Parameters::Read { target, .. } = first.request.parameters() else {
                return Err(TranscriptError::Order);
            };
            let count = remaining.iter().take_while(|e| matches!(e.request.parameters(),Parameters::Read { target: current, .. } if current == target)).count();
            let group = remaining[..count]
                .iter()
                .map(ObservedExchange::borrowed)
                .collect::<Vec<_>>();
            match target {
                ReadTarget::Original { entry } if projection.is_none() => {
                    originals.push((entry, group))
                }
                ReadTarget::SemanticProjection if projection.is_none() => projection = Some(group),
                _ => return Err(TranscriptError::Order),
            }
            remaining = &remaining[count..];
        }
        let transfers = originals
            .iter()
            .map(|(entry, exchanges)| OriginalTransfer { entry, exchanges })
            .collect::<Vec<_>>();
        let originals = expected
            .originals
            .verify(
                expected.session,
                CaptureEvidence {
                    capture: first.borrowed(),
                    pages: &pages,
                    originals: &transfers,
                },
            )
            .map_err(TranscriptError::Originals)?;
        let checked_projection = match (
            &expected.projection,
            originals.projection_status(),
            projection,
        ) {
            (ExpectedProjectionState::NotRequested, ProjectionStatus::NotRequested, None)
            | (ExpectedProjectionState::Unavailable(_), ProjectionStatus::Unavailable(_), None)
                if expected.projection.status() == originals.projection_status() =>
            {
                None
            }
            (
                ExpectedProjectionState::Available(value),
                ProjectionStatus::Available,
                Some(exchanges),
            ) => Some(
                originals
                    .verify_projection(value, &exchanges)
                    .map_err(TranscriptError::Projection)?,
            ),
            _ => return Err(TranscriptError::ProjectionState),
        };
        Ok(CheckedCaptureTranscript {
            originals,
            projection: checked_projection,
            completion: expected.completion,
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CaptureCompletion {
    Retained,
    Released,
    ReleasedTwice,
}
impl CaptureCompletion {
    fn release_count(self) -> usize {
        match self {
            Self::Retained => 0,
            Self::Released => 1,
            Self::ReleasedTwice => 2,
        }
    }
}
pub enum ExpectedProjectionState<'a> {
    NotRequested,
    Unavailable(ProjectionRefusal),
    Available(&'a ExpectedProjection<'a>),
}
impl ExpectedProjectionState<'_> {
    fn status(&self) -> ProjectionStatus {
        match self {
            Self::NotRequested => ProjectionStatus::NotRequested,
            Self::Unavailable(reason) => ProjectionStatus::Unavailable(*reason),
            Self::Available(_) => ProjectionStatus::Available,
        }
    }
}
/// Independent fixture facts. In particular, session and capture parameters are
/// never inferred from the observed peer's ready result or replayed requests.
pub struct ConnectedCaptureExpectation<'a> {
    session: &'a SessionId,
    request: &'a Request,
    originals: &'a ExpectedOriginals<'a>,
    projection: ExpectedProjectionState<'a>,
    completion: CaptureCompletion,
}
impl<'a> ConnectedCaptureExpectation<'a> {
    pub fn new(
        session: &'a SessionId,
        request: &'a Request,
        originals: &'a ExpectedOriginals<'a>,
        projection: ExpectedProjectionState<'a>,
        completion: CaptureCompletion,
    ) -> Result<Self, TranscriptError> {
        match (request.parameters(), projection.status()) {
            (
                Parameters::Capture {
                    semantic: SemanticRequest::None,
                    ..
                },
                ProjectionStatus::NotRequested,
            )
            | (
                Parameters::Capture {
                    semantic: SemanticRequest::Projection,
                    ..
                },
                ProjectionStatus::Unavailable(_) | ProjectionStatus::Available,
            ) => {}
            _ => return Err(TranscriptError::ProjectionState),
        }
        Ok(Self {
            session,
            request,
            originals,
            projection,
            completion,
        })
    }
}
/// Actual byte/semantic and release-acknowledgement evidence. This grants no
/// filesystem/current-model/execution authority, nor host reclamation proof.
pub struct CheckedCaptureTranscript {
    originals: CheckedOriginalsEvidence,
    projection: Option<CheckedProjectionEvidence>,
    completion: CaptureCompletion,
}
impl CheckedCaptureTranscript {
    pub fn originals(&self) -> &CheckedOriginalsEvidence {
        &self.originals
    }
    pub fn projection(&self) -> Option<&CheckedProjectionEvidence> {
        self.projection.as_ref()
    }
    pub fn completion(&self) -> CaptureCompletion {
        self.completion
    }
}
