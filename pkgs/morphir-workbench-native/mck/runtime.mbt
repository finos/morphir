///|
priv struct Gate {
  id : String?
  held : Bool
  signal : @async.CondVar
  mut entered : Bool
  mut delivered : Bool
  mut waiters : Int32
}

///|
fn Gate::new(id : String?, held : Bool) -> Gate {
  {
    id,
    held,
    signal: @async.CondVar::Cond(),
    entered: false,
    delivered: false,
    waiters: 0,
  }
}

///|
priv struct Picker {
  gate : Gate
  root : String?
  fail : Bool
}

///|
priv struct Cleanup {
  gate : Gate
  success : Bool
}

///|
priv struct MemoryRoot {
  manifest : String
  files : Map[String, Bytes]
}

///|
priv struct Attempt {
  id : String
  mut state : String
  mut reply : Json
  mut cleanup : Json
  mut failure : Json
}

///|
priv struct ControlledExecutions {
  host : @executions.Host
  session : String
  cleanup : Cleanup
  mut closed : Bool
  mut reserved : Int32
}

///|
priv struct Runtime {
  group : @async.TaskGroup[Unit]
  contract : @request.Contract
  accepted_plans : Array[Json]
  selected_results : Array[Json]
  claims : Map[String, SelectedClaim]
  input : Json
  aliases : Aliases
  roots : Map[String, MemoryRoot]
  pickers : Array[Picker]
  cleanups : Map[String, Cleanup]
  gates : Map[String, Gate]
  services : Map[String, ControlledExecutions]
  workspace_scopes : Map[String, String]
  pending_workspace_scopes : Array[String]
  calls : Array[Json]
  attempts : Array[Attempt]
  changed : @async.CondVar
  mut context : Json
  mut runnable : Int32
  mut picker_position : Int32
  mut used_cleanups : Int32
  mut next_service : Int32
  mut next_workspace : Int32
  mut observing : Bool
}

///|
fn Runtime::new(
  group : @async.TaskGroup[Unit],
  input : Json,
  contract~ : @request.Contract = Executions,
) -> Runtime raise {
  let roots = Map([])
  for root in array(field(input, "roots"), 8) {
    let files = Map([])
    for file in array(field(root, "files"), 4) {
      let (name, bytes) = checkpoint(file)
      files[name] = bytes
    }
    roots[text(field(root, "id"))] = {
      manifest: text(field(root, "manifest"), maximum=16384),
      files,
    }
  }
  let gates = Map([])
  let pickers = array(field(input, "pickers"), 128).map(value => {
    let id = text(field(value, "id"))
    let gate = Gate::new(Some(id), boolean(field(value, "held")))
    gates[id] = gate
    {
      gate,
      root: optional_text(field(value, "root")),
      fail: boolean(field(value, "fail")),
    }
  })
  let cleanups = Map([])
  for value in array(field(input, "cleanups"), 128) {
    let id = text(field(value, "id"))
    let gate = Gate::new(Some(id), boolean(field(value, "held")))
    gates[id] = gate
    cleanups[text(field(value, "session"))] = {
      gate,
      success: boolean(field(value, "success")),
    }
  }
  {
    group,
    contract,
    accepted_plans: [],
    selected_results: [],
    claims: Map([]),
    input,
    aliases: Aliases::new(),
    roots,
    pickers,
    cleanups,
    gates,
    services: Map([]),
    workspace_scopes: Map([]),
    pending_workspace_scopes: [],
    calls: [],
    attempts: [],
    changed: @async.CondVar::Cond(),
    context: field(input, "context"),
    runnable: 0,
    picker_position: 0,
    used_cleanups: 0,
    next_service: 0,
    next_workspace: 0,
    observing: true,
  }
}

///|
fn Runtime::log(self : Runtime, event : Json) -> Unit {
  if self.observing {
    guard self.calls.length() < 512 else {
      abort("native owner MCK: too many dependency calls")
    }
    self.calls.push(Json::string(canonical(event)))
  }
}

///|
/// Every launched request and background cleanup has one runnable reservation.
/// A held callback relinquishes its reservation until explicit gate delivery.
async fn Runtime::wait_gate(self : Runtime, gate : Gate) -> Unit {
  if gate.held && !gate.delivered {
    gate.waiters += 1
    self.runnable -= 1
    self.changed.broadcast()
    while !gate.delivered {
      gate.signal.wait()
    }
    gate.waiters -= 1
  }
}

///|
fn Runtime::deliver(self : Runtime, gate : Gate) -> String {
  if !gate.entered {
    return "unavailable"
  }
  if gate.delivered {
    return "already-delivered"
  }
  gate.delivered = true
  self.runnable += gate.waiters
  gate.signal.broadcast()
  "delivered"
}

///|
async fn Runtime::settle(self : Runtime) -> Unit {
  while self.runnable > 0 {
    self.changed.wait()
  }
  guard self.runnable == 0 else {
    abort("native owner MCK: invalid runnable accounting")
  }
}

///|
async fn Runtime::choose(self : Runtime) -> String? {
  let picker = if self.picker_position < self.pickers.length() {
    let picker = self.pickers[self.picker_position]
    self.picker_position += 1
    picker
  } else {
    { gate: Gate::new(None, false), root: None, fail: false, }
  }
  let id = picker.gate.id.map(Json::string).unwrap_or(Json::null())
  self.log({ "event": "picker.begin", "id": id })
  picker.gate.entered = true
  self.wait_gate(picker.gate)
  self.log({
    "event": "picker.result",
    "id": id,
    "root": picker.root.map(Json::string).unwrap_or(Json::null()),
    "failed": picker.fail,
  })
  if picker.fail {
    raise @workspace.Rejected("controlled picker failure")
  }
  picker.root
}

///|
fn Runtime::open_root(self : Runtime, id : String) -> @workspace.RootAccess {
  let root = self.roots.get(id).unwrap()
  let closed = Ref(false)
  self.log({ "event": "root.open", "root": id })
  {
    current: fn() raise {
      self.log({ "event": "root.current", "root": id })
      guard !closed.val else {
        raise @workspace.Rejected("workbench.workspace_revoked")
      }
    },
    snapshot: fn() {
      self.log({ "event": "root.snapshot", "root": id })
      let files = root.files.keys().collect()
      files.push("morphir.json")
      files.sort()
      {
        tree: { files: { "morphir.json": root.manifest }, directories: [""], },
        files,
      }
    },
    read: fn(name) {
      let bytes = root.files.get(name).unwrap()
      self.log({
        "event": "root.read",
        "root": id,
        "name": name,
        "size": bytes.length(),
      })
      bytes
    },
    close: fn() {
      closed.val = true
      self.log({ "event": "root.close", "root": id })
    },
  }
}

///|
fn Runtime::workspace(self : Runtime) -> @workspace.Service {
  self.next_workspace += 1
  self.pending_workspace_scopes.push(
    "workspace-instance-" + self.next_workspace.to_string(),
  )
  @workspace.Service::new(open_root=fn(id) { self.open_root(id) })
}

///|
fn Attempt::to_json(self : Attempt) -> Json {
  {
    "id": self.id,
    "state": self.state,
    "reply": self.reply,
    "cleanup": self.cleanup,
    "failure": self.failure,
  }
}

///|
fn Runtime::attempt(self : Runtime, id : String) -> Attempt {
  let attempt = {
    id,
    state: "pending",
    reply: Json::null(),
    cleanup: Json::null(),
    failure: Json::null(),
  }
  self.attempts.push(attempt)
  attempt
}

///|
fn Runtime::finished(self : Runtime) -> Unit {
  self.runnable -= 1
  self.changed.broadcast()
}

///|
fn Runtime::reference(
  self : Runtime,
  action : Json,
  key : String,
  domain : String,
) -> Json? {
  let name = text(field(action, key))
  if !name.has_prefix(domain + "-") {
    return None
  }
  self.aliases.reverse.get(name)
}

///|
fn Runtime::frame(self : Runtime, action : Json) -> (String, Json)? {
  let operation = text(field(action, "operation"))
  let frame : Map[String, Json] = {
    "profile": "morphir/workbench/native",
    "contractVersion": self.contract.version(),
    "operation": Json::string(operation),
  }
  if operation == "session.open" {
    return Some(("", Json::object(frame)))
  }
  guard self.reference(action, "session", "session") is Some(String(session)) else {
    return None
  }
  frame["sessionId"] = Json::string(session)
  let payload : Map[String, Json] = Map([])
  if operation == "execution.submit" {
    guard field(self.input, "evaluation") is Object(evaluation) else {
      abort("native owner MCK: evaluation")
    }
    for (key, value) in evaluation {
      payload[key] = value
    }
    payload["contractVersion"] = Json::string("0.2.0-draft.1")
  } else if operation.has_prefix("execution.") {
    guard self.reference(action, "execution", "execution") is Some(identity) else {
      return None
    }
    payload["contractVersion"] = Json::string("0.2.0-draft.1")
    payload["identity"] = identity
  } else if [
      "workspace.revoke", "workspace.open", "workspace.read", "workspace.release",
    ].contains(operation) {
    guard self.reference(action, "grant", "grant") is Some(grant) else {
      return None
    }
    payload["grantId"] = grant
    if operation == "workspace.open" {
      guard self.reference(action, "project", "project") is Some(project) else {
        return None
      }
      payload["projectId"] = project
    }
    if operation != "workspace.revoke" {
      payload["sequence"] = field(action, "sequence")
    }
    if operation == "workspace.read" {
      payload["offset"] = field(action, "offset")
    }
  }
  if operation.has_prefix("execution.") ||
    [
      "workspace.revoke", "workspace.open", "workspace.read", "workspace.release",
    ].contains(operation) {
    frame["payload"] = Json::object(payload)
  }
  Some((session, Json::object(frame)))
}

///|
fn Runtime::launch(
  self : Runtime,
  owner : @bridge.Owner,
  action : Json,
) -> Unit {
  let attempt = self.attempt(text(field(action, "id")))
  guard self.frame(action) is Some((session, frame)) else {
    attempt.state = "rejected"
    attempt.failure = Json::string("reference")
    return
  }
  let operation = text(field(action, "operation"))
  self.runnable += 1
  self.group.spawn_bg(async fn() {
    defer self.finished()
    let response = owner.request(
      frame.stringify(),
      fn() raise { caller(self.context) },
      async fn() { self.choose() },
    )
    let reply = (if self.contract == @request.CapabilityChecks {
      @reply.decode_policy(@utf8.encode(response), operation)
    } else {
      @reply.decode(@utf8.encode(response), operation)
    }).to_json()
    if field(reply, "ok") == Json::boolean(true) {
      let value = field(reply, "value")
      if operation == "session.open" || operation == "session.check" {
        let raw = text(field(value, "sessionId"))
        if !self.workspace_scopes.contains(raw) &&
          !self.pending_workspace_scopes.is_empty() {
          self.workspace_scopes[raw] = self.pending_workspace_scopes.remove(0)
        }
      }
      attempt.reply = {
        "ok": true,
        "operation": field(reply, "operation"),
        "value": canonical(self.normalize(operation, session, value)),
      }
    } else {
      let error = field(reply, "error")
      attempt.reply = {
        "ok": false,
        "code": field(error, "code"),
        "effect": field(error, "effect"),
      }
    }
    attempt.state = "returned"
  })
}

///|
fn Runtime::shutdown(
  self : Runtime,
  owner : @bridge.Owner,
  id : String,
) -> Unit {
  let attempt = self.attempt(id)
  self.runnable += 1
  self.group.spawn_bg(async fn() {
    defer self.finished()
    try {
      owner.shutdown()
      attempt.state = "returned"
      attempt.cleanup = Json::boolean(true)
    } catch {
      _ => {
        attempt.state = "rejected"
        attempt.cleanup = Json::boolean(false)
      }
    }
  })
}

///|
async fn Runtime::execute(self : Runtime, owner : @bridge.Owner) -> Json {
  let steps : Array[Json] = []
  for action in array(field(self.input, "actions"), 32) {
    let op = text(field(action, "op"))
    let mut delivery = Json::null()
    let mut completion = Json::null()
    match op {
      "call" => self.launch(owner, action)
      "context" =>
        self.context = {
          "window": field(action, "window"),
          "origin": field(action, "origin"),
          "page": field(action, "page"),
        }
      "revoke" => owner.revoke()
      "close" => owner.close()
      "shutdown" => self.shutdown(owner, text(field(action, "id")))
      "deliver" =>
        delivery = Json::string(
          self.deliver(self.gates[text(field(action, "id"))]),
        )
      "claim" | "evaluate" => self.selected_action(action)
      "complete" =>
        completion = self.complete(
          text(field(action, "execution")),
          field(action, "outcomes"),
        )
      "replace" => {
        let (name, bytes) = checkpoint(action, replace=true)
        self.roots[text(field(action, "root"))].files[name] = bytes
      }
      _ => abort("native owner MCK: admitted action")
    }
    self.settle()
    steps.push({
      "action": op,
      "attempts": self.attempts.map(attempt => {
        ({ "id": attempt.id, "state": attempt.state } : Json)
      }),
      "callCount": self.calls.length(),
      "delivery": delivery,
      "completion": completion,
    })
  }
  let observation : Json = {
    "steps": steps,
    "results": self.attempts.map(Attempt::to_json),
    "calls": self.calls.copy(),
    "usedPickers": self.picker_position,
    "unusedPickers": self.pickers.length() - self.picker_position,
    "usedCleanups": self.used_cleanups,
    "unusedCleanups": self.cleanups.length() - self.used_cleanups,
  }
  if self.contract == @request.CapabilityChecks {
    guard observation is Object(fields) else { abort("Owner projection") }
    fields["acceptedPlans"] = Json::array(self.accepted_plans.copy())
    fields["selectedResults"] = Json::array(self.selected_results.copy())
  }
  ignore(canonical(observation))
  // Final observation precedes teardown. Cleanup cannot append events or mutate
  // the copied result projection, and every controlled waiter is released.
  self.observing = false
  for gate in self.gates.values() {
    if !gate.delivered {
      gate.delivered = true
      self.runnable += gate.waiters
      gate.signal.broadcast()
    }
  }
  owner.close()
  self.runnable += 1
  owner.shutdown() catch {
    _ => ()
  }
  self.finished()
  self.settle()
  observation
}
