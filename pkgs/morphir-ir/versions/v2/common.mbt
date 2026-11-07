///|
pub using @common {
  type Name,
  type NameSegment,
  type NameError,
  type Path,
  type PackageName,
  type ModuleName,
  type FQName,
  type Access,
  type AccessControlled,
}

///|
/// Elm documentation defaults to the empty string when its wrapper is absent.
#derive(Eq, Debug)
pub(all) struct Documented[A] {
  doc : String
  value : A
}

///|
pub extend Documented with Eq::{equal, not_equal}

///|
pub extend Documented with @debug.Debug::{to_repr}
