///|
pub enum TScalarStyle {
  /// A YAML plain scalar.
  Plain
  /// A YAML single quoted scalar.
  SingleQuoted
  /// A YAML double quoted scalar.
  DoubleQuoted
  /// A YAML literal block (`|` block).
  Literal
  /// A YAML folded block (`>` block).
  Folded
} derive(Eq, Debug)

///|
pub extend TScalarStyle with Eq::{not_equal, equal}

///|
pub extend TScalarStyle with @moonbitlang/core/debug.Debug::{to_repr}
