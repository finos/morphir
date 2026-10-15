///|
pub(all) struct Mount {
  kind : (String) -> Int raise
  read : (String) -> String raise
  list : (String) -> Array[String] raise
}

///|
pub(all) struct Publication {
  stage : (@engine.Artifact) -> Unit raise
  commit : (String) -> Unit raise
  abort : () -> Unit raise
}

///|
pub(all) enum PublicationGuarantee {
  AtomicTask
  RecoverableTask
  HostManaged
}

///|
pub(all) struct Publisher {
  guarantee : PublicationGuarantee
  begin : (Array[String]) -> Publication raise
}

///|
pub(all) struct Limits {
  max_files : Int
  max_bytes : Int
  max_depth : Int
}

///|
pub fn Limits::default() -> Limits {
  { max_files: 10000, max_bytes: 67108864, max_depth: 64, }
}

///|
pub(all) enum Event {
  Phase(String)
  Diagnostic(@engine.Diagnostic)
  Generated(@engine.LibraryProject)
  Validated(ValidatedProject)
  Published(String)
}

///|
pub(all) struct Host {
  input : Mount
  publisher : Publisher?
  toolchain : @toolchain.Provider?
  library_build : LibraryBuildProvider?
  metadata_sessions : MetadataSessions
  environment : Map[String, String]
  system : @config.Document
  global : @config.Document
  cancelled : () -> Bool
  event : (Event) -> Unit
  limits : Limits
}

///|
pub fn Host::new(
  input : Mount,
  publisher? : Publisher? = None,
  toolchain? : @toolchain.Provider? = None,
  library_build? : LibraryBuildProvider? = None,
  environment? : Map[String, String] = Map([]),
  system? : @config.Document = @config.empty(),
  global? : @config.Document = @config.empty(),
  cancelled? : () -> Bool = fn() { false },
  event? : (Event) -> Unit = fn(_) { () },
  limits? : Limits = Limits::default(),
) -> Host {
  {
    input,
    publisher,
    toolchain,
    library_build,
    metadata_sessions: MetadataSessions::new(),
    environment,
    system,
    global,
    cancelled,
    event,
    limits,
  }
}

///|
/// Host-owned tooling for pipelines. Acquisition and embedding remain provider capabilities.
pub fn Host::toolchain_request(self : Host, request : Json) -> Json raise {
  if (self.cancelled)() {
    raise @config.Invalid("Cancelled")
  }
  let provider = match self.toolchain {
    Some(provider) => provider
    None => raise @config.Invalid("Host does not provide a toolchain")
  }
  (self.event)(Phase("toolchain"))
  let result = (provider.request)(request)
  if (self.cancelled)() {
    raise @config.Invalid("Cancelled")
  }
  result
}

///|
pub(all) struct Snapshot {
  tree : @workspace.Tree
  paths : Array[String]
}

///|
fn configuration_path(path : String) -> Bool {
  [
    "morphir.toml", "morphir.yaml", "morphir.user.toml", "morphir.user.yaml", "config.toml",
    "config.yaml", "config.user.toml", "config.user.yaml", "morphir.json", "morphir-workspace.json",
    "morphir.config.scm",
  ].contains(path.split("/").last().unwrap_or("").to_owned())
}

///|
pub fn Host::snapshot(self : Host) -> Snapshot raise {
  (self.event)(Phase("snapshot"))
  let files = Map([])
  let paths = []
  let directories = []
  let mut bytes = 0
  fn walk(path : String, depth : Int) -> Unit raise {
    if (self.cancelled)() {
      raise @config.Invalid("Cancelled")
    }
    if depth > self.limits.max_depth {
      raise @config.Invalid("Directory depth limit exceeded")
    }
    directories.push(path)
    if paths.length() + directories.length() > self.limits.max_files {
      raise @config.Invalid("Entry limit exceeded")
    }
    let children = (self.input.list)(path)
    children.sort()
    for name in children {
      if name.contains("/") || name == "" || name == "." || name == ".." {
        raise @config.Invalid("Invalid directory entry: " + name)
      }
      if [".git", ".beads", ".mooncakes", "node_modules", "_build"].contains(
          name,
        ) {
        continue
      }
      let child = @workspace.join(path, name)
      match (self.input.kind)(child) {
        1 => {
          paths.push(child)
          if paths.length() + directories.length() > self.limits.max_files {
            raise @config.Invalid("Entry limit exceeded")
          }
          if configuration_path(child) {
            let content = (self.input.read)(child)
            bytes = bytes + @utf8.encode(content[:]).length()
            if bytes > self.limits.max_bytes {
              raise @config.Invalid("Configuration byte limit exceeded")
            }
            files[child] = content
          }
        }
        2 => walk(child, depth + 1)
        3 => raise @config.Invalid("Unresolved symbolic link: " + child)
        _ => raise @config.Invalid("Unreadable or unsupported entry: " + child)
      }
    }
  }
  walk("", 0)
  { tree: { files, directories, }, paths, }
}

///|
pub fn Snapshot::engine_host(self : Snapshot) -> @engine.Host {
  {
    read: fn(path) raise {
      match self.tree.files.get(path) {
        Some(s) => s
        None =>
          raise @config.Invalid(
            "Content not in configuration snapshot: " + path,
          )
      }
    },
    exists: fn(path) { self.tree.files.contains(path) },
    list: fn(root) { self.paths.filter(p => @workspace.within(root, p)) },
  }
}

///|
pub(all) struct Result {
  report : @engine.Report
  committed : Array[String]
  publication_error : String?
  cancelled : Bool
}

///|
pub fn Result::successful(self : Result) -> Bool {
  self.report.successful() && self.publication_error is None && !self.cancelled
}

///|
pub fn Host::run(
  self : Host,
  engine : @engine.Engine,
  plan : @engine.Plan,
) -> Result raise {
  let publisher = match self.publisher {
    Some(publisher) => publisher
    None => raise @config.Invalid("Host does not provide publication")
  }
  let result = self.run_content(engine, plan, ContentPublisher::text(publisher))
  {
    report: result.report.text_report(),
    committed: result.committed,
    publication_error: result.publication_error,
    cancelled: result.cancelled,
  }
}

///|
pub fn Mount::memory(files : Map[String, String]) -> Mount raise {
  let data = Map([])
  let dirs = Map::from_array([("", true)])
  for path, value in files {
    let path = @workspace.normalize(path)
    if path == "" || data.contains(path) {
      raise @config.Invalid("Invalid or duplicate memory path: " + path)
    }
    data[path] = value
    let mut parent = @workspace.parent(path)
    while parent != "" {
      dirs[parent] = true
      parent = @workspace.parent(parent)
    }
  }
  {
    kind: fn(path) {
      if data.contains(path) {
        1
      } else if dirs.contains(path) {
        2
      } else {
        0
      }
    },
    read: fn(path) raise {
      match data.get(path) {
        Some(s) => s
        None => raise @config.Invalid("Missing memory file: " + path)
      }
    },
    list: fn(root) {
      let names = Map([])
      for path in data.keys().concat(dirs.keys()) {
        if path != root && @workspace.parent(path) == root {
          names[path.split("/").last().unwrap_or("").to_owned()] = true
        }
      }
      names.keys().collect()
    },
  }
}

///|
pub fn Publisher::memory(outputs : Map[String, String]) -> Publisher {
  {
    guarantee: AtomicTask,
    begin: fn(destinations) {
      let staged : Map[String, String] = Map([])
      {
        stage: fn(artifact) raise {
          if !destinations.any(d => @workspace.within(d, artifact.path)) {
            raise @config.Invalid("Artifact outside publication")
          }
          staged[artifact.path] = artifact.content
        },
        commit: fn(destination) {
          for path in outputs.keys().collect() {
            if @workspace.within(destination, path) {
              outputs.remove(path)
            }
          }
          for path, value in staged {
            if @workspace.within(destination, path) {
              outputs[path] = value
            }
          }
        },
        abort: fn() { staged.clear() },
      }
    },
  }
}
