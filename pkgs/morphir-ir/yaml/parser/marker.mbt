///|
pub struct Marker {
  /// The index (in chars) in the input string.
  index : Int32
  /// The line (1-indexed).
  line : Int32
  /// The column (1-indexed).
  col : Int32
} derive(Debug, Eq)

///|
pub extend Marker with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Marker with Eq::{not_equal, equal}
