///|
/// The one binding this command dispatches: a saved core-Wasm MEP guest served
/// by the pinned Node process host. It is not a Component Model binding.
enum ExtensionBinding {
  CoreWasmProcess
}

///|
/// Runtimes qualified for the binding. A new runtime needs new route evidence.
enum ExtensionRuntime {
  Node24_22_0
  Node24_22_1
}

///|
enum ExtensionOperation {
  Describe
  Compile
  Generate
}

///|
/// The two model tuples the saved guest qualifies. Ion is the default.
enum ExtensionModelTuple {
  IonModel
  JsonIr
} derive(Eq, Debug)

///|
struct ExtensionPin {
  binding : ExtensionBinding
  runtime : ExtensionRuntime
  runtime_executable : String
  runtime_sha256 : String
  host_root : String
  host_modules : Map[String, String]
  artifact_directory : String
  wasm_sha256 : String
  manifest_sha256 : String
  origin : String
}

///|
/// One fresh guest session. Requests are pipelined: the guest serves them in
/// order, and responses are matched by id after the process exits.
struct ExtensionPlan {
  operation : ExtensionOperation
  messages : Array[Json]
  tuple : ExtensionModelTuple?
  output : String
}

///|
/// Host-process facts returned by the helper. `exited` means the guest process
/// ended by itself; the protocol outcome is decided from its framed output.
struct ExtensionProcess {
  state : String
  exit_code : Int32?
  stderr : String
  error : String
  work_directory_empty : Bool
}

///|
let extension_contract : String = "0.1.0-draft.1"

///|
let extension_profile : String = "morphir/cli/extension-command"

///|
let mep_protocol : String = "0.2.0-draft.1"

///|
let mep_execution_profile : String = "morphir/mep-bytes-v1/v1-draft"

///|
/// SHA-256 of the complete morphir/mep-bytes-v1 contract text in
/// pkgs/morphir-host/embedding/mep-adapter.mts.
let mep_execution_profile_sha256 : String = "6ed5e96fa9c7f7dcaa179efc88e517307463cfeddc5e2eeae854f0395e7a4ec6"

///|
/// The Node process host's complete module closure, as qualified by
/// scripts/portable-mep-check.mbtx and scripts/portable-mep-mck.mbtx.
let extension_host_modules : Array[String] = [
  "node-mep-cli.mjs", "node-mep-stdio.mjs", "node-mep-adapter.mjs", "node-mep-worker.mjs",
  "mep-adapter.mjs", "mep-frames.mjs", "wasm-memory.mjs", "node-artifacts.mjs", "artifacts.mjs",
  "assembly.mjs", "index.mjs", "dist/bridge.mjs",
]

///|
/// Offered model limits. The guest takes the lower value of each; the complete
/// framed request must also fit the helper's 4 MiB process-input bound.
let extension_limits : Json = {
  "maxEncodedBytes": 2796204,
  "maxDecodedBytes": 2097152,
  "maxDepth": 128,
  "maxNodes": 100000,
}

///|
fn ExtensionOperation::name(self : ExtensionOperation) -> String {
  match self {
    Describe => "describe"
    Compile => "compile"
    Generate => "generate"
  }
}

///|
fn ExtensionModelTuple::tuple(
  self : ExtensionModelTuple,
  operation : String,
) -> Json {
  let (profile, codec) = match self {
    IonModel => ("morphir-model", "ion-binary")
    JsonIr => ("morphir-ir", "morphir-json")
  }
  {
    "operation": operation,
    "profile": profile,
    "codec": codec,
    "envelopeVersion": "0.1.0-draft.1",
    "irVersion": "4.0.0",
  }
}

///|
fn ExtensionModelTuple::file_name(self : ExtensionModelTuple) -> String {
  match self {
    IonModel => "model.ionb"
    JsonIr => "model.json"
  }
}

///|
fn extension_model_format(text : String) -> ExtensionModelTuple raise {
  match text {
    "" | "ion" | "ion-binary" => IonModel
    "json" | "morphir-json" => JsonIr
    _ => raise @config.Invalid("extension.unsupported_model_format")
  }
}

///|
fn extension_sha256(bytes : Bytes) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
fn extension_text(
  fields : Map[String, Json],
  name : String,
  limit~ : Int32 = 4096,
) -> String raise {
  guard fields.get(name) is Some(String(text)) &&
    text.length() > 0 &&
    text.length() <= limit &&
    !text.contains("\u0000") else {
    raise @config.Invalid("extension.invalid_pin")
  }
  text
}

///|
fn extension_digest(fields : Map[String, Json], name : String) -> String raise {
  let text = extension_text(fields, name)
  guard mck_hex(text, 64) else {
    raise @config.Invalid("extension.invalid_pin")
  }
  text
}

///|
fn extension_path(fields : Map[String, Json], name : String) -> String raise {
  let text = extension_text(fields, name)
  guard mck_absolute(text) else {
    raise @config.Invalid("extension.invalid_pin")
  }
  text
}

///|
/// Decode the explicit pin at the boundary. Unknown members, other bindings,
/// runtimes or execution profiles are refused rather than ignored.
fn extension_pin(value : Json) -> ExtensionPin raise {
  guard value is Object(fields) &&
    fields.length() == 7 &&
    fields.get("contractVersion") == Some(Json::string(extension_contract)) &&
    fields.get("binding") is Some(String(binding)) &&
    fields.get("executionProfile") is Some(Object(profile)) &&
    fields.get("runtime") is Some(Object(runtime)) &&
    fields.get("host") is Some(Object(host)) &&
    fields.get("artifact") is Some(Object(artifact)) &&
    fields.get("origin") is Some(String(_)) else {
    raise @config.Invalid("extension.invalid_pin")
  }
  let binding = match binding {
    "core-wasm-process" => CoreWasmProcess
    _ => raise @config.Invalid("extension.unsupported_binding")
  }
  guard profile.length() == 2 &&
    profile.get("id") == Some(Json::string(mep_execution_profile)) &&
    profile.get("sha256") == Some(Json::string(mep_execution_profile_sha256)) else {
    raise @config.Invalid("extension.unsupported_execution_profile")
  }
  guard runtime.length() == 4 &&
    runtime.get("name") == Some(Json::string("node")) &&
    runtime.get("version") is Some(String(version)) else {
    raise @config.Invalid("extension.invalid_pin")
  }
  let runtime_version = match version {
    "v24.22.0" => Node24_22_0
    "v24.22.1" => Node24_22_1
    _ => raise @config.Invalid("extension.unsupported_runtime")
  }
  guard host.length() == 2 && host.get("modules") is Some(Object(modules)) else {
    raise @config.Invalid("extension.invalid_pin")
  }
  guard modules.length() == extension_host_modules.length() else {
    raise @config.Invalid("extension.incomplete_host_modules")
  }
  let host_modules : Map[String, String] = Map([])
  for name in extension_host_modules {
    guard modules.contains(name) else {
      raise @config.Invalid("extension.incomplete_host_modules")
    }
    host_modules[name] = extension_digest(modules, name)
  }
  guard artifact.length() == 3 else {
    raise @config.Invalid("extension.invalid_pin")
  }
  {
    binding,
    runtime: runtime_version,
    runtime_executable: extension_path(runtime, "executable"),
    runtime_sha256: extension_digest(runtime, "sha256"),
    host_root: extension_path(host, "root"),
    host_modules,
    artifact_directory: extension_path(artifact, "directory"),
    wasm_sha256: extension_digest(artifact, "wasmSha256"),
    manifest_sha256: extension_digest(artifact, "manifestSha256"),
    origin: extension_text(fields, "origin", limit=2048),
  }
}

///|
fn ExtensionPin::to_json(self : ExtensionPin) -> Json {
  let modules : Map[String, Json] = Map([])
  for name in extension_host_modules {
    modules[name] = Json::string(self.host_modules.get(name).unwrap_or(""))
  }
  {
    "contractVersion": extension_contract,
    "binding": match self.binding {
      CoreWasmProcess => "core-wasm-process"
    },
    "executionProfile": {
      "id": mep_execution_profile,
      "sha256": mep_execution_profile_sha256,
    },
    "runtime": {
      "name": "node",
      "version": match self.runtime {
        Node24_22_0 => "v24.22.0"
        Node24_22_1 => "v24.22.1"
      },
      "executable": self.runtime_executable,
      "sha256": self.runtime_sha256,
    },
    "host": { "root": self.host_root, "modules": Json::object(modules) },
    "artifact": {
      "directory": self.artifact_directory,
      "wasmSha256": self.wasm_sha256,
      "manifestSha256": self.manifest_sha256,
    },
    "origin": self.origin,
  }
}

///|
fn extension_request(id : Int32, name : String, params : Json) -> Json {
  { "jsonrpc": "2.0", "id": id, "method": name, "params": params }
}

///|
fn extension_operation_method(operation : ExtensionOperation) -> String {
  match operation {
    Describe => "morphir.extension.describe"
    Compile => "morphir.frontend.compileModel"
    Generate => "morphir.backend.generateModel"
  }
}

///|
/// Describe never initializes, so it ends with exit alone. Rich operations
/// offer exactly the selected tuple: there is no silent codec fallback.
fn extension_messages(
  operation : ExtensionOperation,
  tuple : ExtensionModelTuple?,
  params : Json,
) -> Array[Json] {
  let messages = [
    extension_request(1, "morphir.extension.describe", {
      "protocolVersions": [mep_protocol],
    }),
  ]
  if tuple is Some(tuple) {
    let rpc_name = extension_operation_method(operation)
    messages.push(
      extension_request(2, "morphir.initialize", {
        "protocolVersions": [mep_protocol],
        "host": { "name": "morphir-moonbit-cli", "version": "0.1.0" },
        "modelTransport": {
          "tuples": [tuple.tuple(rpc_name)],
          "limits": extension_limits,
          "guarantees": [],
        },
      }),
    )
    messages.push({ "jsonrpc": "2.0", "method": "morphir.initialized" })
    messages.push(extension_request(3, rpc_name, params))
    messages.push(extension_request(4, "morphir.shutdown", {}))
  }
  messages.push({ "jsonrpc": "2.0", "method": "morphir.exit" })
  messages
}

///|
/// A clean relative path keeps its nesting; otherwise only the file name is
/// declared. Absolute host paths never enter the model's source provenance.
fn extension_document_uri(path : String) -> String raise {
  let normal = path.replace_all(old="\\", new="/")
  let parts = normal.split("/").map(p => p.to_owned()).to_array()
  let name = parts[parts.length() - 1]
  guard name.has_suffix(".mbt") && name.length() > 4 else {
    raise @config.Invalid("extension.moonbit_source_required")
  }
  if mck_absolute(path) ||
    parts.any(p => p == "" || p == "." || p == ".." || p.contains(":")) {
    name
  } else {
    parts.join("/")
  }
}

///|
fn extension_compile_params(
  cli : Cli,
  tuple : ExtensionModelTuple,
  text : String,
) -> Json raise {
  let package_name = value(cli, "package")
  if package_name == "" {
    raise @config.Invalid("extension.package_required")
  }
  let options : Map[String, Json] = Map([
    ("typesOnly", Json::boolean(false)),
    ("irVersion", Json::string("4.0.0")),
  ])
  let profile = value(cli, "frontend-profile")
  if profile != "" {
    options["profile"] = Json::string(profile)
  }
  // The declared context is the package and options; there are no
  // dependencies or incremental baselines in this binding.
  let context : Json = {
    "package": package_name,
    "options": Json::object(options),
  }
  {
    "languageId": "moonbit",
    "sources": {
      "documents": [
        {
          "uri": extension_document_uri(value(cli, "path")),
          "languageId": "moonbit",
          "version": 0,
          "text": text,
        },
      ],
    },
    "package": { "name": package_name },
    "options": Json::object(options),
    "contextDigest": extension_sha256(@utf8.encode(context.stringify())),
    "output": tuple.tuple("morphir.frontend.compileModel"),
  }
}

///|
/// Only the qualified envelope and IR drafts are forwarded; the guest still
/// checks payload length, digest and critical members itself.
fn extension_envelope_tuple(envelope : Json) -> ExtensionModelTuple raise {
  guard envelope is Object(fields) &&
    fields.get("envelopeVersion") == Some(Json::string("0.1.0-draft.1")) &&
    fields.get("irVersion") == Some(Json::string("4.0.0")) &&
    fields.get("profile") is Some(String(profile)) &&
    fields.get("payload") is Some(Object(payload)) &&
    payload.get("codec") is Some(String(codec)) else {
    raise @config.Invalid("extension.unsupported_model_envelope")
  }
  match (profile, codec) {
    ("morphir-model", "ion-binary") => IonModel
    ("morphir-ir", "morphir-json") => JsonIr
    _ => raise @config.Invalid("extension.unsupported_model_tuple")
  }
}

///|
fn extension_generate_params(
  envelope : Json,
  tuple : ExtensionModelTuple,
  target : String,
) -> Json {
  let identity : Json = match envelope {
    Object(fields) =>
      {
        "target": target,
        "modelId": fields.get("modelId").unwrap_or(Json::null()),
        "revision": fields.get("revision").unwrap_or(Json::null()),
      }
    _ => Json::null()
  }
  {
    "model": envelope,
    "input": tuple.tuple("morphir.backend.generateModel"),
    "target": target,
    "contextDigest": extension_sha256(@utf8.encode(identity.stringify())),
  }
}

///|
fn extension_output(cli : Cli, operation : ExtensionOperation) -> String raise {
  if operation is Describe {
    if value(cli, "output") != "" {
      raise @config.Invalid("extension.describe_has_no_output")
    }
    return ""
  }
  let output = value(cli, "output")
  if output == "" {
    raise @config.Invalid("extension.output_required")
  }
  let mut output = output
  while output.length() > 1 &&
        (output.has_suffix("/") || output.has_suffix("\\")) {
    output = output[:output.length() - 1].to_owned()
  }
  if @platform.kind(output) != 0 ||
    @platform.kind(output + ".morphir-partial") != 0 {
    raise @config.Invalid("extension.output_exists")
  }
  output
}

///|
/// Read and validate every local input before any process starts.
fn extension_plan(
  cli : Cli,
  operation : ExtensionOperation,
) -> ExtensionPlan raise {
  let path = value(cli, "path")
  let output = extension_output(cli, operation)
  match operation {
    Describe => {
      if path != "" {
        raise @config.Invalid("extension.describe_takes_no_input")
      }
      {
        operation,
        messages: extension_messages(operation, None, {}),
        tuple: None,
        output,
      }
    }
    Compile => {
      if path == "" || path == "-" {
        raise @config.Invalid("extension.source_required")
      }
      let tuple = extension_model_format(value(cli, "model-format"))
      let bytes = @platform.read_input(path, 1048576)
      let text = @utf8.decode(bytes[:]) catch {
        _ => raise @config.Invalid("extension.invalid_source_encoding")
      }
      let params = extension_compile_params(cli, tuple, text)
      {
        operation,
        messages: extension_messages(operation, Some(tuple), params),
        tuple: Some(tuple),
        output,
      }
    }
    Generate => {
      if path == "" || path == "-" {
        raise @config.Invalid("extension.model_envelope_required")
      }
      if value(cli, "model-format") != "" {
        raise @config.Invalid("extension.model_format_from_envelope")
      }
      let bytes = @platform.read_input(path, 4194304)
      let envelope = @model_wire.parse_bounded(
        @utf8.decode(bytes[:]),
        max_depth=128,
        max_nodes=100000,
        max_string_units=4194304,
      ) catch {
        _ => raise @config.Invalid("extension.invalid_model_envelope")
      }
      let tuple = extension_envelope_tuple(envelope)
      let params = extension_generate_params(
        envelope,
        tuple,
        value(cli, "target", fallback="moonbit"),
      )
      {
        operation,
        messages: extension_messages(operation, Some(tuple), params),
        tuple: Some(tuple),
        output,
      }
    }
  }
}

///|
fn extension_frames(plan : ExtensionPlan) -> Bytes raise {
  let buffer = Buffer()
  for message in plan.messages {
    buffer.write_bytes(@mep.encode_frame(message.stringify()))
  }
  let bytes = buffer.to_bytes()
  if bytes.length() > 4194304 {
    raise @config.Invalid("extension.request_limit")
  }
  bytes
}

///|
/// The protocol outcome of one session, before any output is written.
priv struct ExtensionOutcome {
  state : String
  exit_code : Int32
  error : String
  extension : Json
  negotiated : Json
  result : Json
  shutdown : String
}

///|
fn extension_failure(
  state : String,
  code : Int32,
  error : String,
) -> ExtensionOutcome {
  {
    state,
    exit_code: code,
    error,
    extension: Json::null(),
    negotiated: Json::null(),
    result: Json::null(),
    shutdown: "not-observed",
  }
}

///|
fn extension_error_text(response : Json) -> String {
  match response {
    Object(fields) =>
      match fields.get("error") {
        Some(Object(error)) => {
          let code = match error.get("code") {
            Some(Number(_, repr=Some(text))) => text
            Some(Number(n, ..)) => n.to_int().to_string()
            _ => "?"
          }
          let message = match error.get("message") {
            Some(String(text)) => text
            _ => ""
          }
          code + " " + message
        }
        _ => "invalid response"
      }
    _ => "invalid response"
  }
}

///|
/// Pure interpretation of the guest's framed replies. Responses must answer the
/// requests in order; a missing reply is an incomplete session, never success.
fn extension_outcome(
  plan : ExtensionPlan,
  process : ExtensionProcess,
  stdout : Bytes,
) -> ExtensionOutcome {
  // A deadline is reported as such even when it expires during identity checks.
  if process.state != "exited" && process.error.contains("execution.deadline") {
    return extension_failure("failed", 124, process.error)
  }
  match process.state {
    "exited" => ()
    "refused" => return extension_failure("refused", 2, process.error)
    "cancelled" => return extension_failure("cancelled", 130, process.error)
    _ => return extension_failure("failed", 1, process.error)
  }
  let decoder = @mep.Decoder::new()
  let bodies = try {
    let frames = decoder.feed(stdout)
    decoder.finish()
    frames
  } catch {
    _ => return extension_failure("failed", 1, "extension.invalid_frame")
  }
  let responses : Array[Json] = []
  for body in bodies {
    let text = @utf8.decode(body[:]) catch {
      _ => return extension_failure("failed", 1, "extension.invalid_response")
    }
    let response = @model_wire.parse_bounded(
      text,
      max_depth=256,
      max_nodes=1000000,
      max_string_units=16777216,
    ) catch {
      _ => return extension_failure("failed", 1, "extension.invalid_response")
    }
    responses.push(response)
  }
  let expected = plan.messages.filter(m => {
    m is Object(fields) && fields.contains("id")
  })
  if responses.length() > expected.length() {
    return extension_failure("failed", 1, "extension.unsolicited_response")
  }
  for i, response in responses {
    guard response is Object(fields) &&
      fields.get("jsonrpc") == Some(Json::string("2.0")) &&
      expected[i] is Object(request) &&
      fields.get("id") == request.get("id") &&
      fields.contains("result") != fields.contains("error") else {
      return extension_failure("failed", 1, "extension.invalid_response")
    }
  }
  let complete = responses.length() == expected.length() &&
    process.exit_code == Some(0)
  let failed = fn(error : String) {
    extension_failure(
      "failed",
      1,
      if complete {
        error
      } else {
        "extension.incomplete_session: " + error
      },
    )
  }
  if responses.is_empty() {
    return failed("extension.guest_failed")
  }
  let describe = match responses[0] {
    Object(fields) => fields.get("result")
    _ => None
  }
  guard describe is Some(Object(claims)) &&
    claims.get("extension") is Some(Object(_) as extension) else {
    return extension_failure(
      "refused",
      2,
      "extension.describe_refused: " + extension_error_text(responses[0]),
    )
  }
  guard plan.tuple is Some(tuple) else {
    if !complete {
      return failed("extension.guest_failed")
    }
    return {
      state: "completed",
      exit_code: 0,
      error: "",
      extension,
      negotiated: Json::null(),
      result: Json::object(claims),
      shutdown: "not-applicable",
    }
  }
  if responses.length() < 2 {
    return failed("extension.guest_failed")
  }
  let rpc_name = extension_operation_method(plan.operation)
  let offered = tuple.tuple(rpc_name)
  let negotiated = match responses[1] {
    Object(fields) => fields.get("result")
    _ => None
  }
  guard negotiated is Some(Object(selection)) &&
    selection.get("protocolVersion") == Some(Json::string(mep_protocol)) &&
    selection.get("capabilities") is Some(Object(capabilities)) &&
    capabilities.get("modelTransport") is Some(Object(transport)) &&
    transport.get("tuples") is Some(Array(tuples)) else {
    let outcome = extension_failure(
      "refused",
      2,
      "extension.negotiation_refused: " + extension_error_text(responses[1]),
    )
    return { ..outcome, extension, }
  }
  let agreed : Json = {
    "protocolVersion": mep_protocol,
    "tuple": offered,
    "limits": transport.get("limits").unwrap_or(Json::null()),
  }
  if !tuples.contains(offered) {
    return {
      ..extension_failure("refused", 2, "extension.tuple_unavailable"),
      extension,
      negotiated: agreed,
    }
  }
  if responses.length() < 3 {
    return {
      ..failed("extension.guest_failed"),
      extension,
      negotiated: agreed,
    }
  }
  let result = match responses[2] {
    Object(fields) => fields.get("result")
    _ => None
  }
  guard result is Some(Object(result_fields) as result) else {
    return {
      ..failed(
        "extension.operation_error: " + extension_error_text(responses[2]),
      ),
      extension,
      negotiated: agreed,
    }
  }
  let shutdown = if responses.length() >= 4 &&
    responses[3] is Object(fields) &&
    fields.get("result") is Some(Object(_)) {
    "acknowledged"
  } else {
    "not-acknowledged"
  }
  if !complete || shutdown != "acknowledged" {
    return {
      ..failed("extension.guest_failed"),
      extension,
      negotiated: agreed,
      result,
      shutdown,
    }
  }
  let success = result_fields.get("success") == Some(Json::boolean(true))
  {
    state: "completed",
    exit_code: if success {
      0
    } else {
      1
    },
    error: if success {
      ""
    } else {
      "extension.operation_unsuccessful"
    },
    extension,
    negotiated: agreed,
    result,
    shutdown,
  }
}

///|
/// The decoded payload must match the length and digest the guest declared.
fn extension_model_bytes(
  result : Json,
  tuple : ExtensionModelTuple,
) -> (Json, Bytes) raise {
  guard result is Object(fields) &&
    fields.get("model") is Some(Object(model_fields) as model) &&
    extension_envelope_tuple(model) == tuple &&
    model_fields.get("payload") is Some(Object(payload)) &&
    payload.get("content") is Some(String(content)) &&
    payload.get("sha256") is Some(String(digest)) &&
    payload.get("decodedByteLength") is Some(Number(length, ..)) else {
    raise @config.Invalid("extension.invalid_model_result")
  }
  let bytes = @base64.decode(content) catch {
    _ => raise @config.Invalid("extension.invalid_model_result")
  }
  guard bytes.length().to_double() == length &&
    extension_sha256(bytes) == digest else {
    raise @config.Invalid("extension.model_integrity")
  }
  (model, bytes)
}

///|
/// Generated paths are relative, slash-separated and confined to the output.
fn extension_artifacts(result : Json) -> Array[(String, Bytes)] raise {
  guard result is Object(fields) &&
    fields.get("artifacts") is Some(Array(artifacts)) &&
    artifacts.length() <= 10000 else {
    raise @config.Invalid("extension.invalid_artifacts")
  }
  let seen : Map[String, Bool] = Map([])
  let files = []
  for artifact in artifacts {
    guard artifact is Object(item) &&
      item.get("path") is Some(String(path)) &&
      path.length() <= 1024 &&
      !mck_absolute(path) &&
      !path.contains("\\") &&
      !path.contains(":") &&
      !path.contains("\u0000") &&
      path.split("/").all(p => p != "" && p != "." && p != "..") &&
      item.get("content") is Some(String(content)) &&
      item.get("binary") is Some(binary) &&
      (binary == Json::boolean(true) || binary == Json::boolean(false)) &&
      !seen.contains(path) else {
      raise @config.Invalid("extension.invalid_artifacts")
    }
    seen[path] = true
    let bytes = if binary == Json::boolean(true) {
      @base64.decode(content) catch {
        _ => raise @config.Invalid("extension.invalid_artifacts")
      }
    } else {
      @utf8.encode(content)
    }
    files.push((path, bytes))
  }
  // A file path cannot also be a directory prefix of another artifact.
  for entry in files {
    if files.any(other => other.0.has_prefix(entry.0 + "/")) {
      raise @config.Invalid("extension.invalid_artifacts")
    }
  }
  files
}

///|
/// Files the operation publishes, decided before anything is written.
fn extension_files(
  plan : ExtensionPlan,
  outcome : ExtensionOutcome,
) -> Array[(String, Bytes)] raise {
  if outcome.exit_code != 0 {
    return []
  }
  match (plan.operation, plan.tuple) {
    (Compile, Some(tuple)) => {
      let (model, bytes) = extension_model_bytes(outcome.result, tuple)
      [
        ("model-envelope.json", @utf8.encode(model.stringify())),
        (tuple.file_name(), bytes),
      ]
    }
    (Generate, Some(_)) => extension_artifacts(outcome.result)
    _ => []
  }
}

///|
/// Write into a sibling staging directory, then publish it with a
/// no-replacement rename. A failure leaves no partial destination.
fn extension_publish(
  output : String,
  files : Array[(String, Bytes)],
) -> Array[Json] raise {
  let staging = output + ".morphir-partial"
  @platform.mkdir(staging)
  let created : Array[String] = []
  let directories : Array[String] = [staging]
  errdefer {
    for path in created.rev() {
      @platform.remove_file(path) catch {
        _ => ()
      }
    }
    for directory in directories.rev() {
      @platform.remove_dir(directory) catch {
        _ => ()
      }
    }
  }
  let receipts : Array[Json] = []
  for entry in files {
    let (path, bytes) = entry
    let parts = path.split("/").map(p => p.to_owned()).to_array()
    let mut parent = staging
    for i in 0..<(parts.length() - 1) {
      parent = parent + "/" + parts[i]
      if @platform.kind(parent) == 0 {
        @platform.mkdir(parent)
        directories.push(parent)
      }
    }
    @platform.write_bytes(staging + "/" + path, bytes)
    created.push(staging + "/" + path)
    receipts.push({
      "path": path,
      "bytes": bytes.length(),
      "sha256": extension_sha256(bytes),
    })
  }
  @platform.rename_directory_new(staging, output)
  receipts
}

///|
fn extension_report(
  plan : ExtensionPlan,
  pin : ExtensionPin,
  process : ExtensionProcess,
  outcome : ExtensionOutcome,
  outputs : Array[Json],
) -> Json {
  {
    "profile": extension_profile,
    "contractVersion": extension_contract,
    "operation": plan.operation.name(),
    "state": outcome.state,
    "exitCode": outcome.exit_code,
    "binding": pin.to_json(),
    "access": {
      "guestImports": "declared morphir_bytes_v1 byte callbacks only, checked by the host loader",
      "wireCancellation": false,
      "hostCancellation": "guest process-group termination",
      "fileLogging": false,
    },
    "extension": outcome.extension,
    "negotiated": outcome.negotiated,
    "result": outcome.result,
    "output": if plan.output == "" || outputs.is_empty() {
      Json::null()
    } else {
      { "directory": plan.output, "files": Json::array(outputs) }
    },
    "lifecycle": {
      "process": process.state,
      "exitCode": match process.exit_code {
        Some(code) => Json::number(code.to_double())
        None => Json::null()
      },
      "shutdown": outcome.shutdown,
      "workDirectoryEmpty": process.work_directory_empty,
    },
    "stderr": process.stderr,
    "error": if outcome.error == "" {
      Json::null()
    } else {
      Json::string(outcome.error)
    },
  }
}

///|
fn extension_diagnostics(result : Json) -> Array[String] {
  guard result is Object(fields) &&
    fields.get("diagnostics") is Some(Array(items)) else {
    return []
  }
  items.map(item => {
    guard item is Object(d) else { return item.stringify() }
    let text = fn(name : String) {
      match d.get(name) {
        Some(String(s)) => s
        _ => ""
      }
    }
    let at = match d.get("location") {
      Some(Object(location)) =>
        match (location.get("uri"), location.get("range")) {
          (Some(String(uri)), Some(Object(range))) =>
            match range.get("start") {
              Some(Object(start)) =>
                match (start.get("line"), start.get("character")) {
                  (Some(Number(line, ..)), Some(Number(column, ..))) =>
                    uri +
                    ":" +
                    (line.to_int() + 1).to_string() +
                    ":" +
                    (column.to_int() + 1).to_string() +
                    ": "
                  _ => uri + ": "
                }
              _ => uri + ": "
            }
          _ => ""
        }
      _ => ""
    }
    at + text("severity") + " " + text("code") + ": " + text("message")
  })
}

///|
fn extension_emit(report : Json, mode : OutputMode) -> Unit {
  match mode {
    JSON => println(report.stringify())
    JSONLines => emit_record("extension", report)
    Human => {
      guard report is Object(fields) else { return }
      let extension = match fields.get("extension") {
        Some(Object(e)) =>
          match (e.get("id"), e.get("version")) {
            (Some(String(id)), Some(String(version))) => id + " " + version
            _ => "extension"
          }
        _ => "extension"
      }
      let result = fields.get("result").unwrap_or(Json::null())
      for line in extension_diagnostics(result) {
        @platform.stderr(line + "\n")
      }
      match fields.get("output") {
        Some(Object(output)) =>
          if output.get("files") is Some(Array(files)) &&
            output.get("directory") is Some(String(directory)) {
            println(
              extension +
              " via core-wasm-process: wrote " +
              files.length().to_string() +
              " file(s) to " +
              directory,
            )
          }
        _ =>
          if fields.get("operation") == Some(Json::string("describe")) &&
            fields.get("exitCode") == Some(Json::number(0.0)) {
            println(extension + " via core-wasm-process")
            println(result.stringify())
          }
      }
      if fields.get("stderr") is Some(String(stderr)) && stderr != "" {
        @platform.stderr(stderr)
      }
      if fields.get("error") is Some(String(error)) {
        @platform.stderr(error + "\n")
      }
    }
  }
}

///|
/// Interpret the helper's reply, publish outputs and emit the report. Every
/// path returns an exit status; a write failure is reported, never hidden.
fn extension_finish(
  plan : ExtensionPlan,
  pin : ExtensionPin,
  reply : String,
  stdout : Bytes,
  mode : OutputMode,
) -> Int32 {
  let parsed = Some(@json.parse(reply)) catch { _ => None }
  let process : ExtensionProcess = match parsed {
    Some(Object(fields)) if fields.get("profile") ==
      Some(Json::string(extension_profile)) &&
      fields.get("contractVersion") == Some(Json::string(extension_contract)) &&
      fields.get("state") is Some(String(state)) =>
      {
        state,
        exit_code: match fields.get("exitCode") {
          Some(Number(n, ..)) => Some(n.to_int())
          _ => None
        },
        stderr: match fields.get("stderr") {
          Some(String(text)) => text
          _ => ""
        },
        error: match fields.get("error") {
          Some(String(text)) => text
          _ => ""
        },
        work_directory_empty: fields.get("workDirectoryEmpty") ==
        Some(Json::boolean(true)),
      }
    _ =>
      {
        state: "failed",
        exit_code: None,
        stderr: "",
        error: "extension.invalid_helper_reply",
        work_directory_empty: false,
      }
  }
  let mut outcome = extension_outcome(plan, process, stdout)
  if outcome.exit_code == 0 && !process.work_directory_empty {
    outcome = {
      ..outcome,
      state: "failed",
      exit_code: 1,
      error: "extension.guest_wrote_files",
    }
  }
  let outputs = try {
    let files = extension_files(plan, outcome)
    if files.is_empty() {
      []
    } else {
      extension_publish(plan.output, files)
    }
  } catch {
    error => {
      outcome = {
        ..outcome,
        state: "failed",
        exit_code: 1,
        error: match error {
          @config.Invalid(code) => code
          _ => "extension.output_failed: " + @host.error_message(error)
        },
      }
      []
    }
  }
  extension_emit(extension_report(plan, pin, process, outcome, outputs), mode)
  outcome.exit_code
}

///|
fn extension_command(cli : Cli, mode : OutputMode) -> Int32 raise {
  let operation = match cli.command {
    "extension describe" => Describe
    "extension compile" => Compile
    "extension generate" => Generate
    _ => raise @config.Invalid("extension.command_required")
  }
  if !connected_supported() {
    raise @config.Invalid("extension.runtime_unavailable")
  }
  let pin_path = value(
    cli,
    "extension-pin",
    fallback=@platform.environment().get("MORPHIR_EXTENSION_PIN").unwrap_or(""),
  )
  let helper = value(
    cli,
    "extension-helper",
    fallback=@platform.environment()
      .get("MORPHIR_EXTENSION_HELPER")
      .unwrap_or(""),
  )
  if pin_path == "" || helper == "" {
    raise @config.Invalid("extension.explicit_pin_and_helper_required")
  }
  let pin_bytes = @platform.read_input(pin_path, 65536)
  let pin_json = @json.parse(@utf8.decode(pin_bytes[:])) catch {
    _ => raise @config.Invalid("extension.invalid_pin")
  }
  if pin_json is Object(fields) &&
    fields.get("binding") == Some(Json::string("native-process")) {
    return native_extension_command(cli, mode, pin_json, helper, operation) catch {
      cause => {
        let message = @host.error_message(cause)
        @platform.stderr(message + "\n")
        native_services_emit(
          native_services_report(cli.command, Json::null(), message, 1),
          mode,
        )
        1
      }
    }
  }
  if value(cli, "log-file") != "" || value(cli, "log-format") != "" {
    raise @config.Invalid("extension.portable_file_logging_unavailable")
  }
  let pin = extension_pin(pin_json)
  let timeout = build_timeout(value(cli, "timeout", fallback="60000"))
  if timeout > 594000 {
    raise @config.Invalid("extension.timeout_limit: maximum 594000 ms")
  }
  let plan = extension_plan(cli, operation)
  let frames = extension_frames(plan)
  @platform.interruption_start()
  defer @platform.interruption_stop()
  let root = @platform.temporary()
  let control : Json = {
    "profile": extension_profile,
    "contractVersion": extension_contract,
    "pin": pin.to_json(),
    "requestFile": root + "/request.bin",
    "responseFile": root + "/response.bin",
    "workDirectory": root + "/guest",
    "timeout": timeout,
    "cancelFile": value(cli, "cancel-file"),
  }
  @platform.write_bytes(root + "/request.bin", frames)
  @platform.mkdir(root + "/guest")
  extension_dispatch(
    helper,
    control,
    root,
    value(cli, "node", fallback="node"),
    timeout,
    fn(reply) {
      let stdout = @platform.read_input(root + "/response.bin", 16777216) catch {
        _ => b""
      }
      let code = extension_finish(plan, pin, reply, stdout, mode)
      extension_cleanup(root)
      code
    },
  )
}

///|
/// Remove only the files this command creates. A guest that wrote into its
/// working directory leaves it in place, and the report already says so.
fn extension_cleanup(root : String) -> Unit {
  for name in ["control.json", "request.bin", "response.bin"] {
    let file = try @platform.kind(root + "/" + name) == 1 catch {
      _ => false
    }
    if file {
      @platform.remove_file(root + "/" + name) catch {
        _ => ()
      }
    }
  }
  @platform.remove_dir(root + "/guest") catch {
    _ => ()
  }
  @platform.remove_dir(root) catch {
    _ => ()
  }
}

///|
#cfg(target="js")
extern "js" fn extension_start(
  helper : String,
  config : String,
  interrupted : () -> Bool,
  finish : (String) -> Int32,
) -> Unit =
  #| (helper, config, interrupted, finish) => {
  #|   const failed = JSON.stringify({profile:'morphir/cli/extension-command',contractVersion:'0.1.0-draft.1',state:'failed',exitCode:null,stderr:'',error:'extension.helper_unavailable',workDirectoryEmpty:false});
  #|   import('node:url').then(({pathToFileURL})=>import(pathToFileURL(helper).href))
  #|     .then(module=>module.extensionCommand(JSON.parse(config),interrupted))
  #|     .then(reply=>JSON.stringify(reply),()=>failed)
  #|     .then(reply=>{process.exitCode=finish(reply);});
  #| }

///|
#cfg(target="js")
fn extension_dispatch(
  helper : String,
  control : Json,
  _root : String,
  _node : String,
  _timeout : Int32,
  finish : (String) -> Int32,
) -> Int32 {
  extension_start(
    helper,
    control.stringify(),
    @platform.interruption_requested,
    finish,
  )
  0
}

///|
#cfg(target="native")
fn extension_dispatch(
  helper : String,
  control : Json,
  root : String,
  node : String,
  timeout : Int32,
  finish : (String) -> Int32,
) -> Int32 raise {
  @platform.write(root + "/control.json", control.stringify())
  let result = @platform.process(
    node,
    [helper, "--morphir-extension-v1", root + "/control.json"],
    @platform.cwd(),
    "",
    timeout + 10000,
  ) catch {
    _ => Json::null()
  }
  let reply = match result {
    Object(fields) =>
      match (fields.get("exitCode"), fields.get("stdout")) {
        (Some(Number(0.0, ..)), Some(String(source))) => source
        _ => ""
      }
    _ => ""
  }
  finish(reply)
}

///|
#cfg(any(target="wasm", target="wasm-gc"))
fn extension_dispatch(
  _helper : String,
  _control : Json,
  _root : String,
  _node : String,
  _timeout : Int32,
  _finish : (String) -> Int32,
) -> Int32 raise {
  raise @config.Invalid("extension.runtime_unavailable")
}
