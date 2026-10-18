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
pub(all) struct SchemeExecutionProjection {
  identity : @receipts.Identity
  plan_id : String
  runtime : SchemeRuntime
  policy : @execution.CapabilityPolicy
  boundary : Json
}

///|
priv enum ExecutionKind {
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
fn Execution::scheme_plan(self : Execution) -> @execution.SchemePlan raise {
  guard self.kind is Scheme(_, Scheme, policy, boundary) else {
    raise Invalid("workbench.host_execution_kind")
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
) -> SchemeExecutionProjection raise {
  let execution = self.lookup(identity)
  guard execution.kind is Scheme(plan_id, runtime, policy, _) else {
    raise Invalid("workbench.host_execution_kind")
  }
  {
    identity: execution.identity,
    plan_id,
    runtime,
    policy,
    boundary: execution.scheme_plan().boundary_json(),
  }
}

///|
fn Execution::check_scheme_selection(
  self : Execution,
  expected_plan_id : String,
  expected_provider_id : String,
  expected_runtime : SchemeRuntime,
  expected_policy : @execution.CapabilityPolicy,
) -> Unit raise {
  guard self.kind is Scheme(plan_id, runtime, policy, _) else {
    raise Invalid("workbench.host_execution_kind")
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
  let execution = self.lookup(identity)
  execution.check_scheme_selection(
    expected_plan_id, expected_provider_id, expected_runtime, expected_policy,
  )
  let latest = execution.cursor.latest()
  guard latest.state() is Submitted else {
    raise Invalid("workbench.host_already_claimed")
  }
  let plan = execution.scheme_plan()
  ignore(
    self.advance(
      execution,
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
/// Replan only the original accepted input. This allocates a new independent execution
/// and never claims, revokes or reschedules either execution.
pub fn Session::replan_scheme(
  self : Session,
  identity : @receipts.Identity,
  expected_plan_id : String,
  expected_provider_id : String,
  expected_runtime : SchemeRuntime,
  expected_policy : @execution.CapabilityPolicy,
) -> @receipts.Receipt raise {
  let execution = self.lookup(identity)
  execution.check_scheme_selection(
    expected_plan_id, expected_provider_id, expected_runtime, expected_policy,
  )
  let plan = execution.scheme_plan()
  self.submit_scheme(plan.unit(), plan.suite(), policy=plan.policy())
}
