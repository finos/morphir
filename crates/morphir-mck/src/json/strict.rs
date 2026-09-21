//! Duplicate-aware JSON, retaining fixture member order for JSON.stringify inputs.
use serde::de::{Error, MapAccess, SeqAccess, Visitor};
use serde::ser::{SerializeMap, SerializeSeq};
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::{Number, Value};
use std::fmt;

#[derive(Debug, Clone)]
pub(crate) enum Document {
    Null,
    Bool(bool),
    Number(Number),
    String(String),
    Array(Vec<Document>),
    Object(Vec<(String, Document)>),
}
impl<'de> Deserialize<'de> for Document {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct JsonVisitor;
        impl<'de> Visitor<'de> for JsonVisitor {
            type Value = Document;
            fn expecting(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                f.write_str("JSON without duplicate members")
            }
            fn visit_unit<E: Error>(self) -> Result<Document, E> {
                Ok(Document::Null)
            }
            fn visit_bool<E: Error>(self, value: bool) -> Result<Document, E> {
                Ok(Document::Bool(value))
            }
            fn visit_i64<E: Error>(self, value: i64) -> Result<Document, E> {
                Ok(Document::Number(value.into()))
            }
            fn visit_u64<E: Error>(self, value: u64) -> Result<Document, E> {
                Ok(Document::Number(value.into()))
            }
            fn visit_f64<E: Error>(self, value: f64) -> Result<Document, E> {
                Number::from_f64(value)
                    .map(Document::Number)
                    .ok_or_else(|| E::custom("invalid number"))
            }
            fn visit_str<E: Error>(self, value: &str) -> Result<Document, E> {
                Ok(Document::String(value.into()))
            }
            fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<Document, A::Error> {
                let mut values = Vec::new();
                while let Some(value) = seq.next_element()? {
                    values.push(value);
                }
                Ok(Document::Array(values))
            }
            fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Document, A::Error> {
                let mut values = Vec::new();
                let mut keys = std::collections::BTreeSet::new();
                while let Some(key) = map.next_key::<String>()? {
                    if !keys.insert(key.clone()) {
                        return Err(A::Error::custom(format!("duplicate key {key}")));
                    }
                    values.push((key, map.next_value()?));
                }
                Ok(Document::Object(values))
            }
        }
        deserializer.deserialize_any(JsonVisitor)
    }
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
        serde_json::from_slice(bytes).map_err(|e| e.to_string())
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
