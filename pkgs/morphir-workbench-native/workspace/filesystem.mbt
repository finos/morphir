///|
pub(all) suberror Invalid {
  Rejected(String)
}

///|
extern "C" fn supported_c() -> Int32 = "morphir_workspace_supported"

///|
#borrow(path)
extern "C" fn canonical_c(path : Bytes) -> Bytes = "morphir_workspace_canonical"

///|
#borrow(path)
extern "C" fn open_c(path : Bytes) -> Int32 = "morphir_workspace_open"

///|
extern "C" fn close_c(fd : Int32) -> Unit = "morphir_workspace_close"

///|
#borrow(path)
extern "C" fn current_c(fd : Int32, path : Bytes) -> Int32 = "morphir_workspace_current"

///|
#borrow(path)
extern "C" fn list_c(fd : Int32, path : Bytes) -> Bytes = "morphir_workspace_list"

///|
#borrow(path)
extern "C" fn read_c(fd : Int32, path : Bytes, limit : Int32) -> Bytes = "morphir_workspace_read"

///|
pub fn supported() -> Bool {
  supported_c() == 1
}

///|
fn check(code : Int32) -> Unit raise Invalid {
  if code != 0 {
    raise Rejected(
      "workbench.workspace_" +
      (match code {
        1 => "unavailable"
        2 => "path"
        4 => "link_or_type"
        5 => "quota"
        6 => "changed"
        7 => "stale_root"
        _ => "io"
      }),
    )
  }
}

///|
fn cstring(path : String) -> Bytes raise Invalid {
  guard !path.contains("\u0000") else {
    raise Rejected("workbench.workspace_path")
  }
  let bytes = @utf8.encode(path[:])
  guard bytes.length() <= 4096 else {
    raise Rejected("workbench.workspace_path")
  }
  bytes + b"\x00"
}

///|
fn unpack(bytes : Bytes) -> Bytes raise Invalid {
  guard bytes.length() > 0 else { raise Rejected("workbench.workspace_io") }
  check(bytes[0].to_int())
  bytes[1:].to_owned()
}

///|
fn decoded(bytes : Bytes) -> String raise {
  @utf8.decode(bytes) catch {
    _ => raise Rejected("workbench.workspace_encoding")
  }
}

///|
/// Host-only authority, constructed from the native picker's result.
pub struct Root {
  priv fd : Int32
  priv canonical : Bytes
  priv mut closed : Bool
}

///|
pub fn Root::open(native_path : String) -> Root raise {
  let path = decoded(unpack(canonical_c(cstring(native_path))))
  let canonical = cstring(path)
  let fd = open_c(canonical)
  if fd < 0 {
    check(-fd)
  }
  { fd, canonical, closed: false, }
}

///|
pub fn Root::close(self : Root) -> Unit {
  if !self.closed {
    self.closed = true
    close_c(self.fd)
  }
}

///|
fn Root::current(self : Root) -> Unit raise Invalid {
  guard !self.closed else { raise Rejected("workbench.workspace_revoked") }
  check(current_c(self.fd, self.canonical))
}

///|
pub fn Root::read(
  self : Root,
  relative : String,
  limit~ : Int32 = 16 * 1024 * 1024,
) -> Bytes raise {
  self.current()
  let captured = unpack(read_c(self.fd, cstring(relative), limit))
  self.current()
  captured
}

///|
priv struct Entry {
  kind : String
  name : String
}

///|
fn Root::list(self : Root, path : String) -> Array[Entry] raise {
  self.current()
  let raw = decoded(unpack(list_c(self.fd, cstring(path))))
  self.current()
  let entries = raw
    .split("\u0000")
    .filter(s => s != "")
    .map(s => { kind: s[:1].to_owned(), name: s[1:].to_owned(), })
    .collect()
  entries.sort_by((a, b) => a.name.compare(b.name))
  entries
}

///|
/// Discovery input supplied by the host; it does not establish OS authority.
pub(all) struct Snapshot {
  tree : @engine.Tree
  files : Array[String]
}

///|
/// Trusted host access to a picked workspace. Renderer requests cannot create
/// this access or choose its callbacks. The service owns its retained lifetime.
pub(all) struct RootAccess {
  current : () -> Unit raise
  snapshot : () -> Snapshot raise
  read : (String) -> Bytes raise
  close : () -> Unit
}

///|
fn native_root(native_path : String) -> RootAccess raise {
  let root = Root::open(native_path)
  {
    current: fn() raise { root.current() },
    snapshot: fn() raise { root.snapshot() },
    read: fn(relative) raise { root.read(relative) },
    close: fn() { root.close() },
  }
}

///|
fn configuration(path : String) -> Bool {
  let name = path.split("/").last().unwrap_or("")
  [
    "morphir.toml", "morphir.yaml", "morphir.json", "morphir-workspace.json", "morphir.user.toml",
    "morphir.user.yaml",
  ].contains(name.to_owned()) ||
  path.has_suffix(".config/morphir/config.toml") ||
  path.has_suffix(".config/morphir/config.yaml") ||
  path.has_suffix(".config/morphir/config.user.toml") ||
  path.has_suffix(".config/morphir/config.user.yaml")
}

///|
fn Root::snapshot(self : Root) -> Snapshot raise {
  let directories = [""]
  let files : Array[String] = []
  let configs : Map[String, String] = Map([])
  let mut position = 0
  let mut entries = 0
  let mut bytes = 0
  while position < directories.length() {
    let path = directories[position]
    position += 1
    for entry in self.list(path) {
      entries += 1
      guard entries <= 4096 else { raise Rejected("workbench.workspace_quota") }
      if [".git", "node_modules", "_build", ".mooncakes", ".idea", ".vscode"].contains(
          entry.name,
        ) {
        continue
      }
      let relative = @engine.join(path, entry.name)
      guard entry.kind != "l" else {
        raise Rejected("workbench.workspace_link_or_type")
      }
      if entry.kind == "d" {
        guard directories.length() < 256 && relative.split("/").count() <= 16 else {
          raise Rejected("workbench.workspace_quota")
        }
        directories.push(relative)
      } else if entry.kind == "f" {
        files.push(relative)
        if configuration(relative) {
          let content = self.read(relative, limit=256 * 1024)
          bytes += content.length()
          guard bytes <= 2 * 1024 * 1024 else {
            raise Rejected("workbench.workspace_quota")
          }
          configs[relative] = decoded(content)
        }
      }
    }
  }
  files.sort()
  { tree: { files: configs, directories, }, files, }
}
