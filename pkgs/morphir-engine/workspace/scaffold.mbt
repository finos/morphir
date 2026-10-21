///|
/// A canonical project root relative to the workspace. The empty path identifies the root project.
pub struct ProjectPath(String) derive(Eq, Compare, Hash, Debug)

///|
pub extend ProjectPath with Eq::{equal, not_equal}

///|
pub extend ProjectPath with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend ProjectPath with Hash::{hash, hash_combine}

///|
pub extend ProjectPath with @debug.Debug::{to_repr}

///|
pub fn ProjectPath::parse(path : String) -> ProjectPath raise {
  ProjectPath(normalize(path))
}

///|
pub impl Show for ProjectPath with fn output(self, logger) {
  logger.write_string(self.0)
}

///|
pub extend ProjectPath with Show::{to_string, output}

///|
pub(all) struct NewProject {
  name : @ids.SourcePackageName
  language : @ids.LanguageId?
  profile : @ids.ProfileId?
  source_directory : String
}

///|
/// A pure edit. Deletes identify subtrees, and are only included when explicitly requested.
pub(all) struct Edit {
  writes : Map[String, String]
  directories : Array[String]
  deletes : Array[String]
  warnings : Array[String]
}

///|
/// Infer directories from canonical file paths, for memory workspaces and browser imports.
pub fn Tree::from_files(files : Map[String, String]) -> Tree raise {
  let directories : Map[String, Bool] = Map::from_array([("", true)])
  for path, _ in files {
    if path == "" || normalize(path) != path {
      raise @config.Invalid("Expected a canonical file path: " + path)
    }
    let mut directory = parent(path)
    while directory != "" {
      if files.contains(directory) {
        raise @config.Invalid("File is also a directory: " + directory)
      }
      directories[directory] = true
      directory = parent(directory)
    }
  }
  let paths = directories.keys().collect()
  paths.sort()
  { files: files.copy(), directories: paths, }
}

///|
pub fn Edit::apply(self : Edit, tree : Tree) -> Tree raise {
  let deletes = self.deletes.map(normalize)
  if deletes.contains("") {
    raise @config.Invalid("Cannot delete the workspace root")
  }
  let files = tree.files.filter(fn(path, _) {
    !deletes.any(d => within(d, path))
  })
  for path, text in self.writes {
    files[path] = text
  }
  let result = Tree::from_files(files)
  let directories = result.directories.copy()
  for directory in tree.directories + self.directories {
    let directory = normalize(directory)
    if !deletes.any(d => within(d, directory)) &&
      !directories.contains(directory) {
      if files.contains(directory) {
        raise @config.Invalid("File is also a directory: " + directory)
      }
      directories.push(directory)
    }
  }
  directories.sort()
  { files: result.files, directories, }
}

///|
fn quoted(text : String) -> String {
  Json::string(text).stringify()
}

///|
fn edit_toml(
  text : String,
  edit : (@toml_edit.Document) -> @toml_edit.Document raise,
) -> String raise {
  edit(@toml_edit.parse(text)).encode() catch {
    @toml_edit.Diagnostic(_, message, position) =>
      raise @config.Invalid(
        message +
        " at " +
        position.line.to_string() +
        ":" +
        position.column.to_string(),
      )
    error => raise error
  }
}

///|
fn new_project_files(
  path : String,
  project : NewProject,
  language : String,
  checkpoint~ : Bool = true,
) -> Map[String, String] raise {
  let source = normalize(project.source_directory)
  if source == "" {
    raise @config.Invalid("Source directory must be nonempty")
  }
  let (filename, starter) = match language {
    "scheme" => ("main.scm", "(define (identity value) value)\n")
    "elm" => {
      let module_prefix = project.name.to_string().replace_all(old="/", new=".")
      if !module_prefix
        .split(".")
        .all(part => {
          let chars = part.to_array()
          !chars.is_empty() &&
          chars[0] >= 'A' &&
          chars[0] <= 'Z' &&
          chars.all(c => {
            (c >= 'A' && c <= 'Z') ||
            (c >= 'a' && c <= 'z') ||
            (c >= '0' && c <= '9') ||
            c == '_'
          })
        }) {
        raise @config.Invalid(
          "An Elm project name must use capitalized module segments, for example My.Project",
        )
      }
      (
        module_prefix.replace_all(old=".", new="/") + "/Main.elm",
        "module " +
        module_prefix +
        ".Main exposing (identity)\n\nidentity value =\n    value\n",
      )
    }
    "moonbit" =>
      ("main.mbt", "pub fn identity(value : Int) -> Int {\n  value\n}\n")
    _ => raise @config.Invalid("No project starter for language: " + language)
  }
  let mut config = "[project]\nname = " +
    quoted(project.name.to_string()) +
    "\nsource_directory = " +
    quoted(source) +
    "\n"
  if language == "elm" {
    config += "exposed_modules = [\"Main\"]\n"
  }
  if project.language is Some(language) {
    config += "\n[frontend]\nlanguage = " + quoted(language.to_string()) + "\n"
  }
  if project.profile is Some(profile) {
    if project.language is None {
      config += "\n[frontend]\n"
    }
    config += "profile = " + quoted(profile.to_string()) + "\n"
  }
  if checkpoint && (language == "elm" || language == "moonbit") {
    config += "\n[pipeline]\nbackend = \"checkpoint\"\ncheckpoint_format = \"ion-binary\"\n"
  }
  Map::from_array([
    (join(path, "morphir.toml"), config),
    (join(join(path, source), filename), starter),
  ])
}

///|
fn ensure_new_config(tree : Tree, path : String) -> Unit raise {
  let candidates = primary_paths(path) +
    [join(path, "morphir.json"), join(path, "morphir-workspace.json")]
  if candidates.any(p => tree.files.contains(p)) {
    raise @config.Invalid("Project configuration already exists: " + path)
  }
}

///|
pub fn init_workspace(
  tree : Tree,
  project~ : NewProject? = None,
  members~ : Array[String] = [],
) -> Edit raise {
  ensure_new_config(tree, "")
  for pattern in members {
    ignore(matches(pattern, ""))
  }
  let config = "[workspace]\nmembers = [" +
    members.map(quoted).join(", ") +
    "]\n"
  let writes = match project {
    Some(project) =>
      new_project_files(
        "",
        project,
        project.language.map(l => l.to_string()).unwrap_or("scheme"),
      )
    None => Map([])
  }
  writes["morphir.toml"] = config +
    "\n" +
    writes.get("morphir.toml").unwrap_or("")
  let edit : Edit = { writes, directories: [], deletes: [], warnings: [], }
  // A starter never overwrites an existing source file.
  for path, _ in writes {
    if tree.files.contains(path) || tree.directories.contains(path) {
      raise @config.Invalid("File already exists: " + path)
    }
  }
  ignore(edit.apply(tree))
  edit
}

///|
fn workspace_config(workspace : Workspace, tree : Tree) -> String raise {
  if !workspace.anchor.has_suffix(".toml") ||
    !tree.files.contains(workspace.anchor) {
    raise @config.Invalid("Project changes require a morphir.toml workspace")
  }
  let text = tree.files[workspace.anchor]
  if @config.parse(text).get("workspace") is None {
    raise @config.Invalid("Project changes require a [workspace] table")
  }
  text
}

///|
pub fn add_project(
  workspace : Workspace,
  tree : Tree,
  path : ProjectPath,
  project : NewProject,
) -> Edit raise {
  let config = workspace_config(workspace, tree)
  let relative = path.to_string()
  let root = join(workspace.root, relative)
  if workspace.projects.any(p => p.root == root) {
    raise @config.Invalid("Project already exists: " + relative)
  }
  let excludes = workspace.document.strings("workspace.exclude")
  if excludes.any(pattern => matches(normalize(pattern), relative)) {
    raise @config.Invalid(
      "Project is excluded by workspace configuration: " + relative,
    )
  }
  let language = project.language
    .map(l => l.to_string())
    .unwrap_or(workspace.document.text("frontend.language", "scheme"))
  let writes = new_project_files(
    root,
    project,
    language,
    checkpoint=workspace.document.get("pipeline.backend") is None,
  )
  if relative == "" {
    // The virtual workspace's existing config remains the source of shared defaults.
    let project_config = @config.parse(writes[join(root, "morphir.toml")])
    let has_frontend = @config.parse(config).get("frontend") is Some(_)
    let has_pipeline = @config.parse(config).get("pipeline") is Some(_)
    let updated = edit_toml(config, fn(doc) raise {
      let mut doc = doc.add_table(["project"])
      for key in ["name", "source_directory", "exposed_modules"] {
        if project_config.json("project." + key) is Some(value) {
          doc = doc.set(["project", key], value.stringify())
        }
      }
      if !has_frontend &&
        (project.language is Some(_) || project.profile is Some(_)) {
        doc = doc.add_table(["frontend"])
      }
      if project.language is Some(language) {
        doc = doc.set(["frontend", "language"], quoted(language.to_string()))
      }
      if project.profile is Some(profile) {
        doc = doc.set(["frontend", "profile"], quoted(profile.to_string()))
      }
      if project_config.get("pipeline") is Some(_) {
        if !has_pipeline {
          doc = doc.add_table(["pipeline"])
        }
        doc = doc.set(["pipeline", "backend"], "\"checkpoint\"")
        doc = doc.set(["pipeline", "checkpoint_format"], "\"ion-binary\"")
      }
      doc
    })
    writes.remove(join(root, "morphir.toml"))
    writes[workspace.anchor] = updated
  } else {
    ensure_new_config(tree, root)
    let members = workspace.document.strings("workspace.members")
    if !members.any(pattern => matches(normalize(pattern), relative)) {
      writes[workspace.anchor] = edit_toml(config, fn(doc) raise {
        if doc.get(["workspace", "members"]) is None {
          doc.set(["workspace", "members"], "[" + quoted(relative) + "]")
        } else {
          doc.append(["workspace", "members"], quoted(relative))
        }
      })
    }
  }
  for file, _ in writes {
    if file != workspace.anchor &&
      (tree.files.contains(file) || tree.directories.contains(file)) {
      raise @config.Invalid("File already exists: " + file)
    }
  }
  let warnings = if workspace.projects.any(p => {
      p.name == project.name.to_string()
    }) {
    ["Duplicate project name: " + project.name.to_string()]
  } else {
    []
  }
  let edit : Edit = {
    writes,
    directories: [join(root, project.source_directory)],
    deletes: [],
    warnings,
  }
  ignore(edit.apply(tree))
  edit
}

///|
pub fn remove_project(
  workspace : Workspace,
  tree : Tree,
  path : ProjectPath,
  delete_files~ : Bool = false,
) -> Edit raise {
  let config = workspace_config(workspace, tree)
  let relative = path.to_string()
  let root = join(workspace.root, relative)
  if !workspace.projects.any(p => p.root == root) {
    raise @config.Invalid("Unknown project: " + relative)
  }
  if relative == "" && delete_files {
    raise @config.Invalid("Cannot delete the workspace root")
  }
  if delete_files &&
    workspace.projects.any(p => p.root != root && within(root, p.root)) {
    raise @config.Invalid(
      "Remove nested projects before deleting their containing project",
    )
  }
  let members = workspace.document.strings("workspace.members")
  let updated = edit_toml(config, fn(doc) raise {
    let mut doc = doc
    if relative == "" {
      doc = doc.remove_table(["project"])
    } else {
      for i = members.length() - 1; i >= 0; i = i - 1 {
        if normalize(members[i]) == relative {
          doc = doc.remove_item(["workspace", "members"], i)
        }
      }
      if members.any(pattern => {
          normalize(pattern) != relative &&
          matches(normalize(pattern), relative)
        }) {
        doc = if doc.get(["workspace", "exclude"]) is None {
          doc.set(["workspace", "exclude"], "[" + quoted(relative) + "]")
        } else {
          doc.append(["workspace", "exclude"], quoted(relative))
        }
      }
    }
    if normalize(workspace.document.text("workspace.default_member", "")) ==
      relative &&
      doc.get(["workspace", "default_member"]) is Some(_) {
      doc = doc.remove(["workspace", "default_member"])
    }
    doc
  })
  {
    writes: Map::from_array([(workspace.anchor, updated)]),
    directories: [],
    deletes: if delete_files {
      [root]
    } else {
      []
    },
    warnings: [],
  }
}
