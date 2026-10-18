///|
fn frame_request(
  input : Json,
  version~ : String = "0.1.0-draft.15",
  format~ : String = "json",
) -> Json {
  {
    "id": 1,
    "op": "validate-native-frame",
    "suite": "workbench",
    "contractVersion": version,
    "format": format,
    "input": input,
  }
}

///|
test "native frame MCK negotiates an exclusive JSON operation" {
  let caps = @mck.handle({
    "id": 1,
    "op": "capabilities",
    "suite": "workbench",
    "contractVersion": "0.1.0-draft.15",
  })
  assert_eq(
    execution_field(caps, "operations"),
    Json::array([Json::string("validate-native-frame")]),
  )
  assert_eq(
    execution_field(caps, "formats"),
    Json::array([Json::string("json")]),
  )
  let source = "{\"profile\":\"morphir/workbench/native\",\"contractVersion\":\"0.2.0-draft.1\",\"operation\":\"session.open\"}"
  assert_eq(
    @mck.handle(frame_request({ "encoding": "utf8", "source": source })),
    ({ "id": 1, "status": "ok", "value": { "frameAccepted": true } } : Json),
  )
  assert_eq(
    execution_field(
      @mck.handle(frame_request({ "encoding": "hex", "source": "c328" })),
      "code",
    ),
    Json::string("native.frame.utf8"),
  )
  assert_eq(
    execution_field(
      @mck.handle(
        frame_request({
          "encoding": "utf8",
          "source": source,
          "generate": { "prefix": { "repeat": " ", "count": 1048576 } },
        }),
      ),
      "code",
    ),
    Json::string("native.frame.limit"),
  )
  for version in ["0.1.0-draft.14", "0.1.0-draft.16", "0.1.0-draft.15+local"] {
    assert_eq(
      execution_field(
        @mck.handle(
          frame_request({ "encoding": "utf8", "source": source }, version~),
        ),
        "code",
      ),
      Json::string("workbench.invalid_request"),
    )
  }
  assert_eq(
    execution_field(
      @mck.handle(
        frame_request(
          { "encoding": "utf8", "source": source },
          format="ion-text",
        ),
      ),
      "code",
    ),
    Json::string("workbench.invalid_request"),
  )
}
