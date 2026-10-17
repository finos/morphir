///|
/// One file of a project, with its path relative to the project root (for example `src/Shop/Orders/Api.elm`).
pub(all) struct ProjectFile {
  path : @ids.SourcePath
  content : String
} derive(Eq, Debug)

///|
/// How many files a language's project holds in the workbench. Per-file languages hold one
/// (`morphir-ukvn.5.22.14`).
pub(all) enum Layout {
  OneFile
  ManyFiles
} derive(Eq, Debug)

///|
/// The file rules of a language, from the catalog: its extensions and its layout.
pub(all) struct FileRules {
  extensions : Array[@ids.FileExtension]
  layout : Layout
}

///|
/// A refused edit: a code and a message for the person.
pub(all) suberror ProjectError {
  ProjectError(String, String)
}

///|
/// The open project of one language. `name` keeps the configuration spelling; `active` is the file in the editor.
pub(all) struct Project {
  name : @ids.SourcePackageName
  language : @ids.LanguageId
  provider : @ids.ProviderId?
  profile : @ids.ProfileId?
  files : Array[ProjectFile]
  exposed : Array[@ids.SourceModuleName]
  active : @ids.SourcePath
} derive(Eq, Debug)

///|
pub fn Project::single(
  language : @ids.LanguageId,
  name : @ids.SourcePackageName,
  path : @ids.SourcePath,
  content : String,
  provider~ : @ids.ProviderId? = None,
  profile~ : @ids.ProfileId? = None,
  exposed~ : Array[@ids.SourceModuleName] = [],
) -> Project {
  {
    name,
    language,
    provider,
    profile,
    files: [{ path, content, }],
    exposed,
    active: path,
  }
}

///|
pub fn Project::active_file(self : Project) -> ProjectFile {
  match self.files.search_by(f => f.path == self.active) {
    Some(i) => self.files[i]
    None => self.files[0]
  }
}

///|
/// The module name of a source file: the path under `src/` without its extension, with `.` between segments.
pub fn module_of(path : @ids.SourcePath) -> String? {
  let text = path.to_string()
  guard text.strip_prefix("src/") is Some(rest) else { return None }
  let rest = rest.to_owned()
  guard rest.rev_find(".") is Some(dot) else { return None }
  Some(rest.unsafe_substring(start=0, end=dot).replace_all(old="/", new="."))
}

///|
/// The module of `path` relative to the package: `src/Shop/Orders/Api.elm` in `Shop.Orders` gives `Api`.
fn Project::relative_module(self : Project, path : @ids.SourcePath) -> String? {
  guard module_of(path) is Some(full) else { return None }
  let prefix = self.name.to_string().replace_all(old="/", new=".") + "."
  match full.strip_prefix(prefix) {
    Some(rest) => Some(rest.to_owned())
    None => Some(full)
  }
}

///|
pub fn Project::modules(self : Project) -> Array[(@ids.SourceModuleName, Bool)] {
  self.files.filter_map(file => {
    match self.relative_module(file.path) {
      Some(text) =>
        try {
          let m = @ids.SourceModuleName::parse(text)
          Some((m, self.exposed.contains(m)))
        } catch {
          _ => None
        }
      None => None
    }
  })
}

///|
pub fn FileRules::add_reason(self : FileRules) -> String? {
  match self.layout {
    OneFile =>
      Some(
        "This language holds one file in the workbench; projects of several files are planned (morphir-ukvn.5.22.14)",
      )
    ManyFiles => None
  }
}

///|
fn Project::new_path(
  self : Project,
  rules : FileRules,
  text : String,
) -> @ids.SourcePath raise ProjectError {
  let path = @ids.SourcePath::parse(text) catch {
    _ =>
      raise ProjectError(
        "workbench.invalid_path",
        "Use a relative path with / between folders: " + text,
      )
  }
  if !text.has_prefix("src/") {
    raise ProjectError(
      "workbench.outside_source",
      "Put source files under src/: " + text,
    )
  }
  if !rules.extensions.iter().any(e => text.has_suffix(e.to_string())) {
    raise ProjectError(
      "workbench.wrong_extension",
      "Use one of " +
      rules.extensions.map(e => e.to_string()).join(", ") +
      ": " +
      text,
    )
  }
  if self.files.iter().any(f => f.path == path) {
    raise ProjectError(
      "workbench.duplicate_path",
      "A file with this path exists: " + text,
    )
  }
  path
}

///|
/// A new file is empty, except that an Elm file starts with its module header.
fn Project::starter(self : Project, path : @ids.SourcePath) -> String {
  if self.language.to_string() == "elm" && module_of(path) is Some(name) {
    "module " + name + " exposing (..)\n\n"
  } else {
    ""
  }
}

///|
pub fn Project::add_file(
  self : Project,
  rules : FileRules,
  path : String,
) -> Project raise ProjectError {
  if rules.add_reason() is Some(reason) {
    raise ProjectError("workbench.one_file_language", reason)
  }
  let path = self.new_path(rules, path)
  {
    ..self,
    files: self.files + [{ path, content: self.starter(path), }],
    active: path,
  }
}

///|
pub fn Project::rename_file(
  self : Project,
  rules : FileRules,
  from : @ids.SourcePath,
  to : String,
) -> Project raise ProjectError {
  guard self.files.search_by(f => f.path == from) is Some(index) else {
    raise ProjectError(
      "workbench.missing_file",
      "No file has this path: " + from.to_string(),
    )
  }
  let path = self.new_path(rules, to)
  let files = self.files.copy()
  files[index] = { ..files[index], path, }
  let exposed = match (self.relative_module(from), self.relative_module(path)) {
    (Some(old), Some(new)) =>
      self.exposed.filter_map(m => {
        if m.to_string() != old {
          Some(m)
        } else {
          Some(@ids.SourceModuleName::parse(new)) catch {
            _ => None
          }
        }
      })
    (Some(old), None) => self.exposed.filter(m => m.to_string() != old)
    _ => self.exposed
  }
  {
    ..self,
    files,
    exposed,
    active: if self.active == from {
      path
    } else {
      self.active
    },
  }
}

///|
pub fn Project::delete_file(
  self : Project,
  path : @ids.SourcePath,
) -> Project raise ProjectError {
  guard self.files.iter().any(f => f.path == path) else {
    raise ProjectError(
      "workbench.missing_file",
      "No file has this path: " + path.to_string(),
    )
  }
  if self.files.length() == 1 {
    raise ProjectError(
      "workbench.last_file", "A project keeps at least one file",
    )
  }
  let files = self.files.filter(f => f.path != path)
  let exposed = match self.relative_module(path) {
    Some(gone) => self.exposed.filter(m => m.to_string() != gone)
    None => self.exposed
  }
  {
    ..self,
    files,
    exposed,
    active: if self.active == path {
      files[0].path
    } else {
      self.active
    },
  }
}

///|
/// The module of a source file in this package and whether the package exposes it; `None` for a path that names
/// no module.
pub fn Project::file_module(
  self : Project,
  path : @ids.SourcePath,
) -> (@ids.SourceModuleName, Bool)? {
  guard self.relative_module(path) is Some(text) else { return None }
  let module_name = @ids.SourceModuleName::parse(text) catch {
    _ => return None
  }
  Some((module_name, self.exposed.contains(module_name)))
}

///|
/// The files inside the folder `folder`, at any depth.
fn Project::files_in(
  self : Project,
  folder : @ids.SourcePath,
) -> Array[@ids.SourcePath] {
  let prefix = folder.to_string() + "/"
  self.files.filter(f => f.path.to_string().has_prefix(prefix)).map(f => f.path)
}

///|
/// Moves every file of the folder `from` to the folder `to`. Each move follows the rules of `rename_file`; one
/// refusal refuses the whole move.
pub fn Project::rename_folder(
  self : Project,
  rules : FileRules,
  from : @ids.SourcePath,
  to : String,
) -> Project raise ProjectError {
  let inside = self.files_in(from)
  if inside.is_empty() {
    raise ProjectError(
      "workbench.missing_folder",
      "No folder has this path: " + from.to_string(),
    )
  }
  if to == from.to_string() {
    return self
  }
  ignore(
    @ids.SourcePath::parse(to) catch {
      _ =>
        raise ProjectError(
          "workbench.invalid_path",
          "Use a relative path with / between folders: " + to,
        )
    },
  )
  let prefix = from.to_string().length()
  inside.fold(init=self, (project, path) => {
    let text = path.to_string()
    project.rename_file(
      rules,
      path,
      to + text.unsafe_substring(start=prefix, end=text.length()),
    )
  })
}

///|
/// Deletes every file of the folder `folder`. A project keeps at least one file.
pub fn Project::delete_folder(
  self : Project,
  folder : @ids.SourcePath,
) -> Project raise ProjectError {
  let inside = self.files_in(folder)
  if inside.is_empty() {
    raise ProjectError(
      "workbench.missing_folder",
      "No folder has this path: " + folder.to_string(),
    )
  }
  if inside.length() == self.files.length() {
    raise ProjectError(
      "workbench.last_file", "A project keeps at least one file",
    )
  }
  inside.fold(init=self, (project, path) => project.delete_file(path))
}

///|
pub fn Project::set_content(
  self : Project,
  path : @ids.SourcePath,
  content : String,
) -> Project {
  {
    ..self,
    files: self.files.map(f => {
      if f.path == path {
        { ..f, content, }
      } else {
        f
      }
    }),
  }
}

///|
pub fn Project::set_active(
  self : Project,
  path : @ids.SourcePath,
) -> Project raise ProjectError {
  guard self.files.iter().any(f => f.path == path) else {
    raise ProjectError(
      "workbench.missing_file",
      "No file has this path: " + path.to_string(),
    )
  }
  { ..self, active: path, }
}

///|
/// The package name of `text` when it holds letters, digits, `_`, `.`, `/` and `-` only; `None` otherwise.
fn safe_package_name(text : String) -> @ids.SourcePackageName? {
  let safe = text != "" &&
    text
    .to_array()
    .all(c => {
      (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '.' ||
      c == '/' ||
      c == '-'
    })
  if safe {
    Some(@ids.SourcePackageName::parse(text)) catch {
      _ => None
    }
  } else {
    None
  }
}

///|
/// A package name with letters, digits, `_`, `.`, `/` and `-` only, as the worker accepts.
pub fn Project::set_name(
  self : Project,
  text : String,
) -> Project raise ProjectError {
  let name = safe_package_name(text)
  match name {
    Some(name) => {
      let exposed_paths = self.files
        .filter(f => {
          match self.relative_module(f.path) {
            Some(text) => self.exposed.iter().any(m => m.to_string() == text)
            None => false
          }
        })
        .map(f => f.path)
      let renamed = { ..self, name, }
      let exposed = exposed_paths.filter_map(p => {
        match renamed.relative_module(p) {
          Some(text) =>
            Some(@ids.SourceModuleName::parse(text)) catch {
              _ => None
            }
          None => None
        }
      })
      { ..renamed, exposed, }
    }
    None =>
      raise ProjectError(
        "workbench.invalid_package",
        "Use letters, digits, _, ., / and - in the package name: " + text,
      )
  }
}

///|
/// Exposure belongs to files: a module that no file has is ignored.
pub fn Project::set_exposed(
  self : Project,
  module_name : @ids.SourceModuleName,
  exposed : Bool,
) -> Project {
  guard self.modules().iter().any(m => m.0 == module_name) else { return self }
  let others = self.exposed.filter(m => m != module_name)
  { ..self, exposed: if exposed { others + [module_name] } else { others }, }
}

///|
pub extend ProjectFile with Eq::{not_equal, equal}

///|
pub extend ProjectFile with @debug.Debug::{to_repr}

///|
pub extend Layout with Eq::{not_equal, equal}

///|
pub extend Layout with @debug.Debug::{to_repr}

///|
pub extend Project with Eq::{not_equal, equal}

///|
pub extend Project with @debug.Debug::{to_repr}
