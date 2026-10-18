///|
fn native_descriptor(operations : Json, executions~ : Bool = true) -> Json {
  let fields : Map[String, Json] = {
    "profile": "morphir/workbench/native",
    "contractVersion": "0.2.0-draft.1",
    "sessionId": "session",
    "operations": operations,
  }
  if executions {
    fields["offer"] = offer()
  }
  Json::object(fields)
}

///|
fn admit_native(raw : String, session~ : String = "session") -> Json {
  @executions.Client::new().handle(
    ({ "op": "native-descriptor", "source": raw, "sessionId": session } : Json).stringify(),
  )
}

///|
test "native descriptors admit only closed capabilities and directly nested offers" {
  for
    operations in [
      (["executions"] : Json),
      (["executions", "workspace"] : Json),
    ] {
    let descriptor = native_descriptor(operations)
    assert_eq(value(admit_native(descriptor.stringify())), descriptor)
  }
  for operations in [([] : Json), (["workspace"] : Json)] {
    let descriptor = native_descriptor(operations, executions=false)
    assert_eq(value(admit_native(descriptor.stringify())), descriptor)
    assert_false(ok(admit_native(native_descriptor(operations).stringify())))
  }
  for
    operations in [
      (["workspace", "executions"] : Json),
      (["executions", "executions"] : Json),
      (["evaluate"] : Json),
      (["executions", "workspace", "other"] : Json),
      Json::null(),
      Json::string("executions"),
    ] {
    assert_false(ok(admit_native(native_descriptor(operations).stringify())))
  }
  assert_false(
    ok(
      admit_native(
        native_descriptor(["executions"], executions=false).stringify(),
      ),
    ),
  )
}

///|
test "native admission binds page session without accepting an HTTP descriptor" {
  let native = native_descriptor(["executions"])
  assert_false(ok(admit_native(native.stringify(), session="other")))
  assert_false(
    ok(
      admit_native(
        (
          {
            "profile": "morphir/workbench/host",
            "contractVersion": "0.2.0-draft.1",
            "offer": offer(),
          } : Json).stringify(),
      ),
    ),
  )
  assert_false(
    ok(
      @executions.Client::new().handle(
        ({ "op": "offer", "value": native, "sessionId": "session" } : Json).stringify(),
      ),
    ),
  )
  for
    (name, replacement) in [
      ("profile", Json::string("morphir/workbench/host")),
      ("contractVersion", Json::string("0.2.0-draft.1+build")),
      ("contractVersion", Json::string("0.1.0-draft.2")),
      ("sessionId", Json::string("other")),
      ("sessionId", Json::string("")),
      ("sessionId", Json::string("a/b")),
      ("sessionId", Json::string("é")),
      ("sessionId", Json::string("s".repeat(129))),
      ("extra", Json::boolean(true)),
      ("offer", offer(session="other")),
    ] {
    guard native_descriptor(["executions"]) is Object(fields) else {
      abort("fixture")
    }
    fields[name] = replacement
    assert_false(ok(admit_native(Json::object(fields).stringify())))
  }
}

///|
test "native raw descriptor rejection precedes cursor mutation" {
  for
    raw in [
      "null",
      "[]",
      "{}",
      "{} {}",
      "\uFEFF{}",
      "{\"profile\":\"first\",\"profile\":\"morphir/workbench/native\"}",
      native_descriptor(["executions"])
      .stringify()
      .replace(
        old="\"hostId\":\"host\"",
        new="\"hostId\":\"host\",\"ho\\u0073tId\":\"host\"",
      ),
      " ".repeat(1048577),
      "[".repeat(65) + "0" + "]".repeat(65),
    ] {
    assert_false(ok(admit_native(raw)))
  }
  let client = @executions.Client::new()
  let host = @executions.Host::new(offer().stringify())
  let initial = value(
    host.handle(
      ({ "op": "submit", "body": body().stringify() } : Json).stringify(),
    ),
  )
  assert_true(
    ok(
      client.handle(
        (
          {
            "op": "start",
            "offer": offer(),
            "identity": @wire.field(initial, "identity"),
            "calls": ["workbench"],
            "receipt": @wire.field(initial, "receipt"),
          } : Json).stringify(),
      ),
    ),
  )
  let before = client.handle("{\"op\":\"view\"}")
  assert_false(
    ok(
      client.handle(
        (
          {
            "op": "native-descriptor",
            "source": native_descriptor(["executions"]).stringify(),
            "sessionId": "other",
          } : Json).stringify(),
      ),
    ),
  )
  assert_eq(client.handle("{\"op\":\"view\"}"), before)
}
