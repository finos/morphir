//! Duplicate-aware JSON, retaining fixture member order for JSON.stringify inputs.
use serde::de::{Error, MapAccess, Visitor};
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
// Borrow subtrees from the original bytes. Inspecting raw token kinds avoids
// serde_json's feature-dependent synthetic maps for arbitrary-precision numbers.
// The member visitor still sees every decoded key, including duplicate keys.
struct Members<'a>(Vec<(String, &'a serde_json::value::RawValue)>);
impl<'de> Deserialize<'de> for Members<'de> {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct MemberVisitor;
        impl<'de> Visitor<'de> for MemberVisitor {
            type Value = Members<'de>;
            fn expecting(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                f.write_str("JSON without duplicate members")
            }
            fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Self::Value, A::Error> {
                let mut values = Vec::new();
                let mut keys = std::collections::BTreeSet::new();
                while let Some(key) = map.next_key::<String>()? {
                    if !keys.insert(key.clone()) {
                        return Err(A::Error::custom(format!("duplicate key {key}")));
                    }
                    values.push((key, map.next_value()?));
                }
                Ok(Members(values))
            }
        }
        deserializer.deserialize_map(MemberVisitor)
    }
}
fn from_raw(raw: &serde_json::value::RawValue, depth: usize) -> Result<Document, String> {
    let token = raw.get();
    let kind = token.as_bytes()[0];
    // RawValue intentionally skips serde's recursion guard. Retain the existing
    // 127-container limit explicitly before recursively constructing a document.
    if matches!(kind, b'{' | b'[') && depth >= 127 {
        return Err("recursion limit exceeded".into());
    }
    match kind {
        b'{' => {
            let members: Members<'_> = serde_json::from_str(token).map_err(|e| e.to_string())?;
            members
                .0
                .into_iter()
                .map(|(key, value)| Ok((key, from_raw(value, depth + 1)?)))
                .collect::<Result<_, _>>()
                .map(Document::Object)
        }
        b'[' => {
            let values: Vec<&serde_json::value::RawValue> =
                serde_json::from_str(token).map_err(|e| e.to_string())?;
            values
                .into_iter()
                .map(|value| from_raw(value, depth + 1))
                .collect::<Result<_, _>>()
                .map(Document::Array)
        }
        b'"' => serde_json::from_str(token)
            .map(Document::String)
            .map_err(|e| e.to_string()),
        b't' => Ok(Document::Bool(true)),
        b'f' => Ok(Document::Bool(false)),
        b'n' => Ok(Document::Null),
        _ => number(token).map(Document::Number),
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
        let raw = serde_json::from_slice::<&serde_json::value::RawValue>(bytes)
            .map_err(|e| e.to_string())?;
        from_raw(raw, 0)
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

#[cfg(test)]
mod tests {
    use super::*;

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
    fn finite_numbers_and_existing_nesting_bound_are_preserved() {
        for invalid in ["1e400", "-1e400", "01", "1.", "+1", "NaN"] {
            assert!(parse(invalid).is_err(), "{invalid}");
        }
        assert!(parse(&format!("{}0{}", "[".repeat(127), "]".repeat(127))).is_ok());
        assert!(parse(&format!("{}0{}", "[".repeat(128), "]".repeat(128))).is_err());
    }
}
