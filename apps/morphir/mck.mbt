///|
/// A qualified backend version, independent of the suites' contract versions.
enum MckRunnerVersion {
  Beta10
}

///|
struct MckRunnerPin {
  version : MckRunnerVersion
  executable : String
  sha256 : String
  source_revision : String
  origin : String
}

///|
fn mck_absolute(path : String) -> Bool {
  path.has_prefix("/") ||
  path.has_prefix("\\\\") ||
  (
    path.length() > 2 &&
    path[1] == 58 &&
    ((path[0] >= 65 && path[0] <= 90) || (path[0] >= 97 && path[0] <= 122)) &&
    (path[2] == 47 || path[2] == 92)
  )
}

///|
fn mck_hex(value : String, length : Int32) -> Bool {
  value.length() == length &&
  value.iter().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
}

///|
fn mck_pin(value : Json) -> MckRunnerPin raise {
  guard value is Object(fields) &&
    fields.length() == 6 &&
    fields.get("contractVersion") == Some(Json::string("0.1.0-draft.1")) &&
    fields.get("runnerVersion") is Some(String(version)) &&
    fields.get("executable") is Some(String(executable)) &&
    fields.get("sha256") is Some(String(sha256)) &&
    fields.get("sourceRevision") is Some(String(source_revision)) &&
    fields.get("origin") is Some(String(origin)) else {
    raise @config.Invalid("mck.invalid_runner_pin")
  }
  let version = match version {
    "0.4.0-beta.10" => Beta10
    _ => raise @config.Invalid("mck.unsupported_runner_version")
  }
  guard mck_absolute(executable) &&
    executable.length() <= 4096 &&
    !executable.contains("\u0000") &&
    mck_hex(sha256, 64) &&
    mck_hex(source_revision, 40) &&
    origin.length() > 0 &&
    origin.length() <= 2048 &&
    !origin.contains("\u0000") else {
    raise @config.Invalid("mck.invalid_runner_pin")
  }
  { version, executable, sha256, source_revision, origin, }
}

///|
fn MckRunnerPin::to_json(self : MckRunnerPin) -> Json {
  {
    "contractVersion": "0.1.0-draft.1",
    "runnerVersion": match self.version {
      Beta10 => "0.4.0-beta.10"
    },
    "executable": self.executable,
    "sha256": self.sha256,
    "sourceRevision": self.source_revision,
    "origin": self.origin,
  }
}

///|
/// Only the prefix belongs to this CLI. The canonical command and its complete
/// argv remain opaque, including help, repeated options, empty strings and --.
fn mck_cli(args : Array[String]) -> Cli? raise {
  let mut start = 0
  while start < args.length() &&
        ["--json", "--json-lines", "--help", "-h", "--no-banner"].contains(
          args[start],
        ) {
    start += 1
  }
  if start >= args.length() || args[start] != "mck" {
    return None
  }
  let end = mck_prefix_end(args, start + 1)
  let bootstrap = args[:end].to_owned().filter(arg => arg != "--no-banner")
  let cli = parse_cli_local(bootstrap)
  let offset = if end < args.length() && args[end] == "--" {
    end + 1
  } else {
    end
  }
  let forwarded = if offset < args.length() {
    Some(args[offset:].to_owned())
  } else {
    None
  }
  Some({ ..cli, forwarded, })
}

///|
/// Five Set options of arity one, no positionals and valueless flags can
/// consume at most five candidate tokens. The first valid boundary is therefore
/// among six candidates. ArrayViews avoid copying every attempted prefix.
/// Adding repeatable/multivalued options or positionals requires requalification.
fn mck_prefix_end(args : Array[String], start : Int32) -> Int32 raise {
  let syntax = mck_syntax_spec()
  let mut candidates = 0
  for end = start; end <= args.length(); end = end + 1 {
    if end < args.length() && args[end] != "--" && args[end].has_prefix("-") {
      continue
    }
    candidates += 1
    let valid = try {
      ignore(syntax.parse(argv=args[:end], env=Map([])))
      true
    } catch {
      _ => false
    }
    if valid {
      return end
    }
    if candidates >= command_schema("mck").options.length() + 1 {
      break
    }
  }
  // Request the library's diagnostic only after exhausting the syntax budget.
  ignore(syntax.parse(argv=args, env=Map([]))) catch {
    error => raise @config.Invalid(error.to_string())
  }
  raise @config.Invalid("mck.invalid_local_prefix")
}

///|
fn mck_command(cli : Cli, mode : OutputMode) -> Int32 raise {
  guard cli.forwarded is Some(arguments) && !arguments.is_empty() else {
    raise @config.Invalid("mck.command_required: " + render_help("mck"))
  }
  guard arguments.length() <= 1000 &&
    arguments.all(arg => !arg.contains("\u0000") && arg.length() <= 65536) else {
    raise @config.Invalid("mck.argument_limit")
  }
  if !connected_supported() {
    raise @config.Invalid("mck.runtime_unavailable")
  }
  let pin_path = value(
    cli,
    "runner-pin",
    fallback=@platform.environment().get("MORPHIR_MCK_PIN").unwrap_or(""),
  )
  let helper = value(
    cli,
    "mck-helper",
    fallback=@platform.environment().get("MORPHIR_MCK_HELPER").unwrap_or(""),
  )
  if pin_path == "" || helper == "" {
    raise @config.Invalid("mck.explicit_runner_pin_and_helper_required")
  }
  let bytes = @platform.read_input(pin_path, 16384)
  let pin = mck_pin(@json.parse(@utf8.decode(bytes[:])))
  let timeout = build_timeout(value(cli, "timeout", fallback="180000"))
  if timeout > 594000 {
    raise @config.Invalid("mck.timeout_limit: maximum 594000 ms")
  }
  let config : Json = {
    "profile": "morphir/cli/mck-command",
    "contractVersion": "0.1.0-draft.1",
    "pin": pin.to_json(),
    "arguments": arguments,
    "cwd": @platform.cwd(),
    "timeout": timeout,
    "cancelFile": value(cli, "cancel-file"),
  }
  if @utf8.encode(config.stringify()).length() > 131072 {
    raise @config.Invalid("mck.argument_limit")
  }
  @platform.interruption_start()
  defer @platform.interruption_stop()
  mck_dispatch(
    helper,
    config,
    timeout,
    value(cli, "node", fallback="node"),
    mode,
  )
}

///|
#cfg(target="js")
extern "js" fn mck_start(
  helper : String,
  config : String,
  interrupted : () -> Bool,
  mode : Int32,
) -> Unit =
  #| (helper, config, interrupted, mode) => {
  #|   import('node:url').then(({pathToFileURL})=>import(pathToFileURL(helper).href))
  #|     .then(module=>module.mckCommand(JSON.parse(config),interrupted))
  #|     .then(report=>{
  #|       if(mode) console.log(JSON.stringify(mode===2?{type:'mck',data:report}:report));
  #|       else {process.stdout.write(report.stdout);process.stderr.write(report.stderr);if(report.error)process.stderr.write(report.error+'\n');}
  #|       process.exitCode=report.exitCode;
  #|     }).catch(error=>{
  #|       const report={profile:'morphir/cli/mck-command',contractVersion:'0.1.0-draft.1',state:'failed',exitCode:1,stdout:'',stderr:'',error:'mck.helper_unavailable'};
  #|       if(mode)console.log(JSON.stringify(mode===2?{type:'mck',data:report}:report));else console.error(report.error);
  #|       process.exitCode=1;
  #|     });
  #| }

///|
#cfg(target="js")
fn mck_dispatch(
  helper : String,
  config : Json,
  _timeout : Int32,
  _node : String,
  mode : OutputMode,
) -> Int32 {
  mck_start(
    helper,
    config.stringify(),
    @platform.interruption_requested,
    match mode {
      Human => 0
      JSON => 1
      JSONLines => 2
    },
  )
  0
}

///|
#cfg(target="native")
fn mck_dispatch(
  helper : String,
  config : Json,
  timeout : Int32,
  node : String,
  mode : OutputMode,
) -> Int32 raise {
  let directory = @platform.temporary()
  defer @platform.remove_dir(directory)
  let path = directory + "/mck.json"
  @platform.write(path, config.stringify())
  defer @platform.remove_file(path)
  let result = @platform.process(
    node,
    [helper, "--morphir-mck-v1", path],
    @platform.cwd(),
    "",
    timeout + 6000,
  )
  guard result is Object(fields) &&
    fields.get("exitCode") is Some(Number(0.0, ..)) &&
    fields.get("stdout") is Some(String(source)) else {
    return mck_helper_failure(
      mode, "mck.helper_failed: execution outcome unknown",
    )
  }
  let report = @json.parse(source) catch {
    _ => return mck_helper_failure(mode, "mck.invalid_helper_reply")
  }
  guard report is Object(reply) &&
    reply.get("profile") == Some(Json::string("morphir/cli/mck-command")) &&
    reply.get("contractVersion") == Some(Json::string("0.1.0-draft.1")) &&
    reply.get("exitCode") is Some(Number(code, ..)) &&
    code >= 0.0 &&
    code <= 255.0 &&
    code == code.to_int().to_double() &&
    reply.get("stdout") is Some(String(stdout)) &&
    reply.get("stderr") is Some(String(stderr)) else {
    return mck_helper_failure(mode, "mck.invalid_helper_reply")
  }
  match mode {
    JSON => println(report.stringify())
    JSONLines => emit_record("mck", report)
    Human => {
      @platform.stdout(stdout)
      @platform.stderr(stderr)
      if reply.get("error") is Some(String(error)) {
        @platform.stderr(error + "\n")
      }
    }
  }
  code.to_int()
}

///|
#cfg(target="native")
fn mck_helper_failure(mode : OutputMode, error : String) -> Int32 {
  let report : Json = {
    "profile": "morphir/cli/mck-command",
    "contractVersion": "0.1.0-draft.1",
    "state": "failed",
    "exitCode": 1,
    "stdout": "",
    "stderr": "",
    "error": error,
  }
  match mode {
    JSON => println(report.stringify())
    JSONLines => emit_record("mck", report)
    Human => @platform.stderr(error + "\n")
  }
  1
}

///|
#cfg(any(target="wasm", target="wasm-gc"))
fn mck_dispatch(
  _helper : String,
  _config : Json,
  _timeout : Int32,
  _node : String,
  _mode : OutputMode,
) -> Int32 raise {
  raise @config.Invalid("mck.runtime_unavailable")
}
