///|
pub(all) enum Section {
  Home
  Docs
  Blog
} derive(Eq, Debug)

///|
pub extend Section with Eq::{equal, not_equal}

///|
pub extend Section with @debug.Debug::{to_repr}

///|
pub(all) struct PostSummary {
  route : String
  title : String
  date : String
  authors : Array[String]
  summary : String
} derive(Eq, Debug)

///|
pub extend PostSummary with Eq::{equal, not_equal}

///|
pub extend PostSummary with @debug.Debug::{to_repr}

///|
/// One line of the docs sidebar. An empty `route` is a label without a page.
pub(all) struct NavItem {
  route : String
  title : String
  depth : Int
} derive(Eq, Debug)

///|
pub extend NavItem with Eq::{equal, not_equal}

///|
pub extend NavItem with @debug.Debug::{to_repr}
