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
        let uuid = uuid::Uuid::parse_str(value.strip_prefix("op-")?).ok()?;
        Some(Self(format!("op-{uuid}")))
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

    #[test]
    fn parsed_operation_ids_use_the_canonical_logged_spelling() {
        let canonical = "op-123e4567-e89b-42d3-a456-426614174abc";
        let uppercase = "op-123E4567-E89B-42D3-A456-426614174ABC";

        assert_eq!(OperationId::parse(uppercase).unwrap().as_str(), canonical);
    }
}
