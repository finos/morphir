///|
fn request(operation : String, payload~ : Json? = None) -> @files.Request raise {
  let fields : Map[String, Json] = Map([
    ("profile", Json::string(@files.PROFILE)),
    ("contractVersion", Json::string(@files.VERSION)),
    ("operation", Json::string(operation)),
  ])
  if operation != "session.open" {
    fields["sessionId"] = Json::string("session-1")
  }
  if payload is Some(payload) {
    fields["payload"] = payload
  }
  @files.decode_request(@utf8.encode(Json::object(fields).stringify()))
}

///|
fn rejects(action : () -> Unit raise) -> Unit raise {
  let rejected = try {
    action()
    false
  } catch {
    @files.Invalid(_) => true
    error => raise error
  }
  assert_true(rejected)
}

///|
test "file access has an explicit separate picker and no renderer path authority" {
  let choose = request("workspace.choose-write")
  assert_eq(choose.operation(), "workspace.choose-write")
  assert_true(choose.command() is Some(@files.ChooseWrite))
  assert_eq(choose.session_id().unwrap().to_string(), "session-1")
  rejects(fn() raise {
    ignore(
      request(
        "workspace.choose-write",
        payload=Some({ "path": "/tmp/renderer-selected" }),
      ),
    )
  })
  rejects(fn() raise { ignore(request("workspace.choose")) })
  rejects(fn() raise {
    ignore(
      request(
        "workspace.snapshot",
        payload=Some({ "grantId": "../outside", "sequence": 1 }),
      ),
    )
  })
  rejects(fn() raise {
    ignore(
      @files.decode_request(
        b"{\"profile\":\"morphir/workbench/native\",\"contractVersion\":\"0.2.0-draft.2\",\"operation\":\"workspace.choose\",\"sessionId\":\"session-1\"}",
      ),
    )
  })
}

///|
test "uploads carry bounded canonical bytes and checked sequence offset and revision" {
  let upload = request(
    "workspace.write",
    payload=Some({
      "grantId": "grant-1",
      "sequence": 1,
      "offset": 3,
      "content": "AP8=",
    }),
  )
  guard upload.command() is Some(@files.Write(grant, sequence, offset, bytes)) else {
    fail("upload")
  }
  assert_eq(grant.to_string(), "grant-1")
  assert_eq(sequence, 1)
  assert_eq(offset, 3)
  assert_eq(bytes, b"\x00\xff")
  for content in ["", "!", "YQ", "YR=="] {
    rejects(fn() raise {
      ignore(
        request(
          "workspace.write",
          payload=Some({
            "grantId": "grant-1",
            "sequence": 1,
            "offset": 0,
            "content": content,
          }),
        ),
      )
    })
  }
  for sequence in [0.0, -1.0, 2147483648.0] {
    rejects(fn() raise {
      ignore(
        request(
          "workspace.snapshot",
          payload=Some({ "grantId": "grant-1", "sequence": sequence }),
        ),
      )
    })
  }
  for size in [0, 25165825] {
    rejects(fn() raise {
      ignore(
        request(
          "workspace.begin-edit",
          payload=Some({
            "grantId": "grant-1",
            "sequence": 1,
            "baseRevision": 0,
            "size": size,
          }),
        ),
      )
    })
  }
  rejects(fn() raise {
    ignore(
      request(
        "workspace.write",
        payload=Some({
          "grantId": "grant-1",
          "sequence": 1,
          "offset": 25165824,
          "content": "YQ==",
        }),
      ),
    )
  })
  rejects(fn() raise {
    ignore(
      request(
        "workspace.commit",
        payload=Some({
          "grantId": "grant-1",
          "sequence": 1,
          "path": "elsewhere",
        }),
      ),
    )
  })
}

///|
test "reply admission binds each response to its operation session sequence and offset" {
  let read = request(
    "workspace.read",
    payload=Some({ "grantId": "grant-1", "sequence": 2, "offset": 3 }),
  )
  let session = @files.SessionId::parse("session-1")
  let good : Json = {
    "sequence": 2,
    "offset": 3,
    "content": "AP8=",
    "done": true,
  }
  let reply = @files.success(read, session, good)
  assert_eq(
    @files.decode_reply(read, reply).to_json(),
    @json.parse(@utf8.decode(reply)),
  )
  rejects(fn() raise {
    ignore(@files.success(read, @files.SessionId::parse("session-2"), good))
  })
  for
    changed in [
      good.stringify().replace(old="\"sequence\":2", new="\"sequence\":3"),
      good.stringify().replace(old="\"offset\":3", new="\"offset\":4"),
    ] {
    rejects(fn() raise {
      ignore(@files.success(read, session, @json.parse(changed)))
    })
  }
  let other = request(
    "workspace.commit",
    payload=Some({ "grantId": "grant-1", "sequence": 2 }),
  )
  rejects(fn() raise { ignore(@files.decode_reply(other, reply)) })
  let written = request(
    "workspace.write",
    payload=Some({
      "grantId": "grant-1",
      "sequence": 2,
      "offset": 3,
      "content": "AP8=",
    }),
  )
  ignore(@files.success(written, session, { "sequence": 2, "offset": 5 }))
  rejects(fn() raise {
    ignore(@files.success(written, session, { "sequence": 2, "offset": 3 }))
  })
}

///|
test "status is a closed transfer state and retains uncertain commit evidence" {
  let status = request(
    "workspace.status",
    payload=Some({ "grantId": "grant-1", "sequence": 4 }),
  )
  let session = @files.SessionId::parse("session-1")
  for
    value in [
      ({ "sequence": 4, "state": "idle" } : Json),
      { "sequence": 4, "state": "uploading", "offset": 3, "size": 9 },
      { "sequence": 4, "state": "committed", "revision": 1 },
      {
        "sequence": 4,
        "state": "failed",
        "error": {
          "code": "workspace_files.recovery",
          "message": "Backup retained",
          "effect": "unknown",
        },
      },
    ] {
    ignore(@files.success(status, session, value))
  }
  for
    invalid in [
      ({ "state": "idle" } : Json),
      { "sequence": 4, "state": "idle", "revision": 1 },
      { "sequence": 4, "state": "uploading", "offset": 10, "size": 9 },
      { "sequence": 4, "state": "committed", "revision": 0 },
      { "sequence": 4, "state": "future" },
    ] {
    rejects(fn() raise { ignore(@files.success(status, session, invalid)) })
  }
  let uncertain = @files.failure(
    status,
    @files.Uncertain(
      "workspace_files.recovery", "Commit may have changed files",
    ),
  )
  let denied = @files.failure(
    status,
    @files.Denied("workspace_files.stale", "Nothing changed"),
  )
  assert_eq(
    @wire.field(
      @wire.field(@files.decode_reply(status, uncertain).to_json(), "error"),
      "effect",
    ),
    Json::string("unknown"),
  )
  assert_eq(
    @wire.field(
      @wire.field(@files.decode_reply(status, denied).to_json(), "error"),
      "effect",
    ),
    Json::string("none"),
  )
}

///|
test "descriptors are bounded support claims and do not contain filesystem locators" {
  let open = request("session.open")
  let session = @files.SessionId::parse("session-1")
  ignore(@files.success(open, session, @files.descriptor()))
  let choose = request("workspace.choose-write")
  ignore(@files.success(choose, session, { "cancelled": true }))
  ignore(
    @files.success(choose, session, {
      "cancelled": false,
      "grantId": "grant-1",
      "revision": 0,
      "name": "Example",
    }),
  )
  rejects(fn() raise {
    ignore(
      @files.success(choose, session, {
        "cancelled": false,
        "grantId": "grant-1",
        "revision": 0,
        "name": "Example",
        "path": "/tmp/example",
      }),
    )
  })
  rejects(fn() raise {
    ignore(@files.decode_request(Bytes::make(@files.FRAME_LIMIT + 1, 0x20)))
  })
  rejects(fn() raise { ignore(@files.decode_request(b"\xff")) })
  rejects(fn() raise {
    ignore(
      @files.decode_request(
        b"{\"profile\":\"morphir/workbench/workspace-files\",\"contractVersion\":\"0.1.0-draft.1\",\"operation\":\"session.open\",\"operation\":\"session.open\"}",
      ),
    )
  })
}
