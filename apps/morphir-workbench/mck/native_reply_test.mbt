///|
fn reply_request(input : Json) -> Json {
  {
    "id": 1,
    "op": "validate-native-reply",
    "suite": "workbench",
    "contractVersion": "0.1.0-draft.8",
    "format": "json",
    "input": input,
  }
}

///|
test "native reply MCK negotiates and invokes the production reply decoder" {
  let caps = @mck.handle({
    "id": 1,
    "op": "capabilities",
    "suite": "workbench",
    "contractVersion": "0.1.0-draft.8",
  })
  assert_eq(job_field(caps, "operations"), (["validate-native-reply"] : Json))
  assert_eq(job_field(caps, "formats"), (["json"] : Json))
  assert_eq(
    @mck.handle(
      reply_request({
        "expectedOperation": "session.close",
        "expectedSession": null,
        "encoding": "utf8",
        "source": "{\"ok\":true,\"operation\":\"session.close\",\"value\":{}}",
      }),
    ),
    (
      {
        "id": 1,
        "status": "ok",
        "value": {
          "replyAccepted": true,
          "ok": true,
          "operation": "session.close",
        },
      } : Json),
  )
}

///|
test "native reply MCK projects admitted effects and preserves call correlation" {
  for effect in ["none", "unknown"] {
    let source = (
      {
        "ok": false,
        "error": { "code": "unavailable", "effect": effect, "message": "No" },
      } : Json).stringify()
    assert_eq(
      @mck.handle(
        reply_request({
          "expectedOperation": "job.submit",
          "expectedSession": "session",
          "encoding": "utf8",
          "source": source,
        }),
      ),
      (
        {
          "id": 1,
          "status": "ok",
          "value": {
            "replyAccepted": true,
            "ok": false,
            "error": { "code": "unavailable", "effect": effect },
          },
        } : Json),
    )
  }
  assert_eq(
    @mck.handle(
      reply_request({
        "expectedOperation": "session.check",
        "expectedSession": null,
        "encoding": "utf8",
        "source": "{\"ok\":true,\"operation\":\"session.close\",\"value\":{}}",
      }),
    ),
    ({ "id": 1, "status": "invalid", "code": "native.reply.operation" } : Json),
  )
  assert_eq(
    @mck.handle(
      reply_request({
        "expectedOperation": "session.close",
        "expectedSession": null,
        "encoding": "hex",
        "source": "c328",
      }),
    ),
    ({ "id": 1, "status": "invalid", "code": "native.reply.utf8" } : Json),
  )
}
