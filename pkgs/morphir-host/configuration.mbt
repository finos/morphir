///|
pub(all) struct Location {
  root : String
  invocation : String
  file : String?
  directory : @lander_config.FileTreePath
  configuration_files : Map[String, String]
}

///|
fn configuration_platform() -> @lander_config.Platform {
  match @platform.system_type() {
    "windows" => Windows
    "macos" => MacOs
    _ => Linux
  }
}

///|
#cfg(target="wasm")
fn configuration_cwd() -> @lander_config.FileTreePath raise {
  @lander_config.FileTreePath::parse("/__morphir_wasi")
}

///|
#cfg(not(target="wasm"))
fn configuration_cwd() -> @lander_config.FileTreePath raise {
  @lander_config.FileTreePath::from_native(
    @platform.cwd(),
    configuration_platform(),
  )
}

///|
#cfg(target="wasm")
fn configuration_native(
  path : @lander_config.FileTreePath,
  machine : Bool,
) -> String? {
  let text = path.to_string()
  let base = "/__morphir_wasi"
  if text == base {
    return Some(".")
  }
  if text.has_prefix(base + "/") {
    return Some(text[base.length() + 1:].to_owned())
  }
  if machine {
    // Conventions own filenames. WASI maps machine requests into host mounts.
    let directory = if text == "/etc/morphir" ||
      text.has_prefix("/etc/morphir/") {
      ".morphir-host/system"
    } else {
      ".morphir-host/user"
    }
    return Some(
      if text.has_suffix("/morphir") {
        directory
      } else {
        directory + "/" + path.name().unwrap_or("")
      },
    )
  }
  None
}

///|
#cfg(not(target="wasm"))
fn configuration_native(
  path : @lander_config.FileTreePath,
  _machine : Bool,
) -> String? {
  Some(path.to_native(configuration_platform()))
}

///|
fn read_configuration_requests(
  initial : @lander_config.FileTree,
  requests : Array[@lander_config.FileRequest],
  files : Map[String, String],
  machine~ : Bool = false,
) -> @lander_config.FileTree raise {
  let mut tree = initial
  for request in requests {
    match request {
      ListDir(path) => {
        guard configuration_native(path, machine) is Some(native) else {
          tree = tree.with_missing(path)
          continue
        }
        let kind = @platform.kind(native)
        if kind == 0 {
          tree = tree.with_missing(path)
          continue
        }
        if kind != 2 {
          raise @config.Invalid(
            "Cannot list configuration directory: " + native,
          )
        }
        let entries = @platform.list(native).map(name => {
          let kind : @lander_config.EntryKind = match
            @platform.kind(native + "/" + name) {
            1 => File
            2 => Directory
            _ => Inaccessible
          }
          @lander_config.DirEntry::{ name, kind, }
        })
        tree = tree.with_listing(path, entries)
      }
      ReadFile(path) => {
        guard configuration_native(path, machine) is Some(native) else {
          tree = tree.with_missing(path)
          continue
        }
        match @platform.kind(native) {
          0 => tree = tree.with_missing(path)
          1 => {
            let text = @platform.read(native)
            files[path.to_string()] = text
            tree = tree.with_file(path, text)
          }
          _ =>
            raise @config.Invalid(
              "Configuration must be a readable regular file: " + native,
            )
        }
      }
    }
  }
  tree
}

///|
pub fn Location::at_root(root : String) -> Location raise {
  let cwd = configuration_cwd()
  let directory = if root == @platform.cwd() {
    cwd
  } else {
    let parsed = @lander_config.FileTreePath::from_native(
      root,
      configuration_platform(),
    )
    if parsed.is_absolute() {
      parsed
    } else {
      cwd.resolve(parsed)
    }
  }
  { root, invocation: "", file: None, directory, configuration_files: Map([]), }
}

///|
/// The published document-aware policy owns the entire root walk.
pub fn locate(path : String, boundary? : String) -> Location raise {
  let requested = @workspace.normalize(path)
  let cwd = configuration_cwd()
  let full = if requested == "" { cwd } else { cwd.join(requested) }
  let native = configuration_native(full, false).unwrap_or(path)
  let kind = @platform.kind(native)
  if kind != 1 && kind != 2 {
    raise @config.Invalid("Input does not exist or is unsupported: " + path)
  }
  let start = if kind == 1 { full.parent().unwrap_or(full) } else { full }
  let boundary = boundary.map(path => {
    let path = @lander_config.FileTreePath::from_native(
      path,
      configuration_platform(),
    )
    if path.is_absolute() {
      path.to_string()
    } else {
      cwd.resolve(path).to_string()
    }
  })
  let conventions = @workspace.configuration_conventions(boundary?)
  let files = Map([])
  let mut tree = @lander_config.FileTree::new()
  let formats = @workspace.configuration_formats()
  while true {
    let context : @lander_config.LoadContext = {
      tree,
      platform: Some(configuration_platform()),
      env_vars: Map([]),
      working_dir: Some(start),
      formats,
    }
    let step = conventions.roots(context) catch {
      @lander_config.Ambiguous(candidates~, ..) =>
        raise @config.Invalid(
          "Ambiguous configuration: " + candidates.join(", "),
        )
      error => raise @config.Invalid(error.message())
    }
    match step {
      Need(requests) =>
        tree = read_configuration_requests(tree, requests, files)
      Done(evidence) => {
        let root = evidence
          .workspace()
          .unwrap_or(evidence.nearest_project().unwrap_or(start))
        let prefix = root.to_string() + "/"
        let invocation = if start == root {
          ""
        } else {
          start.to_string()[prefix.length():].to_owned()
        }
        let file = if kind == 1 {
          Some(full.to_string()[prefix.length():].to_owned())
        } else {
          None
        }
        return {
          root: configuration_native(root, false).unwrap(),
          invocation,
          file,
          directory: root,
          configuration_files: files,
        }
      }
    }
  } nobreak {
    abort("root discovery ended without a result")
  }
}

///|
pub fn configuration_options(
  location : Location,
  environment : Map[String, String],
  selected? : String,
  profiles~ : @lander_config.ProfileSelection = Unspecified,
  isolated~ : Bool = false,
  suppress~ : Array[String] = [],
) -> @workspace.ConfigurationOptions raise {
  let files = location.configuration_files.copy()
  if !isolated {
    let formats = @workspace.configuration_formats()
    let conventions = machine_conventions(
      @workspace.configuration_conventions(),
    )
    let builder = formats.fold(
        init=@lander_config.builder()
          |> @lander_config.working_dir(location.directory.to_string())
          |> @lander_config.platform(configuration_platform())
          |> @lander_config.env_vars(environment),
        (builder, format) => builder |> @lander_config.format(format),
      )
      |> @conventions.add(
        conventions,
        options=@conventions.DiscoveryOptions::new(config=Skip),
      )
    let mut tree = @lander_config.FileTree::new()
    while true {
      let step = @lander_config.load(builder, tree) catch {
        @lander_config.Ambiguous(candidates~, ..) =>
          raise @config.Invalid(
            "Ambiguous configuration: " + candidates.join(", "),
          )
        error => raise @config.Invalid(error.message())
      }
      match step {
        Need(requests) =>
          tree = read_configuration_requests(
            tree,
            requests,
            files,
            machine=true,
          )
        Done(_) => break
      }
    }
  }
  let selected = selected.map(path => {
    if path.has_suffix(".scm") {
      raise @config.Invalid(
        "Use --config-script for Scheme configuration scripts: " + path,
      )
    }
    let parsed = configuration_selected_path(path)
    let native = configuration_native(parsed, false).unwrap_or(path)
    if @platform.kind(native) != 1 {
      raise @config.Invalid(
        "Configuration file not found or unreadable: " + path,
      )
    }
    files[parsed.to_string()] = @platform.read(native)
    parsed.to_string()
  })
  @workspace.ConfigurationOptions::new(
    directory=location.directory,
    selected?,
    profiles~,
    isolated~,
    suppress~,
    external_files=files,
    platform=configuration_platform(),
  )
}

///|
#cfg(target="wasm")
fn configuration_selected_path(
  path : String,
) -> @lander_config.FileTreePath raise {
  // WASI grants the development directory through a preopen. Its selected
  // files use the same confined relative paths as the other WASI inputs.
  configuration_cwd().join(@workspace.normalize(path))
}

///|
#cfg(not(target="wasm"))
fn configuration_selected_path(
  path : String,
) -> @lander_config.FileTreePath raise {
  let resolved = @metadata_grants.host_path(
    path,
    @platform.cwd(),
    @platform.system_type(),
  )
  let parsed = @lander_config.FileTreePath::from_native(
    resolved,
    configuration_platform(),
  )
  if parsed.is_absolute() {
    parsed
  } else {
    configuration_cwd().resolve(parsed)
  }
}

///|
#cfg(target="wasm")
fn machine_conventions(
  conventions : @conventions.Conventions,
) -> @conventions.Conventions {
  conventions |> @conventions.without(AppHome)
}

///|
#cfg(not(target="wasm"))
fn machine_conventions(
  conventions : @conventions.Conventions,
) -> @conventions.Conventions {
  conventions
}
