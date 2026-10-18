///|
test "capabilities claim only exact draft value decoding" {
  let response = @mck.handle({
    "id": 1,
    "op": "capabilities",
    "suite": "workbench",
    "contractVersion": "0.1.0-draft.1",
  })
  assert_eq(response, {
    "id": 1,
    "suite": "workbench",
    "contractVersion": "0.1.0-draft.1",
    "binding": "morphir-moonbit",
    "language": "moonbit",
    "operations": ["decode-value"],
    "formats": ["json", "ion-text"],
  })
}

///|
test "transport exit produces no observation and requires a closed envelope" {
  assert_true(@mck.exit_requested({ "id": 66, "op": "exit" }))
  assert_false(
    @mck.exit_requested({ "id": 66, "op": "exit", "suite": "workbench" }),
  )
  assert_false(@mck.exit_requested({ "id": -1, "op": "exit" }))
}

///|
test "raw requests reject duplicate JSON members at every depth" {
  for
    source in [
      "{\"id\":1,\"op\":\"capabilities\",\"suite\":\"workbench\",\"contractVersion\":\"0.1.0-draft.1\",\"contractVersion\":\"0.1.0-draft.1\"}",
      "{\"id\":1,\"op\":\"decode-value\",\"suite\":\"workbench\",\"contractVersion\":\"0.1.0-draft.1\",\"format\":\"json\",\"input\":{\"type\":\"unit\",\"type\":\"unit\"}}",
    ] {
    assert_eq(
      @mck.handle_line(source),
      Some({ "id": 1, "status": "invalid", "code": "workbench.invalid_request" }),
    )
  }
}

///|
test "rejection codes omit unbounded input identity details" {
  let name = "field".repeat(100)
  let fields : Map[String, Json] = { "type": Json::string("unit") }
  fields[name] = Json::boolean(true)
  let input = Json::object(fields)
  assert_eq(
    @mck.handle({
      "id": 7,
      "op": "decode-value",
      "suite": "workbench",
      "contractVersion": "0.1.0-draft.1",
      "format": "json",
      "input": input,
    }),
    { "id": 7, "status": "invalid", "code": "execution.invalid_field" },
  )
}

///|
test "adapter decodes exact input without a golden" {
  for
    (format, input) in [
      ("json", Json::object({ "type": "int", "value": "0009007199254740993" })),
      ("ion-text", Json::string("9007199254740993")),
    ] {
    assert_eq(
      @mck.handle({
        "id": 2,
        "op": "decode-value",
        "suite": "workbench",
        "contractVersion": "0.1.0-draft.1",
        "format": format,
        "input": input,
      }),
      {
        "id": 2,
        "status": "ok",
        "value": { "type": "int", "value": "9007199254740993" },
      },
    )
  }
}

///|
test "adapter rejects unsupported drafts and leaked expected values" {
  let requests : Array[Json] = [
    {
      "id": 3,
      "op": "capabilities",
      "suite": "workbench",
      "contractVersion": "0.1.0-draft.17",
    },
    {
      "id": 3,
      "op": "decode-value",
      "suite": "workbench",
      "contractVersion": "0.1.0-draft.1",
      "format": "json",
      "input": { "type": "unit" },
      "expected": { "status": "ok" },
    },
  ]
  for request in requests {
    assert_eq(@mck.handle(request), {
      "id": 3,
      "status": "invalid",
      "code": "workbench.invalid_request",
    })
  }
}

///|
test "replacement adapter rejects retired job trace and native MCK drafts" {
  for version in ["0.1.0-draft.6", "0.1.0-draft.7", "0.1.0-draft.8"] {
    assert_eq(
      @mck.handle({
        "id": 1,
        "op": "capabilities",
        "suite": "workbench",
        "contractVersion": version,
      }),
      { "id": 1, "status": "invalid", "code": "workbench.invalid_request" },
    )
  }
  assert_eq(
    @mck.handle({
      "id": 1,
      "op": "reduce-job",
      "suite": "workbench",
      "contractVersion": "0.1.0-draft.14",
      "format": "json",
      "input": {},
    }),
    { "id": 1, "status": "invalid", "code": "workbench.invalid_request" },
  )
}

///|
test "adapter keeps SDK model errors distinct from malformed Ion" {
  assert_eq(
    @mck.handle({
      "id": 4,
      "op": "decode-value",
      "suite": "workbench",
      "contractVersion": "0.1.0-draft.1",
      "format": "ion-text",
      "input": "[",
    }),
    { "id": 4, "status": "invalid", "code": "workbench.invalid_ion" },
  )
  assert_eq(
    @mck.handle({
      "id": 5,
      "op": "decode-value",
      "suite": "workbench",
      "contractVersion": "0.1.0-draft.1",
      "format": "json",
      "input": { "type": "decimal", "coefficient": "1", "exponent": -33 },
    }),
    { "id": 5, "status": "invalid", "code": "execution.decimal_precision" },
  )
}
