///|
let native_services_revision : String = "ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409"

///|
fn native_services_host(value : Json) -> Json raise {
  guard value is Object(fields) &&
    fields.length() == 3 &&
    fields.get("sourceRevision") == Some(Json::string(native_services_revision)) else {
    raise @config.Invalid("native.invalid_host_pin")
  }
  ignore(extension_path(fields, "executable"))
  ignore(extension_digest(fields, "sha256"))
  value
}

///|
fn native_services_report(
  command : String,
  result : Json,
  error : String,
  status : Int32,
  diagnostics~ : Json = Json::array([]),
) -> Json {
  let fields : Map[String, Json] = Map([
    ("profile", Json::string("morphir/command-result")),
    ("contractVersion", Json::string("0.1.0")),
    ("command", Json::string(command)),
    ("state", Json::string(if status == 0 { "succeeded" } else { "failed" })),
    ("exitCode", Json::number(status.to_double())),
    ("diagnostics", diagnostics),
  ])
  if status == 0 {
    fields["result"] = result
  } else {
    fields["error"] = { "code": "native.operation_failed", "message": error }
  }
  Json::object(fields)
}

///|
fn native_services_emit(report : Json, mode : OutputMode) -> Unit {
  match mode {
    JSON => println(report.stringify())
    JSONLines => emit_record("result", report)
    Human => println(report.stringify())
  }
}

///|
fn native_services_cleanup(
  root : String,
  logs : @host.TelemetrySession,
) -> Bool {
  logs
  .observer()
  .scope()
  .observe(@observe.Cleanup, _ => {
    extension_cleanup(root)
    if @platform.kind(root) != 0 {
      raise @config.Invalid("native.scratch_cleanup_failed")
    }
    true
  }) catch {
    _ => false
  }
}

///|
fn native_services_logs(cli : Cli) -> @host.TelemetrySession raise {
  @host.TelemetrySession::for_project(
    @platform.cwd(),
    values(cli, "log-file").get(0),
    enabled=true,
    kind="execution",
    format=value(cli, "log-format", fallback="ion-binary"),
  )
}

///|
fn catalog_command(cli : Cli, mode : OutputMode) -> Int32 {
  catalog_execute(cli, mode) catch {
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

///|
fn catalog_execute(cli : Cli, mode : OutputMode) -> Int32 raise {
  if !connected_supported() {
    raise @config.Invalid("native.runtime_unavailable")
  }
  let helper = value(
    cli,
    "services-helper",
    fallback=@platform.environment()
      .get("MORPHIR_NATIVE_SERVICES_HELPER")
      .unwrap_or(""),
  )
  if helper == "" {
    raise @config.Invalid("native.explicit_helper_required")
  }
  let pin_path = value(
    cli,
    "services-pin",
    fallback=@platform.environment()
      .get("MORPHIR_NATIVE_SERVICES_PIN")
      .unwrap_or(""),
  )
  if pin_path == "" {
    raise @config.Invalid("native.explicit_pin_required")
  }
  let host = native_services_host(
    @json.parse(@utf8.decode(@platform.read_input(pin_path, 65536)[:])),
  )
  let request : Map[String, Json] = Map([
    ("operation", Json::string(cli.command)),
  ])
  for
    option in [
      "path", "directory", "repository", "version", "executable", "sha256", "extension-id",
      "short-id", "platform",
    ] {
    let text = value(cli, option)
    if text != "" {
      request[option] = Json::string(text)
    }
  }
  let environment = @platform.environment()
  let default_home = environment
    .get("MORPHIR_HOME")
    .unwrap_or(
      environment
      .get("HOME")
      .unwrap_or(environment.get("USERPROFILE").unwrap_or(".")) +
      "/.morphir",
    )
  request["home"] = Json::string(
    @metadata_grants.host_path(
      value(cli, "home", fallback=default_home),
      @platform.cwd(),
      @platform.system_type(),
    ),
  )
  let output = if cli.command == "extension bundle" {
    extension_output(cli, Compile)
  } else {
    ""
  }
  let timeout = build_timeout(value(cli, "timeout", fallback="60000"))
  if timeout > 594000 {
    raise @config.Invalid("native.timeout_limit")
  }
  let root = @platform.temporary()
  errdefer extension_cleanup(root)
  let logs = native_services_logs(cli)
  errdefer logs.flush()
  @platform.mkdir(root + "/guest")
  // Repository roots and bundle inputs are absolute because the adapter has
  // an empty private working directory and no inherited user environment.
  for option in ["directory", "executable"] {
    if request.get(option) is Some(String(path)) {
      request[option] = Json::string(
        @metadata_grants.host_path(
          path,
          @platform.cwd(),
          @platform.system_type(),
        ),
      )
    }
  }
  if ["extension repository init", "extension repository publish"].contains(
      cli.command,
    ) &&
    request.get("path") is Some(String(path)) {
    request["path"] = Json::string(
      @metadata_grants.host_path(path, @platform.cwd(), @platform.system_type()),
    )
  }
  @platform.write(root + "/request.bin", Json::object(request).stringify())
  let control : Json = {
    "profile": "morphir/cli/native-services",
    "contractVersion": "0.1.0",
    "host": host,
    "requestFile": root + "/request.bin",
    "responseFile": root + "/response.bin",
    "workDirectory": root + "/guest",
    "timeout": timeout,
    "cancelFile": value(cli, "cancel-file"),
  }
  @platform.interruption_start()
  defer @platform.interruption_stop()
  extension_dispatch(
    helper,
    control,
    root,
    value(cli, "node", fallback="node"),
    timeout,
    fn(reply) {
      let mut status = 1
      let mut result = Json::null()
      let mut error = "native.invalid_helper_reply"
      try {
        guard @json.parse(reply) is Object(process) else {
          raise @config.Invalid(error)
        }
        if process.get("state") == Some(Json::string("cancelled")) {
          status = 130
        }
        if process.get("stderr") is Some(String(stderr)) && stderr != "" {
          @platform.stderr(stderr)
        }
        guard process.get("state") == Some(Json::string("exited")) &&
          process.get("workDirectoryEmpty") == Some(Json::boolean(true)) else {
          error = process
            .get("error")
            .unwrap_or(Json::string("native.cleanup_failed"))
            .stringify()
          raise @config.Invalid(error)
        }
        let response = @json.parse(
          @utf8.decode(
            @platform.read_input(root + "/response.bin", 16777216)[:],
          ),
        )
        guard response is Object(service) &&
          service.get("state") == Some(Json::string("succeeded")) &&
          service.get("result") is Some(value) else {
          error = response.stringify()
          raise @config.Invalid(error)
        }
        result = if output == "" {
          value
        } else {
          let files = extension_artifacts(value)
          let descriptor = match value {
            Object(fields) => fields.get("descriptor").unwrap_or(Json::null())
            _ => Json::null()
          }
          {
            "bundle": { "descriptor": descriptor },
            "outputDirectory": output,
            "files": extension_publish(output, files),
          }
        }
        status = 0
      } catch {
        cause =>
          if error == "native.invalid_helper_reply" {
            error = @host.error_message(cause)
          }
      }
      if !native_services_cleanup(root, logs) {
        status = 1
        error = "native.scratch_cleanup_failed"
      }
      logs.flush()
      if status != 0 {
        @platform.stderr(error + "\n")
      }
      native_services_emit(
        native_services_report(cli.command, result, error, status),
        mode,
      )
      status
    },
  )
}

///|
fn native_extension_params(plan : ExtensionPlan) -> (Json, Json) {
  fn params(id : Int32) -> Json {
    for message in plan.messages {
      if message is Object(fields) && fields.get("id") == Some(Json(id)) {
        return fields.get("params").unwrap_or(Json::null())
      }
    }
    Json::null()
  }

  (params(2), params(3))
}

///|
fn native_extension_command(
  cli : Cli,
  mode : OutputMode,
  pin : Json,
  helper : String,
  operation : ExtensionOperation,
) -> Int32 raise {
  guard pin is Object(fields) &&
    fields.length() == 5 &&
    fields.get("contractVersion") == Some(Json::string("0.1.0")) &&
    fields.get("binding") == Some(Json::string("native-process")) &&
    fields.get("host") is Some(host) &&
    fields.get("artifact") is Some(Object(artifact)) &&
    (
      artifact.length() == 4 ||
      (artifact.length() == 5 && artifact.get("args") is Some(Array(_)))
    ) else {
    raise @config.Invalid("native.invalid_pin")
  }
  let host = native_services_host(host)
  ignore(extension_text(fields, "origin"))
  ignore(extension_path(artifact, "executable"))
  ignore(extension_digest(artifact, "sha256"))
  ignore(extension_text(artifact, "extensionId"))
  ignore(extension_text(artifact, "version"))
  let plan = extension_plan(cli, operation)
  let (initialize, params) = native_extension_params(plan)
  let timeout = build_timeout(value(cli, "timeout", fallback="60000"))
  if timeout > 594000 {
    raise @config.Invalid("native.timeout_limit")
  }
  let root = @platform.temporary()
  errdefer extension_cleanup(root)
  let logs = native_services_logs(cli)
  errdefer logs.flush()
  @platform.mkdir(root + "/guest")
  @platform.write(
    root + "/request.bin",
    (
      {
        "operation": operation.name(),
        "pin": pin,
        "initialize": initialize,
        "params": params,
        "timeout": timeout,
        "workDirectory": root + "/guest",
      } : Json).stringify(),
  )
  let control : Json = {
    "profile": "morphir/cli/native-services",
    "contractVersion": "0.1.0",
    "host": host,
    "requestFile": root + "/request.bin",
    "responseFile": root + "/response.bin",
    "workDirectory": root + "/guest",
    "timeout": timeout,
    "cancelFile": value(cli, "cancel-file"),
  }
  @platform.interruption_start()
  defer @platform.interruption_stop()
  extension_dispatch(
    helper,
    control,
    root,
    value(cli, "node", fallback="node"),
    timeout,
    fn(reply) {
      let mut status = 1
      let mut result = Json::null()
      let mut diagnostics = Json::array([])
      let mut error = "native.invalid_helper_reply"
      try {
        guard @json.parse(reply) is Object(process) else {
          raise @config.Invalid(error)
        }
        if process.get("state") == Some(Json::string("cancelled")) {
          status = 130
        }
        if process.get("stderr") is Some(String(stderr)) && stderr != "" {
          @platform.stderr(stderr)
        }
        guard process.get("state") == Some(Json::string("exited")) &&
          process.get("workDirectoryEmpty") == Some(Json::boolean(true)) else {
          error = process
            .get("error")
            .unwrap_or(Json::string("native.cleanup_failed"))
            .stringify()
          raise @config.Invalid(error)
        }
        let response = @json.parse(
          @utf8.decode(
            @platform.read_input(root + "/response.bin", 16777216)[:],
          ),
        )
        guard response is Object(service) &&
          service.get("state") == Some(Json::string("succeeded")) &&
          service.get("result") is Some(Object(native)) else {
          error = response.stringify()
          raise @config.Invalid(error)
        }
        let native_result = native.get("result").unwrap_or(Json::null())
        if native_result is Object(fields) {
          diagnostics = fields.get("diagnostics").unwrap_or(Json::array([]))
        }
        for diagnostic in extension_diagnostics(native_result) {
          @platform.stderr(diagnostic + "\n")
        }
        if !(operation is Describe) {
          guard native_result is Object(operation_result) &&
            operation_result.get("success") == Some(Json::boolean(true)) else {
            error = "native.operation_unsuccessful: " +
              native_result.stringify()
            raise @config.Invalid(error)
          }
        }
        let outcome : ExtensionOutcome = {
          state: "completed",
          exit_code: 0,
          error: "",
          extension: native.get("extension").unwrap_or(Json::null()),
          negotiated: native.get("negotiated").unwrap_or(Json::null()),
          result: native_result,
          shutdown: "acknowledged",
        }
        let outputs = extension_files(plan, outcome)
        let receipts = if outputs.is_empty() {
          []
        } else {
          extension_publish(plan.output, outputs)
        }
        result = {
          "binding": pin,
          "session": Json::object(native),
          "outputs": receipts,
          "outputDirectory": plan.output,
          "lifecycle": {
            "shutdown": native.get("shutdown").unwrap_or(Json::null()),
            "processGroup": "stopped",
            "workDirectoryEmpty": true,
          },
          "access": {
            "fileLogging": true,
            "sandbox": "not-enforced",
            "wireCancellation": false,
            "hostCancellation": "process-group termination",
          },
        }
        status = 0
      } catch {
        cause =>
          if error == "native.invalid_helper_reply" {
            error = @host.error_message(cause)
          }
      }
      if !native_services_cleanup(root, logs) {
        status = 1
        error = "native.scratch_cleanup_failed"
      }
      logs.flush()
      if status != 0 {
        @platform.stderr(error + "\n")
      }
      native_services_emit(
        native_services_report(cli.command, result, error, status, diagnostics~),
        mode,
      )
      status
    },
  )
}
