//! Independent JSON comparison with literal objects and exact decimal values.
//! No implementation IR codec is linked. An available, recognized release is
//! evidence, not a claim of consumer support or current-model authority.
use super::{CaptureInventory, Exchange, InvalidFrame, ReadTarget, TransferError};
use serde::de::{DeserializeSeed, Error as _, MapAccess, SeqAccess, Visitor};
use serde_json::value::RawValue;
use std::{collections::BTreeMap, fmt, num::NonZeroUsize};

const MAX_PROJECTION_BYTES: usize = 64 * 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModelRelease {
    spelling: String,
    version: semver::Version,
}
impl ModelRelease {
    pub fn parse(text: &str) -> Result<Self, InvalidFrame> {
        let version = semver::Version::parse(text).map_err(|_| InvalidFrame::Shape)?;
        if version.to_string() != text || !version.pre.is_empty() || !version.build.is_empty() {
            return Err(InvalidFrame::Shape);
        }
        if [version.major, version.minor, version.patch]
            .into_iter()
            .any(|part| part > u32::MAX.into())
        {
            return Err(InvalidFrame::Range);
        }
        Ok(Self {
            spelling: text.into(),
            version,
        })
    }
    pub fn as_str(&self) -> &str {
        &self.spelling
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ComparisonResource {
    DecodeBytes,
    Values,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProjectionError {
    Transfer(TransferError),
    Json,
    Header,
    DescriptorVersion,
    Semantics,
    ByteLimit,
    InvalidWorkLimits,
    WorkLimit(ComparisonResource),
}
impl From<TransferError> for ProjectionError {
    fn from(error: TransferError) -> Self {
        Self::Transfer(error)
    }
}
impl fmt::Display for ProjectionError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Transfer(_) => "invalid actual projection transfer",
            Self::Json => "invalid or duplicate-member projection JSON",
            Self::Header => "projection has no valid actual formatVersion header",
            Self::DescriptorVersion => {
                "actual emitted header differs from the projection descriptor"
            }
            Self::Semantics => "projection differs from independently authored JSON semantics",
            Self::ByteLimit => "projection exceeds its independent64MiB byte limit",
            Self::InvalidWorkLimits => "comparison work limits must be finite positive values",
            Self::WorkLimit(_) => "projection comparison exceeds its explicit checker work budget",
        })
    }
}
impl std::error::Error for ProjectionError {}

/// Checker work, not a producer/consumer policy. DecodeBytes charges the bytes
/// passed to each serde decode and exact-number normalization, including
/// repeated container/child decodes. These are logical input-work requests,
/// not a claim about allocator bytes, physical lexer scans or process RSS.
/// Values reserves each scalar/container before retaining a child reference.
/// Callers must supply reviewed per-case limits; there is no production default.
#[derive(Debug, Clone, Copy)]
pub struct ProjectionWorkLimits {
    decode_bytes: NonZeroUsize,
    values: NonZeroUsize,
}
impl ProjectionWorkLimits {
    pub fn new(decode_bytes: usize, values: usize) -> Result<Self, ProjectionError> {
        Ok(Self {
            decode_bytes: NonZeroUsize::new(decode_bytes)
                .ok_or(ProjectionError::InvalidWorkLimits)?,
            values: NonZeroUsize::new(values).ok_or(ProjectionError::InvalidWorkLimits)?,
        })
    }
}
#[derive(Debug, Clone, Copy)]
struct WorkBudget {
    decode_bytes: usize,
    values: usize,
    fault: Option<ComparisonResource>,
}
impl WorkBudget {
    fn new(limits: ProjectionWorkLimits) -> Self {
        Self {
            decode_bytes: limits.decode_bytes.get(),
            values: limits.values.get(),
            fault: None,
        }
    }
    fn charge(
        &mut self,
        resource: ComparisonResource,
        count: usize,
    ) -> Result<(), ProjectionError> {
        if let Some(fault) = self.fault {
            return Err(ProjectionError::WorkLimit(fault));
        }
        let remaining = match resource {
            ComparisonResource::DecodeBytes => &mut self.decode_bytes,
            ComparisonResource::Values => &mut self.values,
        };
        let Some(next) = remaining.checked_sub(count) else {
            self.fault = Some(resource);
            return Err(ProjectionError::WorkLimit(resource));
        };
        *remaining = next;
        Ok(())
    }
    fn decode(&mut self, bytes: usize) -> Result<(), ProjectionError> {
        self.charge(ComparisonResource::DecodeBytes, bytes)
    }
    fn value(&mut self) -> Result<(), ProjectionError> {
        self.charge(ComparisonResource::Values, 1)
    }
    fn serde_error(&self) -> ProjectionError {
        self.fault
            .map_or(ProjectionError::Json, ProjectionError::WorkLimit)
    }
}

struct MembersSeed<'a>(&'a mut WorkBudget);
impl<'de> DeserializeSeed<'de> for MembersSeed<'_> {
    type Value = BTreeMap<String, &'de RawValue>;
    fn deserialize<D: serde::Deserializer<'de>>(self, d: D) -> Result<Self::Value, D::Error> {
        d.deserialize_map(self)
    }
}
impl<'de> Visitor<'de> for MembersSeed<'_> {
    type Value = BTreeMap<String, &'de RawValue>;
    fn expecting(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("literal JSON object without duplicate members")
    }
    fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Self::Value, A::Error> {
        let mut members = BTreeMap::new();
        while let Some(key) = map.next_key::<String>()? {
            if members.contains_key(&key) {
                return Err(A::Error::custom("duplicate projection member"));
            }
            let raw = map.next_value::<&RawValue>()?;
            self.0
                .value()
                .map_err(|_| A::Error::custom("projection value work exhausted"))?;
            members.insert(key, raw);
        }
        Ok(members)
    }
}
struct ElementsSeed<'a>(&'a mut WorkBudget);
impl<'de> DeserializeSeed<'de> for ElementsSeed<'_> {
    type Value = Vec<&'de RawValue>;
    fn deserialize<D: serde::Deserializer<'de>>(self, d: D) -> Result<Self::Value, D::Error> {
        d.deserialize_seq(self)
    }
}
impl<'de> Visitor<'de> for ElementsSeed<'_> {
    type Value = Vec<&'de RawValue>;
    fn expecting(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("literal JSON array")
    }
    fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<Self::Value, A::Error> {
        let mut elements = Vec::new();
        while let Some(raw) = seq.next_element::<&RawValue>()? {
            self.0
                .value()
                .map_err(|_| A::Error::custom("projection value work exhausted"))?;
            elements.push(raw);
        }
        Ok(elements)
    }
}
#[derive(PartialEq)]
enum Atom<'a> {
    Null,
    Bool(bool),
    String(String),
    Number(&'a str),
}
enum Shape<'a> {
    Object(BTreeMap<String, &'a RawValue>),
    Array(Vec<&'a RawValue>),
    Atom(Atom<'a>),
}
fn shape<'a>(raw: &'a RawValue, budget: &mut WorkBudget) -> Result<Shape<'a>, ProjectionError> {
    let text = raw.get();
    budget.decode(text.len())?;
    match text.as_bytes()[0] {
        b'{' => MembersSeed(budget)
            .deserialize(&mut serde_json::Deserializer::from_str(text))
            .map(Shape::Object)
            .map_err(|_| budget.serde_error()),
        b'[' => ElementsSeed(budget)
            .deserialize(&mut serde_json::Deserializer::from_str(text))
            .map(Shape::Array)
            .map_err(|_| budget.serde_error()),
        b'"' => serde_json::from_str::<String>(text)
            .map(|v| Shape::Atom(Atom::String(v)))
            .map_err(|_| ProjectionError::Json),
        b'n' => Ok(Shape::Atom(Atom::Null)),
        b't' => Ok(Shape::Atom(Atom::Bool(true))),
        b'f' => Ok(Shape::Atom(Atom::Bool(false))),
        _ => Ok(Shape::Atom(Atom::Number(text))),
    }
}
fn document<'a>(text: &'a str, budget: &mut WorkBudget) -> Result<&'a RawValue, ProjectionError> {
    if text.len() > MAX_PROJECTION_BYTES {
        return Err(ProjectionError::ByteLimit);
    }
    budget.decode(text.len())?;
    budget.value()?;
    serde_json::from_str(text).map_err(|_| ProjectionError::Json)
}
fn header(raw: &RawValue, budget: &mut WorkBudget) -> Result<ModelRelease, ProjectionError> {
    let text = raw.get();
    budget.decode(text.len())?;
    if text.starts_with('"') {
        let text = serde_json::from_str::<String>(text).map_err(|_| ProjectionError::Header)?;
        let version = ModelRelease::parse(&text).map_err(|_| ProjectionError::Header)?;
        if version.version.major < 3 {
            return Err(ProjectionError::Header);
        }
        Ok(version)
    } else {
        let major = text.parse::<u32>().map_err(|_| ProjectionError::Header)?;
        if major == 0 {
            return Err(ProjectionError::Header);
        }
        ModelRelease::parse(&format!("{major}.0.0")).map_err(|_| ProjectionError::Header)
    }
}
fn root_members<'a>(
    raw: &'a RawValue,
    budget: &mut WorkBudget,
) -> Result<(BTreeMap<String, &'a RawValue>, ModelRelease), ProjectionError> {
    let Shape::Object(members) = shape(raw, budget)? else {
        return Err(ProjectionError::Header);
    };
    let version = header(
        members
            .get("formatVersion")
            .ok_or(ProjectionError::Header)?,
        budget,
    )?;
    Ok((members, version))
}
fn validate(raw: &RawValue, budget: &mut WorkBudget) -> Result<ModelRelease, ProjectionError> {
    let (members, version) = root_members(raw, budget)?;
    let mut pending = members.into_values().collect::<Vec<_>>();
    while let Some(raw) = pending.pop() {
        match shape(raw, budget)? {
            Shape::Object(members) => pending.extend(members.into_values()),
            Shape::Array(elements) => pending.extend(elements),
            Shape::Atom(_) => {}
        }
    }
    Ok(version)
}
fn compare(
    expected: &RawValue,
    actual: &RawValue,
    descriptor: &ModelRelease,
    budget: &mut WorkBudget,
) -> Result<(), ProjectionError> {
    budget.value()?; // The actual root was reserved by document().
    let (mut left, left_version) = root_members(expected, budget)?;
    let (mut right, right_version) = root_members(actual, budget)?;
    if &right_version != descriptor {
        return Err(ProjectionError::DescriptorVersion);
    }
    if left_version != right_version {
        return Err(ProjectionError::Semantics);
    }
    // The actual headers are compared through their validated release domain,
    // allowing canonical numeric/string aliases without a serializer mandate.
    left.remove("formatVersion");
    right.remove("formatVersion");
    let mut pending = Vec::new();
    schedule_members(left, right, &mut pending)?;
    while let Some((left, right)) = pending.pop() {
        match (shape(left, budget)?, shape(right, budget)?) {
            (Shape::Object(left), Shape::Object(right)) => {
                schedule_members(left, right, &mut pending)?
            }
            (Shape::Array(left), Shape::Array(right)) if left.len() == right.len() => {
                pending.extend(left.into_iter().zip(right))
            }
            (Shape::Atom(Atom::Number(left)), Shape::Atom(Atom::Number(right))) => {
                budget.decode(left.len())?;
                budget.decode(right.len())?;
                if NormalizedDecimal::from_valid_json(left)
                    != NormalizedDecimal::from_valid_json(right)
                {
                    return Err(ProjectionError::Semantics);
                }
            }
            (Shape::Atom(left), Shape::Atom(right)) if left == right => {}
            _ => return Err(ProjectionError::Semantics),
        }
    }
    Ok(())
}
fn schedule_members<'a, 'b>(
    left: BTreeMap<String, &'a RawValue>,
    right: BTreeMap<String, &'b RawValue>,
    pending: &mut Vec<(&'a RawValue, &'b RawValue)>,
) -> Result<(), ProjectionError> {
    if left.len() != right.len() {
        return Err(ProjectionError::Semantics);
    }
    for ((left_key, left), (right_key, right)) in left.into_iter().zip(right) {
        if left_key != right_key {
            return Err(ProjectionError::Semantics);
        }
        pending.push((left, right));
    }
    Ok(())
}

/// A signed decimal magnitude keeps arbitrarily long JSON exponents exact.
/// Digits are normalized, least significant first. No floating-point or
/// machine-integer exponent conversion occurs during semantic comparison.
#[derive(PartialEq, Eq)]
struct DecimalExponent {
    negative: bool,
    digits: Vec<u8>,
}
impl DecimalExponent {
    fn from_valid_json(text: &str) -> Self {
        let negative = text.starts_with('-');
        let magnitude = text.trim_start_matches(['-', '+']).trim_start_matches('0');
        let digits = if magnitude.is_empty() {
            vec![0]
        } else {
            magnitude.bytes().rev().map(|byte| byte - b'0').collect()
        };
        let mut result = Self { negative, digits };
        result.normalize();
        result
    }
    fn normalize(&mut self) {
        while self.digits.len() > 1 && self.digits.last() == Some(&0) {
            self.digits.pop();
        }
        if self.digits == [0] {
            self.negative = false;
        }
    }
    fn add_small(mut self, delta: i64) -> Self {
        if delta == 0 {
            return self;
        }
        let negative = delta < 0;
        let mut magnitude = delta.unsigned_abs();
        let mut digits = Vec::new();
        while magnitude > 0 {
            digits.push((magnitude % 10) as u8);
            magnitude /= 10;
        }
        if self.negative == negative {
            let mut carry = 0u8;
            for index in 0..self.digits.len().max(digits.len()) {
                let sum = self.digits.get(index).copied().unwrap_or(0)
                    + digits.get(index).copied().unwrap_or(0)
                    + carry;
                if index == self.digits.len() {
                    self.digits.push(sum % 10);
                } else {
                    self.digits[index] = sum % 10;
                }
                carry = sum / 10;
            }
            if carry > 0 {
                self.digits.push(carry);
            }
        } else {
            let order = self
                .digits
                .len()
                .cmp(&digits.len())
                .then_with(|| self.digits.iter().rev().cmp(digits.iter().rev()));
            if order.is_lt() {
                std::mem::swap(&mut self.digits, &mut digits);
                self.negative = negative;
            }
            let mut borrow = 0i16;
            for (index, digit) in self.digits.iter_mut().enumerate() {
                let value =
                    i16::from(*digit) - i16::from(digits.get(index).copied().unwrap_or(0)) - borrow;
                *digit = value.rem_euclid(10) as u8;
                borrow = i16::from(value < 0);
            }
        }
        self.normalize();
        self
    }
}
#[derive(PartialEq, Eq)]
struct NormalizedDecimal {
    negative: bool,
    coefficient: Vec<u8>,
    exponent: DecimalExponent,
}
impl NormalizedDecimal {
    fn from_valid_json(text: &str) -> Self {
        let negative = text.starts_with('-');
        let text = text.strip_prefix('-').unwrap_or(text);
        let (mantissa, exponent) = text.split_once(['e', 'E']).unwrap_or((text, "0"));
        let fractional = mantissa
            .split_once('.')
            .map_or(0, |(_, fraction)| fraction.len());
        let digits = mantissa
            .bytes()
            .filter(|byte| *byte != b'.')
            .collect::<Vec<_>>();
        let first = digits.iter().position(|byte| *byte != b'0');
        let Some(first) = first else {
            return Self {
                negative,
                coefficient: Vec::new(),
                exponent: DecimalExponent::from_valid_json("0"),
            };
        };
        let last = digits
            .iter()
            .rposition(|byte| *byte != b'0')
            .expect("nonzero digit");
        // Both lengths are bounded by the independent64MiB input limit.
        let adjustment = (digits.len() - last - 1) as i64 - fractional as i64;
        Self {
            negative,
            coefficient: digits[first..=last].to_vec(),
            exponent: DecimalExponent::from_valid_json(exponent).add_small(adjustment),
        }
    }
}

pub struct ExpectedProjection<'a> {
    json: &'a RawValue,
    release: ModelRelease,
    after_expectation: WorkBudget,
}
impl<'a> ExpectedProjection<'a> {
    pub fn json(text: &'a str, limits: ProjectionWorkLimits) -> Result<Self, ProjectionError> {
        let mut budget = WorkBudget::new(limits);
        let json = document(text, &mut budget)?;
        let release = validate(json, &mut budget)?;
        Ok(Self {
            json,
            release,
            after_expectation: budget,
        })
    }
    pub fn verify(
        &self,
        capture: &CaptureInventory,
        exchanges: &[Exchange<'_>],
    ) -> Result<CheckedProjectionEvidence, ProjectionError> {
        let descriptor = capture
            .projection_version()
            .ok_or(ProjectionError::DescriptorVersion)?;
        let stream = capture.verify_stream(&ReadTarget::SemanticProjection, exchanges)?;
        let text = std::str::from_utf8(stream.bytes()).map_err(|_| ProjectionError::Json)?;
        let mut budget = self.after_expectation;
        let actual = document(text, &mut budget)?;
        compare(self.json, actual, descriptor, &mut budget)?;
        Ok(CheckedProjectionEvidence {
            release: self.release.clone(),
            byte_length: stream.bytes().len(),
        })
    }
}
/// Independent semantic/byte evidence only. No usable model is constructed.
#[derive(Debug, Clone)]
pub struct CheckedProjectionEvidence {
    release: ModelRelease,
    byte_length: usize,
}
impl CheckedProjectionEvidence {
    pub fn format_version(&self) -> &ModelRelease {
        &self.release
    }
    pub fn byte_length(&self) -> usize {
        self.byte_length
    }
}
