// Scenario tests for native process workers on Linux and macOS. They use the
// POSIX sh fixture in fixtures/worker.sh; `moon test` runs them from the
// module root, pkgs/morphir-host.

///|
#cfg(not(platform="windows"))
const FIXTURE : String = "worker/process/native/fixtures/worker.sh"

///|
#cfg(not(platform="windows"))
async fn file_artifact(path : String) -> @worker.ArtifactRef {
  let bytes = @fs.read_file(path).binary()
  @worker.ArtifactRef::new(
    File(@worker.ArtifactPath::parse(path, Posix)),
    @worker.Sha256::of(bytes),
  )
}

///|
#cfg(not(platform="windows"))
async fn fixture() -> @worker.ArtifactRef {
  file_artifact(@fs.realpath(FIXTURE))
}

///|
#cfg(not(platform="windows"))
fn machine() -> @worker.Machine {
  @native.host_machine().unwrap()
}

///|
/// A platform that this machine runs.
#cfg(not(platform="windows"))
fn platform() -> @worker.Platform {
  machine().platforms()[0]
}

///|
#cfg(not(platform="windows"))
async fn start(
  mode : String,
  args~ : Array[String] = [],
  limits~ : @worker.Limits = @worker.Limits::host(),
) -> @native.ProcessChannel {
  @native.ProcessLauncher::new().start(
    @native.stage(fixture()),
    [mode, ..args],
    limits~,
  )
}

///|
#cfg(not(platform="windows"))
fn message(fields : Map[String, Json]) -> @worker.Message {
  @worker.Message::new(fields)
}

///|
#cfg(not(platform="windows"))
fn text(bytes : Bytes) -> String {
  @utf8.decode_lossy(bytes)
}

///|
#cfg(not(platform="windows"))
/// Whether a process has gone: it no longer exists, or it is a zombie that
/// runs no code.
async fn gone(pid : Int32) -> Bool {
  @async.pause()
  !@native.process_alive(pid)
}

///|
/// Names a channel error for a failure message.
#cfg(not(platform="windows"))
fn describe(error : Error?) -> String {
  match error {
    None => "no error"
    Some(@worker.WorkerClosed) => "WorkerClosed"
    Some(@worker.Stopped) => "Stopped"
    Some(@worker.FrameInvalid(text)) => "FrameInvalid(\{text})"
    Some(@worker.TransportFailed(text)) => "TransportFailed(\{text})"
    Some(@worker.FrameLimit(direction~, declared~, limit~)) =>
      "FrameLimit(\{@debug.to_string(direction)}, declared=\{declared}, limit=\{limit})"
    Some(other) => other.to_string()
  }
}

///|
/// Receives a message, or stops the worker and fails with how it stopped.
#cfg(not(platform="windows"))
async fn[C : @worker.Channel] receive_or_report(channel : C) -> @worker.Message {
  channel.receive() catch {
    error => {
      let stop = channel.abort(Fault)
      fail(
        "receive failed with \{describe(Some(error))}; the worker stopped as \{@debug.to_string(stop.status)} by \{@debug.to_string(stop.stop_method)}, stderr: \{text(stop.stderr.bytes())}",
      )
    }
  }
}

///|
/// The command lines of the processes that are not zombies and whose
/// arguments contain `text`: from `/proc` on Linux, from `ps` on macOS.
#cfg(not(platform="windows"))
async fn processes_naming(text : String) -> Array[String] {
  let found = []
  match @async.platform {
    Linux =>
      for entry in @fs.readdir("/proc") {
        guard entry is ['0'..<='9', ..] else { continue }
        let (command, stat) = (
          @fs.read_file("/proc/\{entry}/cmdline").text(),
          @fs.read_file("/proc/\{entry}/stat").text(),
        ) catch {
          _ => continue
        }
        // "pid (comm) state ...": the state follows the last parenthesis.
        let zombie = match stat.rev_find(")") {
          Some(at) => stat[at + 1:].trim_start().has_prefix("Z")
          None => false
        }
        if command.contains(text) && !zombie {
          found.push(command.replace_all(old="\u0000", new=" "))
        }
      }
    _ => {
      let (_, listing) = @process.collect_stdout("/bin/ps", [
        "-A", "-o", "stat=", "-o", "args=",
      ])
      for line in listing.text().split("\n") {
        let line = line.trim_start()
        if line.contains(text) && !line.has_prefix("Z") {
          found.push(line.to_owned())
        }
      }
    }
  }
  found
}

///|
#cfg(not(platform="windows"))
async fn grandchild_of(channel : @native.ProcessChannel) -> Int32 {
  let reply = receive_or_report(channel).json()
  guard reply is { "grandchild": Number(pid, ..), .. } else {
    fail("no grandchild in \{reply.stringify()}")
  }
  pid.to_int()
}

///|
#cfg(not(platform="windows"))
async test "a worker answers whole frames on stdin and stdout" {
  let channel = start("echo")
  let first = message({ "jsonrpc": "2.0", "id": 1, "method": "describe" })
  let second = message({ "jsonrpc": "2.0", "method": "exit" })
  channel.send(first)
  channel.send(second)
  assert_eq(channel.receive(), first)
  assert_eq(channel.receive(), second)
  let stop = channel.close()
  assert_eq(stop.status, Exited(code=0))
  assert_eq(stop.stop_method, ExitedAfterExit)
  assert_true(gone(channel.pid()))
}

///|
#cfg(not(platform="windows"))
async test "the launcher runs a process specification for this platform" {
  let spec = @worker.WorkerSpec::new(
    fixture(),
    Process(platform=platform(), args=["echo"]),
  )
  let channel = @native.ProcessLauncher::new().launch(
    spec,
    @worker.Limits::host(),
  )
  let ping = message({ "id": 7 })
  channel.send(ping)
  assert_eq(receive_or_report(channel), ping)
  assert_eq(channel.close().status, Exited(code=0))
}

///|
#cfg(not(platform="windows"))
async test "an artifact replaced after verification does not run" {
  let directory = @fs.tmpdir(prefix="morphir-worker-test-")
  defer (@fs.rmdir(directory, recursive=true) catch { _ => () })
  let original = directory + "/worker.sh"
  @fs.write_file(original, @fs.read_file(FIXTURE), permission=0o700)
  let artifact = file_artifact(original)
  let staged = @native.stage(artifact)
  // Replace the original between verification and start.
  @fs.remove(original)
  @fs.write_file(
    original,
    "#!/bin/sh\nprintf 'Content-Length: 24\\r\\n\\r\\n{\"marker\":\"replacement\"}'\n",
    permission=0o700,
  )
  assert_true(staged.executable() != original)
  let channel = @native.ProcessLauncher::new().start(staged, ["echo"])
  let probe = message({ "probe": "verified" })
  channel.send(probe)
  assert_eq(channel.receive(), probe)
  ignore(channel.close())
  // A replacement before verification is refused, never started.
  let refused = try {
    ignore(@native.stage(artifact))
    None
  } catch {
    error => Some(error)
  }
  guard refused is Some(@worker.DigestMismatch(..)) else {
    fail("expected a digest mismatch")
  }
}

///|
#cfg(not(platform="windows"))
async test "a digest mismatch starts no process" {
  let spec = @worker.WorkerSpec::new(
    @worker.ArtifactRef::new(
      File(@worker.ArtifactPath::parse(@fs.realpath(FIXTURE), Posix)),
      @worker.Sha256::of(b"other bytes"),
    ),
    Process(platform=platform(), args=["echo"]),
  )
  let refused = try {
    ignore(@native.ProcessLauncher::new().launch(spec, @worker.Limits::host()))
    None
  } catch {
    error => Some(error)
  }
  guard refused is Some(@worker.DigestMismatch(expected~, actual~)) else {
    fail("expected a digest mismatch")
  }
  assert_eq(expected, @worker.Sha256::of(b"other bytes"))
  assert_eq(actual, @worker.Sha256::of(@fs.read_file(FIXTURE).binary()))
}

///|
#cfg(not(platform="windows"))
async test "a symbolic link to an artifact is refused" {
  let directory = @fs.tmpdir(prefix="morphir-worker-test-")
  defer (@fs.rmdir(directory, recursive=true) catch { _ => () })
  let link = directory + "/worker.sh"
  @fs.symlink(target=@fs.realpath(FIXTURE), link)
  let artifact = @worker.ArtifactRef::new(
    File(@worker.ArtifactPath::parse(link, Posix)),
    @worker.Sha256::of(@fs.read_file(FIXTURE).binary()),
  )
  let refused = try {
    ignore(@native.stage(artifact))
    None
  } catch {
    error => Some(error)
  }
  guard refused is Some(@worker.ArtifactUnreadable(SymbolicLink)) else {
    fail("expected a refused symbolic link")
  }
}

///|
#cfg(not(platform="windows"))
async test "a process launcher refuses other runtimes, platforms and memory artifacts" {
  let launcher = @native.ProcessLauncher::new()
  let other = if machine().runs(X86_64UnknownLinuxGnu) {
    @worker.Platform::Aarch64AppleDarwin
  } else {
    X86_64UnknownLinuxGnu
  }
  let refusals = []
  for
    spec in [
      @worker.WorkerSpec::new(fixture(), Wasm(abi=None)),
      @worker.WorkerSpec::new(fixture(), Process(platform=other, args=[])),
      @worker.WorkerSpec::new(
        @worker.ArtifactRef::new(
          Memory(b"#!/bin/sh\n"),
          @worker.Sha256::of(b"#!/bin/sh\n"),
        ),
        Process(platform=platform(), args=[]),
      ),
    ] {
    refusals.push(
      try {
        ignore(launcher.launch(spec, @worker.Limits::host()))
        "started"
      } catch {
        @worker.RuntimeUnavailable(supported~) =>
          "runtime \{@debug.to_string(supported)}"
        @worker.PlatformMismatch(platform) => "platform \{platform}"
        _ => "other refusal"
      },
    )
  }
  assert_eq(refusals, [
    "runtime [Process]",
    "platform \{other}",
    "runtime [Process]",
  ])
}

///|
#cfg(not(platform="windows"))
async test "a worker gets no user environment, its arguments unchanged and a private directory" {
  @env.set_env_var("MORPHIR_HOME", "/home/user/.morphir")
  @env.set_env_var("MORPHIR_TOKEN", "secret-token")
  let staged = @native.stage(fixture())
  let cwd = @fs.realpath(staged.working_directory())
  let channel = @native.ProcessLauncher::new().start(staged, [
    "report", "", "a b", "--", "", "$HOME", "\"q\"", "-",
  ])
  let probe = message({ "id": 1 })
  channel.send(probe)
  assert_eq(channel.receive(), probe)
  let stop = channel.close()
  assert_eq(stop.status, Exited(code=0))
  let report = text(stop.stderr.bytes())
  assert_true(report.contains("[][a b][--][][$HOME][\"q\"][-]\n"))
  assert_true(!report.contains("MORPHIR_HOME"))
  assert_true(!report.contains("secret-token"))
  assert_true(report.contains("env:|\n"))
  assert_true(report.contains("files:|\n"))
  assert_true(report.contains("fds:|\n"))
  assert_true(report.contains("cwd:\{cwd}\n"))
  // The private directory is gone after the confirmed stop.
  assert_true(!@fs.exists(staged.directory()))
}

///|
#cfg(not(platform="windows"))
async test "text on stdout that is not a frame stops the worker" {
  let channel = start("junk")
  let fault = try {
    ignore(channel.receive())
    None
  } catch {
    error => Some(error)
  }
  guard fault is Some(@worker.FrameInvalid(_)) else {
    fail("expected an invalid frame")
  }
  let stop = channel.abort(Fault)
  assert_eq(stop.status, Terminated(Fault))
  assert_eq(stop.stop_method, GroupSignal)
  assert_true(gone(channel.pid()))
}

///|
#cfg(not(platform="windows"))
async test "a frame above the message limit is refused before its body is read" {
  let limits = @worker.Limits::new(
    request_bytes=80,
    response_bytes=32,
    model=@worker.Limits::host().model,
  )
  let channel = start("echo", limits~)
  let large = message({ "padding": "a sentence longer than the limit" })
  let refused = try {
    channel.send(
      message({ "padding": "a sentence much longer than the limit, and longer" }),
    )
    None
  } catch {
    error => Some(error)
  }
  guard refused is Some(@worker.FrameLimit(direction=Request, limit=80, ..)) else {
    fail("expected a request frame limit")
  }
  channel.send(large)
  let fault = try {
    ignore(channel.receive())
    None
  } catch {
    error => Some(error)
  }
  guard fault is Some(@worker.FrameLimit(direction=Response, limit=32, ..)) else {
    fail("expected a response frame limit, got \{describe(fault)}")
  }
  assert_eq(channel.abort(Fault).status, Terminated(Fault))
}

///|
#cfg(not(platform="windows"))
async test "a noisy worker keeps the last 64 KiB of stderr and succeeds" {
  let channel = start("flood")
  let request = message({ "id": 2, "method": "compile" })
  channel.send(request)
  assert_eq(channel.receive(), request)
  let stop = channel.close()
  assert_eq(stop.status, Exited(code=0))
  let tail = stop.stderr.bytes()
  assert_eq(tail.length(), 65536)
  assert_true(stop.stderr.truncated())
  assert_eq(text(tail[65536 - 8:].to_owned()), "TAIL-END")
}

///|
#cfg(not(platform="windows"))
async test "abort(Deadline) stops the worker and its grandchild" {
  let channel = start("grandchild")
  let grandchild = grandchild_of(channel)
  assert_true(!gone(grandchild))
  let answer = @async.with_timeout_opt(200, () => channel.receive())
  assert_eq(answer, None)
  let stop = channel.abort(Deadline)
  assert_eq(stop.status, Terminated(Deadline))
  assert_eq(stop.stop_method, GroupSignal)
  assert_true(gone(channel.pid()))
  assert_true(gone(grandchild))
  // Every later call returns the first stop.
  assert_eq(channel.close(), stop)
  let after = try {
    ignore(channel.receive())
    None
  } catch {
    error => Some(error)
  }
  guard after is Some(@worker.Stopped) else { fail("expected Stopped") }
}

///|
#cfg(not(platform="windows"))
async test "abort(Cancelled) after a cancelled receive stops the worker and its grandchild" {
  let channel = start("grandchild")
  let grandchild = grandchild_of(channel)
  @async.with_task_group(group => {
    let pending = group.spawn(() => channel.receive())
    @async.sleep(100)
    pending.cancel()
  })
  let stop = channel.abort(Cancelled)
  assert_eq(stop.status, Terminated(Cancelled))
  assert_true(gone(channel.pid()))
  assert_true(gone(grandchild))
}

///|
#cfg(not(platform="windows"))
async test "a close that is cancelled in the grace period stops the tree at once" {
  let channel = start("stubborn")
  let grandchild = grandchild_of(channel)
  let started = @async.now()
  @async.with_task_group(group => {
    let closing = group.spawn(() => channel.close())
    @async.sleep(100)
    closing.cancel()
  })
  let stop = channel.close()
  assert_eq(stop.status, Terminated(Cancelled))
  assert_true(@async.now() - started < 1500L)
  assert_true(gone(channel.pid()))
  assert_true(gone(grandchild))
}

///|
#cfg(not(platform="windows"))
async test "an abort during the grace period wins" {
  let channel = start("stubborn")
  let grandchild = grandchild_of(channel)
  let stops = @async.all([
    () => channel.close(),
    () => {
      @async.sleep(100)
      channel.abort(Deadline)
    },
  ])
  assert_eq(stops[0], stops[1])
  assert_eq(stops[0].status, Terminated(Deadline))
  assert_true(gone(grandchild))
}

///|
#cfg(not(platform="windows"))
async test "a worker that ignores exit is stopped after the grace period" {
  let channel = start("stubborn")
  let grandchild = grandchild_of(channel)
  let started = @async.now()
  let stop = channel.close()
  let elapsed = @async.now() - started
  assert_eq(stop.status, Terminated(GraceExpired))
  assert_eq(stop.stop_method, GroupSignal)
  assert_true(elapsed >= 2000L)
  assert_true(elapsed < 2000L + 5000L)
  assert_true(gone(channel.pid()))
  assert_true(gone(grandchild))
}

///|
#cfg(not(platform="windows"))
async test "a grandchild left after the worker exits is stopped with it" {
  let channel = start("grandchild")
  let grandchild = grandchild_of(channel)
  let stop = channel.close()
  assert_eq(stop.status, Exited(code=0))
  assert_eq(stop.stop_method, GroupSignal)
  assert_true(gone(grandchild))
}

///|
#cfg(not(platform="windows"))
async test "a receive ends when the worker exits while its grandchild keeps stdout open" {
  let channel = start("orphan")
  let grandchild = grandchild_of(channel)
  let started = @async.now()
  let ended = @async.with_timeout_opt(5000, () => {
    try {
      ignore(channel.receive())
      None
    } catch {
      error => Some(error)
    }
  })
  guard ended is Some(Some(@worker.WorkerClosed)) else {
    ignore(channel.abort(Fault))
    fail("expected WorkerClosed, got \{describe(ended.unwrap_or(None))}")
  }
  assert_true(@async.now() - started < 2000L)
  assert_true(!gone(grandchild))
  let stop = channel.close()
  assert_eq(stop.status, Exited(code=0))
  assert_eq(stop.stop_method, GroupSignal)
  assert_true(gone(grandchild))
}

///|
#cfg(not(platform="windows"))
async test "an exit status and the end of stdin reach the host" {
  let exited = start("exit", args=["3"])
  let closed = try {
    ignore(exited.receive())
    None
  } catch {
    error => Some(error)
  }
  guard closed is Some(@worker.WorkerClosed) else {
    fail("expected WorkerClosed")
  }
  assert_eq(exited.close().status, Exited(code=3))
}

///|
#cfg(not(platform="windows"))
async test "a worker reads end of file when the host closes stdin, while another worker runs" {
  // The host is the only holder of each stdin pipe: a second worker does not
  // inherit the first worker's pipe, so the end of the host ends its input.
  let first = start("eof")
  let second = start("report")
  // Wait until the worker runs: under load, macOS can take seconds to
  // authorize an exec, and the grace period starts only at `close`.
  assert_eq(receive_or_report(first).json(), { "ready": true })
  let stop = first.close()
  assert_eq(
    stop.status,
    Exited(code=0),
    msg="stderr: [\{text(stop.stderr.bytes())}]",
  )
  assert_eq(stop.stop_method, ExitedAfterExit)
  assert_eq(text(stop.stderr.bytes()), "eof\n")
  let report = second.close()
  assert_true(text(report.stderr.bytes()).contains("fds:|\n"))
}

///|
#cfg(not(platform="windows"))
async test "an abort ends a send that waits on a full stdin" {
  let channel = start("stubborn")
  ignore(grandchild_of(channel))
  // The worker never reads stdin, so this write fills the pipe and waits.
  let large = message({ "padding": String::make(1000000, 'x') })
  @async.with_timeout(10000, () => {
    @async.with_task_group(group => {
      let sending = group.spawn(() => {
        try {
          channel.send(large)
          "sent"
        } catch {
          _ => "failed"
        }
      })
      @async.sleep(100)
      assert_eq(channel.abort(Deadline).status, Terminated(Deadline))
      assert_eq(sending.wait(), "failed")
    })
  })
  assert_true(gone(channel.pid()))
}

///|
#cfg(not(platform="windows"))
async test "a cancelled launch leaves no process and no private directory" {
  let root = @fs.tmpdir(prefix="morphir-worker-test-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let launcher = @native.ProcessLauncher::new(staging_root=root)
  let spec = @worker.WorkerSpec::new(
    fixture(),
    Process(platform=platform(), args=["stubborn"]),
  )
  let mut cancelled = 0
  for wait in 0..<20 {
    let launched = @async.with_timeout_opt(wait, () => {
      launcher.launch(spec, @worker.Limits::host())
    })
    match launched {
      Some(channel) =>
        assert_eq(channel.abort(Cancelled).status, Terminated(Cancelled))
      None => cancelled += 1
    }
  }
  assert_true(cancelled > 0)
  // No worker runs from the staging root: each one runs its staged copy, so
  // its arguments name the root.
  let running = processes_naming(root)
  assert_eq(running, [], msg="still running: \{running.join(", ")}")
  // The probe sees a worker that runs from the root.
  let probe = launcher.start(@native.stage(fixture(), root~), ["stubborn"])
  ignore(grandchild_of(probe))
  assert_true(processes_naming(root).length() > 0)
  assert_eq(probe.abort(Cancelled).status, Terminated(Cancelled))
  let left = @fs.readdir(root)
  let contents = []
  for name in left {
    let inside = @fs.readdir(root + "/" + name) catch { _ => [] }
    contents.push("\{name}: \{inside.join(" ")}")
  }
  assert_eq(left, [], msg="left behind: \{contents.join(", ")}")
}

///|
#cfg(not(platform="windows"))
async test "an artifact named work does not collide with the working directory" {
  let directory = @fs.tmpdir(prefix="morphir-worker-test-")
  defer (@fs.rmdir(directory, recursive=true) catch { _ => () })
  let original = directory + "/work"
  @fs.write_file(original, @fs.read_file(FIXTURE), permission=0o700)
  let staged = @native.stage(file_artifact(original))
  assert_true(staged.executable().has_suffix("/bin/work"))
  assert_true(staged.working_directory().has_suffix("/work"))
  assert_true(staged.executable() != staged.working_directory())
  let channel = @native.ProcessLauncher::new().start(staged, ["report"])
  let probe = message({ "id": 1 })
  channel.send(probe)
  assert_eq(receive_or_report(channel), probe)
  let stop = channel.close()
  assert_eq(stop.status, Exited(code=0))
  assert_true(text(stop.stderr.bytes()).contains("files:|\n"))
}

///|
#cfg(not(platform="windows"))
async test "many concurrent sessions see no transport fault" {
  // Regression: worker pipe ends registered with the host's event loop gave
  // false readiness to later pipes, and reads failed with EAGAIN.
  let failures = []
  for round in 0..<10 {
    @async.with_task_group(group => {
      for k in 0..<12 {
        group.spawn_bg(() => {
          let channel = start(if k % 2 == 0 { "grandchild" } else { "echo" })
          let problem = try {
            if k % 2 == 1 {
              channel.send(message({ "id": round * 100 + k }))
            }
            ignore(channel.receive())
            None
          } catch {
            error => Some(describe(Some(error)))
          }
          let stop = channel.abort(Deadline)
          if problem is Some(problem) {
            failures.push("\{problem}: \{@debug.to_string(stop.status)}")
          }
        })
      }
    })
  }
  assert_eq(failures, [])
}

///|
#cfg(not(platform="windows"))
async test "a FIFO artifact is refused without blocking" {
  let directory = @fs.tmpdir(prefix="morphir-worker-test-")
  defer (@fs.rmdir(directory, recursive=true) catch { _ => () })
  let fifo = directory + "/worker"
  ignore(@process.run("/usr/bin/mkfifo", [fifo]))
  let artifact = @worker.ArtifactRef::new(
    File(@worker.ArtifactPath::parse(fifo, Posix)),
    @worker.Sha256::of(b""),
  )
  let refused = @async.with_timeout_opt(2000, () => {
    try {
      ignore(@native.stage(artifact))
      None
    } catch {
      error => Some(error)
    }
  })
  guard refused is Some(Some(@worker.ArtifactUnreadable(NotRegularFile))) else {
    fail("expected a refused FIFO, got \{describe(refused.unwrap_or(None))}")
  }
}
