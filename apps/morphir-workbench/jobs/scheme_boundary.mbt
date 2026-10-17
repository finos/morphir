///|
fn scheme_policy(value : Json) -> @execution.AdmissionPolicy raise {
  let fields = closed(value, ["profile", "contractVersion", "policy"])
  version(fields)
  guard fields["profile"] == Json::string("morphir/workbench/admission") else {
    raise Invalid("workbench.host_profile")
  }
  scheme_policy_name(fields["policy"])
}

///|
fn scheme_policy_name(value : Json) -> @execution.AdmissionPolicy raise {
  match value {
    String("strict") => Strict
    String("permissive") => Permissive
    _ => raise Invalid("workbench.host_selection_mismatch")
  }
}

///|
fn scheme_projection(plan : @owner.SchemeJobProjection) -> Json {
  {
    "profile": "morphir/workbench/job-plan",
    "contractVersion": "0.1.0-draft.1",
    "identity": plan.identity.to_json(),
    "planId": plan.plan_id,
    "runtime": "scheme",
    "evaluator": "scheme-portable-v1/shared-sdk/bounded",
    "admission": {
      "profile": "morphir/workbench/admission",
      "contractVersion": "0.1.0-draft.1",
      "policy": match plan.policy {
        Strict => "strict"
        Permissive => "permissive"
      },
    },
    "boundary": plan.boundary,
  }
}

///|
fn selection(
  value : Json,
) -> (String, String, @execution.AdmissionPolicy) raise {
  let fields = closed(value, ["planId", "providerId", "runtime", "policy"])
  if fields["runtime"] != Json::string("scheme") {
    raise Invalid("workbench.host_selection_mismatch")
  }
  (
    string(fields["planId"]),
    string(fields["providerId"]),
    scheme_policy_name(fields["policy"]),
  )
}

///|
fn Host::scheme_submission(
  self : Host,
  receipt : @receipts.Receipt,
) -> Json raise {
  {
    "identity": receipt.identity().to_json(),
    "calls": ["workbench"],
    "receipt": receipt.to_json(),
    "plan": scheme_projection(self.owner.describe_scheme(receipt.identity())),
  }
}

///|
/// New private operations. Frozen host submission and receipt shapes are retained.
fn Host::scheme_command(
  self : Host,
  op : String,
  fields : Map[String, Json],
) -> Json raise {
  if op == "submit-scheme" {
    ignore(closed(Json::object(fields), ["op", "body"]))
    let raw = decode(string(fields["body"]))
    guard raw is Object(body) else { raise Invalid("workbench.host_shape") }
    let names = [
      "contractVersion", "model", "entry", "inputs", "runtime", "providerId",
    ]
    let policy = if body.contains("admission") {
      names.push("admission")
      scheme_policy(body["admission"])
    } else {
      @execution.Strict
    }
    ignore(closed(raw, names))
    version(body)
    let authority = closed(self.owner.offer().to_json(), [
      "profile", "contractVersion", "hostId", "sessionId", "providerId", "operations",
    ])
    if body["runtime"] != Json::string("scheme") ||
      body["providerId"] != authority["providerId"] {
      raise Invalid("workbench.host_selection_mismatch")
    }
    let inputs = closed(body["inputs"], ["format", "source"])
    let source = string(inputs["source"])
    let arguments = match inputs["format"] {
      String("json") => decode(source)
      String("ion-text") => {
        admit_ion_structure(source)
        @arguments.ion_arguments(Json::null(), source, true)
      }
      _ => raise Invalid("workbench.host_format")
    }
    let suite = @protocol.Suite::from_json({
      "profile": "morphir-invocations-v1",
      "calls": [
        { "id": "workbench", "entry": body["entry"], "arguments": arguments },
      ],
    })
    let unit = @data.IRUnit::new(
      "workbench",
      @migration.to_current(@versioned.read(string(body["model"]))),
    )
    return self.scheme_submission(
      self.owner.submit_scheme(unit, suite, policy~),
    )
  }
  if op == "plan-scheme" {
    ignore(closed(Json::object(fields), ["op", "body"]))
    let body = closed(decode(string(fields["body"])), [
      "contractVersion", "identity",
    ])
    version(body)
    return scheme_projection(
      self.owner.describe_scheme(
        @receipts.Identity::from_json(body["identity"]),
      ),
    )
  }
  let (body, identity) = if op == "claim-scheme" {
    ignore(closed(Json::object(fields), ["op", "identity", "selection"]))
    (fields, @receipts.Identity::from_json(fields["identity"]))
  } else {
    ignore(closed(Json::object(fields), ["op", "body"]))
    let body = closed(decode(string(fields["body"])), [
      "contractVersion", "identity", "selection",
    ])
    version(body)
    (body, @receipts.Identity::from_json(body["identity"]))
  }
  let (plan_id, provider_id, policy) = selection(body["selection"])
  if op == "replan-scheme" {
    return self.scheme_submission(
      self.owner.replan_scheme(
        identity,
        plan_id,
        provider_id,
        @owner.Scheme,
        policy,
      ),
    )
  }
  let plan = self.owner.claim_scheme(
    identity,
    plan_id,
    provider_id,
    @owner.Scheme,
    policy,
  )
  let unit = plan.unit()
  let snapshot = match @data.Registry::new().encode("ion-binary", unit) {
    Binary(bytes) => @base64.encode(bytes[:])
    Text(_) => raise Invalid("workbench.host_snapshot")
  }
  {
    "operation": "evaluate-scheme-job",
    "snapshot": { "unitId": unit.id, "sourceBase64": snapshot },
    "suite": plan.suite().to_json(),
    "plan": scheme_projection(self.owner.describe_scheme(identity)),
  }
}

///|
/// Reconstruct the exact accepted rich unit and verify its selected boundary in
/// the isolated worker. This is not an authenticated public job-submission API.
pub fn evaluate_scheme_claim(request : Json) -> Json raise {
  let fields = closed(request, ["operation", "snapshot", "suite", "plan"])
  if fields["operation"] != Json::string("evaluate-scheme-job") {
    raise Invalid("workbench.host_operation")
  }
  let projection = closed(fields["plan"], [
    "profile", "contractVersion", "identity", "planId", "runtime", "evaluator", "admission",
    "boundary",
  ])
  version(projection)
  ignore(@receipts.Identity::from_json(projection["identity"]))
  let plan_id = string(projection["planId"])
  if projection["profile"] != Json::string("morphir/workbench/job-plan") ||
    projection["runtime"] != Json::string("scheme") ||
    projection["evaluator"] !=
    Json::string("scheme-portable-v1/shared-sdk/bounded") ||
    plan_id.length() == 0 ||
    plan_id.length() > 128 {
    raise Invalid("workbench.host_selection_mismatch")
  }
  let policy = scheme_policy(projection["admission"])
  let snapshot = closed(fields["snapshot"], ["unitId", "sourceBase64"])
  let encoded = string(snapshot["sourceBase64"])
  if encoded.length() > 5592408 {
    raise Invalid("workbench.host_input_limit")
  }
  let bytes = @base64.decode(encoded[:])
  let unit = @data.Registry::new().decode("ion-binary", {
    unit_id: string(snapshot["unitId"]),
    content: Binary(bytes),
  })
  let suite = @protocol.Suite::from_json(fields["suite"])
  if suite.calls.length() != 1 || suite.calls[0].id != "workbench" {
    raise Invalid("execution.call_identity")
  }
  let plan = @execution.plan_scheme_capabilities(unit, suite, policy~)
  if plan.boundary_json() != projection["boundary"] {
    raise Invalid("workbench.host_boundary_changed")
  }
  let result = @outcomes.prepare(
      {
        "profile": "scheme-portable-v1/shared-sdk/bounded",
        "terminalOutcomes": plan.evaluate_outcomes().to_json(),
      },
      expected_ids=Some(["workbench"]),
    ).0
  guard result is Object(reply) else { raise Invalid("workbench.host_shape") }
  reply["jobPlan"] = fields["plan"]
  result
}
