//! A small path-tracking reader over parsed JSON values.
//!
//! Every document is parsed at its boundary into domain types. The reader
//! never fails on an unknown member: must-ignore is the default, and the
//! envelope check has already refused unknown critical members.

use crate::diagnostic::{Code, Diagnostic, Result};
use serde_json::{Map, Value};

/// A value and the member path that reached it.
#[derive(Clone, Copy)]
pub(crate) struct Node<'a> {
    value: &'a Value,
    path: &'a str,
}

/// An object and its member path.
pub(crate) struct Obj<'a> {
    map: &'a Map<String, Value>,
    path: String,
}

/// Parse a JSON document, refusing an object that repeats a member name.
/// `serde_json` keeps the last of two repeated members silently, so the
/// value is built by a visitor that sees every name. A byte order mark is
/// not JSON and is refused like any other syntax error.
pub(crate) fn parse_json(bytes: &[u8]) -> Result<Value> {
    use serde::Deserializer as _;
    let mut deserializer = serde_json::Deserializer::from_slice(bytes);
    let value = deserializer
        .deserialize_any(StrictVisitor)
        .and_then(|value| deserializer.end().map(|()| value))
        .map_err(|error| {
            Diagnostic::new(Code::InvalidDocument, "", format!("not JSON: {error}"))
        })?;
    Ok(value)
}

struct StrictValue(Value);

impl<'de> serde::Deserialize<'de> for StrictValue {
    fn deserialize<D: serde::Deserializer<'de>>(
        deserializer: D,
    ) -> std::result::Result<Self, D::Error> {
        deserializer.deserialize_any(StrictVisitor).map(StrictValue)
    }
}

struct StrictVisitor;

impl<'de> serde::de::Visitor<'de> for StrictVisitor {
    type Value = Value;

    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("a JSON value")
    }
    fn visit_bool<E>(self, value: bool) -> std::result::Result<Value, E> {
        Ok(Value::Bool(value))
    }
    fn visit_i64<E>(self, value: i64) -> std::result::Result<Value, E> {
        Ok(Value::from(value))
    }
    fn visit_u64<E>(self, value: u64) -> std::result::Result<Value, E> {
        Ok(Value::from(value))
    }
    fn visit_f64<E>(self, value: f64) -> std::result::Result<Value, E> {
        Ok(serde_json::Number::from_f64(value).map_or(Value::Null, Value::Number))
    }
    fn visit_str<E>(self, value: &str) -> std::result::Result<Value, E> {
        Ok(Value::String(value.to_owned()))
    }
    fn visit_string<E>(self, value: String) -> std::result::Result<Value, E> {
        Ok(Value::String(value))
    }
    fn visit_unit<E>(self) -> std::result::Result<Value, E> {
        Ok(Value::Null)
    }
    fn visit_seq<A: serde::de::SeqAccess<'de>>(
        self,
        mut items: A,
    ) -> std::result::Result<Value, A::Error> {
        let mut values = Vec::new();
        while let Some(StrictValue(value)) = items.next_element()? {
            values.push(value);
        }
        Ok(Value::Array(values))
    }
    fn visit_map<A: serde::de::MapAccess<'de>>(
        self,
        mut members: A,
    ) -> std::result::Result<Value, A::Error> {
        let mut map = Map::new();
        while let Some(name) = members.next_key::<String>()? {
            if map.contains_key(&name) {
                return Err(serde::de::Error::custom(format!(
                    "the member name '{name}' is repeated"
                )));
            }
            let StrictValue(value) = members.next_value()?;
            map.insert(name, value);
        }
        Ok(Value::Object(map))
    }
}

pub(crate) fn join(path: &str, key: &str) -> String {
    if path.is_empty() {
        key.to_owned()
    } else {
        format!("{path}.{key}")
    }
}

pub(crate) fn index(path: &str, position: usize) -> String {
    format!("{path}[{position}]")
}

fn type_error(path: &str, expected: &str) -> Diagnostic {
    Diagnostic::new(Code::InvalidDocument, path, format!("expected {expected}"))
}

impl<'a> Node<'a> {
    pub(crate) fn root(value: &'a Value) -> Self {
        Self { value, path: "" }
    }

    pub(crate) fn value(&self) -> &'a Value {
        self.value
    }

    pub(crate) fn path(&self) -> &str {
        self.path
    }

    pub(crate) fn object(&self) -> Result<Obj<'a>> {
        self.value
            .as_object()
            .map(|map| Obj {
                map,
                path: self.path.to_owned(),
            })
            .ok_or_else(|| type_error(self.path, "an object"))
    }

    pub(crate) fn str(&self) -> Result<&'a str> {
        self.value
            .as_str()
            .ok_or_else(|| type_error(self.path, "a string"))
    }

    /// A non-negative integer, at most 2^53 - 1; a larger one is
    /// `invalid_value`.
    pub(crate) fn u64(&self) -> Result<u64> {
        let integer = self
            .value
            .as_u64()
            .ok_or_else(|| type_error(self.path, "a non-negative integer"))?;
        if integer > crate::ids::MAX_INTEGER {
            return Err(Diagnostic::new(
                Code::InvalidValue,
                self.path,
                format!("{integer} is past the integer bound 2^53 - 1"),
            ));
        }
        Ok(integer)
    }

    /// Parse a string with a validated constructor, reporting `code` on refusal.
    pub(crate) fn parse<T>(
        &self,
        code: Code,
        parse: impl FnOnce(&str) -> std::result::Result<T, String>,
    ) -> Result<T> {
        let text = self.str()?;
        parse(text).map_err(|message| Diagnostic::new(code, self.path, message))
    }

    /// Parse a string with a constructor that chooses its own refusal code.
    pub(crate) fn parse_coded<T>(
        &self,
        parse: impl FnOnce(&str) -> std::result::Result<T, (Code, String)>,
    ) -> Result<T> {
        let text = self.str()?;
        parse(text).map_err(|(code, message)| Diagnostic::new(code, self.path, message))
    }

    /// Read a string that names one of `cases`.
    pub(crate) fn case<T: Copy>(&self, cases: &[(&'static str, T)]) -> Result<T> {
        let tag = self.str()?;
        cases
            .iter()
            .find(|(name, _)| *name == tag)
            .map(|(_, value)| *value)
            .ok_or_else(|| {
                Diagnostic::new(
                    Code::UnsupportedCase,
                    self.path,
                    format!(
                        "'{tag}' is not one of {}",
                        cases
                            .iter()
                            .map(|(name, _)| *name)
                            .collect::<Vec<_>>()
                            .join(", ")
                    ),
                )
            })
    }
    /// Read every element of an array with its indexed path.
    pub(crate) fn array<T>(&self, mut read: impl FnMut(Node<'_>) -> Result<T>) -> Result<Vec<T>> {
        let values = self
            .value
            .as_array()
            .ok_or_else(|| type_error(self.path, "an array"))?;
        values
            .iter()
            .enumerate()
            .map(|(position, value)| {
                let path = index(self.path, position);
                read(Node { value, path: &path })
            })
            .collect()
    }
}

impl<'a> Obj<'a> {
    pub(crate) fn path(&self) -> &str {
        &self.path
    }

    pub(crate) fn member_path(&self, key: &str) -> String {
        join(&self.path, key)
    }

    pub(crate) fn has(&self, key: &str) -> bool {
        self.map.contains_key(key)
    }

    /// Visit a required member.
    pub(crate) fn req<T>(&self, key: &str, read: impl FnOnce(Node<'_>) -> Result<T>) -> Result<T> {
        let path = self.member_path(key);
        let value = self.map.get(key).ok_or_else(|| {
            Diagnostic::new(
                Code::InvalidDocument,
                &path,
                format!("required member '{key}' is absent"),
            )
        })?;
        read(Node { value, path: &path })
    }

    /// Visit an optional member.
    pub(crate) fn opt<T>(
        &self,
        key: &str,
        read: impl FnOnce(Node<'_>) -> Result<T>,
    ) -> Result<Option<T>> {
        let path = self.member_path(key);
        self.map
            .get(key)
            .map(|value| read(Node { value, path: &path }))
            .transpose()
    }

    pub(crate) fn str(&self, key: &str) -> Result<&'a str> {
        let path = self.member_path(key);
        let value = self.map.get(key).ok_or_else(|| {
            Diagnostic::new(
                Code::InvalidDocument,
                &path,
                format!("required member '{key}' is absent"),
            )
        })?;
        value.as_str().ok_or_else(|| type_error(&path, "a string"))
    }

    /// Read a tagged member. The tag must be a string naming one of `cases`;
    /// any other tag is `unsupported_case`. There is no default case.
    pub(crate) fn case<T: Copy>(&self, key: &str, cases: &[(&'static str, T)]) -> Result<T> {
        let path = self.member_path(key);
        let value = self.map.get(key).ok_or_else(|| {
            Diagnostic::new(
                Code::InvalidDocument,
                &path,
                format!("required member '{key}' is absent"),
            )
        })?;
        Node { value, path: &path }.case(cases)
    }
    /// Visit every entry of a map-valued object with its keyed path.
    ///
    /// The visiting order does not depend on the order of the document's
    /// members. Every key is parsed first, and the first invalid key in UTF-8
    /// byte order is refused. The entries are then read in key order, which
    /// for platform keys is the order of the platform table.
    pub(crate) fn map<K: Ord, T>(
        &self,
        mut key: impl FnMut(&str) -> std::result::Result<K, String>,
        mut read: impl FnMut(&K, Node<'_>) -> Result<T>,
    ) -> Result<Vec<(K, T)>> {
        let mut names = self.map.iter().collect::<Vec<_>>();
        names.sort_by(|(left, _), (right, _)| left.as_bytes().cmp(right.as_bytes()));
        let mut entries = names
            .into_iter()
            .map(|(name, value)| {
                key(name)
                    .map(|parsed| (parsed, name, value))
                    .map_err(|message| {
                        Diagnostic::new(Code::InvalidValue, self.member_path(name), message)
                    })
            })
            .collect::<Result<Vec<_>>>()?;
        entries.sort_by(|(left, _, _), (right, _, _)| left.cmp(right));
        entries
            .into_iter()
            .map(|(parsed, name, value)| {
                let path = self.member_path(name);
                let item = read(&parsed, Node { value, path: &path })?;
                Ok((parsed, item))
            })
            .collect()
    }
}

/// Refuse a member that contradicts another member.
pub(crate) fn inconsistent(path: impl Into<String>, message: impl Into<String>) -> Diagnostic {
    Diagnostic::new(Code::InconsistentDocument, path, message)
}

/// Member names that carry credentials, compared ASCII case-insensitively.
pub(crate) const CREDENTIAL_MEMBERS: &[&str] = &[
    "password",
    "passwd",
    "secret",
    "token",
    "apikey",
    "api-key",
    "api_key",
    "authorization",
    "credential",
    "credentials",
    "cookie",
];

/// Refuse a credential-shaped member at any depth, including inside members
/// a reader otherwise ignores. The scan is depth first; an object's members
/// are visited in UTF-8 byte order of their names and array elements in index
/// order, so the reported member does not depend on member order.
pub(crate) fn refuse_credentials(value: &Value, path: &str) -> Result<()> {
    match value {
        Value::Object(map) => {
            let mut members = map.iter().collect::<Vec<_>>();
            members.sort_by(|(left, _), (right, _)| left.as_bytes().cmp(right.as_bytes()));
            members.into_iter().try_for_each(|(key, value)| {
                let member = join(path, key);
                if CREDENTIAL_MEMBERS
                    .iter()
                    .any(|name| name.eq_ignore_ascii_case(key))
                {
                    Err(Diagnostic::new(
                        Code::CredentialInDocument,
                        member,
                        "toolchain documents never carry credentials",
                    ))
                } else {
                    refuse_credentials(value, &member)
                }
            })
        }
        Value::Array(values) => values
            .iter()
            .enumerate()
            .try_for_each(|(position, value)| refuse_credentials(value, &index(path, position))),
        _ => Ok(()),
    }
}
