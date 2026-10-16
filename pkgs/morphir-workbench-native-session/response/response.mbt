///|
pub(all) suberror Invalid {
  Invalid(String)
}

///|
pub(all) enum Code {
  InvalidRequest
  Unauthorized
  Unavailable
  NotFound
  Conflict
  Limit
}

///|
/// An effect concerns this invocation only, not earlier requests.
pub(all) enum Effect {
  NoEffect
  UnknownEffect
} derive(Eq)

///|
pub extend Effect with Eq::{equal, not_equal}

///|
/// Constructed only after raw framing, shape and operation admission.
pub struct Reply {
  priv envelope : Json
  priv effect : Effect?
}

///|
pub fn Reply::effect(self : Reply) -> Effect? {
  self.effect
}

///|
pub fn Reply::to_json(self : Reply) -> Json {
  @wire.parse_bounded(self.envelope.stringify()) catch {
    _ => abort("Admitted native reply copy")
  }
}

///|
fn closed(
  value : Json,
  names : Array[String],
) -> Map[String, Json] raise Invalid {
  guard value is Object(fields) &&
    fields.length() == names.length() &&
    names.all(name => fields.contains(name)) else {
    raise Invalid("native.reply.shape")
  }
  fields
}

///|
fn text(value : Json, minimum : Int32, maximum : Int32) -> String raise Invalid {
  guard value is String(value) &&
    value.iter().count() >= minimum &&
    value.iter().count() <= maximum else {
    raise Invalid("native.reply.shape")
  }
  value
}

///|
fn token(value : Json) -> String raise Invalid {
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
    raise Invalid("native.reply.shape")
  }
  value
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
    @wire.is_integral_number(value) else {
    raise Invalid("native.reply.shape")
  }
}

///|
fn boolean(value : Json) -> Unit raise Invalid {
  guard value is True || value is False else {
    raise Invalid("native.reply.shape")
  }
}

///|
fn parse(bytes : Bytes) -> Json raise Invalid {
  guard bytes.length() <= 1048576 else { raise Invalid("native.reply.limit") }
  let source = @utf8.decode(bytes[:], ignore_bom=false) catch {
    _ => raise Invalid("native.reply.utf8")
  }
  @wire.parse_bounded(source) catch {
    @wire.Invalid("json_limit", _) => raise Invalid("native.reply.limit")
    _ => raise Invalid("native.reply.json")
  }
}

///|
fn descriptor_value(value : Json, expected_session : String?) -> Json raise {
  guard value is Object(fields) && fields.get("operations") is Some(operations) else {
    raise Invalid("native.reply.shape")
  }
  let jobs = operations == (["jobs"] : Json) ||
    operations == (["jobs", "workspace"] : Json)
  guard jobs ||
    operations == ([] : Json) ||
    operations == (["workspace"] : Json) else {
    raise Invalid("native.reply.shape")
  }
  ignore(
    closed(
      value,
      if jobs {
        ["profile", "contractVersion", "sessionId", "operations", "offer"]
      } else {
        ["profile", "contractVersion", "sessionId", "operations"]
      },
    ),
  )
  guard fields["profile"] == Json::string("morphir/workbench/native") &&
    fields["contractVersion"] == Json::string("0.1.0-draft.1") else {
    raise Invalid("native.reply.shape")
  }
  let session = token(fields["sessionId"])
  if expected_session is Some(expected) && session != expected {
    raise Invalid("native.reply.authority")
  }
  if jobs {
    let offer = @jobs.Offer::from_json(fields["offer"]).to_json()
    guard offer is Object(authority) &&
      authority["sessionId"] == Json::string(session) else {
      raise Invalid("native.reply.authority")
    }
    fields["offer"] = offer
  }
  Json::object(fields)
}

///|
/// A descriptor is data. Its binding must establish current native page authority.
pub fn descriptor(
  bytes : Bytes,
  expected_session~ : String? = None,
) -> Json raise Invalid {
  descriptor_value(parse(bytes), expected_session) catch {
    Invalid(code) => raise Invalid(code)
    _ => raise Invalid("native.reply.shape")
  }
}

///|
fn identity_session(
  value : Json,
  expected_session : String?,
) -> Unit raise Invalid {
  if expected_session is Some(session) {
    guard value is Object(fields) &&
      fields.get("sessionId") == Some(Json::string(session)) else {
      raise Invalid("native.reply.authority")
    }
  }
}

///|
fn receipt(value : Json, expected_session : String?) -> @jobs.Receipt raise {
  guard value is Object(fields) &&
    fields.get("sequence") is Some(sequence) &&
    fields.get("identity") is Some(identity) else {
    raise Invalid("native.reply.shape")
  }
  integer(sequence, 0, 2147483647)
  identity_session(identity, expected_session)
  @jobs.Receipt::from_json(value)
}

///|
fn payload(
  operation : String,
  value : Json,
  expected_session : String?,
) -> Json raise {
  match operation {
    "session.open" | "session.check" =>
      descriptor_value(value, expected_session)
    "session.close"
    | "workspace.cancel-picker"
    | "workspace.revoke"
    | "workspace.release" => {
      ignore(closed(value, []))
      value
    }
    "job.submit" => {
      let fields = closed(value, ["identity", "calls", "receipt"])
      let identity = @jobs.Identity::from_json(fields["identity"])
      identity_session(fields["identity"], expected_session)
      let initial = receipt(fields["receipt"], expected_session)
      guard fields["calls"] == (["workbench"] : Json) &&
        initial.identity() == identity &&
        initial.sequence() == 0 &&
        initial.state() is Submitted &&
        !initial.cancel_requested() else {
        raise Invalid("native.reply.shape")
      }
      value
    }
    "job.query" | "job.cancel" => {
      ignore(receipt(value, expected_session))
      value
    }
    "job.release" => {
      let fields = closed(value, ["released"])
      guard fields["released"] == Json::boolean(true) else {
        raise Invalid("native.reply.shape")
      }
      value
    }
    "workspace.choose" => {
      guard value is Object(fields) else { raise Invalid("native.reply.shape") }
      if fields.get("cancelled") == Some(Json::boolean(true)) {
        ignore(closed(value, ["cancelled"]))
      } else {
        ignore(closed(value, ["cancelled", "grantId", "projects", "warnings"]))
        guard fields["cancelled"] == Json::boolean(false) &&
          fields["projects"] is Array(projects) &&
          projects.length() <= 128 &&
          fields["warnings"] is Array(warnings) &&
          warnings.length() <= 128 else {
          raise Invalid("native.reply.shape")
        }
        ignore(token(fields["grantId"]))
        let ids : Map[String, Bool] = Map([])
        for project in projects {
          let fields = closed(project, ["id", "name", "available", "message"])
          let id = token(fields["id"])
          guard !ids.contains(id) else { raise Invalid("native.reply.shape") }
          ids[id] = true
          ignore(text(fields["name"], 1, 1024))
          ignore(text(fields["message"], 0, 1024))
          boolean(fields["available"])
        }
        for warning in warnings {
          ignore(text(warning, 0, 1024))
        }
      }
      value
    }
    "workspace.open" => {
      let fields = closed(value, ["sequence", "size", "format", "filename"])
      integer(fields["sequence"], 1, 2147483647)
      integer(fields["size"], 0, 16777216)
      guard [
        Json::string("morphir-json"),
        Json::string("ion-text"),
        Json::string("ion-binary"),
      ].contains(fields["format"]) else {
        raise Invalid("native.reply.shape")
      }
      let filename = text(fields["filename"], 1, 256)
      guard !filename.contains("/") && !filename.contains("\\") else {
        raise Invalid("native.reply.shape")
      }
      value
    }
    "workspace.read" => {
      let fields = closed(value, ["sequence", "offset", "content", "done"])
      integer(fields["sequence"], 1, 2147483647)
      integer(fields["offset"], 0, 16777216)
      boolean(fields["done"])
      let content = text(fields["content"], 0, 262144)
      let decoded = @base64.decode(content[:])
      guard decoded.length() <= 196608 &&
        (!decoded.is_empty() || fields["done"] == Json::boolean(true)) &&
        @base64.encode(decoded[:]) == content else {
        raise Invalid("native.reply.shape")
      }
      value
    }
    _ => raise Invalid("native.reply.operation")
  }
}

///|
fn known(operation : String) -> Bool {
  [
    "session.open", "session.check", "session.close", "job.submit", "job.query",
    "job.cancel", "job.release", "workspace.choose", "workspace.cancel-picker", "workspace.revoke",
    "workspace.open", "workspace.read", "workspace.release",
  ].contains(operation)
}

///|
/// The binding correlates concurrent invocations, including equal operations.
/// This decoder checks the operation captured by that exact originating call.
pub fn decode(
  bytes : Bytes,
  expected_operation : String,
  expected_session~ : String? = None,
) -> Reply raise Invalid {
  guard known(expected_operation) else {
    raise Invalid("native.reply.operation")
  }
  if expected_operation == "workspace.choose" && bytes.length() > 524288 {
    raise Invalid("native.reply.limit")
  }
  let value = parse(bytes)
  guard value is Object(fields) else { raise Invalid("native.reply.shape") }
  if fields.get("ok") == Some(Json::boolean(true)) {
    ignore(closed(value, ["ok", "operation", "value"]))
    guard fields["operation"] == Json::string(expected_operation) else {
      raise Invalid("native.reply.operation")
    }
    fields["value"] = payload(
      expected_operation,
      fields["value"],
      expected_session,
    ) catch {
      Invalid(code) => raise Invalid(code)
      _ => raise Invalid("native.reply.shape")
    }
    { envelope: value, effect: None, }
  } else {
    ignore(closed(value, ["ok", "error"]))
    guard fields["ok"] == Json::boolean(false) else {
      raise Invalid("native.reply.shape")
    }
    let error = closed(fields["error"], ["code", "effect", "message"])
    guard [
      Json::string("invalid_request"),
      Json::string("unauthorized"),
      Json::string("unavailable"),
      Json::string("not_found"),
      Json::string("conflict"),
      Json::string("limit"),
    ].contains(error["code"]) else {
      raise Invalid("native.reply.shape")
    }
    ignore(text(error["message"], 1, 512))
    let effect = match error["effect"] {
      String("none") => NoEffect
      String("unknown") => UnknownEffect
      _ => raise Invalid("native.reply.shape")
    }
    { envelope: value, effect: Some(effect), }
  }
}

///|
/// Reserve the complete wrapper before publication. A failure here does not
/// establish whether an earlier owner action took effect.
pub fn success(operation : String, value : Json) -> Bytes raise Invalid {
  let bytes = @utf8.encode(
    ({ "ok": true, "operation": operation, "value": value } : Json).stringify(),
  )
  ignore(decode(bytes, operation))
  bytes
}

///|
/// Fixed public messages omit internal errors, paths, source and worker stderr.
/// The owner chooses the effect from its actual admission/execution boundary.
pub fn failure(code : Code, effect : Effect) -> Bytes {
  let (code, message) = match code {
    InvalidRequest => ("invalid_request", "The native request is invalid.")
    Unauthorized =>
      ("unauthorized", "The native page or session is no longer authorized.")
    Unavailable => ("unavailable", "The native operation is unavailable.")
    NotFound => ("not_found", "The native resource was not found.")
    Conflict =>
      ("conflict", "The native request conflicts with the current state.")
    Limit => ("limit", "The native request exceeds a supported limit.")
  }
  @utf8.encode(
    (
      {
        "ok": false,
        "error": {
          "code": code,
          "effect": match effect {
            NoEffect => "none"
            UnknownEffect => "unknown"
          },
          "message": message,
        },
      } : Json).stringify(),
  )
}
