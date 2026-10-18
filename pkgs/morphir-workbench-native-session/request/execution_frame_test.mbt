///|
test "native execution query uses the replacement execution contract" {
  let frame : Json = {
    "profile": "morphir/workbench/native",
    "contractVersion": "0.2.0-draft.1",
    "operation": "execution.query",
    "sessionId": "session",
    "payload": {
      "contractVersion": "0.2.0-draft.1",
      "identity": {
        "hostId": "host",
        "sessionId": "session",
        "providerId": "provider",
        "executionId": "execution-1",
        "snapshotId": "snapshot",
      },
    },
  }
  assert_eq(
    @request.decode(@utf8.encode(frame.stringify())).operation(),
    "execution.query",
  )
}

///|
test "native replacement frame rejects retired execution operations and versions" {
  for
    (operation, version) in [
      ("job.query", "0.2.0-draft.1"),
      ("job.submit", "0.2.0-draft.1"),
      ("execution.query", "0.1.0-draft.1"),
    ] {
    let source : Json = {
      "profile": "morphir/workbench/native",
      "contractVersion": version,
      "operation": operation,
      "sessionId": "session",
      "payload": {
        "contractVersion": "0.2.0-draft.1",
        "identity": {
          "hostId": "host",
          "sessionId": "session",
          "providerId": "provider",
          "executionId": "execution-1",
          "snapshotId": "snapshot",
        },
      },
    }
    let accepted = try {
      ignore(@request.decode(@utf8.encode(source.stringify())))
      true
    } catch {
      _ => false
    }
    assert_false(accepted)
  }
}
