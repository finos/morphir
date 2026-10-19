///|
fn transfer_command(cli : Cli, mode : OutputMode) -> Int32 raise {
  if value(cli, "provider") != "workbench-http" {
    raise @config.Invalid("connected.explicit_provider_required")
  }
  if !connected_supported() {
    raise @config.Invalid("connected.runtime_unavailable")
  }
  let path = value(cli, "path")
  let helper = value(
    cli,
    "transfer-helper",
    fallback=@platform.environment()
      .get("MORPHIR_TRANSFER_HELPER")
      .unwrap_or(""),
  )
  let output = @workspace.normalize(value(cli, "output"))
  let connection = value(cli, "connection")
  if path == "" || helper == "" || output == "" || connection == "" {
    raise @config.Invalid("transfer.explicit_inputs_required")
  }
  let destination = @workspace.join(output, "artifacts")
  if @platform.kind(destination) != 0 {
    raise @config.Invalid("transfer.output_exists")
  }
  let timeout = build_timeout(value(cli, "timeout", fallback="120000"))
  @platform.interruption_start()
  defer @platform.interruption_stop()
  let source = @utf8.decode(@platform.read_input(path, 1048576)[:]) catch {
    _ => raise @config.Invalid("transfer.invalid_input")
  }
  let scratch = @platform.temporary()
  let config : Json = {
    "profile": "morphir/cli/transfer-command",
    "contractVersion": "0.1.0",
    "binding": "workbench-http",
    "operation": "artifacts",
    "source": source,
    "connection": connection,
    "scratch": scratch,
    "timeout": timeout,
    "cancelFile": value(cli, "cancel-file"),
  }
  transfer_dispatch(
    helper,
    config,
    scratch,
    output,
    timeout,
    value(cli, "node", fallback="node"),
    mode,
  )
}

///|
priv struct TransferFile {
  path : String
  bytes : Bytes
  digest : String
}

///|
fn transfer_publish(
  report : Json,
  scratch : String,
  output : String,
) -> Json raise {
  guard report is Object(fields) &&
    fields.get("observation") == Some(Json::string("verified")) &&
    fields.get("cleanup") is Some({ "kind": String("released"), .. }) &&
    fields.get("files") is Some(Array(inventory)) &&
    inventory.length() <= 256 else {
    raise @config.Invalid("transfer.invalid_inventory")
  }
  let entries : Array[(String, Int32, String)] = []
  let mut total = 0
  for entry in inventory {
    if @platform.interruption_requested() {
      raise @platform.IOError("Cancelled")
    }
    guard entry
      is {
        "path": String(path),
        "byteLength": Number(length, ..),
        "sha256": String(digest),
        ..
      } &&
      length >= 0.0 &&
      length <= 16777216.0 &&
      length == length.to_int().to_double() else {
      raise @config.Invalid("transfer.invalid_inventory")
    }
    if length.to_int() > 67108864 - total {
      raise @config.Invalid("transfer.inventory_limit")
    }
    total += length.to_int()
    entries.push((path, length.to_int(), digest))
  }
  @model_document.validate_inventory_paths(entries.map(entry => entry.0), [])
  let files : Array[TransferFile] = []
  for index, (path, length, digest) in entries {
    if @platform.interruption_requested() {
      raise @platform.IOError("Cancelled")
    }
    let bytes = @platform.read_input(
      scratch + "/file-" + index.to_string(),
      if length == 0 {
        1
      } else {
        length
      },
    )
    if bytes.length() != length || @identity.sha256(bytes) != digest {
      raise @config.Invalid("transfer.inventory_integrity")
    }
    files.push({ path, bytes, digest, })
  }
  let destination = @workspace.join(output, "artifacts")
  let publisher = @host.ContentPublisher::filesystem_inventory(
    @platform.cwd(),
    output,
    [],
  )
  let transaction = (publisher.begin)([destination])
  defer (transaction.abort)()
  // The publisher lock closes the race between preflight and publication.
  if @platform.kind(destination) != 0 {
    raise @config.Invalid("transfer.output_exists")
  }
  for file in files {
    if @platform.interruption_requested() {
      raise @platform.IOError("Cancelled")
    }
    (transaction.stage)({
      path: @workspace.join(destination, file.path),
      source: "connected-artifact",
      format: "verified-bytes",
      content: @data.Binary(file.bytes),
    })
  }
  if @platform.interruption_requested() {
    raise @platform.IOError("Cancelled")
  }
  (transaction.commit)(destination)
  {
    "profile": "morphir/cli/transfer-command",
    "contractVersion": "0.1.0",
    "binding": "workbench-http",
    "operation": "artifacts",
    "observation": "published",
    "publication": "cli",
    "published": [destination],
    "cleanup": fields["cleanup"],
    "files": files.map(file => {
      (
        {
          "path": file.path,
          "byteLength": file.bytes.length(),
          "sha256": file.digest,
        } : Json)
    }),
  }
}

///|
fn transfer_cleanup(scratch : String) -> Unit raise {
  // Cleanup must work after interruption; bounded directory capture deliberately
  // refuses interrupted requests. Only these fixed, private helper files exist.
  for index in 0..<256 {
    let path = scratch + "/file-" + index.to_string()
    if @platform.kind(path) != 0 {
      @platform.remove_file(path)
    }
  }
  let command = scratch + "/command.json"
  if @platform.kind(command) != 0 {
    @platform.remove_file(command)
  }
  @platform.remove_dir(scratch)
}

///|
fn transfer_finish(
  source : String,
  code : Int32,
  scratch : String,
  output : String,
  mode : OutputMode,
) -> Int32 {
  let mut exit_code = code
  let mut cleanup : Json = Json::string("unknown")
  let mut report = try {
    if source.length() > 1048576 ||
      @utf8.encode(source).length() > 1048576 ||
      ![0, 1, 2, 130].contains(code) {
      raise @config.Invalid("transfer.helper_lost")
    }
    let report = @json.parse(source)
    guard report
      is {
        "profile": String("morphir/cli/transfer-command"),
        "contractVersion": String("0.1.0"),
        "binding": String("workbench-http"),
        "operation": String("artifacts"),
        ..
      } else {
      raise @config.Invalid("transfer.helper_lost")
    }
    if report is Object(reply) {
      cleanup = reply.get("cleanup").unwrap_or(Json::string("unknown"))
    }
    if code == 0 {
      transfer_publish(report, scratch, output)
    } else {
      report
    }
  } catch {
    error => {
      let message = @host.error_message(error)
      exit_code = if message == "Cancelled" { 130 } else { 1 }
      (
        {
          "profile": "morphir/cli/transfer-command",
          "contractVersion": "0.1.0",
          "observation": "not-published",
          "error": message,
          "cleanup": cleanup,
        } : Json)
    }
  }
  transfer_cleanup(scratch) catch {
    _ => {
      exit_code = 1
      report = {
        "profile": "morphir/cli/transfer-command",
        "contractVersion": "0.1.0",
        "observation": "cleanup-unconfirmed",
        "result": report,
        "error": "transfer.scratch_cleanup_failed",
      }
    }
  }
  if mode is JSONLines {
    emit_record("result", report)
  } else {
    println(report.stringify())
  }
  exit_code
}

///|
#cfg(target="js")
extern "js" fn transfer_start(
  helper : String,
  config : String,
  core : (String) -> String,
  interrupted : () -> Bool,
  finish : (String, Int32) -> Int32,
) -> Unit =
  #| (helper,config,core,interrupted,finish) => {
  #|   let invoked=false;
  #|   import('node:url').then(({pathToFileURL})=>import(pathToFileURL(helper).href))
  #|     .then(module=>{invoked=true;return module.transferCommand(JSON.parse(config),core,interrupted);})
  #|     .then(({code,report})=>{process.exitCode=finish(JSON.stringify(report),code);})
  #|     .catch(()=>{process.exitCode=finish(JSON.stringify({profile:'morphir/cli/transfer-command',contractVersion:'0.1.0',binding:'workbench-http',operation:'artifacts',observation:invoked?'helper-lost':'refused',error:'transfer.helper_unavailable',cleanup:'unknown'}),invoked?1:2);});
  #| }

///|
#cfg(target="js")
fn transfer_dispatch(
  helper : String,
  config : Json,
  scratch : String,
  output : String,
  _timeout : Int32,
  _node : String,
  mode : OutputMode,
) -> Int32 {
  let core = @connected_core.Client::new()
  transfer_start(
    helper,
    config.stringify(),
    source => core.handle(source).stringify(),
    @platform.interruption_requested,
    (source, code) => transfer_finish(source, code, scratch, output, mode),
  )
  0
}

///|
#cfg(target="native")
fn transfer_dispatch(
  helper : String,
  config : Json,
  scratch : String,
  output : String,
  timeout : Int32,
  node : String,
  mode : OutputMode,
) -> Int32 {
  let result = try {
    let path = scratch + "/command.json"
    @platform.write(path, config.stringify())
    let result = @platform.process(
      node,
      [helper, "--morphir-transfer-v1", path],
      @platform.cwd(),
      "",
      timeout + 5000,
    )
    guard result
      is { "stdout": String(source), "exitCode": Number(number, ..), .. } else {
      raise @config.Invalid("transfer.helper_lost")
    }
    (source, number.to_int())
  } catch {
    _ => ("", 1)
  }
  transfer_finish(result.0, result.1, scratch, output, mode)
}

///|
#cfg(any(target="wasm", target="wasm-gc"))
fn transfer_dispatch(
  _helper : String,
  _config : Json,
  _scratch : String,
  _output : String,
  _timeout : Int32,
  _node : String,
  _mode : OutputMode,
) -> Int32 raise {
  raise @config.Invalid("connected.runtime_unavailable")
}
