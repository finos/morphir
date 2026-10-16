///|
fn reply(calls : Array[Json], cleanup~ : Json = Json::null()) -> Json {
  {
    "success": true,
    "typed": { "type": "bool", "value": true },
    "terminalOutcomes": {
      "contractVersion": "0.1.0-draft.5",
      "calls": calls,
      "cleanup": cleanup,
      "extensions": Json::null(),
    },
  }
}

///|
test "returned Result Err and exact value survive cleanup failure" {
  let value : Json = {
    "type": "result",
    "case": "err",
    "value": { "type": "int", "value": "9007199254740993" },
  }
  let (prepared, projection) = @outcomes.prepare(
    reply(
      [
        {
          "id": "workbench",
          "outcome": { "status": "returned", "value": value },
        },
      ],
      cleanup={
        "stage": "cleanup",
        "code": "provider.dispose",
        "message": "Dispose failed",
      },
    ),
    expected_ids=Some(["workbench"]),
  )
  guard projection is Valid(summary) else { fail("valid terminal evidence") }
  assert_true(summary.calls[0].kind == @outcomes.Returned)
  assert_true(summary.has_value())
  assert_true(summary.level() == @outcomes.Error)
  assert_eq(summary.heading(), "Returned · Cleanup failed")
  assert_true(summary.calls[0].preview.contains("9007199254740993"))
  guard prepared is Object(fields) else { fail("prepared object") }
  assert_eq(fields["typed"], value)
  assert_eq(fields["success"], Json::boolean(false))
}

///|
test "terminal projection preserves model error primary failure and cancellation" {
  let (prepared, projection) = @outcomes.prepare(
    reply([
      {
        "id": "a",
        "outcome": { "status": "model-error", "code": "sdk.division_by_zero" },
      },
      {
        "id": "b",
        "outcome": {
          "status": "failed",
          "failure": {
            "stage": "invoke",
            "code": "provider.crash",
            "message": "Invoke failed",
          },
        },
      },
      { "id": "c", "outcome": { "status": "cancelled" } },
    ]),
  )
  guard projection is Valid(summary) else { fail("valid inventory") }
  assert_eq(summary.calls.map(c => c.id), ["a", "b", "c"])
  assert_eq(summary.calls[1].code, "provider.crash")
  assert_eq(summary.calls[1].stage, "invoke")
  assert_true(summary.calls[2].kind == @outcomes.Cancelled)
  assert_true(!summary.has_value())
  guard prepared is Object(fields) else { fail("prepared object") }
  assert_true(!fields.contains("typed"))
  assert_eq(fields["success"], Json::boolean(false))
}

///|
test "malformed or mismatched evidence never falls back to success" {
  let inputs : Array[Json] = [
    { "success": true, "terminalOutcomes": Json::null() },
    reply([{ "id": "other", "outcome": { "status": "cancelled" } }]),
    reply([
      {
        "id": "workbench",
        "outcome": { "status": "cancelled", "value": { "type": "unit" } },
      },
    ]),
  ]
  for input in inputs {
    let (prepared, projection) = @outcomes.prepare(
      input,
      expected_ids=Some(["workbench"]),
    )
    assert_true(projection is Invalid(_))
    guard prepared is Object(fields) else { fail("rejection object") }
    assert_eq(fields["success"], Json::boolean(false))
    assert_true(!fields.contains("typed"))
  }
  let legacy : Json = { "success": true, "value": "42" }
  let (prepared, projection) = @outcomes.prepare(legacy)
  assert_eq(prepared, legacy)
  assert_true(projection == @outcomes.Absent)
}

///|
test "presentation bounds calls previews and UTF16 without losing canonical data" {
  let value : Json = { "type": "text", "units": Array::make(2000, 65) }
  let (_prepared, projection) = @outcomes.prepare(
    reply(
      Array::makei(51, i => {
        "id": i.to_string(),
        "outcome": { "status": "returned", "value": value },
      }),
    ),
  )
  guard projection is Valid(summary) else { fail("bounded presentation") }
  assert_eq(summary.calls.length(), 50)
  assert_eq(summary.omitted, 1)
  assert_true(summary.calls.all(c => c.preview.length() <= 4000))
  assert_eq(@outcomes.bounded("😀".repeat(20), 16), "😀… (truncated)")
}
