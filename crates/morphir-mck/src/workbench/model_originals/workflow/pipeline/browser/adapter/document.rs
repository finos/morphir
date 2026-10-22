//! Closed document-frame DATA only. No physical document or factual authority.
#[path = "document/data.rs"]
mod data;
#[cfg(test)]
#[path = "document/data_tests.rs"]
mod data_tests;
use super::*;
use crate::json::strict::{self, Document};
use crate::workbench::model_originals::workflow::{
    Decoder, decode::DecodeError, pipeline::installed::observation::InstalledObservationFault,
};
pub use data::*;
use serde_json::value::RawValue;
use std::time::Instant;

const MAX_SAFE: u64 = 9_007_199_254_740_991;
const SCHEMA_FIELDS: usize = 8;
const SCHEMA_CONTAINERS: usize = 3;
const SCHEMA_NAME_BYTES: usize = 32;
// Thirteen FACT tags, at most thirteen owner-shape alternatives, the
// download-result branch, two outcome tags and three returned-result tags.
const SCHEMA_TAG_COMPARISONS: usize = 13 + 13 + 1 + 2 + 3;
// At most six opaque tokens. Each span performs <=6 checked address/range
// operations. Eight whole-result spans conservatively cover nested owner,
// fact and frame construction/copies, without assuming compiler elision.
const PROJECTION_TOKEN_SPANS: usize = 6;
const PROJECTION_VALUE_MOVES: usize = 8;
pub struct BrowserDocumentDecoder {
    source: BrowserApplicationSource,
    remaining: usize,
    frame_bytes: usize,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserDocumentErrorKind {
    Funding,
    Source,
    End,
    Capacity,
    Json,
    Shape,
    Order,
    ProducerIncomplete,
}
#[derive(Debug)]
enum Cause {
    Input(BrowserInputError),
    Decode(DecodeError),
    Closed(BrowserDocumentErrorKind),
}
#[derive(Debug)]
pub struct BrowserDocumentError {
    cause: Cause,
}
impl BrowserDocumentError {
    pub fn kind(&self) -> BrowserDocumentErrorKind {
        match &self.cause {
            Cause::Input(BrowserInputError {
                cause: inputs::BrowserInputFault::Source(_),
            }) => BrowserDocumentErrorKind::Source,
            Cause::Input(_) => BrowserDocumentErrorKind::Funding,
            Cause::Decode(DecodeError::Literal(_)) => BrowserDocumentErrorKind::Json,
            Cause::Decode(_) => BrowserDocumentErrorKind::Funding,
            Cause::Closed(kind) => *kind,
        }
    }
}
impl From<BrowserInputError> for BrowserDocumentError {
    fn from(cause: BrowserInputError) -> Self {
        Self {
            cause: Cause::Input(cause),
        }
    }
}
impl From<DecodeError> for BrowserDocumentError {
    fn from(cause: DecodeError) -> Self {
        Self {
            cause: Cause::Decode(cause),
        }
    }
}
fn fault(kind: BrowserDocumentErrorKind) -> BrowserDocumentError {
    BrowserDocumentError {
        cause: Cause::Closed(kind),
    }
}
fn shape<T>() -> Result<T, BrowserDocumentError> {
    Err(fault(BrowserDocumentErrorKind::Shape))
}
fn add(a: usize, b: usize) -> Option<usize> {
    a.checked_add(b)
}
fn mul(a: usize, b: usize) -> Option<usize> {
    a.checked_mul(b)
}
impl BrowserLoans<'_, '_> {
    /// Preissue requested parser storage and our own schema scan budget from
    /// the SAME owners. Actual literal traversal still spends SAME Decoder.
    pub fn prepare_document_decoder(
        &mut self,
        source: &BrowserApplicationSource,
        records: usize,
        frame_bytes: usize,
    ) -> Result<BrowserDocumentDecoder, BrowserInputError> {
        self.validate_application_source(source)?;
        let plan = (|| {
            // Tag parse tokens are disjoint substrings of this one payload.
            // Every term of requested_document_storage_bound is positive and
            // linear or floor(N/k), so the SUM of those tag allocations is
            // bounded by one call on their total span, <= frame_bytes.
            // Root, actual/observer, and outcome are at most three member
            // passes. Only the first diagnostic can propagate out of `?`.
            let temporary = add(
                add(
                    strict::requested_document_storage_bound(frame_bytes)?,
                    mul(
                        SCHEMA_CONTAINERS,
                        strict::requested_raw_members_storage_bound(frame_bytes)?,
                    )?,
                )?,
                strict::requested_diagnostic_storage_bound(frame_bytes)?,
            )?;
            let projection = mul(
                PROJECTION_VALUE_MOVES,
                std::mem::size_of::<BrowserDocumentFrameData>(),
            )?;
            let requested = add(
                add(mul(records, temporary)?, projection)?,
                std::mem::size_of::<BrowserDocumentDecoder>(),
            )?;
            let pairs = mul(
                mul(mul(SCHEMA_FIELDS, SCHEMA_FIELDS)?, 2)?,
                SCHEMA_CONTAINERS,
            )?;
            // Three exact-field passes cost <=3*8*8=192 comparisons.
            // At most twenty field lookups cost <=20*8=160 more. The
            // conservative pairs384 covers both; tags are prepaid separately.
            let visits = mul(records, add(pairs, SCHEMA_TAG_COMPARISONS)?)?;
            let comparisons = mul(
                records,
                mul(
                    mul(add(pairs, SCHEMA_TAG_COMPARISONS)?, 2)?,
                    SCHEMA_NAME_BYTES,
                )?,
            )?;
            let scans = mul(
                records,
                add(
                    add(
                        mul(12, frame_bytes)?,
                        mul(SCHEMA_TAG_COMPARISONS, SCHEMA_NAME_BYTES)?,
                    )?,
                    add(
                        projection,
                        mul(
                            mul(PROJECTION_TOKEN_SPANS, 6)?,
                            std::mem::size_of::<usize>(),
                        )?,
                    )?,
                )?,
            )?;
            Some((
                requested,
                mul(records, frame_bytes)?,
                visits,
                comparisons,
                scans,
            ))
        })();
        let Some((requested, slots, visits, comparisons, scans)) = plan else {
            let (_, receiving, _) = self
                .inner
                .physical_owners()
                .map_err(BrowserInputError::from)?;
            let cause = *receiving.fail(InstalledObservationFault::SizeOverflow);
            return Err(inputs::BrowserInputFault::Receiving(cause).into());
        };
        self.reserve_application_storage(source, requested, slots, scans)?;
        self.reserve_application_comparison(source, visits, comparisons, records)?;
        Ok(BrowserDocumentDecoder {
            source: self.prepare_application_source()?,
            remaining: records,
            frame_bytes,
        })
    }
    /// Consumes one already prepaid frame slot. Shape validation is DATA only;
    /// it never supplies source/action identity, joins or comparison predicates.
    pub fn validate_document_frame(
        &mut self,
        source: &BrowserApplicationSource,
        permission: &mut BrowserDocumentDecoder,
        kind: u8,
        sequence: u64,
        payload: &[u8],
        end: Instant,
    ) -> Result<(), BrowserDocumentError> {
        self.decode_document_frame_data(source, permission, kind, sequence, payload, end)
            .map(|_| ())
    }
    /// Return literal DATA from the SAME strict parse. The actual receiver
    /// must retain it inseparably with this original payload before ACK. This
    /// supplies no run, physical-document, action or Download association.
    pub fn decode_document_frame_data(
        &mut self,
        source: &BrowserApplicationSource,
        permission: &mut BrowserDocumentDecoder,
        kind: u8,
        sequence: u64,
        payload: &[u8],
        end: Instant,
    ) -> Result<BrowserDocumentFrameData, BrowserDocumentError> {
        self.validate_application_source(source)?;
        self.validate_application_source(&permission.source)?;
        if permission.remaining == 0
            || permission
                .frame_bytes
                .checked_sub(16)
                .is_none_or(|maximum| payload.len() > maximum)
        {
            let (_, receiving, _) = self
                .inner
                .physical_owners()
                .map_err(BrowserInputError::from)?;
            receiving.fail(InstalledObservationFault::PriorFault);
            return Err(fault(BrowserDocumentErrorKind::Capacity));
        }
        let (decode, receiving, _) = self
            .inner
            .physical_owners()
            .map_err(BrowserInputError::from)?;
        let result = source
            .while_source_active(|| {
                if Instant::now() >= end {
                    return Err(fault(BrowserDocumentErrorKind::End));
                }
                permission.remaining -= 1;
                // UTF8 before the SAME literal/raw-member reader. Raw string
                // value tokens remain untouched, including escaped UTF16 units.
                std::str::from_utf8(payload).map_err(|_| fault(BrowserDocumentErrorKind::Shape))?;
                let raw = decode.raw_literal(payload)?;
                decode_frame_data(decode, kind, sequence, payload, raw)
            })
            .map_err(|_| fault(BrowserDocumentErrorKind::Source))?;
        if result.is_err() {
            receiving.fail(InstalledObservationFault::PriorFault);
        }
        result
    }
}
struct Object<'a> {
    members: Vec<(String, &'a RawValue)>,
}
impl<'a> Object<'a> {
    fn read(decode: &mut Decoder, raw: &'a RawValue) -> Result<Self, BrowserDocumentError> {
        if !raw.get().starts_with('{') {
            return shape();
        }
        let members = decode.raw_members(raw)?;
        // Refuse the already-paid raw pass before any key lookup. Otherwise
        // looking for "kind" could scan an arbitrary input member count.
        if members.len() > SCHEMA_FIELDS {
            return shape();
        }
        Ok(Self { members })
    }
    fn exact(&self, names: &[&str]) -> Result<(), BrowserDocumentError> {
        if self.members.len() != names.len()
            || self
                .members
                .iter()
                .any(|(name, _)| !names.contains(&name.as_str()))
        {
            return shape();
        }
        Ok(())
    }
    fn field(&self, name: &str) -> Result<&'a RawValue, BrowserDocumentError> {
        self.members
            .iter()
            .find(|(key, _)| key == name)
            .map(|(_, raw)| *raw)
            .ok_or_else(|| fault(BrowserDocumentErrorKind::Shape))
    }
    fn string(&self, name: &str) -> Result<(), BrowserDocumentError> {
        if !self.field(name)?.get().starts_with('"') {
            return shape();
        }
        Ok(())
    }
    fn span(
        &self,
        name: &str,
        payload: &[u8],
    ) -> Result<BrowserJsonStringSpan, BrowserDocumentError> {
        BrowserJsonStringSpan::from_raw(payload, self.field(name)?)
    }
    fn natural<const MIN: u64>(
        &self,
        name: &str,
    ) -> Result<
        crate::workbench::model_originals::workflow::Natural<MIN, MAX_SAFE>,
        BrowserDocumentError,
    > {
        crate::workbench::model_originals::workflow::Natural::new(self.number(name, MIN > 0)?)
            .map_err(|_| fault(BrowserDocumentErrorKind::Shape))
    }
    fn number(&self, name: &str, positive: bool) -> Result<u64, BrowserDocumentError> {
        let token = self.field(name)?.get();
        if token.is_empty()
            || !token.bytes().all(|b| b.is_ascii_digit())
            || token.len() > 1 && token.starts_with('0')
        {
            return shape();
        }
        let value = token
            .parse::<u64>()
            .map_err(|_| fault(BrowserDocumentErrorKind::Shape))?;
        if value > MAX_SAFE || positive && value == 0 {
            return shape();
        }
        Ok(value)
    }
    fn tag(&self, decode: &mut Decoder, name: &str) -> Result<String, BrowserDocumentError> {
        self.string(name)?;
        match decode.literal_with_raw(self.field(name)?.get())?.0 {
            Document::String(value) => Ok(value),
            _ => shape(),
        }
    }
}
fn decode_frame_data(
    decode: &mut Decoder,
    kind: u8,
    sequence: u64,
    payload: &[u8],
    raw: &RawValue,
) -> Result<BrowserDocumentFrameData, BrowserDocumentError> {
    if sequence == 0 || sequence > MAX_SAFE {
        return Err(fault(BrowserDocumentErrorKind::Order));
    }
    let root = Object::read(decode, raw)?;
    let content = if kind == 2 {
        root.exact(&["lastSequence", "observer"])?;
        let last = root.number("lastSequence", false)?;
        if last.checked_add(1) != Some(sequence) {
            return Err(fault(BrowserDocumentErrorKind::Order));
        }
        let observer = Object::read(decode, root.field("observer")?)?;
        let tag = observer.tag(decode, "kind")?;
        match tag.as_str() {
            "closed" => {
                observer.exact(&["kind"])?;
                BrowserDocumentContent::End {
                    last_sequence: crate::workbench::model_originals::workflow::Natural::new(last)
                        .map_err(|_| fault(BrowserDocumentErrorKind::Shape))?,
                }
            }
            "active" | "unobserved" => {
                observer.exact(&["kind"])?;
                return Err(fault(BrowserDocumentErrorKind::ProducerIncomplete));
            }
            "incomplete" => {
                observer.exact(&["kind", "cause"])?;
                let cause = observer.tag(decode, "cause")?;
                if !matches!(
                    cause.as_str(),
                    "sink-raised" | "owner-limit" | "event-limit" | "owner-mismatch"
                ) {
                    return shape();
                }
                return Err(fault(BrowserDocumentErrorKind::ProducerIncomplete));
            }
            _ => return shape(),
        }
    } else if kind == 1 {
        let tag = data::FactTag::parse(&root.tag(decode, "kind")?)?;
        root.exact(tag.fields())?;
        if root.number("sequence", true)? != sequence {
            return Err(fault(BrowserDocumentErrorKind::Order));
        }
        let actual = Object::read(decode, root.field("actual")?)?;
        actual.exact(tag.owner_fields())?;
        BrowserDocumentContent::Fact(project_fact(tag, &root, &actual, payload, decode)?)
    } else {
        return shape();
    };
    Ok(BrowserDocumentFrameData {
        sequence: crate::workbench::model_originals::workflow::Natural::new(sequence)
            .map_err(|_| fault(BrowserDocumentErrorKind::Shape))?,
        content,
    })
}

fn visit(actual: &Object<'_>, payload: &[u8]) -> Result<BrowserVisitData, BrowserDocumentError> {
    Ok(BrowserVisitData {
        workspace: actual.span("workspace", payload)?,
        opening: actual.natural("opening")?,
    })
}
fn opening(
    actual: &Object<'_>,
    payload: &[u8],
) -> Result<BrowserOpeningData, BrowserDocumentError> {
    Ok(BrowserOpeningData {
        visit: visit(actual, payload)?,
        attempt: actual.span("attempt", payload)?,
        opening_ordinal: actual.natural("openingOrdinal")?,
    })
}
fn inventory(
    actual: &Object<'_>,
    payload: &[u8],
) -> Result<BrowserInventoryData, BrowserDocumentError> {
    Ok(BrowserInventoryData {
        opening: opening(actual, payload)?,
        inventory_revision: actual.span("inventoryRevision", payload)?,
    })
}
fn archive(
    actual: &Object<'_>,
    payload: &[u8],
) -> Result<BrowserArchiveData, BrowserDocumentError> {
    Ok(BrowserArchiveData {
        inventory: inventory(actual, payload)?,
        operation_ordinal: actual.natural("operationOrdinal")?,
    })
}
fn ready(
    actual: &Object<'_>,
    payload: &[u8],
) -> Result<BrowserReadyArchiveData, BrowserDocumentError> {
    Ok(BrowserReadyArchiveData {
        archive: archive(actual, payload)?,
        ready_ordinal: actual.natural("readyOrdinal")?,
    })
}
fn selection(
    root: &Object<'_>,
    payload: &[u8],
) -> Result<BrowserSourceSelectionData, BrowserDocumentError> {
    Ok(BrowserSourceSelectionData {
        session_id: root.span("sessionId", payload)?,
        provider_id: root.span("providerId", payload)?,
        locator: root.span("locator", payload)?,
    })
}
fn project(
    root: &Object<'_>,
    payload: &[u8],
) -> Result<BrowserProjectSelectionData, BrowserDocumentError> {
    Ok(BrowserProjectSelectionData {
        source: selection(root, payload)?,
        project_id: root.span("projectId", payload)?,
    })
}
fn outcome(
    root: &Object<'_>,
    decode: &mut Decoder,
) -> Result<BrowserDownloadOutcomeData, BrowserDocumentError> {
    let outcome = Object::read(decode, root.field("outcome")?)?;
    Ok(match outcome.tag(decode, "kind")?.as_str() {
        "raised" => {
            outcome.exact(&["kind"])?;
            BrowserDownloadOutcomeData::Raised
        }
        "returned" => {
            outcome.exact(&["kind", "result"])?;
            BrowserDownloadOutcomeData::Returned(match outcome.tag(decode, "result")?.as_str() {
                "download-requested" => BrowserDownloadResultData::DownloadRequested,
                "retired" => BrowserDownloadResultData::Retired,
                "failed" => BrowserDownloadResultData::Failed,
                _ => return shape(),
            })
        }
        _ => return shape(),
    })
}
fn project_fact(
    tag: data::FactTag,
    root: &Object<'_>,
    actual: &Object<'_>,
    payload: &[u8],
    decode: &mut Decoder,
) -> Result<BrowserDocumentFactData, BrowserDocumentError> {
    use BrowserDocumentFactData as Fact;
    use data::FactTag as Tag;
    Ok(match tag {
        Tag::OpeningStored => Fact::OpeningStored(opening(actual, payload)?),
        Tag::SourceSelected => Fact::SourceSelected {
            actual: opening(actual, payload)?,
            selection: selection(root, payload)?,
        },
        Tag::ProjectSelected => Fact::ProjectSelected {
            actual: opening(actual, payload)?,
            selection: project(root, payload)?,
        },
        Tag::TransferVerified => Fact::TransferVerified {
            actual: opening(actual, payload)?,
            selection: project(root, payload)?,
        },
        Tag::InventoryAdopted => Fact::InventoryAdopted(inventory(actual, payload)?),
        Tag::ArchiveStored => Fact::ArchiveStored(archive(actual, payload)?),
        Tag::ArchiveRetirementRequested => {
            Fact::ArchiveRetirementRequested(archive(actual, payload)?)
        }
        Tag::ArchiveSettledRetired => Fact::ArchiveSettledRetired(archive(actual, payload)?),
        Tag::ArchiveReady => Fact::ArchiveReady(ready(actual, payload)?),
        Tag::DownloadWillRequest => Fact::DownloadWillRequest(ready(actual, payload)?),
        Tag::DownloadResult => Fact::DownloadResult {
            actual: ready(actual, payload)?,
            outcome: outcome(root, decode)?,
        },
        Tag::ModelClosed => Fact::ModelClosed(visit(actual, payload)?),
        Tag::WorkspaceClosed => Fact::WorkspaceClosed(visit(actual, payload)?),
    })
}
