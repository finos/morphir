//! Correlation identifiers shared by CLI operations and launched components.

use std::fmt;

/// Environment variable used to pass a parent operation to a child process.
pub const PARENT_OPERATION_ID_ENV: &str = "MORPHIR_PARENT_OPERATION_ID";

/// An opaque identifier for one user-requested Morphir operation.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct OperationId(String);

impl OperationId {
    /// Create a new identifier without encoding user, host, or command data.
    pub fn new() -> Self {
        Self(format!("op-{}", uuid::Uuid::new_v4()))
    }

    /// Return the identifier as a string slice for structured fields and child processes.
    pub fn as_str(&self) -> &str {
        &self.0
    }

    /// Parse an identifier previously reported by Morphir.
    pub fn parse(value: &str) -> Option<Self> {
        let uuid = value.strip_prefix("op-")?;
        uuid::Uuid::parse_str(uuid).ok()?;
        Some(Self(value.to_owned()))
    }
}

impl Default for OperationId {
    fn default() -> Self {
        Self::new()
    }
}

impl fmt::Display for OperationId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn operation_ids_are_opaque_unique_uuid_values() {
        let first = OperationId::new();
        let second = OperationId::new();

        assert_ne!(first, second);
        assert!(first.as_str().starts_with("op-"));
        uuid::Uuid::parse_str(first.as_str().trim_start_matches("op-")).unwrap();
        assert_eq!(OperationId::parse(first.as_str()), Some(first));
        assert!(OperationId::parse("bad-operation").is_none());
    }
}
