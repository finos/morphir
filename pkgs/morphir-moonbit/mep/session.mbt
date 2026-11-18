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
  priv mut models : ModelTransport?
  priv metadata_capabilities : @linked_metadata.Capabilities
  priv frontend : Frontend?
  priv cancelled : () -> Bool
  priv bounded : BoundedBackend?
  priv mut bounded_activation : BoundedActivation
  priv mut generation : GuestGeneration?
  priv used_generation_ids : Array[String]
}

///|
/// Capabilities come from the embedding host, never from a MEP request. The
/// native stdio adapter leaves them unavailable until authenticated integration.
pub fn Session::new(
  metadata_capabilities~ : @linked_metadata.Capabilities = @linked_metadata.Capabilities::unavailable(),
  frontend~ : Frontend? = None,
  cancelled~ : () -> Bool = fn() { false },
  bounded~ : BoundedBackend? = None,
) -> Session {
  let bounded = match bounded {
    Some(backend) if !backend.support.tuples().is_empty() => bounded
    _ => None
  }
  {
    lifecycle: BeforeInitialize,
    models: None,
    metadata_capabilities,
    frontend,
    cancelled,
    bounded,
    bounded_activation: BoundedInactive,
    generation: None,
    used_generation_ids: [],
  }
}

///|
pub fn Session::exited(self : Session) -> Bool {
  self.lifecycle is Exited
}

///|
fn Session::info(self : Session) -> Json {
  {
    "id": "morphir-moonbit",
    "name": "Morphir MoonBit",
    "version": "0.1.0",
    "types": if self.frontend is Some(_) {
      ["frontend", "backend"]
    } else {
      ["backend"]
    },
    "license": "Apache-2.0",
  }
}

///|
fn Session::capabilities(
  self : Session,
  models : ModelTransport?,
  access~ : @model_access.Support? = None,
  bounded_line~ : Bool = false,
) -> Json {
  let value : Json = {
    "backend": {
      "targets": ["moonbit"],
      "irVersions": ["4"],
      "generate": !bounded_line,
    },
    "streaming": false,
    "incremental": false,
    "cancellation": false,
    "progress": false,
  }
  if access is Some(support) && value is Object(fields) {
    fields["modelAccess"] = support.to_json()
  }
  if models is Some(support) && value is Object(fields) {
    fields["modelTransport"] = support.to_json()
  }
  if self.frontend is Some(frontend) && value is Object(fields) {
    fields["frontend"] = {
      "languages": [
        {
          "id": frontend.language_id,
          "fileExtensions": frontend.file_extensions,
        },
      ],
      "irVersions": ["4.0.0"],
      "compile": false,
      "incremental": false,
      "fragments": false,
    }
    // Root capability extras survive the typed SDK; nested frontend extras do
    // not. Keep this vendor profile vocabulary out of the canonical record.
    fields["moonbitFrontendProfiles"] = Json(frontend.profiles)
  }
  value
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
fn negotiation(
  params : Json,
  initialize~ : Bool = false,
  bounded~ : Bool = false,
) -> Int32? {
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
  if versions.contains(Json::string("0.1")) ||
    versions.contains(Json::string(MODEL_PROTOCOL)) ||
    (bounded && versions.contains(Json::string(@model_access.PROTOCOL))) {
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
      self.release_generation()
    } else if operation == "morphir.initialized" &&
      self.lifecycle is Ready &&
      self.bounded_activation is BoundedWaiting(agreed) {
      self.bounded_activation = BoundedReady(agreed)
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
  let bounded_method = operation == @model_access.START ||
    operation == @model_access.ADVANCE ||
    operation == @model_access.CANCEL
  match self.lifecycle {
    Exited | Shutdown =>
      return Some(rpc_error(id, -32014, "Session has shut down"))
    BeforeInitialize =>
      if !bounded_method &&
        !["morphir.initialize", "morphir.extension.describe", "morphir.ping"].contains(
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
  if bounded_method {
    return Some(self.bounded_message(id, operation, params))
  }
  if !(params is Object(_)) {
    return Some(rpc_error(id, -32602, "Object parameters required"))
  }
  Some(
    match operation {
      "morphir.extension.describe" | "morphir.initialize" =>
        match
          negotiation(
            params,
            initialize=operation == "morphir.initialize",
            bounded=self.bounded is Some(_),
          ) {
          Some(code) =>
            rpc_error(
              id, code, "Invalid negotiation parameters or unsupported MEP version",
            )
          None =>
            if operation == "morphir.extension.describe" {
              result(id, {
                "claimsVersion": "0.1.0-draft.2",
                "protocolVersions": if self.bounded is Some(_) {
                  [@model_access.PROTOCOL, MODEL_PROTOCOL, "0.1"]
                } else {
                  [MODEL_PROTOCOL, "0.1"]
                },
                "extension": self.info(),
                "capabilities": self.capabilities(
                  Some(model_support(frontend=self.frontend is Some(_))),
                  access=self.bounded.map(backend => backend.support),
                ),
              })
            } else if self.bounded is Some(backend) &&
              field(params, "protocolVersions") is Array(versions) &&
              versions.contains(Json::string(@model_access.PROTOCOL)) {
              let agreement = if params is Object(fields) &&
                fields.get("modelAccess") is Some(offer) {
                let host = @model_access.Support::from_json(offer) catch {
                  _ =>
                    return Some(
                      rpc_error(
                        id, -32602, "Invalid bounded model access offer",
                      ),
                    )
                }
                let chosen = host.intersect(backend.support)
                if chosen.tuples().is_empty() {
                  None
                } else {
                  Some(chosen)
                }
              } else {
                None
              }
              self.bounded_activation = BoundedWaiting(agreement)
              self.lifecycle = Ready
              result(id, {
                "protocolVersion": @model_access.PROTOCOL,
                "extension": self.info(),
                "capabilities": self.capabilities(
                  None,
                  access=agreement,
                  bounded_line=true,
                ),
              })
            } else {
              let versions = field(params, "protocolVersions")
              let has_offer = params is Object(fields) &&
                fields.contains("modelTransport")
              let rich = versions is Array(items) &&
                items.contains(Json::string(MODEL_PROTOCOL)) &&
                has_offer
              let models = if rich {
                Some(
                  select_models(
                    field(params, "modelTransport"),
                    frontend=self.frontend is Some(_),
                  ) catch {
                    _ =>
                      return Some(
                        rpc_error(id, -32602, "Invalid model transport offer"),
                      )
                  },
                )
              } else {
                guard versions is Array(items) &&
                  items.contains(Json::string("0.1")) else {
                  return Some(
                    rpc_error(
                      id, -32011, "Rich initialization requires a model transport offer",
                    ),
                  )
                }
                None
              }
              self.models = models
              self.lifecycle = Ready
              result(id, {
                "protocolVersion": if rich {
                  MODEL_PROTOCOL
                } else {
                  "0.1"
                },
                "extension": self.info(),
                "capabilities": self.capabilities(models),
              })
            }
        }
      "morphir.ping" => result(id, { "ok": true })
      "morphir.extension.info" => result(id, self.info())
      "morphir.extension.capabilities" =>
        match self.bounded_activation {
          BoundedInactive => result(id, self.capabilities(self.models))
          BoundedWaiting(agreed) | BoundedReady(agreed) =>
            result(
              id,
              self.capabilities(None, access=agreed, bounded_line=true),
            )
        }
      "morphir.shutdown" => {
        self.lifecycle = Shutdown
        self.release_generation()
        result(id, Json::object({}))
      }
      _ if !(self.bounded_activation is BoundedInactive) &&
        [
          "morphir.backend.generate", "morphir.backend.generateModel", "morphir.frontend.compileModel",
        ].contains(operation) =>
        rpc_error(
          id, -32013, "The bounded session does not admit whole-model methods",
        )
      "morphir.backend.generate" => generate(id, params)
      "morphir.backend.generateModel" => self.generate_model(id, params)
      "morphir.frontend.compileModel" => self.compile_model(id, params)
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
  generation_result(id, output, artifacts)
}

///|
fn generation_result(
  id : Json,
  output : @generator.Output,
  artifacts : Array[Json],
) -> Json {
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
