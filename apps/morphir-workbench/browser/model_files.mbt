///|
let model_index_path : String = ".morphir/workbench-models.json"

///|
struct StoredModels {
  files : Map[String, @document.SourceCodec]
  trees : Array[String]
}

///|
fn stored_models(files : @workspace_files.Files) -> StoredModels raise {
  guard files.read(model_index_path) is Some(source) else {
    if files.content(model_index_path) is Some(_) {
      raise @config.Invalid("The model file index must be text")
    }
    return { files: Map([]), trees: [], }
  }
  let value = @json.parse(source) catch {
    _ => raise @config.Invalid("The model file index is not valid JSON")
  }
  guard value is Object(fields) &&
    fields.length() == 3 &&
    fields.get("version") == Some(Json::number(1)) &&
    fields.get("files") is Some(Object(entries)) &&
    fields.get("trees") is Some(Array(trees)) else {
    raise @config.Invalid("Unsupported model file index")
  }
  let codecs : Map[String, @document.SourceCodec] = Map([])
  let roots : Array[String] = []
  for path, value in entries {
    ignore(@ids.SourcePath::parse(path))
    guard value is String(codec) else {
      raise @config.Invalid("Invalid model file codec")
    }
    codecs[path] = @document.SourceCodec::parse(codec) catch {
      _ => raise @config.Invalid("Unsupported model file codec")
    }
  }
  for value in trees {
    guard value is String(root) else {
      raise @config.Invalid("Invalid model tree root")
    }
    ignore(@ids.SourcePath::parse(root))
    if roots.any(other => {
        @discovery.within(root, other) || @discovery.within(other, root)
      }) {
      raise @config.Invalid("Overlapping model trees")
    }
    roots.push(root)
  }
  { files: codecs, trees: roots, }
}

///|
fn StoredModels::save(
  self : StoredModels,
  files : @workspace_files.Files,
) -> @workspace_files.Files raise {
  files.write(
    model_index_path,
    (
      {
        "version": 1,
        "files": Json::object(
          self.files.map(fn(_, codec) { Json::string(codec.to_string()) }),
        ),
        "trees": Json::array(self.trees.map(Json::string)),
      } : Json).stringify(indent=2) +
    "\n",
  )
}

///|
fn file_bytes(files : @workspace_files.Files, path : String) -> Bytes? {
  files
  .content(path)
  .map(content => {
    match content {
      Text(text) => @utf8.encode(text)
      Binary(bytes) => bytes
    }
  })
}

///|
/// Capture original bytes only after inspection succeeds. Colliding imports get
/// a separate folder, retaining the original filename for later downloads.
fn capture_model_files(before : Model, after : Model, msg : Msg) -> Model {
  if !workspace_writable(after) ||
    before.active != after.active ||
    !(msg is (Receive(_, _, "inspect", _) | ReceiveModel(_, _, _, "inspect", _))) ||
    after.document.current_revision() == before.document.current_revision() {
    return after
  }
  let file = after.document.original()
  let tree = after.document.original_tree()
  if file is None && tree is None {
    return after
  }
  let files = try {
    let index = stored_models(after.workspace_files)
    match (file, tree) {
      (Some(original), _) => {
        let filename = original.filename.to_string()
        let bytes = original.copy_bytes()
        let mut path = "models/" + filename
        let mut number = 2
        while after.workspace_files.content(path) is Some(_) &&
              file_bytes(after.workspace_files, path) != Some(bytes) {
          path = "models/import-" + number.to_string() + "/" + filename
          number += 1
        }
        let files = after.workspace_files.write_content(
          path,
          @data.Binary(bytes),
        )
        let codecs = index.files.copy()
        codecs[path] = original.codec
        { ..index, files: codecs, }.save(files).open(path)
      }
      (_, Some(original)) => {
        let originals = original.copy_files()
        let same = index.trees
          .iter()
          .find_first(root => {
            let paths = after.workspace_files
              .paths()
              .filter(path => @discovery.within(root, path))
            paths.length() == originals.length() &&
            originals
            .iter()
            .all(entry => {
              file_bytes(after.workspace_files, root + "/" + entry.0) ==
              Some(entry.1)
            })
          })
        let mut root = same.unwrap_or("models/model")
        let mut number = 2
        while same is None &&
              after.workspace_files
              .paths()
              .any(path => {
                @discovery.within(root, path) || @discovery.within(path, root)
              }) {
          root = "models/model-" + number.to_string()
          number += 1
        }
        let updates : Map[String, @data.Content] = Map([])
        for path, bytes in originals {
          updates[root + "/" + path] = @data.Binary(bytes)
        }
        let files = after.workspace_files.write_all(updates)
        let roots = if index.trees.contains(root) {
          index.trees
        } else {
          index.trees + [root]
        }
        let opened = if originals.contains("manifest.yaml") {
          "manifest.yaml"
        } else {
          "manifest.yml"
        }
        { ..index, trees: roots, }.save(files).open(root + "/" + opened)
      }
      _ => after.workspace_files
    }
  } catch {
    @config.Invalid(message) =>
      return refused_model_capture(before, after, message)
    error => return refused_model_capture(before, after, error.to_string())
  }
  with_workspace_files(after, files)
}

///|
fn refused_model_capture(
  before : Model,
  after : Model,
  reason : String,
) -> Model {
  let document = match before.document.opening() {
    Some(attempt) => before.document.reject(attempt)
    None => before.document
  }
  let status = "The model could not be added to workspace files: " + reason
  note(
    {
      ..after,
      document,
      model_revision: before.model_revision,
      selected: before.selected,
      query: before.query,
      history: before.history,
      busy: false,
      status,
    },
    "Import",
    @bottom_panel.Error,
    status,
  )
}

///|
fn codec_for_model_path(path : String) -> @document.SourceCodec? {
  let path = path.to_lower()
  if path.has_suffix(".json") {
    Some(@document.SourceCodec::MorphirJson)
  } else if path.has_suffix(".yaml") || path.has_suffix(".yml") {
    Some(@document.SourceCodec::MorphirYaml)
  } else if path.has_suffix(".ionb") {
    Some(@document.SourceCodec::IonBinary)
  } else if path.has_suffix(".ion") {
    Some(@document.SourceCodec::IonText)
  } else {
    None
  }
}

///|
/// Reopen through the existing captured-original inspection lifecycle. The
/// index retains an explicitly chosen codec and the inventory root of YAML trees.
fn open_model_file(
  model : Model,
  path : String,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd)? {
  if !uses_file_projects(model) {
    return None
  }
  let selection = try {
    let index = stored_models(model.workspace_files)
    let root = index.trees
      .iter()
      .find_first(root => @discovery.within(root, path))
    if root is Some(root) {
      let files = model.workspace_files
        .paths()
        .filter(p => @discovery.within(root, p))
        .map(p => {
          (
            {
              "path": p[root.length() + 1:].to_owned(),
              "contentBase64": @base64.encode(
                file_bytes(model.workspace_files, p).unwrap()[:],
              ),
            } : Json)
        })
      ({ "kind": "selected-tree", "files": Json::array(files) } : Json)
    } else {
      let codec = match index.files.get(path) {
        Some(codec) => Some(codec)
        None =>
          if path.has_prefix("models/") {
            codec_for_model_path(path)
          } else {
            None
          }
      }
      guard codec is Some(codec) &&
        file_bytes(model.workspace_files, path) is Some(bytes) else {
        return None
      }
      (
        {
          "kind": "selected",
          "filename": path.split("/").last().unwrap_or("").to_owned(),
          "codec": codec.to_string(),
          "contentBase64": @base64.encode(bytes[:]),
        } : Json)
    }
  } catch {
    @config.Invalid(message) =>
      return Some(
        (note(model, "Model", @bottom_panel.Warning, message), @cmd.none),
      )
    _ => return None
  }
  if model.busy {
    return Some(({ ..model, status: busy_reason, }, @cmd.none))
  }
  match model.document.begin(host_retention(model)) {
    Started(document, attempt) =>
      Some(
        update_core(
          { ..model, document, doc: Model, worksheet: false, },
          Imported(attempt, selection.stringify()),
          emit,
        ),
      )
    _ =>
      Some(
        (
          {
            ..model,
            status: "Finish the retained execution before opening another model",
          },
          @cmd.none,
        ),
      )
  }
}

///|
fn move_model_file_index(
  before : @workspace_files.Files,
  changed : @workspace_files.Files,
  path : String,
  replacement : String?,
) -> @workspace_files.Files raise {
  if path == model_index_path {
    return changed
  }
  let index = stored_models(before) catch { _ => return changed }
  guard index.files.get(path) is Some(codec) else { return changed }
  let files = index.files.copy()
  files.remove(path)
  if replacement is Some(next) {
    files[next] = codec
  }
  { ..index, files, }.save(changed)
}

///|
fn original_model_files_present(
  model : Model,
  files : @workspace_files.Files,
) -> Bool {
  let index = stored_models(files) catch { _ => return false }
  match (model.document.original(), model.document.original_tree()) {
    (Some(original), _) => {
      let bytes = original.copy_bytes()
      index.files
      .iter()
      .any(entry => {
        entry.1 == original.codec && file_bytes(files, entry.0) == Some(bytes)
      })
    }
    (_, Some(original)) =>
      index.trees.any(root => {
        original
        .copy_files()
        .iter()
        .all(entry => file_bytes(files, root + "/" + entry.0) == Some(entry.1))
      })
    _ => false
  }
}
