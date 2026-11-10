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

    pub(crate) fn u64(&self) -> Result<u64> {
        self.value
            .as_u64()
            .ok_or_else(|| type_error(self.path, "a non-negative integer"))
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
    pub(crate) fn map<K, T>(
        &self,
        mut key: impl FnMut(&str) -> std::result::Result<K, String>,
        mut read: impl FnMut(&K, Node<'_>) -> Result<T>,
    ) -> Result<Vec<(K, T)>> {
        self.map
            .iter()
            .map(|(name, value)| {
                let path = self.member_path(name);
                let parsed = key(name)
                    .map_err(|message| Diagnostic::new(Code::InvalidValue, &path, message))?;
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
/// a reader otherwise ignores.
pub(crate) fn refuse_credentials(value: &Value, path: &str) -> Result<()> {
    match value {
        Value::Object(map) => map.iter().try_for_each(|(key, value)| {
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
        }),
        Value::Array(values) => values
            .iter()
            .enumerate()
            .try_for_each(|(position, value)| refuse_credentials(value, &index(path, position))),
        _ => Ok(()),
    }
}
