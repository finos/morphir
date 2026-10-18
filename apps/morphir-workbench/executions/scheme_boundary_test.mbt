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
