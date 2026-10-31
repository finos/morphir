///|
let native_services_revision : String = "fc9f723a2cf0adae1299892c6cc4bee5ebcf4560"

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
fn extension_sha256(bytes : Bytes) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
/// Strips trailing separators and refuses an output path that exists, or
/// whose staging directory exists. The message names the path that exists.
fn fresh_output(text : String) -> String raise {
  let mut output = text
  while output.length() > 1 &&
        (output.has_suffix("/") || output.has_suffix("\\")) {
    output = output[:output.length() - 1].to_owned()
  }
  if @platform.kind(output) != 0 {
    raise @config.Invalid("the output path \{output} exists")
  }
  let staging = output + ".morphir-partial"
  if @platform.kind(staging) != 0 {
    raise @config.Invalid(
      "the staging directory \{staging} of an earlier run exists; remove it",
    )
  }
  output
}

///|
/// The key that two artifact paths share when a file system may treat them
/// as one name: NFC-normalized and case-folded, then normalized again, since
/// case folding can leave a string that is not in NFC.
fn extension_path_key(path : String) -> String {
  @normalization.nfc(@casefold.casefold(@normalization.nfc(path)))
}

///|
/// Generated paths are relative, slash-separated and confined to the output.
/// Two paths that differ only by case or by Unicode normalization collide, as
/// does a file whose name is also a directory of another artifact.
fn extension_artifacts(result : Json) -> Array[(String, Bytes)] raise {
  let invalid = (message : String) => {
    @config.Invalid("extension.invalid_artifacts: " + message)
  }
  guard result is Object(fields) &&
    fields.get("artifacts") is Some(Array(artifacts)) &&
    artifacts.length() <= 10000 else {
    raise invalid("the generate result has no list of at most 10000 artifacts")
  }
  // The key of each file and of each directory that the files need.
  let file_keys : Map[String, String] = Map([])
  let directory_keys : Map[String, String] = Map([])
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
      (binary == Json::boolean(true) || binary == Json::boolean(false)) else {
      raise invalid("an artifact has an unsafe or incomplete entry")
    }
    let key = extension_path_key(path)
    if file_keys.get(key) is Some(other) {
      raise invalid(
        "the artifacts \{other} and \{path} collide by case or Unicode normalization",
      )
    }
    file_keys[key] = path
    let parts = key.split("/").map(part => part.to_owned()).to_array()
    for index in 1..<parts.length() {
      let directory = parts[:index].join("/")
      if !directory_keys.contains(directory) {
        directory_keys[directory] = path
      }
    }
    let bytes = if binary == Json::boolean(true) {
      @base64.decode(content) catch {
        _ => raise invalid("the artifact \{path} is not base64")
      }
    } else {
      @utf8.encode(content)
    }
    files.push((path, bytes))
  }
  // A file cannot also be a directory of another artifact.
  for key, path in file_keys {
    if directory_keys.get(key) is Some(other) {
      raise invalid(
        "the artifact \{path} is also a directory of the artifact \{other}",
      )
    }
  }
  files
}

///|
/// Writes into a sibling staging directory, then publishes it with a
/// no-replacement rename. A failure leaves no partial destination and no
/// staging directory: each path is recorded before it is created, so a
/// write that fails partway through is removed too.
fn extension_publish(
  output : String,
  files : Array[(String, Bytes)],
  check~ : () -> Unit raise = fn() {  },
  write~ : (String, Bytes) -> Unit raise = @platform.write_bytes,
) -> Array[Json] raise {
  check()
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
    check()
    let (path, bytes) = entry
    let parts = path.split("/").map(p => p.to_owned()).to_array()
    let mut parent = staging
    for i in 0..<(parts.length() - 1) {
      parent = parent + "/" + parts[i]
      if @platform.kind(parent) == 0 {
        directories.push(parent)
        @platform.mkdir(parent)
      }
    }
    created.push(staging + "/" + path)
    write(staging + "/" + path, bytes)
    receipts.push({
      "path": path,
      "bytes": bytes.length(),
      "sha256": extension_sha256(bytes),
    })
  }
  check()
  @platform.rename_directory_new(staging, output)
  receipts
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
    if value(cli, "output") == "" {
      raise @config.Invalid("extension.output_required")
    }
    fresh_output(value(cli, "output")) catch {
      @config.Invalid(message) =>
        raise @config.Invalid("extension.output_exists: " + message)
      error => raise error
    }
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
  let flush_logs = telemetry_flush(fn() { logs.flush() })
  errdefer flush_logs()
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
          status = cancellation_exit_code()
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
      flush_logs()
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
  started : (String) -> Unit,
) -> @js_async.Promise[Int32] =
  #| (helper, config, interrupted, finish, started) => {
  #|   const failed = JSON.stringify({profile:'morphir/cli/extension-command',contractVersion:'0.1.0-draft.1',state:'failed',exitCode:null,stderr:'',error:'extension.helper_unavailable',workDirectoryEmpty:false});
  #|   return import('node:url').then(({pathToFileURL})=>import(pathToFileURL(helper).href))
  #|     .then(module=>module.extensionCommand(JSON.parse(config),interrupted,started))
  #|     .then(reply=>JSON.stringify(reply),()=>failed)
  #|     .then(reply=>{process.exitCode=finish(reply); return process.exitCode;});
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
  remember_completion(
    extension_start(
      helper,
      control.stringify(),
      @platform.interruption_requested,
      finish,
      @platform.process_started,
    ),
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
