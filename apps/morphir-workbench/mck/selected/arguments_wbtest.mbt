///|
test "tagged argument budgets stay distinct from malformed JSON" {
  let mut nested : Json = { "type": "unit" }
  for _ in 0..<65 {
    nested = { "type": "list", "items": [nested] }
  }
  for
    (source, expected) in [
      (Json::array([nested]).stringify(), "execution.value_limit"),
      ("[", "execution.invalid_arguments"),
    ] {
    let code = try {
      let arguments = invocation_arguments({
        "inputs": { "format": "json", "source": source },
      })
      ignore(
        @protocol.Suite::from_json({
          "profile": "morphir-invocations-v1",
          "calls": [
            {
              "id": "selected",
              "entry": "selected:main#answer",
              "arguments": arguments,
            },
          ],
        }),
      )
      "accepted"
    } catch {
      error => error_code(error)
    }
    assert_eq(code, expected)
  }
}

///|
test "argument framing preserves the published value and container depth limits" {
  let mut list : Json = { "type": "unit" }
  let mut maybe : Json = { "type": "unit" }
  for _ in 0..<64 {
    list = { "type": "list", "items": [list] }
    maybe = { "type": "maybe", "case": "just", "value": maybe }
  }
  for
    (value, expected) in [(maybe, "accepted"), (list, "execution.value_limit")] {
    let arguments = invocation_arguments({
      "inputs": { "format": "json", "source": Json::array([value]).stringify() },
    })
    let code = try {
      ignore(
        @protocol.Suite::from_json({
          "profile": "morphir-invocations-v1",
          "calls": [
            {
              "id": "selected",
              "entry": "selected:main#answer",
              "arguments": arguments,
            },
          ],
        }),
      )
      "accepted"
    } catch {
      error => error_code(error)
    }
    assert_eq(code, expected)
  }
}
