///|
/// One Elm corpus project: its `morphir.json` text, unchanged, and its Elm sources. `elm_projects` in the
/// generated `projects.mbt` lists them.
priv struct ElmProject {
  name : String
  manifest : String // the corpus morphir.json, byte for byte
  sources : Array[(String, String)] // path relative to the source directory, content
}

///|
/// The source directory of `project`, from its `morphir.json` (`src` when it has none).
fn source_directory(project : ElmProject) -> String raise {
  match @json.parse(project.manifest) {
    Object(fields) =>
      match fields.get("sourceDirectory") {
        Some(String(text)) => text
        _ => "src"
      }
    _ => fail("\{project.name}: morphir.json is not an object")
  }
}

///|
/// Compiles `project` through the engine with the Elm provider, from its unchanged `morphir.json`, and generates
/// it with `backend`.
fn generate(
  project : ElmProject,
  backend : String,
) -> @engine.ContentReport raise {
  let directory = source_directory(project)
  let files = Map::from_array([("morphir.json", project.manifest)])
  for source in project.sources {
    files[directory + "/" + source.0] = source.1
  }
  let engine = @engine.Engine::new()..register_source_provider(
    @adapter.provider(),
  )
  let host = @engine.Host::memory(files)
  let request = {
    ..@engine.Request::new(),
    overlay: "[pipeline]\nbackend = '\{backend}'\nvalidation = 'source-only'\n"
    |> @config.parse(),
  }
  let plan = engine.plan(
    host,
    @workspace.discover({ files, directories: ["", directory], }),
    request,
  )
  // A pipe cannot feed `plan` here: it is the second argument of the method, after the engine.
  engine.execute_content(plan, fn(path, _) raise {
    @data.Text((host.read)(path))
  })
}

///|
/// The files of the one generated project of `report`, with paths relative to the project root and binary
/// content as an array of byte values.
fn generated_files(name : String, report : @engine.ContentReport) -> Json raise {
  guard report.projects is [project] else {
    fail(
      "\{name}: expected one generated project, got \{report.projects.length()}",
    )
  }
  let prefix = project.root + "/"
  let files : Array[Json] = []
  for artifact in report.artifacts {
    if !artifact.path.has_prefix(prefix) {
      fail("\{name}: \{artifact.path} is outside \{project.root}")
    }
    let path = artifact.path.unsafe_substring(
      start=prefix.length(),
      end=artifact.path.length(),
    )
    let content : Json = match artifact.content {
      Text(text) => Json::string(text)
      Binary(bytes) =>
        Json::array(
          bytes.to_array().map(byte => Json::number(byte.to_int().to_double())),
        )
    }
    files.push({ "path": path, "content": content })
  }
  Json::array(files)
}

///|
/// Checks the report of one project and backend against `gaps`. A successful report must not be pinned and adds
/// the project's files to `outputs` under `field`. A failed report must be pinned in `gaps`, and its first diagnostic
/// must start with the pinned text. A pinned report, or a successful report in `build_gaps`, adds the gap to
/// `pinned`.
fn check(
  name : String,
  backend : String,
  report : @engine.ContentReport,
  field : String,
  outputs : Array[Json],
  pinned : Array[Json],
) -> Unit raise {
  let key = name + "/" + backend
  match (report.successful(), gaps.get(key)) {
    (true, None) =>
      match build_gaps.get(key) {
        Some(reason) =>
          pinned.push({ "name": name, "code": "build", "detail": reason })
        None =>
          outputs.push(
            Json::object(
              Map::from_array([
                ("name", Json::string(name)),
                (field, generated_files(name, report)),
              ]),
            ),
          )
      }
    (true, Some(_)) => fail("\{key}: the engine generates it; remove its gap")
    (false, Some(code)) => {
      let first = report.diagnostics[0]
      if !first.message.has_prefix(code) {
        fail("\{key}: expected \{code}, got [\{first.stage}] \{first.message}")
      }
      pinned.push({ "name": name, "code": code, "detail": first.message })
    }
    (false, None) =>
      fail(
        key +
        ":\n" +
        report.diagnostics
        .map(d => d.path + " [" + d.stage + "] " + d.message)
        .join("\n"),
      )
  }
}

///|
/// Compiles every corpus project through the engine and generates MoonBit and Elm. A failure raises, so that the
/// process exits non-zero.
fn main raise {
  let projects = elm_projects()
  let keys = gaps.keys().collect()
  keys.append(build_gaps.keys().collect())
  for key in keys {
    if !projects
      .iter()
      .any(p => key == p.name + "/moonbit" || key == p.name + "/elm") {
      fail("the gap \{key} names no project and backend")
    }
    if gaps.contains(key) && build_gaps.contains(key) {
      fail("the gap \{key} is in both maps")
    }
  }
  let libraries : Array[Json] = []
  let moonbit_gaps : Array[Json] = []
  let elm : Array[Json] = []
  let elm_gaps : Array[Json] = []
  for project in projects {
    check(
      project.name,
      "moonbit",
      generate(project, "moonbit"),
      "artifacts",
      libraries,
      moonbit_gaps,
    )
    check(project.name, "elm", generate(project, "elm"), "files", elm, elm_gaps)
  }
  println(
    (
      {
        "moonbit": libraries,
        "moonbitGaps": moonbit_gaps,
        "elm": elm,
        "elmGaps": elm_gaps,
      } : Json).stringify(),
  )
}
