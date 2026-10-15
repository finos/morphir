///|
/// Exact Workbench jobs profile. It does not advertise a live host capability.
pub(all) suberror Invalid {
  Invalid(String)
}

///|
pub struct Identity {
  priv host : String
  priv session : String
  priv provider : String
  priv job : String
  priv snapshot : String
} derive(Eq)

///|
pub struct Offer {
  priv host : String
  priv session : String
  priv provider : String
  priv cancel : Bool
}

///|
pub enum State {
  Submitted
  Running
  Terminal(@execution.Outcomes)
}

///|
pub struct Receipt {
  priv identity : Identity
  priv sequence : Int
  priv state : State
  priv cancel_requested : Bool
}

///|
pub enum Disposition {
  Advanced
  Replay
  Stale
} derive(Debug)

///|
pub enum CancelAction {
  Send
  Pending
  AlreadyTerminal
  Unavailable
  Disconnected
} derive(Debug)

///|
/// Private canonical evidence prevents caller-owned arrays from changing history.
pub struct Cursor {
  priv identity : Identity
  priv calls : Array[String]
  priv evidence : String
  priv sequence : Int
  priv running : Bool
  priv terminal : Bool
  priv acknowledged : Bool
  priv can_cancel : Bool
  priv online : Bool
}

///|
fn fields(
  value : Json,
  keys : Array[String],
  code : String,
) -> Map[String, Json] raise {
  guard value is Object(values) &&
    values.length() == keys.length() &&
    keys.all(key => values.contains(key)) else {
    raise Invalid(code)
  }
  values
}

///|
fn name(value : Json) -> String raise {
  guard value is String(text) && text.length() > 0 && text.length() <= 128 else {
    raise Invalid("workbench.job_identity")
  }
  text
}

///|
pub fn Identity::from_json(value : Json) -> Identity raise {
  let values = fields(
    value,
    ["hostId", "sessionId", "providerId", "jobId", "snapshotId"],
    "workbench.job_identity",
  )
  {
    host: name(values["hostId"]),
    session: name(values["sessionId"]),
    provider: name(values["providerId"]),
    job: name(values["jobId"]),
    snapshot: name(values["snapshotId"]),
  }
}

///|
pub fn Identity::to_json(self : Identity) -> Json {
  {
    "hostId": self.host,
    "sessionId": self.session,
    "providerId": self.provider,
    "jobId": self.job,
    "snapshotId": self.snapshot,
  }
}

///|
pub fn Offer::from_json(value : Json) -> Offer raise {
  let values = fields(
    value,
    [
      "profile", "contractVersion", "hostId", "sessionId", "providerId", "operations",
    ],
    "workbench.job_negotiation",
  )
  guard values["profile"] == Json::string("morphir/workbench/jobs") &&
    values["contractVersion"] == Json::string("0.1.0-draft.1") &&
    values["operations"] is Array(operations) &&
    operations.length() >= 1 &&
    operations.length() <= 2 &&
    operations.contains(Json::string("query")) &&
    operations.all(op => {
      op == Json::string("query") || op == Json::string("cancel")
    }) &&
    (operations.length() == 1 || operations[0] != operations[1]) else {
    raise Invalid("workbench.job_negotiation")
  }
  {
    host: name(values["hostId"]),
    session: name(values["sessionId"]),
    provider: name(values["providerId"]),
    cancel: operations.contains(Json::string("cancel")),
  }
}

///|
pub fn Offer::to_json(self : Offer) -> Json {
  {
    "profile": "morphir/workbench/jobs",
    "contractVersion": "0.1.0-draft.1",
    "hostId": self.host,
    "sessionId": self.session,
    "providerId": self.provider,
    "operations": Json::array(
      if self.cancel {
        [Json::string("query"), Json::string("cancel")]
      } else {
        [Json::string("query")]
      },
    ),
  }
}

///|
fn Offer::bind(self : Offer, identity : Identity) -> Unit raise {
  if self.host != identity.host ||
    self.session != identity.session ||
    self.provider != identity.provider {
    raise Invalid("workbench.job_authority")
  }
}

///|
pub fn Receipt::from_json(value : Json) -> Receipt raise {
  if @utf8.encode(value.stringify()).length() > 1024 * 1024 {
    raise Invalid("workbench.job_limit")
  }
  let values = fields(
    value,
    [
      "contractVersion", "identity", "sequence", "state", "cancelRequested", "outcomes",
    ],
    "workbench.job_receipt",
  )
  guard values["contractVersion"] == Json::string("0.1.0-draft.1") &&
    values["sequence"] is Number(sequence, ..) &&
    sequence >= 0 &&
    sequence <= 2147483647 &&
    sequence.floor() == sequence &&
    (values["cancelRequested"] is True || values["cancelRequested"] is False) else {
    raise Invalid("workbench.job_receipt")
  }
  let acknowledged = values["cancelRequested"] == Json::boolean(true)
  let state = match values["state"] {
    String("submitted") if values["outcomes"] == Json::null() => Submitted
    String("running") if sequence > 0 && values["outcomes"] == Json::null() =>
      Running
    String("terminal") if sequence > 0 =>
      Terminal(@execution.Outcomes::from_json(values["outcomes"]))
    _ => raise Invalid("workbench.job_receipt")
  }
  if sequence == 0 && (!(state is Submitted) || acknowledged) {
    raise Invalid("workbench.job_receipt")
  }
  {
    identity: Identity::from_json(values["identity"]),
    sequence: sequence.to_int(),
    state,
    cancel_requested: acknowledged,
  }
}

///|
pub fn Receipt::to_json(self : Receipt) -> Json {
  let (state, outcomes) = match self.state {
    Submitted => ("submitted", Json::null())
    Running => ("running", Json::null())
    Terminal(value) => ("terminal", value.to_json())
  }
  {
    "contractVersion": "0.1.0-draft.1",
    "identity": self.identity.to_json(),
    "sequence": self.sequence,
    "state": state,
    "cancelRequested": self.cancel_requested,
    "outcomes": outcomes,
  }
}

///|
pub fn Receipt::state(self : Receipt) -> State {
  self.state
}

///|
pub fn Receipt::identity(self : Receipt) -> Identity {
  self.identity
}

///|
pub fn Receipt::sequence(self : Receipt) -> Int {
  self.sequence
}

///|
pub fn Receipt::cancel_requested(self : Receipt) -> Bool {
  self.cancel_requested
}

///|
pub fn Cursor::start(
  offer : Offer,
  expected : Identity,
  calls : Array[String],
  receipt : Receipt,
) -> Cursor raise {
  offer.bind(expected)
  if receipt.identity != expected {
    raise Invalid("workbench.job_identity")
  }
  if receipt.sequence != 0 ||
    !(receipt.state is Submitted) ||
    receipt.cancel_requested {
    raise Invalid("workbench.job_transition")
  }
  if calls.is_empty() || calls.length() > 1000 {
    raise Invalid("workbench.job_limit")
  }
  let seen = Map([])
  for call in calls {
    ignore(name(Json::string(call)))
    if seen.contains(call) {
      raise Invalid("execution.call_identity")
    }
    seen[call] = true
  }
  {
    identity: expected,
    calls: calls.copy(),
    evidence: receipt.to_json().stringify(),
    sequence: 0,
    running: false,
    terminal: false,
    acknowledged: false,
    can_cancel: offer.cancel,
    online: true,
  }
}

///|
pub fn Cursor::observe(
  self : Cursor,
  receipt : Receipt,
) -> (Cursor, Disposition) raise {
  if !self.online {
    raise Invalid("workbench.job_disconnected")
  }
  if receipt.identity != self.identity {
    raise Invalid("workbench.job_identity")
  }
  // Re-admit public receipt payloads before replay/order checks. This also
  // prevents mutated or malformed stale terminal data from being accepted.
  let receipt = Receipt::from_json(receipt.to_json())
  if receipt.state is Terminal(outcomes) {
    if outcomes.calls.length() != self.calls.length() {
      raise Invalid("execution.result_count")
    }
    for i, call in outcomes.calls {
      if call.id != self.calls[i] {
        raise Invalid("execution.call_identity")
      }
    }
  }
  if receipt.cancel_requested && !self.can_cancel {
    raise Invalid("workbench.job_negotiation")
  }
  if receipt.sequence < self.sequence {
    return (self, Stale)
  }
  let evidence = receipt.to_json().stringify()
  if receipt.sequence == self.sequence {
    if receipt.to_json() != self.latest().to_json() {
      raise Invalid("workbench.job_conflict")
    }
    return (self, Replay)
  }
  if self.terminal ||
    (self.running && receipt.state is Submitted) ||
    (self.acknowledged && !receipt.cancel_requested) ||
    (
      !(receipt.state is Terminal(_)) &&
      self.running == (receipt.state is Running) &&
      self.acknowledged == receipt.cancel_requested
    ) {
    raise Invalid("workbench.job_transition")
  }
  (
    {
      ..self,
      evidence,
      sequence: receipt.sequence,
      running: receipt.state is Running,
      terminal: receipt.state is Terminal(_),
      acknowledged: receipt.cancel_requested,
    },
    Advanced,
  )
}

///|
pub fn Cursor::latest(self : Cursor) -> Receipt raise {
  Receipt::from_json(@json.parse(self.evidence))
}

///|
pub fn Cursor::connected(self : Cursor) -> Bool {
  self.online
}

///|
pub fn Cursor::disconnect(self : Cursor) -> Cursor {
  { ..self, online: false, }
}

///|
pub fn Cursor::reconnect(self : Cursor, offer : Offer) -> Cursor raise {
  offer.bind(self.identity)
  if offer.cancel != self.can_cancel {
    raise Invalid("workbench.job_negotiation")
  }
  { ..self, online: true, }
}

///|
/// This only selects a client action. Sending it never changes host evidence.
pub fn Cursor::cancel_action(self : Cursor) -> CancelAction {
  if self.terminal {
    AlreadyTerminal
  } else if !self.online {
    Disconnected
  } else if !self.can_cancel {
    Unavailable
  } else if self.acknowledged {
    Pending
  } else {
    Send
  }
}

///|
pub extend Identity with Eq::{equal, not_equal}

///|
pub extend Disposition with @debug.Debug::{to_repr}

///|
pub extend CancelAction with @debug.Debug::{to_repr}
