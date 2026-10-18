///|
/// Fixed HTTP boundary cases drive the production selection decoder and cursor.
/// Effects, authentication and worker execution belong to the separate host kit.
fn http_policy_boundary(id : Json, input : Json) -> Json {
  let bytes = native_fixture_bytes(input, [
    "kind", "encoding", "source", "context",
  ])
  if bytes.length() > 1048576 {
    return invalid(id, "workbench.host_input_limit")
  }
  let source = @utf8.decode(bytes[:]) catch {
    _ => return invalid(id, "workbench.host_utf8")
  }
  let context = fixture_fields(field(input, "context"), [
    "sessionId", "offer", "submission",
  ])
  let client = @host.Client::new()
  let kind = field(input, "kind")
  let reply = if kind == Json::string("descriptor") {
    client.handle(
      (
        {
          "op": "host-policy-descriptor",
          "source": source,
          "sessionId": context["sessionId"],
        } : Json).stringify(),
    )
  } else if kind == Json::string("submit") {
    client.handle(
      (
        {
          "op": "validate-http-policy",
          "offer": context["offer"],
          "body": source,
        } : Json).stringify(),
    )
  } else if kind == Json::string("submission-reply") {
    let decoded = @host.decode_reply(source)
    if field(decoded, "ok") != Json::boolean(true) {
      return invalid(id, string_field(decoded, "code"))
    }
    let value = field(decoded, "value")
    guard value is Object(fields) &&
      fields.length() == 4 &&
      ["identity", "calls", "receipt", "plan"].all(name => fields.contains(name)) else {
      return invalid(id, "workbench.host_shape")
    }
    client.handle(
      (
        {
          "op": "start-http-policy",
          "offer": context["offer"],
          "body": context["submission"].stringify(),
          "identity": fields["identity"],
          "calls": fields["calls"],
          "receipt": fields["receipt"],
          "plan": fields["plan"],
        } : Json).stringify(),
    )
  } else {
    abort("workbench: invalid HTTP policy boundary kind")
  }
  if field(reply, "ok") != Json::boolean(true) {
    return invalid(id, string_field(reply, "code"))
  }
  let policy = if kind == Json::string("descriptor") {
    Json::null()
  } else {
    let raw = if kind == Json::string("submit") {
      source
    } else {
      context["submission"].stringify()
    }
    let decoded = field(@host.decode_reply(raw), "value")
    if field(decoded, "admission") == Json::null() {
      Json::string("strict")
    } else {
      field(field(decoded, "admission"), "policy")
    }
  }
  { "id": id, "status": "ok", "value": { "accepted": true, "policy": policy } }
}

///|
fn string_field(value : Json, name : String) -> String {
  guard field(value, name) is String(source) else {
    abort("workbench: production boundary returned no rejection code")
  }
  source
}
