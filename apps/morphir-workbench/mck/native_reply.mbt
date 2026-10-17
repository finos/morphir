///|
fn captured_session(value : Json) -> String? {
  if value == Json::null() {
    return None
  }
  guard value is String(session) &&
    session.length() >= 1 &&
    session.length() <= 128 &&
    session
    .iter()
    .all(c => {
      (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '.' ||
      c == '-'
    }) else {
    abort("workbench: invalid captured native session")
  }
  Some(session)
}

///|
/// A captured call is infrastructure data. It cannot create native authority.
/// Only the production decoder interprets the original materialized reply bytes.
fn native_reply(id : Json, input : Json) -> Json {
  guard field(input, "expectedOperation") is String(operation) &&
    [
      "session.open", "session.check", "session.close", "job.submit", "job.query",
      "job.cancel", "job.release", "workspace.choose", "workspace.cancel-picker",
      "workspace.revoke", "workspace.open", "workspace.read", "workspace.release",
    ].contains(operation) else {
    abort("workbench: invalid captured native operation")
  }
  let session = captured_session(field(input, "expectedSession"))
  let bytes = native_fixture_bytes(input, [
    "expectedOperation", "expectedSession", "encoding", "source",
  ])
  try {
    let reply = @native_reply.decode(bytes, operation, expected_session=session)
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
}
