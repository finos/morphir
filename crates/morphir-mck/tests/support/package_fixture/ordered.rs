// Copyright 2026 FINOS
// SPDX-License-Identifier: Apache-2.0
//! Ordered output belongs only to fixture authoring; canonical signing sorts keys separately.
use serde::{
    Serialize, Serializer,
    ser::{SerializeMap, SerializeSeq},
};
use serde_json::Value;

#[derive(Clone)]
pub enum Json {
    Value(Value),
    Object(Vec<(String, Json)>),
    Array(Vec<Json>),
}
impl Serialize for Json {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        match self {
            Self::Value(value) => {
                // Parsed values used sorted maps before feature unification;
                // explicit Json::Object entries keep their authored order.
                let mut value = value.clone();
                value.sort_all_objects();
                value.serialize(serializer)
            }
            Self::Object(entries) => {
                let mut map = serializer.serialize_map(Some(entries.len()))?;
                for (key, value) in entries {
                    map.serialize_entry(key, value)?;
                }
                map.end()
            }
            Self::Array(entries) => {
                let mut seq = serializer.serialize_seq(Some(entries.len()))?;
                for value in entries {
                    seq.serialize_element(value)?;
                }
                seq.end()
            }
        }
    }
}
impl From<Value> for Json {
    fn from(value: Value) -> Self {
        Self::Value(value)
    }
}
impl From<&Value> for Json {
    fn from(value: &Value) -> Self {
        Self::Value(value.clone())
    }
}
impl From<&str> for Json {
    fn from(value: &str) -> Self {
        Self::Value(value.into())
    }
}
impl From<String> for Json {
    fn from(value: String) -> Self {
        Self::Value(value.into())
    }
}
impl From<bool> for Json {
    fn from(value: bool) -> Self {
        Self::Value(value.into())
    }
}
impl From<usize> for Json {
    fn from(value: usize) -> Self {
        Self::Value(value.into())
    }
}
impl From<Vec<Json>> for Json {
    fn from(value: Vec<Json>) -> Self {
        Self::Array(value)
    }
}
macro_rules! object {
    ($($key:expr => $value:expr),* $(,)?) => {
        $crate::fixture::ordered::Json::Object(vec![$(($key.to_string(), $crate::fixture::ordered::Json::from($value))),*])
    };
}
pub(crate) use object;
pub fn pretty(value: &Json) -> Vec<u8> {
    let mut bytes = serde_json::to_vec_pretty(value).expect("fixture JSON serializes");
    bytes.push(b'\n');
    bytes
}
pub fn canonical(value: &impl Serialize) -> Vec<u8> {
    // Workspace dependencies may enable preserve_order. Signing must still
    // sort every object, including objects nested inside arrays.
    let mut value = serde_json::to_value(value).expect("fixture JSON value");
    value.sort_all_objects();
    serde_json::to_vec(&value).expect("fixture canonical JSON")
}
