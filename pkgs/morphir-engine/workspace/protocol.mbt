///|
fn object(value : Json) -> Map[String, Json] raise {
  match value {
    Object(fields) => fields
    _ => raise @config.Invalid("Expected discovery object")
  }
}

///|
fn required(fields : Map[String, Json], key : String) -> Json raise {
  match fields.get(key) {
    Some(v) => v
    None => raise @config.Invalid("Missing discovery field: " + key)
  }
}

///|
fn string(value : Json) -> String raise {
  match value {
    String(s) => s
    _ => raise @config.Invalid("Expected discovery string")
  }
}

///|
pub fn Tree::from_json(value : Json) -> Tree raise {
  let entries = object(required(object(value), "entries"))
  let files = Map([])
  let dirs = Map::from_array([("", true)])
  for path, entry in entries {
    let normalized = normalize(path)
    if normalized != path && !(path == "." && normalized == "") {
      raise @config.Invalid("Noncanonical discovery path: " + path)
    }
    let fields = object(entry)
    match string(required(fields, "kind")) {
      "file" => files[normalized] = string(required(fields, "text"))
      "directory" => dirs[normalized] = true
      "symlink" =>
        raise @config.Invalid(
          "Protocol v1 requires materialized symlinks: " + path,
        )
      _ => raise @config.Invalid("Unknown discovery entry kind")
    }
  }
  let directories = dirs.keys().collect()
  directories.sort()
  { files, directories, }
}

///|
fn mount_document(value : Json?) -> @config.Document raise {
  match value {
    None | Some(Null) => @config.empty()
    Some(value) => {
      let tree = Tree::from_json(value)
      match primary(tree, "") {
        Some(path) => @config.parse(tree.files[path], origin=path)
        None => @config.empty()
      }
    }
  }
}

///|
/// Discovery protocol 0.1.0. Numeric v1 requests remain readable at this compatibility boundary.
pub fn discover_request(request : Json) -> Workspace raise {
  let fields = object(request)
  match required(fields, "protocolVersion") {
    String("0.1.0") => ()
    Number(n, ..) if n == 1 => ()
    _ => raise @config.Invalid("Unsupported workspace discovery protocol")
  }
  let tree = Tree::from_json(required(fields, "developmentRoot"))
  let environment = Map([])
  if fields.get("environment") is Some(value) {
    for key, value in object(value) {
      environment[key] = string(value)
    }
  }
  let overlay = match fields.get("cliOverlay") {
    None | Some(Null) => @config.empty()
    Some(value) => @config.from_json(value, origin="CLI")
  }
  discover(
    tree,
    system=mount_document(fields.get("systemConfig")),
    global=mount_document(fields.get("morphirHome")),
    environment~,
    overlay~,
  )
}
