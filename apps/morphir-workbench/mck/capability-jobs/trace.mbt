///|
priv struct TracedJob {
  identity : @receipts.Identity
  mut plan : Json
  mut receipt : @receipts.Receipt
  mut released : Bool
  mut claimed_context : (@engine.AdmissionPolicy, Json)?
}

///|
fn runtime_name(runtime : @host.SchemeRuntime) -> String {
  match runtime {
    Scheme => "scheme"
  }
}

///|
fn plan_json(plan : @host.SchemeJobProjection) -> Json {
  {
    "profile": "morphir/workbench/job-plan",
    "contractVersion": "0.1.0-draft.1",
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
fn TracedJob::refresh(self : TracedJob, session : @host.Session) -> Unit raise {
  self.plan = plan_json(session.describe_scheme(self.identity))
  self.receipt = session.query(self.identity)
}

///|
fn TracedJob::capture(
  session : @host.Session,
  receipt : @receipts.Receipt,
) -> TracedJob raise {
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
fn TracedJob::observed_plan(self : TracedJob) -> Json {
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
fn TracedJob::view(
  self : TracedJob,
  session : @host.Session,
  claimed_policy~ : @engine.AdmissionPolicy? = None,
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
fn job_index(value : Json) -> Int32 raise {
  match value {
    Number(n, ..) if n >= 0 && n <= 3 && n.floor() == n => n.to_int()
    _ => raise @host.Invalid("workbench.host_unknown_job")
  }
}

///|
fn job_at(jobs : Array[TracedJob], index : Int32) -> TracedJob raise {
  guard jobs.get(index) is Some(job) else {
    // No owner identity exists for this binding-local reference.
    raise @host.Invalid("workbench.host_unknown_job")
  }
  job
}

///|
fn action_selection(
  action : Json,
) -> (String, String, @host.SchemeRuntime, @engine.AdmissionPolicy) raise {
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
  job : Json,
  status : String,
  code : Json,
  view : Json,
) -> Json {
  { "op": op, "job": job, "status": status, "code": code, "view": view }
}

///|
fn perform_action(
  action : Json,
  session : @host.Session,
  jobs : Array[TracedJob],
  unit : @data.IRUnit,
  suite : @protocol.Suite,
  defaults : Ref[@engine.AdmissionPolicy],
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
  let index = job_index(field_value(action, "job"))
  let job = job_at(jobs, index)
  let mut observed_index = index
  let view = match op {
    "inspect" | "query" => job.view(session)
    "mutate-plan-view" => {
      let exposed = session.describe_scheme(job.identity)
      if exposed.boundary is Object(fields) {
        fields.clear()
      }
      job.view(session)
    }
    "query-lost-reply" => {
      ignore(session.query(job.identity))
      // This separate trusted owner observation is not the discarded client reply.
      return action_observation(
        op,
        Json(index),
        "reply-lost",
        Json::null(),
        job.view(session),
      )
    }
    "cancel" => {
      ignore(session.cancel(job.identity))
      job.view(session)
    }
    "release" => {
      let before = job.view(session)
      session.release(job.identity)
      job.released = true
      before
    }
    "complete" => {
      // Supplied evidence is decoded and validated, never executed.
      let outcomes = supplied_outcomes(field_value(action, "outcomes"))
      ignore(session.complete(job.identity, outcomes))
      job.view(session)
    }
    "claim" | "run" | "claim-lost-reply" => {
      let (plan_id, provider_id, runtime, policy) = action_selection(action)
      let plan = session.claim_scheme(
        job.identity,
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
          job.view(session),
        )
      }
      job.claimed_context = Some((plan.policy(), plan.boundary_json()))
      if op == "run" {
        let cancelled = session.query(job.identity).cancel_requested()
        let outcomes = plan.evaluate_outcomes(cancelled=fn() { cancelled })
        ignore(session.complete(job.identity, outcomes))
      }
      job.view(session, claimed_policy=Some(plan.policy()))
    }
    "replan" => {
      let (plan_id, provider_id, runtime, policy) = action_selection(action)
      let accepted = session.replan_scheme(
        job.identity,
        plan_id,
        provider_id,
        runtime,
        policy,
      )
      let fresh = TracedJob::capture(session, accepted)
      observed_index = jobs.length()
      jobs.push(fresh)
      fresh.view(session)
    }
    _ => raise @host.Invalid("workbench.invalid_request")
  }
  action_observation(op, Json(observed_index), "ok", Json::null(), view)
}

///|
fn refused_projection(stage : String, code : String) -> Json {
  {
    "jobs": [],
    "observations": [],
    "failure": { "stage": stage, "code": code },
  }
}

///|
/// Drives actual Session ownership. No fixture IDs, expected values, or verdicts
/// are available here. The shared Rust MCK decides compatibility independently.
fn observe(input : Json) -> Json {
  let (session, unit, suite, defaults, jobs) = try {
    let session = @host.Session::new(
      @receipts.Offer::from_json(field_value(input, "offer")),
      max_jobs=4,
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
    (session, unit, suite, defaults, [TracedJob::capture(session, receipt)])
  } catch {
    error => return refused_projection("startup", error_code(error))
  }
  let observations = []
  let actions = match field_value(input, "actions") {
    Array(actions) => actions
    _ => abort("validated trace actions")
  }
  for action in actions {
    let observed = perform_action(action, session, jobs, unit, suite, defaults) catch {
      error => {
        let index = field_value(action, "job")
        let view = try {
          let job = job_at(jobs, job_index(index))
          job.view(session)
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
  for job in jobs {
    if !job.released {
      // Final owner state is observed afresh; failed actions never predict it.
      job.refresh(session) catch {
        error =>
          abort(
            "workbench: final owner observation failed: " + error_code(error),
          )
      }
    }
  }
  let retained = jobs.map(job => {
    (
      {
        "plan": job.observed_plan(),
        "receipt": job.receipt.to_json(),
        "released": job.released,
      } : Json)
  })
  let result : Json = {
    "jobs": retained,
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
