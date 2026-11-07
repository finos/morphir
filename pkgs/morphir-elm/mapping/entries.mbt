///|
/// `Function` and `Type` hold an Elm name, qualified or not, and an optional import line.
#derive(Eq, Debug)
pub(all) enum MappingEntry {
  Operator(String)
  Function(String, String?)
  Type(String, String?)
  Removed
}

///|
pub extend MappingEntry with Eq::{equal, not_equal}

///|
pub extend MappingEntry with @debug.Debug::{to_repr}

///|
/// Types and values have separate namespaces: `basics#never` is both a type and a function.
#derive(Eq, Debug)
pub(all) enum Namespace {
  TypeSpace
  ValueSpace
}

///|
pub extend Namespace with Eq::{equal, not_equal}

///|
pub extend Namespace with @debug.Debug::{to_repr}
