///|
fn frame_request(
  input : Json,
  version~ : String = "0.1.0-draft.7",
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
    "contractVersion": "0.1.0-draft.7",
  })
  assert_eq(
    job_field(caps, "operations"),
    Json::array([Json::string("validate-native-frame")]),
  )
  assert_eq(job_field(caps, "formats"), Json::array([Json::string("json")]))
  let source = "{\"profile\":\"morphir/workbench/native\",\"contractVersion\":\"0.1.0-draft.1\",\"operation\":\"session.open\"}"
  assert_eq(
    @mck.handle(frame_request({ "encoding": "utf8", "source": source })),
    ({ "id": 1, "status": "ok", "value": { "frameAccepted": true } } : Json),
  )
  assert_eq(
    job_field(
      @mck.handle(frame_request({ "encoding": "hex", "source": "c328" })),
      "code",
    ),
    Json::string("native.frame.utf8"),
  )
  assert_eq(
    job_field(
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
  for version in ["0.1.0-draft.6", "0.1.0-draft.8", "0.1.0-draft.7+local"] {
    assert_eq(
      job_field(
        @mck.handle(
          frame_request({ "encoding": "utf8", "source": source }, version~),
        ),
        "code",
      ),
      Json::string("workbench.invalid_request"),
    )
  }
  assert_eq(
    job_field(
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
