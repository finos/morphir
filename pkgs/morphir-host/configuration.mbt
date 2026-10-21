///|
fn primary_at(root : String) -> Bool raise {
  for candidate in @workspace.primary_paths("") {
    if @platform.kind(root + "/" + candidate) != 0 {
      return true
    }
  }
  @platform.kind(root + "/morphir-workspace.json") != 0 ||
  @platform.kind(root + "/morphir.json") != 0
}

///|
pub(all) struct Location {
  root : String
  invocation : String
  file : String?
}

///|
/// Discover an enclosing workspace. WASI discovery stays within preopened fd 3.
pub fn locate(path : String) -> Location raise {
  // CLI paths are portable and relative to cwd, on every target.
  let requested = @workspace.normalize(path)
  let base = @platform.cwd()
    .split("\\")
    .map(StringView::to_owned)
    .collect()
    .join("/")
  let full = if requested == "" { base } else { base + "/" + requested }
  let kind = @platform.kind(full)
  if kind != 1 && kind != 2 {
    raise @config.Invalid("Input does not exist or is unsupported: " + path)
  }
  let start = if kind == 1 { @workspace.parent(full) } else { full }
  let mut root = start
  let mut cursor = start
  let mut found = false
  while cursor != "" {
    if primary_at(cursor) {
      if !found {
        root = cursor
        found = true
      }
      // Prefer an enclosing workspace over a standalone member configuration.
      let mount = Mount::filesystem(cursor)
      for candidate in @workspace.primary_paths("") {
        if (mount.kind)(candidate) == 1 && candidate.has_suffix(".toml") {
          let document = @config.parse(
            (mount.read)(candidate),
            origin=candidate,
          )
          if document.get("workspace") is Some(_) {
            let relative_project = if root == cursor {
              ""
            } else {
              root[cursor.length() + 1:].to_owned()
            }
            let members = document.strings("workspace.members")
            let excluded = document.strings("workspace.exclude")
            if relative_project == "" ||
              (
                members.any(pattern => {
                  @workspace.matches(
                    @workspace.normalize(pattern),
                    relative_project,
                  )
                }) &&
                !excluded.any(pattern => {
                  @workspace.matches(
                    @workspace.normalize(pattern),
                    relative_project,
                  )
                })
              ) {
              root = cursor
            }
          }
        }
      }
      if (mount.kind)("morphir-workspace.json") == 1 {
        root = cursor
      }
    }
    // A WASI preopen has no parent and absolute filesystem roots terminate here.
    let next = @workspace.parent(cursor)
    if next == cursor || cursor == "." || next == "" {
      break
    }
    cursor = next
  }
  let invocation = if start == root {
    ""
  } else {
    start[root.length() + 1:].to_owned()
  }
  let file = if kind == 1 {
    Some(full[root.length() + 1:].to_owned())
  } else {
    None
  }
  { root, invocation, file, }
}

///|
fn external_configuration(
  candidates : Array[String],
  label : String,
) -> @config.Document raise {
  let found = []
  let seen = Map([])
  for path in candidates {
    if seen.contains(path) {
      continue
    }
    seen[path] = true
    let kind = @platform.kind(path)
    if kind != 0 {
      if kind != 1 {
        raise @config.Invalid("Configuration must be a regular file: " + path)
      }
      found.push(path)
    }
  }
  if found.length() > 1 {
    raise @config.Invalid(
      "Ambiguous " + label + " configuration: " + found.join(", "),
    )
  }
  match found {
    [path] if path.has_suffix(".toml") =>
      @config.parse(@platform.read(path), origin=path)
    [path] => raise @config.Invalid("Unsupported configuration format: " + path)
    _ => @config.empty()
  }
}

///|
#cfg(target="wasm")
pub fn configuration(
  _environment : Map[String, String],
) -> (@config.Document, @config.Document) raise {
  let system = external_configuration(
    [".morphir-host/system/morphir.toml", ".morphir-host/system/morphir.yaml"],
    "system",
  )
  let global = external_configuration(
    [".morphir-host/user/morphir.toml", ".morphir-host/user/morphir.yaml"],
    "global",
  )
  (system, global)
}

///|
#cfg(not(target="wasm"))
pub fn configuration(
  environment : Map[String, String],
) -> (@config.Document, @config.Document) raise {
  let home = environment
    .get("HOME")
    .filter(value => value != "")
    .unwrap_or(environment.get("USERPROFILE").unwrap_or(""))
  let appdata = environment.get("APPDATA").unwrap_or("")
  let xdg = environment.get("XDG_CONFIG_HOME").unwrap_or("")
  let config_dir = if appdata != "" {
    Some(appdata)
  } else if xdg.has_prefix("/") {
    Some(xdg)
  } else if home == "" {
    None
  } else if @platform.system_type() == "macos" {
    Some(home + "/Library/Application Support")
  } else {
    Some(home + "/.config")
  }
  let override_home = environment.get("MORPHIR_HOME").unwrap_or("")
  let morphir_home = if override_home != "" {
    Some(override_home)
  } else if home != "" {
    Some(home + "/.morphir")
  } else {
    None
  }
  let candidates = []
  for directory in [config_dir.map(path => path + "/morphir"), morphir_home] {
    if directory is Some(path) {
      candidates.push(path + "/morphir.toml")
      candidates.push(path + "/morphir.yaml")
    }
  }
  let system_root = environment
    .get("PROGRAMDATA")
    .map(p => p + "/morphir")
    .unwrap_or("/etc/morphir")
  (
    external_configuration(
      [system_root + "/morphir.toml", system_root + "/morphir.yaml"],
      "system",
    ),
    external_configuration(candidates, "global"),
  )
}
