///|
pub(all) enum Failure {
  Denied(String, String)
  Uncertain(String, String)
}

///|
pub struct Reply {
  priv value : Json
}

///|
pub fn Reply::to_json(self : Reply) -> Json {
  self.value
}

///|
fn session_value(value : Json) -> SessionId raise Invalid {
  SessionId::parse(text(value, 128))
}

///|
fn correlate_sequence(
  fields : Map[String, Json],
  sequence : Int32,
) -> Unit raise Invalid {
  if integer(fields.get("sequence").unwrap_or(Json::null()), 1, 2147483647) !=
    sequence {
    raise Invalid("workspace_files.sequence")
  }
}

///|
fn validate_value(request : Request, value : Json) -> Unit raise Invalid {
  match request {
    OpenSession | Bound(_, CheckSession) =>
      if value != descriptor() {
        raise Invalid("workspace_files.descriptor")
      }
    Bound(_, ChooseWrite) => {
      guard value is Object(fields) else {
        raise Invalid("workspace_files.shape")
      }
      if fields.get("cancelled") == Some(Json::boolean(true)) {
        ignore(closed(value, ["cancelled"]))
      } else {
        ignore(closed(value, ["cancelled", "grantId", "revision", "name"]))
        if fields["cancelled"] != Json::boolean(false) {
          raise Invalid("workspace_files.shape")
        }
        ignore(GrantId::parse(text(fields["grantId"], 128)))
        ignore(integer(fields["revision"], 0, 2147483647))
        let name = text(fields["name"], 1024)
        if name == "" || name.iter().any(c => c < ' ' || c == '\u007f') {
          raise Invalid("workspace_files.shape")
        }
      }
    }
    Bound(_, Snapshot(_, sequence)) => {
      let fields = closed(value, ["sequence", "size", "revision"])
      correlate_sequence(fields, sequence)
      ignore(integer(fields["size"], 1, TRANSFER_LIMIT))
      ignore(integer(fields["revision"], 0, 2147483647))
    }
    Bound(_, Read(_, sequence, offset)) => {
      let fields = closed(value, ["sequence", "offset", "content", "done"])
      correlate_sequence(fields, sequence)
      if integer(fields["offset"], 0, TRANSFER_LIMIT) != offset {
        raise Invalid("workspace_files.offset")
      }
      let bytes = chunk(fields["content"])
      guard fields["done"] is True || fields["done"] is False else {
        raise Invalid("workspace_files.shape")
      }
      if bytes.is_empty() ||
        offset > TRANSFER_LIMIT - bytes.length() ||
        (
          fields["done"] == Json::boolean(false) &&
          bytes.length() != CHUNK_LIMIT
        ) {
        raise Invalid("workspace_files.shape")
      }
    }
    Bound(_, BeginEdit(_, sequence, _, _)) => {
      let fields = closed(value, ["sequence", "offset"])
      correlate_sequence(fields, sequence)
      if fields["offset"] != Json::number(0) {
        raise Invalid("workspace_files.offset")
      }
    }
    Bound(_, Write(_, sequence, offset, bytes)) => {
      let fields = closed(value, ["sequence", "offset"])
      correlate_sequence(fields, sequence)
      if integer(fields["offset"], 1, TRANSFER_LIMIT) != offset + bytes.length() {
        raise Invalid("workspace_files.offset")
      }
    }
    Bound(_, Commit(_, sequence)) => {
      let fields = closed(value, ["sequence", "revision"])
      correlate_sequence(fields, sequence)
      ignore(integer(fields["revision"], 1, 2147483647))
    }
    Bound(_, Status(_, sequence)) => {
      guard value is Object(fields) else {
        raise Invalid("workspace_files.shape")
      }
      correlate_sequence(fields, sequence)
      match fields.get("state") {
        Some(String("idle")) => ignore(closed(value, ["sequence", "state"]))
        Some(String("uploading")) => {
          ignore(closed(value, ["sequence", "state", "offset", "size"]))
          let size = integer(fields["size"], 1, TRANSFER_LIMIT)
          ignore(integer(fields["offset"], 0, size))
        }
        Some(String("committed")) => {
          ignore(closed(value, ["sequence", "state", "revision"]))
          ignore(integer(fields["revision"], 1, 2147483647))
        }
        Some(String("failed")) => {
          ignore(closed(value, ["sequence", "state", "error"]))
          validate_failure(fields["error"])
        }
        _ => raise Invalid("workspace_files.shape")
      }
    }
    Bound(_, CloseSession | CancelPicker | Release(_, _) | Revoke(_)) =>
      ignore(closed(value, []))
  }
}

///|
fn validate_failure(value : Json) -> Unit raise Invalid {
  let fields = closed(value, ["code", "message", "effect"])
  if !valid_id(text(fields["code"], 128)) {
    raise Invalid("workspace_files.shape")
  }
  ignore(text(fields["message"], 2048))
  if fields["effect"] != Json::string("none") &&
    fields["effect"] != Json::string("unknown") {
    raise Invalid("workspace_files.shape")
  }
}

///|
/// Replies bind to the exact originating request, session and transfer offset.
/// This validates a claim; only the native owner grants filesystem access.
pub fn decode_reply(request : Request, bytes : Bytes) -> Reply raise Invalid {
  let value = parse(bytes)
  guard value is Object(fields) &&
    fields.get("profile") == Some(Json::string(PROFILE)) &&
    fields.get("contractVersion") == Some(Json::string(VERSION)) &&
    fields.get("operation") == Some(Json::string(request.operation())) else {
    raise Invalid("workspace_files.profile")
  }
  let success = fields.get("ok") == Some(Json::boolean(true))
  if !success && fields.get("ok") != Some(Json::boolean(false)) {
    raise Invalid("workspace_files.shape")
  }
  ignore(
    closed(
      value,
      if success {
        ["profile", "contractVersion", "operation", "sessionId", "ok", "value"]
      } else {
        ["profile", "contractVersion", "operation", "sessionId", "ok", "error"]
      },
    ),
  )
  match request.session_id() {
    Some(expected) =>
      if session_value(fields["sessionId"]) != expected {
        raise Invalid("workspace_files.session")
      }
    None =>
      if success {
        ignore(session_value(fields["sessionId"]))
      } else if fields["sessionId"] != Json::null() {
        raise Invalid("workspace_files.session")
      }
  }
  if success {
    validate_value(request, fields["value"])
  } else {
    validate_failure(fields["error"])
  }
  { value, }
}

///|
pub fn success(
  request : Request,
  session : SessionId,
  value : Json,
) -> Bytes raise Invalid {
  let bytes = @utf8.encode(
    (
      {
        "profile": PROFILE,
        "contractVersion": VERSION,
        "operation": request.operation(),
        "sessionId": session.to_string(),
        "ok": true,
        "value": value,
      } : Json).stringify(),
  )
  ignore(decode_reply(request, bytes))
  bytes
}

///|
pub fn failure(request : Request, reason : Failure) -> Bytes raise Invalid {
  let (code, message, effect) = match reason {
    Denied(code, message) => (code, message, "none")
    Uncertain(code, message) => (code, message, "unknown")
  }
  let bytes = @utf8.encode(
    (
      {
        "profile": PROFILE,
        "contractVersion": VERSION,
        "operation": request.operation(),
        "sessionId": request
        .session_id()
        .map(id => Json::string(id.to_string()))
        .unwrap_or(Json::null()),
        "ok": false,
        "error": { "code": code, "message": message, "effect": effect },
      } : Json).stringify(),
  )
  ignore(decode_reply(request, bytes))
  bytes
}
