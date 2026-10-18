///|
/// Draft.20 selects an exact policy mapping; historical boundary codecs remain
/// unchanged and never infer this mapping from an optional field.
fn native_policy_boundary(id : Json, input : Json) -> Json {
  let kind = field(input, "kind")
  if kind == Json::string("request") {
    let bytes = native_fixture_bytes(input, ["kind", "encoding", "source"])
    try {
      ignore(@native_frame.decode_policy(bytes))
      { "id": id, "status": "ok", "value": { "frameAccepted": true } }
    } catch {
      @native_frame.Invalid(code) => invalid(id, code)
    }
  } else if kind == Json::string("reply") {
    guard field(input, "expectedOperation") is String(operation) &&
      [
        "session.open", "session.check", "session.close", "execution.submit", "execution.query",
        "execution.cancel", "execution.release", "workspace.choose", "workspace.cancel-picker",
        "workspace.revoke", "workspace.open", "workspace.read", "workspace.release",
      ].contains(operation) else {
      abort("workbench: invalid captured native policy operation")
    }
    let session = captured_session(field(input, "expectedSession"))
    let bytes = native_fixture_bytes(input, [
      "kind", "expectedOperation", "expectedSession", "encoding", "source",
    ])
    try {
      let reply = @native_reply.decode_policy(
        bytes,
        operation,
        expected_session=session,
      )
      let envelope = reply.to_json()
      let value : Json = if field(envelope, "ok") == Json::boolean(true) {
        {
          "replyAccepted": true,
          "ok": true,
          "operation": field(envelope, "operation"),
        }
      } else {
        let effect = match reply.effect() {
          Some(@native_reply.NoEffect) => "none"
          Some(@native_reply.UnknownEffect) => "unknown"
          None => abort("workbench: admitted native failure lacks an effect")
        }
        {
          "replyAccepted": true,
          "ok": false,
          "error": {
            "code": field(field(envelope, "error"), "code"),
            "effect": effect,
          },
        }
      }
      { "id": id, "status": "ok", "value": value }
    } catch {
      @native_reply.Invalid(code) => invalid(id, code)
    }
  } else {
    abort("workbench: invalid native policy boundary kind")
  }
}
