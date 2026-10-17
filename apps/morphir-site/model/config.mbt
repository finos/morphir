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
  /// The sidebar order of listed packages' sub-package pages; empty when `site.json` has no `chapters`.
  chapters : Array[ChapterOrder]
} derive(Eq, Debug)

///|
/// The sub-package pages of one listed package, in sidebar order: each is a directory below the package, such as
/// `frontend`. A listed page takes its position as its `order`, before front matter.
pub(all) struct ChapterOrder {
  name : String
  chapters : Array[String]
} derive(Eq, Debug)

///|
pub extend ChapterOrder with Eq::{equal, not_equal}

///|
pub extend ChapterOrder with @debug.Debug::{to_repr}

///|
/// The `order` of the sub-package page `sub` of package `name` from `chapters`, counted from 1, or `None` when
/// `chapters` does not list it.
pub fn SiteConfig::chapter_order(
  self : SiteConfig,
  name : String,
  sub : String,
) -> Int32? {
  for entry in self.chapters {
    if entry.name == name {
      for i, chapter in entry.chapters {
        if chapter == sub {
          return Some(i + 1)
        }
      }
    }
  }
  None
}

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
  let chapters = match fields.get("chapters") {
    None => []
    Some(value) => parse_chapters(file, value, packages, problems)
  }
  if problems.length() > 0 {
    raise Invalid(problems)
  }
  {
    title,
    description,
    base_path,
    site_url,
    repo_url,
    packages,
    nav,
    chapters,
  }
}

///|
/// A sub-package path below a package: names separated by `/`, with no empty name.
fn is_sub_path(item : String) -> Bool {
  item != "" && item.split("/").all(part => part != "")
}

///|
fn parse_chapters(
  file : String,
  value : Json,
  packages : Array[String],
  problems : Array[Problem],
) -> Array[ChapterOrder] {
  guard value is Object(entries) else {
    problems.push(
      problem(
        file, "`chapters` must be an object from package names to arrays of sub-package paths",
      ),
    )
    return []
  }
  let orders : Array[ChapterOrder] = []
  for name, list in entries {
    if !packages.contains(name) {
      problems.push(
        problem(
          file,
          "`chapters` names package `\{name}`, which is not in `packages`",
        ),
      )
    }
    guard list is Array(values) else {
      problems.push(
        problem(
          file,
          "`chapters` of `\{name}` must be an array of sub-package paths",
        ),
      )
      continue
    }
    let chapters : Array[String] = []
    for v in values {
      guard v is String(item) && is_sub_path(item) else {
        problems.push(
          problem(
            file,
            "`chapters` of `\{name}`: every item must be a sub-package path such as `frontend`",
          ),
        )
        continue
      }
      if chapters.contains(item) {
        problems.push(
          problem(
            file,
            "`chapters` of `\{name}` lists `\{item}` more than once",
          ),
        )
      } else {
        chapters.push(item)
      }
    }
    orders.push({ name, chapters, })
  }
  orders
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
