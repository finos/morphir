///|
/// A caller-selected format. Ion is preferred; JSON is an explicit opt-out.
pub(all) enum GrantFormat {
  IonText
  IonBinary
  Json
}

///|
priv enum Flavor {
  Posix
  Windows
}

///|
/// Exact, separately authorized paths. Configuration is only a selection.
pub(all) struct GrantedService {
  node : String
  node_sha256 : String
  helper : String
  helper_bundle_sha256 : String
  service : String
  service_sha256 : String
  policy : String
  lock : String
  registry : String
  state : String
  release : String
}

///|
priv struct ProjectGrant {
  project : String
  service : String
  service_sha256 : String
  policy : String
  lock : String
  registry : String
  state : String
}

///|
/// Opaque authority from a host-selected file, never a discovered project file.
/// Parsing and matching perform no filesystem access, probing or acquisition.
pub struct Grants {
  priv flavor : Flavor
  priv workspace : String
  priv node : String
  priv node_sha256 : String
  priv helper : String
  priv helper_bundle_sha256 : String
  priv projects : Array[ProjectGrant]
}

///|
fn[T] invalid(code : String) -> T raise {
  raise @config.Invalid("metadata.restore_" + code)
}

///|
fn fields(
  value : @ion.IonValue,
  names : Array[String],
) -> Map[String, @ion.IonValue] raise {
  guard !value.has_annotations() && value.kind() is @ion.Struct(entries) else {
    invalid("invalid_grants")
  }
  let result = Map([])
  for field in entries {
    guard field.name().text() is Some(name) &&
      names.contains(name) &&
      !result.contains(name) else {
      invalid("invalid_grants")
    }
    result[name] = field.value()
  }
  if result.length() != names.length() {
    invalid("invalid_grants")
  }
  result
}

///|
fn text(
  fields : Map[String, @ion.IonValue],
  key : String,
  empty? : Bool = false,
) -> String raise {
  guard fields.get(key) is Some(value) &&
    !value.has_annotations() &&
    value.kind() is @ion.String(s) &&
    s.length() <= 4096 &&
    !s.contains("\u0000") &&
    (empty || s != "") else {
    invalid("invalid_grants")
  }
  s
}

///|
fn pin(fields : Map[String, @ion.IonValue], key : String) -> String raise {
  let s = text(fields, key)
  if s.length() != 71 ||
    !s.has_prefix("sha256:") ||
    !s[7:]
    .to_owned()
    .to_array()
    .all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
    invalid("invalid_grant_pin")
  }
  s[7:].to_owned()
}

///|
fn absolute(path : String, flavor : Flavor) -> Bool {
  match flavor {
    Posix => @posix.Path(path).is_absolute()
    Windows => {
      let normalized = path
        .split("\\")
        .map(StringView::to_owned)
        .collect()
        .join("/")
      @win32.Path(path).is_absolute() &&
      (
        (normalized.length() >= 3 && normalized[1:3] == ":/") ||
        (
          normalized.has_prefix("//") &&
          normalized.split("/").filter(p => p != "").count() >= 2 &&
          !normalized.has_prefix("//?/")
        )
      )
    }
  }
}

///|
fn resolve(path : String, base : String, flavor : Flavor) -> String raise {
  if path == "" || path.contains("\u0000") || !absolute(base, flavor) {
    invalid("path_origin_unknown")
  }
  match flavor {
    Posix => {
      let p = @posix.Path(path)
      (if p.is_absolute() { p } else { @posix.Path(base).join(p) })
      .normalize()
      .to_string()
    }
    Windows => {
      let p = @win32.Path(path)
      // Drive-relative and root-relative paths depend on ambient drive state.
      if !absolute(path, flavor) &&
        (path.contains(":") || path.has_prefix("/") || path.has_prefix("\\")) {
        invalid("invalid_path")
      }
      let result = (if p.is_absolute() { p } else { @win32.Path(base).join(p) })
        .normalize()
        .to_string()
      result.split("\\").map(StringView::to_owned).collect().join("/")
    }
  }
}

///|
fn parent(path : String, flavor : Flavor) -> String {
  match flavor {
    Posix => @posix.Path(path).dirname().to_string()
    Windows => @win32.Path(path).dirname().to_string()
  }
}

///|
/// Decode a bounded, closed host grant document. Relative paths resolve from
/// this explicitly selected file's absolute origin, not a project selection.
pub fn Grants::decode(
  bytes : Bytes,
  format : GrantFormat,
  origin : String,
  system : String,
) -> Grants raise {
  if bytes.length() > 1048576 {
    invalid("grants_limit")
  }
  let flavor = match system {
    "windows" => Windows
    "linux" | "macos" => Posix
    _ => invalid("runtime_unavailable")
  }
  if !absolute(origin, flavor) {
    invalid("path_origin_unknown")
  }
  let base = parent(origin, flavor)
  let value = match format {
    IonBinary => @binary.read_binary_value(bytes[:])
    IonText => @ion_text.read_ion(@utf8.decode(bytes[:])[:])
    Json => @ion_json.read_json(@utf8.decode(bytes[:])[:])
  }
  let root = fields(value, ["profile", "workspace", "runtime", "projects"])
  if text(root, "profile") != "morphir-metadata-host-grants-v1" {
    invalid("invalid_grants")
  }
  let workspace = resolve(text(root, "workspace"), base, flavor)
  let runtime = fields(root["runtime"], [
    "node", "nodeSha256", "helper", "helperBundleSha256",
  ])
  let node = resolve(text(runtime, "node"), base, flavor)
  let helper = resolve(text(runtime, "helper"), base, flavor)
  if !helper.has_suffix("/metadata.mjs") {
    invalid("unqualified_helper")
  }
  guard root["projects"].kind() is @ion.List(items) &&
    !root["projects"].has_annotations() &&
    items.length() <= 128 else {
    invalid("invalid_grants")
  }
  let projects = []
  let seen = Map([])
  for item in items {
    let fields = fields(item, [
      "project", "service", "serviceSha256", "policy", "lock", "registry", "state",
    ])
    let project = text(fields, "project", empty=true)
    if project.has_prefix("/") ||
      project.contains("\\") ||
      project.contains(":") ||
      project
      .split("/")
      .any(p => p == "." || p == ".." || (p == "" && project != "")) ||
      seen.contains(project) {
      invalid("invalid_project_grant")
    }
    seen[project] = true
    projects.push({
      project,
      service: resolve(text(fields, "service"), base, flavor),
      service_sha256: pin(fields, "serviceSha256"),
      policy: resolve(text(fields, "policy"), base, flavor),
      lock: resolve(text(fields, "lock"), base, flavor),
      registry: resolve(text(fields, "registry"), base, flavor),
      state: resolve(text(fields, "state"), base, flavor),
    })
  }
  {
    flavor,
    workspace,
    node,
    node_sha256: pin(runtime, "nodeSha256"),
    helper,
    helper_bundle_sha256: pin(runtime, "helperBundleSha256"),
    projects,
  }
}

///|
fn selection(
  path : @config.MetadataPath,
  workspace : String,
  invocation : String,
  flavor : Flavor,
) -> String raise {
  if absolute(path.path, flavor) {
    return resolve(path.path, workspace, flavor)
  }
  let base = if path.origin == "CLI" {
    invocation
  } else if absolute(path.origin, flavor) ||
    [".toml", ".json", ".yaml", ".yml", ".scm", ".ion", ".ionb"].any(suffix => {
      path.origin.has_suffix(suffix)
    }) {
    parent(resolve(path.origin, workspace, flavor), flavor)
  } else {
    invalid("path_origin_unknown: " + path.origin)
  }
  resolve(path.path, base, flavor)
}

///|
/// Match this frozen project selection against independent exact grants. The
/// workspace/invocation roots come from the owning host, not provider metadata.
pub fn Grants::select(
  self : Grants,
  scope : @engine.ProjectMetadataScope,
  workspace : String,
  invocation : String,
) -> GrantedService raise {
  let root = resolve(
    if scope.workspace_root == "" {
      "."
    } else {
      scope.workspace_root
    },
    workspace,
    self.flavor,
  )
  if root != self.workspace {
    invalid("workspace_not_granted")
  }
  guard scope.request
    is @config.MetadataProviderRequest::SharedLocalRestore(request) else {
    invalid("provider_disabled")
  }
  guard self.projects.iter().find_first(p => p.project == scope.project_root)
    is Some(grant) else {
    invalid("project_not_granted")
  }
  if request.assurance != "portable" {
    invalid("unsupported_assurance")
  }
  for
    (key, path, allowed) in [
      ("service", request.service, grant.service),
      ("policy", request.policy, grant.policy),
      ("lock", request.lock, grant.lock),
      ("registry", request.registry, grant.registry),
      ("state", request.state, grant.state),
    ] {
    if selection(path, workspace, invocation, self.flavor) != allowed {
      invalid("path_not_granted: metadata." + key + " set in " + path.origin)
    }
  }
  {
    node: self.node,
    node_sha256: self.node_sha256,
    helper: self.helper,
    helper_bundle_sha256: self.helper_bundle_sha256,
    service: grant.service,
    service_sha256: grant.service_sha256,
    policy: grant.policy,
    lock: grant.lock,
    registry: grant.registry,
    state: grant.state,
    release: request.release,
  }
}

///|
/// Resolve an explicit CLI host path from its invocation directory. This does
/// not consult filesystem state, environment configuration or project metadata.
pub fn host_path(path : String, base : String, system : String) -> String raise {
  let flavor = match system {
    "windows" => Windows
    "linux" | "macos" => Posix
    _ => invalid("runtime_unavailable")
  }
  resolve(path, base, flavor)
}
