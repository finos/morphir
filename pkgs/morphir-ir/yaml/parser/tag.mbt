///|
pub struct Tag {
  /// Handle of the tag (`!` included).
  handle : String
  /// The suffix of the tag.
  suffix : String
} derive(Eq, Debug)

///|
pub extend Tag with Eq::{not_equal, equal}

///|
pub extend Tag with @moonbitlang/core/debug.Debug::{to_repr}
