///|
/// One resolution problem. `path` is the source path of the module; `range` is the place in that file.
#derive(Eq, Debug)
pub(all) struct ResolveProblem {
  code : String
  message : String
  path : String
  range : @ast.Range?
}

///|
pub extend ResolveProblem with Eq::{equal, not_equal}

///|
pub extend ResolveProblem with @debug.Debug::{to_repr}

///|
/// All the problems of one check, in source order.
#derive(Eq, Debug)
pub(all) suberror ResolveFailed {
  ResolveFailed(Array[ResolveProblem])
}

///|
pub extend ResolveFailed with Eq::{equal, not_equal}

///|
pub extend ResolveFailed with @debug.Debug::{to_repr}

///|
/// One name that does not resolve: (code, message). The caller adds the path and the range.
#derive(Eq, Debug)
pub(all) suberror ResolveError {
  ResolveError(String, String)
}

///|
pub extend ResolveError with Eq::{equal, not_equal}

///|
pub extend ResolveError with @debug.Debug::{to_repr}

///|
/// A resolved value name: a local binding, a top-level value or constructor, or the Elm `True` or `False` (the
/// SDK `Bool` is opaque, so morphir-elm writes them as a `BoolLiteral`).
#derive(Eq, Debug)
pub(all) enum Resolved {
  Local(String)
  Global(@ir.FQName)
  BoolLiteral(Bool)
}

///|
pub extend Resolved with Eq::{equal, not_equal}

///|
pub extend Resolved with @debug.Debug::{to_repr}
