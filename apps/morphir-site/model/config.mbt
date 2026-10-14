///|
pub(all) struct SiteConfig {
  title : String
  description : String
  base_path : String
  site_url : String
  repo_url : String
  packages : Array[String]
} derive(Eq, Debug)

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
  if problems.length() > 0 {
    raise Invalid(problems)
  }
  { title, description, base_path, site_url, repo_url, packages, }
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
