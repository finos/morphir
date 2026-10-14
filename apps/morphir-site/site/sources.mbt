///|
pub(all) struct SourceFile {
  path : String
  text : String?
}

///|
pub(all) enum Kind {
  /// A file below `docs/`; the payload is the path below `docs/`.
  Doc(String)
  /// A file in `site/blog/`; the payload is the file name.
  Post(String)
  Landing
  /// A package README listed in `site.json`; the payload is the package name.
  Package(String)
  Forbidden
  Other
} derive(Eq, Debug)

///|
pub extend Kind with Eq::{equal, not_equal}

///|
pub extend Kind with @debug.Debug::{to_repr}

///|
fn is_content(path : String) -> Bool {
  (path.has_suffix(".md") || path.has_suffix(".html")) &&
  !path.has_suffix(".mbt.md")
}

///|
pub fn classify(path : String, config : @model.SiteConfig) -> Kind {
  if path.has_prefix("docs/superpowers/") {
    return Forbidden
  }
  if path.has_prefix("docs/") && is_content(path) {
    return Doc(path[5:].to_owned())
  }
  if path.has_prefix("site/blog/") &&
    is_content(path) &&
    !path[10:].contains("/") {
    return Post(path[10:].to_owned())
  }
  if path == "site/pages/index.md" || path == "site/pages/index.html" {
    return Landing
  }
  for name in config.packages {
    if path == "pkgs/\{name}/README.md" || path == "apps/\{name}/README.md" {
      return Package(name)
    }
  }
  Other
}

///|
/// Whether the generator must read this file's text.
pub fn needs_text(path : String, config : @model.SiteConfig) -> Bool {
  match classify(path, config) {
    Doc(_) | Post(_) | Landing | Package(_) => true
    Forbidden | Other => false
  }
}
