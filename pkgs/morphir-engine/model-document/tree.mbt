///|
/// A portable path inside a captured original inventory, never a host path.
pub struct OriginalPath(String) derive(Eq, Debug)

///|
/// Connected originals use their own published path and inventory bounds.
pub(all) enum InventoryPathProfile {
  Local
  Connected
}

///|
pub extend OriginalPath with Eq::{equal, not_equal}

///|
pub extend OriginalPath with @debug.Debug::{to_repr}

///|
pub fn OriginalPath::parse(
  path : String,
  profile~ : InventoryPathProfile = Local,
) -> OriginalPath raise DocumentError {
  if path == "" ||
    path.length() > (if profile is Connected { 8000 } else { 4096 }) {
    raise InvalidFilename
  }
  if profile is Connected &&
    (@utf8.encode(path).length() > 16000 || path.iter().count() > 4000) {
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
    if depth > (if profile is Connected { 256 } else { 128 }) {
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
  priv storage : InventoryStorage
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
  if files.is_empty() {
    raise TooLarge
  }
  {
    format_version,
    storage: InventoryStorage::capture(files, directories, Local),
  }
}

///|
/// Validate a portable captured inventory before adapters read or publish bytes.
/// This checks paths only and makes no claim about model format or provenance.
pub fn validate_inventory_paths(
  files : Array[String],
  directories : Array[String],
  profile~ : InventoryPathProfile = Local,
) -> Unit raise DocumentError {
  if (
      profile is Local && (files.length() > 4096 || directories.length() > 4096)
    ) ||
    files.length() + directories.length() > 100064 {
    raise TooLarge
  }
  let folded_files : Map[String, Bool] = Map([])
  let spelling : Map[String, String] = Map([])
  let seen_directories : Map[String, Bool] = Map([])
  let mut path_units = 0
  fn check_path(path : String) -> Unit raise DocumentError {
    ignore(OriginalPath::parse(path, profile~))
    path_units += path.length()
    if path_units > (if profile is Connected { 67108864 } else { 1048576 }) {
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
  self.storage.copy_files()
}

///|
pub fn OriginalTree::directory_paths(self : OriginalTree) -> Array[String] {
  self.storage.directory_paths()
}

///|
/// Reuse the existing artifact download/archive adapter at the effect boundary.
pub fn OriginalTree::download(self : OriginalTree) -> Json {
  self.storage.download()
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
