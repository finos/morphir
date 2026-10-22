//! Closed document-frame DATA only. No physical document or factual authority.
use super::*;
use crate::json::strict::{self, Document};
use crate::workbench::model_originals::workflow::{
    Decoder, decode::DecodeError, pipeline::installed::observation::InstalledObservationFault,
};
use serde_json::value::RawValue;
use std::time::Instant;

const MAX_SAFE: u64 = 9_007_199_254_740_991;
const SCHEMA_FIELDS: usize = 8;
const SCHEMA_CONTAINERS: usize = 3;
const SCHEMA_NAME_BYTES: usize = 32;
// Thirteen FACT tags, at most thirteen owner-shape alternatives, the
// download-result branch, two outcome tags and three returned-result tags.
const SCHEMA_TAG_COMPARISONS: usize = 13 + 13 + 1 + 2 + 3;
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
            let requested = add(
                mul(records, temporary)?,
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
                    mul(12, frame_bytes)?,
                    mul(SCHEMA_TAG_COMPARISONS, SCHEMA_NAME_BYTES)?,
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
                validate(decode, kind, sequence, raw)
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
fn validate(
    decode: &mut Decoder,
    kind: u8,
    sequence: u64,
    raw: &RawValue,
) -> Result<(), BrowserDocumentError> {
    if sequence == 0 || sequence > MAX_SAFE {
        return Err(fault(BrowserDocumentErrorKind::Order));
    }
    let root = Object::read(decode, raw)?;
    if kind == 2 {
        root.exact(&["lastSequence", "observer"])?;
        let last = root.number("lastSequence", false)?;
        if last.checked_add(1) != Some(sequence) {
            return Err(fault(BrowserDocumentErrorKind::Order));
        }
        let observer = Object::read(decode, root.field("observer")?)?;
        let tag = observer.tag(decode, "kind")?;
        match tag.as_str() {
            "closed" => observer.exact(&["kind"]),
            "active" | "unobserved" => {
                observer.exact(&["kind"])?;
                Err(fault(BrowserDocumentErrorKind::ProducerIncomplete))
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
                Err(fault(BrowserDocumentErrorKind::ProducerIncomplete))
            }
            _ => shape(),
        }
    } else if kind == 1 {
        let tag = root.tag(decode, "kind")?;
        let fields: &[&str] = match tag.as_str() {
            "source-selected" => &[
                "kind",
                "actual",
                "sequence",
                "sessionId",
                "providerId",
                "locator",
            ],
            "project-selected" | "transfer-verified" => &[
                "kind",
                "actual",
                "sequence",
                "sessionId",
                "providerId",
                "locator",
                "projectId",
            ],
            "download-result" => &["kind", "actual", "sequence", "outcome"],
            "opening-stored"
            | "inventory-adopted"
            | "archive-stored"
            | "archive-retirement-requested"
            | "archive-settled-retired"
            | "archive-ready"
            | "download-will-request"
            | "model-closed"
            | "workspace-closed" => &["kind", "actual", "sequence"],
            _ => return shape(),
        };
        root.exact(fields)?;
        if root.number("sequence", true)? != sequence {
            return Err(fault(BrowserDocumentErrorKind::Order));
        }
        for field in fields {
            if matches!(*field, "sessionId" | "providerId" | "locator" | "projectId") {
                root.string(field)?;
            }
        }
        let actual = Object::read(decode, root.field("actual")?)?;
        let owner_fields: &[&str] = match tag.as_str() {
            "model-closed" | "workspace-closed" => &["workspace", "opening"],
            "opening-stored" | "source-selected" | "project-selected" | "transfer-verified" => {
                &["workspace", "opening", "attempt", "openingOrdinal"]
            }
            "inventory-adopted" => &[
                "workspace",
                "opening",
                "attempt",
                "openingOrdinal",
                "inventoryRevision",
            ],
            "archive-stored" | "archive-retirement-requested" | "archive-settled-retired" => &[
                "workspace",
                "opening",
                "attempt",
                "openingOrdinal",
                "inventoryRevision",
                "operationOrdinal",
            ],
            _ => &[
                "workspace",
                "opening",
                "attempt",
                "openingOrdinal",
                "inventoryRevision",
                "operationOrdinal",
                "readyOrdinal",
            ],
        };
        actual.exact(owner_fields)?;
        for field in owner_fields {
            if matches!(
                *field,
                "opening" | "openingOrdinal" | "operationOrdinal" | "readyOrdinal"
            ) {
                actual.number(field, *field != "opening")?;
            } else {
                actual.string(field)?;
            }
        }
        if tag == "download-result" {
            let outcome = Object::read(decode, root.field("outcome")?)?;
            match outcome.tag(decode, "kind")?.as_str() {
                "raised" => outcome.exact(&["kind"])?,
                "returned" => {
                    outcome.exact(&["kind", "result"])?;
                    if !matches!(
                        outcome.tag(decode, "result")?.as_str(),
                        "download-requested" | "retired" | "failed"
                    ) {
                        return shape();
                    }
                }
                _ => return shape(),
            }
        }
        Ok(())
    } else {
        shape()
    }
}
