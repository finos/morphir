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
/// The native CLI with the worker mode, from MORPHIR_CLI.
fn cli() -> String? raise {
  prerequisite("MORPHIR_CLI")
}

///|
fn wasm_spec(bytes : Bytes, abi? : @worker.WasmAbi) -> @worker.WorkerSpec {
  @worker.WorkerSpec::new(
    @worker.ArtifactRef::new(Memory(bytes), @worker.Sha256::of(bytes)),
    Wasm(abi~),
  )
}

///|
/// The stamp of the tests' own launchers.
let test_stamp : @native.BuildStamp = @native.BuildStamp::new(
  version="test",
  commit="test",
)

///|
/// The build identity of a built CLI, from `extension worker --help --json`.
async fn cli_identity(path : String) -> @native.BuildIdentity {
  let (code, out, err) = @spawn.collect_output(path, [
    "extension", "worker", "--help", "--json",
  ])
  guard code == 0 &&
    (@json.parse(out.text()) catch { _ => Json::null() })
    is { "result": { "buildIdentity": String(identity), .. }, .. } else {
    fail("the CLI gave no build identity: \{out.text()} \{err.text()}")
  }
  @native.BuildIdentity::parse(identity)
}

///|
/// Runs `body` with a host whose WASM launcher starts the worker mode of the
/// CLI at `path`, then releases the launcher's staged copy of the CLI. The
/// identity is the CLI's own unless `identity` is given; a CLI at a path
/// that does not exist gets the tests' identity, for refusals before launch.
async fn with_host(
  path : String,
  identity? : @native.BuildIdentity,
  call? : @guest.CallBounds,
  body : async (@worker.Host) -> Unit,
) -> Unit {
  let identity = match identity {
    Some(identity) => identity
    None if @fs.exists(path) => cli_identity(path)
    None => @native.BuildIdentity::current(test_stamp)
  }
  let launcher = @native.WasmProcessLauncher::new(
    stamp=test_stamp,
    executable=At(path),
    identity~,
    call?,
  )
  defer launcher.release()
  let machine = @process.host_machine().unwrap()
  body(@worker.Host::new(launcher, Native(machine)))
}

///|
/// How a probe ended early, or `None` when it described the guest.
async fn probe_ending(
  host : @worker.Host,
  spec : @worker.WorkerSpec,
  deadline? : @worker.Deadline,
) -> (@worker.Ending, @worker.SessionReport)? {
  try host.probe(spec, deadline?) catch {
    @worker.Ended(ending, report~) => Some((ending, report))
    error => abort("not a host error: \{@debug.to_string(error)}")
  } noraise {
    _ => None
  }
}

///|
async test "native WASM worker runtime: an Extism guest runs in a worker process of the CLI" {
  guard cli() is Some(path) else { return }
  with_host(path, host => {
    // The echo guest answers describe with the request, which is not a
    // description: the probe fails after a full round trip through the
    // worker process.
    guard probe_ending(host, wasm_spec(@fixtures.extism_echo_guest()))
      is Some((ending, report)) else {
      fail("the echo guest described itself")
    }
    assert_true(ending is Failed(Host(..)))
    assert_eq(report.bounds, Some(@guest.engine_bounds()))
  })
}

///|
async test "runaway guest: the call is stopped at its deadline and the worker is gone" {
  guard cli() is Some(path) else { return }
  with_host(
    path,
    call=@guest.CallBounds::new(deadline_ms=300, instructions=None),
    host => {
      let failure = probe_ending(
        host,
        wasm_spec(@fixtures.runaway_guest()),
        deadline=@worker.Deadline::of_ms(20000),
      )
      guard failure is Some((Deadline, report)) else {
        fail("a runaway guest did not end at its deadline")
      }
      guard report.stop is Some(stop) else { fail("no worker stop") }
      assert_true(stop.status is Exited(code=1))
    },
  )
}

///|
async test "runaway guest: the session deadline stops the worker's process group" {
  guard cli() is Some(path) else { return }
  // A call deadline and a budget beyond the session deadline.
  let call = @guest.CallBounds::new(
    deadline_ms=60000,
    instructions=Some(2147483647),
  )
  with_host(path, call~, host => {
    // The budget ends the call after about 2 s on a developer machine, so the
    // session deadline must come first. A first probe stages the CLI, so that
    // under the load of a full test run the launch inside the deadline only
    // starts a process.
    ignore(probe_ending(host, wasm_spec(@fixtures.extism_echo_guest())))
    let failure = probe_ending(
      host,
      wasm_spec(@fixtures.runaway_guest()),
      deadline=@worker.Deadline::of_ms(1000),
    )
    guard failure is Some((Deadline, report)) else {
      fail(
        "the session deadline did not end the probe: \{@debug.to_string(failure)}",
      )
    }
    guard report.stop is Some(stop) else { fail("no worker stop") }
    assert_true(
      stop.status is Terminated(Deadline) || stop.status is Signalled(..),
    )
  })
}

///|
async test "memory ceiling: a growth past 256 MiB fails the call with memory_limit" {
  guard cli() is Some(path) else { return }
  with_host(path, host => {
    let failure = probe_ending(host, wasm_spec(@fixtures.growing_guest(4096)))
    guard failure is Some((Failed(Host(code=MemoryLimit, ..)), _)) else {
      fail("a growth past the ceiling did not fail with memory_limit")
    }
  })
}

///|
async test "build identity: a worker of another build is refused with worker_runtime_mismatch" {
  guard cli() is Some(path) else { return }
  let other = @native.BuildIdentity::parse(
    "1111111111111111111111111111111111111111111111111111111111111111",
  )
  with_host(path, identity=other, host => {
    let failure = probe_ending(host, wasm_spec(@fixtures.extism_echo_guest()))
    guard failure is Some((Refused(code=WorkerRuntimeMismatch, ..), _)) else {
      fail(
        "a worker of another build was not refused: \{@debug.to_string(failure)}",
      )
    }
  })
}

///|
async test "unsupported WASM features: a shared memory is refused at load, before any request" {
  with_host("/nonexistent/morphir", host => {
    // The launcher refuses before it starts a process, so no CLI is needed.
    let plain = @fixtures.module_(
      imports=@fixtures.byte_callbacks(),
      functions=[
        @fixtures.DefinedFunction::new(export_name="handle", b"\x41\x00"),
      ],
      memory=@fixtures.Memory::new(1, maximum=2, exported=false),
    )
    // Set the shared flag of the memory limits: 0x01 becomes 0x03.
    let shared = plain.to_array()
    for index in 0..<(shared.length() - 5) {
      if shared[index] == b'\x05' &&
        shared[index + 1] == b'\x04' &&
        shared[index + 2] == b'\x01' &&
        shared[index + 3] == b'\x01' {
        shared[index + 3] = b'\x03'
        break
      }
    }
    let failure = probe_ending(host, wasm_spec(Bytes::from_array(shared)))
    guard failure
      is Some((Refused(code=WasmFeatureUnsupported, message~), report)) else {
      fail("a shared memory was not refused: \{@debug.to_string(failure)}")
    }
    assert_true(message.contains("threads"))
    assert_true(report.stop is None)
  })
}

///|
async test "ABI classification at launch: env.open_socket is refused and nothing starts" {
  with_host("/nonexistent/morphir", host => {
    let guest = @fixtures.module_(
      imports=[
        @fixtures.ImportedFunction::new("env", "open_socket", [I32], [I32]),
      ],
      functions=[
        @fixtures.DefinedFunction::new(export_name="handle", b"\x41\x00"),
      ],
    )
    let failure = probe_ending(host, wasm_spec(guest))
    guard failure is Some((Refused(code=AbiUnsupported, message~), report)) else {
      fail("env.open_socket was not refused")
    }
    assert_true(message.contains("env.open_socket"))
    assert_true(report.stop is None)
  })
}

///|
test "prerequisites: a missing one skips the test outside CI and fails it in CI" {
  // The test runner's own environment decides; this checks the rule on the
  // variable that is never set.
  let missing = "MORPHIR_WASM_WORKER_TEST_NEVER_SET"
  if @env.get_env_var("CI") is Some("true") {
    assert_true((Ok(prerequisite(missing)) catch { e => Err(e) }) is Err(_))
  } else {
    assert_eq(prerequisite(missing), None)
  }
}

///|
async test "build identity: the stamp's version and commit are part of the identity" {
  let a = @native.BuildIdentity::current(
    @native.BuildStamp::new(version="0.1.0", commit="a"),
  )
  let b = @native.BuildIdentity::current(
    @native.BuildStamp::new(version="0.1.0", commit="b"),
  )
  let c = @native.BuildIdentity::current(
    @native.BuildStamp::new(version="0.2.0", commit="a"),
  )
  assert_true(a != b && a != c)
  assert_eq(
    a,
    @native.BuildIdentity::current(
      @native.BuildStamp::new(version="0.1.0", commit="a"),
    ),
  )
}

///|
async test "build identity: the launcher stages the CLI once and removes the copy on release" {
  guard cli() is Some(path) else { return }
  let root = @fs.tmpdir(prefix="morphir-wasm-launcher-test-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let launcher = @native.WasmProcessLauncher::new(
    stamp=test_stamp,
    staging_root=root,
    executable=At(path),
    identity=cli_identity(path),
  )
  let machine = @process.host_machine().unwrap()
  let host = @worker.Host::new(launcher, Native(machine))
  for _ in 0..<2 {
    ignore(probe_ending(host, wasm_spec(@fixtures.extism_echo_guest())))
  }
  // Both workers ran the one staged copy; their own directories are gone.
  let entries = @fs.readdir(root)
  assert_eq(entries.length(), 1)
  launcher.release()
  assert_eq(@fs.readdir(root).length(), 0)
}
