///|
/// A path in the writable inventory, never an OS locator. Tool directories are
/// omitted outside model trees; the root recovery directory is always reserved.
pub struct RelativePath(String) derive(Eq)

///|
pub extend RelativePath with Eq::{equal, not_equal}

///|
pub fn RelativePath::parse(path : String) -> RelativePath raise Invalid {
  let exact = @utf8.decode(@utf8.encode(path), ignore_bom=false) catch {
    _ => raise Invalid("workspace_files.path")
  }
  if exact != path {
    raise Invalid("workspace_files.path")
  }
  let parts = path.split("/").map(p => p.to_owned()).collect()
  if path == "" ||
    path.length() > 4096 ||
    parts.length() > 16 ||
    path.iter().any(c => c < ' ' || c == '\u007f' || c == '\\' || c == ':') ||
    parts.any(p => {
      p == "" || p == "." || p == ".." || @utf8.encode(p).length() > 255
    }) ||
    parts[0] == ".morphir-workspace-edit.lock" ||
    (
      parts[0] != "models" &&
      parts.any(p => {
        [
          ".git", "node_modules", "_build", ".mooncakes", ".idea", ".vscode", ".morphir-workspace-edit.lock",
        ].contains(p)
      })
    ) {
    raise Invalid("workspace_files.path")
  }
  RelativePath(path)
}

///|
pub fn RelativePath::to_string(self : RelativePath) -> String {
  let RelativePath(path) = self
  path
}

///|
/// Immutable bounded file contents. Native grants and disk baselines remain in
/// their host owner; possession of this value supplies no write authority.
pub struct Inventory {
  priv files : Map[String, Bytes]
}

///|
pub struct FileChanges {
  writes : Map[String, Bytes]
  deletes : Array[String]
  create_directories : Array[String]
  remove_directories : Array[String]
}

///|
fn parent(path : String) -> String {
  let parts = path.split("/").collect()
  parts[:parts.length() - 1].join("/")
}

///|
/// Derive the entire bounded batch from the host baseline. Directories that
/// were already empty remain; an inventory alone cannot request their deletion.
pub fn Inventory::difference(
  self : Inventory,
  candidate : Inventory,
  directories : Array[String],
) -> FileChanges raise Invalid {
  if directories.length() > 256 || !directories.contains("") {
    raise Invalid("workspace_files.directories")
  }
  let seen : Map[String, Bool] = Map([])
  for directory in directories {
    if directory != "" {
      ignore(RelativePath::parse(directory))
    }
    if seen.contains(directory) || self.files.contains(directory) {
      raise Invalid("workspace_files.directories")
    }
    seen[directory] = true
    if candidate.files.contains(directory) {
      raise Invalid("workspace_files.directories")
    }
  }
  for directory in directories {
    let mut ancestor = parent(directory)
    while ancestor != "" {
      if !seen.contains(ancestor) {
        raise Invalid("workspace_files.directories")
      }
      ancestor = parent(ancestor)
    }
  }
  let occupied : Map[String, Bool] = Map([])
  for path in self.files.keys() {
    let mut ancestor = parent(path)
    while ancestor != "" {
      if !seen.contains(ancestor) {
        raise Invalid("workspace_files.directories")
      }
      occupied[ancestor] = true
      ancestor = parent(ancestor)
    }
  }
  let writes = candidate.files.filter(fn(path, bytes) {
    self.files.get(path) != Some(bytes)
  })
  let deletes = self.files
    .keys()
    .filter(path => !candidate.files.contains(path))
    .collect()
  deletes.sort_by(fn(a, b) { a.lexical_compare(b) })
  let next_occupied : Map[String, Bool] = Map([])
  let create_set : Map[String, Bool] = Map([])
  for path in candidate.files.keys() {
    let mut ancestor = parent(path)
    while ancestor != "" {
      if self.files.contains(ancestor) {
        raise Invalid("workspace_files.directories")
      }
      next_occupied[ancestor] = true
      if !seen.contains(ancestor) {
        create_set[ancestor] = true
      }
      ancestor = parent(ancestor)
    }
  }
  let creates = create_set.keys().collect()
  creates.sort_by(fn(a, b) {
    let depth = a.split("/").count().compare(b.split("/").count())
    if depth == 0 {
      a.lexical_compare(b)
    } else {
      depth
    }
  })
  let preserve : Map[String, Bool] = Map([])
  for directory in directories {
    if directory == "" || occupied.contains(directory) {
      continue
    }
    let mut ancestor = directory
    while ancestor != "" {
      preserve[ancestor] = true
      ancestor = parent(ancestor)
    }
  }
  let removable : Map[String, Bool] = Map([])
  for directory in directories {
    if directory != "" &&
      occupied.contains(directory) &&
      !next_occupied.contains(directory) &&
      !preserve.contains(directory) {
      removable[directory] = true
    }
  }
  let removes = removable
    .keys()
    .filter(path => {
      let mut ancestor = parent(path)
      while ancestor != "" {
        if removable.contains(ancestor) {
          return false
        }
        ancestor = parent(ancestor)
      }
      true
    })
    .collect()
  removes.sort_by(fn(a, b) { a.lexical_compare(b) })
  if directories.filter(path => !removable.contains(path)).length() +
    creates.length() >
    256 {
    raise Invalid("workspace_files.directories")
  }
  {
    writes: writes.map(fn(_, bytes) {
      Bytes::from_array(bytes.iter().collect())
    }),
    deletes,
    create_directories: creates,
    remove_directories: removes,
  }
}

///|
pub fn Inventory::new(files : Map[String, Bytes]) -> Inventory raise Invalid {
  if files.length() > 2000 {
    raise Invalid("workspace_files.inventory_limit")
  }
  let mut remaining = 16 * 1024 * 1024
  for path, bytes in files {
    ignore(RelativePath::parse(path))
    remaining -= @utf8.encode(path).length()
    if remaining < 0 || bytes.length() > remaining {
      raise Invalid("workspace_files.inventory_limit")
    }
    remaining -= bytes.length()
    let parts = path.split("/").map(p => p.to_owned()).collect()
    for depth in 1..<parts.length() {
      if files.contains(parts[:depth].join("/")) {
        raise Invalid("workspace_files.path")
      }
    }
  }
  {
    files: files.map(fn(_, bytes) { Bytes::from_array(bytes.iter().collect()) }),
  }
}

///|
pub fn Inventory::files(self : Inventory) -> Map[String, Bytes] {
  self.files.map(fn(_, bytes) { Bytes::from_array(bytes.iter().collect()) })
}

///|
pub fn Inventory::encode(self : Inventory) -> Bytes raise Invalid {
  let entries : Map[String, Json] = Map([])
  for path, bytes in self.files {
    entries[path] = try {
      let text = @utf8.decode(bytes, ignore_bom=false)
      if @utf8.encode(text) != bytes {
        raise Invalid("workspace_files.utf8")
      }
      Json::string(text)
    } catch {
      _ => { "encoding": "base64", "content": @base64.encode(bytes[:]) }
    }
  }
  let bytes = @utf8.encode(
    ({ "version": 1, "files": Json::object(entries) } : Json).stringify(),
  )
  if bytes.length() > TRANSFER_LIMIT {
    raise Invalid("workspace_files.inventory_limit")
  }
  bytes
}

///|
pub fn Inventory::decode(bytes : Bytes) -> Inventory raise Invalid {
  if bytes.length() > TRANSFER_LIMIT {
    raise Invalid("workspace_files.inventory_limit")
  }
  let value = @wire.parse_bounded(
    @utf8.decode(bytes, ignore_bom=false),
    max_depth=8,
    max_nodes=16016,
    max_string_units=TRANSFER_LIMIT,
  ) catch {
    _ => raise Invalid("workspace_files.inventory")
  }
  guard value is Object(fields) &&
    fields.length() == 2 &&
    fields.get("version") == Some(Json::number(1)) &&
    fields.get("files") is Some(Object(entries)) &&
    entries.length() <= 2000 else {
    raise Invalid("workspace_files.inventory")
  }
  let files : Map[String, Bytes] = Map([])
  let mut remaining = 16 * 1024 * 1024
  for path, value in entries {
    ignore(RelativePath::parse(path))
    remaining -= @utf8.encode(path).length()
    if remaining < 0 {
      raise Invalid("workspace_files.inventory_limit")
    }
    let bytes = match value {
      String(text) => @utf8.encode(text)
      Object(record) if record.length() == 2 &&
        record.get("encoding") == Some(Json::string("base64")) &&
        record.get("content") is Some(String(encoded)) => {
        if encoded.length() > (remaining + 2) / 3 * 4 {
          raise Invalid("workspace_files.inventory_limit")
        }
        let bytes = @base64.decode(encoded) catch {
          _ => raise Invalid("workspace_files.inventory")
        }
        if @base64.encode(bytes[:]) != encoded {
          raise Invalid("workspace_files.inventory")
        }
        bytes
      }
      _ => raise Invalid("workspace_files.inventory")
    }
    if bytes.length() > remaining {
      raise Invalid("workspace_files.inventory_limit")
    }
    remaining -= bytes.length()
    files[path] = bytes
  }
  Inventory::new(files)
}
