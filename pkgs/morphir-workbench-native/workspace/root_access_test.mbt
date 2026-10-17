///|
fn field(value : Json, name : String) -> Json {
  guard value is Object(fields) else { abort("Expected object") }
  fields[name]
}

///|
fn native_value(
  service : @workspace.Service,
  operation : String,
  payload : Json,
) -> Json raise {
  let envelope = @reply.decode(
    service.native_request(operation, payload),
    operation,
  ).to_json()
  assert_eq(field(envelope, "ok"), Json::boolean(true))
  field(envelope, "value")
}

///|
test "trusted root access preserves workspace capture and retirement policy" {
  // This tree is discovery input supplied by a trusted host, not OS authority.
  let snapshot : @workspace.Snapshot = {
    tree: {
      files: {
        "morphir.json": "{\"name\":\"demo/memory\",\"exposedModules\":[]}",
      },
      directories: [""],
    },
    files: ["morphir-ir.json", "morphir.json"],
  }
  let original = b"  {\"formatVersion\":1,\"unchanged\":true}\n" +
    Bytes::make(192 * 1024, 0x20)
  let stored = [original]
  let opens = [0]
  let closes = [0]
  let reads = [0]
  let service = @workspace.Service::new(open_root=fn(path) raise {
    assert_eq(path, "trusted-memory")
    opens[0] += 1
    {
      current: fn() raise { assert_eq(closes[0], 0) },
      snapshot: fn() { snapshot },
      read: fn(path) raise {
        assert_eq(path, "morphir-ir.json")
        reads[0] += 1
        stored[0]
      },
      close: fn() { closes[0] += 1 },
    }
  })
  let stale = service.begin_choose()
  service.cancel_choose()
  let ticket = service.begin_choose()
  let stale_rejected = try {
    ignore(service.finish_choose(stale, Some("trusted-memory")))
    false
  } catch {
    @workspace.Rejected(_) => true
    error => raise error
  }
  assert_true(stale_rejected)
  assert_eq(opens[0], 0)
  let offer = service.finish_choose(ticket, Some("trusted-memory"))
  assert_eq(field(offer, "ok"), Json::boolean(true))
  let grant = field(offer, "grantId")
  guard field(offer, "projects") is Array(projects) else {
    abort("Expected projects")
  }
  assert_eq(projects.length(), 1)
  assert_eq(field(projects[0], "name"), Json::string("demo/memory"))
  assert_eq(field(projects[0], "available"), Json::boolean(true))
  let project = field(projects[0], "id")
  let opened = native_value(service, "workspace.open", {
    "grantId": grant,
    "projectId": project,
    "sequence": 1,
  })
  assert_eq(field(opened, "size"), Json::number(original.length().to_double()))
  stored[0] = b"replaced after capture"
  let bad_offset = @reply.decode(
    service.native_request("workspace.read", {
      "grantId": grant,
      "sequence": 1,
      "offset": 1,
    }),
    "workspace.read",
  )
  assert_true(bad_offset.effect() == Some(@reply.UnknownEffect))
  let mut recovered = b""
  while recovered.length() < original.length() {
    let chunk = native_value(service, "workspace.read", {
      "grantId": grant,
      "sequence": 1,
      "offset": recovered.length(),
    })
    assert_eq(
      field(chunk, "offset"),
      Json::number(recovered.length().to_double()),
    )
    guard field(chunk, "content") is String(content) else {
      abort("Expected base64 content")
    }
    let bytes = @base64.decode(content[:])
    assert_true(bytes.length() <= 192 * 1024)
    recovered = recovered + bytes
    assert_eq(
      field(chunk, "done"),
      Json::boolean(recovered.length() == original.length()),
    )
  }
  assert_eq(recovered, original)
  assert_eq(reads[0], 1)
  ignore(
    native_value(service, "workspace.release", {
      "grantId": grant,
      "sequence": 1,
    }),
  )
  // Release may arrive before its open, and permanently retires that sequence.
  ignore(
    native_value(service, "workspace.release", {
      "grantId": grant,
      "sequence": 2,
    }),
  )
  let retired = @reply.decode(
    service.native_request("workspace.open", {
      "grantId": grant,
      "projectId": project,
      "sequence": 2,
    }),
    "workspace.open",
  )
  assert_true(retired.effect() == Some(@reply.UnknownEffect))
  assert_eq(reads[0], 1)
  let fresh = native_value(service, "workspace.open", {
    "grantId": grant,
    "projectId": project,
    "sequence": 3,
  })
  assert_eq(field(fresh, "size"), Json::number(stored[0].length().to_double()))
  service.close()
  service.close()
  assert_eq(opens[0], 1)
  assert_eq(closes[0], 1)
}
