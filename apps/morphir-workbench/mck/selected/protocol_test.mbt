///|
test "selected Scheme adapter negotiates one exact offline witness" {
  let request =
    #|{"id":1,"op":"capabilities","suite":"workbench","contractVersion":"0.1.0-draft.11"}
  assert_eq(
    @selected.handle_line(request),
    Some({
      "id": @wire.number("1"),
      "suite": "workbench",
      "contractVersion": "0.1.0-draft.11",
      "binding": "morphir-moonbit-selected-scheme",
      "language": "moonbit",
      "operations": ["run-selected-scheme"],
      "formats": ["json"],
    }),
  )
}

///|
test "selected Scheme witness observes model decoding failure without running" {
  let request : Json = {
    "id": 2,
    "op": "run-selected-scheme",
    "suite": "workbench",
    "contractVersion": "0.1.0-draft.11",
    "format": "json",
    "input": {
      "model": "{",
      "entry": "selected:main#answer",
      "runtime": "scheme",
      "inputs": { "format": "json", "source": "[]" },
      "admission": {
        "profile": "morphir/workbench/admission",
        "contractVersion": "0.1.0-draft.1",
        "policy": "permissive",
      },
    },
  }
  assert_eq(
    @selected.handle_line(request.stringify()),
    Some({
      "id": @wire.number("2"),
      "status": "ok",
      "value": {
        "policy": "permissive",
        "runtime": "scheme",
        "boundary": null,
        "values": null,
        "failure": { "stage": "decode", "code": "invalid_json" },
      },
    }),
  )
}

///|
test "selected Scheme witness cannot negotiate adjacent versions or mappings" {
  for version in ["0.1.0-draft.18", "0.1.0-draft.11+build", "0.1.0-draft.12"] {
    let request : Json = {
      "id": 1,
      "op": "capabilities",
      "suite": "workbench",
      "contractVersion": version,
    }
    assert_eq(
      @selected.handle_line(request.stringify()),
      Some({
        "id": @wire.number("1"),
        "status": "invalid",
        "code": "workbench.invalid_request",
      }),
    )
  }
  for
    source in [
      "{\"id\":1,\"id\":2,\"op\":\"capabilities\",\"suite\":\"workbench\",\"contractVersion\":\"0.1.0-draft.11\"}",
      "{\"id\":1.0,\"op\":\"capabilities\",\"suite\":\"workbench\",\"contractVersion\":\"0.1.0-draft.11\"}",
      "{\"id\":0,\"op\":\"capabilities\",\"suite\":\"workbench\",\"contractVersion\":\"0.1.0-draft.11\"}",
    ] {
    let response = @selected.handle_line(source).unwrap()
    assert_eq(@wire.field(response, "status"), Json::string("invalid"))
  }
  assert_eq(@selected.handle_line("{\"id\":1,\"op\":\"exit\"}"), None)
  assert_eq(
    @wire.field(
      @selected.handle_line("{\"id\":1,\"op\":\"exit\",\"extra\":true}").unwrap(),
      "status",
    ),
    Json::string("invalid"),
  )
}
