///|
pub(all) suberror InvalidInput {
  InvalidInput(String)
} derive(Debug)

///|
pub extend InvalidInput with @debug.Debug::{to_repr}

///|
/// M1 identities are opaque nonempty strings, not necessarily URIs.
pub struct Id(String) derive(Eq, Debug)

///|
pub fn Id::parse(value : String) -> Id raise InvalidInput {
  if value.is_empty() {
    raise InvalidInput("Identity must be nonempty")
  }
  Id(value)
}

///|
pub fn Id::value(self : Id) -> String {
  self.0
}

///|
/// Required descriptive text has no identity semantics.
pub struct NonemptyText(String) derive(Eq, Debug)

///|
pub fn NonemptyText::parse(value : String) -> NonemptyText raise InvalidInput {
  if value.is_empty() {
    raise InvalidInput("Text must be nonempty")
  }
  NonemptyText(value)
}

///|
pub fn NonemptyText::value(self : NonemptyText) -> String {
  self.0
}

///|
pub extend NonemptyText with Eq::{equal, not_equal}

///|
pub extend NonemptyText with @debug.Debug::{to_repr}

///|
pub extend Id with Eq::{equal, not_equal}

///|
pub extend Id with @debug.Debug::{to_repr}

///|
pub struct Revision(String) derive(Eq, Debug)

///|
pub fn Revision::parse(value : String) -> Revision raise InvalidInput {
  if value.is_empty() {
    raise InvalidInput("Revision must be nonempty")
  }
  Revision(value)
}

///|
pub fn Revision::value(self : Revision) -> String {
  self.0
}

///|
pub extend Revision with Eq::{equal, not_equal}

///|
pub extend Revision with @debug.Debug::{to_repr}

///|
/// Category IDs have a namespace and a nonempty local part. Notation is separate.
pub struct Category(String) derive(Eq, Debug)

///|
pub fn Category::parse(value : String) -> Category raise InvalidInput {
  let parts = value.split(":").to_array()
  if parts.length() < 2 || parts[0].is_empty() || parts[1].is_empty() {
    raise InvalidInput("Requirement category must be namespaced")
  }
  Category(value)
}

///|
pub fn Category::value(self : Category) -> String {
  self.0
}

///|
pub extend Category with Eq::{equal, not_equal}

///|
pub extend Category with @debug.Debug::{to_repr}

///|
pub(all) struct Snapshot {
  id : Id
  revision : Revision
} derive(Eq, Debug)

///|
pub extend Snapshot with Eq::{equal, not_equal}

///|
pub extend Snapshot with @debug.Debug::{to_repr}

///|
pub(all) struct ResolvedRef {
  model : Snapshot
  entity : Snapshot
} derive(Eq, Debug)

///|
pub extend ResolvedRef with Eq::{equal, not_equal}

///|
pub extend ResolvedRef with @debug.Debug::{to_repr}

///|
pub(all) struct SourceRef {
  source_id : Id
  anchor : Id
} derive(Eq, Debug)

///|
pub extend SourceRef with Eq::{equal, not_equal}

///|
pub extend SourceRef with @debug.Debug::{to_repr}
