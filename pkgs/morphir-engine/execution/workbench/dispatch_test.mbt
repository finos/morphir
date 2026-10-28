///|
test "unknown operations refuse without changing the host or wire failure" {
  let host = @workbench.Host::new(
    (
      {
        "profile": "morphir/workbench/executions",
        "contractVersion": "0.2.0-draft.1",
        "hostId": "host",
        "sessionId": "session",
        "providerId": "moonbit-scheme",
        "operations": ["query", "cancel"],
      } : Json).stringify(),
  )
  for op in ["unknown", "Submit", "submit-scheme-extra", ""] {
    assert_eq(
      host.handle(({ "op": op, "body": "not parsed" } : Json).stringify()),
      { "ok": false, "code": "workbench.host_operation" },
    )
  }
  assert_eq(host.handle("{\"op\":1}"), {
    "ok": false,
    "code": "workbench.host_shape",
  })
  let body : Json = {
    "contractVersion": "0.2.0-draft.1",
    "model": @codec.to_json(@fixtures.invocation_library()).stringify(),
    "entry": "calls:main#subtract",
    "inputs": {
      "format": "json",
      "source": "[{\"type\":\"int\",\"value\":\"45\"},{\"type\":\"int\",\"value\":\"3\"}]",
    },
  }
  let accepted = host.handle(
    ({ "op": "submit", "body": body.stringify() } : Json).stringify(),
  )
  assert_eq(@wire.field(accepted, "ok"), Json::boolean(true))
  let identity = @wire.field(@wire.field(accepted, "value"), "identity")
  let receipt_body = (
    { "contractVersion": "0.2.0-draft.1", "identity": identity } : Json).stringify()
  let queried = host.handle(
    ({ "op": "query", "body": receipt_body } : Json).stringify(),
  )
  assert_eq(@wire.field(queried, "ok"), Json::boolean(true))
  let claimed = host.handle(
    ({ "op": "claim", "identity": identity } : Json).stringify(),
  )
  assert_eq(@wire.field(claimed, "ok"), Json::boolean(true))
  let outcomes : Json = {
    "contractVersion": "0.1.0-draft.5",
    "calls": [
      {
        "id": "workbench",
        "outcome": {
          "status": "returned",
          "value": { "type": "int", "value": "42" },
        },
      },
    ],
    "cleanup": null,
    "extensions": null,
  }
  let completed = host.handle(
    ({ "op": "complete", "identity": identity, "outcomes": outcomes } : Json).stringify(),
  )
  assert_eq(@wire.field(completed, "ok"), Json::boolean(true))
  let cancelled = host.handle(
    ({ "op": "cancel", "body": receipt_body } : Json).stringify(),
  )
  assert_eq(@wire.field(cancelled, "ok"), Json::boolean(true))
  assert_eq(
    host.handle(({ "op": "release", "body": receipt_body } : Json).stringify()),
    { "ok": true, "value": { "released": true } },
  )
}
