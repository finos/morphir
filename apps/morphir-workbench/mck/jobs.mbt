///|
priv enum JobAction {
  Observe(Json)
  Reconnect(Json)
  Disconnect
  CancelAction
}

///|
fn JobAction::name(self : JobAction) -> String {
  match self {
    Observe(_) => "observe"
    Reconnect(_) => "reconnect"
    Disconnect => "disconnect"
    CancelAction => "cancel-action"
  }
}

///|
fn job_action(value : Json) -> JobAction raise {
  let names = match field(value, "op") {
    String("observe") => ["op", "receipt"]
    String("reconnect") => ["op", "offer"]
    String("disconnect" | "cancel-action") => ["op"]
    _ => raise @jobs.Invalid("workbench.invalid_job_trace")
  }
  ignore(closed_fields(value, names, "workbench.invalid_job_trace"))
  match field(value, "op") {
    String("observe") => Observe(field(value, "receipt"))
    String("reconnect") => Reconnect(field(value, "offer"))
    String("disconnect") => Disconnect
    _ => CancelAction
  }
}

///|
fn cancel_action(cursor : @jobs.Cursor) -> String {
  match cursor.cancel_action() {
    Send => "send"
    Pending => "pending"
    AlreadyTerminal => "already-terminal"
    Unavailable => "unavailable"
    Disconnected => "disconnected"
  }
}

///|
fn job_view(cursor : @jobs.Cursor) -> Json raise {
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
fn job_step(
  cursor : @jobs.Cursor,
  action : JobAction,
) -> (@jobs.Cursor, Json) raise {
  let (next, status, code) : (@jobs.Cursor, String, String?) = try {
    let (next, status) = match action {
      Observe(value) => {
        let (next, disposition) = cursor.observe(
          @jobs.Receipt::from_json(value),
        )
        let status = match disposition {
          Advanced => "advanced"
          Replay => "replay"
          Stale => "stale"
        }
        (next, status)
      }
      Reconnect(value) =>
        (cursor.reconnect(@jobs.Offer::from_json(value)), "local")
      Disconnect => (cursor.disconnect(), "local")
      // Selecting a client action does not send a request or acknowledge it.
      CancelAction => (cursor, "local")
    }
    (next, status, None)
  } catch {
    @jobs.Invalid(code) => (cursor, "invalid", Some(code))
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
    "view": job_view(next),
  }
  if code is Some(code) && observation is Object(fields) {
    fields["code"] = Json::string(code)
  }
  (next, observation)
}

///|
/// Offline traces call the shipped reducer. Expectations and verdicts stay in
/// the parent MCK; no host authentication, execution or RPC is claimed here.
fn reduce_job(input : Json, format : Json) -> Json raise {
  if format != Json::string("json") {
    raise @jobs.Invalid("workbench.invalid_request")
  }
  ignore(
    closed_fields(
      input,
      ["offer", "identity", "calls", "initial", "actions"],
      "workbench.invalid_job_trace",
    ),
  )
  let offer = @jobs.Offer::from_json(field(input, "offer"))
  let identity = @jobs.Identity::from_json(field(input, "identity"))
  guard field(input, "calls") is Array(calls) else {
    raise @jobs.Invalid("workbench.invalid_job_trace")
  }
  let calls = calls.map(value => {
    guard value is String(name) else {
      raise @jobs.Invalid("workbench.job_identity")
    }
    name
  })
  let initial = @jobs.Receipt::from_json(field(input, "initial"))
  let mut cursor = @jobs.Cursor::start(offer, identity, calls, initial)
  guard field(input, "actions") is Array(values) else {
    raise @jobs.Invalid("workbench.invalid_job_trace")
  }
  if values.length() > 64 {
    raise @jobs.Invalid("workbench.job_limit")
  }
  // Reject syntax for the whole trace before running any action. Receipt and
  // offer payload admission happens per action and leaves the cursor intact.
  let actions = values.map(job_action)
  let observations = []
  for action in actions {
    let (next, observation) = job_step(cursor, action)
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
    raise @jobs.Invalid("workbench.job_limit")
  }
  projection
}
