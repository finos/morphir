///|
fn policy_frame(policy : Json?) -> Json {
  let body : Map[String, Json] = {
    "contractVersion": "0.2.0-draft.1",
    "model": "{}",
    "entry": "selected:main#answer",
    "inputs": { "format": "json", "source": "[]" },
    "runtime": "scheme",
    "providerId": "moonbit-scheme",
  }
  if policy is Some(value) {
    body["admission"] = value
  }
  {
    "profile": "morphir/workbench/native",
    "contractVersion": "0.2.0-draft.2",
    "operation": "execution.submit",
    "sessionId": "session-1",
    "payload": Json::object(body),
  }
}

///|
fn policy_decodes(value : Json) -> Bool {
  try {
    ignore(@request.decode_policy(@utf8.encode(value.stringify())))
    true
  } catch {
    _ => false
  }
}

///|
test "new native mapping is exact and leaves policy omission unresolved until owner acceptance" {
  for
    policy in [
      None,
      Some(
        (
          {
            "profile": "morphir/workbench/admission",
            "contractVersion": "0.1.0-draft.1",
            "policy": "strict",
          } : Json),
      ),
      Some(
        (
          {
            "profile": "morphir/workbench/admission",
            "contractVersion": "0.1.0-draft.1",
            "policy": "permissive",
          } : Json),
      ),
    ] {
    let frame = policy_frame(policy)
    let admitted = @request.decode_policy(@utf8.encode(frame.stringify()))
    assert_eq(admitted.to_json(), frame)
    assert_true(admitted.contract() == @request.CapabilityChecks)
    assert_eq(
      @request.decode_current(@utf8.encode(frame.stringify())).to_json(),
      frame,
    )
    let frozen_rejects = try {
      ignore(@request.decode(@utf8.encode(frame.stringify())))
      false
    } catch {
      _ => true
    }
    assert_true(frozen_rejects)
  }
}

///|
test "policy mapping rejects unsupported selections extra fields and retired execution fields" {
  for
    (key, value) in [
      ("runtime", Json::string("javascript")),
      ("providerId", Json::string("")),
      ("jobId", Json::string("old")),
      ("extra", Json::boolean(true)),
      (
        "admission",
        (
          {
            "profile": "morphir/workbench/admission",
            "contractVersion": "0.1.0-draft.1",
            "policy": "future",
          } : Json),
      ),
      (
        "admission",
        (
          {
            "profile": "morphir/workbench/admission",
            "contractVersion": "0.1.0-draft.1+build",
            "policy": "permissive",
          } : Json),
      ),
    ] {
    let frame = policy_frame(None)
    guard frame is Object(fields) && fields["payload"] is Object(body) else {
      abort("fixture")
    }
    body[key] = value
    assert_false(policy_decodes(frame), msg=key)
  }
}
