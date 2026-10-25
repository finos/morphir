///|
priv struct OriginalsControl {
  deadline : Double
  cancel_file : String
}

///|
/// The native adapter constructs this value. Pure targets keep the shared type.
#warnings("-struct_never_constructed")
priv struct OriginalsObservation {
  commit : (String, Bool) -> Unit
  cleanup : (String, Bool) -> Unit
}

///|
fn originals_check(control : OriginalsControl) -> Unit raise {
  if @platform.interruption_requested() ||
    (control.cancel_file != "" && @platform.kind(control.cancel_file) != 0) {
    raise @platform.IOError("Cancelled")
  }
  if @platform.monotonic_seconds() >= control.deadline {
    raise @config.Invalid("originals.timeout")
  }
}

///|
fn originals_command(cli : Cli, mode : OutputMode) -> Int32 raise {
  if value(cli, "provider") != "workbench-http" {
    raise @config.Invalid("connected.explicit_provider_required")
  }
  if !connected_supported() {
    raise @config.Invalid("connected.runtime_unavailable")
  }
  let path = value(cli, "path")
  let helper = value(
    cli,
    "originals-helper",
    fallback=@platform.environment()
      .get("MORPHIR_ORIGINALS_HELPER")
      .unwrap_or(""),
  )
  let output = @workspace.normalize(value(cli, "output"))
  let listing = flag(cli, "list")
  if path == "" ||
    helper == "" ||
    value(cli, "connection") == "" ||
    (!listing && output == "") {
    raise @config.Invalid("originals.explicit_inputs_required")
  }
  if !listing && @platform.kind(@workspace.join(output, "originals")) != 0 {
    raise @config.Invalid("originals.output_exists")
  }
  let timeout = build_timeout(value(cli, "timeout", fallback="120000"))
  let control = {
    deadline: @platform.monotonic_seconds() + timeout.to_double() / 1000.0,
    cancel_file: value(cli, "cancel-file"),
  }
  @platform.interruption_start()
  defer @platform.interruption_stop()
  let source = @utf8.decode(@platform.read_input(path, 1048576)[:])
  let scratch = @platform.temporary()
  let config : Json = {
    "profile": "morphir/cli/originals-command",
    "contractVersion": "0.1.0",
    "operation": if listing {
      "list"
    } else {
      "originals"
    },
    "source": source,
    "connection": value(cli, "connection"),
    "scratch": scratch,
    "timeout": timeout,
    "cancelFile": value(cli, "cancel-file"),
  }
  originals_dispatch(
    helper,
    config,
    scratch,
    output,
    timeout,
    value(cli, "node", fallback="node"),
    mode,
    control,
  )
}

///|
fn originals_publish(
  report : Json,
  scratch : String,
  output : String,
  control : OriginalsControl,
  observation : OriginalsObservation?,
) -> Json raise {
  originals_check(control)
  guard report is Object(fields) &&
    fields.get("observation") == Some(Json::string("verified")) &&
    fields.get("cleanup") == Some(({ "kind": "released" } : Json)) else {
    raise @config.Invalid("originals.unverified_transfer")
  }
  let metadata = @json.parse(
    @utf8.decode(
      originals_read(scratch + "/inventory.json", 67108864, control)[:],
    ),
  )
  guard metadata
    is { "capture": Object(capture), "entries": Array(entries), .. } &&
    entries.length() <= 100064 &&
    capture.get("sha256") == fields.get("inventorySha256") &&
    capture.get("fileCount") == fields.get("fileCount") &&
    capture.get("directoryCount") == fields.get("directoryCount") &&
    capture.get("sourceByteLength") == fields.get("sourceByteLength") else {
    raise @config.Invalid("originals.invalid_inventory")
  }
  let files : Array[(Int32, String, Int32, String)] = []
  let directories : Array[String] = []
  let mut total = 0
  for index, item in entries {
    originals_check(control)
    match item {
      { "kind": String("directory"), "path": String(path), .. } =>
        directories.push(path)
      {
        "kind": String("file"),
        "path": String(path),
        "byteLength": Number(length, ..),
        "sha256": String(digest),
        ..
      } => {
        if length < 0.0 ||
          length > 67108864.0 ||
          length != length.to_int().to_double() ||
          length.to_int() > 67108864 - total {
          raise @config.Invalid("originals.invalid_inventory")
        }
        total += length.to_int()
        files.push((index, path, length.to_int(), digest))
      }
      _ => raise @config.Invalid("originals.invalid_inventory")
    }
  }
  if capture.get("fileCount") != Some(Json::number(files.length().to_double())) ||
    capture.get("directoryCount") !=
    Some(Json::number(directories.length().to_double())) ||
    capture.get("sourceByteLength") != Some(Json::number(total.to_double())) {
    raise @config.Invalid("originals.invalid_inventory")
  }
  @model_document.validate_inventory_paths(
    files.map(file => file.1),
    directories,
    profile=@model_document.InventoryPathProfile::Connected,
  )
  let destination = @workspace.join(output, "originals")
  let publisher = @host.ContentPublisher::filesystem_inventory(
    @platform.cwd(),
    output,
    directories.map(path => @workspace.join(destination, path)),
    destination_policy=@host.DestinationPolicy::Create,
  )
  let transaction = (publisher.begin)([destination])
  defer (transaction.abort)()
  if @platform.kind(destination) != 0 {
    raise @config.Invalid("originals.output_exists")
  }
  // Stage privately. No accepted prefix is published if any later file fails.
  for (index, path, length, digest) in files {
    originals_check(control)
    let bytes = originals_read(
      scratch +
      "/part-" +
      (index / 65536).to_string() +
      "/file-" +
      index.to_string(),
      if length == 0 {
        1
      } else {
        length
      },
      control,
    )
    let observed = @crypto.SHA256::new()
    observed.update(bytes)
    if bytes.length() != length ||
      @crypto.bytes_to_hex_string(observed.finalize()) != digest {
      raise @config.Invalid("originals.inventory_integrity")
    }
    (transaction.stage)({
      path: @workspace.join(destination, path),
      source: "connected-model-original",
      format: "original-bytes",
      content: @data.Binary(bytes),
    })
  }
  originals_check(control)
  {
    errdefer (if observation is Some(observer) {
      (observer.commit)(destination, false)
    })
    (transaction.commit)(destination)
  }
  if observation is Some(observer) {
    (observer.commit)(destination, true)
  }
  fields["observation"] = Json::string("published")
  fields["publication"] = Json::string("cli")
  fields["representation"] = Json::string("original-bytes")
  fields["published"] = Json::array([Json::string(destination)])
  fields["sourceFormatVersion"] = capture
    .get("sourceFormatVersion")
    .unwrap_or(Json::null())
  report
}

///|
fn originals_read(
  path : String,
  limit : Int32,
  control : OriginalsControl,
) -> Bytes raise {
  let buffer = Buffer()
  @platform.file_chunks(path, limit, fn(bytes) raise {
    originals_check(control)
    if bytes.length() > limit - buffer.length() {
      raise @config.Invalid("originals.byte_limit")
    }
    buffer.write_bytes(bytes[:])
  })
  buffer.to_bytes()
}

///|
fn originals_cleanup(scratch : String) -> Unit raise {
  let count_path = scratch + "/cleanup-count"
  let count = if @platform.kind(count_path) == 0 {
    0
  } else {
    let value = @json.parse(
      @utf8.decode(@platform.read_input(count_path, 6)[:]),
    )
    guard value is Number(number, ..) &&
      number >= 0.0 &&
      number <= 100064.0 &&
      number == number.to_int().to_double() else {
      raise @config.Invalid("originals.invalid_cleanup_count")
    }
    number.to_int()
  }
  for index in 0..<count {
    let path = scratch +
      "/part-" +
      (index / 65536).to_string() +
      "/file-" +
      index.to_string()
    let kind = @platform.kind(path)
    if kind == 1 {
      @platform.remove_file(path)
    } else if kind != 0 {
      raise @config.Invalid("originals.unexpected_scratch_entry")
    }
  }
  for part in ["part-0", "part-1"] {
    let directory = scratch + "/" + part
    if @platform.kind(directory) == 2 {
      @platform.remove_dir(directory)
    }
  }
  for name in ["command.json", "inventory.json", "cleanup-count"] {
    let path = scratch + "/" + name
    if @platform.kind(path) != 0 {
      @platform.remove_file(path)
    }
  }
  @platform.remove_dir(scratch)
}

///|
/// Native and JS dispatchers use this shared completion path.
#warnings("-unused_value")
fn originals_finish(
  source : String,
  code : Int32,
  scratch : String,
  output : String,
  mode : OutputMode,
  control : OriginalsControl,
  observation : OriginalsObservation?,
) -> Int32 {
  let mut status = code
  let mut cleanup : Json = Json::string("unknown")
  let mut report = try {
    if source.length() > 1048576 ||
      @utf8.encode(source).length() > 1048576 ||
      ![0, 1, 2, 130].contains(code) {
      raise @config.Invalid("originals.helper_lost")
    }
    let report = @json.parse(source)
    guard report is Object(fields) &&
      fields.get("profile") ==
      Some(Json::string("morphir/cli/originals-command")) &&
      fields.get("contractVersion") == Some(Json::string("0.1.0")) else {
      raise @config.Invalid("originals.helper_lost")
    }
    cleanup = fields.get("cleanup").unwrap_or(Json::string("unknown"))
    if code == 0 && fields.get("operation") == Some(Json::string("originals")) {
      originals_publish(report, scratch, output, control, observation)
    } else if code != 0 ||
      fields.get("observation") == Some(Json::string("discovered")) {
      report
    } else {
      raise @config.Invalid("originals.invalid_helper_result")
    }
  } catch {
    error => {
      let message = @host.error_message(error)
      status = if message == "Cancelled" { 130 } else { 1 }
      (
        {
          "profile": "morphir/cli/originals-command",
          "contractVersion": "0.1.0",
          "observation": "not-published",
          "error": message,
          "cleanup": cleanup,
        } : Json)
    }
  }
  try {
    originals_cleanup(scratch)
    if observation is Some(observer) {
      (observer.cleanup)(scratch, true)
    }
  } catch {
    _ => {
      if observation is Some(observer) {
        (observer.cleanup)(scratch, false)
      }
      status = 1
      report = {
        "profile": "morphir/cli/originals-command",
        "contractVersion": "0.1.0",
        "observation": "cleanup-unconfirmed",
        "result": report,
        "error": "originals.scratch_cleanup_failed",
      }
    }
  }
  if mode is JSONLines {
    emit_record("result", report)
  } else {
    println(report.stringify())
  }
  status
}

///|
#cfg(target="js")
extern "js" fn originals_start(
  helper : String,
  config : String,
  core : (String) -> String,
  interrupted : () -> Bool,
  finish : (String, Int32, (String, String, Bool) -> Unit) -> Int32,
) -> Unit =
  #| (helper,config,core,interrupted,finish)=>{
  #|   const noop=()=>{};
  #|   import('node:url').then(({pathToFileURL})=>import(pathToFileURL(helper).href))
  #|     .then(async module=>{
  #|       const input=JSON.parse(config);
  #|       const owner=input.operation==='originals'?module.openOriginalsOuterObservation?.():undefined;
  #|       const observe=(kind,path,returned)=>{try{
  #|         owner?.emit(()=>{
  #|           const fact={kind,path:{kind:'unix-bytes',bytes:{kind:'hex',hex:Buffer.from(path,'utf8').toString('hex')}},outcome:returned?'returned':'raised'};
  #|           if(kind==='destination-commit-finished')fact.policy='create';
  #|           return fact;
  #|         });
  #|       }catch{}};
  #|       try{
  #|         let value;try{value=await module.originalsCommand(input,core,interrupted);}catch{value={code:1,report:null};}
  #|         process.exitCode=finish(value.report===null?'':JSON.stringify(value.report),value.code,observe);
  #|       }finally{owner?.finish({kind:'in-process'});}
  #|     }).catch(()=>{process.exitCode=finish('',1,noop);});
  #| }

///|
#cfg(target="js")
fn originals_dispatch(
  helper : String,
  config : Json,
  scratch : String,
  output : String,
  _timeout : Int32,
  _node : String,
  mode : OutputMode,
  control : OriginalsControl,
) -> Int32 {
  let core = @connected_core.Client::new()
  originals_start(
    helper,
    config.stringify(),
    source => core.handle(source).stringify(),
    @platform.interruption_requested,
    (source, code, observe) => {
      originals_finish(
        source,
        code,
        scratch,
        output,
        mode,
        control,
        Some({
          commit: (path, returned) => {
            observe("destination-commit-finished", path, returned)
          },
          cleanup: (path, returned) => {
            observe("scratch-cleanup-finished", path, returned)
          },
        }),
      )
    },
  )
  0
}

///|
#cfg(target="native")
fn originals_dispatch(
  helper : String,
  config : Json,
  scratch : String,
  output : String,
  timeout : Int32,
  node : String,
  mode : OutputMode,
  control : OriginalsControl,
) -> Int32 {
  let owner = if config is { "operation": String("originals"), .. } {
    Some(@platform.originals_observer_start())
  } else {
    None
  }
  defer (if owner is Some(observer) { observer.finish() })
  let observation = owner.map(observer => OriginalsObservation::{
    commit: (path, returned) => observer.commit(path, returned),
    cleanup: (path, returned) => observer.cleanup(path, returned),
  })
  let result = try {
    let path = scratch + "/command.json"
    @platform.write(path, config.stringify())
    let args = [helper, "--morphir-originals-v1", path]
    let result = match owner {
      Some(observer) =>
        observer.process(node, args, @platform.cwd(), "", timeout + 5000)
      None => @platform.process(node, args, @platform.cwd(), "", timeout + 5000)
    }
    guard result
      is { "stdout": String(source), "exitCode": Number(number, ..), .. } else {
      raise @config.Invalid("originals.helper_lost")
    }
    (source, number.to_int())
  } catch {
    _ => ("", 1)
  }
  originals_finish(
    result.0,
    result.1,
    scratch,
    output,
    mode,
    control,
    observation,
  )
}

///|
#cfg(any(target="wasm", target="wasm-gc"))
fn originals_dispatch(
  _helper : String,
  _config : Json,
  _scratch : String,
  _output : String,
  _timeout : Int32,
  _node : String,
  _mode : OutputMode,
  _control : OriginalsControl,
) -> Int32 raise {
  raise @config.Invalid("connected.runtime_unavailable")
}
