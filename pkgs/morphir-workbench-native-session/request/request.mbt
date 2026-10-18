///|
/// Framing diagnostics are stages, not native invocation error effects.
pub(all) suberror Invalid {
  Invalid(String)
}

///|
/// A syntactically admitted frame carries no caller, session or grant authority.
/// The source documents remain unchanged for later admission and capture.
pub struct Request {
  priv value : Json
}

///|
pub fn Request::operation(self : Request) -> String {
  match self.value {
    Object(fields) =>
      match fields["operation"] {
        String(op) => op
        _ => abort("Admitted request operation")
      }
    _ => abort("Admitted request object")
  }
}

///|
pub fn Request::to_json(self : Request) -> Json {
  // Json maps are mutable. Return a fresh copy so no caller can change an
  // admitted frame behind another owner's reference.
  @wire.parse_bounded(self.value.stringify()) catch {
    _ => abort("Admitted request copy")
  }
}

///|
fn closed(
  value : Json,
  keys : Array[String],
) -> Map[String, Json] raise Invalid {
  guard value is Object(fields) &&
    fields.length() == keys.length() &&
    keys.all(key => fields.contains(key)) else {
    raise Invalid("native.frame.shape")
  }
  fields
}

///|
fn text(value : Json, minimum : Int32, maximum : Int32) -> String raise Invalid {
  guard value is String(source) &&
    source.iter().count() >= minimum &&
    source.iter().count() <= maximum else {
    raise Invalid("native.frame.shape")
  }
  source
}

///|
fn token(value : Json) -> Unit raise Invalid {
  let value = text(value, 1, 128)
  guard value
    .iter()
    .all(c => {
      (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '.' ||
      c == '-'
    }) else {
    raise Invalid("native.frame.shape")
  }
}

///|
fn integer(
  value : Json,
  minimum : Double,
  maximum : Double,
) -> Unit raise Invalid {
  guard value is Number(n, ..) &&
    n >= minimum &&
    n <= maximum &&
    n.floor() == n &&
    @wire.is_integral_number(value) else {
    raise Invalid("native.frame.shape")
  }
}

///|
fn version(value : Json) -> Unit raise Invalid {
  guard value == Json::string("0.2.0-draft.1") else {
    raise Invalid("native.frame.shape")
  }
}

///|
fn shape(value : Json) -> Unit raise Invalid {
  guard value is Object(fields) && fields.get("operation") is Some(String(op)) else {
    raise Invalid("native.frame.shape")
  }
  let payload = match op {
    "session.open" => {
      ignore(closed(value, ["profile", "contractVersion", "operation"]))
      None
    }
    "session.check"
    | "session.close"
    | "workspace.choose"
    | "workspace.cancel-picker" => {
      ignore(
        closed(value, ["profile", "contractVersion", "operation", "sessionId"]),
      )
      token(fields["sessionId"])
      None
    }
    "execution.submit"
    | "execution.query"
    | "execution.cancel"
    | "execution.release"
    | "workspace.revoke"
    | "workspace.open"
    | "workspace.read"
    | "workspace.release" => {
      ignore(
        closed(value, [
          "profile", "contractVersion", "operation", "sessionId", "payload",
        ]),
      )
      token(fields["sessionId"])
      Some(fields["payload"])
    }
    _ => raise Invalid("native.frame.shape")
  }
  guard fields["profile"] == Json::string("morphir/workbench/native") else {
    raise Invalid("native.frame.shape")
  }
  version(fields["contractVersion"])
  if payload is Some(payload) {
    match op {
      "execution.submit" => {
        let payload = closed(payload, [
          "contractVersion", "model", "entry", "inputs",
        ])
        version(payload["contractVersion"])
        ignore(text(payload["model"], 1, 1048576))
        ignore(text(payload["entry"], 1, 1024))
        let inputs = closed(payload["inputs"], ["format", "source"])
        guard inputs["format"] == Json::string("json") ||
          inputs["format"] == Json::string("ion-text") else {
          raise Invalid("native.frame.shape")
        }
        ignore(text(inputs["source"], 0, 1048576))
      }
      "execution.query" | "execution.cancel" | "execution.release" => {
        let payload = closed(payload, ["contractVersion", "identity"])
        version(payload["contractVersion"])
        let keys = [
          "hostId", "sessionId", "providerId", "executionId", "snapshotId",
        ]
        let identity = closed(payload["identity"], keys)
        for key in keys {
          let item = text(identity[key], 1, 128)
          guard item.length() <= 128 else {
            raise Invalid("native.frame.shape")
          }
        }
      }
      "workspace.revoke" => {
        let payload = closed(payload, ["grantId"])
        token(payload["grantId"])
      }
      "workspace.open" => {
        let payload = closed(payload, ["grantId", "projectId", "sequence"])
        token(payload["grantId"])
        token(payload["projectId"])
        integer(payload["sequence"], 1, 2147483647)
      }
      "workspace.read" => {
        let payload = closed(payload, ["grantId", "sequence", "offset"])
        token(payload["grantId"])
        integer(payload["sequence"], 1, 2147483647)
        integer(payload["offset"], 0, 16777216)
      }
      "workspace.release" => {
        let payload = closed(payload, ["grantId", "sequence"])
        token(payload["grantId"])
        integer(payload["sequence"], 1, 2147483647)
      }
      _ => abort("Payload operation admitted")
    }
  }
}

///|
fn nested(value : Json) -> Unit raise Invalid {
  guard value is Object(fields) &&
    fields["operation"] == Json::string("execution.submit") else {
    return
  }
  let payload = closed(fields["payload"], [
    "contractVersion", "model", "entry", "inputs",
  ])
  let model = text(payload["model"], 1, 1048576)
  ignore(@wire.parse_bounded(model)) catch {
    _ => raise Invalid("native.frame.model")
  }
  let inputs = closed(payload["inputs"], ["format", "source"])
  if inputs["format"] == Json::string("json") {
    let source = text(inputs["source"], 0, 1048576)
    let arguments = @wire.parse_bounded(source) catch {
      _ => raise Invalid("native.frame.arguments")
    }
    guard arguments is Array(_) else { raise Invalid("native.frame.arguments") }
  }
}

///|
/// Production native draft.1 decoder. This boundary only admits framing and
/// closed shape; trusted caller checks, model/type admission and execution follow
/// separately. Never call dispatch with a framework-decoded Json object.
pub fn decode(bytes : Bytes) -> Request raise Invalid {
  guard bytes.length() <= 1048576 else { raise Invalid("native.frame.limit") }
  let source = @utf8.decode(bytes[:], ignore_bom=false) catch {
    _ => raise Invalid("native.frame.utf8")
  }
  let value = @wire.parse_bounded(source) catch {
    @wire.Invalid("json_limit", _) => raise Invalid("native.frame.limit")
    _ => raise Invalid("native.frame.json")
  }
  if value is Object(fields) &&
    fields.get("operation") is Some(String(op)) &&
    [
      "workspace.choose", "workspace.cancel-picker", "workspace.revoke", "workspace.open",
      "workspace.read", "workspace.release",
    ].contains(op) &&
    bytes.length() > 4096 {
    raise Invalid("native.frame.limit")
  }
  shape(value)
  nested(value)
  { value, }
}
