///|
/// One retained UI evaluation. Connection availability is separate from evidence.
pub struct Client {
  priv mut cursor : @receipts.Cursor?
}

///|
pub fn Client::new() -> Client {
  { cursor: None, }
}

///|
fn Client::current(self : Client) -> @receipts.Cursor raise {
  guard self.cursor is Some(cursor) else {
    raise Invalid("workbench.host_no_job")
  }
  cursor
}

///|
fn descriptor(value : Json, session : String) -> Json raise {
  let fields = closed(value, ["profile", "contractVersion", "offer"])
  version(fields)
  if fields["profile"] != Json::string("morphir/workbench/host") {
    raise Invalid("workbench.host_profile")
  }
  let offer = @receipts.Offer::from_json(fields["offer"]).to_json()
  guard offer is Object(authority) &&
    authority["sessionId"] == Json::string(session) else {
    raise Invalid("workbench.job_authority")
  }
  {
    "profile": "morphir/workbench/host",
    "contractVersion": "0.1.0-draft.1",
    "offer": offer,
  }
}

///|
pub fn Client::handle(self : Client, source : String) -> Json {
  try {
    let fields = command(source)
    let op = string(fields["op"])
    if op == "decode" {
      ignore(closed(Json::object(fields), ["op", "source"]))
      return { "ok": true, "value": decode(string(fields["source"])) }
    }
    if op == "offer" {
      ignore(closed(Json::object(fields), ["op", "value", "sessionId"]))
      return {
        "ok": true,
        "value": descriptor(fields["value"], string(fields["sessionId"])),
      }
    }
    let cursor = match op {
      "start" => {
        ignore(
          closed(Json::object(fields), [
            "op", "offer", "identity", "calls", "receipt",
          ]),
        )
        if self.cursor is Some(previous) &&
          !(previous.latest().state() is Terminal(_)) {
          raise Invalid("workbench.host_active_job")
        }
        if fields["calls"] != (["workbench"] : Json) {
          raise Invalid("execution.call_identity")
        }
        @receipts.Cursor::start(
          @receipts.Offer::from_json(fields["offer"]),
          @receipts.Identity::from_json(fields["identity"]),
          ["workbench"],
          @receipts.Receipt::from_json(fields["receipt"]),
        )
      }
      "observe" => {
        ignore(closed(Json::object(fields), ["op", "receipt"]))
        self.current().observe(@receipts.Receipt::from_json(fields["receipt"])).0
      }
      "disconnect" => {
        ignore(closed(Json::object(fields), ["op"]))
        self.current().disconnect()
      }
      "reconnect" => {
        ignore(closed(Json::object(fields), ["op", "offer"]))
        self.current().reconnect(@receipts.Offer::from_json(fields["offer"]))
      }
      "view" => {
        ignore(closed(Json::object(fields), ["op"]))
        self.current()
      }
      _ => raise Invalid("workbench.host_operation")
    }
    let receipt = cursor.latest()
    let result = match receipt.state() {
      Terminal(outcomes) =>
        @outcomes.prepare(
          {
            "profile": "scheme-portable-v1/shared-sdk/bounded",
            "terminalOutcomes": outcomes.to_json(),
          },
          expected_ids=Some(["workbench"]),
        ).0
      _ => Json::null()
    }
    let job : Json = {
      "identity": receipt.identity().to_json(),
      "state": match receipt.state() {
        Submitted => "submitted"
        Running => "running"
        Terminal(_) => "terminal"
      },
      "sequence": receipt.sequence(),
      "cancelRequested": receipt.cancel_requested(),
      "connected": cursor.connected(),
      "cancelAction": match cursor.cancel_action() {
        Send => "send"
        Pending => "pending"
        AlreadyTerminal => "already-terminal"
        Unavailable => "unavailable"
        Disconnected => "disconnected"
      },
    }
    self.cursor = Some(cursor)
    { "ok": true, "job": job, "result": result }
  } catch {
    error => failure(error)
  }
}
