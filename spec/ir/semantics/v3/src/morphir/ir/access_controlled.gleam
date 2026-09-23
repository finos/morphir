//// Access control for the Morphir IR.
//// This module provides types for declaring access levels on types and values,
//// allowing modules to expose public interfaces while keeping implementations private.

/// Access level for types and values.
pub type Access {
  /// Publicly accessible to all modules.
  Public
  /// Only accessible within the same module.
  Private
}

/// A value with an associated access level.
pub type AccessControlled(a) {
  AccessControlled(access: Access, value: a)
}
