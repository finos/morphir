///|
fn request(
  actions : Array[Json],
  model~ : String = (
    #|{"formatVersion":4,"distribution":{"Library":{"packageName":"selected","dependencies":{},"def":{"modules":{"main":{"Public":{"types":{},"values":{"answer":{"Public":{"doc":"Selected public Int42","ExpressionBody":{"inputTypes":{},"outputType":"morphir/SDK:basics#int","body":{"Literal":{"IntegerLiteral":42}}}}}}}}}}}}}
  ),
) -> Json {
  {
    "id": 1,
    "op": "run-capability-jobs",
    "suite": "workbench",
    "contractVersion": "0.1.0-draft.13",
    "format": "json",
    "input": {
      "offer": {
        "profile": "morphir/workbench/jobs",
        "contractVersion": "0.1.0-draft.1",
        "hostId": "host",
        "sessionId": "session",
        "providerId": "scheme",
        "operations": ["query", "cancel"],
      },
      "submission": {
        "model": model,
        "calls": [
          {
            "id": "first",
            "entry": "selected:main#answer",
            "inputs": { "format": "json", "source": "[]" },
          },
        ],
        "runtime": "scheme",
        "extensions": null,
        "admission": {
          "profile": "morphir/workbench/admission",
          "contractVersion": "0.1.0-draft.1",
          "policy": "permissive",
        },
      },
      "actions": actions,
    },
  }
}

///|
fn selection() -> Json {
  {
    "planId": "plan-1",
    "providerId": "scheme",
    "runtime": "scheme",
    "policy": "permissive",
  }
}

///|
fn field(value : Json, name : String) -> Json {
  guard value is Object(fields) else { abort("object") }
  fields[name]
}

///|
fn trace(actions : Array[Json]) -> Json {
  field(@adapter.handle_line(request(actions).stringify()).unwrap(), "value")
}

///|
fn item(value : Json, name : String, index : Int32) -> Json {
  guard field(value, name) is Array(items) else { abort("array") }
  items[index]
}

///|
test "capability jobs negotiates only its exact offline trace operation" {
  for version in ["0.1.0-draft.11", "0.1.0-draft.12", "0.1.0-draft.13+local"] {
    let response = @adapter.handle_line(
      (
        {
          "id": 1,
          "op": "capabilities",
          "suite": "workbench",
          "contractVersion": version,
        } : Json).stringify(),
    ).unwrap()
    assert_eq(field(response, "status"), Json::string("invalid"))
  }
  let response = @adapter.handle_line(
    "{\"id\":1,\"op\":\"capabilities\",\"suite\":\"workbench\",\"contractVersion\":\"0.1.0-draft.13\"}",
  ).unwrap()
  assert_eq(field(response, "operations"), (["run-capability-jobs"] : Json))
  assert_eq(@adapter.handle_line("{\"id\":1,\"op\":\"exit\"}"), None)
}

///|
test "capability jobs executes captured source and calls after caller mutation" {
  let result = trace([
    { "op": "mutate-caller", "policy": "strict" },
    { "op": "mutate-plan-view", "job": 0 },
    { "op": "run", "job": 0, "selection": selection() },
  ])
  assert_eq(field(result, "failure"), Json::null())
  let job = item(result, "jobs", 0)
  let plan = field(job, "plan")
  assert_eq(
    field(field(plan, "admission"), "policy"),
    Json::string("permissive"),
  )
  let receipt = field(job, "receipt")
  assert_eq(field(receipt, "state"), Json::string("terminal"))
  assert_eq(field(receipt, "sequence"), Json::number(2))
  let outcome = field(item(field(receipt, "outcomes"), "calls", 0), "outcome")
  assert_eq(field(outcome, "status"), Json::string("returned"))
  assert_eq(field(field(outcome, "value"), "value"), Json::string("42"))
}

///|
test "capability jobs lost claim and transport gap cannot reset once only ownership" {
  let result = trace([
    { "op": "claim-lost-reply", "job": 0, "selection": selection() },
    { "op": "transport-gap" },
    { "op": "run", "job": 0, "selection": selection() },
  ])
  assert_eq(
    field(item(result, "observations", 0), "status"),
    Json::string("reply-lost"),
  )
  assert_eq(
    field(field(item(result, "observations", 0), "view"), "state"),
    Json::string("running"),
  )
  assert_eq(
    field(item(result, "observations", 2), "code"),
    Json::string("workbench.host_already_claimed"),
  )
  assert_eq(
    field(field(item(result, "jobs", 0), "receipt"), "state"),
    Json::string("running"),
  )
}

///|
test "capability jobs supplies completion separately from actual precancelled execution" {
  let supplied = trace([
    {
      "op": "complete",
      "job": 0,
      "outcomes": {
        "format": "json",
        "source": "{\"contractVersion\":\"0.1.0-draft.5\",\"calls\":[{\"id\":\"first\",\"outcome\":{\"status\":\"cancelled\"}}],\"cleanup\":null,\"extensions\":null}",
      },
    },
  ])
  let actual = trace([
    { "op": "cancel", "job": 0 },
    { "op": "run", "job": 0, "selection": selection() },
  ])
  let supplied_receipt = field(item(supplied, "jobs", 0), "receipt")
  let actual_receipt = field(item(actual, "jobs", 0), "receipt")
  assert_eq(field(supplied_receipt, "sequence"), Json::number(1))
  assert_eq(field(supplied_receipt, "cancelRequested"), Json::boolean(false))
  assert_eq(field(actual_receipt, "sequence"), Json::number(3))
  assert_eq(field(actual_receipt, "cancelRequested"), Json::boolean(true))
  assert_eq(
    field(
      field(item(field(actual_receipt, "outcomes"), "calls", 0), "outcome"),
      "status",
    ),
    Json::string("cancelled"),
  )
}

///|
test "capability jobs bounds trace history before owner effects" {
  let action : Json = { "op": "replan", "job": 0, "selection": selection() }
  let response = @adapter.handle_line(
    request([action, action, action, action]).stringify(),
  ).unwrap()
  assert_eq(field(response, "status"), Json::string("invalid"))
}

///|
test "capability jobs omission uses production strict default before local default edit" {
  let strict_selection : Json = {
    "planId": "plan-1",
    "providerId": "scheme",
    "runtime": "scheme",
    "policy": "strict",
  }
  let source = request([
    { "op": "mutate-caller", "policy": "permissive" },
    { "op": "run", "job": 0, "selection": strict_selection },
  ])
  guard field(field(source, "input"), "submission") is Object(fields) else {
    abort("submission")
  }
  fields.remove("admission")
  let result = field(@adapter.handle_line(source.stringify()).unwrap(), "value")
  assert_eq(field(result, "failure"), Json::null())
  assert_eq(
    field(field(field(item(result, "jobs", 0), "plan"), "admission"), "policy"),
    Json::string("strict"),
  )
  assert_eq(
    field(field(item(result, "jobs", 0), "receipt"), "state"),
    Json::string("terminal"),
  )
}
