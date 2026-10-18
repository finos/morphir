///|
test "policy boundary negotiation selects only the new exact mapping" {
  let capabilities = @mck.handle({
    "id": 1,
    "op": "capabilities",
    "suite": "workbench",
    "contractVersion": "0.1.0-draft.20",
  })
  assert_eq(
    execution_field(capabilities, "operations"),
    (["validate-native-policy-boundary"] : Json),
  )
  let source = (
    {
      "profile": "morphir/workbench/native",
      "contractVersion": "0.2.0-draft.2",
      "operation": "session.open",
    } : Json).stringify()
  let result = @mck.handle({
    "id": 1,
    "op": "validate-native-policy-boundary",
    "suite": "workbench",
    "contractVersion": "0.1.0-draft.20",
    "format": "json",
    "input": { "kind": "request", "encoding": "utf8", "source": source },
  })
  assert_eq(
    result,
    ({ "id": 1, "status": "ok", "value": { "frameAccepted": true } } : Json),
  )
  let frozen = @mck.handle(
    frame_request({ "encoding": "utf8", "source": source }),
  )
  assert_eq(execution_field(frozen, "code"), Json::string("native.frame.shape"))
}
