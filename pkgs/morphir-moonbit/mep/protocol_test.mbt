///|
fn call(
  session : @mep.Session,
  operation : String,
  params~ : Json = {},
) -> Json {
  session
  .handle({ "jsonrpc": "2.0", "id": 1, "method": operation, "params": params })
  .unwrap()
}

///|
fn initialize(session : @mep.Session) -> Unit raise {
  let response = call(session, "morphir.initialize", params={
    "protocolVersions": ["0.1"],
    "host": { "name": "test", "version": "1" },
  })
  assert_eq(
    @wire.field(@wire.field(response, "result"), "protocolVersion"),
    Json::string("0.1"),
  )
}

///|
test "describe is available before initialization and claims only the implemented backend" {
  let session = @mep.Session::new()
  let result = @wire.field(
    call(session, "morphir.extension.describe", params={
      "protocolVersions": ["0.1"],
    }),
    "result",
  )
  assert_eq(@wire.field(result, "claimsVersion"), Json::string("0.1.0-draft.2"))
  let capabilities = @wire.field(result, "capabilities")
  assert_eq(
    @wire.field(@wire.field(capabilities, "backend"), "targets"),
    Json::array([Json::string("moonbit")]),
  )
  assert_true(!capabilities.stringify().contains("frontend"))
  assert_true(
    call(session, "morphir.extension.capabilities")
    .stringify()
    .contains("-32014"),
  )
  initialize(session)
}

///|
test "failed negotiation does not advance state and shutdown refuses further work" {
  let session = @mep.Session::new()
  assert_true(
    call(session, "morphir.initialize", params={
      "protocolVersions": ["99"],
      "host": { "name": "t", "version": "1" },
    })
    .stringify()
    .contains("-32011"),
  )
  assert_true(
    call(session, "morphir.initialize", params={ "protocolVersions": ["0.1"] })
    .stringify()
    .contains("-32602"),
  )
  initialize(session)
  assert_true(
    call(session, "morphir.initialize").stringify().contains("-32600"),
  )
  assert_eq(
    session.handle({ "jsonrpc": "2.0", "method": "morphir.initialized" }),
    None,
  )
  ignore(call(session, "morphir.shutdown"))
  assert_true(
    call(session, "morphir.extension.info").stringify().contains("-32014"),
  )
  assert_eq(
    session.handle({ "jsonrpc": "2.0", "method": "morphir.exit" }),
    None,
  )
  assert_true(session.exited())
}

///|
test "invalid RPC requests return errors and notifications never receive responses" {
  let session = @mep.Session::new()
  assert_true(
    session
    .handle({ "jsonrpc": "1.0", "id": 2, "method": "morphir.ping" })
    .unwrap()
    .stringify()
    .contains("-32600"),
  )
  assert_true(session.handle([1, 2]).unwrap().stringify().contains("-32600"))
  assert_true(
    session
    .handle({ "jsonrpc": "2.0", "id": -1, "method": "morphir.ping" })
    .unwrap()
    .stringify()
    .contains("-32600"),
  )
  assert_eq(session.handle({ "jsonrpc": "2.0", "method": "unknown" }), None)
  initialize(session)
  assert_true(call(session, "unknown").stringify().contains("-32601"))
  assert_true(call(session, "morphir.exit").stringify().contains("-32600"))
  assert_true(!session.exited())
}

///|
test "external JSON decoding rejects duplicates deep inputs and invalid UTF-8 while retaining integer IDs" {
  let session = @mep.Session::new()
  for
    input in [
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"morphir.ping\",\"method\":\"morphir.exit\"}",
      "[".repeat(258) + "0" + "]".repeat(258),
      "{invalid}",
    ] {
    assert_true(
      session
      .receive(@utf8.encode(input))
      .unwrap()
      .stringify()
      .contains("-32700"),
    )
  }
  assert_true(session.receive(b"\xff").unwrap().stringify().contains("-32700"))
  let response = session
    .receive(
      b"{\"jsonrpc\":\"2.0\",\"id\":18446744073709551615,\"method\":\"morphir.ping\"}",
    )
    .unwrap()
  assert_eq(
    @wire.number_text(@wire.field(response, "id")),
    "18446744073709551615",
  )
  assert_true(
    session
    .receive(
      b"{\"jsonrpc\":\"2.0\",\"id\":18446744073709551616,\"method\":\"morphir.ping\"}",
    )
    .unwrap()
    .stringify()
    .contains("-32600"),
  )
  initialize(session)
}

///|
test "backend returns the same artifacts as the pure generator without filesystem IO" {
  let session = @mep.Session::new()
  initialize(session)
  let ir = @fixtures.library()
  let direct = @generator.generate(@generator.Input::new("mep", ir))
  let result = @wire.field(
    call(session, "morphir.backend.generate", params={
      "target": "moonbit",
      "ir": @ir_json.to_json(ir),
    }),
    "result",
  )
  assert_true(
    @wire.field(result, "success") == Json::boolean(true),
    msg=result.stringify(),
  )
  let artifacts = @wire.array(@wire.field(result, "artifacts"))
  assert_eq(artifacts.length(), direct.artifacts.length())
  for i, artifact in artifacts {
    assert_eq(
      @wire.field(artifact, "path"),
      Json::string(direct.artifacts[i].path),
    )
    match direct.artifacts[i].content {
      Text(text) => {
        assert_eq(@wire.field(artifact, "content"), Json::string(text))
        assert_eq(@wire.field(artifact, "binary"), Json::boolean(false))
      }
      Binary(bytes) => {
        assert_eq(
          @base64.decode(@wire.string(@wire.field(artifact, "content"))),
          bytes,
        )
        assert_eq(@wire.field(artifact, "binary"), Json::boolean(true))
      }
    }
  }
}

///|
test "backend refuses unsupported targets options and lossy or malformed IR" {
  let session = @mep.Session::new()
  initialize(session)
  let ir = @ir_json.to_json(@fixtures.library())
  for
    params in [
      ({ "target": "rust", "ir": ir } : Json),
      ({ "target": "moonbit", "ir": ir, "options": { "ignored": true } } : Json),
      ({ "target": "moonbit", "ir": ir, "options": [] } : Json),
      ({ "ir": ir } : Json),
    ] {
    assert_true(
      call(session, "morphir.backend.generate", params~)
      .stringify()
      .contains("-32602"),
    )
  }
  let invalid = call(session, "morphir.backend.generate", params={
    "target": "moonbit",
    "ir": {
      "formatVersion": "4",
      "distribution": null,
      "metadata": { "keep": true },
    },
  })
  let result = @wire.field(invalid, "result")
  assert_eq(@wire.field(result, "success"), Json::boolean(false))
  assert_eq(@wire.field(result, "artifacts"), Json::array([]))
}
