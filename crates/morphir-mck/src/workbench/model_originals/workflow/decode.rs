//! Closed fixture operands. Work accounting belongs to this decode owner and
//! includes embedded JSON. Limits are explicit checker inputs, not host quotas.
use crate::json::strict::{Document, ReadWork, ReadWorkLimits, ReadWorkUsage, StrictReadError};
use std::num::NonZeroUsize;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum OperandResource {
    ByteVisits,
    Slots,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) enum DecodeError {
    Limits,
    SavedBytes,
    Shape(&'static str),
    Value(String),
    Literal(StrictReadError),
    Work(OperandResource),
    Allocation,
}
#[derive(Clone, Copy)]
pub(super) struct DecodeLimits {
    saved: NonZeroUsize,
    literal: ReadWorkLimits,
    byte_visits: NonZeroUsize,
    slots: NonZeroUsize,
}
impl DecodeLimits {
    pub(super) fn new(
        saved: usize,
        decode_bytes: usize,
        values: usize,
        byte_visits: usize,
        slots: usize,
    ) -> Result<Self, DecodeError> {
        Ok(Self {
            saved: NonZeroUsize::new(saved).ok_or(DecodeError::Limits)?,
            literal: ReadWorkLimits::new(decode_bytes, values).map_err(DecodeError::Literal)?,
            byte_visits: NonZeroUsize::new(byte_visits).ok_or(DecodeError::Limits)?,
            slots: NonZeroUsize::new(slots).ok_or(DecodeError::Limits)?,
        })
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct DecodeUsage {
    pub(super) literal: ReadWorkUsage,
    pub(super) byte_visits: usize,
    pub(super) slots: usize,
}
pub(super) struct Decoder {
    limits: DecodeLimits,
    literal: ReadWork,
    byte_visits: usize,
    slots: usize,
    fault: Option<DecodeError>,
}
impl Decoder {
    pub(super) fn saved_limit(&self) -> usize {
        self.limits.saved.get()
    }
    pub(super) fn new(limits: DecodeLimits) -> Self {
        Self {
            limits,
            literal: ReadWork::new(limits.literal),
            byte_visits: 0,
            slots: 0,
            fault: None,
        }
    }
    pub(super) fn usage(&self) -> DecodeUsage {
        DecodeUsage {
            literal: self.literal.usage(),
            byte_visits: self.byte_visits,
            slots: self.slots,
        }
    }
    pub(super) fn ready(&self) -> Result<(), DecodeError> {
        self.fault.clone().map_or(Ok(()), Err)
    }
    fn charge(&mut self, resource: OperandResource, count: usize) -> Result<(), DecodeError> {
        self.ready()?;
        let (used, limit) = match resource {
            OperandResource::ByteVisits => (&mut self.byte_visits, self.limits.byte_visits.get()),
            OperandResource::Slots => (&mut self.slots, self.limits.slots.get()),
        };
        let Some(next) = used.checked_add(count).filter(|next| *next <= limit) else {
            let error = DecodeError::Work(resource);
            self.fault = Some(error.clone());
            return Err(error);
        };
        *used = next;
        Ok(())
    }
    pub(super) fn bytes(&mut self, count: usize) -> Result<(), DecodeError> {
        self.charge(OperandResource::ByteVisits, count)
    }
    pub(super) fn slots(&mut self, count: usize) -> Result<(), DecodeError> {
        self.charge(OperandResource::Slots, count)
    }
    fn read_result<T>(&mut self, result: Result<T, StrictReadError>) -> Result<T, DecodeError> {
        match result {
            Ok(value) => Ok(value),
            Err(error) => {
                let exhausted = matches!(error, StrictReadError::Work(_));
                let error = DecodeError::Literal(error);
                if exhausted {
                    self.fault = Some(error.clone());
                }
                Err(error)
            }
        }
    }
    fn literal(&mut self, raw: &str) -> Result<Document, DecodeError> {
        self.ready()?;
        let result = Document::parse_exact_with_work(raw.as_bytes(), &mut self.literal);
        self.read_result(result)
    }
    pub(super) fn literal_with_raw<'source>(
        &mut self,
        raw: &'source str,
    ) -> Result<(Document, &'source serde_json::value::RawValue), DecodeError> {
        self.ready()?;
        if raw.len() > self.limits.saved.get() {
            return Err(DecodeError::SavedBytes);
        }
        let result = Document::parse_exact_with_raw(raw.as_bytes(), &mut self.literal);
        self.read_result(result)
    }
    pub(super) fn raw_members<'source>(
        &mut self,
        raw: &'source serde_json::value::RawValue,
    ) -> Result<Vec<(String, &'source serde_json::value::RawValue)>, DecodeError> {
        self.ready()?;
        let result = crate::json::strict::raw_members_with_work(raw, &mut self.literal);
        self.read_result(result)
    }
    pub(super) fn raw_elements<'source>(
        &mut self,
        raw: &'source serde_json::value::RawValue,
    ) -> Result<Vec<&'source serde_json::value::RawValue>, DecodeError> {
        self.ready()?;
        let result = crate::json::strict::raw_elements_with_work(raw, &mut self.literal);
        self.read_result(result)
    }
    #[cfg(test)]
    pub(super) fn decode<T: Decode>(&mut self, raw: &str) -> Result<T, DecodeError> {
        self.ready()?;
        if raw.len() > self.limits.saved.get() {
            return Err(DecodeError::SavedBytes);
        }
        let document = self.literal(raw)?;
        T::decode(&document, self)
    }
}
pub(super) trait Decode: Sized {
    fn decode(document: &Document, owner: &mut Decoder) -> Result<Self, DecodeError>;
}
impl<T: Decode> Decode for Box<T> {
    fn decode(document: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        owner.slots(1)?;
        Ok(Box::new(T::decode(document, owner)?))
    }
}
pub(super) trait Literal {
    fn decode_literal(
        document: &Document,
        expected: Self,
        owner: &mut Decoder,
    ) -> Result<(), DecodeError>;
}
impl Literal for bool {
    fn decode_literal(
        document: &Document,
        expected: Self,
        owner: &mut Decoder,
    ) -> Result<(), DecodeError> {
        owner.ready()?;
        if matches!(document, Document::Bool(actual) if *actual == expected) {
            Ok(())
        } else {
            Err(DecodeError::Shape("boolean constant"))
        }
    }
}
impl Literal for &str {
    fn decode_literal(
        document: &Document,
        expected: Self,
        owner: &mut Decoder,
    ) -> Result<(), DecodeError> {
        let actual = string(document, owner)?;
        owner.bytes(expected.len())?;
        if actual == expected {
            Ok(())
        } else {
            Err(DecodeError::Shape("text constant"))
        }
    }
}
impl Literal for i64 {
    fn decode_literal(
        document: &Document,
        expected: Self,
        owner: &mut Decoder,
    ) -> Result<(), DecodeError> {
        owner.ready()?;
        let Document::Number(number) = document else {
            return Err(DecodeError::Shape("numeric constant"));
        };
        owner.bytes(number.as_str().len().saturating_mul(4))?;
        let actual = super::super::super::artifacts::signed_rpc_code(&serde_json::Value::Number(
            number.clone(),
        ))
        .map_err(DecodeError::Value)?;
        if i64::from(actual) == expected {
            Ok(())
        } else {
            Err(DecodeError::Shape("numeric constant"))
        }
    }
}
pub(super) fn string<'a>(
    document: &'a Document,
    owner: &mut Decoder,
) -> Result<&'a str, DecodeError> {
    owner.ready()?;
    let Document::String(text) = document else {
        return Err(DecodeError::Shape("string"));
    };
    owner.bytes(text.len())?;
    Ok(text)
}
pub(super) struct Fields<'a>(&'a [(String, Document)]);
impl<'a> Fields<'a> {
    pub(super) fn new(
        document: &'a Document,
        names: &[&str],
        owner: &mut Decoder,
    ) -> Result<Self, DecodeError> {
        Self::with_optional(document, names, &[], owner)
    }
    pub(super) fn with_optional(
        document: &'a Document,
        required: &[&str],
        optional: &[&str],
        owner: &mut Decoder,
    ) -> Result<Self, DecodeError> {
        owner.ready()?;
        let Document::Object(fields) = document else {
            return Err(DecodeError::Shape("object"));
        };
        if fields.len() < required.len()
            || fields.len() > required.len().saturating_add(optional.len())
        {
            return Err(DecodeError::Shape("closed object fields"));
        }
        for (key, _) in fields {
            let mut found = false;
            for name in required.iter().chain(optional) {
                owner.bytes(key.len().saturating_add(name.len()))?;
                if key == name {
                    found = true;
                    break;
                }
            }
            if !found {
                return Err(DecodeError::Shape("unknown object field"));
            }
        }
        for name in required {
            Self::find(fields, name, owner)?;
        }
        Ok(Self(fields))
    }
    pub(super) fn field<T: Decode>(
        &self,
        name: &str,
        owner: &mut Decoder,
    ) -> Result<T, DecodeError> {
        T::decode(Self::find(self.0, name, owner)?, owner)
    }
    pub(super) fn document(
        &self,
        name: &str,
        owner: &mut Decoder,
    ) -> Result<&'a Document, DecodeError> {
        Self::find(self.0, name, owner)
    }
    pub(super) fn presence<T: Decode>(
        &self,
        name: &str,
        owner: &mut Decoder,
    ) -> Result<Presence<T>, DecodeError> {
        match Self::lookup(self.0, name, owner)? {
            Some(value) => T::decode(value, owner).map(Presence::Present),
            None => Ok(Presence::Absent),
        }
    }
    /// Same-reader, same-owner presence query for disjoint record branches.
    /// This does not decode the field or materialize another Document.
    pub(super) fn has(&self, name: &str, owner: &mut Decoder) -> Result<bool, DecodeError> {
        Self::lookup(self.0, name, owner).map(|value| value.is_some())
    }
    fn find(
        fields: &'a [(String, Document)],
        name: &str,
        owner: &mut Decoder,
    ) -> Result<&'a Document, DecodeError> {
        Self::lookup(fields, name, owner)?.ok_or(DecodeError::Shape("required object field"))
    }
    fn lookup(
        fields: &'a [(String, Document)],
        name: &str,
        owner: &mut Decoder,
    ) -> Result<Option<&'a Document>, DecodeError> {
        owner.ready()?;
        for (key, value) in fields {
            owner.bytes(key.len().saturating_add(name.len()))?;
            if key == name {
                return Ok(Some(value));
            }
        }
        Ok(None)
    }
}
pub(super) fn nested_discriminator<'a>(
    document: &'a Document,
    parent: &str,
    tag: &str,
    owner: &mut Decoder,
) -> Result<&'a str, DecodeError> {
    owner.ready()?;
    let Document::Object(fields) = document else {
        return Err(DecodeError::Shape("nested tagged object"));
    };
    discriminator(Fields::find(fields, parent, owner)?, tag, owner)
}
#[derive(Debug)]
pub(super) enum Presence<T> {
    Absent,
    Present(T),
}
pub(super) fn discriminator<'a>(
    document: &'a Document,
    name: &str,
    owner: &mut Decoder,
) -> Result<&'a str, DecodeError> {
    owner.ready()?;
    let Document::Object(fields) = document else {
        return Err(DecodeError::Shape("tagged object"));
    };
    string(Fields::find(fields, name, owner)?, owner)
}
#[derive(Debug)]
pub(super) struct Nullable<T>(pub(super) Option<T>);
impl<T: Decode> Decode for Nullable<T> {
    fn decode(value: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        owner.ready()?;
        if matches!(value, Document::Null) {
            Ok(Self(None))
        } else {
            T::decode(value, owner).map(|value| Self(Some(value)))
        }
    }
}
#[derive(Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct Text<const MIN: usize, const MAX: usize>(pub(super) String);
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DataValueError {
    Length,
    Range,
    Pattern,
    Path,
    Version,
}
impl<const MIN: usize, const MAX: usize> Text<MIN, MAX> {
    fn validate(value: &str) -> Result<(), DataValueError> {
        if !(MIN..=MAX).contains(&value.chars().count()) {
            return Err(DataValueError::Length);
        }
        Ok(())
    }
    pub fn new(value: &str) -> Result<Self, DataValueError> {
        Self::validate(value)?;
        Ok(Self(value.to_owned()))
    }
    pub(super) fn from_owned(value: String) -> Result<Self, DataValueError> {
        Self::validate(&value)?;
        Ok(Self(value))
    }
    pub fn as_str(&self) -> &str {
        &self.0
    }
}
impl<const MIN: usize, const MAX: usize> serde::Serialize for Text<MIN, MAX> {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.0)
    }
}
impl<const MIN: usize, const MAX: usize> Decode for Text<MIN, MAX> {
    fn decode(value: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        let text = string(value, owner)?;
        Self::validate(text).map_err(|_| DecodeError::Shape("text length"))?;
        Ok(Self(text.to_owned()))
    }
}
pub(super) use super::super::FixtureAlias;
impl Decode for FixtureAlias {
    fn decode(value: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        let text = string(value, owner)?;
        Self::new(text).map_err(|_| DecodeError::Shape("fixture alias"))
    }
}
#[derive(Debug)]
pub struct Natural<const MIN: u64, const MAX: u64>(pub(super) u64);
impl<const MIN: u64, const MAX: u64> Natural<MIN, MAX> {
    pub fn new(value: u64) -> Result<Self, DataValueError> {
        if !(MIN..=MAX).contains(&value) {
            return Err(DataValueError::Range);
        }
        Ok(Self(value))
    }
    pub fn get(&self) -> u64 {
        self.0
    }
}
impl<const MIN: u64, const MAX: u64> serde::Serialize for Natural<MIN, MAX> {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_u64(self.0)
    }
}
impl<const MIN: u64, const MAX: u64> Decode for Natural<MIN, MAX> {
    fn decode(value: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        owner.ready()?;
        let Document::Number(number) = value else {
            return Err(DecodeError::Shape("number"));
        };
        let token = number.as_str();
        // Existing exact-decimal conversion scans and copies the token. Reserve
        // those byte visits before entering that conversion.
        owner.bytes(token.len().saturating_mul(4))?;
        let number = super::super::super::artifacts::integer_u64(
            &serde_json::Value::Number(number.clone()),
            MAX,
        )
        .map_err(DecodeError::Value)?;
        if number < MIN {
            return Err(DecodeError::Shape("number lower bound"));
        }
        Ok(Self(number))
    }
}
#[derive(Debug)]
pub struct Items<T, const MIN: usize, const MAX: usize>(pub(super) Vec<T>);
impl<T, const MIN: usize, const MAX: usize> Items<T, MIN, MAX> {
    pub fn new(values: Vec<T>) -> Result<Self, DataValueError> {
        if !(MIN..=MAX).contains(&values.len()) {
            return Err(DataValueError::Length);
        }
        Ok(Self(values))
    }
    pub fn as_slice(&self) -> &[T] {
        &self.0
    }
}
impl<T: serde::Serialize, const MIN: usize, const MAX: usize> serde::Serialize
    for Items<T, MIN, MAX>
{
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        self.0.serialize(s)
    }
}
impl<T: Decode, const MIN: usize, const MAX: usize> Decode for Items<T, MIN, MAX> {
    fn decode(value: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        owner.ready()?;
        let Document::Array(items) = value else {
            return Err(DecodeError::Shape("array"));
        };
        if !(MIN..=MAX).contains(&items.len()) {
            return Err(DecodeError::Shape("array length"));
        }
        owner.slots(items.len())?;
        let mut result = Vec::new();
        result
            .try_reserve_exact(items.len())
            .map_err(|_| DecodeError::Allocation)?;
        for item in items {
            result.push(T::decode(item, owner)?);
        }
        Ok(Self(result))
    }
}
#[derive(Debug)]
pub(super) struct RawJson(pub(super) String);
impl Decode for RawJson {
    fn decode(value: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        let text = string(value, owner)?;
        if text.len() > 1048576 {
            return Err(DecodeError::Shape("embedded JSON UTF-8 bytes"));
        }
        owner.literal(text)?;
        Ok(Self(text.to_owned()))
    }
}
#[derive(Debug)]
pub(super) struct JsonBool(pub(super) bool);
impl Decode for JsonBool {
    fn decode(value: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        owner.ready()?;
        if let Document::Bool(value) = value {
            Ok(Self(*value))
        } else {
            Err(DecodeError::Shape("boolean"))
        }
    }
}
#[derive(Debug)]
pub(super) struct JsonNull;
impl Decode for JsonNull {
    fn decode(value: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        owner.ready()?;
        if matches!(value, Document::Null) {
            Ok(Self)
        } else {
            Err(DecodeError::Shape("null"))
        }
    }
}

pub(super) use super::super::inventory::ContentSha256;
impl Decode for ContentSha256 {
    fn decode(value: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        let text = string(value, owner)?;
        super::super::inventory::hash(&serde_json::Value::String(text.to_owned()))
            .map(Self)
            .map_err(|error| DecodeError::Value(error.to_string()))
    }
}
#[derive(Debug)]
pub struct SourcePath(pub(super) super::super::RootPath);
impl SourcePath {
    pub fn new(value: &str) -> Result<Self, DataValueError> {
        if value.chars().count() > 4096 {
            return Err(DataValueError::Length);
        }
        super::super::Root::file(value)
            .map(|root| Self(root.path))
            .map_err(|_| DataValueError::Path)
    }
    pub fn as_str(&self) -> &str {
        self.0.as_str()
    }
}
impl serde::Serialize for SourcePath {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(self.as_str())
    }
}
impl Decode for SourcePath {
    fn decode(value: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        let text = string(value, owner)?;
        if text.chars().count() > 4096 {
            return Err(DecodeError::Shape("source path length"));
        }
        super::super::RootPath::parse(&serde_json::Value::String(text.to_owned()))
            .map(Self)
            .map_err(|error| DecodeError::Value(error.to_string()))
    }
}
#[derive(Debug)]
pub struct U64Token(pub(super) super::super::RequestId);
impl U64Token {
    pub fn new(value: u64) -> Self {
        Self(super::super::RequestId(value))
    }
    pub fn get(&self) -> u64 {
        self.0.get()
    }
}
impl serde::Serialize for U64Token {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.collect_str(&self.0.get())
    }
}
impl Decode for U64Token {
    fn decode(value: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        let text = string(value, owner)?;
        if text.len() > 20 || (text.len() > 1 && text.starts_with('0')) {
            return Err(DecodeError::Shape("canonical u64 token"));
        }
        super::super::RequestId::parse(text)
            .map(Self)
            .map_err(|error| DecodeError::Value(error.to_string()))
    }
}

pub(super) trait UniqueKey {
    fn key(&self) -> &str;
}
impl<const MIN: usize, const MAX: usize> UniqueKey for Text<MIN, MAX> {
    fn key(&self) -> &str {
        &self.0
    }
}
#[derive(Debug)]
pub(super) struct UniqueItems<T, const MIN: usize, const MAX: usize>(pub(super) Vec<T>);
impl<T: Decode + UniqueKey, const MIN: usize, const MAX: usize> Decode
    for UniqueItems<T, MIN, MAX>
{
    fn decode(value: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        let Items(items) = Items::<T, MIN, MAX>::decode(value, owner)?;
        owner.slots(items.len())?;
        let mut keys = Vec::new();
        keys.try_reserve_exact(items.len())
            .map_err(|_| DecodeError::Allocation)?;
        keys.extend(items.iter().map(UniqueKey::key));
        // Fallible heapsort charges comparisons before inspecting key bytes.
        // No hidden global comparator state or quadratic duplicate scan.
        for start in (0..keys.len() / 2).rev() {
            sift(&mut keys, start, owner)?;
        }
        for end in (1..keys.len()).rev() {
            keys.swap(0, end);
            sift(&mut keys[..end], 0, owner)?;
        }
        for pair in keys.windows(2) {
            if compare(pair[0], pair[1], owner)?.is_eq() {
                return Err(DecodeError::Shape("unique array values"));
            }
        }
        Ok(Self(items))
    }
}
fn compare(
    left: &str,
    right: &str,
    owner: &mut Decoder,
) -> Result<std::cmp::Ordering, DecodeError> {
    owner.bytes(left.len().saturating_add(right.len()))?;
    Ok(left.cmp(right))
}
fn sift(keys: &mut [&str], mut root: usize, owner: &mut Decoder) -> Result<(), DecodeError> {
    while let Some(mut child) = root
        .checked_mul(2)
        .and_then(|v| v.checked_add(1))
        .filter(|child| *child < keys.len())
    {
        if child + 1 < keys.len() && compare(keys[child], keys[child + 1], owner)?.is_lt() {
            child += 1;
        }
        if !compare(keys[root], keys[child], owner)?.is_lt() {
            break;
        }
        keys.swap(root, child);
        root = child;
    }
    Ok(())
}
