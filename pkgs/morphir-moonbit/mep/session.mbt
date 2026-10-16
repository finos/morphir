///|
priv enum Lifecycle {
  BeforeInitialize
  Ready
  Shutdown
  Exited
}

///|
pub struct Session {
  priv mut lifecycle : Lifecycle
}

///|
pub fn Session::new() -> Session {
  { lifecycle: BeforeInitialize, }
}

///|
pub fn Session::exited(self : Session) -> Bool {
  self.lifecycle is Exited
}

///|
fn info() -> Json {
  {
    "id": "morphir-moonbit",
    "name": "Morphir MoonBit",
    "version": "0.1.0",
    "types": ["backend"],
    "license": "Apache-2.0",
  }
}

///|
fn capabilities() -> Json {
  {
    "backend": { "targets": ["moonbit"], "irVersions": ["4"], "generate": true },
    "streaming": false,
    "incremental": false,
    "cancellation": false,
    "progress": false,
  }
}

///|
fn result(id : Json, value : Json) -> Json {
  { "jsonrpc": "2.0", "id": id, "result": value }
}

///|
fn rpc_error(id : Json, code : Int32, message : String) -> Json {
  { "jsonrpc": "2.0", "id": id, "error": { "code": code, "message": message } }
}

///|
fn field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn negotiation(params : Json, initialize~ : Bool = false) -> Int32? {
  guard params is Object(_) &&
    field(params, "protocolVersions") is Array(versions) &&
    !versions.is_empty() else {
    return Some(-32602)
  }
  for version in versions {
    guard version is String(_) else { return Some(-32602) }
  }
  if initialize {
    let host = field(params, "host")
    guard field(host, "name") is String(name) &&
      !name.is_empty() &&
      field(host, "version") is String(version) &&
      !version.is_empty() else {
      return Some(-32602)
    }
  }
  if versions.contains(Json::string("0.1")) {
    None
  } else {
    Some(-32011)
  }
}

///|
/// Parse errors preserve the session and always produce a JSON-RPC error.
pub fn Session::receive(self : Session, body : Bytes) -> Json? {
  let request = @wire.parse_bounded(
    @utf8.decode(body[:]),
    max_depth=256,
    max_nodes=200000,
    max_string_units=8388608,
  ) catch {
    _ => return Some(rpc_error(Json::null(), -32700, "Invalid UTF-8 or JSON"))
  }
  self.handle(request)
}

///|
pub fn Session::handle(self : Session, request : Json) -> Json? {
  guard request is Object(fields) &&
    field(request, "jsonrpc") == Json::string("2.0") &&
    field(request, "method") is String(operation) else {
    return Some(rpc_error(Json::null(), -32600, "Invalid JSON-RPC request"))
  }
  guard fields.get("id") is Some(id) else {
    if operation == "morphir.exit" {
      self.lifecycle = Exited
    }
    // Notifications, including initialized, never generate a response.
    return None
  }
  let valid_id = try {
    ignore(@strconv.parse_uint64(@wire.integer_text(id)))
    true
  } catch {
    _ => false
  }
  guard valid_id else {
    return Some(
      rpc_error(
        Json::null(),
        -32600,
        "MEP request ID must be an unsigned integer",
      ),
    )
  }
  if operation == "morphir.exit" {
    return Some(rpc_error(id, -32600, "morphir.exit must be a notification"))
  }
  match self.lifecycle {
    Exited | Shutdown =>
      return Some(rpc_error(id, -32014, "Session has shut down"))
    BeforeInitialize =>
      if !["morphir.initialize", "morphir.extension.describe", "morphir.ping"].contains(
          operation,
        ) {
        return Some(rpc_error(id, -32014, "Initialize the extension first"))
      }
    Ready =>
      if operation == "morphir.initialize" {
        return Some(rpc_error(id, -32600, "Extension is already initialized"))
      }
  }
  let params = fields.get("params").unwrap_or(Json::object({}))
  if !(params is Object(_)) {
    return Some(rpc_error(id, -32602, "Object parameters required"))
  }
  Some(
    match operation {
      "morphir.extension.describe" | "morphir.initialize" =>
        match
          negotiation(params, initialize=operation == "morphir.initialize") {
          Some(code) =>
            rpc_error(
              id, code, "Invalid negotiation parameters or unsupported MEP version",
            )
          None =>
            if operation == "morphir.extension.describe" {
              result(id, {
                "claimsVersion": "0.1.0-draft.2",
                "protocolVersions": ["0.1"],
                "extension": info(),
                "capabilities": capabilities(),
              })
            } else {
              self.lifecycle = Ready
              result(id, {
                "protocolVersion": "0.1",
                "extension": info(),
                "capabilities": capabilities(),
              })
            }
        }
      "morphir.ping" => result(id, { "ok": true })
      "morphir.extension.info" => result(id, info())
      "morphir.extension.capabilities" => result(id, capabilities())
      "morphir.shutdown" => {
        self.lifecycle = Shutdown
        result(id, Json::object({}))
      }
      "morphir.backend.generate" => generate(id, params)
      _ => rpc_error(id, -32601, "Unknown MEP operation")
    },
  )
}

///|
fn generation_failure(code : String, message : String) -> Json {
  {
    "success": false,
    "artifacts": [],
    "diagnostics": [{ "severity": "error", "code": code, "message": message }],
  }
}

///|
fn generate(id : Json, params : Json) -> Json {
  if field(params, "target") != Json::string("moonbit") {
    return rpc_error(id, -32602, "Expected target moonbit")
  }
  let options = match params {
    Object(fields) => fields.get("options").unwrap_or(Json::object({}))
    _ => Json::null()
  }
  guard options is Object(fields) && fields.is_empty() else {
    return rpc_error(id, -32602, "This backend accepts no generation options")
  }
  @wire.fields(params, ["ir", "target", "options"]) catch {
    _ => return rpc_error(id, -32602, "Unknown generation parameter")
  }
  guard params is Object(members) && members.contains("ir") else {
    return rpc_error(id, -32602, "Missing ir parameter")
  }
  let output = try {
    let ir = @ir_json.from_json(@wire.field(params, "ir"))
    @generator.generate(@generator.Input::new("mep", ir))
  } catch {
    @generator.Invalid(code, context, message) =>
      return result(id, generation_failure(code, context + ": " + message))
    @wire.Invalid(code, detail) =>
      return result(
        id,
        generation_failure("moonbit.invalid_ir." + code, detail),
      )
    error =>
      return result(
        id,
        generation_failure("moonbit.invalid_ir", error.to_string()),
      )
  }
  let artifacts = []
  for artifact in output.artifacts {
    let (content, binary) = match artifact.content {
      Text(text) => (text, false)
      Binary(bytes) => (@base64.encode(bytes[:]), true)
    }
    artifacts.push(
      ({ "path": artifact.path, "content": content, "binary": binary } : Json),
    )
  }
  let diagnostics = output.warnings.map(warning => {
    (
      {
        "severity": "warning",
        "code": warning.code,
        "message": warning.message + " Fix: " + warning.fix,
      } : Json)
  })
  result(id, {
    "success": true,
    "artifacts": Json::array(artifacts),
    "diagnostics": Json::array(diagnostics),
  })
}
