///|
priv struct Project {
  id : String
  name : String
  path : String
  format : String
  error : String
}

///|
pub struct Service {
  priv open_root : (String) -> RootAccess raise
  priv mut root : RootAccess?
  priv mut snapshot : Snapshot?
  priv mut projects : Array[Project]
  priv mut generation : Int32
  priv mut chooser : Int32?
  priv mut grant : String
  priv mut capture : Bytes?
  priv mut active_sequence : Int32
  priv mut retired_sequence : Int32
  priv mut offset : Int32
  priv mut closed : Bool
}

///|
/// The root factory is trusted host wiring, never renderer-supplied data.
pub fn Service::new(
  open_root~ : (String) -> RootAccess raise = native_root,
) -> Service {
  {
    open_root,
    root: None,
    snapshot: None,
    projects: [],
    generation: 0,
    chooser: None,
    grant: "",
    capture: None,
    active_sequence: 0,
    retired_sequence: 0,
    offset: 0,
    closed: false,
  }
}

///|
pub fn Service::revoke(self : Service) -> Unit {
  if self.root is Some(root) {
    (root.close)()
  }
  self.root = None
  self.snapshot = None
  self.projects = []
  self.grant = ""
  self.capture = None
  self.active_sequence = 0
  self.retired_sequence = 0
  self.chooser = None
}

///|
pub fn Service::close(self : Service) -> Unit {
  self.revoke()
  self.closed = true
}

///|
pub fn Service::begin_choose(self : Service) -> Int32 raise Invalid {
  guard !self.closed else { raise Rejected("workbench.workspace_revoked") }
  guard self.chooser == None else {
    raise Rejected("workbench.workspace_picker_busy")
  }
  guard self.generation < 2147483647 else {
    raise Rejected("workbench.workspace_quota")
  }
  self.generation += 1
  self.chooser = Some(self.generation)
  self.generation
}

///|
pub fn Service::cancel_choose(self : Service) -> Unit {
  self.chooser = None
}

///|
/// Cleanup belongs to the picker that created it. An older completion may
/// arrive after explicit cancellation and a replacement picker has started.
pub fn Service::cancel_choose_if_current(
  self : Service,
  ticket : Int32,
) -> Unit {
  if self.chooser == Some(ticket) {
    self.chooser = None
  }
}

///|
fn format(path : String) -> String? {
  if path.has_suffix(".json") {
    Some("morphir-json")
  } else if path.has_suffix(".ion") || path.has_suffix(".10n") {
    Some("ion-text")
  } else if path.has_suffix(".ionb") {
    Some("ion-binary")
  } else {
    None
  }
}

///|
fn candidates(
  workspace : @engine.Workspace,
  project : @engine.Project,
  files : Array[String],
) -> Array[String] raise {
  let out = @engine.join(
    workspace.root,
    workspace.document.text("workspace.out_dir", ".morphir/out"),
  )
  let relative = if project.root == workspace.root {
    ""
  } else if workspace.root == "" {
    project.root
  } else {
    project.root[workspace.root.length() + 1:].to_owned()
  }
  let destination = @engine.join(@engine.join(out, relative), "compile.dest")
  let conventional = [
    "morphir-ir.json", "morphir-ir.ion", "morphir-ir.10n", "morphir-ir.ionb",
  ].map(name => @engine.join(project.root, name))
  files.filter(path => {
    conventional.contains(path) ||
    (@engine.within(destination, path) && format(path) != None)
  })
}

///|
/// Complete only after the caller has revalidated the page/session following
/// the asynchronous native picker. Renderer data cannot create this authority.
pub fn Service::finish_choose(
  self : Service,
  ticket : Int32,
  path : String?,
) -> Json raise {
  guard !self.closed && self.chooser == Some(ticket) else {
    raise Rejected("workbench.workspace_picker_stale")
  }
  self.chooser = None
  guard path is Some(path) else { return { "ok": true, "cancelled": true } }
  let root = (self.open_root)(path)
  let mut retained = false
  defer (if !retained { (root.close)() })
  let snapshot = (root.snapshot)()
  let workspace = @engine.discover(snapshot.tree)
  guard workspace.projects.length() <= 128 else {
    raise Rejected("workbench.workspace_quota")
  }
  let projects : Array[Project] = []
  for project in workspace.projects {
    guard @utf8.encode(project.name[:]).length() <= 256 else {
      raise Rejected("workbench.workspace_quota")
    }
    let paths = candidates(workspace, project, snapshot.files)
    if paths.is_empty() || project.error != None {
      projects.push({
        id: "project-" + projects.length().to_string(),
        name: project.name,
        path: "",
        format: "",
        error: project.error.unwrap_or(
          "No saved model checkpoint. Compile the project before opening it here.",
        ),
      })
    } else {
      for path in paths {
        projects.push({
          id: "project-" + projects.length().to_string(),
          name: project.name +
          (if paths.length() > 1 { " · " + path } else { "" }),
          path,
          format: format(path).unwrap(),
          error: "",
        })
      }
    }
  }
  guard projects.length() <= 128 else {
    raise Rejected("workbench.workspace_quota")
  }
  let grant = "workspace-" + ticket.to_string()
  let reply : Json = {
    "ok": true,
    "cancelled": false,
    "grantId": grant,
    "projects": projects.map(p => {
      (
        {
          "id": p.id,
          "name": p.name,
          "available": p.error == "",
          "message": p.error,
        } : Json)
    }),
    "warnings": workspace.warnings,
  }
  guard @utf8.encode(reply.stringify()[:]).length() <= 512 * 1024 else {
    raise Rejected("workbench.workspace_quota")
  }
  // Validate the complete public envelope before replacing the existing grant.
  guard reply is Object(fields) else { abort("Workspace offer object") }
  fields.remove("ok")
  ignore(@reply.success("workspace.choose", Json::object(fields)))
  fields["ok"] = Json::boolean(true)
  self.revoke()
  self.root = Some(root)
  self.snapshot = Some(snapshot)
  self.projects = projects
  self.grant = grant
  retained = true
  reply
}

///|
fn string(fields : Map[String, Json], key : String) -> String raise Invalid {
  match fields.get(key) {
    Some(String(s)) => s
    _ => raise Rejected("workbench.workspace_request")
  }
}

///|
fn sequence(fields : Map[String, Json]) -> Int32 raise Invalid {
  guard fields.get("sequence") is Some(Number(n, ..)) &&
    n >= 1 &&
    n <= 2147483647 &&
    n == n.to_int().to_double() else {
    raise Rejected("workbench.workspace_sequence")
  }
  n.to_int()
}

///|
pub fn Service::request(self : Service, source : String) -> Json {
  try {
    guard @utf8.encode(source[:]).length() <= 4096 else {
      raise Rejected("workbench.workspace_request")
    }
    guard @jobs.decode(source) is Object(fields) else {
      raise Rejected("workbench.workspace_request")
    }
    let action = string(fields, "action")
    if action == "cancel-picker" {
      guard fields.length() == 1 else {
        raise Rejected("workbench.workspace_request")
      }
      self.cancel_choose()
      return { "ok": true }
    }
    guard !self.closed &&
      self.root is Some(root) &&
      string(fields, "grantId") == self.grant else {
      raise Rejected("workbench.workspace_revoked")
    }
    if action == "release" {
      guard fields.length() == 3 else {
        raise Rejected("workbench.workspace_request")
      }
      let sequence = sequence(fields)
      guard self.capture == None || sequence == self.active_sequence else {
        raise Rejected("workbench.workspace_capture")
      }
      self.capture = None
      self.active_sequence = 0
      // A release can overtake an open whose reply/effect is unknown. Retire
      // its identity even when no capture exists, preventing late admission.
      if sequence > self.retired_sequence {
        self.retired_sequence = sequence
      }
      return { "ok": true }
    }
    if action == "revoke" {
      guard fields.length() == 2 else {
        raise Rejected("workbench.workspace_request")
      }
      self.revoke()
      return { "ok": true }
    }
    (root.current)()
    let sequence = sequence(fields)
    if action == "open" {
      guard fields.length() == 4 else {
        raise Rejected("workbench.workspace_request")
      }
      guard self.capture == None else {
        raise Rejected("workbench.workspace_busy")
      }
      guard sequence > self.retired_sequence else {
        raise Rejected("workbench.workspace_retired")
      }
      let project_id = string(fields, "projectId")
      guard self.projects.filter(p => p.id == project_id).get(0)
        is Some(project) else {
        raise Rejected("workbench.workspace_project")
      }
      guard project.error == "" else {
        raise Rejected("workbench.workspace_model_missing")
      }
      let fresh = (root.snapshot)()
      guard self.snapshot is Some(old) && fresh.tree.files == old.tree.files else {
        raise Rejected("workbench.workspace_changed")
      }
      let bytes = (root.read)(project.path)
      let codec = if project.format != "morphir-json" &&
        bytes.length() >= 4 &&
        bytes[:4] == b"\xe0\x01\x00\xea"[:] {
        "ion-binary"
      } else {
        project.format
      }
      self.capture = Some(bytes)
      self.active_sequence = sequence
      self.offset = 0
      return {
        "ok": true,
        "sequence": sequence,
        "size": bytes.length(),
        "format": codec,
        "filename": project.path.split("/").last().unwrap().to_owned(),
      }
    }
    if action == "read" {
      guard fields.length() == 4 &&
        sequence == self.active_sequence &&
        fields.get("offset") is Some(Number(n, ..)) &&
        n == self.offset.to_double() else {
        raise Rejected("workbench.workspace_sequence")
      }
      guard self.capture is Some(bytes) else {
        raise Rejected("workbench.workspace_capture")
      }
      let start = self.offset
      let end = if bytes.length() < start + 192 * 1024 {
        bytes.length()
      } else {
        start + 192 * 1024
      }
      self.offset = end
      return {
        "ok": true,
        "sequence": sequence,
        "offset": start,
        "content": @base64.encode(bytes[start:end]),
        "done": end == bytes.length(),
      }
    }
    raise Rejected("workbench.workspace_request")
  } catch {
    error => failure(error)
  }
}

///|
pub fn bridge_request(source : String) -> (String, String) raise {
  guard @utf8.encode(source[:]).length() <= 8192 else {
    raise Rejected("workbench.workspace_request")
  }
  guard @jobs.decode(source) is Object(fields) && fields.length() == 2 else {
    raise Rejected("workbench.workspace_request")
  }
  let id = string(fields, "sessionId")
  let body = string(fields, "body")
  guard id.length() <= 128 && @utf8.encode(body[:]).length() <= 4096 else {
    raise Rejected("workbench.workspace_request")
  }
  (id, body)
}

///|
pub fn failure(error : Error) -> Json {
  {
    "ok": false,
    "code": match error {
      Rejected(code) => code
      _ => "workbench.workspace_configuration"
    },
  }
}

///|
/// The dispatcher owns authority checks. This wrapper conservatively reports
/// unknown after entry to the stateful workspace owner, including reply failure.
pub fn Service::native_request(
  self : Service,
  operation : String,
  payload : Json,
) -> Bytes {
  try {
    let action = match operation {
      "workspace.cancel-picker" => "cancel-picker"
      "workspace.revoke" => "revoke"
      "workspace.open" => "open"
      "workspace.read" => "read"
      "workspace.release" => "release"
      _ => return @reply.failure(@reply.InvalidRequest, @reply.NoEffect)
    }
    guard payload is Object(fields) else {
      return @reply.failure(@reply.InvalidRequest, @reply.NoEffect)
    }
    fields["action"] = Json::string(action)
    let result = self.request(Json::object(fields).stringify())
    guard result is Object(result) &&
      result.get("ok") == Some(Json::boolean(true)) else {
      return @reply.failure(@reply.Conflict, @reply.UnknownEffect)
    }
    result.remove("ok")
    @reply.success(operation, Json::object(result))
  } catch {
    _ => @reply.failure(@reply.Unavailable, @reply.UnknownEffect)
  }
}
