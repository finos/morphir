///|
#derive(Eq, Debug)
pub struct Tag {
  /// Handle of the tag (`!` included).
  handle : String
  /// The suffix of the tag.
  suffix : String
}

///|
pub extend Tag with Eq::{not_equal, equal}

///|
pub extend Tag with @moonbitlang/core/debug.Debug::{to_repr}
