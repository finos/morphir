///|
fn descriptor() -> Json {
  {
    "profile": "morphir/workbench/native",
    "contractVersion": "0.1.0-draft.1",
    "sessionId": "session",
    "operations": ["workspace"],
  }
}

///|
fn envelope(op : String, value : Json) -> Bytes {
  @utf8.encode(
    ({ "ok": true, "operation": op, "value": value } : Json).stringify(),
  )
}

///|
fn rejects(bytes : Bytes, operation~ : String = "workspace.read") -> Bool {
  try {
    ignore(@response.decode(bytes, operation))
    false
  } catch {
    _ => true
  }
}

///|
test "native reply codec admits correlated descriptor and closed failure effects" {
  let bytes = @response.success("session.open", descriptor())
  let reply = @response.decode(
    bytes,
    "session.open",
    expected_session=Some("session"),
  )
  assert_eq(
    reply.to_json(),
    ({ "ok": true, "operation": "session.open", "value": descriptor() } : Json),
  )
  assert_true(rejects(bytes, operation="session.check"))
  for effect in [@response.NoEffect, @response.UnknownEffect] {
    let reply = @response.decode(
      @response.failure(@response.Unavailable, effect),
      "job.submit",
    )
    assert_true(reply.effect() == Some(effect))
  }
}

///|
test "native reply codec rejects malformed raw and noncanonical chunks" {
  for
    bytes in [
      Bytes::from_array([0xFF]),
      Bytes::from_array([0xEF, 0xBB, 0xBF, 0x7B, 0x7D]),
      @utf8.encode("{} {}"),
      @utf8.encode(" ".repeat(1048577)),
      @utf8.encode(
        "{\"ok\":false,\"error\":{\"code\":\"limit\",\"effect\":\"none\",\"effect\":\"unknown\",\"message\":\"No\"}}",
      ),
      envelope("workspace.read", {
        "sequence": 1,
        "offset": 0,
        "content": "YR==",
        "done": true,
      }),
      envelope("workspace.read", {
        "sequence": 1.00000000001,
        "offset": 0,
        "content": "",
        "done": true,
      }),
    ] {
    assert_true(rejects(bytes))
  }
  let good : Json = {
    "sequence": 1,
    "offset": 0,
    "content": "YQ==",
    "done": true,
  }
  assert_eq(
    @response.decode(envelope("workspace.read", good), "workspace.read").to_json(),
    ({ "ok": true, "operation": "workspace.read", "value": good } : Json),
  )
}

///|
test "native grant reply rejects duplicate identities regardless of metadata" {
  let rows : Array[Json] = [
    { "id": "one", "name": "First", "available": true, "message": "" },
    { "id": "one", "name": "Second", "available": false, "message": "Missing" },
  ]
  assert_true(
    rejects(
      envelope("workspace.choose", {
        "cancelled": false,
        "grantId": "grant",
        "projects": rows,
        "warnings": [],
      }),
      operation="workspace.choose",
    ),
  )
  assert_false(
    rejects(
      envelope("workspace.choose", { "cancelled": true }),
      operation="workspace.choose",
    ),
  )
}

///|
fn identity() -> Json {
  {
    "hostId": "host",
    "sessionId": "session",
    "providerId": "scheme",
    "jobId": "job",
    "snapshotId": "snapshot",
  }
}

///|
fn receipt() -> Json {
  {
    "contractVersion": "0.1.0-draft.1",
    "identity": identity(),
    "sequence": 0,
    "state": "submitted",
    "cancelRequested": false,
    "outcomes": null,
  }
}

///|
test "all thirteen native operation payloads have production round trips" {
  for
    (operation, value) in [
      ("session.open", descriptor()),
      ("session.check", descriptor()),
      ("session.close", ({} : Json)),
      (
        "job.submit",
        (
          {
            "identity": identity(),
            "calls": ["workbench"],
            "receipt": receipt(),
          } : Json),
      ),
      ("job.query", receipt()),
      ("job.cancel", receipt()),
      ("job.release", ({ "released": true } : Json)),
      (
        "workspace.choose",
        (
          {
            "cancelled": false,
            "grantId": "grant",
            "projects": [
              {
                "id": "model",
                "name": "Model",
                "available": true,
                "message": "",
              },
            ],
            "warnings": ["Notice"],
          } : Json),
      ),
      ("workspace.cancel-picker", ({} : Json)),
      ("workspace.revoke", ({} : Json)),
      (
        "workspace.open",
        (
          {
            "sequence": 1,
            "size": 0,
            "format": "ion-binary",
            "filename": "model.ion",
          } : Json),
      ),
      (
        "workspace.read",
        ({ "sequence": 1, "offset": 0, "content": "", "done": true } : Json),
      ),
      ("workspace.release", ({} : Json)),
    ] {
    let encoded = @response.success(operation, value)
    let decoded = @response.decode(
      encoded,
      operation,
      expected_session=Some("session"),
    )
    assert_eq(
      decoded.to_json(),
      ({ "ok": true, "operation": operation, "value": value } : Json),
    )
    assert_true(decoded.effect() is None)
  }
}

///|
test "native error codes and effects are closed and Unicode message bounds use characters" {
  for
    code in [
      @response.InvalidRequest,
      @response.Unauthorized,
      @response.Unavailable,
      @response.NotFound,
      @response.Conflict,
      @response.Limit,
    ] {
    for effect in [@response.NoEffect, @response.UnknownEffect] {
      assert_true(
        @response.decode(@response.failure(code, effect), "session.close").effect() ==
        Some(effect),
      )
    }
  }
  let error : Json = {
    "ok": false,
    "error": {
      "code": "conflict",
      "effect": "none",
      "message": "😀".repeat(512),
    },
  }
  assert_false(rejects(@utf8.encode(error.stringify())))
  for
    (name, value) in [
      ("code", Json::string("internal_error")),
      ("effect", Json::string("maybe")),
      ("message", Json::string("")),
      ("message", Json::string("😀".repeat(513))),
      ("extra", Json::null()),
    ] {
    guard error is Object(fields) && fields["error"] is Object(inner) else {
      abort("fixture")
    }
    let copy = inner.to_array().iter().collect()
    let copy : Map[String, Json] = Map(copy)
    copy[name] = value
    assert_true(
      rejects(
        @utf8.encode(
          ({ "ok": false, "error": Json::object(copy) } : Json).stringify(),
        ),
      ),
    )
  }
}

///|
test "native replies bind descriptor and submission identity before cursor admission" {
  let bytes = envelope("session.check", descriptor())
  let different = try {
    ignore(
      @response.decode(bytes, "session.check", expected_session=Some("other")),
    )
    false
  } catch {
    _ => true
  }
  assert_true(different)
  let wrong : Json = {
    "hostId": "other",
    "sessionId": "session",
    "providerId": "scheme",
    "jobId": "job",
    "snapshotId": "snapshot",
  }
  assert_true(
    rejects(
      envelope("job.submit", {
        "identity": wrong,
        "calls": ["workbench"],
        "receipt": receipt(),
      }),
      operation="job.submit",
    ),
  )
  assert_true(
    rejects(
      envelope("job.submit", {
        "identity": identity(),
        "calls": ["different"],
        "receipt": receipt(),
      }),
      operation="job.submit",
    ),
  )
  let raw = @utf8.decode(envelope("job.query", receipt()))
  assert_true(
    rejects(
      @utf8.encode(
        raw.replace(old="\"sequence\":0", new="\"sequence\":-1e-999"),
      ),
      operation="job.query",
    ),
  )
  assert_true(
    rejects(
      @utf8.encode(
        raw.replace(
          old="\"sequence\":0",
          new="\"sequence\":0.00000000000000000001",
        ),
      ),
      operation="job.query",
    ),
  )
}

///|
test "whole reply and grant budgets include every wrapper byte" {
  let bytes = envelope("workspace.read", {
    "sequence": 1,
    "offset": 0,
    "content": "",
    "done": true,
  })
  let source = @utf8.decode(bytes)
  assert_false(
    rejects(@utf8.encode(" ".repeat(1048576 - bytes.length()) + source)),
  )
  assert_true(
    rejects(@utf8.encode(" ".repeat(1048577 - bytes.length()) + source)),
  )
  let cancelled = envelope("workspace.choose", { "cancelled": true })
  let source = @utf8.decode(cancelled)
  assert_false(
    rejects(
      @utf8.encode(" ".repeat(524288 - cancelled.length()) + source),
      operation="workspace.choose",
    ),
  )
  assert_true(
    rejects(
      @utf8.encode(" ".repeat(524289 - cancelled.length()) + source),
      operation="workspace.choose",
    ),
  )
  let huge : Json = {
    "sequence": 1,
    "offset": 0,
    "content": "A".repeat(262148),
    "done": true,
  }
  assert_true(rejects(envelope("workspace.read", huge)))
  assert_true(
    rejects(
      envelope("workspace.read", {
        "sequence": 1,
        "offset": 0,
        "content": "",
        "done": false,
      }),
    ),
  )
}

///|
test "bounded parsing rejects deep and large-node replies before shape recursion" {
  for
    raw in [
      "[".repeat(65) + "0" + "]".repeat(65),
      "[" + "0,".repeat(100000) + "0]",
    ] {
    let limited = try {
      ignore(@response.decode(@utf8.encode(raw), "workspace.read"))
      false
    } catch {
      @response.Invalid("native.reply.limit") => true
      _ => false
    }
    assert_true(limited)
  }
  let reply = @response.decode(
    envelope("workspace.open", {
      "sequence": 1,
      "size": 0,
      "format": "morphir-json",
      "filename": "model.json",
    }),
    "workspace.open",
  )
  guard reply.to_json() is Object(fields) && fields["value"] is Object(value) else {
    abort("fixture")
  }
  value["sequence"] = Json::number(2)
  guard reply.to_json() is Object(fields) && fields["value"] is Object(value) else {
    abort("fixture")
  }
  assert_eq(value["sequence"], Json::number(1))
}

///|
test "producer reserves the complete grant envelope and preserves Unicode basename bounds" {
  let rows : Array[Json] = Array::makei(128, i => {
    "id": "project-" + i.to_string(),
    "name": "é".repeat(1024),
    "available": true,
    "message": "é".repeat(1024),
  })
  let limited = try {
    ignore(
      @response.success("workspace.choose", {
        "cancelled": false,
        "grantId": "grant",
        "projects": rows,
        "warnings": [],
      }),
    )
    false
  } catch {
    @response.Invalid("native.reply.limit") => true
    _ => false
  }
  assert_true(limited)
  let filename = "😀".repeat(256)
  assert_false(
    rejects(
      envelope("workspace.open", {
        "sequence": 1,
        "size": 0,
        "format": "morphir-json",
        "filename": filename,
      }),
      operation="workspace.open",
    ),
  )
  assert_true(
    rejects(
      envelope("workspace.open", {
        "sequence": 1,
        "size": 0,
        "format": "morphir-json",
        "filename": filename + "😀",
      }),
      operation="workspace.open",
    ),
  )
}
