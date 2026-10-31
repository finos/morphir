///|
/// A prerequisite of the end-to-end tests, from the environment variable
/// `name`: `mise run test:wasm-workers` builds them and sets the variables.
/// Outside CI a missing one skips the test; with `CI=true` it fails the test.
fn prerequisite(name : String) -> String? raise {
  match @env.get_env_var(name) {
    Some(value) if value != "" => Some(value)
    _ => {
      if @env.get_env_var("CI") is Some("true") {
        fail("\{name} is not set: run mise run test:wasm-workers")
      }
      None
    }
  }
}

///|
/// The built worker entry module, from MORPHIR_WASM_THREAD_ENTRY.
fn entry() -> String? raise {
  prerequisite("MORPHIR_WASM_THREAD_ENTRY")
}

///|
fn wasm_spec(bytes : Bytes, abi? : @worker.WasmAbi) -> @worker.WorkerSpec {
  @worker.WorkerSpec::new(
    @worker.ArtifactRef::new(Memory(bytes), @worker.Sha256::of(bytes)),
    Wasm(abi~),
  )
}

///|
fn host(path : String, call_ms? : Int32) -> @worker.Host {
  @worker.Host::new(
    ThreadLauncher::new(entry=path, call_ms?),
    Node(@worker.Machine::of(Aarch64AppleDarwin)),
  )
}

///|
/// How a probe ended early, or `None` when it described the guest.
async fn probe_ending(
  host : @worker.Host,
  spec : @worker.WorkerSpec,
  deadline? : @worker.Deadline,
  stop? : @worker.StopSignal,
) -> (@worker.Ending, @worker.SessionReport)? {
  try host.probe(spec, deadline?, stop?) catch {
    @worker.Ended(ending, report~) => Some((ending, report))
    _ => abort("not a host error")
  } noraise {
    _ => None
  }
}

///|
async test "Node worker threads: an Extism guest runs in a thread with the js bounds" {
  guard entry() is Some(path) else { return }
  guard probe_ending(host(path), wasm_spec(@fixtures.extism_echo_guest()))
    is Some((ending, report)) else {
    fail("the echo guest described itself")
  }
  // The echo guest answers describe with the request, which is not a
  // description, after a full round trip through the thread.
  assert_true(ending is Failed(Host(..)))
  guard report.bounds is Some(bounds) else { fail("no bounds in the report") }
  assert_eq(bounds.instruction_budget, NotEnforced(NoInstructionMetering))
  assert_eq(bounds.call_deadline, Enforced)
  assert_eq(bounds.memory_ceiling, Enforced)
  guard report.stop is Some(stop) else { fail("no worker stop") }
  assert_eq(stop.stop_method, ThreadTermination)
}

///|
async test "runaway guest in a thread: the call deadline terminates the thread" {
  guard entry() is Some(path) else { return }
  guard probe_ending(
      host(path, call_ms=300),
      wasm_spec(@fixtures.runaway_guest()),
    )
    is Some((ending, report)) else {
    fail("a runaway guest described itself")
  }
  assert_eq(ending, Deadline)
  guard report.stop is Some(stop) else { fail("no worker stop") }
  assert_eq(stop.status, Terminated(Deadline))
}

///|
async test "runaway guest in a thread: the session deadline terminates the thread" {
  guard entry() is Some(path) else { return }
  guard probe_ending(
      host(path),
      wasm_spec(@fixtures.runaway_guest()),
      deadline=@worker.Deadline::of_ms(800),
    )
    is Some((ending, report)) else {
    fail("a runaway guest described itself")
  }
  assert_eq(ending, Deadline)
  guard report.stop is Some(stop) else { fail("no worker stop") }
  assert_eq(stop.status, Terminated(Deadline))
}

///|
async test "cancel a WASM call in a thread: the thread is terminated and the outcome is cancelled" {
  guard entry() is Some(path) else { return }
  let started = @async.now()
  let stop = @worker.StopSignal::new(() => @async.now() - started > 500L)
  guard probe_ending(host(path), wasm_spec(@fixtures.runaway_guest()), stop~)
    is Some((ending, report)) else {
    fail("a runaway guest described itself")
  }
  assert_eq(ending, Cancelled)
  guard report.stop is Some(worker) else { fail("no worker stop") }
  assert_eq(worker.status, Terminated(Cancelled))
}

///|
async test "guest traps in a thread: the session fails with guest_trap" {
  guard entry() is Some(path) else { return }
  guard probe_ending(host(path), wasm_spec(@fixtures.trapping_guest()))
    is Some((Failed(Host(code=GuestTrap, ..)), _)) else {
    fail("a trap did not fail with guest_trap")
  }
}

///|
async test "memory ceiling in a thread: a growth past 256 MiB fails with memory_limit" {
  guard entry() is Some(path) else { return }
  guard probe_ending(host(path), wasm_spec(@fixtures.growing_guest(4096)))
    is Some((Failed(Host(code=MemoryLimit, ..)), _)) else {
    fail("a growth past the ceiling did not fail with memory_limit")
  }
}

///|
async test "the thread launcher refuses a module outside its profile before a thread starts" {
  let guest = @fixtures.module_(
    imports=[
      @fixtures.ImportedFunction::new("env", "open_socket", [I32], [I32]),
    ],
    functions=[
      @fixtures.DefinedFunction::new(export_name="handle", b"\x41\x00"),
    ],
  )
  guard probe_ending(host("/nonexistent/entry.js"), wasm_spec(guest))
    is Some((Refused(code=AbiUnsupported, ..), report)) else {
    fail("env.open_socket was not refused")
  }
  assert_true(report.stop is None)
}

///|
async test "Node worker threads: the portable guest and Python describe themselves" {
  guard entry() is Some(path) else { return }
  if prerequisite("MORPHIR_PORTABLE_GUEST") is Some(portable) {
    let bytes = read_file(portable)
    let description = host(path).probe(wasm_spec(bytes, abi=MorphirBytesV1))
    assert_true(
      description.claims.languages
      .iter()
      .any(claim => claim.language_id.to_string() == "moonbit"),
    )
  }
  if prerequisite("MORPHIR_PYTHON_EXTENSIONS") is Some(root) {
    for version in ["0.4.1", "0.4.2"] {
      let bytes = read_file(
        "\{root}/\{version}/morphir-python-binding-\{version}.wasm",
      )
      let description = host(path).probe(wasm_spec(bytes, abi=ExtismKernelV1))
      assert_eq(description.claims.version.to_string(), version)
    }
  }
}

///|
async test "a missing entry module fails the launch and names the file" {
  guard probe_ending(
      host("/nonexistent/wasm-worker.js"),
      wasm_spec(@fixtures.echo_guest()),
    )
    is Some((Failed(Host(code=IncompleteSession, message~)), report)) else {
    fail("a missing entry module did not fail the launch")
  }
  assert_true(message.contains("/nonexistent/wasm-worker.js"))
  assert_true(report.stop is None)
}

///|
test "the bundled launcher looks for wasm-worker.js beside the running script" {
  let path = beside_script(ENTRY_FILE)
  assert_true(is_absolute(path))
  assert_true(
    path.has_suffix("/wasm-worker.js") || path.has_suffix("\\wasm-worker.js"),
  )
}

///|
/// The separator of the platform's paths.
extern "js" fn path_separator() -> String =
  #| () => process.getBuiltinModule('node:path').sep

///|
test "beside_script: a file: URL and a path with a space and a non-ASCII character" {
  let posix = path_separator() == "/"
  guard posix else { return }
  let expected = "/tmp/dir with space é/wasm-worker.js"
  // An ES module frame: a file: URL with percent escapes.
  let esm = "Error\n    at node:internal/main:1:1\n    at beside (file:///tmp/dir%20with%20space%20%C3%A9/cli.js:10:5)\n"
  assert_eq(script_beside(esm, ENTRY_FILE), expected)
  // A frame without a function name.
  let bare = "Error\n    at file:///tmp/dir%20with%20space%20%C3%A9/cli.mjs:1:1\n"
  assert_eq(script_beside(bare, ENTRY_FILE), expected)
  // A CommonJS frame: an absolute path with the space and the é as they are.
  let cjs = "Error\n    at Object.<anonymous> (/tmp/dir with space é/cli.cjs:3:1)\n"
  assert_eq(script_beside(cjs, ENTRY_FILE), expected)
}

///|
test "beside_script: a relative path or no script gives no path" {
  assert_eq(script_beside("Error\n    at f (cli.js:1:1)\n", ENTRY_FILE), "")
  assert_eq(
    script_beside("Error\n    at node:internal/x:1:1\n", ENTRY_FILE),
    "",
  )
  assert_eq(script_beside("", ENTRY_FILE), "")
}

///|
/// Runs Node on a script in a new directory named `name`, in the system's
/// temporary directory, that prints its own stack trace. Returns the
/// directory and the stack, and removes the directory.
extern "js" fn real_stack(
  name : String,
  extension : String,
) -> FixedArray[String] =
  #| (name, extension) => {
  #|   const fs = process.getBuiltinModule('node:fs');
  #|   const path = process.getBuiltinModule('node:path');
  #|   const os = process.getBuiltinModule('node:os');
  #|   const {execFileSync} = process.getBuiltinModule('node:child_process');
  #|   const parent = fs.mkdtempSync(path.join(os.tmpdir(), 'morphir-thread-test-'));
  #|   const directory = path.join(parent, name);
  #|   try {
  #|     fs.mkdirSync(directory);
  #|     const script = path.join(directory, 'cli' + extension);
  #|     fs.writeFileSync(script, 'process.stdout.write(String(new Error().stack));\n');
  #|     const stack = execFileSync(process.execPath, [script], {encoding: 'utf8'});
  #|     return [fs.realpathSync(directory), stack];
  #|   } finally { fs.rmSync(parent, {recursive: true, force: true}); }
  #| }

///|
test "beside_script: real ES module and CommonJS stacks from a directory with a space and an é" {
  for extension in [".mjs", ".cjs"] {
    let result = real_stack("thread entry é", extension)
    let found = script_beside(result[1], ENTRY_FILE)
    // The stack may name the directory through a link, as /tmp on macOS.
    assert_true(
      found.has_suffix("thread entry é" + path_separator() + ENTRY_FILE),
    )
    assert_true(is_absolute(found))
  }
}

///|
async test "the thread launcher refuses an entry path that is not absolute" {
  guard probe_ending(host("wasm-worker.js"), wasm_spec(@fixtures.echo_guest()))
    is Some((Failed(Host(code=IncompleteSession, message~)), report)) else {
    fail("a relative entry path did not fail the launch")
  }
  assert_true(message.contains("not absolute"))
  assert_true(report.stop is None)
}

///|
extern "js" fn directory_state(path : String) -> String =
  #| (path) => {
  #|   const fs = process.getBuiltinModule('node:fs');
  #|   try {
  #|     const stat = fs.statSync(path);
  #|     const mode = (stat.mode & 0o777).toString(8);
  #|     return `${stat.isDirectory() ? 'directory' : 'file'} ${mode} ${fs.readdirSync(path).length}`;
  #|   } catch { return 'missing'; }
  #| }

///|
async test "the guest workspace in a thread is a private, empty directory that is removed afterwards" {
  guard entry() is Some(path) else { return }
  let bytes = @fixtures.extism_workspace_guest()
  let channel = ThreadLauncher::new(entry=path).launch(
    wasm_spec(bytes),
    @worker.Limits::host(),
  )
  channel.send(
    @worker.Message::new({
      "jsonrpc": "2.0",
      "id": 1,
      "method": "morphir.extension.describe",
    }),
  )
  let answer = channel.receive().json()
  guard answer is { "root": String(root), .. } else {
    fail("no workspace in the answer: \{answer.stringify()}")
  }
  assert_true(is_absolute(root))
  if path_separator() == "/" {
    assert_eq(directory_state(root), "directory 700 0")
  } else {
    assert_true(directory_state(root).has_prefix("directory"))
  }
  ignore(channel.abort(Cancelled))
  assert_eq(directory_state(root), "missing")
}
