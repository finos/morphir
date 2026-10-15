///|
/// One lowering problem: (code, message, range).
pub(all) suberror LowerError {
  LowerError(String, String, @ast.Range?)
} derive(Eq, Debug)

///|
pub extend LowerError with Eq::{equal, not_equal}

///|
pub extend LowerError with @debug.Debug::{to_repr}
