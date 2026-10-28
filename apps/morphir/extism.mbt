///|
/// A separate legacy profile. Neither a rich tuple nor a byte-ABI runtime.
let extism_execution_profile : String = "morphir/extism-mep-0.1/v1"

///|
let extism_helper_modules : Array[String] = [
  "extism.mjs", "supervision.mjs", "windows-job.mjs",
]

///|
enum ExtismIrVersion {
  PythonV3
  PythonV4
} derive(Eq, Debug)

///|
fn ExtismIrVersion::major(self : ExtismIrVersion) -> String {
  match self {
    PythonV3 => "3"
    PythonV4 => "4"
  }
}

///|
fn extism_ir_version(text : String) -> ExtismIrVersion raise {
  match text {
    "3" | "3.0.0" => PythonV3
    "4" | "4.0.0" => PythonV4
    _ => raise @config.Invalid("extension.ir_version_required: select 3 or 4")
  }
}

///|
fn extism_pin(pin : Json) -> Json raise {
  guard pin is Object(fields) &&
    fields.length() == 8 &&
    fields.get("binding") == Some(Json::string("extism-wasm")) &&
    fields.get("contractVersion") == Some(Json::string("0.1.0")) &&
    fields.get("executionProfile") ==
    Some(Json::string(extism_execution_profile)) &&
    fields.get("host") is Some(host) &&
    fields.get("runtime") is Some(Object(runtime)) &&
    runtime.length() == 3 &&
    fields.get("helper") is Some(Object(helper)) &&
    helper.length() == 2 &&
    helper.get("modules") is Some(Object(modules)) &&
    modules.length() == extism_helper_modules.length() &&
    fields.get("artifact") is Some(Object(artifact)) &&
    artifact.length() == 5 else {
    raise @config.Invalid("extension.invalid_pin")
  }
  ignore(native_services_host(host)) catch {
    _ => raise @config.Invalid("extension.invalid_pin: host revision or digest")
  }
  ignore(extension_path(runtime, "executable"))
  ignore(extension_digest(runtime, "sha256"))
  ignore(extension_text(runtime, "version"))
  ignore(extension_path(helper, "root"))
  for name in extism_helper_modules {
    ignore(extension_digest(modules, name))
  }
  ignore(extension_path(artifact, "directory"))
  ignore(extension_digest(artifact, "descriptorSha256"))
  ignore(extension_digest(artifact, "wasmSha256"))
  ignore(extension_text(artifact, "extensionId"))
  ignore(extension_text(artifact, "version"))
  ignore(extension_text(fields, "origin", limit=2048))
  pin
}

///|
fn extism_model(model : Json, version : ExtismIrVersion) -> Json raise {
  let text = model.stringify()
  if @utf8.encode(text).length() > 2097152 {
    raise @config.Invalid("extension.resource_limit: IR bytes")
  }
  let model = @model_wire.parse_bounded(
    text,
    max_depth=128,
    max_nodes=100000,
    max_string_units=2097152,
  )
  guard model is Object(fields) && fields.get("formatVersion") is Some(header) else {
    raise @config.Invalid(
      "extension.unsupported_model_format: plain Morphir JSON required",
    )
  }
  let actual = @model_wire.read_version(header) catch {
    _ =>
      raise @config.Invalid(
        "extension.ir_version_mismatch: unsupported formatVersion",
      )
  }
  if actual.to_release_string() != version.major() + ".0.0" {
    raise @config.Invalid("extension.ir_version_mismatch")
  }
  ignore(@versioned_json.from_json(model)) catch {
    cause =>
      raise @config.Invalid(
        "extension.invalid_result: " + @model_wire.diagnostic(cause),
      )
  }
  model
}

///|
fn extism_tick(deadline : Double, cancel_file~ : String = "") -> Unit raise {
  if @platform.interruption_requested() ||
    (cancel_file != "" && @platform.kind(cancel_file) != 0) {
    raise @config.Invalid("execution.cancelled")
  }
  if @platform.monotonic_seconds() >= deadline {
    raise @config.Invalid("extension.timeout")
  }
}

///|
fn extism_sources(
  path : String,
  deadline : Double,
  cancel_file~ : String = "",
) -> Array[Json] raise {
  let sources : Array[Json] = []
  let mut total = 0
  let mut entries = 0
  let seen : Map[String, Bool] = Map([])
  fn file(path : String, uri : String) -> Unit raise {
    extism_tick(deadline, cancel_file~)
    if !uri.has_suffix(".py") {
      return
    }
    if sources.length() >= 1024 ||
      seen.contains(uri) ||
      uri.split("/").any(p => p == "" || p == "." || p == "..") ||
      uri.contains("\\") ||
      uri.contains(":") {
      raise @config.Invalid("extension.invalid_source_path")
    }
    let bytes = @platform.read_input(path, 2097152)
    total += bytes.length()
    if total > 2097152 {
      raise @config.Invalid("extension.resource_limit: sources")
    }
    let source = @utf8.decode(bytes[:]) catch {
      _ => raise @config.Invalid("extension.invalid_source_encoding")
    }
    seen[uri] = true
    sources.push({
      "uri": uri,
      "languageId": "python",
      "version": 1,
      "text": source,
    })
  }
  fn walk(directory : String, relative : String, depth : Int32) -> Unit raise {
    extism_tick(deadline, cancel_file~)
    if depth > 32 {
      raise @config.Invalid("extension.resource_limit: source depth")
    }
    let names = @platform.list_bounded(directory, 4096)
    names.sort()
    for name in names {
      entries += 1
      if entries > 16384 {
        raise @config.Invalid("extension.resource_limit: source entries")
      }
      let full = directory + "/" + name
      let uri = if relative == "" { name } else { relative + "/" + name }
      match @platform.kind(full) {
        1 => file(full, uri)
        2 => walk(full, uri, depth + 1)
        _ =>
          raise @config.Invalid(
            "extension.invalid_source_path: symlink or special entry",
          )
      }
    }
  }
  match @platform.kind(path) {
    1 => file(path, path.split("/").last().unwrap_or("").to_owned())
    2 => walk(path, "", 0)
    _ =>
      raise @config.Invalid(
        "extension.source_required: regular Python file or directory",
      )
  }
  if sources.is_empty() {
    raise @config.Invalid("extension.source_required: no Python files")
  }
  sources
}

///|
fn extism_params(
  cli : Cli,
  operation : ExtensionOperation,
  deadline : Double,
) -> (Json, ExtismIrVersion?) raise {
  if !(operation is Describe) &&
    value(cli, "model-format", fallback="json") != "json" {
    raise @config.Invalid("extension.unsupported_model_format: use json")
  }
  if value(cli, "frontend-profile") != "" {
    raise @config.Invalid(
      "extension.unsupported_model_format: rich profiles unavailable",
    )
  }
  let cancel_file = value(cli, "cancel-file")
  extism_tick(deadline, cancel_file~)
  match operation {
    Describe => {
      if value(cli, "path") != "" {
        raise @config.Invalid("extension.describe_takes_no_input")
      }
      ({}, None)
    }
    Compile => {
      let version = extism_ir_version(value(cli, "ir-version"))
      let package_name = value(cli, "package")
      if package_name == "" {
        raise @config.Invalid("extension.package_required")
      }
      let documents = extism_sources(value(cli, "path"), deadline, cancel_file~)
      (
        {
          "languageId": "python",
          "sources": { "documents": documents },
          "package": { "name": package_name },
          "dependencies": [],
          "options": { "irVersion": version.major(), "typesOnly": false },
        },
        Some(version),
      )
    }
    Generate => {
      let version = extism_ir_version(value(cli, "ir-version"))
      if value(cli, "target", fallback="python") != "python" {
        raise @config.Invalid(
          "extension.capability_mismatch: target python required",
        )
      }
      let bytes = @platform.read_input(value(cli, "path"), 2097152)
      let source = @utf8.decode(bytes[:]) catch {
        _ =>
          raise @config.Invalid(
            "extension.unsupported_model_format: UTF-8 JSON required",
          )
      }
      let parsed = @model_wire.parse_bounded(
        source,
        max_depth=128,
        max_nodes=100000,
        max_string_units=2097152,
      ) catch {
        cause =>
          raise @config.Invalid(
            "extension.unsupported_model_format: " +
            @model_wire.diagnostic(cause),
          )
      }
      let model = extism_model(parsed, version)
      ({ "ir": model, "target": "python", "options": {} }, Some(version))
    }
  }
}

///|
fn extism_files(
  operation : ExtensionOperation,
  result : Json,
  version : ExtismIrVersion?,
) -> Array[(String, Bytes)] raise {
  match operation {
    Describe => []
    Compile => {
      guard result is Object(fields) &&
        fields.get("ir") is Some(ir) &&
        fields.get("irVersion") is Some(String(reported)) &&
        version is Some(expected) &&
        extism_ir_version(reported) == expected else {
        raise @config.Invalid("extension.ir_version_mismatch")
      }
      let model = extism_model(ir, expected)
      [("morphir-ir.json", @utf8.encode(model.stringify()))]
    }
    Generate => {
      let files = extension_artifacts(result)
      if files.length() > 1024 {
        raise @config.Invalid("extension.resource_limit: file count")
      }
      let mut total = 0
      for entry in files {
        total += entry.1.length()
        if total > 8388608 {
          raise @config.Invalid("extension.resource_limit: artifact bytes")
        }
      }
      files
    }
  }
}

///|
fn extism_report(
  command : String,
  result : Json,
  error : String,
  status : Int32,
  diagnostics : Json,
) -> Json {
  let fields : Map[String, Json] = Map([
    ("profile", Json::string("morphir/command-result")),
    ("contractVersion", Json::string("0.1.0")),
    ("command", Json::string(command.replace(old=" ", new="."))),
    ("state", Json::string(if status == 0 { "succeeded" } else { "failed" })),
    ("exitCode", Json(status)),
    ("diagnostics", diagnostics),
  ])
  if status == 0 {
    fields["result"] = result
  } else {
    let code = error
      .split(":")
      .to_array()
      .get(0)
      .unwrap_or("extension.invalid_result")
      .to_owned()
    fields["error"] = {
      "code": if code.has_prefix("extension.") || code == "execution.cancelled" {
        code
      } else {
        "extension.invalid_result"
      },
      "message": error,
    }
  }
  Json::object(fields)
}

///|
fn extism_failure_status(error : String) -> Int32 {
  if error == "execution.cancelled" {
    130
  } else {
    1
  }
}

///|
fn extism_command(
  cli : Cli,
  mode : OutputMode,
  pin : Json,
  helper : String,
  operation : ExtensionOperation,
) -> Int32 {
  extism_execute(cli, mode, pin, helper, operation) catch {
    cause => {
      let message = @host.error_message(cause)
      let message = if message == "Cancelled" {
        "execution.cancelled"
      } else {
        message
      }
      let status = extism_failure_status(message)
      @platform.stderr(message + "\n")
      native_services_emit(
        extism_report(cli.command, Json::null(), message, status, []),
        mode,
      )
      status
    }
  }
}

///|
fn extism_execute(
  cli : Cli,
  mode : OutputMode,
  pin : Json,
  helper : String,
  operation : ExtensionOperation,
) -> Int32 raise {
  if !connected_supported() || @platform.system_type() == "windows" {
    raise @config.Invalid("extension.unsupported_target")
  }
  let pin = extism_pin(pin)
  let output = extension_output(cli, operation)
  let configured_timeout = build_timeout(
    value(cli, "timeout", fallback="60000"),
  )
  if configured_timeout > 594000 {
    raise @config.Invalid("extension.resource_limit: session timeout")
  }
  if value(cli, "log-file") != "" || value(cli, "log-format") != "" {
    raise @config.Invalid("extension.file_logging_unavailable")
  }
  let cancel_file = value(cli, "cancel-file")
  let deadline = @platform.monotonic_seconds() +
    configured_timeout.to_double() / 1000.0
  @platform.interruption_start()
  defer @platform.interruption_stop()
  let (params, version) = extism_params(cli, operation, deadline)
  let root = @platform.temporary()
  errdefer extism_cleanup(root)
  @platform.mkdir(root + "/guest")
  // The CLI copies the pinned bootstrap closure before importing/spawning it.
  // The bootstrap then verifies and copies the selected runtime and host too.
  guard pin is Object(pin_fields) &&
    pin_fields.get("helper") is Some(Object(helper_fields)) &&
    helper_fields.get("root") is Some(String(helper_root)) &&
    helper_fields.get("modules") is Some(Object(modules)) &&
    helper == helper_root + "/extism.mjs" else {
    raise @config.Invalid("extension.invalid_pin: helper path")
  }
  for name in extism_helper_modules {
    let chunks : Array[Bytes] = []
    @platform.file_chunks(helper_root + "/" + name, 4194304, chunk => {
      extism_tick(deadline, cancel_file~)
      chunks.push(chunk)
    })
    let bytes = Bytes::from_array(
      chunks.iter().flat_map(chunk => chunk.iter()).collect(),
    )
    if modules.get(name) != Some(Json::string(extension_sha256(bytes))) {
      raise @config.Invalid("extension.integrity_mismatch: helper")
    }
    @platform.write_bytes(root + "/" + name, bytes)
  }
  extism_tick(deadline, cancel_file~)
  let timeout = ((deadline - @platform.monotonic_seconds()) * 1000.0)
    .to_int()
    .max(1)
  let request : Json = {
    "operation": "extism." + operation.name(),
    "pin": pin,
    "params": params,
    "timeout": timeout,
    "workDirectory": root + "/guest",
  }
  if @utf8.encode(request.stringify()).length() > 4194304 {
    raise @config.Invalid("extension.resource_limit: request")
  }
  @platform.write(root + "/request.bin", request.stringify())
  let control : Json = {
    "profile": "morphir/cli/extism-services",
    "contractVersion": "0.1.0",
    "pin": pin,
    "requestFile": root + "/request.bin",
    "responseFile": root + "/response.bin",
    "workDirectory": root + "/guest",
    "timeout": timeout,
    "cancelFile": cancel_file,
  }
  extension_dispatch(
    root + "/extism.mjs",
    control,
    root,
    value(cli, "node", fallback="node"),
    timeout,
    fn(reply) {
      let mut status = 1
      let mut result = Json::null()
      let mut diagnostics = Json::array([])
      let mut error = "extension.invalid_result"
      let mut cleanup_allowed = false
      try {
        guard @model_wire.parse_bounded(
            reply,
            max_depth=32,
            max_nodes=1000,
            max_string_units=131072,
          )
          is Object(process) else {
          raise @config.Invalid(error)
        }
        cleanup_allowed = process.get("workDirectoryEmpty") ==
          Some(Json::boolean(true))
        if process.get("stderr") is Some(String(stderr)) && stderr != "" {
          @platform.stderr(stderr)
        }
        if process.get("state") == Some(Json::string("cancelled")) {
          status = 130
          error = "execution.cancelled"
        }
        guard process.get("state") == Some(Json::string("exited")) &&
          process.get("workDirectoryEmpty") == Some(Json::boolean(true)) else {
          if status != 130 {
            error = match process.get("error") {
              Some(String(message)) => message
              _ => "extension.incomplete_session"
            }
          }
          raise @config.Invalid(error)
        }
        let source = @utf8.decode(
          @platform.read_input(root + "/response.bin", 16777216)[:],
        )
        let service = @model_wire.parse_bounded(
          source,
          max_depth=144,
          max_nodes=110000,
          max_string_units=16777216,
        )
        guard service is Object(service_fields) else {
          raise @config.Invalid(error)
        }
        if service_fields.get("state") != Some(Json::string("succeeded")) {
          error = match service_fields.get("error") {
            Some(Object(failure)) =>
              match failure.get("message") {
                Some(String(message)) => message
                _ => error
              }
            _ => error
          }
          raise @config.Invalid(error)
        }
        guard service_fields.get("result") is Some(Object(session)) &&
          session.get("containerDropped") == Some(Json::boolean(true)) &&
          session.get("result") is Some(operation_result) else {
          raise @config.Invalid(error)
        }
        if operation_result is Object(fields) {
          diagnostics = fields.get("diagnostics").unwrap_or(Json::array([]))
        }
        for message in extension_diagnostics(operation_result) {
          @platform.stderr(message + "\n")
        }
        if !(operation is Describe) {
          guard operation_result is Object(fields) &&
            fields.get("success") == Some(Json::boolean(true)) else {
            error = "extension.operation_unsuccessful"
            raise @config.Invalid(error)
          }
        }
        let files = extism_files(operation, operation_result, version)
        extism_tick(deadline, cancel_file~)
        extism_cleanup(root)
        if @platform.kind(root) != 0 {
          error = "extension.incomplete_session: scratch cleanup"
          raise @config.Invalid(error)
        }
        let receipts = if files.is_empty() {
          []
        } else {
          extension_publish(output, files, check=() => {
            extism_tick(deadline, cancel_file~)
          })
        }
        result = {
          "binding": "extism-wasm",
          "session": Json::object(session),
          "outputDirectory": output,
          "outputs": receipts,
          "lifecycle": {
            "containerDropped": true,
            "processGroup": "stopped",
            "scratchRemoved": true,
          },
          "access": {
            "network": "denied",
            "filesystem": "no-preopens",
            "environment": "empty",
            "wireCancellation": false,
          },
        }
        status = 0
      } catch {
        cause =>
          if error == "extension.invalid_result" {
            let diagnostic = @model_wire.diagnostic(cause)
            error = if diagnostic == "unknown_error" {
              @host.error_message(cause)
            } else {
              "extension.invalid_result: " + diagnostic
            }
          }
      }
      if cleanup_allowed {
        extism_cleanup(root)
      }
      let cleaned = cleanup_allowed &&
        (try @platform.kind(root) == 0 catch {
          _ => false
        })
      if !cleaned {
        status = 1
        error = "extension.incomplete_session: scratch cleanup"
      }
      if status != 0 {
        status = extism_failure_status(error)
        @platform.stderr(error + "\n")
      }
      native_services_emit(
        extism_report(cli.command, result, error, status, diagnostics),
        mode,
      )
      status
    },
  )
}

///|
fn extism_cleanup(root : String) -> Unit {
  for name in extism_helper_modules {
    @platform.remove_file(root + "/" + name) catch {
      _ => ()
    }
  }
  extension_cleanup(root)
}
