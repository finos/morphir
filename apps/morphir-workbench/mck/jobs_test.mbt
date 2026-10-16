///|
fn job_identity() -> Json {
  {
    "hostId": "host",
    "sessionId": "session",
    "providerId": "provider",
    "jobId": "job",
    "snapshotId": "snapshot",
  }
}

///|
fn job_offer() -> Json {
  {
    "profile": "morphir/workbench/jobs",
    "contractVersion": "0.1.0-draft.1",
    "hostId": "host",
    "sessionId": "session",
    "providerId": "provider",
    "operations": ["query", "cancel"],
  }
}

///|
fn job_receipt(
  sequence : Int32,
  state : String,
  acknowledged~ : Bool = false,
  outcomes~ : Json = Json::null(),
) -> Json {
  {
    "contractVersion": "0.1.0-draft.1",
    "identity": job_identity(),
    "sequence": sequence,
    "state": state,
    "cancelRequested": acknowledged,
    "outcomes": outcomes,
  }
}

///|
fn job_request(actions : Array[Json]) -> Json {
  {
    "id": 1,
    "op": "reduce-job",
    "suite": "workbench",
    "contractVersion": "0.1.0-draft.6",
    "format": "json",
    "input": {
      "offer": job_offer(),
      "identity": job_identity(),
      "calls": ["call"],
      "initial": job_receipt(0, "submitted"),
      "actions": actions,
    },
  }
}

///|
fn job_field(value : Json, name : String) -> Json {
  match value {
    Object(fields) => fields[name]
    _ => abort("expected object")
  }
}

///|
fn job_items(value : Json) -> Array[Json] {
  match value {
    Array(items) => items
    _ => abort("expected array")
  }
}

///|
test "job draft negotiates only JSON reduction and preserves historical claims" {
  assert_eq(
    @mck.handle({
      "id": 1,
      "op": "capabilities",
      "suite": "workbench",
      "contractVersion": "0.1.0-draft.6",
    }),
    {
      "id": 1,
      "suite": "workbench",
      "contractVersion": "0.1.0-draft.6",
      "binding": "morphir-moonbit",
      "language": "moonbit",
      "operations": ["reduce-job"],
      "formats": ["json"],
    },
  )
  for
    version in [
      "0.1.0-draft.1", "0.1.0-draft.2", "0.1.0-draft.3", "0.1.0-draft.4", "0.1.0-draft.5",
    ] {
    let request : Json = {
      "id": 1,
      "op": "reduce-job",
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
test "job transcript retains state after rejected evidence and can continue" {
  let result = @mck.handle(
    job_request([
      { "op": "observe", "receipt": job_receipt(2, "running") },
      { "op": "observe", "receipt": job_receipt(3, "submitted") },
      { "op": "observe", "receipt": job_receipt(1, "submitted") },
      { "op": "observe", "receipt": job_receipt(2, "running") },
      {
        "op": "observe",
        "receipt": job_receipt(5, "running", acknowledged=true),
      },
      { "op": "cancel-action" },
    ]),
  )
  assert_eq(job_field(result, "status"), Json::string("ok"))
  let value = job_field(result, "value")
  let observations = job_items(job_field(value, "observations"))
  assert_eq(job_field(observations[0], "status"), Json::string("advanced"))
  assert_eq(
    job_field(observations[1], "code"),
    Json::string("workbench.job_transition"),
  )
  assert_eq(
    job_field(observations[1], "view"),
    job_field(observations[0], "view"),
  )
  assert_eq(job_field(observations[2], "status"), Json::string("stale"))
  assert_eq(job_field(observations[3], "status"), Json::string("replay"))
  assert_eq(
    job_field(value, "receipt"),
    job_receipt(5, "running", acknowledged=true),
  )
  assert_eq(job_field(value, "cancelAction"), Json::string("pending"))
}

///|
test "offline observation cannot manufacture a host terminal" {
  let result = @mck.handle(
    job_request([
      { "op": "disconnect" },
      { "op": "observe", "receipt": job_receipt(1, "running") },
      { "op": "cancel-action" },
      { "op": "reconnect", "offer": job_offer() },
      { "op": "observe", "receipt": job_receipt(1, "running") },
    ]),
  )
  let value = job_field(result, "value")
  let steps = job_items(job_field(value, "observations"))
  assert_eq(
    job_field(steps[1], "code"),
    Json::string("workbench.job_disconnected"),
  )
  assert_eq(job_field(steps[2], "view"), job_field(steps[0], "view"))
  assert_eq(job_field(value, "receipt"), job_receipt(1, "running"))
  assert_eq(job_field(value, "connected"), Json::boolean(true))
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
    job_request([
      {
        "op": "observe",
        "receipt": job_receipt(1, "running", acknowledged=true),
      },
      {
        "op": "observe",
        "receipt": job_receipt(2, "terminal", acknowledged=true, outcomes~),
      },
      { "op": "disconnect" },
    ]),
  )
  let value = job_field(result, "value")
  assert_eq(job_field(value, "cancelAction"), Json::string("already-terminal"))
  assert_eq(job_field(value, "connected"), Json::boolean(false))
  let terminal = job_field(job_field(value, "receipt"), "outcomes")
  assert_eq(job_field(terminal, "cleanup"), job_field(outcomes, "cleanup"))
  let call = job_items(job_field(terminal, "calls"))[0]
  assert_eq(
    job_field(job_field(job_field(call, "outcome"), "value"), "value"),
    Json::string("9007199254740993"),
  )
}

///|
test "job action syntax is closed and bounded before any step runs" {
  assert_eq(
    @mck.handle(job_request([{ "op": "cancel-action", "extra": true }])),
    { "id": 1, "status": "invalid", "code": "workbench.invalid_job_trace" },
  )
  assert_eq(
    @mck.handle(job_request(Array::make(65, { "op": "cancel-action" }))),
    { "id": 1, "status": "invalid", "code": "workbench.job_limit" },
  )
  assert_eq(@mck.handle(job_request([{ "op": "observe", "receipt": null }])), {
    "id": 1,
    "status": "ok",
    "value": {
      "identity": job_identity(),
      "receipt": job_receipt(0, "submitted"),
      "connected": true,
      "cancelAction": "send",
      "observations": [
        {
          "op": "observe",
          "status": "invalid",
          "code": "workbench.job_receipt",
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
  })
}

///|
test "job raw JSON duplicate members cannot disappear at the boundary" {
  let line = "{\"id\":1,\"op\":\"reduce-job\",\"suite\":\"workbench\",\"contractVersion\":\"0.1.0-draft.6\",\"format\":\"json\",\"input\":{\"offer\":{},\"offer\":{}}}"
  assert_eq(
    @mck.handle_line(line),
    Some({ "id": 1, "status": "invalid", "code": "workbench.invalid_request" }),
  )
}

///|
test "job input budget applies before malformed trace admission" {
  let request : Json = {
    "id": 1,
    "op": "reduce-job",
    "suite": "workbench",
    "contractVersion": "0.1.0-draft.6",
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
    job_request([
      { "op": "observe", "receipt": job_receipt(1, "terminal", outcomes~) },
      { "op": "cancel-action" },
    ]),
  )
  assert_eq(job_field(result, "status"), Json::string("ok"))
  let value = job_field(result, "value")
  let steps = job_items(job_field(value, "observations"))
  assert_eq(
    job_field(steps[0], "code"),
    Json::string("workbench.codec_failure"),
  )
  assert_eq(job_field(steps[1], "status"), Json::string("local"))
  assert_eq(job_field(steps[1], "view"), job_field(steps[0], "view"))
  assert_eq(job_field(value, "receipt"), job_receipt(0, "submitted"))
}
