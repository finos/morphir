///|
test "Scheme execution host captures effective policy and guards the once-only claim" {
  let host = @executions.Host::new(offer().stringify())
  let submission_body = match body() {
    Object(fields) => {
      fields["runtime"] = "scheme"
      fields["providerId"] = "moonbit-scheme"
      fields["admission"] = {
        "profile": "morphir/workbench/admission",
        "contractVersion": "0.1.0-draft.1",
        "policy": "permissive",
      }
      Json::object(fields)
    }
    _ => abort("fixture")
  }
  let reply = host.handle(
    ({ "op": "submit-scheme", "body": submission_body.stringify() } : Json).stringify(),
  )
  assert_true(ok(reply))
  let submitted = value(reply)
  let identity = @wire.field(submitted, "identity")
  let plan = @wire.field(submitted, "plan")
  assert_eq(@wire.field(plan, "planId"), Json::string("plan-1"))
  assert_eq(@wire.field(plan, "runtime"), Json::string("scheme"))
  let selection : Json = {
    "planId": @wire.field(plan, "planId"),
    "providerId": "replacement",
    "runtime": "scheme",
    "policy": "permissive",
  }
  assert_false(
    ok(
      host.handle(
        (
          { "op": "claim-scheme", "identity": identity, "selection": selection } :
          Json).stringify(),
      ),
    ),
  )
  guard selection is Object(fields) else { abort("fixture") }
  fields["providerId"] = "moonbit-scheme"
  let claim : Json = {
    "op": "claim-scheme",
    "identity": identity,
    "selection": selection,
  }
  let worker = value(host.handle(claim.stringify()))
  assert_eq(
    @wire.field(worker, "operation"),
    Json::string("evaluate-scheme-execution"),
  )
  assert_eq(@wire.field(worker, "plan"), plan)
  assert_false(ok(host.handle(claim.stringify())))
  let current = value(
    host.handle(
      ({ "op": "plan-scheme", "body": request(identity) } : Json).stringify(),
    ),
  )
  assert_eq(current, plan)
}

///|
test "native checking cursor validates the accepted selection and typed terminal before committing evidence" {
  let host = @executions.Host::new(offer().stringify())
  let client = @executions.Client::new()
  let payload = body()
  guard payload is Object(request_fields) else { abort("fixture") }
  request_fields["runtime"] = "scheme"
  request_fields["providerId"] = "moonbit-scheme"
  request_fields["admission"] = {
    "profile": "morphir/workbench/admission",
    "contractVersion": "0.1.0-draft.1",
    "policy": "permissive",
  }
  let source = payload.stringify()
  assert_true(
    ok(
      client.handle(
        (
          { "op": "validate-native-policy", "offer": offer(), "body": source } :
          Json).stringify(),
      ),
    ),
  )
  let accepted = value(
    host.handle(({ "op": "submit-scheme", "body": source } : Json).stringify()),
  )
  let initial = @wire.field(accepted, "receipt")
  let identity = @wire.field(accepted, "identity")
  let projection = @wire.field(accepted, "plan")
  let start : Json = {
    "op": "start-native-policy",
    "offer": offer(),
    "body": source,
    "plan": projection,
    "identity": identity,
    "calls": ["workbench"],
    "receipt": initial,
  }
  let tampered = @executions.decode(start.stringify())
  guard tampered is Object(changed) &&
    @wire.field(changed["plan"], "admission") is Object(checks) else {
    abort("fixture")
  }
  checks["policy"] = "strict"
  assert_false(ok(client.handle(tampered.stringify())))
  assert_false(ok(client.handle("{\"op\":\"view\"}")))
  assert_true(ok(client.handle(start.stringify())))
  let before = client.handle("{\"op\":\"view\"}")
  let invalid = @executions.decode(initial.stringify())
  guard invalid is Object(terminal) else { abort("fixture") }
  terminal["state"] = "terminal"
  terminal["sequence"] = Json::number(2)
  terminal["outcomes"] = outcomes(
    value=({ "type": "bool", "value": true } : Json),
  )
  assert_false(
    ok(
      client.handle(
        ({ "op": "observe", "receipt": invalid } : Json).stringify(),
      ),
    ),
  )
  assert_eq(client.handle("{\"op\":\"view\"}"), before)
  terminal["outcomes"] = outcomes()
  let completed = client.handle(
    ({ "op": "observe", "receipt": invalid } : Json).stringify(),
  )
  assert_true(ok(completed))
  assert_eq(
    @wire.field(@wire.field(completed, "result"), "admission"),
    request_fields["admission"],
  )
  assert_eq(
    @wire.field(@wire.field(completed, "result"), "executionPlan"),
    projection,
  )
  // Releasing and submitting anew cannot turn a replayed accepted identity into
  // another execution, even when the source and selected policy are identical.
  assert_false(ok(client.handle(start.stringify())))
  assert_eq(client.handle("{\"op\":\"view\"}"), completed)
}

///|
test "native worker selection comes from retained owner state and exposes only independent projections" {
  let host = @executions.Host::new(offer().stringify())
  let payload = body()
  guard payload is Object(fields) else { abort("fixture") }
  fields["runtime"] = "scheme"
  fields["providerId"] = "moonbit-scheme"
  let accepted = value(
    host.handle(
      ({ "op": "submit-scheme", "body": payload.stringify() } : Json).stringify(),
    ),
  )
  let retained = host.scheme_selection(@wire.field(accepted, "identity"))
  let copy = retained.projection()
  guard copy is Object(projection) else { abort("fixture") }
  projection["boundary"] = Json::null()
  projection["runtime"] = "javascript"
  assert_eq(retained.projection(), @wire.field(accepted, "plan"))
  assert_eq(
    @wire.field(host.claim_selected(retained), "plan"),
    retained.projection(),
  )
  let rejected = try {
    ignore(host.claim_selected(retained))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "native page observation budget rejects before another submission and retains terminal evidence" {
  let host = @executions.Host::new(offer().stringify())
  let client = @executions.Client::new()
  let payload = body()
  guard payload is Object(fields) else { abort("fixture") }
  fields["runtime"] = "scheme"
  fields["providerId"] = "moonbit-scheme"
  let source = payload.stringify()
  let accepted = value(
    host.handle(({ "op": "submit-scheme", "body": source } : Json).stringify()),
  )
  let preflight : Json = {
    "op": "validate-native-policy",
    "offer": offer(),
    "body": source,
  }
  for i in 0..<256 {
    assert_true(ok(client.handle(preflight.stringify())))
    let identity : Json = {
      "hostId": "host",
      "sessionId": "session",
      "providerId": "moonbit-scheme",
      "executionId": "execution-" + i.to_string(),
      "snapshotId": "snapshot-" + i.to_string(),
    }
    let plan = @executions.decode(@wire.field(accepted, "plan").stringify())
    guard plan is Object(projection) else { abort("fixture") }
    projection["identity"] = identity
    projection["planId"] = Json::string("plan-" + i.to_string())
    let initial : Json = {
      "contractVersion": "0.2.0-draft.1",
      "identity": identity,
      "sequence": 0,
      "state": "submitted",
      "cancelRequested": false,
      "outcomes": null,
    }
    assert_true(
      ok(
        client.handle(
          (
            {
              "op": "start-native-policy",
              "offer": offer(),
              "body": source,
              "plan": plan,
              "identity": identity,
              "calls": ["workbench"],
              "receipt": initial,
            } : Json).stringify(),
        ),
      ),
    )
    let terminal : Json = {
      "contractVersion": "0.2.0-draft.1",
      "identity": identity,
      "sequence": 1,
      "state": "terminal",
      "cancelRequested": false,
      "outcomes": outcomes(),
    }
    assert_true(
      ok(
        client.handle(
          ({ "op": "observe", "receipt": terminal } : Json).stringify(),
        ),
      ),
    )
  }
  let retained = client.handle("{\"op\":\"view\"}")
  let rejected = client.handle(preflight.stringify())
  assert_false(ok(rejected))
  assert_eq(
    @wire.field(rejected, "code"),
    Json::string("workbench.host_session_capacity"),
  )
  assert_eq(client.handle("{\"op\":\"view\"}"), retained)
}
