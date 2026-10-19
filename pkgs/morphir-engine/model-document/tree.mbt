///|
/// A portable path inside a captured original inventory, never a host path.
pub struct OriginalPath(String) derive(Eq, Debug)

///|
pub extend OriginalPath with Eq::{equal, not_equal}

///|
pub extend OriginalPath with @debug.Debug::{to_repr}

///|
pub fn OriginalPath::parse(path : String) -> OriginalPath raise DocumentError {
  if path == "" || path.length() > 4096 {
    raise InvalidFilename
  }
  let normalized = @workspace.normalize(path) catch {
    _ => raise InvalidFilename
  }
  if normalized != path {
    raise InvalidFilename
  }
  let mut depth = 0
  for part in path.split("/") {
    depth += 1
    if depth > 128 {
      raise InvalidFilename
    }
    ignore(OriginalFilename::parse(part.to_owned()))
  }
  OriginalPath(path)
}

///|
pub fn OriginalPath::to_string(self : OriginalPath) -> String {
  let OriginalPath(path) = self
  path
}

///|
/// The captured inventory owns bytes and explicit directories. It makes no
/// claim about filesystem entries that a picker or provider did not supply.
pub struct OriginalTree {
  format_version : @version.FormatVersion
  priv files : Map[String, Bytes]
  priv directories : Array[String]
} derive(Eq, Debug)

///|
pub extend OriginalTree with Eq::{equal, not_equal}

///|
pub extend OriginalTree with @debug.Debug::{to_repr}

///|
pub fn OriginalTree::new(
  files : Map[String, Bytes],
  directories : Array[String],
  format_version : @version.FormatVersion,
) -> OriginalTree raise DocumentError {
  format_version.check_supported() catch {
    _ => raise InvalidVersion
  }
  let paths = files.keys().collect()
  if paths.is_empty() {
    raise TooLarge
  }
  validate_inventory_paths(paths, directories)
  let mut bytes = 0
  for path in paths {
    if files[path].length() > 16777216 - bytes {
      raise TooLarge
    }
    bytes += files[path].length()
  }
  let owned : Map[String, Bytes] = Map([])
  for path in paths {
    owned[path] = copy_bytes(files[path])
  }
  let directories = directories.copy()
  directories.sort()
  { format_version, files: owned, directories, }
}

///|
/// Validate a portable captured inventory before adapters read or publish bytes.
/// This checks paths only and makes no claim about model format or provenance.
pub fn validate_inventory_paths(
  files : Array[String],
  directories : Array[String],
) -> Unit raise DocumentError {
  if files.length() > 4096 || directories.length() > 4096 {
    raise TooLarge
  }
  let folded_files : Map[String, Bool] = Map([])
  let spelling : Map[String, String] = Map([])
  let seen_directories : Map[String, Bool] = Map([])
  let mut path_units = 0
  fn check_path(path : String) -> Unit raise DocumentError {
    ignore(OriginalPath::parse(path))
    path_units += path.length()
    if path_units > 1048576 {
      raise TooLarge
    }
    let mut parent = ""
    for part in path.split("/") {
      parent = if parent == "" {
        part.to_owned()
      } else {
        parent + "/" + part.to_owned()
      }
      let key = parent.to_lower()
      if folded_files.contains(key) ||
        (spelling.get(key) is Some(previous) && previous != parent) {
        raise InvalidFilename
      }
      spelling[key] = parent
    }
  }
  let paths = files.copy()
  paths.sort()
  for path in paths {
    check_path(path)
    let key = path.to_lower()
    if folded_files.contains(key) {
      raise InvalidFilename
    }
    folded_files[key] = true
  }
  for path in directories {
    check_path(path)
    let key = path.to_lower()
    if seen_directories.contains(key) {
      raise InvalidFilename
    }
    seen_directories[key] = true
  }
}

///|
pub fn OriginalTree::copy_files(self : OriginalTree) -> Map[String, Bytes] {
  self.files.map(fn(_, bytes) { copy_bytes(bytes) })
}

///|
pub fn OriginalTree::directory_paths(self : OriginalTree) -> Array[String] {
  self.directories.copy()
}

///|
/// Reuse the existing artifact download/archive adapter at the effect boundary.
pub fn OriginalTree::download(self : OriginalTree) -> Json {
  let paths = self.files.keys().collect()
  paths.sort()
  {
    "files": paths.map(path => {
      (
        {
          "path": path,
          "content": @base64.encode(self.files[path][:]),
          "binary": true,
          "encoding": "base64",
        } : Json)
    }),
    "directories": self.directories,
  }
}

///|
fn tree_from_reply(
  value : Json,
  source_version_value : Json,
) -> OriginalTree raise DocumentError {
  guard value is Object(fields) &&
    fields.length() == 5 &&
    fields.get("codec") == Some(Json::string("morphir-yaml")) else {
    raise InvalidReply
  }
  let version_text = string(field(value, "formatVersion"))
  if source_version_value != Json::string(version_text) {
    raise InvalidVersion
  }
  guard field(value, "files") is Array(entries) &&
    entries.length() <= @data.model_tree_file_limit &&
    field(value, "directories") is Array(raw_directories) &&
    raw_directories.length() <= 4096 else {
    raise TooLarge
  }
  let files : Map[String, Bytes] = Map([])
  let mut total = 0
  for entry in entries {
    guard entry is Object(fields) && fields.length() == 2 else {
      raise InvalidReply
    }
    let path = string(field(entry, "path"))
    ignore(OriginalPath::parse(path))
    if files.contains(path) {
      raise InvalidFilename
    }
    let encoded = string(field(entry, "contentBase64"))
    if encoded.length() > (16777216 - total + 2) / 3 * 4 {
      raise TooLarge
    }
    let bytes = @base64.decode(encoded[:]) catch { _ => raise InvalidBytes }
    if @base64.encode(bytes[:]) != encoded {
      raise InvalidBytes
    }
    if bytes.length() > 16777216 - total {
      raise TooLarge
    }
    total += bytes.length()
    files[path] = bytes
  }
  OriginalTree::new(
    files,
    raw_directories.map(string),
    source_version(version_text),
  )
}
