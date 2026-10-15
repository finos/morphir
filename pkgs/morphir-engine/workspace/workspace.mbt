///|
pub(all) struct Tree {
  files : Map[String, String]
  directories : Array[String]
}

///|
pub(all) struct Project {
  root : String
  name : String
  anchor : String
  document : @config.Document
  error : String?
}

///|
pub(all) struct Workspace {
  root : String
  anchor : String
  document : @config.Document
  projects : Array[Project]
  warnings : Array[String]
}

///|
pub fn primary_paths(root : String) -> Array[String] raise {
  [
    "morphir.toml", "morphir.yaml", ".morphir/morphir.toml", ".morphir/morphir.yaml",
    ".config/morphir/config.toml", ".config/morphir/config.yaml",
  ].map(path => join(root, path))
}

///|
fn primary(tree : Tree, root : String) -> String? raise {
  let found = primary_paths(root).filter(path => tree.files.contains(path))
  if found.length() > 1 {
    raise @config.Invalid("Ambiguous configuration: " + found.join(", "))
  }
  match found {
    [] => None
    [path] => {
      if path.has_suffix(".yaml") {
        raise @config.Invalid("Unsupported configuration format: " + path)
      }
      Some(path)
    }
    _ => None
  }
}

///|
fn user(tree : Tree, anchor : String) -> @config.Document raise {
  if !anchor.has_suffix(".toml") {
    return @config.empty()
  }
  let base = anchor[:anchor.length() - 5].to_owned() + ".user"
  let found = [base + ".toml", base + ".yaml"].filter(path => {
    tree.files.contains(path)
  })
  if found.length() > 1 {
    raise @config.Invalid("Ambiguous user configuration: " + found.join(", "))
  }
  match found {
    [path] if path.has_suffix(".toml") =>
      @config.parse(tree.files[path], origin=path)
    [path] => raise @config.Invalid("Unsupported configuration format: " + path)
    _ => @config.empty()
  }
}

///|
/// A morphir-elm project file. `morphir.json` is morphir-elm's format, so the project is an Elm project. It
/// compiles to a Morphir IR JSON checkpoint unless the configuration or the run chooses another backend. It
/// returns the pipeline defaults, which sit below system and global configuration, and the project
/// document. `dependencies`, `localDependencies` and `decorations` are not supported; a non-empty one
/// gives a warning.
fn legacy(
  tree : Tree,
  root : String,
  warnings : Array[String],
) -> (@config.Document, @config.Document) raise {
  let path = join(root, "morphir.json")
  guard @json.parse(tree.files[path]) is Object(fields) else {
    raise @config.Invalid("Expected project manifest object: " + path)
  }
  let fail = fn(message : String) -> @config.Invalid {
    @config.Invalid("morphir.json " + message + ": " + path)
  }
  let name = match fields.get("name") {
    Some(String(text)) => text
    None => "user"
    Some(_) => raise fail("name must be a string")
  }
  ignore(
    @ids.SourcePackageName::parse(name) catch {
      @config.Invalid(message) => raise fail("name: " + message)
    },
  )
  let source_directory = match fields.get("sourceDirectory") {
    Some(String(text)) => text
    None => "src"
    Some(_) => raise fail("sourceDirectory must be a string")
  }
  guard fields.get("exposedModules") is Some(Array(items)) else {
    raise fail("exposedModules must be a list of module names")
  }
  let exposed : Array[Json] = []
  for item in items {
    guard item is String(text) else {
      raise fail("exposedModules must be a list of module names")
    }
    ignore(
      @ids.SourceModuleName::parse(text) catch {
        @config.Invalid(message) => raise fail("exposedModules: " + message)
      },
    )
    exposed.push(Json::string(text))
  }
  for key in ["dependencies", "localDependencies", "decorations"] {
    let present = match fields.get(key) {
      None | Some(Null) => false
      Some(Array(values)) => !values.is_empty()
      Some(Object(values)) => !values.is_empty()
      Some(_) => true
    }
    if present {
      warnings.push(
        "Ignoring morphir.json " + key + " (not supported): " + path,
      )
    }
  }
  let primary = @config.from_json(
    {
      "project": {
        "name": Json::string(name),
        "source_directory": Json::string(source_directory),
        "exposed_modules": Json::array(exposed),
      },
      "frontend": { "language": "elm" },
    },
    origin=path,
  )
  // The pipeline settings are defaults only: system, global and workspace configuration may replace them.
  let defaults = @config.from_json(
    {
      "pipeline": {
        "backend": "checkpoint",
        "checkpoint_format": "morphir-json",
      },
    },
    origin=path,
  )
  (defaults, primary)
}

///|
fn load(
  tree : Tree,
  root : String,
  warnings : Array[String],
) -> (String, @config.Document, @config.Document) raise {
  match primary(tree, root) {
    Some(path) => {
      if tree.files.contains(join(root, "morphir.json")) ||
        tree.files.contains(join(root, "morphir-workspace.json")) {
        warnings.push(
          "Canonical configuration overrides legacy manifest at " + root,
        )
      }
      (path, @config.parse(tree.files[path], origin=path), @config.empty())
    }
    None => {
      let path = join(root, "morphir.json")
      if tree.files.contains(path) {
        let (defaults, document) = legacy(tree, root, warnings)
        (path, document, defaults)
      } else {
        ("", @config.empty(), @config.empty())
      }
    }
  }
}

///|
pub fn discover(
  tree : Tree,
  root? : String = "",
  system? : @config.Document = @config.empty(),
  global? : @config.Document = @config.empty(),
  environment? : Map[String, String] = Map([]),
  overlay? : @config.Document = @config.empty(),
) -> Workspace raise {
  let root = normalize(root)
  let warnings = []
  let (anchor, primary_doc, root_defaults) = load(tree, root, warnings)
  let defaults = @config.parse(
    "[workspace]\nout_dir = '.morphir/out'\n[frontend]\nlanguage = 'scheme'\n[project]\nsource_directory = 'src'\n[ir]\nformat_version = 4\nlayout = 'single-file'\nformat = 'json'\n",
    origin="defaults",
  )
  let base_with = fn(extra : @config.Document) {
    defaults
    |> @config.merge(extra)
    |> @config.merge(system.shared())
    |> @config.merge(global.shared())
  }
  let base = base_with(root_defaults)
  let env = @config.environment(environment)
  let shared = @config.merge(base, primary_doc)
  let root_user = user(tree, anchor)
  let root_effective = @config.merge(
    @config.merge(@config.merge(shared, root_user), env),
    overlay,
  )
  root_effective.validate()
  let workspace_root = join(root, root_effective.text("workspace.root", ""))
  let members = root_effective.strings("workspace.members")
  let excludes = root_effective.strings("workspace.exclude")
  for pattern in members + excludes {
    ignore(matches(pattern, ""))
  }
  let roots : Map[String, Bool] = Map([])
  if primary_doc.get("project") is Some(_) {
    roots[workspace_root] = true
  }
  for directory in tree.directories {
    let directory = normalize(directory)
    if !within(workspace_root, directory) {
      continue
    }
    let rel = suffix(workspace_root, directory)
    if members.any(pattern => matches(pattern, rel)) &&
      !excludes.any(pattern => matches(pattern, rel)) {
      roots[directory] = true
    }
  }
  for pattern in members {
    if !pattern.contains("*") &&
      !pattern.contains("?") &&
      !pattern.contains("[") &&
      !pattern.contains("{") {
      let member_config = join(workspace_root, pattern)
      if !tree.directories.contains(member_config) {
        raise @config.Invalid("Missing workspace member: " + member_config)
      }
    }
  }
  let legacy_workspace = join(root, "morphir-workspace.json")
  if anchor == "" && tree.files.contains(legacy_workspace) {
    match @json.parse(tree.files[legacy_workspace]) {
      Object(fields) =>
        match fields.get("projects") {
          Some(Array(items)) =>
            for item in items {
              match item {
                String(s) => roots[join(root, s)] = true
                _ =>
                  raise @config.Invalid(
                    "Legacy workspace projects must be strings",
                  )
              }
            }
          _ => raise @config.Invalid("Legacy workspace requires projects")
        }
      _ => raise @config.Invalid("Invalid legacy workspace")
    }
  }
  if roots.is_empty() && members.is_empty() {
    roots[workspace_root] = true
  }
  let paths = roots.keys().collect()
  paths.sort()
  let projects = []
  for path in paths {
    try {
      let (member_anchor, member_config, member_defaults) = if path ==
        workspace_root {
        (anchor, @config.empty(), @config.empty())
      } else {
        load(tree, path, warnings)
      }
      if path != workspace_root && member_anchor == "" {
        if members.contains(suffix(workspace_root, path)) {
          raise @config.Invalid("Member has no project configuration: " + path)
        }
        continue
      }
      if member_config.get("workspace.out_dir") is Some(_) {
        warnings.push("Ignoring member workspace.out_dir: " + path)
      }
      if member_config.get("workspace.output_dir") is Some(_) {
        warnings.push("Removed workspace.output_dir alias: " + path)
      }
      let mut effective = @config.merge(
        if path == workspace_root {
          shared
        } else {
          @config.merge(base_with(member_defaults), primary_doc.shared())
        },
        member_config,
      )
      effective = @config.merge(
        effective,
        if path == workspace_root {
          root_user
        } else {
          root_user.shared()
        },
      )
      if path != workspace_root {
        effective = @config.merge(effective, user(tree, member_anchor))
      }
      effective = @config.merge(@config.merge(effective, env), overlay)
      effective.validate()
      ignore(normalize(effective.text("project.source_directory", "src")))
      let name = effective.text(
        "project.name",
        if path == "" {
          "user"
        } else {
          suffix(workspace_root, path)
        },
      )
      if name == "" {
        raise @config.Invalid("Project name must be nonempty: " + path)
      }
      projects.push({
        root: path,
        name,
        anchor: member_anchor,
        document: effective,
        error: None,
      })
    } catch {
      error => {
        let found = primary_paths(path).filter(p => tree.files.contains(p))
        projects.push({
          root: path,
          name: path,
          anchor: found.get(0).unwrap_or(""),
          document: @config.empty(),
          error: Some(error.to_string()),
        })
      }
    }
  }
  let default_member = root_effective.text("workspace.default_member", "")
  if default_member != "" &&
    !projects.any(p => p.root == join(workspace_root, default_member)) {
    raise @config.Invalid("Invalid default member: " + default_member)
  }
  if root_effective.get("workspace.output_dir") is Some(_) {
    warnings.push("Removed workspace.output_dir alias")
  }
  {
    root: workspace_root,
    anchor,
    document: root_effective,
    projects,
    warnings,
  }
}

///|
pub fn Workspace::select(
  self : Workspace,
  selector? : String = "",
  all? : Bool = false,
  invocation? : String = "",
) -> Array[Project] raise {
  if all && selector != "" {
    raise @config.Invalid("--all and --project cannot be combined")
  }
  if all {
    return self.projects.copy()
  }
  if selector != "" {
    // Prefer an exact canonical member_config path over names.
    let by_path = self.projects.filter(p => {
      suffix(self.root, p.root) == selector
    })
    if by_path.length() == 1 {
      return by_path
    }
    let by_name = self.projects.filter(p => p.name == selector)
    if by_name.length() != 1 {
      raise @config.Invalid("Unknown or ambiguous project: " + selector)
    }
    return by_name
  }
  let owners = self.projects.filter(p => {
    within(p.root, invocation) && p.root != self.root
  })
  if !owners.is_empty() {
    owners.sort_by(fn(a, b) { b.root.length().compare(a.root.length()) })
    return [owners[0]]
  }
  let default_member = self.document.text("workspace.default_member", "")
  if default_member != "" {
    return self.projects.filter(p => p.root == join(self.root, default_member))
  }
  let root = self.projects.filter(p => p.root == self.root)
  if root.length() == 1 {
    return root
  }
  if self.projects.length() == 1 {
    return self.projects.copy()
  }
  raise @config.Invalid("Select --project <name-or-path> or --all")
}

///|
pub fn Workspace::to_json(self : Workspace) -> Json raise {
  Json::object(
    Map::from_array([
      ("protocolVersion", Json::number(1)),
      ("configAnchor", Json::string(self.anchor)),
      (
        "name",
        match self.document.get("workspace.name") {
          Some(_) => Json::string(self.document.text("workspace.name", ""))
          None => Json::null()
        },
      ),
      (
        "state",
        Json::string(
          if self.projects.any(p => p.error is Some(_)) {
            "error"
          } else {
            "open"
          },
        ),
      ),
      ("diagnostics", Json::array([])),
      (
        "projects",
        Json::array(
          self.projects.map(fn(p) raise {
            Json::object(
              Map::from_array([
                ("name", Json::string(p.name)),
                (
                  "version",
                  match p.document.get("project.version") {
                    Some(_) =>
                      Json::string(p.document.text("project.version", ""))
                    None => Json::null()
                  },
                ),
                (
                  "relativePath",
                  Json::string(if p.root == "" { "." } else { p.root }),
                ),
                (
                  "configAnchor",
                  if p.anchor == "" {
                    Json::null()
                  } else {
                    Json::string(p.anchor)
                  },
                ),
                (
                  "sourceDirectory",
                  Json::string(
                    p.document.text("project.source_directory", "src"),
                  ),
                ),
                (
                  "state",
                  Json::string(
                    if p.error is Some(_) {
                      "error"
                    } else {
                      "unloaded"
                    },
                  ),
                ),
                (
                  "diagnostics",
                  Json::array(
                    match p.error {
                      None => []
                      Some(message) =>
                        [
                          Json::object(
                            Map::from_array([
                              ("severity", Json::string("error")),
                              ("code", Json::string("workspace.member.invalid")),
                              ("message", Json::string(message)),
                              ("path", Json::string(p.anchor)),
                              (
                                "projectPath",
                                Json::string(
                                  if p.root == "" {
                                    "."
                                  } else {
                                    p.root
                                  },
                                ),
                              ),
                            ]),
                          ),
                        ]
                    },
                  ),
                ),
              ]),
            )
          }),
        ),
      ),
    ]),
  )
}
