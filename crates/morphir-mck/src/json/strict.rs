//! Duplicate-aware JSON, retaining fixture member order for JSON.stringify inputs.
use serde::de::{DeserializeSeed, Error, MapAccess, SeqAccess, Visitor};
use serde::ser::{SerializeMap, SerializeSeq};
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::{Number, Value};
use std::fmt;

mod requested_storage;
mod work;
pub(crate) use requested_storage::{
    requested_codec_typed_storage_bound, requested_diagnostic_storage_bound,
    requested_document_storage_bound, requested_raw_members_storage_bound,
};
#[cfg(test)]
pub(crate) use work::ReadWorkResource;
pub(crate) use work::{ReadWork, ReadWorkLimits, ReadWorkUsage, StrictReadError};

trait Work {
    fn decode(&mut self, bytes: usize) -> Result<(), String>;
    fn value(&mut self) -> Result<(), String>;
}
struct Unchecked;
impl Work for Unchecked {
    fn decode(&mut self, _: usize) -> Result<(), String> {
        Ok(())
    }
    fn value(&mut self) -> Result<(), String> {
        Ok(())
    }
}

#[derive(Debug, Clone)]
pub(crate) enum Document {
    Null,
    Bool(bool),
    Number(Number),
    String(String),
    Array(Vec<Document>),
    Object(Vec<(String, Document)>),
}
// Borrow subtrees from the original bytes. Inspecting raw token kinds avoids
// serde_json's feature-dependent synthetic maps for arbitrary-precision numbers.
// The member visitor still sees every decoded key, including duplicate keys.
struct MembersSeed<'a, W>(&'a mut W);
struct KeySeed<'a, W>(&'a mut W);
impl<'de, W: Work> DeserializeSeed<'de> for KeySeed<'_, W> {
    type Value = String;
    fn deserialize<D: Deserializer<'de>>(self, deserializer: D) -> Result<String, D::Error> {
        // MapAccess calls this seed only when a real member exists. Reserve
        // its child before decoding/allocating the key or buffering its value.
        self.0.value().map_err(D::Error::custom)?;
        String::deserialize(deserializer)
    }
}
impl<'de, W: Work> DeserializeSeed<'de> for MembersSeed<'_, W> {
    type Value = Vec<(String, &'de serde_json::value::RawValue)>;
    fn deserialize<D: Deserializer<'de>>(self, deserializer: D) -> Result<Self::Value, D::Error> {
        deserializer.deserialize_map(self)
    }
}
impl<'de, W: Work> Visitor<'de> for MembersSeed<'_, W> {
    type Value = Vec<(String, &'de serde_json::value::RawValue)>;
    fn expecting(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("JSON without duplicate members")
    }
    fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Self::Value, A::Error> {
        let mut values = Vec::new();
        let mut keys = std::collections::BTreeSet::new();
        while let Some(key) = map.next_key_seed(KeySeed(&mut *self.0))? {
            if !keys.insert(key.clone()) {
                return Err(A::Error::custom(format!("duplicate key {key}")));
            }
            values.push((key, map.next_value()?));
        }
        Ok(values)
    }
}

struct ElementsSeed<'a, W>(&'a mut W);
struct ElementSeed<'a, W>(&'a mut W);
impl<'de, W: Work> DeserializeSeed<'de> for ElementSeed<'_, W> {
    type Value = &'de serde_json::value::RawValue;
    fn deserialize<D: Deserializer<'de>>(self, deserializer: D) -> Result<Self::Value, D::Error> {
        self.0.value().map_err(D::Error::custom)?;
        Deserialize::deserialize(deserializer)
    }
}
impl<'de, W: Work> DeserializeSeed<'de> for ElementsSeed<'_, W> {
    type Value = Vec<&'de serde_json::value::RawValue>;
    fn deserialize<D: Deserializer<'de>>(self, deserializer: D) -> Result<Self::Value, D::Error> {
        deserializer.deserialize_seq(self)
    }
}
impl<'de, W: Work> Visitor<'de> for ElementsSeed<'_, W> {
    type Value = Vec<&'de serde_json::value::RawValue>;
    fn expecting(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("JSON array")
    }
    fn visit_seq<A: SeqAccess<'de>>(self, mut sequence: A) -> Result<Self::Value, A::Error> {
        let mut values = Vec::new();
        while let Some(value) = sequence.next_element_seed(ElementSeed(&mut *self.0))? {
            values.push(value);
        }
        Ok(values)
    }
}
fn seeded<'de, S: DeserializeSeed<'de>>(text: &'de str, seed: S) -> Result<S::Value, String> {
    let mut deserializer = serde_json::Deserializer::from_str(text);
    let value = seed
        .deserialize(&mut deserializer)
        .map_err(|e| e.to_string())?;
    deserializer.end().map_err(|e| e.to_string())?;
    Ok(value)
}
fn document<W: Work>(
    bytes: &[u8],
    parse_number: fn(&str) -> Result<Number, String>,
    work: &mut W,
) -> Result<Document, String> {
    document_with_raw(bytes, parse_number, work).map(|(document, _)| document)
}

fn document_with_raw<'source, W: Work>(
    bytes: &'source [u8],
    parse_number: fn(&str) -> Result<Number, String>,
    work: &mut W,
) -> Result<(Document, &'source serde_json::value::RawValue), String> {
    work.value()?;
    work.decode(bytes.len())?;
    let raw =
        serde_json::from_slice::<&serde_json::value::RawValue>(bytes).map_err(|e| e.to_string())?;
    let document = from_raw_numbers(raw, 0, parse_number, work)?;
    Ok((document, raw))
}

/// Borrow exact child tokens using the same duplicate-aware object seed.
/// Each additional container decode and child buffering spends the caller's
/// existing cumulative read work. These views prove no packet provenance.
pub(crate) fn raw_members_with_work<'source>(
    raw: &'source serde_json::value::RawValue,
    work: &mut ReadWork,
) -> Result<Vec<(String, &'source serde_json::value::RawValue)>, StrictReadError> {
    work.decode(raw.get().len())
        .and_then(|()| seeded(raw.get(), MembersSeed(&mut *work)))
        .map_err(|error| work.error(error))
}

pub(crate) fn raw_elements_with_work<'source>(
    raw: &'source serde_json::value::RawValue,
    work: &mut ReadWork,
) -> Result<Vec<&'source serde_json::value::RawValue>, StrictReadError> {
    work.decode(raw.get().len())
        .and_then(|()| seeded(raw.get(), ElementsSeed(&mut *work)))
        .map_err(|error| work.error(error))
}

fn from_raw_numbers<W: Work>(
    raw: &serde_json::value::RawValue,
    depth: usize,
    parse_number: fn(&str) -> Result<Number, String>,
    work: &mut W,
) -> Result<Document, String> {
    let token = raw.get();
    let kind = token.as_bytes()[0];
    // RawValue intentionally skips serde's recursion guard. Retain the existing
    // 127-container limit explicitly before recursively constructing a document.
    if matches!(kind, b'{' | b'[') && depth >= 127 {
        return Err("recursion limit exceeded".into());
    }
    match kind {
        b'{' => {
            work.decode(token.len())?;
            let members = seeded(token, MembersSeed(&mut *work))?;
            members
                .into_iter()
                .map(|(key, value)| {
                    Ok((key, from_raw_numbers(value, depth + 1, parse_number, work)?))
                })
                .collect::<Result<_, _>>()
                .map(Document::Object)
        }
        b'[' => {
            work.decode(token.len())?;
            let values = seeded(token, ElementsSeed(&mut *work))?;
            values
                .into_iter()
                .map(|value| from_raw_numbers(value, depth + 1, parse_number, work))
                .collect::<Result<_, _>>()
                .map(Document::Array)
        }
        b'"' => {
            work.decode(token.len())?;
            serde_json::from_str(token)
                .map(Document::String)
                .map_err(|e| e.to_string())
        }
        b't' => Ok(Document::Bool(true)),
        b'f' => Ok(Document::Bool(false)),
        b'n' => Ok(Document::Null),
        _ => {
            work.decode(token.len())?;
            parse_number(token).map(Document::Number)
        }
    }
}
fn number(token: &str) -> Result<Number, String> {
    if let Ok(value) = token.parse::<u64>() {
        return Ok(value.into());
    }
    if let Ok(value) = token.parse::<i64>()
        && value != 0
    {
        return Ok(value.into());
    }
    // Preserve finite IEEE-754 values and negative zero independent of serde's
    // arbitrary_precision feature; integer storage retains the original behavior.
    let value = token.parse::<f64>().map_err(|e| e.to_string())?;
    Number::from_f64(value).ok_or_else(|| "invalid number".into())
}
impl Serialize for Document {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        match self {
            Self::Null => serializer.serialize_unit(),
            Self::Bool(v) => serializer.serialize_bool(*v),
            Self::Number(v) => v.serialize(serializer),
            Self::String(v) => serializer.serialize_str(v),
            Self::Array(values) => {
                let mut seq = serializer.serialize_seq(Some(values.len()))?;
                for value in values {
                    seq.serialize_element(value)?;
                }
                seq.end()
            }
            Self::Object(values) => {
                // ECMAScript object enumeration places array-index keys first.
                let mut entries: Vec<_> = values.iter().collect();
                let index = |key: &str| {
                    key.parse::<u32>()
                        .ok()
                        .filter(|v| *v != u32::MAX && v.to_string() == key)
                };
                entries.sort_by(|(left, _), (right, _)| match (index(left), index(right)) {
                    (Some(a), Some(b)) => a.cmp(&b),
                    (Some(_), None) => std::cmp::Ordering::Less,
                    (None, Some(_)) => std::cmp::Ordering::Greater,
                    _ => std::cmp::Ordering::Equal,
                });
                let mut map = serializer.serialize_map(Some(entries.len()))?;
                for (key, value) in entries {
                    map.serialize_entry(key, value)?;
                }
                map.end()
            }
        }
    }
}
impl Document {
    pub fn parse(bytes: &[u8]) -> Result<Self, String> {
        document(bytes, number, &mut Unchecked)
    }
    /// The existing exact literal traversal, without a serde Value conversion.
    pub(crate) fn parse_exact(bytes: &[u8]) -> Result<Self, String> {
        document(bytes, exact_number, &mut Unchecked)
    }
    /// Selected unsigned-count configuration uses the original numeric token
    /// before Number can normalize representations such as negative zero.
    pub(crate) fn parse_unsigned_counts(bytes: &[u8]) -> Result<Self, String> {
        fn unsigned(token: &str) -> Result<Number, String> {
            if token.is_empty()
                || !token.bytes().all(|byte| byte.is_ascii_digit())
                || (token.len() > 1 && token.starts_with('0'))
            {
                return Err("count requires canonical unsigned integer".into());
            }
            token
                .parse::<u64>()
                .map_err(|_| "count exceeds u64".to_owned())?;
            exact_number(token)
        }
        document(bytes, unsigned, &mut Unchecked)
    }
    pub(crate) fn parse_exact_with_work(
        bytes: &[u8],
        work: &mut ReadWork,
    ) -> Result<Self, StrictReadError> {
        document(bytes, exact_number, work).map_err(|error| work.error(error))
    }
    pub(crate) fn parse_exact_with_raw<'source>(
        bytes: &'source [u8],
        work: &mut ReadWork,
    ) -> Result<(Self, &'source serde_json::value::RawValue), StrictReadError> {
        document_with_raw(bytes, exact_number, work).map_err(|error| work.error(error))
    }
    pub fn value(&self) -> Value {
        serde_json::to_value(self).expect("JSON value")
    }
    pub fn text(&self) -> String {
        serde_json::to_string(self).expect("JSON document")
    }
    pub fn get(&self, key: &str) -> Result<&Self, String> {
        match self {
            Self::Object(entries) => entries
                .iter()
                .find(|(name, _)| name == key)
                .map(|(_, value)| value)
                .ok_or_else(|| format!("missing field {key}")),
            _ => Err("expected object".into()),
        }
    }
    pub fn mutate(&mut self, path: &[String], replacement: Option<Self>) -> Result<(), String> {
        let (key, rest) = path.split_first().ok_or("empty mutation path")?;
        let Self::Object(entries) = self else {
            return Err("mutation target is not an object".into());
        };
        let at = entries.iter().position(|(name, _)| name == key);
        if !rest.is_empty() {
            return entries
                .get_mut(at.ok_or_else(|| format!("missing mutation target {key}"))?)
                .expect("index")
                .1
                .mutate(rest, replacement);
        }
        match (at, replacement) {
            (Some(at), Some(value)) => entries[at].1 = value,
            (None, Some(value)) => entries.push((key.clone(), value)),
            (Some(at), None) => {
                entries.remove(at);
            }
            (None, None) => return Err(format!("missing removal target {key}")),
        }
        Ok(())
    }
}
pub(crate) fn parse(text: &str) -> Result<Value, String> {
    Document::parse(text.as_bytes()).map(|doc| doc.value())
}

/// Duplicate-aware exact decimal numbers, with literal objects built through
/// the same RawValue traversal. Never deserialize arbitrary objects as Value:
/// serde's private number/raw-value maps could otherwise impersonate scalars.
pub(crate) fn parse_exact(text: &str) -> Result<Value, String> {
    Document::parse_exact(text.as_bytes()).map(|doc| doc.value())
}
fn exact_number(token: &str) -> Result<Number, String> {
    token.parse::<Number>().map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exact_work_is_cumulative_across_documents_and_refusals_stay_latched() {
        let mut work = ReadWork::new(ReadWorkLimits::new(31, 5).unwrap());
        let doc = Document::parse_exact_with_work(br#"{"a":[1,2]}"#, &mut work).unwrap();
        assert_eq!(doc.text(), r#"{"a":[1,2]}"#);
        assert_eq!(
            work.usage(),
            ReadWorkUsage {
                decode_bytes: 29,
                values: 4
            }
        );
        Document::parse_exact_with_work(b"0", &mut work).unwrap();
        assert_eq!(
            work.usage(),
            ReadWorkUsage {
                decode_bytes: 31,
                values: 5
            }
        );
        assert!(matches!(
            Document::parse_exact_with_work(b"0", &mut work),
            Err(StrictReadError::Work(ReadWorkResource::Values))
        ));
        assert!(matches!(
            Document::parse_exact_with_work(b"null", &mut work),
            Err(StrictReadError::Work(ReadWorkResource::Values))
        ));
        assert_eq!(
            work.usage(),
            ReadWorkUsage {
                decode_bytes: 31,
                values: 5
            }
        );
    }

    #[test]
    fn value_refusal_precedes_child_buffering_and_decode_refusal_precedes_number_parse() {
        let mut values = ReadWork::new(ReadWorkLimits::new(100, 3).unwrap());
        assert!(matches!(
            Document::parse_exact_with_work(br#"{"a":[1,2]}"#, &mut values),
            Err(StrictReadError::Work(ReadWorkResource::Values))
        ));
        assert_eq!(
            values.usage(),
            ReadWorkUsage {
                decode_bytes: 27,
                values: 3
            }
        );
        let mut bytes = ReadWork::new(ReadWorkLimits::new(28, 4).unwrap());
        assert!(matches!(
            Document::parse_exact_with_work(br#"{"a":[1,2]}"#, &mut bytes),
            Err(StrictReadError::Work(ReadWorkResource::DecodeBytes))
        ));
        assert_eq!(
            bytes.usage(),
            ReadWorkUsage {
                decode_bytes: 28,
                values: 4
            }
        );
    }

    #[test]
    fn budgeted_exact_reader_preserves_literals_and_rejects_hidden_duplicate_keys() {
        let mut work = ReadWork::new(ReadWorkLimits::new(8192, 128).unwrap());
        let doc = Document::parse_exact_with_work(
            br#"{"$serde_json::private::Number":"1","v":9007199254740993,"z":-0.0}"#,
            &mut work,
        )
        .unwrap();
        assert!(
            matches!(doc.get("$serde_json::private::Number").unwrap(), Document::String(s) if s == "1")
        );
        assert!(
            matches!(doc.get("v").unwrap(), Document::Number(n) if n.to_string() == "9007199254740993")
        );
        assert!(matches!(doc.get("z").unwrap(), Document::Number(n) if n.to_string() == "-0.0"));
        assert!(matches!(
            Document::parse_exact_with_work(br#"{"a":[{"x":1,"\u0078":2}]}"#, &mut work),
            Err(StrictReadError::Json(_))
        ));
        let spent = work.usage();
        assert!(spent.decode_bytes > 0 && spent.values > 0);
        Document::parse_exact_with_work(b"true", &mut work).unwrap();
        assert_eq!(work.usage().values, spent.values + 1);
        assert_eq!(work.usage().decode_bytes, spent.decode_bytes + 4);
    }

    #[test]
    fn numeric_tokens_keep_their_values_under_unified_serde_features() {
        for (input, expected) in [
            ("1.5", 1.5_f64),
            ("1e2", 100.0),
            ("-0", -0.0),
            ("-0.0", -0.0),
        ] {
            let value = parse(input).unwrap();
            assert_eq!(
                value.as_f64().map(f64::to_bits),
                Some(expected.to_bits()),
                "{input}"
            );
        }
        let value = parse(r#"{"equals":1.5,"values":[1e2,-0]}"#).unwrap();
        assert_eq!(value["equals"].as_f64(), Some(1.5));
        assert_eq!(value["values"][0].as_f64(), Some(100.0));
        assert_eq!(
            value["values"][1].as_f64().unwrap().to_bits(),
            (-0.0_f64).to_bits()
        );
    }

    #[test]
    fn private_serde_token_members_are_real_objects_and_duplicates_still_fail() {
        let input = r#"{"$serde_json::private::Number":"1.5","nested":{"$serde_json::private::Number":"-0"}}"#;
        let value = parse(input).unwrap();
        assert!(value.is_object());
        assert_eq!(value["$serde_json::private::Number"], "1.5");
        assert_eq!(value["nested"]["$serde_json::private::Number"], "-0");
        assert_eq!(Document::parse(input.as_bytes()).unwrap().text(), input);
        for duplicate in [
            r#"{"a":1,"\u0061":2}"#,
            r#"{"nested":{"a":1,"a":2}}"#,
            r#"{"$serde_json::private::Number":"1","$serde_json::private::Number":"2"}"#,
        ] {
            assert!(parse(duplicate).is_err(), "{duplicate}");
        }
    }

    #[test]
    fn exact_numbers_do_not_reinterpret_literal_private_marker_objects() {
        let value = parse_exact(r#"{"count":1.00000000000000001,"literal":{"$serde_json::private::Number":"1"},"raw":{"$serde_json::private::RawValue":"true"}}"#).unwrap();
        assert_eq!(
            value["count"].as_number().unwrap().to_string(),
            "1.00000000000000001"
        );
        assert_eq!(value["literal"]["$serde_json::private::Number"], "1");
        assert_eq!(value["raw"]["$serde_json::private::RawValue"], "true");
        assert!(parse_exact(r#"{"count":1,"\u0063ount":2}"#).is_err());
        assert!(parse_exact(&format!("{}0{}", "[".repeat(128), "]".repeat(128))).is_err());
    }

    #[test]
    fn finite_numbers_and_existing_nesting_bound_are_preserved() {
        for invalid in ["1e400", "-1e400", "01", "1.", "+1", "NaN"] {
            assert!(parse(invalid).is_err(), "{invalid}");
        }
        assert!(parse(&format!("{}0{}", "[".repeat(127), "]".repeat(127))).is_ok());
        assert!(parse(&format!("{}0{}", "[".repeat(128), "]".repeat(128))).is_err());
    }
}

#[cfg(test)]
#[path = "strict_raw_tests.rs"]
mod raw_window_tests;
