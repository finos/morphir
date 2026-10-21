///|
fn empty_workspace_files() -> @workspace_files.Files {
  known(() => @workspace_files.migrate([], "scheme").open("morphir.toml"))
}

///|
fn seed_workspace(model : Model, contents : Array[@workspace.Content]) -> Model {
  let root = contents.contains(SourceProject)
  let files = @workspace_files.migrate(
    if root {
      [default_project(model, model.language)]
    } else {
      []
    },
    model.language,
    intent=if contents.contains(Intent) { Some("") } else { None },
    concept=if contents.contains(ConceptualModel) { Some("") } else { None },
    worksheet=if contents.contains(Worksheet) {
      Some(worksheet_example)
    } else {
      None
    },
  ) catch {
    _ => empty_workspace_files()
  }
  with_workspace_files(model, files)
}

///|
fn ensure_workspace_content(
  model : Model,
  content : @workspace.Content,
) -> Model {
  let model = if discovered_projects(model).is_empty() &&
    content is SourceProject {
    write_project_files(model, default_project(model, model.language))
  } else {
    model
  }
  let files = try {
    match content {
      Intent =>
        model.workspace_files.write(
          workspace_content_path(model, content),
          model.intent,
        )
      ConceptualModel =>
        model.workspace_files.write(
          workspace_content_path(model, content),
          model.concept,
        )
      Worksheet =>
        model.workspace_files.write("worksheet.scm", model.worksheet_source)
      _ => model.workspace_files
    }
  } catch {
    _ => return model
  }
  with_workspace_files(model, files)
}

///|
fn workspace_content_path(
  model : Model,
  content : @workspace.Content,
) -> String {
  let snapshot = model.workspace_files.discover() catch {
    _ => return if content is Intent { "intent.md" } else { "src/model.mfs" }
  }
  let root = @discovery.join(
    snapshot.root,
    current_project_path(model).to_string(),
  ) catch {
    _ => ""
  }
  let source = snapshot.projects
    .iter()
    .find_first(p => p.root == root)
    .map(p => {
      p.document.text("project.source_directory", "src") catch {
        _ => "src"
      }
    })
    .unwrap_or("src")
  @discovery.join(
    root,
    if content is Intent {
      "intent.md"
    } else {
      source + "/model.mfs"
    },
  ) catch {
    _ => "intent.md"
  }
}

///|
fn sync_workspace_drafts(before : Model, next : Model, msg : Msg) -> Model {
  if next.active != before.active || !workspace_writable(next) {
    return next
  }
  let path = match msg {
    IntentText(_) => workspace_content_path(next, Intent)
    ConceptText(_) => workspace_content_path(next, ConceptualModel)
    Source(_) if next.worksheet => "worksheet.scm"
    _ => return next
  }
  let value = match msg {
    IntentText(_) => next.intent
    ConceptText(_) => next.concept
    _ => next.worksheet_source
  }
  let files = next.workspace_files.write(path, value) catch { _ => return next }
  with_workspace_files(next, files)
}

///|
extern "js" fn fresh_storage_generation() -> String =
  #|() => globalThis.crypto.randomUUID()

///|
fn workspace_prefix(model : Model) -> String {
  "morphir-workbench.workspace." +
  model.active.map(id => id.to_string()).unwrap_or("unscoped")
}

///|
fn discovered_projects(model : Model) -> Array[@discovery.Project] {
  model.workspace_files.discover().projects catch {
    _ => []
  }
}

///|
fn current_project_path(model : Model) -> @discovery.ProjectPath {
  model.workspace_files
  .current()
  .unwrap_or(known(() => @discovery.ProjectPath::parse("."))) catch {
    _ => known(() => @discovery.ProjectPath::parse("."))
  }
}

///|
fn project_extensions(
  model : Model,
  language : String,
) -> Array[@ids.FileExtension] {
  file_rules(model, language).extensions
}

///|
fn projected_project(
  model : Model,
  path : @discovery.ProjectPath,
) -> @project.Project? {
  let snapshot = model.workspace_files.discover() catch { _ => return None }
  let root = @discovery.join(snapshot.root, path.to_string()) catch {
    _ => return None
  }
  guard snapshot.projects.iter().find_first(p => p.root == root)
    is Some(project) else {
    return None
  }
  let language = project.document.text("frontend.language", "scheme") catch {
    _ => return None
  }
  model.workspace_files.project_at(path, project_extensions(model, language)) catch {
    _ => None
  }
}

///|
fn with_workspace_files(model : Model, files : @workspace_files.Files) -> Model {
  follow_current_project(model, hydrate_workspace_files(model, files))
}

///|
fn hydrate_workspace_files(
  model : Model,
  files : @workspace_files.Files,
) -> Model {
  let files = if files.opened() is None && files.read("morphir.toml") is Some(_) {
    files.open("morphir.toml") catch {
      _ => files
    }
  } else {
    files
  }
  let changed = !files.same_contents(model.workspace_files)
  let next = {
    ..model,
    workspace_files: files,
    revision: model.revision + (if changed { 1 } else { 0 }),
  }
  let snapshot = files.discover() catch {
    @config.Invalid(message) =>
      return {
        ..reported(next, "Workspace", "source", next.revision, [
          workspace_diagnostic(
            message,
            @bottom_panel.Error,
            files.opened().unwrap_or("morphir.toml"),
            "workspace.invalid",
          ),
        ]),
        status: message,
      }
    _ => return next
  }
  let diagnostics = snapshot.warnings.map(message => {
    workspace_diagnostic(
      message,
      @bottom_panel.Warning,
      snapshot.anchor,
      "workspace.warning",
    )
  })
  for project in snapshot.projects {
    if project.error is Some(message) {
      diagnostics.push(
        workspace_diagnostic(
          message,
          @bottom_panel.Error,
          project.anchor,
          "workspace.member.invalid",
        ),
      )
    }
  }
  let next = if changed && !diagnostics.is_empty() {
    reported(next, "Workspace", "source", next.revision, diagnostics)
  } else {
    next
  }
  let path = files.current() catch { _ => None }
  let current = path.bind(path => {
    snapshot.projects
    .iter()
    .find_first(p => {
      p.root ==
      (@discovery.join(snapshot.root, path.to_string()) catch { _ => "" })
    })
  })
  match current {
    None =>
      {
        ..next,
        intent: files.read("intent.md").unwrap_or(""),
        concept: files.read("src/model.mfs").unwrap_or(""),
        worksheet_source: files
        .read("worksheet.scm")
        .unwrap_or(next.worksheet_source),
      }
    Some(project) => {
      let language = project.document.text("frontend.language", model.language) catch {
        _ => model.language
      }
      let profile = project.document.text(
        "frontend.profile",
        text(frontend(model, language), "defaultProfile"),
      ) catch {
        _ => ""
      }
      let backend = project.document.text("pipeline.backend", "checkpoint") catch {
        _ => "checkpoint"
      }
      {
        ..next,
        language,
        source_profile: profile,
        target: if backend == "checkpoint" || backend == "ir-json" {
          ""
        } else {
          backend
        },
        intent: files
        .read(
          @discovery.join(project.root, "intent.md") catch {
            _ => "intent.md"
          },
        )
        .unwrap_or(""),
        concept: files
        .read(
          @discovery.join(
            project.root,
            project.document.text("project.source_directory", "src") +
            "/model.mfs",
          ) catch {
            _ => "src/model.mfs"
          },
        )
        .unwrap_or(""),
        worksheet_source: files
        .read("worksheet.scm")
        .unwrap_or(next.worksheet_source),
      }
    }
  }
}

///|
fn workspace_diagnostic(
  message : String,
  severity : @bottom_panel.Severity,
  location : String,
  code : String,
) -> @bottom_panel.Diagnostic {
  {
    severity,
    code,
    message,
    location,
    coordinates: "",
    related: [],
    fix: "",
    stage: "workspace",
    place: None,
  }
}

///|
fn write_project_files(model : Model, project : @project.Project) -> Model {
  let path = current_project_path(model)
  let snapshot = model.workspace_files.discover() catch { _ => return model }
  let root = @discovery.join(snapshot.root, path.to_string()) catch {
    _ => return model
  }
  let source_directory = snapshot.projects
    .iter()
    .find_first(p => p.root == root)
    .map(p => {
      p.document.text("project.source_directory", "src") catch {
        _ => "src"
      }
    })
    .unwrap_or("src")
  // Samples and starters use src/. Keep an existing project's configured source directory.
  let remap = fn(file : @ids.SourcePath) -> @ids.SourcePath {
    let text = file.to_string()
    if source_directory != "src" && text.strip_prefix("src/") is Some(rest) {
      @ids.SourcePath::parse(source_directory + "/" + rest.to_owned()) catch {
        _ => file
      }
    } else {
      file
    }
  }
  let project = {
    ..project,
    files: project.files.map(file => { ..file, path: remap(file.path), }),
    active: remap(project.active),
  }
  let extensions = project_extensions(model, model.language) +
    project_extensions(model, project.language.to_string())
  let files = model.workspace_files.replace_project(path, project, extensions) catch {
    @config.Invalid(message) =>
      return note(model, "Project", @bottom_panel.Warning, message)
    error =>
      return note(model, "Project", @bottom_panel.Warning, error.to_string())
  }
  with_workspace_files(model, files)
}

///|
fn legacy_projection(model : Model) -> Array[@project.Project] {
  let snapshot = model.workspace_files.discover() catch { _ => return [] }
  snapshot.projects.filter_map(p => {
    let relative = if p.root == snapshot.root {
      ""
    } else if snapshot.root == "" {
      p.root
    } else {
      p.root[snapshot.root.length() + 1:].to_owned()
    }
    projected_project(
      model,
      known(() => @discovery.ProjectPath::parse(relative)),
    )
  })
}

///|
fn restored(
  model : Model,
  language : String,
  saved : String,
) -> (Model, String) {
  if saved == "" {
    return (model, "")
  }
  try {
    let project = @project.Project::from_json(@json.parse(saved))
    if project.language.to_string() != language {
      return (
        model,
        "Could not restore the saved " +
        language +
        " project: it belongs to another language",
      )
    }
    let existing = legacy_projection(model).filter(p => {
      p.language.to_string() != language
    })
    let loaded = with_workspace_files(
      model,
      @workspace_files.migrate(existing + [project], model.language),
    )
    let warning = match project.profile {
      Some(profile) if !items(field(frontend(model, language), "profiles")).any(p => {
            text(p, "id") == profile.to_string()
          },
        ) =>
        "The saved source profile " +
        profile.to_string() +
        " is no longer available; its configuration was retained"
      _ => ""
    }
    (loaded, warning)
  } catch {
    _ => (model, "Could not restore the saved " + language + " project")
  }
}

///|
fn restore_all(model : Model) -> Model {
  restore_all_with(model, storage_load)
}

///|
fn restore_all_with(model : Model, load : (String) -> String) -> Model {
  if model.connected {
    return model
  }
  let prefix = workspace_prefix(model)
  let saved = @workspace_files.load(prefix, key => {
    let value = load(key)
    if value == "" {
      None
    } else {
      Some(value)
    }
  }) catch {
    _ =>
      return note(
        model,
        "Restore",
        @bottom_panel.Error,
        "The saved workspace files could not be restored. The saved records were retained.",
      )
  }
  if saved is Some(files) {
    let origin = load(prefix + ".folder-name.v1")
    return with_workspace_files(
      if origin != "" {
        { ..model, file_access: Detached(origin), }
      } else {
        model
      },
      files,
    )
  }
  let recent = active_entry(model)
    .bind(entry => entry.language)
    .map(l => l.to_string())
    .unwrap_or(model.language)
  let mut next = { ..model, language: recent, }
  for entry in items(field(model.catalog, "frontends")) {
    let language = text(entry, "languageId")
    if !valid_language(language) {
      continue
    }
    let (restored, problem) = restored(
      next,
      language,
      load(storage_key(model, language)),
    )
    next = if problem == "" {
      restored
    } else {
      note(restored, "Restore", @bottom_panel.Warning, problem)
    }
  }
  next
}
