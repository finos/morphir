///|
/// `node_path` identifies the IR node: a canonical FQName, followed by `/`-separated steps.
#derive(Eq, Debug)
pub(all) struct Problem {
  code : String
  node_path : String
  detail : String
}

///|
pub extend Problem with Eq::{equal, not_equal}

///|
pub extend Problem with @debug.Debug::{to_repr}

///|
#derive(Eq, Debug)
pub(all) suberror ElmGenerationError {
  Refused(Problem)
  Failed(Array[Problem])
}

///|
pub extend ElmGenerationError with Eq::{equal, not_equal}

///|
pub extend ElmGenerationError with @debug.Debug::{to_repr}

///|
fn[T] refuse(
  code : String,
  at : String,
  detail : String,
) -> T raise ElmGenerationError {
  raise Refused({ code: "elm." + code, node_path: at, detail, })
}
