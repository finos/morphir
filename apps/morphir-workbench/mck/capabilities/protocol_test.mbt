///|
test "capability policy adapter negotiates one exact offline witness" {
  let request =
    #|{"id":1,"op":"capabilities","suite":"workbench","contractVersion":"0.1.0-draft.12"}
  assert_eq(
    @capabilities.handle_line(request),
    Some({
      "id": @wire.number("1"),
      "suite": "workbench",
      "contractVersion": "0.1.0-draft.12",
      "binding": "morphir-moonbit-capability-policy",
      "language": "moonbit",
      "operations": ["run-capability-policy"],
      "formats": ["json"],
    }),
  )
}

///|
test "capability policy witness observes model decoding failure without running" {
  let request : Json = {
    "id": 2,
    "op": "run-capability-policy",
    "suite": "workbench",
    "contractVersion": "0.1.0-draft.12",
    "format": "json",
    "input": {
      "model": "{",
      "calls": [
        {
          "id": "selected",
          "entry": "selected:main#answer",
          "inputs": { "format": "json", "source": "[]" },
        },
      ],
      "runtime": "scheme",
      "extensions": null,
      "admission": {
        "profile": "morphir/workbench/admission",
        "contractVersion": "0.1.0-draft.1",
        "policy": "permissive",
      },
    },
  }
  assert_eq(
    @capabilities.handle_line(request.stringify()),
    Some({
      "id": @wire.number("2"),
      "status": "ok",
      "value": {
        "mode": "execute",
        "policy": "permissive",
        "runtime": "scheme",
        "boundary": null,
        "outcomes": null,
        "failure": { "stage": "decode", "code": "invalid_json" },
      },
    }),
  )
}

///|
test "capability policy witness cannot negotiate adjacent versions or mappings" {
  for version in ["0.1.0-draft.11", "0.1.0-draft.12+build", "0.1.0-draft.13"] {
    let request : Json = {
      "id": 1,
      "op": "capabilities",
      "suite": "workbench",
      "contractVersion": version,
    }
    assert_eq(
      @capabilities.handle_line(request.stringify()),
      Some({
        "id": @wire.number("1"),
        "status": "invalid",
        "code": "workbench.invalid_request",
      }),
    )
  }
  for
    source in [
      "{\"id\":1,\"id\":2,\"op\":\"capabilities\",\"suite\":\"workbench\",\"contractVersion\":\"0.1.0-draft.12\"}",
      "{\"id\":1.0,\"op\":\"capabilities\",\"suite\":\"workbench\",\"contractVersion\":\"0.1.0-draft.12\"}",
      "{\"id\":0,\"op\":\"capabilities\",\"suite\":\"workbench\",\"contractVersion\":\"0.1.0-draft.12\"}",
    ] {
    let response = @capabilities.handle_line(source).unwrap()
    assert_eq(@wire.field(response, "status"), Json::string("invalid"))
  }
  assert_eq(@capabilities.handle_line("{\"id\":1,\"op\":\"exit\"}"), None)
  assert_eq(
    @wire.field(
      @capabilities.handle_line("{\"id\":1,\"op\":\"exit\",\"extra\":true}").unwrap(),
      "status",
    ),
    Json::string("invalid"),
  )
}
