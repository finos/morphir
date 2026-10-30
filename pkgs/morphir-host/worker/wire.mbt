///|
let host_name : String = "morphir-moonbit-cli"

///|
let host_version : String = "0.1.0"

///|
fn request_message(
  id : Int32,
  method_name : String,
  params : Map[String, Json],
) -> Message {
  Message::new({
    "jsonrpc": "2.0",
    "id": id,
    "method": method_name,
    "params": Json::object(params),
  })
}

///|
fn notification_message(method_name : String) -> Message {
  Message::new({ "jsonrpc": "2.0", "method": method_name })
}

///|
/// A probe offers both protocol lines, so that legacy and model guests both
/// describe themselves.
fn describe_message(id : Int32) -> Message {
  request_message(id, "morphir.extension.describe", {
    "protocolVersions": [
      ProtocolLine::Mep0_2Draft1.to_string(),
      ProtocolLine::Mep0_1.to_string(),
    ],
  })
}

///|
fn initialize_message(id : Int32, offer : Offer, limits : Limits) -> Message {
  let params : Map[String, Json] = {
    "protocolVersions": [offer.line().to_string()],
    "host": { "name": host_name, "version": host_version },
  }
  if offer is Model(tuple) {
    params["modelTransport"] = {
      "tuples": [tuple.to_json()],
      "limits": limits.model.to_json(),
      "guarantees": [],
    }
  }
  request_message(id, "morphir.initialize", params)
}

///|
fn shutdown_message(id : Int32) -> Message {
  request_message(id, "morphir.shutdown", {})
}

///|
/// One checked reply to the pending request.
priv enum Reply {
  Answer(Json)
  GuestError(code~ : Int32, message~ : String, data~ : Json?)
}

///|
fn integer(value : Json?) -> Int32? {
  guard value is Some(Number(number, ..)) &&
    number == number.floor() &&
    number >= -2147483648.0 &&
    number <= 2147483647.0 else {
    return None
  }
  Some(number.to_int())
}

///|
/// Checks one message from the worker against the pending request: its size
/// first, then its ID and its shape. A notification is `None`, which the host
/// skips.
fn read_reply(
  message : Message,
  pending~ : Int32,
  answered~ : Array[Int32],
  limit~ : Int32,
) -> Result[Reply?, Fault] {
  guard message.size() <= limit else {
    return Err(
      Host(
        code=ResponseLimit,
        message="a response has \{message.size()} bytes; the limit is \{limit}",
      ),
    )
  }
  guard message.json() is Object(fields) &&
    fields.get("jsonrpc") == Some(Json::string("2.0")) else {
    return Err(
      Host(code=UnexpectedResponse, message="the reply is not JSON-RPC 2.0"),
    )
  }
  if fields.get("method") is Some(_) {
    guard fields.get("id") is None else {
      return Err(
        Host(
          code=UnexpectedResponse,
          message="the worker sent a request to the host",
        ),
      )
    }
    return Ok(None)
  }
  guard integer(fields.get("id")) is Some(id) else {
    return Err(
      Host(code=UnexpectedResponse, message="the reply has no request ID"),
    )
  }
  guard id == pending else {
    return Err(
      Host(
        code=UnexpectedResponse,
        message=if answered.contains(id) {
          "a second response to request \{id}"
        } else if id > pending {
          "a response with ID \{id} to request \{pending}"
        } else {
          "an unsolicited response with ID \{id}"
        },
      ),
    )
  }
  match (fields.get("result"), fields.get("error")) {
    (Some(result), None) => Ok(Some(Answer(result)))
    (None, Some(Object(error))) =>
      match (integer(error.get("code")), error.get("message")) {
        (Some(code), Some(String(text))) =>
          Ok(Some(GuestError(code~, message=text, data=error.get("data"))))
        _ =>
          return Err(
            Host(
              code=UnexpectedResponse,
              message="the error of request \{id} has no code or message",
            ),
          )
      }
    _ =>
      return Err(
        Host(
          code=UnexpectedResponse,
          message="the reply to request \{id} must have exactly one of result or error",
        ),
      )
  }
}

///|
fn field_at(value : Json, path : ArrayView[String]) -> Json? {
  match path {
    [] => Some(value)
    [name, .. rest] =>
      match value {
        Object(fields) => fields.get(name).bind(next => field_at(next, rest))
        _ => None
      }
  }
}

///|
fn texts(value : Json?, name : String) -> Array[String] raise ValueError {
  match value {
    None => []
    Some(Array(items)) =>
      items.map(item => {
        guard item is String(text) else {
          raise InvalidClaim("\{name} has an item that is not text")
        }
        text
      })
    Some(_) => raise InvalidClaim("\{name} is not a list")
  }
}

///|
fn flag(value : Json?) -> Bool {
  value is Some(True)
}

///|
/// Reads the tuples of a worker's model transport. A tuple whose parts are
/// all text but outside the host's closed sets is skipped: the host cannot use
/// it. A tuple with a missing or non-text part is malformed.
fn read_tuples(transport : Json?) -> Array[ModelTuple] raise ValueError {
  guard transport is Some(transport) else { return [] }
  guard field_at(transport, ["tuples"]) is Some(Array(items)) else {
    raise InvalidClaim("modelTransport has no tuples")
  }
  let tuples = []
  for item in items {
    let parts = [
      "operation", "profile", "codec", "envelopeVersion", "irVersion",
    ].map(name => {
      guard field_at(item, [name]) is Some(String(text)) else {
        raise InvalidClaim("a model tuple has no \{name}")
      }
      text
    })
    let tuple = ModelTuple::parse(
      parts[0],
      parts[1],
      parts[2],
      parts[3],
      parts[4],
    ) catch {
      UnknownModelTuplePart(_) => continue
      error => raise error
    }
    tuples.push(tuple)
  }
  tuples
}

///|
fn read_model_limits(transport : Json?) -> ModelLimits raise ValueError {
  let read = (name : String) => {
    guard transport is Some(transport) &&
      integer(field_at(transport, ["limits", name])) is Some(value) else {
      raise InvalidLimit("modelTransport has no \{name}")
    }
    value
  }
  ModelLimits::new(
    encoded_bytes=read("maxEncodedBytes"),
    decoded_bytes=read("maxDecodedBytes"),
    depth=read("maxDepth"),
    nodes=read("maxNodes"),
  )
}

///|
fn read_ir_versions(
  value : Json?,
  name : String,
) -> Array[IrVersionName] raise ValueError {
  texts(value, name).map(IrVersionName::parse)
}

///|
/// The member paths of a claim set that the host reads. A claim set whose
/// `critical` member names another path is refused, as the MEP model
/// requires.
let understood_paths : Array[String] = [
  "protocolVersions", "protocolVersion", "extension", "extension.id", "extension.version",
  "capabilities", "capabilities.frontend", "capabilities.frontend.languages", "capabilities.frontend.irVersions",
  "capabilities.frontend.compile", "capabilities.backend", "capabilities.backend.targets",
  "capabilities.backend.irVersions", "capabilities.backend.generate", "capabilities.modelTransport",
  "capabilities.modelTransport.tuples", "capabilities.modelTransport.limits", "critical",
]

///|
/// Decodes claims from a describe result or an initialize result. A describe
/// result lists `protocolVersions`; an initialize result has the one
/// `protocolVersion` the worker selected. Versions the host does not offer
/// are left out.
fn read_claims(result : Json) -> Claims raise ValueError {
  let text = (path : ArrayView[String]) => {
    guard field_at(result, path) is Some(String(text)) else {
      raise InvalidClaim("\{path.join(".")} is not text")
    }
    text
  }
  for path in texts(field_at(result, ["critical"]), "critical") {
    guard understood_paths.contains(path) else {
      raise InvalidClaim("critical names \{path}, which the host does not read")
    }
  }
  let versions = match field_at(result, ["protocolVersion"]) {
    Some(String(version)) => [version]
    _ => texts(field_at(result, ["protocolVersions"]), "protocolVersions")
  }
  let protocol_lines = versions.filter_map(version => {
    try ProtocolLine::parse(version) catch {
      _ => None
    } noraise {
      line => Some(line)
    }
  })
  let capabilities = field_at(result, ["capabilities"])
  guard capabilities is Some(Object(_)) else {
    raise InvalidClaim("capabilities is not an object")
  }
  let frontend = field_at(result, ["capabilities", "frontend"])
  let backend = field_at(result, ["capabilities", "backend"])
  let transport = field_at(result, ["capabilities", "modelTransport"])
  let model_tuples = read_tuples(transport)
  let operations : Array[Operation] = []
  if flag(field_at(result, ["capabilities", "frontend", "compile"])) {
    operations.push(Compile)
  }
  if flag(field_at(result, ["capabilities", "backend", "generate"])) {
    operations.push(Generate)
  }
  for tuple in model_tuples {
    operations.push(tuple.operation.operation())
  }
  let languages = match
    field_at(result, ["capabilities", "frontend", "languages"]) {
    None => []
    Some(Array(items)) =>
      items.map(item => {
        guard field_at(item, ["id"]) is Some(String(id)) else {
          raise InvalidClaim("a language has no id")
        }
        let extensions = texts(
          field_at(item, ["fileExtensions"]),
          "fileExtensions",
        )
        LanguageClaim::new(
          @ids.LanguageId::parse(id),
          extensions.map(@ids.FileExtension::parse),
        ) catch {
          EmptyLanguageClaim(_) as error => raise error
          _ => raise InvalidClaim("invalid language \{id} or file extension")
        }
      })
    Some(_) => raise InvalidClaim("languages is not a list")
  }
  let targets = texts(
    field_at(result, ["capabilities", "backend", "targets"]),
    "targets",
  ).map(target => {
    @ids.BackendId::parse(target) catch {
      _ => raise InvalidClaim("invalid target \{target}")
    }
  })
  Claims::new(
    ExtensionId::parse(text(["extension", "id"])),
    ExtensionVersion::parse(text(["extension", "version"])),
    protocol_lines~,
    operations~,
    languages~,
    frontend_ir_versions=read_ir_versions(
      frontend.bind(value => field_at(value, ["irVersions"])),
      "frontend irVersions",
    ),
    targets~,
    backend_ir_versions=read_ir_versions(
      backend.bind(value => field_at(value, ["irVersions"])),
      "backend irVersions",
    ),
    model_tuples~,
  )
}

///|
/// Decodes the claims in a describe result.
pub fn Claims::from_describe(result : Json) -> Claims raise ValueError {
  read_claims(result)
}

///|
fn[T : Show + Eq] missing(
  name : String,
  expected : Array[T],
  live : Array[T],
) -> String? {
  let lost = expected.filter(value => !live.contains(value))
  guard !lost.is_empty() else { return None }
  Some("\{name} \{lost.map(value => Show::to_string(value)).join(", ")}")
}

///|
/// Compares the claims of a live worker with the claims recorded for it,
/// within the protocol line of the offer. The extension ID and version always
/// count. Each line then counts only what it carries:
///
/// - MEP 0.1 (`Legacy`): the legacy operations, the languages with their file
///   extensions, the targets, and the frontend and backend IR versions. The
///   recorded model tuples do not count.
/// - MEP 0.2.0-draft.1 (`Model`): the languages with their file extensions
///   for a compileModel tuple, and the targets for a generateModel tuple. The
///   legacy operations and the IR versions do not count. The offered tuple is
///   checked separately; the worker leaves out the tuples that were not
///   offered.
///
/// Drift is a recorded entry that is missing or changed in the live claims.
fn compare_claims(expected : Claims, live : Claims, offer : Offer) -> String? {
  if expected.extension_id != live.extension_id {
    return Some(
      "extension ID \{live.extension_id}, recorded \{expected.extension_id}",
    )
  }
  if expected.version != live.version {
    return Some("version \{live.version}, recorded \{expected.version}")
  }
  let (languages, others) = match offer {
    Legacy =>
      (
        true,
        [
          missing(
            "operations",
            expected.operations.filter(operation => operation.model() is None),
            live.operations,
          ),
          missing("targets", expected.targets, live.targets),
          missing(
            "frontend IR versions",
            expected.frontend_ir_versions,
            live.frontend_ir_versions,
          ),
          missing(
            "backend IR versions",
            expected.backend_ir_versions,
            live.backend_ir_versions,
          ),
        ],
      )
    Model({ operation: CompileModel, .. }) => (true, [])
    Model({ operation: GenerateModel, .. }) =>
      (false, [missing("targets", expected.targets, live.targets)])
  }
  if languages {
    let changed = expected.languages.filter(claim => {
      !live.languages.contains(claim)
    })
    if !changed.is_empty() {
      return Some(
        "the worker dropped or changed languages \{changed.map(claim => claim.language_id.to_string()).join(", ")}",
      )
    }
  }
  for lost in others {
    if lost is Some(text) {
      return Some("the worker dropped \{text}")
    }
  }
  None
}
