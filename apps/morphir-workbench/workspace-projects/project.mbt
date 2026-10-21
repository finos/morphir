///|
pub fn Files::project_at(
  self : Files,
  path : @discovery.ProjectPath,
  extensions : Array[@ids.FileExtension],
) -> @project.Project? raise {
  let snapshot = self.discover()
  let root = @discovery.join(snapshot.root, path.to_string())
  guard snapshot.projects.iter().find_first(p => p.root == root)
    is Some(project) else {
    return None
  }
  if project.error is Some(message) {
    raise @config.Invalid(message)
  }
  let source = @discovery.join(
    root,
    project.document.text("project.source_directory", "src"),
  )
  let files : Array[@project.ProjectFile] = []
  let absolute = self
    .paths()
    .filter(file => {
      @discovery.within(source, file) &&
      extensions.any(ext => file.has_suffix(ext.to_string())) &&
      !snapshot.projects.any(other => {
        other.root != root &&
        @discovery.within(root, other.root) &&
        @discovery.within(other.root, file)
      })
    })
  for file in absolute {
    let relative = if root == "" {
      file
    } else {
      file[root.length() + 1:].to_owned()
    }
    if self.read(file) is Some(content) {
      files.push({ path: @ids.SourcePath::parse(relative), content, })
    }
  }
  guard files is [first, ..] else { return None }
  let opened = self.open_file.bind(file => {
    if files.any(source => {
        source.path.to_string() ==
        (if root == "" { file } else { file[root.length() + 1:].to_owned() })
      }) {
      Some(
        @ids.SourcePath::parse(
          if root == "" {
            file
          } else {
            file[root.length() + 1:].to_owned()
          },
        ),
      )
    } else {
      None
    }
  })
  let document = project.document
  {
    name: @ids.SourcePackageName::parse(project.name),
    language: @ids.LanguageId::parse(
      document.text("frontend.language", "scheme"),
    ),
    provider: if document.get("frontend.provider") is Some(_) {
      Some(@ids.ProviderId::parse(document.text("frontend.provider", "")))
    } else {
      None
    },
    profile: if document.get("frontend.profile") is Some(_) {
      Some(@ids.ProfileId::parse(document.text("frontend.profile", "")))
    } else {
      None
    },
    target: match document.get("pipeline.backend") {
      None => None
      Some(_) => {
        let backend = document.text("pipeline.backend", "")
        @project.Generation::parse(
          if backend == "checkpoint" || backend == "ir-json" {
            ""
          } else {
            backend
          },
        )
      }
    },
    files,
    exposed: document
    .strings("project.exposed_modules")
    .map(@ids.SourceModuleName::parse),
    active: opened.unwrap_or(first.path),
  }
  |> Some
}

///|
pub fn Files::replace_project(
  self : Files,
  path : @discovery.ProjectPath,
  project : @project.Project,
  extensions : Array[@ids.FileExtension],
) -> Files raise {
  let snapshot = self.discover()
  let root = @discovery.join(snapshot.root, path.to_string())
  let existing = snapshot.projects.iter().find_first(p => p.root == root)
  let initial = match existing {
    Some(_) => self
    None =>
      self.add_project(path, {
        name: project.name,
        language: Some(project.language),
        profile: project.profile,
        source_directory: "src",
      })
  }
  let before = initial.project_at(path, extensions)
  let mut result = initial
  // Write only changed settings, retaining original quoting and inherited values otherwise.
  for
    (setting, value) in [
      (Name, Some(project.name.to_string())),
      (Language, Some(project.language.to_string())),
      (SourceProfile, project.profile.map(p => p.to_string())),
      (Provider, project.provider.map(p => p.to_string())),
      (
        Generation,
        project.target.map(g => if g.id() == "" { "checkpoint" } else { g.id() }),
      ),
    ] {
    if result.setting(path, setting).effective != value && value is Some(_) {
      result = result.configure(path, setting, value)
    }
  }
  if before is Some(before) {
    for file in before.files {
      if !project.files.any(next => next.path == file.path) {
        result = result.remove(@discovery.join(root, file.path.to_string()))
      }
    }
  }
  for file in project.files {
    result = result.write(
      @discovery.join(root, file.path.to_string()),
      file.content,
    )
  }
  let anchor = find_project(result, path).anchor
  let doc = @config.parse(result.read(anchor).unwrap_or(""))
  let exposed = project.exposed.map(m => m.to_string())
  if doc.strings("project.exposed_modules") != exposed {
    let text = try {
      let editable = @toml_edit.parse(result.read(anchor).unwrap_or(""))
      let edited = if exposed.is_empty() {
        editable.remove(["project", "exposed_modules"])
      } else {
        editable.set(
          ["project", "exposed_modules"],
          "[" + exposed.map(quote).join(", ") + "]",
        )
      }
      edited.encode()
    } catch {
      @toml_edit.Diagnostic(_, message, _) => raise @config.Invalid(message)
    }
    result = result.write(anchor, text)
  }
  result.open(@discovery.join(root, project.active.to_string()))
}
