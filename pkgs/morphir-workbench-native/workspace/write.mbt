///|
/// Data captured through a granted root. This value alone grants no OS access.
pub(all) struct FileSnapshot {
  files : Map[String, Bytes]
  directories : Array[String]
}

///|
/// A bounded difference against the host's own snapshot, never a renderer's
/// claim about the previous disk contents.
pub(all) struct FileEdit {
  writes : Map[String, Bytes]
  deletes : Array[String]
  directories : Array[String]
  remove_directories : Array[String]
}

///|
pub(all) suberror WriteFailure {
  Uncertain(String)
}

///|
/// Kept separate from Root: a read-only folder grant cannot invoke writes.
pub struct WriteRoot {
  priv root : Root
}

///|
#borrow(packet)
extern "C" fn apply_files_c(
  fd : Int32,
  packet : Bytes,
  length : Int32,
  fault : Int32,
) -> Int32 = "morphir_workspace_apply_files"

///|
extern "C" fn lock_c(fd : Int32) -> Int32 = "morphir_workspace_lock"

///|
extern "C" fn unlock_c(fd : Int32, lock : Int32) -> Int32 = "morphir_workspace_unlock"

///|
/// Trusted host wiring calls this with the explicit write picker's result.
pub fn WriteRoot::open(native_path : String) -> WriteRoot raise {
  { root: Root::open(native_path), }
}

///|
pub fn WriteRoot::close(self : WriteRoot) -> Unit {
  self.root.close()
}

///|
fn scan_files(root : Root) -> (Array[String], Array[String]) raise {
  let directories = [""]
  let files : Array[String] = []
  let mut position = 0
  let mut entries = 0
  while position < directories.length() {
    let path = directories[position]
    position += 1
    for entry in root.list(path) {
      entries += 1
      if entries > 4096 {
        raise Rejected("workbench.workspace_quota")
      }
      let relative = @engine.join(path, entry.name)
      if omitted_path(relative) {
        continue
      }
      write_path(relative)
      if entry.kind == "d" {
        if directories.length() >= 256 || relative.split("/").count() > 16 {
          raise Rejected("workbench.workspace_quota")
        }
        directories.push(relative)
      } else if entry.kind == "f" {
        if files.length() >= 2000 {
          raise Rejected("workbench.workspace_quota")
        }
        files.push(relative)
      } else {
        raise Rejected("workbench.workspace_link_or_type")
      }
    }
  }
  files.sort()
  directories.sort()
  (files, directories)
}

///|
/// Cooperating CLI/native writers use the same exclusive lock. Individual reads
/// retain their descriptor-based link and locator checks.
pub fn WriteRoot::snapshot(self : WriteRoot) -> FileSnapshot raise {
  self.root.current()
  let lock = lock_c(self.root.fd)
  if lock < 0 {
    write_check(-lock)
  }
  defer (if unlock_c(self.root.fd, lock) != 0 {
    raise Uncertain("workbench.workspace_recovery")
  })
  let (paths, directories) = scan_files(self.root)
  let files : Map[String, Bytes] = Map([])
  let mut remaining = 16 * 1024 * 1024
  for path in paths {
    remaining -= @utf8.encode(path).length()
    if remaining < 0 {
      raise Rejected("workbench.workspace_quota")
    }
    let bytes = self.root.read(path, limit=remaining)
    remaining -= bytes.length()
    files[path] = bytes
  }
  let (again, current_directories) = scan_files(self.root)
  if paths != again || directories != current_directories {
    raise Rejected("workbench.workspace_changed")
  }
  self.root.current()
  { files, directories, }
}

///|
fn write_check(code : Int32) -> Unit raise {
  if code == 9 {
    raise Uncertain("workbench.workspace_recovery")
  }
  if code == 8 {
    raise Rejected("workbench.workspace_busy")
  }
  check(code)
}

///|
fn write_path(path : String) -> Unit raise {
  ignore(@filewire.RelativePath::parse(path)) catch {
    _ => raise Rejected("workbench.workspace_path")
  }
}

///|
// Build/editor directories are outside this inventory. Model trees retain
// arbitrary sidecar names, but the root writer's recovery directory is reserved.
fn omitted_path(path : String) -> Bool {
  @engine.within(".morphir-workspace-edit.lock", path) ||
  (
    !@engine.within("models", path) &&
    path
    .split("/")
    .any(part => {
      [
        ".git", "node_modules", "_build", ".mooncakes", ".idea", ".vscode", ".morphir-workspace-edit.lock",
      ].contains(part.to_owned())
    })
  )
}

///|
fn bounded_files(files : Map[String, Bytes]) -> Unit raise {
  if files.length() > 2000 {
    raise Rejected("workbench.workspace_quota")
  }
  let mut remaining = 16 * 1024 * 1024
  for path, bytes in files {
    write_path(path)
    remaining -= @utf8.encode(path).length()
    if remaining < 0 || bytes.length() > remaining {
      raise Rejected("workbench.workspace_quota")
    }
    remaining -= bytes.length()
  }
}

///|
fn file_packet(snapshot : FileSnapshot, edit : FileEdit) -> Bytes raise {
  bounded_files(snapshot.files)
  let candidate = snapshot.files.copy()
  for path in edit.deletes {
    candidate.remove(path)
  }
  for path, content in edit.writes {
    candidate[path] = content
  }
  bounded_files(candidate)
  let creates = edit.directories.filter(path => {
    !snapshot.directories.contains(path)
  })
  for path in edit.writes.keys() {
    let mut parent = @engine.parent(path)
    while parent != "" {
      if !snapshot.directories.contains(parent) && !creates.contains(parent) {
        creates.push(parent)
      }
      parent = @engine.parent(parent)
    }
  }
  creates.sort_by(fn(a, b) {
    let length = a.length().compare(b.length())
    if length == 0 {
      a.compare(b)
    } else {
      length
    }
  })
  let removes = edit.remove_directories.copy()
  removes.sort()
  let paths = edit.writes.keys().collect() + edit.deletes
  paths.sort_by(fn(a, b) {
    let a_config = a.has_suffix(".toml")
    let b_config = b.has_suffix(".toml")
    if a_config != b_config {
      if a_config {
        1
      } else {
        -1
      }
    } else if a_config {
      b.length().compare(a.length())
    } else {
      a.compare(b)
    }
  })
  if paths.length() > 4000 ||
    creates.length() > 256 ||
    removes.length() > 256 ||
    snapshot.directories.length() > 256 {
    raise Rejected("workbench.workspace_quota")
  }
  let seen : Map[String, Bool] = Map([])
  for path in paths + creates + removes {
    write_path(path)
  }
  for path in paths {
    if seen.contains(path) {
      raise Rejected("workbench.workspace_path")
    }
    seen[path] = true
    if edit.deletes.contains(path) && !snapshot.files.contains(path) {
      raise Rejected("workbench.workspace_changed")
    }
  }
  for i, root in removes {
    if !snapshot.directories.contains(root) ||
      removes.iter().take(i).any(other => @engine.within(other, root)) ||
      edit.writes.keys().any(path => @engine.within(root, path)) ||
      creates.any(path => @engine.within(root, path)) {
      raise Rejected("workbench.workspace_path")
    }
  }
  let retained = snapshot.directories.filter(path => {
    !removes.any(root => @engine.within(root, path))
  })
  let combined = retained.copy()
  for path in creates {
    if !combined.contains(path) {
      combined.push(path)
    }
  }
  if combined.length() > 256 {
    raise Rejected("workbench.workspace_quota")
  }
  let directories = snapshot.directories.filter(path => path != "")
  for path in directories {
    write_path(path)
  }
  let encoded = (paths + creates + removes + directories).map(path => {
    @utf8.encode(path)
  })
  let data_size = paths
    .iter()
    .fold(init=0, fn(size, path) {
      size +
      snapshot.files.get(path).map(bytes => bytes.length()).unwrap_or(0) +
      edit.writes.get(path).map(bytes => bytes.length()).unwrap_or(0)
    })
  let total = 20 +
    paths.length() * 12 +
    (creates.length() + removes.length() + directories.length()) * 4 +
    encoded.iter().fold(init=0, fn(size, bytes) { size + bytes.length() }) +
    data_size
  if total > 36 * 1024 * 1024 {
    raise Rejected("workbench.workspace_quota")
  }
  let output : FixedArray[Byte] = FixedArray::make(total, 0x00)
  let mut offset = 0
  fn number(value : Int32) -> Unit {
    for shift in [0, 8, 16, 24] {
      output[offset] = ((value >> shift) & 255).to_byte()
      offset += 1
    }
  }
  fn bytes(value : Bytes) -> Unit {
    for byte in value {
      output[offset] = byte
      offset += 1
    }
  }
  number(1)
  number(paths.length())
  number(creates.length())
  number(removes.length())
  number(directories.length())
  for i, path in paths {
    let old = snapshot.files.get(path)
    let next = edit.writes.get(path)
    number(encoded[i].length())
    number(old.map(bytes => bytes.length()).unwrap_or(-1))
    number(next.map(bytes => bytes.length()).unwrap_or(-1))
    bytes(encoded[i])
    if old is Some(old) {
      bytes(old)
    }
    if next is Some(next) {
      bytes(next)
    }
  }
  for path in creates + removes + directories {
    let path = @utf8.encode(path)
    number(path.length())
    bytes(path)
  }
  output.unsafe_reinterpret_as_bytes()
}

///|
pub fn WriteRoot::apply(
  self : WriteRoot,
  snapshot : FileSnapshot,
  edit : FileEdit,
) -> Unit raise {
  self.apply_with(snapshot, edit, -1)
}

///|
fn WriteRoot::apply_with(
  self : WriteRoot,
  snapshot : FileSnapshot,
  edit : FileEdit,
  fault : Int32,
) -> Unit raise {
  self.root.current()
  let packet = file_packet(snapshot, edit)
  write_check(apply_files_c(self.root.fd, packet, packet.length(), fault))
  self.root.current() catch {
    _ => raise Uncertain("workbench.workspace_stale_root")
  }
}
