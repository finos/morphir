///|
test "HTTP policy boundary negotiates independently of frozen native contracts" {
  let reply = @mck.handle({
    "id": 1,
    "op": "capabilities",
    "suite": "workbench",
    "contractVersion": "0.1.0-draft.23",
  })
  assert_eq(
    execution_field(reply, "operations"),
    (["validate-http-policy-boundary"] : Json),
  )
  for version in ["0.1.0-draft.23+build", "0.1.0-draft.999"] {
    assert_eq(
      execution_field(
        @mck.handle({
          "id": 1,
          "op": "capabilities",
          "suite": "workbench",
          "contractVersion": Json::string(version),
        }),
        "status",
      ),
      Json::string("invalid"),
    )
  }
}
