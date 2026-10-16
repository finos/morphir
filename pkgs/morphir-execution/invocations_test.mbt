///|
fn invocation_validation_code(
  suite : @execution.Suite,
  entries : Array[@execution.PublicEntry],
  rejections~ : Array[(String, String)] = [],
) -> String {
  try {
    @execution.validate_invocations(suite, entries, [], rejections~)
    "ok"
  } catch {
    @execution.Invalid(code) => code
    error => error.to_string()
  }
}

///|
test "public manifest admits ordered repeated entries and ordinary Result Err" {
  let suite = @execution.Suite::from_json({
    "profile": "morphir-invocations-v1",
    "calls": [
      { "id": "zero", "entry": "zero", "arguments": [] },
      {
        "id": "first",
        "entry": "result",
        "arguments": [
          { "type": "result", "case": "err", "value": { "type": "unit" } },
        ],
      },
      {
        "id": "again",
        "entry": "result",
        "arguments": [
          {
            "type": "result",
            "case": "ok",
            "value": { "type": "int", "value": "007" },
          },
        ],
      },
    ],
  })
  let before = suite.to_json()
  let entries : Array[@execution.PublicEntry] = [
    { name: "zero", inputs: [], output: Unit, },
    { name: "result", inputs: [Outcome(Int, Unit)], output: Int, },
  ]
  assert_eq(invocation_validation_code(suite, entries), "ok")
  assert_eq(suite.to_json(), before)
}

///|
test "missing public entries and wrong arity retain stable diagnostics" {
  let suite : @execution.Suite = {
    calls: [{ id: "c", entry: "entry", arguments: [], }],
    extensions: None,
  }
  assert_eq(
    invocation_validation_code(suite, []),
    "execution.entry_not_public_or_supported: entry",
  )
  assert_eq(
    invocation_validation_code(suite, [
      { name: "entry", inputs: [Unit], output: Unit, },
    ]),
    "execution.wrong_arity: c",
  )
}

///|
test "trusted generator rejection hints do not change public membership" {
  let suite : @execution.Suite = {
    calls: [{ id: "c", entry: "entry", arguments: [], }],
    extensions: None,
  }
  let rejections = [("entry", "execution.constructor_visibility")]
  assert_eq(
    invocation_validation_code(suite, [], rejections~),
    "execution.constructor_visibility: entry",
  )
  assert_eq(
    invocation_validation_code(
      suite,
      [{ name: "entry", inputs: [], output: Unit, }],
      rejections~,
    ),
    "ok",
  )
}

///|
test "suite identities are validated before public entry lookup" {
  let suite : @execution.Suite = {
    calls: [
      { id: "same", entry: "entry", arguments: [], },
      { id: "same", entry: "entry", arguments: [], },
    ],
    extensions: None,
  }
  assert_eq(
    invocation_validation_code(suite, []),
    "execution.invalid_call_identity",
  )
}

///|
test "argument admission rejects SDK model errors and wrong declared values" {
  let entries : Array[@execution.PublicEntry] = [
    { name: "entry", inputs: [Int], output: Int, },
  ]
  for
    (value, code) in [
      (@execution.Boolean(false), "execution.wrong_type: value: expected int"),
      (
        @execution.ModelError("sdk.division_by_zero"),
        "execution.model_error_argument",
      ),
    ] {
    let suite : @execution.Suite = {
      calls: [{ id: "c", entry: "entry", arguments: [value], }],
      extensions: None,
    }
    assert_eq(invocation_validation_code(suite, entries), code)
  }
}

///|
test "first invalid argument is reported before a later missing entry" {
  let suite : @execution.Suite = {
    calls: [
      { id: "first", entry: "entry", arguments: [@execution.Unit], },
      { id: "later", entry: "missing", arguments: [], },
    ],
    extensions: None,
  }
  assert_eq(
    invocation_validation_code(suite, [
      { name: "entry", inputs: [Int], output: Int, },
    ]),
    "execution.wrong_type: value: expected int",
  )
}
