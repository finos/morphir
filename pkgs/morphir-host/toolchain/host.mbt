///|
pub(all) suberror ToolchainError {
  ToolchainError(String)
}

///|
/// Effects are supplied by the embedding host. No engine dependency on processes.
pub(all) struct Host {
  execute : (String, Array[String], String, String, Int32) -> Json raise
  kind : (String) -> Int32 raise
  read : (String) -> String raise
  write : (String, String) -> Unit raise
  list : (String) -> Array[String] raise
  mkdir : (String) -> Unit raise
  remove_file : (String) -> Unit raise
  remove_dir : (String) -> Unit raise
  rename : (String, String) -> Unit raise
  temporary : () -> String raise
  environment : Map[String, String]
  cwd : String
  system : String
  architecture : String
  process : Bool
  cancelled : () -> Bool
}

///|
pub fn Host::platform() -> Host {
  {
    execute: @platform.process,
    kind: @platform.kind,
    read: @platform.read,
    write: @platform.write,
    list: @platform.list,
    mkdir: @platform.mkdir,
    remove_file: @platform.remove_file,
    remove_dir: @platform.remove_dir,
    rename: @platform.rename,
    temporary: @platform.temporary,
    environment: @platform.environment(),
    cwd: @platform.cwd(),
    system: @platform.system_type(),
    architecture: @platform.architecture(),
    process: @platform.process_supported(),
    cancelled: fn() { false },
  }
}

///|
fn field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn string(value : Json, key : String, fallback~ : String = "") -> String {
  match field(value, key) {
    String(text) => text
    _ => fallback
  }
}

///|
fn object(items : Array[(String, Json)]) -> Json {
  Json::object(Map::from_array(items))
}

///|
fn check_cancelled(host : Host) -> Unit raise {
  if (host.cancelled)() {
    raise ToolchainError("Cancelled")
  }
}

///|
fn execute(
  host : Host,
  program : String,
  args : Array[String],
  cwd : String,
  home : String,
  timeout : Int32,
) -> Json raise {
  check_cancelled(host)
  if !host.process {
    raise ToolchainError("Host does not provide process execution")
  }
  if [program, cwd, home].any(s => s.contains("\u0000")) ||
    args.any(s => s.contains("\u0000")) {
    raise ToolchainError("Process arguments must not contain NUL")
  }
  let result = (host.execute)(program, args, cwd, home, timeout)
  check_cancelled(host)
  if !(field(result, "stdout") is String(_)) ||
    !(field(result, "stderr") is String(_)) {
    raise ToolchainError("Invalid process host response")
  }
  match field(result, "exitCode") {
    Number(n, ..) if n >= -1.0 && n <= 255.0 && n == n.to_int().to_double() =>
      ()
    _ => raise ToolchainError("Invalid process host exit code")
  }
  result
}

///|
fn successful(result : Json) -> Bool {
  match field(result, "exitCode") {
    Number(n, ..) => n == 0.0
    _ => false
  }
}

///|
fn require_success(result : Json, operation : String) -> Unit raise {
  if !successful(result) {
    raise ToolchainError(
      operation + ": " + string(result, "stderr") + string(result, "stdout"),
    )
  }
}

///|
fn join(a : String, b : String) -> String {
  if a.has_suffix("/") || a.has_suffix("\\") {
    a + b
  } else {
    a + "/" + b
  }
}

///|
fn executable(host : Host, home : String, name : String) -> String {
  join(
    join(home, "bin"),
    name + (if host.system == "windows" { ".exe" } else { "" }),
  )
}

///|
fn make_directories(host : Host, path : String) -> Unit raise {
  if (host.kind)(path) == 2 {
    return
  }
  let parts = path
    .replace(old="\\", new="/")
    .split("/")
    .map(StringView::to_owned)
    .collect()
  if parts.length() > 1 {
    let parent = parts[:parts.length() - 1].to_owned().join("/")
    if parent != "" {
      make_directories(host, parent)
    }
  }
  (host.mkdir)(path)
}

///|
fn remove_tree(host : Host, path : String) -> Unit raise {
  match (host.kind)(path) {
    0 => ()
    2 => {
      for child in (host.list)(path) {
        if child == "" ||
          child == "." ||
          child == ".." ||
          child.contains("/") ||
          child.contains("\\") {
          raise ToolchainError("Invalid cleanup entry")
        }
        remove_tree(host, join(path, child))
      }
      (host.remove_dir)(path)
    }
    _ => (host.remove_file)(path)
  }
}
