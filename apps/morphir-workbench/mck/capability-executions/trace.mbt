///|
priv struct TracedExecution {
  identity : @receipts.Identity
  mut plan : Json
  mut receipt : @receipts.Receipt
  mut released : Bool
  mut claimed_context : (@engine.CapabilityPolicy, Json)?
}

///|
fn runtime_name(runtime : @host.SchemeRuntime) -> String {
  match runtime {
    Scheme => "scheme"
  }
}

///|
fn plan_json(plan : @host.SchemeExecutionProjection) -> Json {
  {
    "profile": "morphir/workbench/execution-plan",
    "contractVersion": "0.2.0-draft.1",
    "identity": plan.identity.to_json(),
    "planId": plan.plan_id,
    "runtime": runtime_name(plan.runtime),
    "evaluator": "scheme-portable-v1/shared-sdk/bounded",
    "admission": {
      "profile": "morphir/workbench/admission",
      "contractVersion": "0.1.0-draft.1",
      "policy": policy_name(plan.policy),
    },
    "boundary": plan.boundary,
  }
}

///|
fn TracedExecution::refresh(
  self : TracedExecution,
  session : @host.Session,
) -> Unit raise {
  self.plan = plan_json(session.describe_scheme(self.identity))
  self.receipt = session.query(self.identity)
}

///|
fn TracedExecution::capture(
  session : @host.Session,
  receipt : @receipts.Receipt,
) -> TracedExecution raise {
  {
    identity: receipt.identity(),
    plan: plan_json(session.describe_scheme(receipt.identity())),
    receipt: session.query(receipt.identity()),
    released: false,
    claimed_context: None,
  }
}

///|
/// The worker's actual returned context is observed, not reconstructed from an
/// expected boundary or substituted with the owner's descriptor.
fn TracedExecution::observed_plan(self : TracedExecution) -> Json {
  match (self.plan, self.claimed_context) {
    (Object(fields), Some((policy, boundary))) => {
      let result = fields.copy()
      result["boundary"] = boundary
      result["admission"] = {
        "profile": "morphir/workbench/admission",
        "contractVersion": "0.1.0-draft.1",
        "policy": policy_name(policy),
      }
      Json::object(result)
    }
    _ => self.plan
  }
}

///|
fn TracedExecution::view(
  self : TracedExecution,
  session : @host.Session,
  claimed_policy~ : @engine.CapabilityPolicy? = None,
) -> Json raise {
  self.refresh(session)
  {
    "planId": field_value(self.plan, "planId"),
    "runtime": field_value(self.plan, "runtime"),
    "policy": match claimed_policy {
      Some(policy) => Json::string(policy_name(policy))
      None => field_value(field_value(self.plan, "admission"), "policy")
    },
    "sequence": self.receipt.sequence(),
    "state": field_value(self.receipt.to_json(), "state"),
    "cancelRequested": self.receipt.cancel_requested(),
  }
}

///|
fn execution_index(value : Json) -> Int32 raise {
  match value {
    Number(n, ..) if n >= 0 && n <= 3 && n.floor() == n => n.to_int()
    _ => raise @host.Invalid("workbench.host_unknown_execution")
  }
}

///|
fn execution_at(
  executions : Array[TracedExecution],
  index : Int32,
) -> TracedExecution raise {
  guard executions.get(index) is Some(execution) else {
    // No owner identity exists for this binding-local reference.
    raise @host.Invalid("workbench.host_unknown_execution")
  }
  execution
}

///|
fn action_selection(
  action : Json,
) -> (String, String, @host.SchemeRuntime, @engine.CapabilityPolicy) raise {
  let selection = field_value(action, "selection")
  let policy = match @wire.string(field_value(selection, "policy")) {
    "strict" => @engine.Strict
    "permissive" => @engine.Permissive
    _ => raise @host.Invalid("workbench.host_selection_mismatch")
  }
  if field_value(selection, "runtime") != Json::string("scheme") {
    // The closed production enum cannot represent another runtime. Refuse at
    // the binding before claiming, never coerce to Scheme or change policy.
    raise @host.Invalid("workbench.host_selection_mismatch")
  }
  (
    @wire.string(field_value(selection, "planId")),
    @wire.string(field_value(selection, "providerId")),
    @host.Scheme,
    policy,
  )
}

///|
fn supplied_outcomes(value : Json) -> @protocol.Outcomes raise {
  let source = @wire.string(field_value(value, "source"))
  let format = @wire.string(field_value(value, "format"))
  if format == "json" {
    ignore(@wire.parse_bounded(source, max_depth=512)) catch {
      @wire.Invalid("json_limit", _) =>
        raise @protocol.Invalid("execution.value_limit")
      error => raise error
    }
  }
  @protocol.Outcomes::decode(@utf8.encode(source), format)
}

///|
fn action_observation(
  op : String,
  execution : Json,
  status : String,
  code : Json,
  view : Json,
) -> Json {
  {
    "op": op,
    "execution": execution,
    "status": status,
    "code": code,
    "view": view,
  }
}

///|
fn perform_action(
  action : Json,
  session : @host.Session,
  executions : Array[TracedExecution],
  unit : @data.IRUnit,
  suite : @protocol.Suite,
  defaults : Ref[@engine.CapabilityPolicy],
) -> Json raise {
  let op = @wire.string(field_value(action, "op"))
  if op == "mutate-caller" {
    for call in suite.calls {
      call.arguments.clear()
    }
    suite.calls.clear()
    if unit.distribution.distribution is Library(_, _, definition) {
      definition.modules.clear()
    }
    defaults.val = if field_value(action, "policy") ==
      Json::string("permissive") {
      @engine.Permissive
    } else {
      @engine.Strict
    }
    return action_observation(
      op,
      Json::null(),
      "ok",
      Json::null(),
      Json::null(),
    )
  }
  if op == "transport-gap" {
    // A transport gap grants no authority and performs no owner operation.
    return action_observation(
      op,
      Json::null(),
      "ok",
      Json::null(),
      Json::null(),
    )
  }
  let index = execution_index(field_value(action, "execution"))
  let execution = execution_at(executions, index)
  let mut observed_index = index
  let view = match op {
    "inspect" | "query" => execution.view(session)
    "mutate-plan-view" => {
      let exposed = session.describe_scheme(execution.identity)
      if exposed.boundary is Object(fields) {
        fields.clear()
      }
      execution.view(session)
    }
    "query-lost-reply" => {
      ignore(session.query(execution.identity))
      // This separate trusted owner observation is not the discarded client reply.
      return action_observation(
        op,
        Json(index),
        "reply-lost",
        Json::null(),
        execution.view(session),
      )
    }
    "cancel" => {
      ignore(session.cancel(execution.identity))
      execution.view(session)
    }
    "release" => {
      let before = execution.view(session)
      session.release(execution.identity)
      execution.released = true
      before
    }
    "complete" => {
      // Supplied evidence is decoded and validated, never executed.
      let outcomes = supplied_outcomes(field_value(action, "outcomes"))
      ignore(session.complete(execution.identity, outcomes))
      execution.view(session)
    }
    "claim" | "run" | "claim-lost-reply" => {
      let (plan_id, provider_id, runtime, policy) = action_selection(action)
      let plan = session.claim_scheme(
        execution.identity,
        plan_id,
        provider_id,
        runtime,
        policy,
      )
      if op == "claim-lost-reply" {
        // The once-only claim really happened. Drop the real plan and response.
        // Observe the real owner separately after discarding the claimed plan.
        // This view grants no client knowledge or successful reply delivery.
        return action_observation(
          op,
          Json(index),
          "reply-lost",
          Json::null(),
          execution.view(session),
        )
      }
      execution.claimed_context = Some((plan.policy(), plan.boundary_json()))
      if op == "run" {
        let cancelled = session.query(execution.identity).cancel_requested()
        let outcomes = plan.evaluate_outcomes(cancelled=fn() { cancelled })
        ignore(session.complete(execution.identity, outcomes))
      }
      execution.view(session, claimed_policy=Some(plan.policy()))
    }
    "replan" => {
      let (plan_id, provider_id, runtime, policy) = action_selection(action)
      let accepted = session.replan_scheme(
        execution.identity,
        plan_id,
        provider_id,
        runtime,
        policy,
      )
      let fresh = TracedExecution::capture(session, accepted)
      observed_index = executions.length()
      executions.push(fresh)
      fresh.view(session)
    }
    _ => raise @host.Invalid("workbench.invalid_request")
  }
  action_observation(op, Json(observed_index), "ok", Json::null(), view)
}

///|
fn refused_projection(stage : String, code : String) -> Json {
  {
    "executions": [],
    "observations": [],
    "failure": { "stage": stage, "code": code },
  }
}

///|
/// Drives actual Session ownership. No fixture IDs, expected values, or verdicts
/// are available here. The shared Rust MCK decides compatibility independently.
fn observe(input : Json) -> Json {
  let (session, unit, suite, defaults, executions) = try {
    let session = @host.Session::new(
      @receipts.Offer::from_json(field_value(input, "offer")),
      max_executions=4,
    )
    let submission = field_value(input, "submission")
    let unit = @data.Registry::new().open_checkpoint(
      "morphir-json",
      @data.Text(@wire.string(field_value(submission, "model"))),
    )
    let invocation : Json = {
      "profile": "morphir-invocations-v1",
      "calls": @wire.array(field_value(submission, "calls")).map(call => {
        (
          {
            "id": field_value(call, "id"),
            "entry": field_value(call, "entry"),
            "arguments": invocation_arguments(call),
          } : Json)
      }),
    }
    let extension = field_value(submission, "extensions")
    if extension != Json::null() && invocation is Object(fields) {
      fields["extensions"] = extension
    }
    let suite = @protocol.Suite::from_json(invocation)
    let defaults = Ref(selected_policy(submission))
    let receipt = if submission is Object(fields) &&
      !fields.contains("admission") {
      // Exercise the actual production default, not an observer-supplied echo.
      session.submit_scheme(unit, suite)
    } else {
      session.submit_scheme(unit, suite, policy=defaults.val)
    }
    (
      session,
      unit,
      suite,
      defaults,
      [TracedExecution::capture(session, receipt)],
    )
  } catch {
    error => return refused_projection("startup", error_code(error))
  }
  let observations = []
  let actions = match field_value(input, "actions") {
    Array(actions) => actions
    _ => abort("validated trace actions")
  }
  for action in actions {
    let observed = perform_action(
      action, session, executions, unit, suite, defaults,
    ) catch {
      error => {
        let index = field_value(action, "execution")
        let view = try {
          let execution = execution_at(executions, execution_index(index))
          execution.view(session)
        } catch {
          _ => Json::null()
        }
        action_observation(
          @wire.string(field_value(action, "op")) catch {
            _ => ""
          },
          index,
          "invalid",
          Json::string(error_code(error)),
          view,
        )
      }
    }
    observations.push(observed)
  }
  for execution in executions {
    if !execution.released {
      // Final owner state is observed afresh; failed actions never predict it.
      execution.refresh(session) catch {
        error =>
          abort(
            "workbench: final owner observation failed: " + error_code(error),
          )
      }
    }
  }
  let retained = executions.map(execution => {
    (
      {
        "plan": execution.observed_plan(),
        "receipt": execution.receipt.to_json(),
        "released": execution.released,
      } : Json)
  })
  let result : Json = {
    "executions": retained,
    "observations": observations,
    "failure": null,
  }
  if @utf8.encode(result.stringify()).length() > 1048576 {
    // View unavailable after actual effects. This is explicitly not a rollback.
    refused_projection("projection", "workbench.projection_limit")
  } else {
    result
  }
}
