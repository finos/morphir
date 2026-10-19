///|
fn connected_command(cli : Cli, mode : OutputMode) -> Int32 raise {
  if value(cli, "provider") != "workbench-http" {
    raise @config.Invalid("connected.explicit_provider_required")
  }
  if !connected_supported() {
    raise @config.Invalid("connected.runtime_unavailable")
  }
  let path = value(cli, "path")
  let connection = value(cli, "connection")
  let helper = value(
    cli,
    "connected-helper",
    fallback=@platform.environment()
      .get("MORPHIR_CONNECTED_HELPER")
      .unwrap_or(""),
  )
  if path == "" || connection == "" || helper == "" {
    raise @config.Invalid("connected.explicit_inputs_required")
  }
  let timeout = build_timeout(value(cli, "timeout", fallback="120000"))
  @platform.interruption_start()
  defer @platform.interruption_stop()
  let bytes = @platform.read_input(path, 1048576)
  let source = @utf8.decode(bytes[:]) catch {
    _ => raise @config.Invalid("connected.input_unavailable")
  }
  let config : Json = {
    "profile": "morphir/cli/connected-command",
    "contractVersion": "0.1.0",
    "operation": if cli.command == "connected connect" {
      "connect"
    } else {
      "run"
    },
    "binding": "workbench-http",
    "connectionScope": value(cli, "connection-scope", fallback="executions"),
    "source": source,
    "connection": connection,
    "timeout": timeout,
    "cancelFile": value(cli, "cancel-file"),
  }
  connected_dispatch(
    helper,
    config,
    timeout,
    value(cli, "node", fallback="node"),
    mode,
  )
}

///|
#cfg(target="js")
fn connected_supported() -> Bool {
  true
}

///|
#cfg(target="native")
fn connected_supported() -> Bool {
  @platform.system_type() != "windows"
}

///|
#cfg(any(target="wasm", target="wasm-gc"))
fn connected_supported() -> Bool {
  false
}

///|
#cfg(target="js")
extern "js" fn connected_start(
  helper : String,
  config : String,
  core : (String) -> String,
  interrupted : () -> Bool,
  mode : Int32,
) -> Unit =
  #| (helper, config, core, interrupted, mode) => {
  #|   const emit = report => console.log(JSON.stringify(mode === 2 ? {type:'result',data:report} : report));
  #|   let invoked = false;
  #|   import('node:url').then(({pathToFileURL}) => import(pathToFileURL(helper).href))
  #|     .then(module => { invoked = true; return module.connectedCommand(JSON.parse(config), core, interrupted); })
  #|     .then(({code,report}) => { emit(report); process.exitCode = code; })
  #|     .catch(() => { let view; try { view = JSON.parse(core(JSON.stringify({op:'view'}))); } catch {} emit({profile:'morphir/cli/connected-command',contractVersion:'0.1.0',observation:invoked?'helper-lost':'refused',error:'connected.helper_unavailable',execution:view?.ok?view.execution:null,result:view?.ok?view.result:null,release:invoked?'unknown':'not-requested'}); process.exitCode = invoked ? 1 : 2; });
  #| }

///|
#cfg(target="js")
fn connected_dispatch(
  helper : String,
  config : Json,
  _timeout : Int32,
  _node : String,
  mode : OutputMode,
) -> Int32 {
  let core = @connected_core.Client::new()
  connected_start(
    helper,
    config.stringify(),
    source => core.handle(source).stringify(),
    @platform.interruption_requested,
    if mode is JSONLines {
      2
    } else {
      1
    },
  )
  0
}

///|
#cfg(target="native")
fn connected_dispatch(
  helper : String,
  config : Json,
  timeout : Int32,
  node : String,
  mode : OutputMode,
) -> Int32 raise {
  let root = @platform.temporary()
  defer @platform.remove_dir(root)
  let path = root + "/connected.json"
  @platform.write(path, config.stringify())
  defer @platform.remove_file(path)
  let result = @platform.process(
    node,
    [helper, "--morphir-connected-v1", path],
    @platform.cwd(),
    "",
    timeout + 5000,
  ) catch {
    _ => return connected_helper_lost(mode)
  }
  guard result is Object(fields) &&
    fields.get("stdout") is Some(String(source)) &&
    fields.get("exitCode") is Some(Number(number, ..)) else {
    return connected_helper_lost(mode)
  }
  if source.length() > 3145728 || @utf8.encode(source).length() > 3145728 {
    return connected_helper_lost(mode)
  }
  let report = @json.parse(source) catch {
    _ => return connected_helper_lost(mode)
  }
  guard report is Object(reply) &&
    reply.get("profile") == Some(Json::string("morphir/cli/connected-command")) &&
    reply.get("contractVersion") == Some(Json::string("0.1.0")) &&
    [0.0, 1.0, 2.0, 130.0].contains(number) else {
    return connected_helper_lost(mode)
  }
  if mode is JSONLines {
    emit_record("result", report)
  } else {
    println(report.stringify())
  }
  number.to_int()
}

///|
#cfg(any(target="wasm", target="wasm-gc"))
fn connected_dispatch(
  _helper : String,
  _config : Json,
  _timeout : Int32,
  _node : String,
  _mode : OutputMode,
) -> Int32 raise {
  raise @config.Invalid("connected.runtime_unavailable")
}

///|
#cfg(target="native")
fn connected_helper_lost(mode : OutputMode) -> Int32 {
  let report : Json = {
    "profile": "morphir/cli/connected-command",
    "contractVersion": "0.1.0",
    "binding": "workbench-http",
    "observation": "helper-lost",
    "execution": Json::null(),
    "result": Json::null(),
    "release": "unknown",
    "error": "connected.helper_lost",
  }
  if mode is JSONLines {
    emit_record("result", report)
  } else {
    println(report.stringify())
  }
  1
}
