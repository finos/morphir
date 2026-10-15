///|
/// One resolution problem. `path` is the source path of the module; `range` is the place in that file.
pub(all) struct ResolveProblem {
  code : String
  message : String
  path : String
  range : @ast.Range?
} derive(Eq, Debug)

///|
pub extend ResolveProblem with Eq::{equal, not_equal}

///|
pub extend ResolveProblem with @debug.Debug::{to_repr}

///|
/// All the problems of one check, in source order.
pub(all) suberror ResolveFailed {
  ResolveFailed(Array[ResolveProblem])
} derive(Eq, Debug)

///|
pub extend ResolveFailed with Eq::{equal, not_equal}

///|
pub extend ResolveFailed with @debug.Debug::{to_repr}

///|
/// One name that does not resolve: (code, message). The caller adds the path and the range.
pub(all) suberror ResolveError {
  ResolveError(String, String)
} derive(Eq, Debug)

///|
pub extend ResolveError with Eq::{equal, not_equal}

///|
pub extend ResolveError with @debug.Debug::{to_repr}

///|
/// A resolved value name: a local binding, a top-level value or constructor, or the Elm `True` or `False` (the
/// SDK `Bool` is opaque, so morphir-elm writes them as a `BoolLiteral`).
pub(all) enum Resolved {
  Local(String)
  Global(@ir.FQName)
  BoolLiteral(Bool)
} derive(Eq, Debug)

///|
pub extend Resolved with Eq::{equal, not_equal}

///|
pub extend Resolved with @debug.Debug::{to_repr}
