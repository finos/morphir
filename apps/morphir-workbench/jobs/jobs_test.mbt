///|
fn offer(session~ : String = "session") -> Json {
  {
    "profile": "morphir/workbench/jobs",
    "contractVersion": "0.1.0-draft.1",
    "hostId": "host",
    "sessionId": session,
    "providerId": "moonbit-scheme",
    "operations": ["query", "cancel"],
  }
}

///|
fn body(
  format~ : String = "json",
  inputs~ : String = "[{\"type\":\"int\",\"value\":\"45\"},{\"type\":\"int\",\"value\":\"3\"}]",
) -> Json raise {
  {
    "contractVersion": "0.1.0-draft.1",
    "model": @codec.to_json(@fixtures.invocation_library()).stringify(),
    "entry": "calls:main#subtract",
    "inputs": { "format": format, "source": inputs },
  }
}

///|
fn value(reply : Json) -> Json raise {
  @wire.field(reply, "value")
}

///|
fn ok(reply : Json) -> Bool raise {
  @wire.field(reply, "ok") == Json::boolean(true)
}

///|
fn request(identity : Json) -> String {
  ({ "contractVersion": "0.1.0-draft.1", "identity": identity } : Json).stringify()
}

///|
fn outcomes(value~ : Json = { "type": "int", "value": "42" }) -> Json {
  {
    "contractVersion": "0.1.0-draft.5",
    "calls": [
      { "id": "workbench", "outcome": { "status": "returned", "value": value } },
    ],
    "cleanup": null,
    "extensions": null,
  }
}

///|
test "host bridge admits JSON and Ion to the same captured invocation" {
  for
    (format, inputs) in [
      (
        "json", "[{\"type\":\"int\",\"value\":\"45\"},{\"type\":\"int\",\"value\":\"3\"}]",
      ),
      ("ion-text", "[45,3]"),
    ] {
    let host = @jobs.Host::new(offer().stringify())
    let initial = value(
      host.handle(
        ({ "op": "submit", "body": body(format~, inputs~).stringify() } : Json).stringify(),
      ),
    )
    let identity = @wire.field(initial, "identity")
    let claimed = value(
      host.handle(({ "op": "claim", "identity": identity } : Json).stringify()),
    )
    assert_eq(
      @wire.field(claimed, "arguments"),
      @jobs.decode(
        "[{\"type\":\"int\",\"value\":\"45\"},{\"type\":\"int\",\"value\":\"3\"}]",
      ),
    )
    assert_false(
      ok(
        host.handle(
          ({ "op": "claim", "identity": identity } : Json).stringify(),
        ),
      ),
    )
    let terminal = host.handle(
      ({ "op": "complete", "identity": identity, "outcomes": outcomes() } : Json).stringify(),
    )
    assert_true(ok(terminal))
    assert_eq(@wire.field(value(terminal), "state"), Json::string("terminal"))
  }
}

///|
test "host wire admission rejects closed shapes versions and duplicate inputs atomically" {
  let host = @jobs.Host::new(offer().stringify())
  for
    raw in [
      "{}", "{\"contractVersion\":\"0.1.0-draft.2\"}", "{\"contractVersion\":\"0.1.0-draft.1\",\"contractVersion\":\"0.1.0-draft.1\"}",
    ] {
    assert_false(
      ok(host.handle(({ "op": "submit", "body": raw } : Json).stringify())),
    )
  }
  let bad = body(
    inputs="[{\"type\":\"int\",\"value\":\"45\",\"value\":\"99\"},{\"type\":\"int\",\"value\":\"3\"}]",
  )
  assert_false(
    ok(
      host.handle(
        ({ "op": "submit", "body": bad.stringify() } : Json).stringify(),
      ),
    ),
  )
  let first = value(
    host.handle(
      ({ "op": "submit", "body": body().stringify() } : Json).stringify(),
    ),
  )
  let identity = @wire.field(first, "identity")
  assert_eq(@wire.field(identity, "jobId"), Json::string("job-1"))
  assert_false(
    ok(
      host.handle(
        ({ "op": "release", "body": request(identity) } : Json).stringify(),
      ),
    ),
  )
  assert_eq(
    value(
      host.handle(
        ({ "op": "query", "body": request(identity) } : Json).stringify(),
      ),
    ),
    @wire.field(first, "receipt"),
  )
}

///|
test "client binds authenticated offer and uses retained qualified cursor" {
  let client = @jobs.Client::new()
  let descriptor : Json = {
    "profile": "morphir/workbench/host",
    "contractVersion": "0.1.0-draft.1",
    "offer": offer(),
  }
  assert_true(
    ok(
      client.handle(
        ({ "op": "offer", "value": descriptor, "sessionId": "session" } : Json).stringify(),
      ),
    ),
  )
  assert_false(
    ok(
      client.handle(
        ({ "op": "offer", "value": descriptor, "sessionId": "other" } : Json).stringify(),
      ),
    ),
  )
  let host = @jobs.Host::new(offer().stringify())
  let initial = value(
    host.handle(
      ({ "op": "submit", "body": body().stringify() } : Json).stringify(),
    ),
  )
  let identity = @wire.field(initial, "identity")
  let start : Json = {
    "op": "start",
    "offer": offer(),
    "identity": identity,
    "calls": ["workbench"],
    "receipt": @wire.field(initial, "receipt"),
  }
  assert_true(ok(client.handle(start.stringify())))
  assert_false(ok(client.handle(start.stringify())))
  assert_true(ok(client.handle("{\"op\":\"disconnect\"}")))
  let latest = value(
    host.handle(
      ({ "op": "cancel", "body": request(identity) } : Json).stringify(),
    ),
  )
  assert_false(
    ok(
      client.handle(({ "op": "observe", "receipt": latest } : Json).stringify()),
    ),
  )
  assert_false(
    ok(
      client.handle(
        ({ "op": "reconnect", "offer": offer(session="other") } : Json).stringify(),
      ),
    ),
  )
  assert_eq(
    @wire.field(
      @wire.field(client.handle("{\"op\":\"view\"}"), "job"),
      "connected",
    ),
    Json::boolean(false),
  )
  assert_true(
    ok(
      client.handle(
        ({ "op": "reconnect", "offer": offer() } : Json).stringify(),
      ),
    ),
  )
  let acknowledged = client.handle(
    ({ "op": "observe", "receipt": latest } : Json).stringify(),
  )
  assert_eq(
    @wire.field(@wire.field(acknowledged, "job"), "cancelAction"),
    Json::string("pending"),
  )
  let terminal = value(
    host.handle(
      ({ "op": "complete", "identity": identity, "outcomes": outcomes() } : Json).stringify(),
    ),
  )
  let result = client.handle(
    ({ "op": "observe", "receipt": terminal } : Json).stringify(),
  )
  assert_eq(
    @wire.field(@wire.field(result, "job"), "state"),
    Json::string("terminal"),
  )
  assert_eq(
    @wire.field(@wire.field(result, "result"), "typed"),
    ({ "type": "int", "value": "42" } : Json),
  )
  assert_true(
    ok(
      host.handle(
        ({ "op": "release", "body": request(identity) } : Json).stringify(),
      ),
    ),
  )
}

///|
test "raw decoder rejects nested duplicate members and UTF8 byte excess" {
  let client = @jobs.Client::new()
  for
    raw in [
      "{\"outer\":{\"x\":1,\"\\u0078\":2}}",
      " ".repeat(1048577),
      "é".repeat(524289),
    ] {
    assert_false(
      ok(client.handle(({ "op": "decode", "source": raw } : Json).stringify())),
    )
  }
  assert_false(ok(client.handle("{}")))
}

///|
test "Ion structural depth is bounded before recursive value parsing" {
  let host = @jobs.Host::new(offer().stringify())
  let raw = body(
    format="ion-text",
    inputs="[".repeat(20000) + "0" + "]".repeat(20000),
  )
  let reply = host.handle(
    ({ "op": "submit", "body": raw.stringify() } : Json).stringify(),
  )
  assert_eq(
    @wire.field(reply, "code"),
    Json::string("workbench.host_input_limit"),
  )
  let comment = body(
    format="ion-text",
    inputs="[/*" + "[".repeat(600) + "*/45,3]",
  )
  assert_true(
    ok(
      host.handle(
        ({ "op": "submit", "body": comment.stringify() } : Json).stringify(),
      ),
    ),
  )
}
