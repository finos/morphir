///|
#derive(Eq, Debug)
pub(all) enum Section {
  Home
  Docs
  Blog
}

///|
pub extend Section with Eq::{equal, not_equal}

///|
pub extend Section with @debug.Debug::{to_repr}

///|
#derive(Eq, Debug)
pub(all) struct PostSummary {
  route : String
  title : String
  date : String
  authors : Array[String]
  summary : String
}

///|
pub extend PostSummary with Eq::{equal, not_equal}

///|
pub extend PostSummary with @debug.Debug::{to_repr}

///|
/// One line of the docs sidebar. An empty `route` is a label without a page.
#derive(Eq, Debug)
pub(all) struct NavItem {
  route : String
  title : String
  depth : Int32
}

///|
pub extend NavItem with Eq::{equal, not_equal}

///|
pub extend NavItem with @debug.Debug::{to_repr}

///|
/// One link of the "On this page" rail. `depth` is 0 for `h2` and 1 for `h3`.
#derive(Eq, Debug)
pub(all) struct TocEntry {
  id : String
  text : String
  depth : Int32
}

///|
pub extend TocEntry with Eq::{equal, not_equal}

///|
pub extend TocEntry with @debug.Debug::{to_repr}
