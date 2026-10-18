///|
/// One retained UI evaluation. Connection availability is separate from evidence.
priv enum CheckingContext {
  WholeModel
  SelectedScheme(@execution.SchemePlan, String)
}

///|
priv struct SelectedPlanId(String) derive(Eq)

///|
priv struct AcceptedSelection {
  identity : @receipts.Identity
  plan_id : SelectedPlanId
}

///|
fn SelectedPlanId::from_json(value : Json) -> SelectedPlanId raise {
  let value = string(value)
  guard value.length() > 0 && value.length() <= 128 else {
    raise Invalid("workbench.host_selection_mismatch")
  }
  SelectedPlanId(value)
}

///|
fn AcceptedSelection::reused(
  self : AcceptedSelection,
  identity : @receipts.Identity,
  plan_id : SelectedPlanId,
) -> Bool {
  guard self.identity.to_json() is Object(previous) &&
    identity.to_json() is Object(next) else {
    abort("Execution identity")
  }
  previous["hostId"] == next["hostId"] &&
  previous["sessionId"] == next["sessionId"] &&
  previous["providerId"] == next["providerId"] &&
  (
    self.identity.execution_id() == identity.execution_id() ||
    self.plan_id == plan_id
  )
}

///|
priv enum ClientState {
  Empty
  Tracking(@receipts.Cursor, CheckingContext)
}

///|
pub struct Client {
  priv mut state : ClientState
  priv accepted : Array[AcceptedSelection]
}

///|
pub fn Client::new() -> Client {
  { state: Empty, accepted: [], }
}

///|
fn Client::current(self : Client) -> @receipts.Cursor raise {
  guard self.state is Tracking(cursor, _) else {
    raise Invalid("workbench.host_no_execution")
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
    raise Invalid("workbench.execution_authority")
  }
  {
    "profile": "morphir/workbench/host",
    "contractVersion": "0.2.0-draft.1",
    "offer": offer,
  }
}

///|
fn http_policy_descriptor(value : Json, session : String) -> Json raise {
  let fields = closed(value, [
    "profile", "contractVersion", "offer", "capabilityChecks",
  ])
  if fields["contractVersion"] != Json::string("0.2.0-draft.2") {
    raise Invalid("workbench.host_version")
  }
  if fields["profile"] != Json::string("morphir/workbench/host") {
    raise Invalid("workbench.host_profile")
  }
  let offer = @receipts.Offer::from_json(fields["offer"]).to_json()
  guard offer is Object(authority) &&
    authority["sessionId"] == Json::string(session) else {
    raise Invalid("workbench.execution_authority")
  }
  let checks = closed(fields["capabilityChecks"], [
    "profile", "contractVersion", "runtime", "evaluator", "policies",
  ])
  if checks["contractVersion"] != Json::string("0.1.0-draft.1") {
    raise Invalid("workbench.host_version")
  }
  if checks["profile"] != Json::string("morphir/workbench/admission") {
    raise Invalid("workbench.host_profile")
  }
  guard checks["runtime"] == Json::string("scheme") &&
    checks["evaluator"] == Json::string("scheme-portable-v1/shared-sdk/bounded") &&
    checks["policies"] == (["strict", "permissive"] : Json) else {
    raise Invalid("workbench.host_selection_mismatch")
  }
  value
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
    if op == "validate-native-policy" || op == "validate-http-policy" {
      ignore(closed(Json::object(fields), ["op", "offer", "body"]))
      guard self.accepted.length() < 256 else {
        raise Invalid("workbench.host_session_capacity")
      }
      ignore(
        selected_request_plan(
          string(fields["body"]),
          fields["offer"],
          if op == "validate-http-policy" {
            HttpPolicy
          } else {
            NativePolicy
          },
        ),
      )
      return { "ok": true, "value": true }
    }
    if op == "host-policy-descriptor" {
      ignore(closed(Json::object(fields), ["op", "source", "sessionId"]))
      return {
        "ok": true,
        "value": http_policy_descriptor(
          decode(string(fields["source"])),
          string(fields["sessionId"]),
        ),
      }
    }
    if op == "native-descriptor" || op == "native-policy-descriptor" {
      ignore(closed(Json::object(fields), ["op", "source", "sessionId"]))
      let source = string(fields["source"])
      if source.length() > 1048576 {
        raise Invalid("native.reply.limit")
      }
      return {
        "ok": true,
        "value": if op == "native-policy-descriptor" {
          @native_reply.descriptor_policy(
            @utf8.encode(source),
            expected_session=Some(string(fields["sessionId"])),
          )
        } else {
          @native_reply.descriptor(
            @utf8.encode(source),
            expected_session=Some(string(fields["sessionId"])),
          )
        },
      }
    }
    if op == "native-response" || op == "native-policy-response" {
      ignore(
        closed(Json::object(fields), ["op", "source", "operation", "sessionId"]),
      )
      let source = string(fields["source"])
      if source.length() > 1048576 {
        raise Invalid("native.reply.limit")
      }
      let operation = string(fields["operation"])
      let expected_session = if operation == "session.open" &&
        fields["sessionId"] == Json::null() {
        None
      } else {
        Some(string(fields["sessionId"]))
      }
      return {
        "ok": true,
        "value": (if op == "native-policy-response" {
          @native_reply.decode_policy(
            @utf8.encode(source),
            operation,
            expected_session~,
          )
        } else {
          @native_reply.decode(
            @utf8.encode(source),
            operation,
            expected_session~,
          )
        }).to_json(),
      }
    }
    if op == "offer" {
      ignore(closed(Json::object(fields), ["op", "value", "sessionId"]))
      return {
        "ok": true,
        "value": descriptor(fields["value"], string(fields["sessionId"])),
      }
    }
    let mut checking = match self.state {
      Empty => CheckingContext::WholeModel
      Tracking(_, checking) => checking
    }
    let cursor = match op {
      "start" | "start-native-policy" | "start-http-policy" => {
        ignore(
          closed(
            Json::object(fields),
            [
              "op",
              "offer",
              "identity",
              "calls",
              "receipt",
              ..if op == "start-native-policy" || op == "start-http-policy" {
                ["body", "plan"]
              } else {
                []
              },
            ],
          ),
        )
        if self.state is Tracking(previous, _) &&
          !(previous.latest().state() is Terminal(_)) {
          raise Invalid("workbench.host_active_execution")
        }
        if fields["calls"] != (["workbench"] : Json) {
          raise Invalid("execution.call_identity")
        }
        checking = if op == "start-native-policy" || op == "start-http-policy" {
          guard self.accepted.length() < 256 else {
            raise Invalid("workbench.host_session_capacity")
          }
          let identity = @receipts.Identity::from_json(fields["identity"])
          let retained = selected_request_plan(
            string(fields["body"]),
            fields["offer"],
            if op == "start-http-policy" {
              HttpPolicy
            } else {
              NativePolicy
            },
          )
          let accepted = closed(fields["plan"], [
            "profile", "contractVersion", "identity", "planId", "runtime", "evaluator",
            "admission", "boundary",
          ])
          let plan_id = SelectedPlanId::from_json(accepted["planId"])
          guard !self.accepted.any(previous => {
            previous.reused(identity, plan_id)
          }) else {
            raise Invalid("workbench.host_execution_reused")
          }
          let policy = scheme_policy(accepted["admission"])
          guard accepted["profile"] ==
            Json::string("morphir/workbench/execution-plan") &&
            accepted["contractVersion"] == Json::string("0.2.0-draft.1") &&
            accepted["identity"] == fields["identity"] &&
            accepted["runtime"] == Json::string("scheme") &&
            accepted["evaluator"] ==
            Json::string("scheme-portable-v1/shared-sdk/bounded") &&
            policy == retained.policy() &&
            accepted["boundary"] == retained.boundary_json() else {
            raise Invalid("workbench.host_selection_mismatch")
          }
          SelectedScheme(retained, fields["plan"].stringify())
        } else {
          WholeModel
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
      Terminal(outcomes) => {
        if checking is SelectedScheme(plan, _) {
          plan.validate_outcomes(outcomes)
        }
        let result = @outcomes.prepare(
            {
              "profile": "scheme-portable-v1/shared-sdk/bounded",
              "terminalOutcomes": outcomes.to_json(),
            },
            expected_ids=Some(["workbench"]),
          ).0
        if checking is SelectedScheme(plan, projection) &&
          result is Object(result_fields) {
          result_fields["admission"] = {
            "profile": "morphir/workbench/admission",
            "contractVersion": "0.1.0-draft.1",
            "policy": match plan.policy() {
              Strict => "strict"
              Permissive => "permissive"
            },
          }
          result_fields["executionPlan"] = decode(projection)
        }
        result
      }
      _ => Json::null()
    }
    let execution : Json = {
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
    if op == "start-native-policy" || op == "start-http-policy" {
      let projection = closed(fields["plan"], [
        "profile", "contractVersion", "identity", "planId", "runtime", "evaluator",
        "admission", "boundary",
      ])
      self.accepted.push({
        identity: receipt.identity(),
        plan_id: SelectedPlanId::from_json(projection["planId"]),
      })
    }
    self.state = Tracking(cursor, checking)
    { "ok": true, "execution": execution, "result": result }
  } catch {
    error => failure(error)
  }
}
