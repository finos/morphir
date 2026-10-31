///|
async fn remove_quietly(directory : String) -> Unit noraise {
  @fs.rmdir(directory, recursive=true) catch {
    _ => ()
  }
}

///|
/// Runs `body` with the path of a module in a new temporary directory, and
/// removes the directory afterwards.
async fn with_module_file(bytes : Bytes, body : async (String) -> Unit) -> Unit {
  let directory = @fs.tmpdir(prefix="morphir-wasm-worker-test-")
  defer remove_quietly(directory)
  let path = directory + "/module.wasm"
  @fs.write_file(path, bytes)
  body(path)
}

///|
fn options(
  abi : @worker.WasmAbi,
  module_path : String,
  identity~ : @native.BuildIdentity = @native.BuildIdentity::current(test_stamp),
  extra~ : Array[String] = [],
) -> @native.WorkerOptions {
  let args = [
    "--abi",
    abi.to_string(),
    "--module",
    module_path,
    "--build-identity",
    identity.to_string(),
    "--json",
    ..extra,
  ]
  let invocation = @native.WorkerInvocation::parse(args) catch {
    error => abort("invalid arguments: \{@debug.to_string(error)}")
  }
  guard invocation is Serve(options) else { abort("not a serve invocation") }
  options
}

///|
/// Runs the worker mode with `requests` as framed stdin. Returns the exit
/// status, the response messages and the stderr report.
async fn run_worker(
  options : @native.WorkerOptions,
  requests : Array[Json],
) -> (Int32, Array[Json], Bytes) {
  let (stdin_read, stdin_write) = @io.pipe()
  let (stdout_read, stdout_write) = @io.pipe()
  let (stderr_read, stderr_write) = @io.pipe()
  let writer = @shared.FrameWriter::new(limit=4194304)
  let mut code = -1
  let mut responses = []
  let mut report = b""
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      // A worker that refuses reads nothing; its stdin closes under the
      // writer.
      for request in requests {
        guard request is Object(fields) else { abort("not an object") }
        stdin_write.write(writer.encode(@worker.Message::new(fields))) catch {
          _ => break
        }
      }
      stdin_write.close()
    })
    group.spawn_bg(() => {
      let reader = @shared.FrameReader::new(limit=16777216)
      let all = stdout_read.read_all().binary()
      responses = reader.feed(all).map(message => message.json())
    })
    group.spawn_bg(() => report = stderr_read.read_all().binary())
    code = options.serve(
      stdin_read,
      stdout_write,
      stderr_write,
      workspace_root="/work",
      own=@native.BuildIdentity::current(test_stamp),
    )
    stdin_read.close()
    stdout_write.close()
    stderr_write.close()
  })
  (code, responses, report)
}

///|
fn request(id : Int32, method_name : String) -> Json {
  { "jsonrpc": "2.0", "id": id, "method": method_name }
}

///|
fn exit_notification() -> Json {
  { "jsonrpc": "2.0", "method": "morphir.exit" }
}

///|
async test "worker mode output: stdout carries only frames and the report goes to stderr" {
  with_module_file(@fixtures.extism_echo_guest(), path => {
    let (code, responses, report) = run_worker(options(ExtismKernelV1, path), [
      request(1, "morphir.extension.describe"),
      { "jsonrpc": "2.0", "method": "morphir.initialized" },
      request(2, "morphir.shutdown"),
      exit_notification(),
    ])
    assert_eq(code, 0)
    assert_eq(responses, [
      request(1, "morphir.extension.describe"),
      request(2, "morphir.shutdown"),
    ])
    let lines = @utf8.decode(report).split("\n").to_array()
    guard lines[0].has_prefix("{\"profile\":\"morphir/command-event\"") else {
      fail("the report does not start with an event: \{lines[0]}")
    }
    assert_true(lines[0].contains("\"event\":\"started\""))
    assert_true(lines.iter().any(line => line.contains("\"event\":\"exited\"")))
    assert_eq(@guest.WorkerEvent::ending_in(report), None)
  })
}

///|
async test "build identity: a worker of another build refuses before it reads a request" {
  with_module_file(@fixtures.extism_echo_guest(), path => {
    let other = @native.BuildIdentity::parse(
      "0000000000000000000000000000000000000000000000000000000000000000",
    )
    let (code, responses, report) = run_worker(
      options(ExtismKernelV1, path, identity=other),
      [request(1, "morphir.extension.describe")],
    )
    assert_eq(code, 3)
    assert_eq(responses, [])
    guard @guest.WorkerEvent::ending_in(report)
      is Some(Refused(code=WorkerRuntimeMismatch, ..)) else {
      fail("no runtime mismatch in the report")
    }
  })
}

///|
async test "declared ABI must agree: the worker refuses a module of another profile" {
  with_module_file(@fixtures.extism_echo_guest(), path => {
    let (code, _, report) = run_worker(options(MorphirBytesV1, path), [])
    assert_eq(code, 3)
    assert_true(
      @guest.WorkerEvent::ending_in(report)
      is Some(Refused(code=AbiMismatch, ..)),
    )
  })
}

///|
async test "guest traps: the worker reports the trap and exits 1" {
  with_module_file(@fixtures.trapping_guest(), path => {
    let (code, responses, report) = run_worker(options(MorphirBytesV1, path), [
      request(1, "morphir.extension.describe"),
    ])
    assert_eq(code, 1)
    assert_eq(responses, [])
    assert_true(
      @guest.WorkerEvent::ending_in(report) is Some(GuestFailed(Trap(_))),
    )
  })
}

///|
async test "guest prints: WASI output goes to the report, never to the response stream" {
  with_module_file(@fixtures.extism_wasi_guest(), path => {
    let (code, responses, report) = run_worker(options(ExtismKernelV1, path), [
      request(1, "x"),
    ])
    // The guest answers with one byte, which is not a JSON message.
    assert_eq(code, 1)
    assert_eq(responses, [])
    let text = @utf8.decode(report)
    assert_true(text.contains("stdout: hello"))
  })
}

///|
async test "the worker ends with a fault when the host closes stdin before exit" {
  with_module_file(@fixtures.echo_guest(), path => {
    let (code, _, report) = run_worker(options(MorphirBytesV1, path), [])
    assert_eq(code, 1)
    assert_true(
      @guest.WorkerEvent::ending_in(report) is Some(GuestFailed(Failure(_))),
    )
  })
}

///|
test "worker arguments: missing or invalid values are usage errors" {
  let refused = (args : Array[String]) => {
    try @native.WorkerInvocation::parse(args) catch {
      UsageError(_) => true
    } noraise {
      _ => false
    }
  }
  assert_true(refused([]))
  assert_true(
    refused(["--abi", "wasi-cli", "--module", "m", "--build-identity", "0"]),
  )
  assert_true(@native.WorkerInvocation::parse(["--help"]) is Help(json=false))
  assert_true(@native.worker_help().contains("stdout carries only"))
}

///|
/// The report events of a worker's stderr.
fn events(report : Bytes) -> Array[Json] {
  @utf8.decode_lossy(report)
  .split("\n")
  .filter(line => line != "")
  .map(line => @json.parse(line) catch { _ => Json::null() })
  .to_array()
}

///|
/// Runs a guest that logs 10 MiB in one call and then ends as `ending` says,
/// and checks that the report holds the newest outputs, the dropped count and
/// then the fault.
async fn flood(
  ending : @fixtures.LoggingEnd,
  extra : Array[String],
  expected : (@worker.GuestFault) -> Bool,
) -> Unit {
  with_module_file(@fixtures.extism_logging_guest(160, ending), path => {
    let (code, responses, report) = run_worker(
      options(ExtismKernelV1, path, extra~),
      [request(1, "morphir.extension.describe")],
    )
    assert_eq(code, 1)
    assert_eq(responses, [])
    // The whole report stays small: the tail and the cut messages bound it.
    assert_true(report.length() < 2 * @guest.OUTPUT_TAIL_BYTES)
    let all = events(report)
    let outputs = all.filter(event => {
      event is { "event": "output", "output": String(text), .. } &&
      text.has_prefix("log info:")
    })
    assert_true(outputs.length() > 0 && outputs.length() <= 16)
    guard all
      .iter()
      .find_first(event => event is { "droppedBytes": Number(_, ..), .. })
      is Some({ "droppedBytes": Number(dropped, ..), .. }) else {
      fail("no dropped count in the report")
    }
    // 160 blocks of 64 KiB were logged; at most 64 KiB was reported.
    assert_true(dropped >= 160.0 * 65536.0 - 65536.0)
    guard @guest.WorkerEvent::ending_in(report) is Some(GuestFailed(fault)) &&
      expected(fault) else {
      fail(
        "the report does not end with the fault: \{@utf8.decode_lossy(report[report.length() - 400:])}",
      )
    }
  })
}

///|
async test "worker mode output: after 10 MiB of logging, a trap reports the tail, the dropped count and the trap" {
  flood(Trap, [], fault => fault is Trap(_))
}

///|
async test "worker mode output: after 10 MiB of logging, a budget fault reports the tail and the dropped count" {
  flood(Spin, ["--instructions", "20000000"], fault => fault is BudgetExhausted)
}

///|
async test "worker mode output: after 10 MiB of logging, the call deadline reports the tail and the dropped count" {
  // The logging takes about 70 ms and the budget about 3 s on a developer
  // machine. Both scale with the load of a test run, so a deadline between
  // them ends the call after the logging and before the budget.
  flood(Spin, ["--call-ms", "1000", "--instructions", "2147483647"], fault => {
    fault is CallDeadline
  })
}

///|
async test "module without handle: the worker refusal names the missing export" {
  // A module of the kernel imports with no handle export.
  let bytes = @fixtures.module_(imports=@fixtures.kernel_imports())
  with_module_file(bytes, path => {
    let (code, _, report) = run_worker(options(ExtismKernelV1, path), [])
    assert_eq(code, 3)
    assert_eq(
      @guest.WorkerEvent::ending_in(report),
      Some(
        Refused(
          code=AbiUnsupported,
          message="the module does not export handle as () -> i32",
        ),
      ),
    )
  })
}

///|
test "worker arguments: with --json a usage error is a command-result failure for stderr" {
  assert_true(@native.wants_json(["--abi", "nope", "--json"]))
  assert_false(@native.wants_json(["--abi", "nope"]))
  let document = @native.usage_failure("--abi must be extism-kernel-v1")
  guard document
    is {
      "profile": "morphir/command-result",
      "contractVersion": "0.1.0",
      "command": "extension worker",
      "state": "failed",
      "exitCode": 2,
      "error": {
        "code": "usage",
        "message": "--abi must be extism-kernel-v1",
        ..
      },
      "diagnostics": [],
      ..
    } else {
    fail("not a usage failure: \{document.stringify()}")
  }
  assert_false(document is { "result": _, .. })
}
