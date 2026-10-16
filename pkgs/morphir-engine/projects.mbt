///|
pub(all) struct ProjectInfo {
  name : String
  relative_path : String
  frontend : String?
  target : String?
  error : String?
}

///|
pub fn ProjectInfo::to_json(self : ProjectInfo) -> Json {
  fn optional(value : String?) -> Json {
    match value {
      Some(value) => Json::string(value)
      None => Json::null()
    }
  }
  Json::object(
    Map::from_array([
      ("name", Json::string(self.name)),
      ("relativePath", Json::string(self.relative_path)),
      ("frontend", optional(self.frontend)),
      ("target", optional(self.target)),
      ("error", optional(self.error)),
    ]),
  )
}

///|
fn validate_project_configuration(
  workspace : @workspace.Workspace,
  project : @workspace.Project,
) -> @version.FormatVersion raise {
  if project.error is Some(message) {
    raise @configuration.Invalid(message)
  }
  let effective = project.document
  effective.validate()
  if effective.boolean("ir.strict_mode", false) &&
    !workspace.warnings.is_empty() {
    raise @configuration.Invalid(
      "Strict configuration rejects warnings: " + workspace.warnings.join("; "),
    )
  }
  if effective.get("ir.mode") is Some(_) &&
    effective.provenance.get("ir.layout") == Some("defaults") {
    if effective.text("ir.mode", "classic") != "classic" {
      raise @configuration.Invalid(
        "Only ir.mode = classic is supported; prefer ir.layout = single-file",
      )
    }
  }
  if effective.text("ir.layout", "single-file") != "single-file" ||
    effective.text("ir.format", "json") != "json" {
    raise @configuration.Invalid(
      "Only single-file JSON IR output is currently supported",
    )
  }
  let version = match effective.get("ir.format_version") {
    Some(@toml.TomlInteger(n)) if n >= 1 && n <= 4 =>
      @version.FormatVersion::baseline(n.to_int().reinterpret_as_uint())
    None => @version.FormatVersion::baseline(4U)
    _ =>
      raise @configuration.Invalid(
        "Supported IR format versions are integers 1 through 4",
      )
  }
  version
}

///|
fn Engine::resolve_project_config(
  self : Engine,
  host : Host,
  workspace : @workspace.Workspace,
  project : @workspace.Project,
  script : String,
  overlay : @configuration.Document,
  cancelled : () -> Bool,
  bind_runtime : (@scheme.Runtime) -> Unit raise,
) -> (Config, @scheme.Runtime, @version.FormatVersion) raise {
  if cancelled() {
    raise @configuration.Invalid("Cancelled")
  }
  let version = validate_project_configuration(workspace, {
    ..project,
    document: @configuration.merge(project.document, overlay),
  })
  let runtime = config_runtime(self.limits)
  runtime.set_cancelled(cancelled)
  bind_runtime(runtime)
  if cancelled() {
    raise @configuration.Invalid("Cancelled")
  }
  let settings = Config::{
    frontend: "scheme",
    frontend_provider: None,
    frontend_profile: None,
    backend: "ir-json",
    output: "",
    package_name: project.name,
    source: if project.anchor == "" {
      ""
    } else {
      "src"
    },
    inference: "off",
    transforms: [],
  }
  settings.overlay(project.document)
  if project.anchor == "" &&
    project.document.provenance.get("project.source_directory") ==
    Some("defaults") {
    settings.source = ""
  }
  let root_script = join(workspace.root, "morphir.config.scm")
  let project_script = join(project.root, "morphir.config.scm")
  for
    path in (if root_script == project_script {
      [root_script]
    } else {
      [root_script, project_script]
    }) {
    if (host.exists)(path) {
      settings.apply(runtime, (host.read)(path), origin=path)
    }
  }
  if script != "" {
    settings.apply(runtime, script)
  }
  if cancelled() {
    raise @configuration.Invalid("Cancelled")
  }
  settings.overlay(overlay)
  (settings, runtime, version)
}

///|
/// Resolve language choices through the host without compiling or reading sources.
/// Unknown frontend/backend names remain visible for external tooling.
pub fn Engine::list_projects(
  self : Engine,
  host : Host,
  workspace : @workspace.Workspace,
  script~ : String = "",
  cancelled~ : () -> Bool = fn() { false },
  bind_runtime~ : (@scheme.Runtime) -> Unit raise = fn(_) { () },
) -> Array[ProjectInfo] raise {
  workspace.projects.map(fn(project) raise {
    if cancelled() {
      raise @configuration.Invalid("Cancelled")
    }
    let path = if project.root == "" { "." } else { project.root }
    try {
      let (settings, _, _) = self.resolve_project_config(
        host,
        workspace,
        project,
        script,
        @configuration.empty(),
        cancelled,
        bind_runtime,
      )
      {
        name: project.name,
        relative_path: path,
        frontend: Some(settings.frontend),
        target: Some(settings.backend),
        error: None,
      }
    } catch {
      @scheme.Limit("cancelled") => raise @configuration.Invalid("Cancelled")
      @configuration.Invalid("Cancelled") =>
        raise @configuration.Invalid("Cancelled")
      error => {
        if cancelled() {
          raise @configuration.Invalid("Cancelled")
        }
        {
          name: project.name,
          relative_path: path,
          frontend: None,
          target: None,
          error: Some(
            match error {
              @configuration.Invalid(message)
              | @scheme.Invalid(message)
              | @scheme.Unsupported(message)
              | @scheme.Unbound(message)
              | @scheme.Limit(message) => message
              @scheme.Syntax(message, position) =>
                message + " at " + position.to_string()
              @scheme.Stage(stage, message) => stage + ": " + message
              _ => error.to_string()
            },
          ),
        }
      }
    }
  })
}
