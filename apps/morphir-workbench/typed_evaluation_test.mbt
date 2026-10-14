///|
fn typed_request(
  file : @ir.IRFile,
  entry : String,
  arguments : Array[Json],
) -> Json raise {
  @pipeline.execute({
    "operation": "evaluate",
    "executionMode": "typed",
    "source": @codec.to_json(file).stringify(),
    "entry": entry,
    "arguments": arguments,
  })
}

///|
test "typed manifest exposes public boundaries while local mode remains inspectable" {
  let model = @fixtures.pricing()
  let inspected = @pipeline.execute({
    "operation": "inspect",
    "source": @codec.to_json(model).stringify(),
  })
  assert_eq(@wire.field(inspected, "success"), Json::boolean(true))
  let entries = @wire.field(
    @wire.field(inspected, "typedEvaluations"),
    "entries",
  )
  let total = @wire.field(entries, "pricing:quotes#total")
  assert_eq(@wire.field(total, "supported"), Json::boolean(true))
  assert_eq(@wire.field(total, "output"), { "type": "decimal" })
  assert_true(@wire.array(@wire.field(total, "definitions")).length() > 0)
  assert_eq(@wire.optional(entries, "pricing:quotes#captured"), None)
  let private_call = typed_request(
    @fixtures.invocation_library(),
    "calls:main#private",
    [],
  )
  assert_eq(@wire.field(private_call, "success"), Json::boolean(false))
  let dynamic = @pipeline.execute({
    "operation": "compile",
    "source": "(+ 20 22)",
  })
  assert_eq(@wire.field(dynamic, "success"), Json::boolean(true))
}

///|
test "typed boundaries round trip exact scalar and composite values" {
  let file = @fixtures.pricing()
  for
    (name, value) in [
      (
        "decimal",
        (
          {
            "type": "decimal",
            "coefficient": "9007199254740993",
            "exponent": -2,
          } : Json),
      ),
      ("float", ({ "type": "float64", "bits": "9223372036854775808" } : Json)),
      ("text", ({ "type": "text", "units": [0, 55357, 56832, 55296] } : Json)),
      ("character", ({ "type": "character", "units": [55296] } : Json)),
      (
        "list",
        (
          {
            "type": "list",
            "items": [{ "type": "int", "value": "9007199254740993" }],
          } : Json),
      ),
      (
        "tuple",
        (
          {
            "type": "tuple",
            "items": [
              { "type": "decimal", "coefficient": "1", "exponent": -1 },
              { "type": "int", "value": "2" },
            ],
          } : Json),
      ),
      (
        "maybe",
        (
          {
            "type": "maybe",
            "case": "just",
            "value": { "type": "int", "value": "9007199254740993" },
          } : Json),
      ),
      (
        "result",
        (
          {
            "type": "result",
            "case": "err",
            "value": { "type": "text", "units": [101] },
          } : Json),
      ),
    ] {
    let result = typed_request(file, "pricing:boundaries#" + name, [value])
    assert_eq(
      @wire.field(result, "success"),
      Json::boolean(true),
      msg=result.stringify(),
    )
    assert_eq(@wire.field(result, "typed"), value)
    assert_eq(@wire.field(result, "outcome"), Json::string("value"))
  }
  let total = typed_request(file, "pricing:results#total", [])
  assert_eq(@wire.field(total, "typed"), {
    "type": "decimal",
    "coefficient": "375",
    "exponent": -1,
  })
  let approved = typed_request(file, "pricing:quotes#approved", [])
  let custom = @wire.field(approved, "typed")
  assert_eq(@wire.field(custom, "owner"), Json::string("pricing:quotes#status"))
  let amount = typed_request(file, "pricing:quotes#status-amount", [custom])
  assert_eq(@wire.field(amount, "typed"), {
    "type": "decimal",
    "coefficient": "375",
    "exponent": -1,
  })
}

///|
test "typed validation rejects invalid inputs and separates domain errors from result err" {
  let file = @fixtures.pricing()
  for
    (entry, arguments) in [
      ("pricing:boundaries#decimal", [({ "type": "int", "value": "1" } : Json)]),
      (
        "pricing:boundaries#character",
        [({ "type": "character", "units": [65536] } : Json)],
      ),
      (
        "pricing:quotes#status-amount",
        [
          (
            {
              "type": "custom",
              "owner": "other:quotes#status",
              "tag": "pricing:quotes#approved",
              "items": [],
            } : Json),
        ],
      ),
      ("pricing:quotes#difference", []),
    ] {
    let result = typed_request(file, entry, arguments)
    assert_eq(
      @wire.field(result, "success"),
      Json::boolean(false),
      msg=entry + " " + result.stringify(),
    )
    assert_true(
      @wire.string(@wire.field(result, "message")).contains("execution."),
    )
  }
  let failure = typed_request(file, "pricing:results#failure", [])
  assert_eq(@wire.field(failure, "success"), Json::boolean(true))
  assert_eq(@wire.field(failure, "outcome"), Json::string("model-error"))
  assert_eq(
    @wire.field(@wire.field(failure, "typed"), "type"),
    Json::string("model-error"),
  )
}

///|
test "typed evaluation emits complete admitted terminal evidence" {
  let file = @fixtures.pricing()
  let returned = typed_request(file, "pricing:boundaries#result", [
    {
      "type": "result",
      "case": "err",
      "value": { "type": "text", "units": [69] },
    },
  ])
  assert_eq(@wire.field(returned, "terminalOutcomes"), {
    "contractVersion": "0.1.0-draft.5",
    "calls": [
      {
        "id": "workbench",
        "outcome": {
          "status": "returned",
          "value": {
            "type": "result",
            "case": "err",
            "value": { "type": "text", "units": [69] },
          },
        },
      },
    ],
    "cleanup": Json::null(),
    "extensions": Json::null(),
  })
  let model_error = typed_request(file, "pricing:results#failure", [])
  let terminal = @wire.field(model_error, "terminalOutcomes")
  assert_eq(@wire.field(terminal, "calls"), [
    {
      "id": "workbench",
      "outcome": { "status": "model-error", "code": "sdk.division_by_zero" },
    },
  ])
  let invalid = typed_request(file, "pricing:boundaries#result", [
    { "type": "bool", "value": false },
  ])
  assert_eq(@wire.field(invalid, "success"), Json::boolean(false))
  assert_eq(@wire.optional(invalid, "terminalOutcomes"), None)
}

///|
test "Ion values evaluate real typed and local functions" {
  let file = @fixtures.pricing()
  let result = @pipeline.execute({
    "operation": "evaluate",
    "executionMode": "typed",
    "source": @codec.to_json(file).stringify(),
    "entry": "pricing:boundaries#decimal",
    "argumentsIon": "[12.50]",
  })
  assert_eq(@wire.field(result, "typed"), {
    "type": "decimal",
    "coefficient": "125",
    "exponent": -1,
  })
  let record = @pipeline.execute({
    "operation": "evaluate",
    "executionMode": "typed",
    "source": @codec.to_json(file).stringify(),
    "entry": "pricing:quotes#total",
    "argumentsIon": "[morphir_value::{type:\"record\",fields:[{name:\"price\",value:{type:\"decimal\",coefficient:\"125\",exponent:-1}},{name:\"quantity\",value:{type:\"int\",value:\"3\"}}]}]",
  })
  assert_eq(@wire.field(record, "typed"), {
    "type": "decimal",
    "coefficient": "375",
    "exponent": -1,
  })
  let local_result = @pipeline.execute({
    "operation": "evaluate",
    "executionMode": "local",
    "source": @codec.to_json(file).stringify(),
    "entry": "pricing:quotes#difference",
    "argumentsIon": "[9007199254740993, 1]",
  })
  assert_eq(
    @wire.field(local_result, "value"),
    Json::string("9007199254740992"),
  )
  let invalid = @pipeline.execute({
    "operation": "evaluate",
    "executionMode": "typed",
    "source": @codec.to_json(file).stringify(),
    "entry": "pricing:boundaries#decimal",
    "argumentsIon": "[",
  })
  assert_eq(@wire.field(invalid, "success"), Json::boolean(false))
  assert_true(@wire.string(@wire.field(invalid, "message")).contains("Ion:"))
}
