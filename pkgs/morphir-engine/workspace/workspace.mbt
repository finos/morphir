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
  primary : @config.Document
  warnings : Array[String]
}

///|
pub fn primary_paths(root : String) -> Array[String] raise {
  let paths = [join(root, "morphir-workspace.json")]
  for stem in ["morphir", ".morphir/morphir", ".config/morphir/config"] {
    for extension in ["json", "json5", "yaml", "yml", "toml"] {
      paths.push(join(root, stem + "." + extension))
    }
  }
  paths
}

///|
pub fn discover(
  tree : Tree,
  root~ : String = "",
  system~ : @config.Document = @config.empty(),
  global~ : @config.Document = @config.empty(),
  environment~ : Map[String, String] = Map([]),
  overlay~ : @config.Document = @config.empty(),
  options~ : ConfigurationOptions = ConfigurationOptions::new(),
) -> Workspace raise {
  let root = normalize(root)
  let loaded = resolve_configuration(
    tree,
    root,
    None,
    options,
    system,
    global,
    environment,
    overlay,
  ) catch {
    @lander.Ambiguous(candidates~, ..) =>
      raise @config.Invalid("Ambiguous configuration: " + candidates.join(", "))
    @lander.Profile(failure~) => raise @config.Invalid(failure.message())
    error => raise @config.Invalid(error.message())
  }
  let anchor = loaded.anchor
  let primary_doc = loaded.primary
  let root_effective = loaded.document
  root_effective.validate()
  let warnings = loaded.warnings.copy()
  let workspace_root = join(root, root_effective.text("workspace.root", ""))
  let members = root_effective.strings("workspace.members").map(normalize)
  let excludes = root_effective.strings("workspace.exclude").map(normalize)
  for pattern in members + excludes {
    ignore(matches(pattern, ""))
  }
  let roots : Map[String, Bool] = Map([])
  if primary_doc.get("project") is Some(_) {
    roots[workspace_root] = true
  }
  for directory in tree.directories {
    let directory = normalize(directory)
    if directory == workspace_root || !within(workspace_root, directory) {
      continue
    }
    if primary_paths(directory).any(path => path == anchor) {
      continue
    }
    let relative = suffix(workspace_root, directory)
    if members.any(pattern => matches(pattern, relative)) &&
      !excludes.any(pattern => matches(pattern, relative)) {
      roots[directory] = true
    }
  }
  for pattern in members {
    if !pattern.contains("*") &&
      !pattern.contains("?") &&
      !pattern.contains("[") &&
      !pattern.contains("{") &&
      !excludes.any(excluded => matches(excluded, pattern)) {
      if !tree.directories.any(directory => {
          normalize(directory) == join(workspace_root, pattern)
        }) {
        warnings.push(
          "Missing workspace member: " + join(workspace_root, pattern),
        )
      }
    }
  }
  if roots.is_empty() && members.is_empty() && anchor == "" {
    roots[workspace_root] = true
  }
  let paths = roots.keys().collect()
  paths.sort()
  let projects = []
  for path in paths {
    try {
      let data = if path == workspace_root {
        loaded
      } else {
        resolve_configuration(
          tree,
          root,
          Some(path),
          options,
          system,
          global,
          environment,
          overlay,
        )
      }
      for warning in data.warnings {
        if !warnings.contains(warning) {
          warnings.push(warning)
        }
      }
      if path != workspace_root && data.anchor == "" {
        if members.contains(suffix(workspace_root, path)) {
          raise @config.Invalid("Member has no project configuration: " + path)
        }
        continue
      }
      if path != workspace_root {
        for
          (key, message) in [
            ("workspace.out_dir", "Ignoring member workspace.out_dir: "),
            ("workspace.output_dir", "Removed workspace.output_dir alias: "),
          ] {
          if data.primary.get(key) is Some(_) {
            warnings.push(message + path)
          }
        }
      }
      let effective = data.document
      effective.validate()
      ignore(normalize(effective.text("project.source_directory", "src")))
      let name = effective.text(
        "project.name",
        if path == workspace_root {
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
        anchor: data.anchor,
        document: effective,
        error: None,
      })
    } catch {
      @lander.Ambiguous(candidates~, ..) =>
        raise @config.Invalid(
          "Ambiguous configuration: " + candidates.join(", "),
        )
      @lander.Profile(failure~) => raise @config.Invalid(failure.message())
      error => {
        let found = primary_paths(path).filter(candidate => {
          tree.files.contains(candidate)
        })
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
  let names : Map[String, Array[String]] = Map([])
  for project in projects {
    let entries = names.get(project.name).unwrap_or([])
    entries.push(
      if project.root == workspace_root {
        "."
      } else {
        suffix(workspace_root, project.root)
      },
    )
    names[project.name] = entries
  }
  let sorted = names.keys().collect()
  sorted.sort()
  for name in sorted {
    if names[name].length() > 1 {
      warnings.push(
        "Duplicate project name '" + name + "': " + names[name].join(", "),
      )
    }
  }
  let default_member = root_effective.text("workspace.default_member", "")
  if default_member != "" &&
    !projects.any(project => {
      project.root == join(workspace_root, default_member)
    }) {
    raise @config.Invalid("Invalid default member: " + default_member)
  }
  if root_effective.get("workspace.output_dir") is Some(_) {
    warnings.push("Removed workspace.output_dir alias")
  }
  {
    root: workspace_root,
    anchor,
    document: root_effective,
    primary: primary_doc,
    projects,
    warnings,
  }
}

///|
pub fn Workspace::select(
  self : Workspace,
  selector~ : String = "",
  all~ : Bool = false,
  invocation~ : String = "",
) -> Array[Project] raise {
  if all && selector != "" {
    raise @config.Invalid("--all and --project cannot be combined")
  }
  if all {
    return self.projects.copy()
  }
  if selector != "" {
    // Paths take precedence over display names, including `.` for the root.
    let canonical = normalize(selector)
    let by_path = self.projects.filter(p => {
      suffix(self.root, p.root) == canonical
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
  self.projects.copy()
}

///|
pub fn Workspace::to_json(self : Workspace) -> Json raise {
  Json::object(
    Map::from_array([
      ("protocolVersion", Json::string("0.1.0")),
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
      (
        "diagnostics",
        Json::array(
          self.warnings.map(message => {
            Json::object(
              Map::from_array([
                ("severity", Json::string("warning")),
                ("code", Json::string("workspace.warning")),
                ("message", Json::string(message)),
                ("path", Json::string(self.anchor)),
              ]),
            )
          }),
        ),
      ),
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
                  Json::string(
                    if p.root == self.root {
                      "."
                    } else {
                      suffix(self.root, p.root)
                    },
                  ),
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
                                  if p.root == self.root {
                                    "."
                                  } else {
                                    suffix(self.root, p.root)
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
