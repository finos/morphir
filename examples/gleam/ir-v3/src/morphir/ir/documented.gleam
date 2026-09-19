//// Documentation wrapper for the Morphir IR.
//// This module provides a type for attaching documentation strings to values,
//// enabling self-documenting IR representations.

/// A documented value containing both a documentation string and the value itself.
pub type Documented(a) {
  Documented(doc: String, value: a)
}
