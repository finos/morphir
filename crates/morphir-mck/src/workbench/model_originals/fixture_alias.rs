//! Symbolic names in connected checker fixtures, never source paths, producer
//! identities or authority tokens. Membership remains a separate boundary.
use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct InvalidFixtureAlias;
impl fmt::Display for InvalidFixtureAlias {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("fixture alias must match [A-Za-z][A-Za-z0-9._-]{0,127}")
    }
}
impl std::error::Error for InvalidFixtureAlias {}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct FixtureAlias(String);
#[derive(Debug)]
pub(super) enum FixtureAliasCloneError {
    Allocation(std::collections::TryReserveError),
    ExcessCapacity,
}
impl serde::Serialize for FixtureAlias {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(self.as_str())
    }
}
impl FixtureAlias {
    pub fn new(text: &str) -> Result<Self, InvalidFixtureAlias> {
        if text.is_empty()
            || text.len() > 128
            || !text.as_bytes()[0].is_ascii_alphabetic()
            || !text
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-'))
        {
            return Err(InvalidFixtureAlias);
        }
        Ok(Self(text.to_owned()))
    }
    pub fn as_str(&self) -> &str {
        &self.0
    }
    /// Copy an already validated nominal alias after its caller has funded the
    /// exact requested string payload. Allocation failure retains the source.
    pub(super) fn try_clone(&self) -> Result<Self, FixtureAliasCloneError> {
        let mut text = String::new();
        text.try_reserve_exact(self.0.len())
            .map_err(FixtureAliasCloneError::Allocation)?;
        if text.capacity() != self.0.len() {
            return Err(FixtureAliasCloneError::ExcessCapacity);
        }
        text.push_str(&self.0);
        Ok(Self(text))
    }
}
