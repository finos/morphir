///|
fn native_descriptor(operations : Json, jobs~ : Bool = true) -> Json {
  let fields : Map[String, Json] = {
    "profile": "morphir/workbench/native",
    "contractVersion": "0.1.0-draft.1",
    "sessionId": "session",
    "operations": operations,
  }
  if jobs {
    fields["offer"] = offer()
  }
  Json::object(fields)
}

///|
fn admit_native(raw : String, session~ : String = "session") -> Json {
  @jobs.Client::new().handle(
    ({ "op": "native-descriptor", "source": raw, "sessionId": session } : Json).stringify(),
  )
}

///|
test "native descriptors admit only closed capabilities and directly nested offers" {
  for operations in [(["jobs"] : Json), (["jobs", "workspace"] : Json)] {
    let descriptor = native_descriptor(operations)
    assert_eq(value(admit_native(descriptor.stringify())), descriptor)
  }
  for operations in [([] : Json), (["workspace"] : Json)] {
    let descriptor = native_descriptor(operations, jobs=false)
    assert_eq(value(admit_native(descriptor.stringify())), descriptor)
    assert_false(ok(admit_native(native_descriptor(operations).stringify())))
  }
  for
    operations in [
      (["workspace", "jobs"] : Json),
      (["jobs", "jobs"] : Json),
      (["evaluate"] : Json),
      (["jobs", "workspace", "other"] : Json),
      Json::null(),
      Json::string("jobs"),
    ] {
    assert_false(ok(admit_native(native_descriptor(operations).stringify())))
  }
  assert_false(
    ok(admit_native(native_descriptor(["jobs"], jobs=false).stringify())),
  )
}

///|
test "native admission binds page session without accepting an HTTP descriptor" {
  let native = native_descriptor(["jobs"])
  assert_false(ok(admit_native(native.stringify(), session="other")))
  assert_false(
    ok(
      admit_native(
        (
          {
            "profile": "morphir/workbench/host",
            "contractVersion": "0.1.0-draft.1",
            "offer": offer(),
          } : Json).stringify(),
      ),
    ),
  )
  assert_false(
    ok(
      @jobs.Client::new().handle(
        ({ "op": "offer", "value": native, "sessionId": "session" } : Json).stringify(),
      ),
    ),
  )
  for
    (name, replacement) in [
      ("profile", Json::string("morphir/workbench/host")),
      ("contractVersion", Json::string("0.1.0-draft.1+build")),
      ("contractVersion", Json::string("0.1.0-draft.2")),
      ("sessionId", Json::string("other")),
      ("sessionId", Json::string("")),
      ("sessionId", Json::string("a/b")),
      ("sessionId", Json::string("é")),
      ("sessionId", Json::string("s".repeat(129))),
      ("extra", Json::boolean(true)),
      ("offer", offer(session="other")),
    ] {
    guard native_descriptor(["jobs"]) is Object(fields) else {
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
      native_descriptor(["jobs"])
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
  let client = @jobs.Client::new()
  let host = @jobs.Host::new(offer().stringify())
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
            "source": native_descriptor(["jobs"]).stringify(),
            "sessionId": "other",
          } : Json).stringify(),
      ),
    ),
  )
  assert_eq(client.handle("{\"op\":\"view\"}"), before)
}
