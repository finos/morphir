///|
test "typed runtime failure emits a bounded terminal after argument admission" {
  let calls = Ref(0)
  let evaluator : @typed_engine.Evaluator = {
    profile: "failure-fixture",
    evaluate: fn(_, _, _, _) raise {
      calls.val += 1
      raise @protocol.Invalid("fixture.runtime: " + "😀".repeat(600))
    },
  }
  let request : Json = {
    "entry": "pricing:boundaries#decimal",
    "arguments": [{ "type": "decimal", "coefficient": "1", "exponent": 0 }],
  }
  let reply = evaluate_typed_with(@fixtures.pricing(), request, evaluator)
  assert_eq(@wire.field(reply, "success"), Json::boolean(false))
  assert_eq(@wire.optional(reply, "typed"), None)
  assert_eq(calls.val, 1)
  let evidence = @protocol.Outcomes::from_json(
    @wire.field(reply, "terminalOutcomes"),
  )
  guard evidence.calls[0].outcome is Failed(failure) else {
    fail("runtime failure")
  }
  assert_true(failure.stage == @protocol.Evaluate)
  assert_eq(failure.code, "execution.evaluate")
  assert_true(failure.message.length() <= 512)
  assert_true(evidence.cleanup == None)
  let wrong_arguments : Json = {
    "entry": "pricing:boundaries#decimal",
    "arguments": [{ "type": "unit" }],
  }
  assert_true(
    try {
      ignore(
        evaluate_typed_with(@fixtures.pricing(), wrong_arguments, evaluator),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_eq(calls.val, 1, msg="Invalid input never reaches the evaluator")
}
