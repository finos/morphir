///|
priv enum ExecutionAction {
  Observe(Json)
  Reconnect(Json)
  Disconnect
  CancelAction
}

///|
fn ExecutionAction::name(self : ExecutionAction) -> String {
  match self {
    Observe(_) => "observe"
    Reconnect(_) => "reconnect"
    Disconnect => "disconnect"
    CancelAction => "cancel-action"
  }
}

///|
fn execution_action(value : Json) -> ExecutionAction raise {
  let names = match field(value, "op") {
    String("observe") => ["op", "receipt"]
    String("reconnect") => ["op", "offer"]
    String("disconnect" | "cancel-action") => ["op"]
    _ => raise @executions.Invalid("workbench.invalid_execution_trace")
  }
  ignore(closed_fields(value, names, "workbench.invalid_execution_trace"))
  match field(value, "op") {
    String("observe") => Observe(field(value, "receipt"))
    String("reconnect") => Reconnect(field(value, "offer"))
    String("disconnect") => Disconnect
    _ => CancelAction
  }
}

///|
fn cancel_action(cursor : @executions.Cursor) -> String {
  match cursor.cancel_action() {
    Send => "send"
    Pending => "pending"
    AlreadyTerminal => "already-terminal"
    Unavailable => "unavailable"
    Disconnected => "disconnected"
  }
}

///|
fn execution_view(cursor : @executions.Cursor) -> Json raise {
  let receipt = cursor.latest()
  let state = match receipt.state() {
    Submitted => "submitted"
    Running => "running"
    Terminal(_) => "terminal"
  }
  {
    "sequence": receipt.sequence(),
    "state": state,
    "cancelRequested": receipt.cancel_requested(),
    "connected": cursor.connected(),
    "cancelAction": cancel_action(cursor),
  }
}

///|
fn execution_step(
  cursor : @executions.Cursor,
  action : ExecutionAction,
) -> (@executions.Cursor, Json) raise {
  let (next, status, code) : (@executions.Cursor, String, String?) = try {
    let (next, status) = match action {
      Observe(value) => {
        let (next, disposition) = cursor.observe(
          @executions.Receipt::from_json(value),
        )
        let status = match disposition {
          Advanced => "advanced"
          Replay => "replay"
          Stale => "stale"
        }
        (next, status)
      }
      Reconnect(value) =>
        (cursor.reconnect(@executions.Offer::from_json(value)), "local")
      Disconnect => (cursor.disconnect(), "local")
      // Selecting a client action does not send a request or acknowledge it.
      CancelAction => (cursor, "local")
    }
    (next, status, None)
  } catch {
    @executions.Invalid(code) => (cursor, "invalid", Some(code))
    @execution.Invalid(code) =>
      (
        cursor,
        "invalid",
        Some(
          code.split(":").next().unwrap_or("workbench.codec_failure").to_owned(),
        ),
      )
    // Nested Ion metadata decoders have their own error types. They are still
    // rejected receipt payloads, and cannot erase earlier accepted evidence.
    _ => (cursor, "invalid", Some("workbench.codec_failure"))
  }
  let observation : Json = {
    "op": action.name(),
    "status": status,
    "view": execution_view(next),
  }
  if code is Some(code) && observation is Object(fields) {
    fields["code"] = Json::string(code)
  }
  (next, observation)
}

///|
/// Offline traces call the shipped reducer. Expectations and verdicts stay in
/// the parent MCK; no host authentication, execution or RPC is claimed here.
fn reduce_execution(input : Json, format : Json) -> Json raise {
  if format != Json::string("json") {
    raise @executions.Invalid("workbench.invalid_request")
  }
  ignore(
    closed_fields(
      input,
      ["offer", "identity", "calls", "initial", "actions"],
      "workbench.invalid_execution_trace",
    ),
  )
  let offer = @executions.Offer::from_json(field(input, "offer"))
  let identity = @executions.Identity::from_json(field(input, "identity"))
  guard field(input, "calls") is Array(calls) else {
    raise @executions.Invalid("workbench.invalid_execution_trace")
  }
  let calls = calls.map(value => {
    guard value is String(name) else {
      raise @executions.Invalid("workbench.execution_identity")
    }
    name
  })
  let initial = @executions.Receipt::from_json(field(input, "initial"))
  let mut cursor = @executions.Cursor::start(offer, identity, calls, initial)
  guard field(input, "actions") is Array(values) else {
    raise @executions.Invalid("workbench.invalid_execution_trace")
  }
  if values.length() > 64 {
    raise @executions.Invalid("workbench.execution_limit")
  }
  // Reject syntax for the whole trace before running any action. Receipt and
  // offer payload admission happens per action and leaves the cursor intact.
  let actions = values.map(execution_action)
  let observations = []
  for action in actions {
    let (next, observation) = execution_step(cursor, action)
    cursor = next
    observations.push(observation)
  }
  let projection : Json = {
    "identity": identity.to_json(),
    "receipt": cursor.latest().to_json(),
    "connected": cursor.connected(),
    "cancelAction": cancel_action(cursor),
    "observations": observations,
  }
  if @utf8.encode(projection.stringify()).length() > 1024 * 1024 {
    raise @executions.Invalid("workbench.execution_limit")
  }
  projection
}
