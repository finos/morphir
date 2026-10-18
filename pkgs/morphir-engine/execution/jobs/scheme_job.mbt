///|
/// The bounded Library Scheme evaluator with the portable shared SDK.
pub(all) enum SchemeRuntime {
  Scheme
} derive(Eq, Debug)

///|
pub extend SchemeRuntime with Eq::{equal, not_equal}

///|
pub extend SchemeRuntime with @debug.Debug::{to_repr}

///|
/// A fresh observation of accepted selection. Its mutable JSON is not retained.
pub(all) struct SchemeJobProjection {
  identity : @receipts.Identity
  plan_id : String
  runtime : SchemeRuntime
  policy : @execution.CapabilityPolicy
  boundary : Json
}

///|
priv enum JobKind {
  Legacy
  Scheme(String, SchemeRuntime, @execution.CapabilityPolicy, Bytes)
}

///|
pub fn Session::submit_scheme(
  self : Session,
  unit : @data.IRUnit,
  suite : @protocol.Suite,
  policy~ : @execution.CapabilityPolicy = Strict,
) -> @receipts.Receipt raise {
  self.submit_with(unit, suite, Some(policy))
}

///|
fn Job::scheme_plan(self : Job) -> @execution.SchemePlan raise {
  guard self.kind is Scheme(_, Scheme, policy, boundary) else {
    raise Invalid("workbench.host_job_kind")
  }
  let unit = @data.Registry::new().decode("ion-binary", {
    unit_id: self.unit_id,
    content: Binary(self.snapshot),
  })
  let plan = @execution.plan_scheme_capabilities(
    unit,
    @protocol.Suite::decode(self.suite, "json"),
    policy~,
  )
  if @utf8.encode(plan.boundary_json().stringify()) != boundary {
    raise Invalid("workbench.host_boundary_changed")
  }
  plan
}

///|
pub fn Session::describe_scheme(
  self : Session,
  identity : @receipts.Identity,
) -> SchemeJobProjection raise {
  let job = self.lookup(identity)
  guard job.kind is Scheme(plan_id, runtime, policy, _) else {
    raise Invalid("workbench.host_job_kind")
  }
  {
    identity: job.identity,
    plan_id,
    runtime,
    policy,
    boundary: job.scheme_plan().boundary_json(),
  }
}

///|
fn Job::check_scheme_selection(
  self : Job,
  expected_plan_id : String,
  expected_provider_id : String,
  expected_runtime : SchemeRuntime,
  expected_policy : @execution.CapabilityPolicy,
) -> Unit raise {
  guard self.kind is Scheme(plan_id, runtime, policy, _) else {
    raise Invalid("workbench.host_job_kind")
  }
  guard self.identity.to_json() is Object(identity) &&
    identity["providerId"] == Json::string(expected_provider_id) &&
    plan_id == expected_plan_id &&
    runtime == expected_runtime &&
    policy == expected_policy else {
    raise Invalid("workbench.host_selection_mismatch")
  }
}

///|
/// Claim once, with the exact provider, runtime, plan and effective policy.
pub fn Session::claim_scheme(
  self : Session,
  identity : @receipts.Identity,
  expected_plan_id : String,
  expected_provider_id : String,
  expected_runtime : SchemeRuntime,
  expected_policy : @execution.CapabilityPolicy,
) -> @execution.SchemePlan raise {
  let job = self.lookup(identity)
  job.check_scheme_selection(
    expected_plan_id, expected_provider_id, expected_runtime, expected_policy,
  )
  let latest = job.cursor.latest()
  guard latest.state() is Submitted else {
    raise Invalid("workbench.host_already_claimed")
  }
  let plan = job.scheme_plan()
  ignore(
    self.advance(
      job,
      receipt(
        identity,
        latest.sequence() + 1,
        Running,
        latest.cancel_requested(),
      ),
    ),
  )
  plan
}

///|
/// Replan only the original accepted input. This allocates a new independent job
/// and never claims, revokes or reschedules either job.
pub fn Session::replan_scheme(
  self : Session,
  identity : @receipts.Identity,
  expected_plan_id : String,
  expected_provider_id : String,
  expected_runtime : SchemeRuntime,
  expected_policy : @execution.CapabilityPolicy,
) -> @receipts.Receipt raise {
  let job = self.lookup(identity)
  job.check_scheme_selection(
    expected_plan_id, expected_provider_id, expected_runtime, expected_policy,
  )
  let plan = job.scheme_plan()
  self.submit_scheme(plan.unit(), plan.suite(), policy=plan.policy())
}
