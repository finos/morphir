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
  /// A sub-package README of a listed package: the package and the directory below it.
  PackagePart(String, String)
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
/// Directories whose READMEs are never package pages.
let excluded_dirs : Array[String] = [
  "fixtures", "_build", ".mooncakes", "node_modules", "target",
]

///|
/// The directory of a README.md or README.mbt.md, or `None`.
fn readme_dir(path : String) -> String? {
  for name in ["/README.md", "/README.mbt.md"] {
    if path.has_suffix(name) {
      return Some(path[:path.length() - name.length()].to_owned())
    }
  }
  None
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
  if readme_dir(path) is Some(dir) {
    for name in config.packages {
      for root in ["pkgs/\{name}", "apps/\{name}"] {
        if dir == root {
          return Package(name)
        }
        if dir.has_prefix(root + "/") {
          let sub = dir[root.length() + 1:].to_owned()
          if sub.split("/").any(part => excluded_dirs.contains(part.to_owned())) {
            return Other
          }
          return PackagePart(name, sub)
        }
      }
    }
  }
  Other
}

///|
/// Whether the generator must read this file's text.
pub fn needs_text(path : String, config : @model.SiteConfig) -> Bool {
  match classify(path, config) {
    Doc(_) | Post(_) | Landing | Package(_) | PackagePart(_, _) => true
    Forbidden | Other => false
  }
}
