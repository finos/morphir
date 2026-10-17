///|
fn invalid(detail : String) -> ProjectError {
  ProjectError(
    "workbench.invalid_project",
    "The project data is not valid: " + detail,
  )
}

///|
fn field(json : Json, key : String) -> Json? {
  match json {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn text_of(json : Json, key : String) -> String raise ProjectError {
  match field(json, key) {
    Some(String(text)) => text
    _ => raise invalid(key + " is missing or not text")
  }
}

///|
fn optional_text(json : Json, key : String) -> String? raise ProjectError {
  match field(json, key) {
    None | Some(Null) => None
    Some(String(text)) => Some(text)
    _ => raise invalid(key + " is not text")
  }
}

///|
fn[T] parsed(
  parse : (String) -> T raise @config.Invalid,
  text : String,
  key : String,
) -> T raise ProjectError {
  parse(text) catch {
    _ => raise invalid(key + ": " + text)
  }
}

///|
fn Project::base_fields(self : Project) -> Array[(String, Json)] {
  let fields : Array[(String, Json)] = [
    ("name", Json::string(self.name.to_string())),
    ("languageId", Json::string(self.language.to_string())),
    (
      "files",
      Json::array(
        self.files.map(f => {
          (
            {
              "path": Json::string(f.path.to_string()),
              "content": Json::string(f.content),
            } : Json)
        }),
      ),
    ),
    (
      "exposedModules",
      Json::array(self.exposed.map(m => Json::string(m.to_string()))),
    ),
  ]
  if self.provider is Some(p) {
    fields.push(("frontendProvider", Json::string(p.to_string())))
  }
  if self.profile is Some(p) {
    fields.push(("frontendProfile", Json::string(p.to_string())))
  }
  fields
}

///|
pub fn Project::to_request(self : Project) -> Json {
  Json::object(Map::from_array(self.base_fields()))
}

///|
pub fn Project::to_json(self : Project) -> Json {
  let fields = self.base_fields()
  fields.push(("version", Json::number(1.0)))
  fields.push(("active", Json::string(self.active.to_string())))
  Json::object(Map::from_array(fields))
}

///|
/// The project of a request-shaped value; `active` names the active file, or the first file when absent.
fn from_fields(json : Json, active : String?) -> Project raise ProjectError {
  let files : Array[ProjectFile] = match field(json, "files") {
    Some(Array(items)) =>
      items.map(item => {
        let path = text_of(item, "path")
        {
          path: parsed(@ids.SourcePath::parse, path, "path"),
          content: text_of(item, "content"),
        }
      })
    _ => raise invalid("files is missing")
  }
  guard files is [first, ..] else {
    raise invalid("a project needs at least one file")
  }
  let paths = files.map(f => f.path.to_string())
  for i, p in paths {
    if paths[:i].contains(p) {
      raise invalid("duplicate path " + p)
    }
  }
  let exposed : Array[@ids.SourceModuleName] = match
    field(json, "exposedModules") {
    None | Some(Null) => []
    Some(Array(items)) =>
      items.map(item => {
        match item {
          String(text) =>
            parsed(@ids.SourceModuleName::parse, text, "exposedModules")
          _ => raise invalid("exposedModules holds a non-text value")
        }
      })
    _ => raise invalid("exposedModules is not a list")
  }
  let active = match active {
    Some(text) => {
      let path = parsed(@ids.SourcePath::parse, text, "active")
      if !files.iter().any(f => f.path == path) {
        raise invalid("active names no file: " + text)
      }
      path
    }
    None => first.path
  }
  let provider = match optional_text(json, "frontendProvider") {
    Some(t) => Some(parsed(@ids.ProviderId::parse, t, "frontendProvider"))
    None => None
  }
  let profile = match optional_text(json, "frontendProfile") {
    Some(t) => Some(parsed(@ids.ProfileId::parse, t, "frontendProfile"))
    None => None
  }
  let project : Project = {
    name: match safe_package_name(text_of(json, "name")) {
      Some(name) => name
      None => raise invalid("name: " + text_of(json, "name"))
    },
    language: parsed(
      @ids.LanguageId::parse,
      text_of(json, "languageId"),
      "languageId",
    ),
    provider,
    profile,
    files,
    exposed: [],
    active,
  }
  // Exposure belongs to files: modules that no file has are dropped, and repeats are kept once.
  let known = project.modules().map(m => m.0)
  let kept : Array[@ids.SourceModuleName] = []
  for m in exposed {
    if known.contains(m) && !kept.contains(m) {
      kept.push(m)
    }
  }
  { ..project, exposed: kept, }
}

///|
pub fn Project::from_json(json : Json) -> Project raise ProjectError {
  match field(json, "version") {
    Some(Number(n, ..)) if n == 1.0 => ()
    _ => raise invalid("unsupported version")
  }
  from_fields(json, Some(text_of(json, "active")))
}

///|
pub fn Project::from_request(json : Json) -> Project raise ProjectError {
  from_fields(json, None)
}

///|
/// A built-in sample: an asset under `assets/samples/<language>/<id>.json`.
pub(all) struct Sample {
  id : String
  title : String
  notice : String
  project : Project
}

///|
pub fn Sample::from_json(json : Json) -> Sample raise ProjectError {
  match field(json, "version") {
    Some(Number(n, ..)) if n == 1.0 => ()
    _ => raise invalid("unsupported sample version")
  }
  guard field(json, "project") is Some(project) else {
    raise invalid("project is missing")
  }
  {
    id: text_of(json, "id"),
    title: text_of(json, "title"),
    notice: text_of(json, "notice"),
    project: Project::from_json(project),
  }
}

///|
pub fn sample_index(json : Json) -> Array[(String, String)] raise ProjectError {
  match field(json, "samples") {
    Some(Array(items)) =>
      items.map(item => (text_of(item, "id"), text_of(item, "title")))
    _ => raise invalid("samples is missing")
  }
}

///|
pub fn problem_counts(reply : Json) -> Map[String, Int32] {
  let counts : Map[String, Int32] = Map([])
  if field(reply, "frontendDiagnostics") is Some(Array(files)) {
    for file in files {
      if (field(file, "path"), field(file, "problems"))
        is (Some(String(path)), Some(Array(problems))) {
        counts[path] = counts.get(path).unwrap_or(0) + problems.length()
      }
    }
  }
  counts
}
