///|
/// One `.elm` source. `path` is relative to the source directory and uses `/`.
pub(all) struct ElmSource {
  path : String
  content : String
} derive(Eq, Debug)

///|
pub extend ElmSource with Eq::{equal, not_equal}

///|
pub extend ElmSource with @debug.Debug::{to_repr}

///|
/// One frontend problem. `path` is the source path relative to the source directory; `location` is the range
/// in that file when it is known.
pub(all) struct ElmProblem {
  code : String
  message : String
  path : String
  location : @ir.SourceLocation?
} derive(Eq, Debug)

///|
pub extend ElmProblem with Eq::{equal, not_equal}

///|
pub extend ElmProblem with @debug.Debug::{to_repr}

///|
/// The problems of the first pass that failed. The `elm.type` problems of the inference pass are in logical-path
/// order (`value:<package>:<module>#<name>…`), because `@typing.infer` sorts them; problems at one path keep their
/// order. The problems of every other pass are in source order.
pub(all) suberror ElmFailed {
  ElmFailed(Array[ElmProblem])
} derive(Eq, Debug)

///|
pub extend ElmFailed with Eq::{equal, not_equal}

///|
pub extend ElmFailed with @debug.Debug::{to_repr}

///|
pub fn location_of(range : @ast.Range) -> @ir.SourceLocation {
  {
    start_line: range.start.row,
    start_column: range.start.column,
    end_line: range.end.row,
    end_column: range.end.column,
  }
}

///|
fn problem(
  code : String,
  message : String,
  path : String,
  range : @ast.Range?,
) -> ElmProblem {
  { code, message, path, location: range.map(location_of), }
}

///|
fn fail_if_any(problems : Array[ElmProblem]) -> Unit raise ElmFailed {
  if !problems.is_empty() {
    raise ElmFailed(problems)
  }
}
