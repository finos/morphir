///|
pub(all) enum Setting {
  Name
  SourceDirectory
  Language
  SourceProfile
  Provider
  Generation
  DefaultMember
} derive(Eq, Debug)

///|
pub extend Setting with Eq::{equal, not_equal}

///|
pub extend Setting with @debug.Debug::{to_repr}

///|
fn Setting::keys(self : Setting) -> Array[String] {
  match self {
    Name => ["project", "name"]
    SourceDirectory => ["project", "source_directory"]
    Language => ["frontend", "language"]
    SourceProfile => ["frontend", "profile"]
    Provider => ["frontend", "provider"]
    Generation => ["pipeline", "backend"]
    DefaultMember => ["workspace", "default_member"]
  }
}

///|
pub(all) struct SettingValue {
  effective : String?
  override_value : String?
  origin : String?
} derive(Eq, Debug)

///|
pub extend SettingValue with Eq::{equal, not_equal}

///|
pub extend SettingValue with @debug.Debug::{to_repr}

///|
fn find_project(
  files : Files,
  path : @discovery.ProjectPath,
) -> @discovery.Project raise {
  let workspace = files.discover()
  let root = @discovery.join(workspace.root, path.to_string())
  match workspace.projects.iter().find_first(p => p.root == root) {
    Some(project) => project
    None => raise @config.Invalid("Unknown project: " + path.to_string())
  }
}

///|
pub fn Files::setting(
  self : Files,
  path : @discovery.ProjectPath,
  setting : Setting,
) -> SettingValue raise {
  let project = find_project(self, path)
  let key = setting.keys().join(".")
  let primary = if project.anchor.has_suffix(".toml") {
    @config.parse(self.read(project.anchor).unwrap_or(""))
  } else {
    @config.empty()
  }
  {
    effective: if project.document.get(key) is Some(_) {
      Some(project.document.text(key, ""))
    } else {
      None
    },
    override_value: if primary.get(key) is Some(_) {
      Some(primary.text(key, ""))
    } else {
      None
    },
    origin: project.document.provenance.get(key),
  }
}

///|
/// None removes an override; Some writes an explicit setting in the project's config.
pub fn Files::configure(
  self : Files,
  path : @discovery.ProjectPath,
  setting : Setting,
  value : String?,
) -> Files raise {
  let project = find_project(self, path)
  if !project.anchor.has_suffix(".toml") {
    raise @config.Invalid(
      "Convert morphir.json to morphir.toml before editing project settings",
    )
  }
  let text = self.read(project.anchor).unwrap_or("")
  self.configure_at(project.anchor, text, setting, value)
}

///|
pub fn Files::configure_workspace(
  self : Files,
  setting : Setting,
  value : String?,
) -> Files raise {
  if setting is (Name | SourceDirectory) {
    raise @config.Invalid(
      "Project identity and source directories are set per project",
    )
  }
  let workspace = self.discover()
  if !workspace.anchor.has_suffix(".toml") {
    raise @config.Invalid("Workspace settings require morphir.toml")
  }
  self.configure_at(
    workspace.anchor,
    self.read(workspace.anchor).unwrap_or(""),
    setting,
    value,
  )
}

///|
fn Files::configure_at(
  self : Files,
  anchor : String,
  text : String,
  setting : Setting,
  value : String?,
) -> Files raise {
  if value is Some(value) {
    match setting {
      Name => ignore(@ids.SourcePackageName::parse(value))
      Language => ignore(@ids.LanguageId::parse(value))
      SourceProfile => ignore(@ids.ProfileId::parse(value))
      Provider => ignore(@ids.ProviderId::parse(value))
      Generation => ignore(@ids.BackendId::parse(value))
      SourceDirectory => ignore(@discovery.normalize(value))
      DefaultMember => ignore(@discovery.ProjectPath::parse(value))
    }
  }
  let keys = setting.keys()
  let primary = @config.parse(text)
  let edited = try {
    let doc = @toml_edit.parse(text)
    let edited = match value {
      None => if doc.get(keys) is Some(_) { doc.remove(keys) } else { doc }
      Some(value) => {
        let doc = if primary.get(keys[0]) is None {
          doc.add_table([keys[0]])
        } else {
          doc
        }
        doc.set(keys, quote(value))
      }
    }
    edited.encode()
  } catch {
    @toml_edit.Diagnostic(_, message, position) =>
      raise @config.Invalid(message + " at line " + position.line.to_string())
  }
  let result = self.write(anchor, edited)
  // Workspace-level errors, such as an unknown default member, refuse the edit.
  // A separate invalid member remains visible and must not block repairing this one.
  ignore(result.discover())
  result
}

///|
/// Conversion is explicit and leaves the original manifest byte-for-byte intact.
pub fn Files::convert_legacy(
  self : Files,
  path : @discovery.ProjectPath,
) -> Files raise {
  let project = find_project(self, path)
  if !project.anchor.has_suffix("morphir.json") {
    raise @config.Invalid("This project already uses morphir.toml")
  }
  if project.error is Some(message) {
    raise @config.Invalid(message)
  }
  let config = @config.from_json({
    "project": {
      "name": Json::string(project.name),
      "source_directory": Json::string(
        project.document.text("project.source_directory", "src"),
      ),
      "exposed_modules": Json::array(
        project.document.strings("project.exposed_modules").map(Json::string),
      ),
    },
    "frontend": { "language": "elm" },
    "pipeline": { "backend": "checkpoint", "checkpoint_format": "morphir-json" },
  }).encode()
  self.write(@discovery.join(project.root, "morphir.toml"), config)
}
