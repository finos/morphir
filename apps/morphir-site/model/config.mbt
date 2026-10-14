///|
pub(all) struct SiteConfig {
  title : String
  description : String
  base_path : String
  site_url : String
  repo_url : String
  packages : Array[String]
  /// Docs sidebar groups. `None` sorts the sidebar by `order` and title.
  nav : Array[NavGroup]?
} derive(Eq, Debug)

///|
/// One labelled group of the docs sidebar. An item is a top-level page (`NAME.md` or
/// `NAME.html`) or directory (`NAME/`) below `docs/`, or a glob of one: `*` and `?`
/// match any characters and one character, but never `/`.
pub(all) struct NavGroup {
  group : String
  items : Array[String]
} derive(Eq, Debug)

///|
pub extend NavGroup with Eq::{equal, not_equal}

///|
pub extend NavGroup with @debug.Debug::{to_repr}

///|
pub extend SiteConfig with Eq::{equal, not_equal}

///|
pub extend SiteConfig with @debug.Debug::{to_repr}

///|
/// Parse `site/site.json`. Every problem is reported, not only the first.
pub fn SiteConfig::parse(
  file : String,
  text : String,
) -> SiteConfig raise Invalid {
  let json = @json.parse(text) catch {
    error => raise Invalid([problem(file, "not valid JSON: \{error}")])
  }
  guard json is Object(fields) else {
    raise Invalid([problem(file, "must be a JSON object")])
  }
  let problems = []
  let text_field = fn(key : String) -> String {
    match fields.get(key) {
      Some(String(value)) => value
      _ => {
        problems.push(problem(file, "missing string field `\{key}`"))
        ""
      }
    }
  }
  let title = text_field("title")
  let description = text_field("description")
  let base_path = text_field("base_path")
  let site_url = text_field("site_url")
  let repo_url = text_field("repo_url")
  let packages = match fields.get("packages") {
    Some(Array(items)) =>
      items.filter_map(item => {
        if item is String(name) {
          Some(name)
        } else {
          None
        }
      })
    _ => []
  }
  if base_path != "" &&
    !(base_path.has_prefix("/") && base_path.has_suffix("/")) {
    problems.push(problem(file, "`base_path` must start and end with `/`"))
  }
  if site_url != "" && !site_url.has_suffix("/") {
    problems.push(problem(file, "`site_url` must end with `/`"))
  }
  let nav = match fields.get("nav") {
    None => None
    Some(value) => Some(parse_nav(file, value, problems))
  }
  if problems.length() > 0 {
    raise Invalid(problems)
  }
  { title, description, base_path, site_url, repo_url, packages, nav, }
}

///|
/// A top-level page (`NAME.md` or `NAME.html`) or directory (`NAME/`), where `NAME`
/// has no `/`.
fn is_top_level_item(item : String) -> Bool {
  let name = if item.has_suffix("/") {
    item[:item.length() - 1].to_owned()
  } else if item.has_suffix(".md") {
    item[:item.length() - 3].to_owned()
  } else if item.has_suffix(".html") {
    item[:item.length() - 5].to_owned()
  } else {
    return false
  }
  name != "" && !name.contains("/")
}

///|
fn parse_nav(
  file : String,
  value : Json,
  problems : Array[Problem],
) -> Array[NavGroup] {
  guard value is Array(entries) else {
    problems.push(problem(file, "`nav` must be an array of groups"))
    return []
  }
  let groups : Array[NavGroup] = []
  let seen : Array[String] = []
  for i, entry in entries {
    guard entry is Object(fields) else {
      problems.push(
        problem(
          file,
          "`nav` group \{i + 1} must be an object with `group` and `items`",
        ),
      )
      continue
    }
    let label = match fields.get("group") {
      Some(String(label)) if label != "" => label
      _ => {
        problems.push(
          problem(file, "`nav` group \{i + 1} needs a non-empty `group` label"),
        )
        ""
      }
    }
    let name = if label == "" { "\{i + 1}" } else { "`\{label}`" }
    let items : Array[String] = []
    match fields.get("items") {
      Some(Array(values)) => {
        if values.is_empty() {
          problems.push(problem(file, "`nav` group \{name} has no items"))
        }
        if values.iter().any(v => !(v is String(_))) {
          problems.push(
            problem(file, "`nav` group \{name}: every item must be a string"),
          )
        }
        for v in values {
          guard v is String(item) else { continue }
          if !is_top_level_item(item) {
            problems.push(
              problem(
                file,
                "`nav` item `\{item}` must be a top-level page (`NAME.md` or `NAME.html`) or directory (`NAME/`)",
              ),
            )
          } else if seen.contains(item) {
            problems.push(
              problem(file, "`nav` item `\{item}` is listed more than once"),
            )
          } else {
            seen.push(item)
            items.push(item)
          }
        }
      }
      _ =>
        problems.push(
          problem(file, "`nav` group \{name} needs an `items` array"),
        )
    }
    groups.push({ group: label, items, })
  }
  groups
}

///|
/// The link for a route, below the base path. `route` starts with `/`.
pub fn SiteConfig::href(self : SiteConfig, route : String) -> String {
  self.base_path + route[1:].to_owned()
}

///|
/// The absolute URL for a route, for the feed.
pub fn SiteConfig::absolute(self : SiteConfig, route : String) -> String {
  self.site_url + route[1:].to_owned()
}
