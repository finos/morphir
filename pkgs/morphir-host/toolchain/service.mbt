///|
pub let compiler_version : String = "0.10.15+943464bfa"

///|
fn absolute(host : Host, path : String) -> String {
  if path.has_prefix("/") ||
    path.has_prefix("\\") ||
    (path.length() > 1 && path[1] == ':') {
    path
  } else {
    join(host.cwd, path)
  }
}

///|
fn managed(host : Host) -> String raise {
  let base = match host.environment.get("MORPHIR_HOME") {
    Some(s) if s != "" => absolute(host, s)
    _ =>
      match
        host.environment
        .get("HOME")
        .unwrap_or(host.environment.get("USERPROFILE").unwrap_or("")) {
        s if s != "" => join(s, ".morphir")
        _ =>
          raise ToolchainError(
            "Set MORPHIR_HOME when the host has no user home",
          )
      }
  }
  join(
    join(base, "toolchains"),
    compiler_version + "-" + host.system + "-" + host.architecture,
  )
}

///|
fn explicit_home(host : Host, request : Json) -> String {
  let value = string(
    request,
    "home",
    fallback=host.environment.get("MORPHIR_MOON_HOME").unwrap_or(""),
  )
  if value == "" {
    ""
  } else {
    absolute(host, value)
  }
}

///|
fn discover(host : Host, request : Json) -> String? raise {
  let explicit = explicit_home(host, request)
  if explicit != "" {
    return Some(explicit)
  }
  let managed = managed(host)
  if (host.kind)(managed) != 0 {
    return Some(managed)
  }
  if host.environment.get("MOON_HOME") is Some(home) {
    if (host.kind)(executable(host, home, "moonc")) != 0 {
      return Some(home)
    }
  }
  let separator = if host.system == "windows" { ";" } else { ":" }
  for directory in host.environment.get("PATH").unwrap_or("").split(separator) {
    let directory = directory.to_owned().replace(old="\\", new="/")
    if directory == "" {
      continue
    }
    let parts = directory.split("/").map(StringView::to_owned).collect()
    if parts.length() > 1 {
      let home = parts[:parts.length() - 1].to_owned().join("/")
      if (host.kind)(executable(host, home, "moonc")) != 0 &&
        (host.kind)(join(home, "lib/core")) == 2 {
        return Some(absolute(host, home))
      }
    }
  }
  None
}

///|
fn validate(host : Host, home : String, timeout : Int32) -> Json raise {
  for name in ["moon", "moonc"] {
    if (host.kind)(executable(host, home, name)) == 0 {
      raise ToolchainError("Missing " + name + " in toolchain: " + home)
    }
  }
  if (host.kind)(join(home, "lib/core")) != 2 {
    raise ToolchainError("Missing matching core library in toolchain: " + home)
  }
  let version = execute(
    host,
    executable(host, home, "moonc"),
    ["-v"],
    host.cwd,
    home,
    timeout,
  )
  require_success(version, "Compiler version")
  if !string(version, "stdout").contains("v" + compiler_version + " ") {
    raise ToolchainError(
      "Compiler must match pinned version " + compiler_version,
    )
  }
  let directory = (host.temporary)()
  defer (remove_tree(host, directory) catch { _ => () })
  (host.write)(
    join(directory, "moon.mod"),
    "name = \"morphir/toolchain-smoke\"\nversion = \"0.0.0\"\n",
  )
  (host.write)(join(directory, "moon.pkg"), "pkgtype(kind: \"executable\")\n")
  (host.write)(join(directory, "main.mbt"), "fn main { println(42) }\n")
  let smoke = execute(
    host,
    executable(host, home, "moon"),
    ["run", ".", "--target", "wasm"],
    directory,
    home,
    timeout,
  )
  require_success(smoke, "Toolchain/core smoke compilation and execution")
  if string(smoke, "stdout").trim().to_owned() != "42" {
    raise ToolchainError("Toolchain smoke program returned unexpected output")
  }
  let moonx = (host.kind)(executable(host, home, "moonx")) == 1
  let operations = ["info", "compile", "run", "setup", "build"]
  if moonx {
    operations.push("exec")
  }
  object([
    ("protocolVersion", Json::number(1.0)),
    ("operations", Json::array(operations.map(Json::string))),
    (
      "targets",
      Json::array(["wasm", "wasm-gc", "js", "native"].map(Json::string)),
    ),
    ("supported", Json::boolean(true)),
    ("available", Json::boolean(true)),
    ("home", Json::string(home)),
    ("compilerVersion", Json::string(compiler_version)),
    ("validated", Json::boolean(true)),
    ("mode", Json::string("process")),
    ("moonx", Json::boolean(moonx)),
  ])
}

///|
fn acquisition_target(host : Host) -> String? {
  match (host.system, host.architecture) {
    ("macos", "arm64") => Some("darwin-aarch64")
    ("linux", "x64") => Some("linux-x86_64")
    _ => None
  }
}

///|
fn acquire(host : Host, home : String, timeout : Int32) -> Json raise {
  let target = match acquisition_target(host) {
    Some(target) => target
    None =>
      raise ToolchainError(
        "No pinned acquisition archive for " +
        host.system +
        "-" +
        host.architecture,
      )
  }
  // Exclusive lock and staging directories belong to this installation only.
  let parts = home
    .replace(old="\\", new="/")
    .split("/")
    .map(StringView::to_owned)
    .collect()
  make_directories(host, parts[:parts.length() - 1].to_owned().join("/"))
  let lock = home + ".lock"
  (host.mkdir)(lock)
  defer (remove_tree(host, lock) catch { _ => () })
  if (host.kind)(home) != 0 {
    return validate(host, home, timeout)
  }
  let staging = join(lock, "installation")
  (host.mkdir)(staging)
  let encoded = compiler_version.replace(old="+", new="%2B")
  let binary_url = "https://cli.moonbitlang.com/binaries/" +
    encoded +
    "/moonbit-" +
    target +
    ".tar.gz"
  let core_url = "https://cli.moonbitlang.com/cores/core-" + encoded + ".tar.gz"
  let receipts : Array[Json] = []
  for
    (name, url, destination, digest) in [
      ("tools.tar.gz", binary_url, staging, binary_digest(target)),
      ("core.tar.gz", core_url, join(staging, "lib"), core_digest),
    ] {
    let archive = join(lock, name)
    require_success(
      execute(
        host,
        "curl",
        [
          "--fail", "--location", "--silent", "--show-error", "--proto", "=https",
          "--proto-redir", "=https", "--output", archive, url,
        ],
        host.cwd,
        "",
        timeout,
      ),
      "Download " + name,
    )
    let hash = if host.system == "macos" {
      execute(host, "shasum", ["-a", "256", archive], host.cwd, "", timeout)
    } else {
      execute(host, "sha256sum", [archive], host.cwd, "", timeout)
    }
    require_success(hash, "Archive integrity")
    if !string(hash, "stdout").has_prefix(digest + " ") {
      raise ToolchainError("Archive SHA-256 mismatch: " + name)
    }
    require_success(
      execute(
        host,
        "tar",
        ["-xf", archive, "-C", destination],
        host.cwd,
        "",
        timeout,
      ),
      "Extract " + name,
    )
    receipts.push(
      object([("url", Json::string(url)), ("sha256", Json::string(digest))]),
    )
  }
  require_success(
    execute(
      host,
      "ln",
      ["-s", "moon", executable(host, staging, "moonx")],
      host.cwd,
      "",
      timeout,
    ),
    "Create moonx alias",
  )
  require_success(
    execute(
      host,
      "chmod",
      ["-R", "u+x", join(staging, "bin")],
      host.cwd,
      "",
      timeout,
    ),
    "Make tools executable",
  )
  require_success(
    execute(
      host,
      executable(host, staging, "moon"),
      ["bundle", "--all", "--warn-list", "-a"],
      join(staging, "lib/core"),
      staging,
      timeout,
    ),
    "Bundle matching core",
  )
  ignore(validate(host, staging, timeout))
  (host.write)(
    join(staging, "morphir-toolchain.json"),
    object([
      ("compilerVersion", Json::string(compiler_version)),
      ("archives", Json::array(receipts)),
    ]).stringify(),
  )
  check_cancelled(host)
  (host.rename)(staging, home)
  validate(host, home, timeout)
}

///|
/// Version 1 request protocol, shared by CLI and process embedding hosts.
pub fn Host::request(self : Host, request : Json) -> Json raise {
  check_cancelled(self)
  let operation = if string(request, "operation") == "compile" {
    "build"
  } else {
    string(request, "operation")
  }
  if !["info", "setup", "build", "run", "exec"].contains(operation) {
    raise ToolchainError("Unknown toolchain operation: " + operation)
  }
  let timeout = match field(request, "timeout") {
    Null => 120000
    Number(n, ..) if n >= 1.0 && n <= 600000.0 && n == n.to_int().to_double() =>
      n.to_int()
    _ =>
      raise ToolchainError(
        "Timeout must be an integer from 1 through 600000 milliseconds",
      )
  }
  if !self.process {
    if operation == "info" {
      return object([
        ("protocolVersion", Json::number(1.0)),
        ("operations", Json::array([Json::string("info")])),
        ("targets", Json::array([])),
        ("supported", Json::boolean(false)),
        ("available", Json::boolean(false)),
        ("mode", Json::string("process")),
      ])
    }
    raise ToolchainError(
      "Host does not provide process execution; supply an embedded or process toolchain provider",
    )
  }
  let home = discover(self, request)
  if operation == "info" && home is None {
    let operations = ["info"]
    if acquisition_target(self) is Some(_) {
      operations.push("setup")
    }
    return object([
      ("protocolVersion", Json::number(1.0)),
      ("mode", Json::string("process")),
      ("operations", Json::array(operations.map(Json::string))),
      (
        "targets",
        Json::array(["wasm", "wasm-gc", "js", "native"].map(Json::string)),
      ),
      ("supported", Json::boolean(true)),
      ("available", Json::boolean(false)),
      ("compilerVersion", Json::string(compiler_version)),
    ])
  }
  let selected = match home {
    Some(home) => {
      if operation == "setup" && (self.kind)(home) == 0 {
        if !(field(request, "consent") is True) {
          raise ToolchainError("Toolchain acquisition requires --yes")
        }
        ignore(acquire(self, home, timeout))
      }
      home
    }
    None if operation == "setup" => {
      if !(field(request, "consent") is True) {
        raise ToolchainError("Toolchain acquisition requires --yes")
      }
      let home = managed(self)
      ignore(acquire(self, home, timeout))
      home
    }
    None =>
      raise ToolchainError(
        "No MoonBit toolchain found; run morphir toolchain setup --yes",
      )
  }
  // An explicitly selected missing home is the requested installation destination.
  let info = validate(self, selected, timeout)
  if operation == "info" || operation == "setup" {
    return info
  }
  let target = string(request, "target", fallback="wasm")
  if !["wasm", "wasm-gc", "js", "native"].contains(target) {
    raise ToolchainError("Unsupported compilation target: " + target)
  }
  let directory = absolute(self, string(request, "directory", fallback="."))
  let arguments = match field(request, "args") {
    Null => []
    Array(items) =>
      items.map(fn(item) raise {
        match item {
          String(s) => s
          _ => raise ToolchainError("Program arguments must be strings")
        }
      })
    _ => raise ToolchainError("Program arguments must be an array")
  }
  let (program, args) = match operation {
    "build" =>
      (executable(self, selected, "moon"), ["build", "--target", target])
    "run" =>
      (
        executable(self, selected, "moon"),
        [
          "run",
          string(request, "package", fallback="."),
          "--target",
          target,
          "--",
        ] +
        arguments,
      )
    _ => {
      let script = string(request, "script")
      if script == "" {
        raise ToolchainError("toolchain exec requires a .mbtx script")
      }
      if (self.kind)(executable(self, selected, "moonx")) == 0 {
        raise ToolchainError("Selected toolchain does not provide moonx")
      }
      (executable(self, selected, "moonx"), [script, "--"] + arguments)
    }
  }
  let result = execute(self, program, args, directory, selected, timeout)
  object([
    ("toolchain", info),
    ("successful", Json::boolean(successful(result))),
    ("process", result),
  ])
}
