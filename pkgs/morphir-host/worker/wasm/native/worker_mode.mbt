///|
/// Exit status: the guest served until `exit`.
pub const EXIT_SERVED : Int32 = 0

///|
/// Exit status: the guest stopped for a fault, or the stream ended early.
pub const EXIT_FAULT : Int32 = 1

///|
/// Exit status: the arguments are not valid.
pub const EXIT_USAGE : Int32 = 2

///|
/// Exit status: the worker refused to serve before any request.
pub const EXIT_REFUSED : Int32 = 3

///|
/// What the worker mode serves: one module of one ABI profile, with the
/// session's frame limits and the call bounds of the profile.
pub struct WorkerOptions {
  abi : @worker.WasmAbi
  module_path : String
  build_identity : BuildIdentity
  request_bytes : Int32
  response_bytes : Int32
  call : @guest.CallBounds?
  memory_pages : Int32?
  json : Bool
}

///|
/// A worker-mode command line: serve, or show the help.
pub(all) enum WorkerInvocation {
  Serve(WorkerOptions)
  Help(json~ : Bool)
}

///|
/// Whether the arguments, without the program name, select the worker mode.
pub fn is_worker_invocation(args : ArrayView[String]) -> Bool {
  args is ["extension", "worker", ..]
}

///|
fn worker_command() -> @argparse.Command {
  @argparse.Command(
    "morphir extension worker",
    about="Serve one WASM extension guest as a worker of the Morphir CLI. " +
      "stdout carries only Content-Length framed MEP messages. The startup " +
      "and diagnostic report goes to stderr: one morphir/command-event 0.1.0 " +
      "line per event with --json (events started, output, fault, refused, " +
      "exited), text lines without it. Guest output of a call is reported " +
      "when the call ends: the newest 64 KiB, each message cut to 4 KiB, and " +
      "an output event with droppedBytes for the rest. With --json a usage " +
      "error is one morphir/command-result failure on stderr. Exit status: 0 " +
      "after exit, 1 for a guest fault or an early end of stdin, 2 for " +
      "invalid arguments, 3 for a " +
      "refusal before any request (another build, an ABI or a WASM feature). " +
      "Started by the CLI's WASM launcher; not for direct use.",
    disable_help_flag=true,
    disable_help_subcommand=true,
    disable_version_flag=true,
    flags=[
      @argparse.FlagArg(
        "json",
        about="Write the stderr report as morphir/command-event lines",
      ),
      @argparse.FlagArg("help", short='h', about="Show this help on stdout"),
    ],
    options=[
      @argparse.OptionArg(
        "abi",
        about="The declared ABI profile: extism-kernel-v1 or morphir-bytes-v1",
      ),
      @argparse.OptionArg("module", about="The path of the module to serve"),
      @argparse.OptionArg(
        "build-identity",
        about="The build identity of the host; another identity is refused",
      ),
      @argparse.OptionArg(
        "request-bytes",
        about="The largest request frame body",
      ),
      @argparse.OptionArg(
        "response-bytes",
        about="The largest response frame body",
      ),
      @argparse.OptionArg(
        "call-ms",
        about="The deadline of each guest call, in milliseconds",
      ),
      @argparse.OptionArg(
        "instructions",
        about="The instruction budget of each guest call",
      ),
      @argparse.OptionArg(
        "memory-pages",
        about="The guest memory ceiling, in 64 KiB pages",
      ),
    ],
  )
}

///|
/// The help text of the worker mode.
pub fn worker_help() -> String {
  worker_command().render_help()
}

///|
/// A worker-mode argument that is not valid.
pub(all) suberror UsageError {
  UsageError(String)
} derive(Debug)

///|
pub extend UsageError with @debug.Debug::{to_repr}

///|
fn single(matches : @argparse.Matches, name : String) -> String? {
  match matches.values.get(name) {
    Some([value, ..]) => Some(value)
    _ => None
  }
}

///|
fn positive(
  matches : @argparse.Matches,
  name : String,
) -> Int32? raise UsageError {
  guard single(matches, name) is Some(text) else { return None }
  let value = @strconv.parse_int(text) catch {
    _ => raise UsageError("--\{name} must be a positive integer")
  }
  guard value > 0 else {
    raise UsageError("--\{name} must be a positive integer")
  }
  Some(value)
}

///|
/// Parses the arguments after `extension worker`.
pub fn WorkerInvocation::parse(
  argv : ArrayView[String],
) -> WorkerInvocation raise UsageError {
  let matches = worker_command().parse(argv~) catch {
    error => raise UsageError(@debug.to_string(error))
  }
  let json = matches.flags.get("json").unwrap_or(false)
  if matches.flags.get("help").unwrap_or(false) {
    return Help(json~)
  }
  let required = (name : String) => {
    guard single(matches, name) is Some(value) else {
      raise UsageError("--\{name} is required")
    }
    value
  }
  let abi = @worker.WasmAbi::parse(required("abi")) catch {
    _ => raise UsageError("--abi must be extism-kernel-v1 or morphir-bytes-v1")
  }
  let module_path = required("module")
  let build_identity = BuildIdentity::parse(required("build-identity")) catch {
    _ => raise UsageError("--build-identity must be 64 hexadecimal digits")
  }
  let host = @worker.Limits::host()
  let defaults = @guest.CallBounds::for_abi(abi)
  let call_ms = positive(matches, "call-ms")
  let instructions = positive(matches, "instructions")
  let call = if call_ms is None && instructions is None {
    None
  } else {
    Some(
      @guest.CallBounds::new(
        deadline_ms=call_ms.unwrap_or(defaults.deadline_ms),
        instructions=match instructions {
          Some(count) => Some(count)
          None => defaults.instructions
        },
      ),
    )
  }
  Serve({
    abi,
    module_path,
    build_identity,
    request_bytes: positive(matches, "request-bytes").unwrap_or(
      host.request_bytes,
    ),
    response_bytes: positive(matches, "response-bytes").unwrap_or(
      host.response_bytes,
    ),
    call,
    memory_pages: positive(matches, "memory-pages"),
    json,
  })
}

///|
/// The arguments that start a worker for these options, after `extension
/// worker`. The launcher always asks for the JSON report.
pub fn WorkerOptions::to_args(self : WorkerOptions) -> Array[String] {
  let args = [
    "--abi",
    self.abi.to_string(),
    "--module",
    self.module_path,
    "--build-identity",
    self.build_identity.to_string(),
    "--request-bytes",
    self.request_bytes.to_string(),
    "--response-bytes",
    self.response_bytes.to_string(),
  ]
  if self.call is Some(call) {
    args.append(["--call-ms", call.deadline_ms.to_string()])
    if call.instructions is Some(count) {
      args.append(["--instructions", count.to_string()])
    }
  }
  if self.memory_pages is Some(pages) {
    args.append(["--memory-pages", pages.to_string()])
  }
  if self.json {
    args.push("--json")
  }
  args
}

///|
/// Writes the worker's report: JSON event lines or text lines.
priv struct Reporter {
  sink : &@io.Writer
  json : Bool
  mut sequence : Int32
}

///|
async fn Reporter::emit(self : Reporter, event : @guest.WorkerEvent) -> Unit {
  self.sequence += 1
  let line = if self.json {
    event.to_json(sequence=self.sequence).stringify()
  } else {
    event.to_text()
  }
  self.sink.write(line + "\n")
}

///|
async fn Reporter::finish(self : Reporter, code : Int32) -> Int32 {
  self.emit(Exited(code~))
  code
}

///|
fn refusal(error : @worker.LaunchError) -> @guest.WorkerEvent {
  match error {
    AbiUnsupported(name) =>
      Refused(code=AbiUnsupported, message="the module imports \{name}")
    ExportMissing(name~, signature~) =>
      Refused(
        code=AbiUnsupported,
        message="the module does not export \{name} as \{signature}",
      )
    MemoryAboveCeiling(initial~, ceiling~) =>
      Fault(
        MemoryLimit(
          "the module's initial memory of \{initial} pages is above the ceiling of \{ceiling} pages",
        ),
      )
    AbiMismatch(declared~, classified~) =>
      Refused(
        code=AbiMismatch,
        message="the worker was started for \{declared}; the module is \{classified}",
      )
    WasmFeatureUnsupported(feature~) =>
      Refused(
        code=WasmFeatureUnsupported,
        message="the module needs \{feature.unwrap_or("a WASM feature")} that the engine does not have",
      )
    LaunchFailed(text) => Fault(Failure(text))
    error => Fault(Failure(@debug.to_string(error)))
  }
}

///|
/// Serves one guest: checks the build identity, loads the module, reports
/// that it started, then answers each request frame from `input` on
/// `output`, until `exit`. Notifications get no frame. The report goes to
/// `report`. Returns the exit status.
pub async fn WorkerOptions::serve(
  self : WorkerOptions,
  input : &@io.Reader,
  output : &@io.Writer,
  report : &@io.Writer,
  workspace_root~ : String,
  own~ : BuildIdentity,
) -> Int32 {
  let reporter = { sink: report, json: self.json, sequence: 0, }
  if self.build_identity != own {
    reporter.emit(
      Refused(
        code=WorkerRuntimeMismatch,
        message="the worker runtime is build \{own}; the host is build \{self.build_identity}",
      ),
    )
    return reporter.finish(EXIT_REFUSED)
  }
  let bytes = @fs.read_file(self.module_path).binary() catch {
    error => {
      reporter.emit(
        Fault(
          Failure("the module could not be read: \{@debug.to_string(error)}"),
        ),
      )
      return reporter.finish(EXIT_FAULT)
    }
  }
  // The guest output of the call that runs. The engine call blocks, so the
  // output is reported when the call ends, whatever ended it.
  let tail = @guest.OutputTail::new()
  let services = @guest.GuestServices::new(workspace_root~, output=item => {
    tail.push(item)
  })
  let flush = async fn() {
    let (outputs, dropped) = tail.drain()
    for item in outputs {
      reporter.emit(Output(item))
    }
    if dropped > 0L {
      reporter.emit(OutputDropped(bytes=dropped))
    }
  }
  let limits = @worker.Limits::new(
    request_bytes=self.request_bytes,
    response_bytes=self.response_bytes,
    model=@worker.Limits::host().model,
  ) catch {
    _ => {
      reporter.emit(Fault(Failure("invalid frame limits")))
      return reporter.finish(EXIT_FAULT)
    }
  }
  let ceiling = match self.memory_pages {
    Some(pages) =>
      @wasm.MemoryCeiling::of_pages(pages) catch {
        _ => {
          reporter.emit(Fault(Failure("invalid memory ceiling")))
          return reporter.finish(EXIT_FAULT)
        }
      }
    None => @wasm.MemoryCeiling::restricted()
  }
  let guest = @guest.load(
    bytes,
    declared=self.abi,
    call?=self.call,
    limits~,
    ceiling~,
    services~,
  ) catch {
    error => {
      let event = refusal(error)
      flush()
      reporter.emit(event)
      return reporter.finish(
        if event is Refused(..) {
          EXIT_REFUSED
        } else {
          EXIT_FAULT
        },
      )
    }
  }
  reporter.emit(
    Started(
      abi=self.abi,
      module_sha256=@worker.Sha256::of(bytes),
      build_identity=own.to_string(),
      bounds=@guest.engine_bounds(),
    ),
  )
  let reader = @shared.FrameReader::new(limit=self.request_bytes)
  let writer = @shared.FrameWriter::new(limit=self.response_bytes)
  while true {
    let chunk = input.read_some() catch {
      error => {
        reporter.emit(
          Fault(Failure("stdin failed: \{@debug.to_string(error)}")),
        )
        return reporter.finish(EXIT_FAULT)
      }
    }
    guard chunk is Some(chunk) else {
      reporter.emit(Fault(Failure("the host closed stdin before exit")))
      return reporter.finish(EXIT_FAULT)
    }
    let messages = reader.feed(chunk) catch {
      error => {
        reporter.emit(
          Fault(Failure("an invalid request frame: \{@debug.to_string(error)}")),
        )
        return reporter.finish(EXIT_FAULT)
      }
    }
    for message in messages {
      let reply = guest.exchange(message.to_bytes()) catch {
        Faulted(fault) => {
          flush()
          reporter.emit(Fault(fault))
          return reporter.finish(EXIT_FAULT)
        }
      }
      flush()
      match reply {
        Response(bytes) => {
          let frame = writer.encode(@worker.Message::parse(bytes)) catch {
            error => {
              reporter.emit(
                Fault(
                  Failure(
                    "the guest's response is not a valid frame: \{@debug.to_string(error)}",
                  ),
                ),
              )
              return reporter.finish(EXIT_FAULT)
            }
          }
          output.write(frame)
        }
        Notified => ()
        Exit => return reporter.finish(EXIT_SERVED)
      }
    }
  }
  EXIT_FAULT
}

///|
/// Whether the worker-mode arguments ask for JSON, also when they are not
/// valid otherwise.
pub fn wants_json(args : ArrayView[String]) -> Bool {
  args.iter().any(arg => arg == "--json")
}

///|
/// The `morphir/command-result` failure for a usage error, with exit status
/// 2. With `--json` the worker mode writes it on stderr, since stdout is the
/// frame stream.
pub fn usage_failure(message : String) -> Json {
  {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": @guest.worker_command,
    "state": "failed",
    "exitCode": EXIT_USAGE,
    "error": { "code": "usage", "message": message },
    "diagnostics": [],
  }
}

///|
/// The `morphir extension worker` mode on the process's stdio. `args` are the
/// command-line arguments without the program name, starting with
/// `extension worker`; `stamp` is the CLI build's stamp. With `--help --json`
/// the result also gives the build identity. Returns the exit status.
pub async fn serve_worker(args : Array[String], stamp~ : BuildStamp) -> Int32 {
  let own = BuildIdentity::current(stamp)
  let invocation = WorkerInvocation::parse(args[2:]) catch {
    UsageError(text) => {
      if wants_json(args[2:]) {
        @stdio.stderr.write(usage_failure(text).stringify() + "\n")
      } else {
        @stdio.stderr.write("morphir extension worker: \{text}\n")
      }
      return EXIT_USAGE
    }
  }
  match invocation {
    Help(json~) => {
      // Help serves no guest, so it may use stdout.
      if json {
        let result : Json = {
          "profile": "morphir/command-result",
          "contractVersion": "0.1.0",
          "command": @guest.worker_command,
          "state": "succeeded",
          "exitCode": 0,
          "result": { "help": worker_help(), "buildIdentity": own.to_string() },
          "diagnostics": [],
        }
        @stdio.stdout.write(result.stringify() + "\n")
      } else {
        @stdio.stdout.write(worker_help())
      }
      EXIT_SERVED
    }
    Serve(options) =>
      options.serve(
        @stdio.stdin,
        @stdio.stdout,
        @stdio.stderr,
        workspace_root=@fs.realpath(".") catch { _ => "." },
        own~,
      )
  }
}
