///|
fn http_checks() -> Json {
  {
    "profile": "morphir/workbench/admission",
    "contractVersion": "0.1.0-draft.1",
    "runtime": "scheme",
    "evaluator": "scheme-portable-v1/shared-sdk/bounded",
    "policies": ["strict", "permissive"],
  }
}

///|
fn http_policy_body() -> Json raise {
  let payload = body()
  guard payload is Object(fields) else { abort("fixture") }
  fields["contractVersion"] = "0.2.0-draft.2"
  fields["runtime"] = "scheme"
  fields["providerId"] = "moonbit-scheme"
  payload
}

///|
test "HTTP policy descriptor binds authenticated session and accepts only the exact mapping" {
  let client = @executions.Client::new()
  let descriptor : Json = {
    "profile": "morphir/workbench/host",
    "contractVersion": "0.2.0-draft.2",
    "offer": offer(),
    "capabilityChecks": http_checks(),
  }
  let check = fn(value : Json, session : String) {
    client.handle(
      (
        {
          "op": "host-policy-descriptor",
          "source": value.stringify(),
          "sessionId": session,
        } : Json).stringify(),
    )
  }
  assert_eq(value(check(descriptor, "session")), descriptor)
  assert_false(ok(check(descriptor, "another-session")))
  for
    invalid_version in ["0.2.0-draft.1", "0.2.0-draft.2+build", "0.2.0-draft.3"] {
    let changed = @executions.decode(descriptor.stringify())
    guard changed is Object(fields) else { abort("fixture") }
    fields["contractVersion"] = Json::string(invalid_version)
    assert_false(ok(check(changed, "session")))
  }
  for
    invalid_policies in [
      ["strict"],
      ["permissive", "strict"],
      ["strict", "permissive", "future"],
    ] {
    let changed = @executions.decode(descriptor.stringify())
    guard changed is Object(fields) &&
      fields["capabilityChecks"] is Object(checks) else {
      abort("fixture")
    }
    checks["policies"] = Json(invalid_policies)
    assert_false(ok(check(changed, "session")))
  }
}

///|
test "HTTP policy submissions retain default strict and reject frozen or substituted selection" {
  let host = @executions.Host::new(offer().stringify())
  let payload = http_policy_body()
  let source = payload.stringify()
  let client = @executions.Client::new()
  assert_true(
    ok(
      client.handle(
        (
          { "op": "validate-http-policy", "offer": offer(), "body": source } :
          Json).stringify(),
      ),
    ),
  )
  let submitted = value(
    host.handle(
      ({ "op": "submit-http-policy", "body": source } : Json).stringify(),
    ),
  )
  let plan = @wire.field(submitted, "plan")
  assert_eq(
    @wire.field(@wire.field(plan, "admission"), "policy"),
    Json::string("strict"),
  )
  let start : Json = {
    "op": "start-http-policy",
    "offer": offer(),
    "body": source,
    "identity": @wire.field(submitted, "identity"),
    "calls": ["workbench"],
    "receipt": @wire.field(submitted, "receipt"),
    "plan": plan,
  }
  assert_true(ok(client.handle(start.stringify())))
  let before = client.handle("{\"op\":\"view\"}")
  assert_false(ok(client.handle(start.stringify())))
  assert_eq(client.handle("{\"op\":\"view\"}"), before)
  guard payload is Object(fields) else { abort("fixture") }
  fields["contractVersion"] = "0.2.0-draft.1"
  assert_false(
    ok(
      host.handle(
        ({ "op": "submit-http-policy", "body": payload.stringify() } : Json).stringify(),
      ),
    ),
  )
  fields["contractVersion"] = "0.2.0-draft.2"
  fields["providerId"] = "replacement"
  assert_false(
    ok(
      host.handle(
        ({ "op": "submit-http-policy", "body": payload.stringify() } : Json).stringify(),
      ),
    ),
  )
}
