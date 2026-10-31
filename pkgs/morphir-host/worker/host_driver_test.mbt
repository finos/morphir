///|
/// A launcher that records each specification and the limits it was given,
/// and hands out one channel.
struct RecordingLauncher {
  channel : @worker.MemoryChannel
  specs : Array[@worker.WorkerSpec]
  limits : Array[@worker.Limits]
}

///|
impl @worker.Launcher for RecordingLauncher with fn launch(self, spec, limits) {
  self.specs.push(spec)
  self.limits.push(limits)
  self.channel
}

///|
fn process_spec(
  platform~ : @worker.Platform = Aarch64AppleDarwin,
) -> @worker.WorkerSpec {
  @worker.WorkerSpec::new(
    @worker.ArtifactRef::new(
      File(@worker.ArtifactPath::parse("/stage/elm", Posix)),
      @worker.Sha256::parse(digest),
    ),
    Process(platform~, args=["serve"]),
  ) catch {
    _ => abort("invalid test specification")
  }
}

///|
fn wasm_spec() -> @worker.WorkerSpec {
  @worker.WorkerSpec::new(
    @worker.ArtifactRef::new(Memory(b"\x00asm"), @worker.Sha256::of(b"\x00asm")),
    Wasm(abi=Some(ExtismKernelV1)),
  )
}

///|
/// A fake worker. It records every message, answers each request with
/// `reply`, stays silent when `reply` gives `None`, and exits on `exit`. It
/// answers the `slow` method after 20 milliseconds.
async fn serve(
  worker : @worker.MemoryWorker,
  received : Array[Json],
  reply : (String) -> Json?,
  slow~ : String = "",
) -> Unit {
  while true {
    let message = worker.receive() catch { _ => return }
    received.push(message.json())
    guard message.json() is Object({ "method": String(name), .. } as fields) else {
      continue
    }
    if name == "morphir.exit" {
      worker.exit(code=0)
      return
    }
    if name == slow {
      @async.sleep(20)
    }
    if fields.get("id") is Some(Number(id, ..)) && reply(name) is Some(result) {
      worker.send(
        @worker.Message::new({ "jsonrpc": "2.0", "id": id, "result": result }),
      )
    }
  }
}

///|
fn received_methods(received : Array[Json]) -> Array[String] {
  received.map(message => {
    match message {
      Object({ "method": String(name), .. }) => name
      _ => "?"
    }
  })
}

///|
/// A legacy guest that answers every request, and `silent` ones not at all.
fn legacy_guest(silent~ : String = "") -> (String) -> Json? {
  name => {
    match name {
      _ if name == silent => None
      "morphir.extension.describe" => Some(legacy_result())
      "morphir.initialize" => Some(legacy_result(protocol="0.1"))
      "morphir.shutdown" => Some({})
      _ => Some({ "success": true, "diagnostics": [] })
    }
  }
}

///|
fn host_error(error : Error) -> (@worker.Ending, @worker.SessionReport) {
  guard error is @worker.Ended(ending, report~) else {
    abort("not a host error")
  }
  (ending, report)
}

///|
async test "probe a staged artifact: the probe returns claims and the worker is gone" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  let host = @worker.Host::new(
    @worker.MemoryLauncher::new(channel),
    Native(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  let received = []
  @async.with_task_group(group => {
    group.spawn_bg(() => serve(worker, received, legacy_guest()))
    let description = host.probe(process_spec())
    assert_eq(description.claims, legacy_claims())
  })
  assert_eq(received_methods(received), [
    "morphir.extension.describe", "morphir.exit",
  ])
  // The host stopped the worker: its channel takes no more messages.
  guard (Ok(channel.send(@worker.Message::new({}))) catch { e => Err(e) })
    is Err(@worker.Stopped) else {
    fail("the probe left the worker running")
  }
}

///|
async test "probe of a guest that does not describe: describe_failed and no claims" {
  for case in ["error", "exit"] {
    let (channel, worker) = @worker.MemoryChannel::pair()
    let host = @worker.Host::new(
      @worker.MemoryLauncher::new(channel),
      Native(@worker.Machine::of(Aarch64AppleDarwin)),
    )
    let failure = @async.with_task_group(group => {
      group.spawn_bg(() => {
        let message = worker.receive()
        if case == "exit" {
          worker.exit(code=1)
          return
        }
        guard message.json() is Object({ "id": id, .. }) else { return }
        worker.send(
          @worker.Message::new({
            "jsonrpc": "2.0",
            "id": id,
            "error": { "code": -32601, "message": "Unknown MEP operation" },
          }),
        )
        ignore(worker.receive())
        worker.exit(code=0)
      })
      try host.probe(process_spec()) catch {
        error => Some(host_error(error))
      } noraise {
        _ => None
      }
    })
    guard failure is Some((Failed(Host(code=DescribeFailed, ..)), report)) else {
      fail("the \{case} probe did not fail with describe_failed")
    }
    assert_true(report.stop is Some(_))
  }
}

///|
async test "deadline: the worker is stopped, its stderr is kept and wire cancellation is not used" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  let host = @worker.Host::new(
    @worker.MemoryLauncher::new(channel),
    Native(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  let received = []
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      worker.write_stderr(b"stuck in compile")
      serve(worker, received, legacy_guest(silent="morphir.frontend.compile"))
    })
    let session = host.activate(
      process_spec(),
      expected=legacy_claims(),
      offer=Legacy,
      deadline=@worker.Deadline::of_ms(200),
    )
    let outcome = session.compile(compile_request())
    assert_eq(outcome.class, Deadline)
    assert_true(outcome.stderr.bytes() == b"stuck in compile")
    let report = session.close()
    guard report.stop is Some(stop) else { fail("no worker stop") }
    assert_eq(stop.status, Terminated(Deadline))
    assert_eq(report.ending, Some(Deadline))
    guard report.to_json() is Object({ "wireCancellation": False, .. }) else {
      fail("the report does not say wireCancellation: false")
    }
  })
  assert_false(received_methods(received).contains("$/cancelRequest"))
}

///|
async test "caller cancels: a stop interrupts a pending receive and stops the worker" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  let host = @worker.Host::new(
    @worker.MemoryLauncher::new(channel),
    Node(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  let stopping = Ref(false)
  let received = []
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      serve(worker, received, legacy_guest(silent="morphir.frontend.compile"))
    })
    let session = host.activate(
      process_spec(),
      expected=legacy_claims(),
      offer=Legacy,
      stop=@worker.StopSignal::new(() => stopping.val),
    )
    group.spawn_bg(() => {
      @async.sleep(30)
      stopping.val = true
    })
    let started = @async.now()
    let outcome = session.compile(compile_request())
    // The worker never answers; the stop, not the 60 s deadline, ended it.
    assert_true(@async.now() - started < 5000L)
    assert_eq(outcome.class, Cancelled)
    // The worker was stopped before the call returned.
    let report = session.close()
    guard report.stop is Some(stop) else { fail("no worker stop") }
    assert_eq(stop.status, Terminated(Cancelled))
  })
  assert_false(received_methods(received).contains("$/cancelRequest"))
}

///|
async test "browser host and a process artifact: runtime_unavailable and nothing starts" {
  let (channel, _worker) = @worker.MemoryChannel::pair()
  let launcher = { channel, specs: [], limits: [], }
  let host = @worker.Host::new(launcher, Browser)
  assert_eq(host.runtimes(), [Wasm])
  assert_false(host.supports(process_spec().runtime))
  assert_true(host.supports(wasm_spec().runtime))
  let failure = try host.probe(process_spec()) catch {
    error => Some(host_error(error))
  } noraise {
    _ => None
  }
  guard failure is Some((Refused(code=RuntimeUnavailable, message~), report)) else {
    fail("a browser host accepted a process worker")
  }
  assert_true(message.contains("wasm"))
  assert_true(report.stop is None)
  assert_eq(launcher.specs.length(), 0)
}

///|
async test "platform mismatch: a process for another platform is refused and nothing starts" {
  let (channel, _worker) = @worker.MemoryChannel::pair()
  let launcher = { channel, specs: [], limits: [], }
  let host = @worker.Host::new(
    launcher,
    Native(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  let spec = process_spec(platform=X86_64UnknownLinuxGnu)
  assert_false(host.supports(spec.runtime))
  let failure = try
    host.activate(spec, expected=legacy_claims(), offer=Legacy)
  catch {
    error => Some(host_error(error))
  } noraise {
    _ => None
  }
  guard failure is Some((Refused(code=PlatformMismatch, ..), _)) else {
    fail("started a process for another platform")
  }
  assert_eq(launcher.specs.length(), 0)
}

///|
async test "specification from an installed catalog: the host starts it with the recorded arguments" {
  let entry : Json = {
    "artifact": {
      "path": "/home/u/.morphir/extensions/elm/elm",
      "sha256": digest,
    },
    "runtime": {
      "kind": "process",
      "platform": "aarch64-apple-darwin",
      "args": ["mep", "--", "", "--stdio"],
    },
  }
  let spec = @worker.WorkerSpec::from_json(entry, Posix)
  let (channel, worker) = @worker.MemoryChannel::pair()
  let launcher = { channel, specs: [], limits: [], }
  let host = @worker.Host::new(
    launcher,
    Native(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  @async.with_task_group(group => {
    group.spawn_bg(() => serve(worker, [], legacy_guest()))
    let session = host.activate(spec, expected=legacy_claims(), offer=Legacy)
    ignore(session.close())
  })
  assert_eq(launcher.specs, [spec])
  guard launcher.specs[0].runtime is Process(args~, ..) else {
    fail("not a process")
  }
  assert_eq(args, ["mep", "--", "", "--stdio"])
  assert_eq(launcher.limits, [@worker.Limits::host()])
}

///|
async test "launch limits: the launcher gets the session's frame limits" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  let launcher = { channel, specs: [], limits: [], }
  let host = @worker.Host::new(
    launcher,
    Native(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  @async.with_task_group(group => {
    group.spawn_bg(() => serve(worker, [], legacy_guest()))
    let session = host.activate(
      wasm_spec(),
      expected=legacy_claims(),
      offer=Legacy,
    )
    ignore(session.close())
  })
  // A MEP 0.1 WASM guest has the bounds of the restricted Extism profile.
  assert_eq(launcher.limits, [
    @worker.Limits::host().for_session(Legacy, wasm_spec().runtime),
  ])
}

///|
async test "claims drift through the host: claims_mismatch, shutdown and exit, no operation" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  let host = @worker.Host::new(
    @worker.MemoryLauncher::new(channel),
    Native(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  let received = []
  let failure = @async.with_task_group(group => {
    group.spawn_bg(() => {
      serve(worker, received, name => {
        match name {
          "morphir.initialize" =>
            Some(legacy_result(version="9.9.9", protocol="0.1"))
          _ => Some({})
        }
      })
    })
    try
      host.activate(process_spec(), expected=legacy_claims(), offer=Legacy)
    catch {
      error => Some(host_error(error))
    } noraise {
      _ => None
    }
  })
  guard failure is Some((Refused(code=ClaimsMismatch, ..), report)) else {
    fail("activation accepted drifted claims")
  }
  assert_eq(received_methods(received), [
    "morphir.initialize", "morphir.shutdown", "morphir.exit",
  ])
  guard report.stop is Some(stop) else { fail("no worker stop") }
  assert_eq(stop.status, Exited(code=0))
}

///|
async test "the report states the limits that applied and how the worker stopped" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  let host = @worker.Host::new(
    @worker.MemoryLauncher::new(channel),
    Node(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  @async.with_task_group(group => {
    group.spawn_bg(() => serve(worker, [], legacy_guest()))
    let session = host.activate(
      wasm_spec(),
      expected=legacy_claims(),
      offer=Legacy,
    )
    let outcome = session.compile(compile_request())
    assert_true(outcome.class is Completed(_))
    let report = session.close()
    assert_eq(report.extism, Some(@worker.ExtismProfile::restricted()))
    guard report.stop is Some(stop) else { fail("no worker stop") }
    assert_eq(stop.status, Exited(code=0))
    assert_eq(stop.stop_method, ExitedAfterExit)
    assert_true(report.ending is None)
    guard report.to_json()
      is Object(
        {
          "protocolVersion": String("0.1"),
          "limits": Object({ "requestBytes": _, "responseBytes": _, .. }),
          "extismProfile": Object(_),
          "wireCancellation": False,
          ..
        }
      ) else {
      fail("the report does not state the limits")
    }
    // A closed session gives the same report again and takes no calls.
    assert_eq(session.close(), report)
    let again = try session.compile(compile_request()) catch {
      @worker.SessionUnavailable(_) => None
      _ => Some("another error")
    } noraise {
      _ => Some("an outcome")
    }
    assert_true(again is None)
  })
}

///|
async test "same guest, two worker kinds: the host sends the same messages and returns the same result" {
  let run = async fn(spec : @worker.WorkerSpec) {
    let (channel, worker) = @worker.MemoryChannel::pair()
    let host = @worker.Host::new(
      @worker.MemoryLauncher::new(channel),
      Native(@worker.Machine::of(Aarch64AppleDarwin)),
    )
    let received = []
    let outcome = @async.with_task_group(group => {
      group.spawn_bg(() => {
        serve(worker, received, name => {
          match name {
            "morphir.initialize" =>
              Some(model_result([ion_tuple], protocol="0.2.0-draft.1"))
            "morphir.shutdown" => Some({})
            _ => Some({ "success": true, "modules": ["main"] })
          }
        })
      })
      let session = host.activate(
        spec,
        expected=model_claims(),
        offer=Model(ion_tuple),
      )
      let outcome = session.compile(compile_request())
      ignore(session.close())
      outcome
    })
    (received, outcome)
  }
  let process = run(process_spec())
  let wasm = run(
    @worker.WorkerSpec::new(
      wasm_spec().artifact,
      Wasm(abi=Some(MorphirBytesV1)),
    ),
  )
  assert_eq(process, wasm)
  assert_true(process.1.class is Completed(_))
}

///|
/// An in-memory channel whose `send` blocks for good once `sends_left`
/// messages have gone out, like a worker that stops reading its input.
struct BlockingChannel {
  inner : @worker.MemoryChannel
  mut sends_left : Int32
}

///|
impl @worker.Channel for BlockingChannel with fn send(self, message) {
  if self.sends_left <= 0 {
    @async.sleep(1000000)
  }
  self.sends_left -= 1
  self.inner.send(message)
}

///|
impl @worker.Channel for BlockingChannel with fn receive(self) {
  self.inner.receive()
}

///|
impl @worker.Channel for BlockingChannel with fn close(self) {
  self.inner.close()
}

///|
impl @worker.Channel for BlockingChannel with fn abort(self, reason) {
  self.inner.abort(reason)
}

///|
/// A launcher that hands out one channel of any kind.
struct OneLauncher {
  channel : &@worker.Channel
}

///|
impl @worker.Launcher for OneLauncher with fn launch(self, _spec, _limits) {
  self.channel
}

///|
/// A launcher whose launch never finishes, like a worker that hangs on start.
struct HangingLauncher {}

///|
impl @worker.Launcher for HangingLauncher with fn launch(_self, _spec, _limits) {
  @async.sleep(1000000)
  abort("the hanging launch finished")
}

///|
/// Activates a legacy worker whose channel blocks after `sends` messages and
/// returns how activation ended and how the worker stopped.
async fn blocked_activation(
  sends : Int32,
  deadline~ : @worker.Deadline = @worker.Deadline::default(),
  stop~ : @worker.StopSignal = @worker.StopSignal::never(),
) -> (@worker.Ending, @worker.StopStatus)? {
  let (memory, worker) = @worker.MemoryChannel::pair()
  let channel = { inner: memory, sends_left: sends, }
  let host = @worker.Host::new(
    { channel, },
    Native(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  let ended = @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => serve(worker, [], legacy_guest()))
    @async.with_timeout_opt(5000, () => {
      try
        host.activate(
          process_spec(),
          expected=legacy_claims(),
          offer=Legacy,
          deadline~,
          stop~,
        )
      catch {
        error => {
          let (ending, report) = host_error(error)
          report.stop.map(stop => (ending, stop.status))
        }
      } noraise {
        _ => None
      }
    })
  })
  ended.bind(found => found)
}

///|
async test "blocked send: the deadline ends a send that never finishes and stops the worker" {
  // The first send, initialize, blocks.
  let started = @async.now()
  let ended = blocked_activation(0, deadline=@worker.Deadline::of_ms(50))
  assert_true(@async.now() - started < 5000L)
  assert_eq(ended, Some((Deadline, Terminated(Deadline))))
  // The send of initialized, after the initialize answer, blocks too.
  let ended = blocked_activation(1, deadline=@worker.Deadline::of_ms(50))
  assert_eq(ended, Some((Deadline, Terminated(Deadline))))
}

///|
async test "blocked send: a stop interrupts a send that never finishes" {
  let stopping = Ref(false)
  let ended = @async.with_task_group(group => {
    group.spawn_bg(() => {
      @async.sleep(30)
      stopping.val = true
    })
    blocked_activation(0, stop=@worker.StopSignal::new(() => stopping.val))
  })
  assert_eq(ended, Some((Cancelled, Terminated(Cancelled))))
}

///|
async test "launch and stop: a stop interrupts a launch that never finishes" {
  let stopping = Ref(false)
  let host = @worker.Host::new(
    HangingLauncher::{ },
    Native(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  let ended = @async.with_task_group(group => {
    group.spawn_bg(() => {
      @async.sleep(30)
      stopping.val = true
    })
    @async.with_timeout_opt(5000, () => {
      try
        host.probe(
          process_spec(),
          stop=@worker.StopSignal::new(() => stopping.val),
        )
      catch {
        error => Some(host_error(error).0)
      } noraise {
        _ => None
      }
    })
  })
  assert_eq(ended, Some(Some(Cancelled)))
}

///|
async test "task cancellation: cancelling the enclosing task during compile aborts the worker" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  let host = @worker.Host::new(
    @worker.MemoryLauncher::new(channel),
    Native(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      serve(worker, [], legacy_guest(silent="morphir.frontend.compile"))
    })
    let finished = @async.with_timeout_opt(50, () => {
      let session = host.activate(
        process_spec(),
        expected=legacy_claims(),
        offer=Legacy,
      )
      ignore(session.compile(compile_request()))
    })
    assert_true(finished is None)
  })
  // A channel returns its first stop: the abort of the cancelled task.
  assert_eq(channel.abort(Fault).status, Terminated(Cancelled))
}

///|
async test "with_session: the session is closed after the work, and aborted when it is cancelled" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  let host = @worker.Host::new(
    @worker.MemoryLauncher::new(channel),
    Native(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  let received = []
  @async.with_task_group(group => {
    group.spawn_bg(() => serve(worker, received, legacy_guest()))
    let outcome = host.with_session(
      process_spec(),
      expected=legacy_claims(),
      offer=Legacy,
      session => session.compile(compile_request()),
    )
    assert_true(outcome.class is Completed(_))
  })
  assert_eq(received_methods(received), [
    "morphir.initialize", "morphir.initialized", "morphir.frontend.compile", "morphir.shutdown",
    "morphir.exit",
  ])
  assert_eq(channel.abort(Fault).stop_method, ExitedAfterExit)
  // An error from the work also closes the session.
  let (channel, worker) = @worker.MemoryChannel::pair()
  let host = @worker.Host::new(
    @worker.MemoryLauncher::new(channel),
    Native(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  let received = []
  let failed = @async.with_task_group(group => {
    group.spawn_bg(() => serve(worker, received, legacy_guest()))
    try
      host.with_session(
        process_spec(),
        expected=legacy_claims(),
        offer=Legacy,
        _ => (fail("the work failed") : Unit),
      )
    catch {
      _ => true
    } noraise {
      _ => false
    }
  })
  assert_true(failed)
  assert_eq(received_methods(received), [
    "morphir.initialize", "morphir.initialized", "morphir.shutdown", "morphir.exit",
  ])
  // Cancellation during the work aborts the worker.
  let (channel, worker) = @worker.MemoryChannel::pair()
  let host = @worker.Host::new(
    @worker.MemoryLauncher::new(channel),
    Native(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  @async.with_task_group(group => {
    group.spawn_bg(() => serve(worker, [], legacy_guest()))
    let finished = @async.with_timeout_opt(50, () => {
      host.with_session(
        process_spec(),
        expected=legacy_claims(),
        offer=Legacy,
        _ => @async.sleep(1000000),
      )
    })
    assert_true(finished is None)
  })
  assert_eq(channel.abort(Fault).status, Terminated(Cancelled))
}

///|
/// A launcher that refuses every specification with one launch error.
struct RefusingLauncher {
  error : @worker.LaunchError
}

///|
impl @worker.Launcher for RefusingLauncher with fn launch(self, _spec, _limits) {
  raise self.error
}

///|
async test "worker runtime mismatch: a worker of another build is refused before any operation" {
  let host = @worker.Host::new(
    RefusingLauncher::{
      error: WorkerRuntimeMismatch(host="build-a", worker="build-b"),
    },
    Native(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  let failure = try host.probe(wasm_spec()) catch {
    error => Some(host_error(error))
  } noraise {
    _ => None
  }
  guard failure is Some((Refused(code=WorkerRuntimeMismatch, message~), report)) else {
    fail("a worker of another build was not refused")
  }
  assert_true(message.contains("build-a") && message.contains("build-b"))
  assert_true(report.stop is None)
  assert_eq(
    @worker.RefusalCode::WorkerRuntimeMismatch.to_string(),
    "extension.worker_runtime_mismatch",
  )
}

///|
async test "missing export: a module without handle is refused and the message names the export" {
  let host = @worker.Host::new(
    RefusingLauncher::{
      error: ExportMissing(name="handle", signature="() -> i32"),
    },
    Native(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  let failure = try host.probe(wasm_spec()) catch {
    error => Some(host_error(error))
  } noraise {
    _ => None
  }
  guard failure is Some((Refused(code=AbiUnsupported, message~), _)) else {
    fail("a module without handle was not refused")
  }
  assert_eq(message, "the module does not export handle as () -> i32")
}

///|
async test "memory ceiling: an initial memory above the ceiling fails with memory_limit before any worker" {
  let host = @worker.Host::new(
    RefusingLauncher::{
      error: MemoryAboveCeiling(initial=5000L, ceiling=4096),
    },
    Native(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  let failure = try host.probe(wasm_spec()) catch {
    error => Some(host_error(error))
  } noraise {
    _ => None
  }
  guard failure is Some((Failed(Host(code=MemoryLimit, message~)), report)) else {
    fail("an initial memory above the ceiling did not fail with memory_limit")
  }
  assert_eq(
    message, "the module's initial memory of 5000 pages is above the ceiling of 4096 pages",
  )
  assert_true(report.stop is None)
}

///|
async test "guest fault: a trap reported by the channel fails the session with guest_trap" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  let host = @worker.Host::new(
    @worker.MemoryLauncher::new(channel),
    Node(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      serve(worker, [], name => {
        if name == "morphir.frontend.compile" {
          worker.fail(Trap("unreachable executed"))
          None
        } else {
          legacy_guest()(name)
        }
      })
    })
    let session = host.activate(
      wasm_spec(),
      expected=legacy_claims(),
      offer=Legacy,
    )
    let outcome = session.compile(compile_request())
    guard outcome.class is Failed(Host(code=GuestTrap, message~)) else {
      fail("a trap did not fail the call: \{@debug.to_string(outcome.class)}")
    }
    assert_true(message.contains("unreachable executed"))
    let report = session.close()
    guard report.ending is Some(Failed(Host(code=GuestTrap, ..))) else {
      fail("the report does not keep the trap")
    }
  })
}

///|
async test "enforced bounds: the report states which WASM bounds the host enforced" {
  let bounds = @worker.EnforcedBounds::new(
    memory_ceiling=Enforced,
    instruction_budget=NotEnforced(NoInstructionMetering),
    call_deadline=Enforced,
  )
  let (channel, worker) = @worker.MemoryChannel::pair(bounds~)
  let host = @worker.Host::new(
    @worker.MemoryLauncher::new(channel),
    Node(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  @async.with_task_group(group => {
    group.spawn_bg(() => serve(worker, [], legacy_guest()))
    let session = host.activate(
      wasm_spec(),
      expected=legacy_claims(),
      offer=Legacy,
    )
    ignore(session.compile(compile_request()))
    let report = session.close()
    assert_eq(report.bounds, Some(bounds))
    guard report.to_json()
      is Object(
        {
          "bounds": Object(
            {
              "memoryCeiling": Object({ "enforced": True, .. }),
              "instructionBudget": Object(
                {
                  "enforced": False,
                  "reason": String("no-instruction-metering"),
                  ..
                }
              ),
              "callDeadline": Object({ "enforced": True, .. }),
              ..
            }
          ),
          ..
        }
      ) else {
      fail("the report does not state the enforced bounds")
    }
  })
  // A process channel enforces no WASM bounds, so its report has none.
  let (channel, worker) = @worker.MemoryChannel::pair()
  let host = @worker.Host::new(
    @worker.MemoryLauncher::new(channel),
    Native(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  @async.with_task_group(group => {
    group.spawn_bg(() => serve(worker, [], legacy_guest()))
    let session = host.activate(
      process_spec(),
      expected=legacy_claims(),
      offer=Legacy,
    )
    ignore(session.compile(compile_request()))
    let report = session.close()
    assert_true(report.bounds is None)
    assert_true(
      report.to_json() is Object(fields) && !fields.contains("bounds"),
    )
  })
}

///|
async test "channel refusal: a refusal of the worker reaches the caller with its code" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  let host = @worker.Host::new(
    @worker.MemoryLauncher::new(channel),
    Native(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  worker.refuse(code=WorkerRuntimeMismatch, message="another build")
  let failure = try host.probe(wasm_spec()) catch {
    error => Some(host_error(error))
  } noraise {
    _ => None
  }
  guard failure is Some((Refused(code=WorkerRuntimeMismatch, message~), report)) else {
    fail("the refusal did not reach the caller")
  }
  assert_eq(message, "another build")
  assert_true(report.stop is Some(_))
}

///|
async test "concurrent calls: a second call is refused and a close waits for the call" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  let host = @worker.Host::new(
    @worker.MemoryLauncher::new(channel),
    Native(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  let received = []
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      serve(worker, received, legacy_guest(), slow="morphir.frontend.compile")
    })
    let session = host.activate(
      process_spec(),
      expected=legacy_claims(),
      offer=Legacy,
    )
    let first = group.spawn(() => session.compile(compile_request()))
    // The first compile waits for its answer.
    @async.sleep(5)
    let second = try session.compile(compile_request()) catch {
      @worker.SessionUnavailable(_) => None
      _ => Some("another error")
    } noraise {
      _ => Some("an outcome")
    }
    assert_eq(second, None)
    // A close waits for the call; it does not send shutdown during it.
    let report = session.close()
    assert_true(first.wait().class is Completed(_))
    assert_true(report.ending is None)
  })
  assert_eq(received_methods(received), [
    "morphir.initialize", "morphir.initialized", "morphir.frontend.compile", "morphir.shutdown",
    "morphir.exit",
  ])
}
