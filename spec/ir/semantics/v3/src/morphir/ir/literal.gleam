//// Literal values for the Morphir IR.
//// This module defines the types for representing fixed/constant values
//// in the IR, such as booleans, numbers, strings, and characters.

/// A literal value representing a fixed/constant value in the IR.
pub type Literal {
  /// Boolean literal (True or False)
  BoolLiteral(value: Bool)
  /// Character literal (a single character)
  CharLiteral(value: String)
  /// String literal
  StringLiteral(value: String)
  /// Whole number (integer) literal
  WholeNumberLiteral(value: Int)
  /// Floating-point number literal
  FloatLiteral(value: Float)
  /// Decimal literal (stored as string for precision)
  /// Note: Gleam doesn't have a built-in Decimal type, so we use String
  DecimalLiteral(value: String)
}
