///|
/// One lowering problem: (code, message, range).
#derive(Eq, Debug)
pub(all) suberror LowerError {
  LowerError(String, String, @ast.Range?)
}

///|
pub extend LowerError with Eq::{equal, not_equal}

///|
pub extend LowerError with @debug.Debug::{to_repr}
