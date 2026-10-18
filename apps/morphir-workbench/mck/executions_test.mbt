///|
fn execution_identity() -> Json {
  {
    "hostId": "host",
    "sessionId": "session",
    "providerId": "provider",
    "executionId": "execution",
    "snapshotId": "snapshot",
  }
}

///|
fn execution_offer() -> Json {
  {
    "profile": "morphir/workbench/executions",
    "contractVersion": "0.2.0-draft.1",
    "hostId": "host",
    "sessionId": "session",
    "providerId": "provider",
    "operations": ["query", "cancel"],
  }
}

///|
fn execution_receipt(
  sequence : Int32,
  state : String,
  acknowledged~ : Bool = false,
  outcomes~ : Json = Json::null(),
) -> Json {
  {
    "contractVersion": "0.2.0-draft.1",
    "identity": execution_identity(),
    "sequence": sequence,
    "state": state,
    "cancelRequested": acknowledged,
    "outcomes": outcomes,
  }
}

///|
fn execution_request(actions : Array[Json]) -> Json {
  {
    "id": 1,
    "op": "reduce-execution",
    "suite": "workbench",
    "contractVersion": "0.1.0-draft.14",
    "format": "json",
    "input": {
      "offer": execution_offer(),
      "identity": execution_identity(),
      "calls": ["call"],
      "initial": execution_receipt(0, "submitted"),
      "actions": actions,
    },
  }
}

///|
fn execution_field(value : Json, name : String) -> Json {
  match value {
    Object(fields) => fields[name]
    _ => abort("expected object")
  }
}

///|
fn execution_items(value : Json) -> Array[Json] {
  match value {
    Array(items) => items
    _ => abort("expected array")
  }
}

///|
test "execution draft negotiates only JSON reduction and preserves historical claims" {
  assert_eq(
    @mck.handle({
      "id": 1,
      "op": "capabilities",
      "suite": "workbench",
      "contractVersion": "0.1.0-draft.14",
    }),
    {
      "id": 1,
      "suite": "workbench",
      "contractVersion": "0.1.0-draft.14",
      "binding": "morphir-moonbit",
      "language": "moonbit",
      "operations": ["reduce-execution"],
      "formats": ["json"],
    },
  )
  for
    version in [
      "0.1.0-draft.1", "0.1.0-draft.2", "0.1.0-draft.3", "0.1.0-draft.4", "0.1.0-draft.5",
    ] {
    let request : Json = {
      "id": 1,
      "op": "reduce-execution",
      "suite": "workbench",
      "contractVersion": version,
      "format": "json",
      "input": {},
    }
    assert_eq(@mck.handle(request), {
      "id": 1,
      "status": "invalid",
      "code": "workbench.invalid_request",
    })
  }
}

///|
test "execution transcript retains state after rejected evidence and can continue" {
  let result = @mck.handle(
    execution_request([
      { "op": "observe", "receipt": execution_receipt(2, "running") },
      { "op": "observe", "receipt": execution_receipt(3, "submitted") },
      { "op": "observe", "receipt": execution_receipt(1, "submitted") },
      { "op": "observe", "receipt": execution_receipt(2, "running") },
      {
        "op": "observe",
        "receipt": execution_receipt(5, "running", acknowledged=true),
      },
      { "op": "cancel-action" },
    ]),
  )
  assert_eq(execution_field(result, "status"), Json::string("ok"))
  let value = execution_field(result, "value")
  let observations = execution_items(execution_field(value, "observations"))
  assert_eq(
    execution_field(observations[0], "status"),
    Json::string("advanced"),
  )
  assert_eq(
    execution_field(observations[1], "code"),
    Json::string("workbench.execution_transition"),
  )
  assert_eq(
    execution_field(observations[1], "view"),
    execution_field(observations[0], "view"),
  )
  assert_eq(execution_field(observations[2], "status"), Json::string("stale"))
  assert_eq(execution_field(observations[3], "status"), Json::string("replay"))
  assert_eq(
    execution_field(value, "receipt"),
    execution_receipt(5, "running", acknowledged=true),
  )
  assert_eq(execution_field(value, "cancelAction"), Json::string("pending"))
}

///|
test "offline observation cannot manufacture a host terminal" {
  let result = @mck.handle(
    execution_request([
      { "op": "disconnect" },
      { "op": "observe", "receipt": execution_receipt(1, "running") },
      { "op": "cancel-action" },
      { "op": "reconnect", "offer": execution_offer() },
      { "op": "observe", "receipt": execution_receipt(1, "running") },
    ]),
  )
  let value = execution_field(result, "value")
  let steps = execution_items(execution_field(value, "observations"))
  assert_eq(
    execution_field(steps[1], "code"),
    Json::string("workbench.execution_disconnected"),
  )
  assert_eq(
    execution_field(steps[2], "view"),
    execution_field(steps[0], "view"),
  )
  assert_eq(execution_field(value, "receipt"), execution_receipt(1, "running"))
  assert_eq(execution_field(value, "connected"), Json::boolean(true))
}

///|
test "returned data and cleanup survive an acknowledged cancellation race" {
  let outcomes : Json = {
    "contractVersion": "0.1.0-draft.5",
    "calls": [
      {
        "id": "call",
        "outcome": {
          "status": "returned",
          "value": { "type": "int", "value": "0009007199254740993" },
        },
      },
    ],
    "cleanup": {
      "stage": "cleanup",
      "code": "provider.dispose",
      "message": "cleanup",
    },
    "extensions": null,
  }
  let result = @mck.handle(
    execution_request([
      {
        "op": "observe",
        "receipt": execution_receipt(1, "running", acknowledged=true),
      },
      {
        "op": "observe",
        "receipt": execution_receipt(
          2,
          "terminal",
          acknowledged=true,
          outcomes~,
        ),
      },
      { "op": "disconnect" },
    ]),
  )
  let value = execution_field(result, "value")
  assert_eq(
    execution_field(value, "cancelAction"),
    Json::string("already-terminal"),
  )
  assert_eq(execution_field(value, "connected"), Json::boolean(false))
  let terminal = execution_field(execution_field(value, "receipt"), "outcomes")
  assert_eq(
    execution_field(terminal, "cleanup"),
    execution_field(outcomes, "cleanup"),
  )
  let call = execution_items(execution_field(terminal, "calls"))[0]
  assert_eq(
    execution_field(
      execution_field(execution_field(call, "outcome"), "value"),
      "value",
    ),
    Json::string("9007199254740993"),
  )
}

///|
test "execution action syntax is closed and bounded before any step runs" {
  assert_eq(
    @mck.handle(execution_request([{ "op": "cancel-action", "extra": true }])),
    {
      "id": 1,
      "status": "invalid",
      "code": "workbench.invalid_execution_trace",
    },
  )
  assert_eq(
    @mck.handle(execution_request(Array::make(65, { "op": "cancel-action" }))),
    { "id": 1, "status": "invalid", "code": "workbench.execution_limit" },
  )
  assert_eq(
    @mck.handle(execution_request([{ "op": "observe", "receipt": null }])),
    {
      "id": 1,
      "status": "ok",
      "value": {
        "identity": execution_identity(),
        "receipt": execution_receipt(0, "submitted"),
        "connected": true,
        "cancelAction": "send",
        "observations": [
          {
            "op": "observe",
            "status": "invalid",
            "code": "workbench.execution_receipt",
            "view": {
              "sequence": 0,
              "state": "submitted",
              "cancelRequested": false,
              "connected": true,
              "cancelAction": "send",
            },
          },
        ],
      },
    },
  )
}

///|
test "execution raw JSON duplicate members cannot disappear at the boundary" {
  let line = "{\"id\":1,\"op\":\"reduce-execution\",\"suite\":\"workbench\",\"contractVersion\":\"0.1.0-draft.14\",\"format\":\"json\",\"input\":{\"offer\":{},\"offer\":{}}}"
  assert_eq(
    @mck.handle_line(line),
    Some({ "id": 1, "status": "invalid", "code": "workbench.invalid_request" }),
  )
}

///|
test "execution input budget applies before malformed trace admission" {
  let request : Json = {
    "id": 1,
    "op": "reduce-execution",
    "suite": "workbench",
    "contractVersion": "0.1.0-draft.14",
    "format": "json",
    "input": { "padding": "x".repeat(1024 * 1024) },
  }
  assert_eq(@mck.handle(request), {
    "id": 1,
    "status": "invalid",
    "code": "workbench.input_limit",
  })
}

///|
test "invalid nested Ion metadata rejects only its action and retains cursor" {
  let outcomes : Json = {
    "contractVersion": "0.1.0-draft.5",
    "calls": [{ "id": "call", "outcome": { "status": "cancelled" } }],
    "cleanup": null,
    "extensions": { "format": "ion-binary", "bytes": [255] },
  }
  let result = @mck.handle(
    execution_request([
      {
        "op": "observe",
        "receipt": execution_receipt(1, "terminal", outcomes~),
      },
      { "op": "cancel-action" },
    ]),
  )
  assert_eq(execution_field(result, "status"), Json::string("ok"))
  let value = execution_field(result, "value")
  let steps = execution_items(execution_field(value, "observations"))
  assert_eq(
    execution_field(steps[0], "code"),
    Json::string("workbench.codec_failure"),
  )
  assert_eq(execution_field(steps[1], "status"), Json::string("local"))
  assert_eq(
    execution_field(steps[1], "view"),
    execution_field(steps[0], "view"),
  )
  assert_eq(
    execution_field(value, "receipt"),
    execution_receipt(0, "submitted"),
  )
}
