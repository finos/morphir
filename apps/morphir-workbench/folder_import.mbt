///|
let max_folder_files : Int32 = 2000

///|
let max_folder_bytes : Int32 = 16 * 1024 * 1024

///|
fn folder_failure(code : String, text : String) -> Json {
  @wire.obj([
    ("success", Json::boolean(false)),
    ("message", @wire.text(code + ": " + text)),
    ("code", @wire.text(code)),
    ("stage", @wire.text("import")),
  ])
}

///|
/// The common leading folder of every path, as a browser folder picker gives (`rentals/morphir.json`), or "".
fn common_folder(paths : Array[String]) -> String {
  guard paths is [first, ..] else { return "" }
  guard first.find("/") is Some(slash) else { return "" }
  let prefix = first.unsafe_substring(start=0, end=slash + 1)
  if paths.iter().all(p => p.has_prefix(prefix)) {
    prefix
  } else {
    ""
  }
}

///|
/// A source directory without a leading `./` and trailing `/`: `./elm-src/` is `elm-src`.
fn normalized_directory(text : String) -> String {
  let mut directory = text
  while directory.strip_prefix("./") is Some(rest) {
    directory = rest.to_owned()
  }
  while directory.strip_suffix("/") is Some(rest) {
    directory = rest.to_owned()
  }
  directory
}

///|
/// Maps a folder with a morphir.json to an Elm project request, with the engine's discovery rules
/// (`@workspace.discover`): name, sourceDirectory and exposedModules, and its warnings.
fn import_folder(request : Json) -> Json raise {
  let raw = @wire.array(@wire.field(request, "files"))
  fn too_large() -> Json {
    folder_failure(
      "workbench.folder_too_large", "Select a project folder with at most 2000 files and 16 MiB of files and paths",
    )
  }
  if raw.length() > max_folder_files {
    return too_large()
  }
  let entries : Array[(String, @data.Content)] = []
  let mut remaining = max_folder_bytes
  for file in raw {
    let path = @wire.string(@wire.field(file, "path"))
    remaining -= @utf8.encode(path).length()
    if remaining < 0 {
      return too_large()
    }
    let content = match @wire.field(file, "content") {
      String(text) => {
        if text.length() > remaining {
          return too_large()
        }
        remaining -= @utf8.encode(text).length()
        @data.Text(text)
      }
      Object(record) if record.length() == 2 &&
        record.get("encoding") == Some(Json::string("base64")) &&
        record.get("content") is Some(String(encoded)) => {
        if encoded.length() > (remaining + 2) / 3 * 4 {
          return too_large()
        }
        let bytes = @base64.decode(encoded) catch {
          _ =>
            return folder_failure(
              "workbench.folder_configuration",
              "Invalid binary folder entry: " + path,
            )
        }
        if @base64.encode(bytes[:]) != encoded {
          return folder_failure(
            "workbench.folder_configuration",
            "Invalid binary folder entry: " + path,
          )
        }
        remaining -= bytes.length()
        @data.Binary(bytes)
      }
      _ =>
        return folder_failure(
          "workbench.folder_configuration",
          "Invalid folder entry content: " + path,
        )
    }
    if remaining < 0 {
      return too_large()
    }
    entries.push((path, content))
  }
  let prefix = common_folder(entries.map(e => e.0))
  let files : Map[String, String] = Map([])
  let binary_files : Map[String, Bytes] = Map([])
  let invalid_paths : Array[String] = []
  for entry in entries {
    let path = entry.0.unsafe_substring(
      start=prefix.length(),
      end=entry.0.length(),
    )
    if (try
        @workspace.normalize(entry.0) == entry.0 &&
        @workspace.normalize(path) == path &&
        path != "" &&
        ({
          ignore(@ids.SourcePath::parse(path))
          true
        })
      catch {
        _ => false
      }) ==
      false {
      invalid_paths.push("Skipped " + path + ": not a valid source path")
      continue
    }
    if files.contains(path) || binary_files.contains(path) {
      return folder_failure(
        "workbench.folder_configuration",
        "Duplicate folder entry: " + path,
      )
    }
    match entry.1 {
      Text(text) => files[path] = text
      Binary(bytes) => binary_files[path] = bytes
    }
  }
  let workspace_files = @workspace_files.Files::new(files, binary_files~) catch {
    @config.Invalid(message) =>
      return folder_failure("workbench.folder_configuration", message)
    error =>
      return folder_failure("workbench.folder_configuration", error.to_string())
  }
  if @workspace.primary_paths("").any(path => files.contains(path)) ||
    files.contains("morphir-workspace.json") {
    let workspace = workspace_files.discover() catch {
      @config.Invalid(message) =>
        return folder_failure("workbench.folder_configuration", message)
      error =>
        return folder_failure(
          "workbench.folder_configuration",
          error.to_string(),
        )
    }
    return @wire.obj([
      ("success", Json::boolean(true)),
      ("workspace", workspace_files.to_json()),
      ("discovery", workspace.to_json()),
      (
        "warnings",
        Json::array((workspace.warnings + invalid_paths).map(@wire.text)),
      ),
      ("skipped", Json::number(invalid_paths.length().to_double())),
    ])
  }
  guard files.get("morphir.json") is Some(manifest_text) else {
    return folder_failure(
      "workbench.folder_without_morphir_json", "The folder has no morphir.json. Open a morphir-elm project folder, or add a morphir.json with name, sourceDirectory and exposedModules",
    )
  }
  // Discovery needs only the manifest: it maps name, sourceDirectory and exposedModules and gives the warnings.
  let workspace = @workspace.discover({
    files: Map([("morphir.json", manifest_text)]),
    directories: [""],
  }) catch {
    error =>
      return folder_failure("workbench.folder_configuration", error.to_string())
  }
  guard workspace.projects is [project, ..] else {
    return folder_failure(
      "workbench.folder_configuration", "No project in morphir.json",
    )
  }
  if project.error is Some(message) {
    return folder_failure("workbench.folder_configuration", message)
  }
  let name = project.document.text("project.name", project.name)
  // The reply must load as a project: the same package-name rule as the editor.
  ignore(
    package_name(name) catch {
      @wire.Invalid(_, message) =>
        return folder_failure("workbench.folder_configuration", message)
      error =>
        return folder_failure(
          "workbench.folder_configuration",
          error.to_string(),
        )
    },
  )
  let source = normalized_directory(
    project.document.text("project.source_directory", "src"),
  )
  let source_prefix = if source == "" || source == "." {
    ""
  } else {
    source + "/"
  }
  let warnings = workspace.warnings + invalid_paths
  let kept : Array[Json] = []
  let mut skipped = invalid_paths.length()
  for path, content in files {
    if path == "morphir.json" {
      continue
    }
    match path.strip_prefix(source_prefix) {
      Some(rest) if path.has_suffix(".elm") => {
        let target = "src/" + rest.to_owned()
        let valid = try {
          ignore(@ids.SourcePath::parse(target))
          true
        } catch {
          _ => false
        }
        if valid {
          kept.push(
            @wire.obj([
              ("path", @wire.text(target)),
              ("content", @wire.text(content)),
            ]),
          )
        } else {
          warnings.push("Skipped " + path + ": not a valid source path")
          skipped += 1
        }
      }
      _ => skipped += 1
    }
  }
  if kept.is_empty() {
    return folder_failure(
      "workbench.folder_without_sources",
      "No .elm file under the source directory " + source,
    )
  }
  @wire.obj([
    ("success", Json::boolean(true)),
    ("workspace", workspace_files.to_json()),
    (
      "project",
      @wire.obj([
        ("name", @wire.text(name)),
        ("languageId", @wire.text("elm")),
        (
          "exposedModules",
          Json::array(
            project.document.strings("project.exposed_modules").map(@wire.text),
          ),
        ),
        ("files", Json::array(kept)),
      ]),
    ),
    ("warnings", Json::array(warnings.map(@wire.text))),
    ("skipped", Json::number(skipped.to_double())),
  ])
}
