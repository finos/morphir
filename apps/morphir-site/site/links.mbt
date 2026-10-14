///|
pub(all) struct LinkContext {
  config : @model.SiteConfig
  /// Repository path of each published page, to its route.
  routes : Map[String, String]
  /// Every repository file.
  files : Map[String, Bool]
  /// Every directory that holds a repository file.
  dirs : Map[String, Bool]
  /// Every route the generator writes.
  site_routes : Map[String, Bool]
}

///|
pub fn LinkContext::new(
  config : @model.SiteConfig,
  routes : Map[String, String],
  files : Array[String],
  site_routes : Array[String],
) -> LinkContext {
  let file_set : Map[String, Bool] = Map([])
  let dirs : Map[String, Bool] = Map([])
  for f in files {
    file_set.set(f, true)
    let mut dir = f
    while dir.rev_find("/") is Some(i) {
      dir = dir[:i].to_owned()
      dirs.set(dir, true)
    }
  }
  let route_set : Map[String, Bool] = Map([])
  for r in site_routes {
    route_set.set(r, true)
  }
  { config, routes, files: file_set, dirs, site_routes: route_set, }
}

///|
/// How one URL in a page is written.
pub(all) struct Resolution {
  url : String
  /// A `(route, anchor)` pair that must exist once all pages are known.
  anchor : (String, String)?
  /// A repository file to copy to the same path below the output directory.
  copy : String?
  problem : String?
}

///|
fn keep(url : String) -> Resolution {
  { url, anchor: None, copy: None, problem: None, }
}

///|
fn broken(url : String, message : String) -> Resolution {
  { url, anchor: None, copy: None, problem: Some(message), }
}

///|
/// Resolve `..`, `.` and empty segments. A path that leaves the root keeps its
/// leading `..`.
pub fn normalize(path : String) -> String {
  let parts : Array[String] = []
  for segment in path.split("/") {
    let s = segment.to_owned()
    if s == "" || s == "." {
      continue
    } else if s == ".." &&
      parts.length() > 0 &&
      parts[parts.length() - 1] != ".." {
      ignore(parts.pop())
    } else {
      parts.push(s)
    }
  }
  parts.join("/")
}

///|
fn split_anchor(url : String) -> (String, String) {
  match url.find("#") {
    Some(i) => (url[:i].to_owned(), url[i + 1:].to_owned())
    None => (url, "")
  }
}

///|
fn with_anchor(url : String, anchor : String) -> String {
  if anchor == "" {
    url
  } else {
    "\{url}#\{anchor}"
  }
}

///|
fn anchor_check(route : String, anchor : String) -> (String, String)? {
  if anchor == "" {
    None
  } else {
    Some((route, anchor))
  }
}

///|
let media_extensions : Array[String] = [
  ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp", ".avif", ".ico",
]

///|
/// Whether the path names an image file, which the site copies wherever it lives.
fn is_media(path : String) -> Bool {
  let lower = path.to_lower()
  media_extensions.iter().any(e => lower.has_suffix(e))
}

///|
/// Resolve one `href` or `src` value of the page whose repository path is `from`.
pub fn resolve(ctx : LinkContext, from : String, url : String) -> Resolution {
  if url == "" ||
    url.contains("://") ||
    url.has_prefix("mailto:") ||
    url.has_prefix("tel:") ||
    url.has_prefix("data:") {
    return keep(url)
  }
  let (path, anchor) = split_anchor(url)
  let config = ctx.config
  if path == "" {
    return match ctx.routes.get(from) {
      Some(route) => { ..keep(url), anchor: anchor_check(route, anchor), }
      None => keep(url)
    }
  }
  if path.has_prefix("/") {
    if ctx.site_routes.contains(path) {
      return {
        ..keep(with_anchor(config.href(path), anchor)),
        anchor: anchor_check(path, anchor),
      }
    }
    if path.has_prefix("/try/") || path.has_prefix("/assets/") {
      return keep(with_anchor(config.href(path), anchor))
    }
    return broken(url, "no page at site route `\{path}`")
  }
  let dir = match from.rev_find("/") {
    Some(i) => from[:i + 1].to_owned()
    None => ""
  }
  let target = normalize(dir + path)
  if target == ".." || target.has_prefix("../") {
    return broken(url, "link `\{url}` leaves the repository")
  }
  if ctx.routes.get(target) is Some(route) {
    return {
      ..keep(with_anchor(config.href(route), anchor)),
      anchor: anchor_check(route, anchor),
    }
  }
  if ctx.files.contains(target) {
    if target.has_prefix("docs/") || is_media(target) {
      return { ..keep(config.href("/" + target)), copy: Some(target), }
    }
    return keep(with_anchor("\{config.repo_url}/blob/main/\{target}", anchor))
  }
  if ctx.dirs.contains(target) {
    return keep("\{config.repo_url}/tree/main/\{target}")
  }
  broken(url, "broken link `\{url}`: `\{target}` does not exist")
}
