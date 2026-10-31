///|
/// The two ends of a `MessageChannel`: the host's port and the guest's.
extern "js" fn port_pair() -> FixedArray[PortTarget] =
  #| () => { const {port1, port2} = new MessageChannel(); return [port1, port2]; }

///|
/// Launches each guest on the guest end of a `MessageChannel` in this
/// thread, with the checks and the message-port channel of the browser
/// launcher. Only `new Worker` differs, which needs a browser. `serve` is
/// false for a guest that never answers.
priv struct PairLauncher {
  browser : BrowserLauncher
  serve : Bool
}

///|
impl @worker.Launcher for PairLauncher with fn launch(self, spec, limits) {
  let (abi, bytes, call_ms) = self.browser.admit(spec)
  let ends = port_pair()
  if self.serve {
    serve(ends[1])
  }
  PortChannel::open(
    ends[0],
    abi,
    bytes,
    limits,
    call_ms~,
    grace_ms=self.browser.grace_ms,
  )
}

///|
fn entry() -> EntryUrl raise {
  EntryUrl::parse("https://example.test/wasm/browser-worker.js")
}

///|
fn pair_host(serve~ : Bool = true, call_ms? : Int32) -> @worker.Host raise {
  @worker.Host::new(
    PairLauncher::{ browser: BrowserLauncher::new(entry(), call_ms?), serve, },
    Browser,
  )
}

///|
fn wasm_spec(bytes : Bytes, abi? : @worker.WasmAbi) -> @worker.WorkerSpec {
  @worker.WorkerSpec::new(
    @worker.ArtifactRef::new(Memory(bytes), @worker.Sha256::of(bytes)),
    Wasm(abi~),
  )
}

///|
/// How a probe ended early, or `None` when it described the guest.
async fn probe_ending(
  host : @worker.Host,
  spec : @worker.WorkerSpec,
) -> (@worker.Ending, @worker.SessionReport)? {
  try host.probe(spec) catch {
    @worker.Ended(ending, report~) => Some((ending, report))
    _ => abort("not a host error")
  } noraise {
    _ => None
  }
}

///|
test "entry URL: an absolute URL is kept and a relative one is refused" {
  assert_eq(
    EntryUrl::parse("http://127.0.0.1:8080/entry.js").to_string(),
    "http://127.0.0.1:8080/entry.js",
  )
  let message = try EntryUrl::parse("entry.js") catch {
    @worker.LaunchError::LaunchFailed(message) => message
    _ => fail("not a launch failure")
  } noraise {
    _ => fail("a relative entry URL was accepted")
  }
  assert_true(message.contains("entry.js"))
}

///|
async test "message port: an Extism guest answers through the port with the js bounds" {
  guard probe_ending(pair_host(), wasm_spec(@fixtures.extism_echo_guest()))
    is Some((ending, report)) else {
    fail("the echo guest described itself")
  }
  // The echo guest answers describe with the request, which is not a
  // description, after a full round trip through the port.
  assert_true(ending is Failed(Host(..)))
  guard report.bounds is Some(bounds) else { fail("no bounds in the report") }
  assert_eq(bounds.instruction_budget, NotEnforced(NoInstructionMetering))
  assert_eq(bounds.call_deadline, Enforced)
  assert_eq(bounds.memory_ceiling, Enforced)
  guard report.stop is Some(stop) else { fail("no worker stop") }
  assert_eq(stop.stop_method, ThreadTermination)
  // The guest's started event is kept in the stderr tail.
  assert_true(@utf8.decode_lossy(stop.stderr.bytes()).contains("\"started\""))
}

///|
async test "message port: a guest that does not answer is terminated at the call deadline" {
  guard probe_ending(
      pair_host(serve=false, call_ms=200),
      wasm_spec(@fixtures.echo_guest()),
    )
    is Some((ending, report)) else {
    fail("a silent guest described itself")
  }
  assert_eq(ending, Deadline)
  guard report.stop is Some(stop) else { fail("no worker stop") }
  assert_eq(stop.status, Terminated(Deadline))
}

///|
/// A guest end that answers each request only with notifications, every
/// 50 ms, for 2 s. It closes its port after 3 s at most, so that the port
/// does not keep the test process alive.
extern "js" fn notifying_guest(target : PortTarget) -> Unit =
  #| (target) => {
  #|   const bytes = new TextEncoder().encode('{"jsonrpc":"2.0","method":"morphir.log","params":{}}');
  #|   const close = setTimeout(() => target.close(), 3000);
  #|   target.onmessage = (event) => {
  #|     if (event.data?.kind !== 'message') return;
  #|     let count = 0;
  #|     const timer = setInterval(() => {
  #|       count += 1;
  #|       if (count > 40) { clearInterval(timer); clearTimeout(close); target.close(); }
  #|       else target.postMessage({kind: 'response', bytes});
  #|     }, 50);
  #|   };
  #| }

///|
async test "message port: notifications do not extend the call deadline" {
  let ends = port_pair()
  notifying_guest(ends[1])
  let channel = PortChannel::open(
    ends[0],
    ExtismKernelV1,
    @fixtures.echo_guest(),
    @worker.Limits::host(),
    call_ms=300,
    grace_ms=100,
  )
  channel.send(
    @worker.Message::parse(
      @utf8.encode(
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"morphir.extension.describe\"}",
      ),
    ),
  )
  // A timer of the test itself: without it, a lost deadline leaves no timer,
  // and the runtime ends the test without a result.
  let notifications = @async.with_timeout_opt(1500, () => {
    let mut notifications = 0
    let mut ended = false
    while !ended {
      try channel.receive() catch {
        @worker.GuestFailed(CallDeadline) => ended = true
        error => fail("not a call deadline: \{error}")
      } noraise {
        message => {
          assert_true(
            message.json() is Object(fields) && !fields.contains("id"),
          )
          notifications += 1
        }
      }
    }
    notifications
  })
  guard notifications is Some(count) else {
    fail("the notifications extended the call deadline")
  }
  // The guest sent notifications, and the call still ended at its deadline.
  assert_true(count > 0)
}

///|
async test "message port: a trap fails the session with guest_trap" {
  guard probe_ending(pair_host(), wasm_spec(@fixtures.trapping_guest()))
    is Some((Failed(Host(code=GuestTrap, ..)), _)) else {
    fail("a trap did not fail with guest_trap")
  }
}

///|
async test "message port: a refusal of the guest's loader reaches the host as a refusal" {
  // The host checks the module first, so this opens the channel itself with
  // a profile that the module does not have.
  let bytes = @fixtures.echo_guest()
  let ends = port_pair()
  serve(ends[1])
  let channel = PortChannel::open(
    ends[0],
    ExtismKernelV1,
    bytes,
    @worker.Limits::host(),
    call_ms=5000,
    grace_ms=500,
  )
  let request = @worker.Message::parse(
    @utf8.encode(
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"morphir.extension.describe\"}",
    ),
  )
  channel.send(request)
  let (code, message) = try channel.receive() catch {
    @worker.ChannelError::Refused(code~, message~) => (code, message)
    error => fail("not a refusal: \{error}")
  } noraise {
    _ => fail("the loader's refusal did not reach the host")
  }
  assert_eq(code, AbiMismatch)
  assert_true(message.contains("Web Worker"))
  let stop = channel.close()
  assert_eq(stop.status, Exited(code=3))
}

///|
async test "browser launcher: a process artifact is refused before a worker starts" {
  let bytes = b"\x7fELF"
  let spec = @worker.WorkerSpec::new(
    @worker.ArtifactRef::new(Memory(bytes), @worker.Sha256::of(bytes)),
    Process(platform=X86_64UnknownLinuxGnu, args=[]),
  )
  let launcher = BrowserLauncher::new(entry())
  let supported = try launcher.launch(spec, @worker.Limits::host()) catch {
    @worker.LaunchError::RuntimeUnavailable(supported~) => supported
    error => fail("not runtime_unavailable: \{error}")
  } noraise {
    _ => fail("the launcher started a process worker")
  }
  assert_eq(supported, [Wasm])
  // The host refuses it first, with the runtimes that it supports.
  let host = @worker.Host::new(launcher, Browser)
  assert_eq(host.runtimes(), [Wasm])
  assert_false(host.supports(spec.runtime))
  guard probe_ending(host, spec)
    is Some((Refused(code=RuntimeUnavailable, message~), report)) else {
    fail("the host did not refuse the process artifact")
  }
  assert_true(message.contains("wasm"))
  assert_true(report.stop is None)
}

///|
async test "browser launcher: a file artifact and a wrong digest are refused" {
  let bytes = @fixtures.echo_guest()
  let launcher = BrowserLauncher::new(entry())
  let file = @worker.WorkerSpec::new(
    @worker.ArtifactRef::new(
      File(@worker.ArtifactPath::parse("/models/guest.wasm", Posix)),
      @worker.Sha256::of(bytes),
    ),
    Wasm(abi=None),
  )
  let detail = try launcher.launch(file, @worker.Limits::host()) catch {
    @worker.LaunchError::ArtifactUnreadable(Unreadable(detail=Some(detail))) =>
      detail
    error => fail("not an unreadable artifact: \{error}")
  } noraise {
    _ => fail("the launcher read a file")
  }
  assert_true(detail.contains("no file system"))
  let wrong = @worker.WorkerSpec::new(
    @worker.ArtifactRef::new(Memory(bytes), @worker.Sha256::of(b"other")),
    Wasm(abi=None),
  )
  try launcher.launch(wrong, @worker.Limits::host()) catch {
    @worker.LaunchError::DigestMismatch(..) => ()
    error => fail("not a digest mismatch: \{error}")
  } noraise {
    _ => fail("a wrong digest was accepted")
  }
}
