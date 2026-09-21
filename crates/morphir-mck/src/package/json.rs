//! Closed package fields and scalar validators.
pub(super) use crate::json::strict::{Document, parse};
use serde_json::{Map, Value};
pub(super) fn fields<'a>(
    value: &'a Value,
    required: &[&str],
    optional: &[&str],
) -> Result<&'a Map<String, Value>, String> {
    let object = value.as_object().ok_or("expected object")?;
    for key in required {
        if !object.contains_key(*key) {
            return Err(format!("missing field {key}"));
        }
    }
    for key in object.keys() {
        if !required.contains(&key.as_str()) && !optional.contains(&key.as_str()) {
            return Err(format!("unknown field {key}"));
        }
    }
    Ok(object)
}
pub(super) fn string(value: &Value) -> Result<&str, String> {
    value.as_str().ok_or_else(|| "expected string".into())
}
pub(super) fn nonempty(value: &Value) -> Result<&str, String> {
    let text = string(value)?;
    if text.is_empty() {
        Err("expected nonempty string".into())
    } else {
        Ok(text)
    }
}
pub(super) fn array(value: &Value) -> Result<&Vec<Value>, String> {
    value.as_array().ok_or_else(|| "expected array".into())
}
pub(super) fn hex(value: &Value) -> Result<&str, String> {
    let text = string(value)?;
    if text.len().is_multiple_of(2)
        && text
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        Ok(text)
    } else {
        Err("expected lowercase byte hex".into())
    }
}
pub(super) fn digest(value: &Value) -> Result<&str, String> {
    let text = string(value)?;
    if text
        .strip_prefix("sha256:")
        .is_some_and(crate::kit::hash::is_sha256_hex)
    {
        Ok(text)
    } else {
        Err("expected sha256 digest".into())
    }
}
