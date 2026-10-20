use super::super::expansion::{ExpansionLimits, ExpansionOwner, ReadExpansionLimits};
use super::super::observation_check::{CompareLimits, CompareOwner};
use super::super::work::{ClosureLimits, ClosureOwner};
use super::super::{DecodeLimits, Decoder};
use crate::json::strict::{Document, ReadWork, ReadWorkLimits};
use std::num::NonZeroUsize;

/// Validated immutable configuration, never a producer grant or live owner.
pub(in crate::workbench) struct Policy {
    decode: DecodeLimits,
    saved: ReadWorkLimits,
    closure: ClosureLimits,
    expansion: ExpansionPolicy,
    comparison: ComparisonPolicy,
    capture: CapturePolicy,
}
struct ExpansionPolicy {
    recipe: u64,
    frame: u64,
    literal: u64,
    entries: u64,
    visits: u64,
    rows: u64,
    window: u64,
    wire: u64,
    observer: u64,
}
struct ComparisonPolicy {
    visits: usize,
    bytes: usize,
    checks: usize,
}
#[derive(Clone, Copy)]
pub(super) struct CapturePolicy {
    pub(super) request: NonZeroUsize,
    pub(super) reply: NonZeroUsize,
    pub(super) aggregate: NonZeroUsize,
}
pub(super) struct Owners {
    pub(super) decode: Decoder,
    pub(super) saved: ReadWork,
    pub(super) closure: ClosureOwner,
    pub(super) expansion: ExpansionOwner,
    pub(super) comparison: CompareOwner,
    pub(super) capture: CaptureBudget,
}
pub(super) struct CaptureBudget {
    policy: CapturePolicy,
    spent: usize,
}
#[derive(Debug)]
pub(super) enum CaptureFault {
    Request,
    Reply,
    Aggregate,
    Overflow,
}
impl CaptureBudget {
    pub(super) fn retain(&mut self, request: usize, reply: usize) -> Result<(), CaptureFault> {
        if request > self.policy.request.get() {
            return Err(CaptureFault::Request);
        }
        if reply > self.policy.reply.get() {
            return Err(CaptureFault::Reply);
        }
        let count = request.checked_add(reply).ok_or(CaptureFault::Overflow)?;
        let next = self
            .spent
            .checked_add(count)
            .ok_or(CaptureFault::Overflow)?;
        if next > self.policy.aggregate.get() {
            return Err(CaptureFault::Aggregate);
        }
        self.spent = next;
        Ok(())
    }
}

pub(super) fn closed<'a>(
    value: &'a Document,
    names: &[&str],
) -> Result<&'a [(String, Document)], String> {
    let Document::Object(fields) = value else {
        return Err("policy requires object".into());
    };
    if fields.len() != names.len() || fields.iter().any(|(key, _)| !names.contains(&key.as_str())) {
        return Err("policy has missing/unknown fields".into());
    }
    Ok(fields)
}
pub(super) fn get<'a>(
    fields: &'a [(String, Document)],
    name: &str,
) -> Result<&'a Document, String> {
    fields
        .iter()
        .find(|(key, _)| key == name)
        .map(|(_, value)| value)
        .ok_or_else(|| "policy required field missing".into())
}
fn natural(value: &Document) -> Result<u64, String> {
    let Document::Number(number) = value else {
        return Err("policy count must be exact integer".into());
    };
    // Reuse the existing exact scalar domain conversion. No opaque operand or
    // report is converted through Value. Huge exponents cannot reach a schema.
    crate::workbench::artifacts::integer_u64(&serde_json::Value::Number(number.clone()), u64::MAX)
}
fn count(fields: &[(String, Document)], name: &str) -> Result<usize, String> {
    usize::try_from(natural(get(fields, name)?)?)
        .map_err(|_| "policy count exceeds target usize".into())
}
fn wide(fields: &[(String, Document)], name: &str) -> Result<u64, String> {
    natural(get(fields, name)?)
}
fn positive(fields: &[(String, Document)], name: &str) -> Result<NonZeroUsize, String> {
    NonZeroUsize::new(count(fields, name)?).ok_or_else(|| "policy requires positive count".into())
}

impl Policy {
    pub(in crate::workbench) fn from_document(document: &Document) -> Result<Self, String> {
        let fields = closed(
            document,
            &[
                "kind",
                "decode",
                "savedRead",
                "closure",
                "expansion",
                "comparison",
                "capture",
            ],
        )?;
        let Document::String(kind) = get(fields, "kind")? else {
            return Err("policy kind must be string".into());
        };
        if kind != "model-originals" {
            return Err("unsupported explicit policy kind".into());
        }
        let d = closed(
            get(fields, "decode")?,
            &[
                "savedBytes",
                "literalBytes",
                "literalValues",
                "byteVisits",
                "slots",
            ],
        )?;
        let decode = DecodeLimits::new(
            count(d, "savedBytes")?,
            count(d, "literalBytes")?,
            count(d, "literalValues")?,
            count(d, "byteVisits")?,
            count(d, "slots")?,
        )
        .map_err(|_| "invalid decode policy".to_owned())?;
        let s = closed(get(fields, "savedRead")?, &["bytes", "values"])?;
        let saved = ReadWorkLimits::new(count(s, "bytes")?, count(s, "values")?)
            .map_err(|_| "invalid saved reader policy".to_owned())?;
        let c = closed(
            get(fields, "closure")?,
            &[
                "definitions",
                "references",
                "lookupBytes",
                "structuralVisits",
            ],
        )?;
        let closure = ClosureLimits::new(
            count(c, "definitions")?,
            count(c, "references")?,
            count(c, "lookupBytes")?,
            count(c, "structuralVisits")?,
        )
        .map_err(|_| "invalid closure policy".to_owned())?;
        let e = closed(
            get(fields, "expansion")?,
            &[
                "recipeBytes",
                "frameBytes",
                "literalStorageBytes",
                "entries",
                "visits",
                "readRows",
                "readWindowBytes",
                "readWireBytes",
                "readObserverBytes",
            ],
        )?;
        let expansion = ExpansionPolicy {
            recipe: wide(e, "recipeBytes")?,
            frame: wide(e, "frameBytes")?,
            literal: wide(e, "literalStorageBytes")?,
            entries: wide(e, "entries")?,
            visits: wide(e, "visits")?,
            rows: wide(e, "readRows")?,
            window: wide(e, "readWindowBytes")?,
            wire: wide(e, "readWireBytes")?,
            observer: wide(e, "readObserverBytes")?,
        };
        let p = closed(
            get(fields, "comparison")?,
            &["structuralVisits", "comparisonBytes", "checks"],
        )?;
        let comparison = ComparisonPolicy {
            visits: count(p, "structuralVisits")?,
            bytes: count(p, "comparisonBytes")?,
            checks: count(p, "checks")?,
        };
        CompareLimits::new(comparison.visits, comparison.bytes, comparison.checks)
            .map_err(|_| "invalid comparison policy".to_owned())?;
        let b = closed(
            get(fields, "capture")?,
            &["requestBytes", "replyBytes", "aggregateBytes"],
        )?;
        let capture = CapturePolicy {
            request: positive(b, "requestBytes")?,
            reply: positive(b, "replyBytes")?,
            aggregate: positive(b, "aggregateBytes")?,
        };
        Ok(Self {
            decode,
            saved,
            closure,
            expansion,
            comparison,
            capture,
        })
    }
    pub(super) fn owners(&self) -> Owners {
        let e = &self.expansion;
        Owners {
            decode: Decoder::new(self.decode),
            saved: ReadWork::new(self.saved),
            closure: ClosureOwner::new(self.closure),
            expansion: ExpansionOwner::new(
                ExpansionLimits::new(e.recipe, e.frame, e.literal, e.entries, e.visits).with_reads(
                    ReadExpansionLimits::new(e.rows, e.window, e.wire, e.observer),
                ),
            ),
            comparison: CompareOwner::new(
                CompareLimits::new(
                    self.comparison.visits,
                    self.comparison.bytes,
                    self.comparison.checks,
                )
                .expect("validated comparison policy"),
            ),
            capture: CaptureBudget {
                policy: self.capture,
                spent: 0,
            },
        }
    }
}
