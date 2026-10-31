///|
/// One case of the conformance suite.
pub struct Case {
  name : String
  priv run : async (Run) -> Unit
}

///|
/// The fixture and the channels that one case started. The suite aborts every
/// channel after the case, so a failed case leaves no worker behind.
priv struct Run {
  fixture : &Fixture
  channels : Array[&@worker.Channel]
}

///|
async fn Run::start(
  self : Run,
  flags : Array[FixtureFlag],
  args~ : Array[String] = [],
  limits~ : @worker.Limits = @worker.Limits::host(),
) -> &@worker.Channel {
  let channel = self.fixture.start(flags, args, limits)
  self.channels.push(channel)
  channel
}

///|
fn request(id : Int32, name : String, params? : Json) -> @worker.Message {
  let body : Map[String, Json] = {
    "jsonrpc": "2.0",
    "id": Json(id),
    "method": Json(name),
  }
  if params is Some(params) {
    body["params"] = params
  }
  @worker.Message::new(body)
}

///|
fn notification(name : String) -> @worker.Message {
  @worker.Message::new({ "jsonrpc": "2.0", "method": Json(name) })
}

///|
/// Sends one request and returns the result of its response.
async fn call(
  channel : &@worker.Channel,
  id : Int32,
  name : String,
  params? : Json,
) -> Json {
  channel.send(request(id, name, params?))
  match channel.receive().json() {
    { "id": Number(answered, ..), "result": result, .. } if answered ==
      id.to_double() => result
    reply => fail("unexpected reply to \{name}: \{reply.stringify()}")
  }
}

///|
async fn pids(channel : &@worker.Channel, id : Int32) -> (Int32, Int32) {
  match call(channel, id, "pids") {
    { "worker": Number(worker, ..), "grandchild": Number(grandchild, ..), .. } =>
      (worker.to_int(), grandchild.to_int())
    result => fail("the fixture has no grandchild: \{result.stringify()}")
  }
}

///|
/// Runs an action that must raise a channel error and returns that error.
async fn channel_error(action : async () -> Unit) -> @worker.ChannelError {
  action() catch {
    @worker.WorkerClosed => return WorkerClosed
    @worker.FrameInvalid(message) => return FrameInvalid(message)
    @worker.FrameLimit(direction~, declared~, limit~) =>
      return FrameLimit(direction~, declared~, limit~)
    @worker.Stopped => return Stopped
    @worker.TransportFailed(message) => return TransportFailed(message)
    error => fail("expected a channel error, got \{error}")
  }
  fail("expected a channel error")
}

///|
fn expect_stop(
  stop : @worker.WorkerStop,
  status : @worker.StopStatus,
  stop_method : @worker.StopMethod,
) -> Unit raise {
  guard stop.status == status && stop.stop_method == stop_method else {
    fail(
      "expected \{@debug.to_string(status)} by \{@debug.to_string(stop_method)}, got \{@debug.to_string(stop)}",
    )
  }
}

///|
fn expect_gone(run : Run, pids : Array[Int32]) -> Unit raise {
  for pid in pids {
    guard !run.fixture.alive(pid) else { fail("process \{pid} still runs") }
  }
}

///|
async fn echo_round_trip(run : Run) -> Unit {
  let channel = run.start([])
  let params : Json = { "text": "λ and 😀" }
  assert_eq(call(channel, 1, "echo", params~), params)
  assert_eq(call(channel, 2, "echo", params=[1, 2, 3]), [1, 2, 3])
  channel.send(notification("exit"))
  let stop = channel.close()
  expect_stop(stop, Exited(code=0), ExitedAfterExit)
  assert_eq(stop.stderr.bytes(), b"")
}

///|
async fn arguments_unchanged(run : Run) -> Unit {
  let args = ["", "two words", "--", "-x", "\"quoted\"", "", "end"]
  let channel = run.start([], args~)
  assert_eq(call(channel, 1, "argv"), { "args": Json(args) })
  channel.send(notification("exit"))
  ignore(channel.close())
}

///|
async fn documented_environment(run : Run) -> Unit {
  let channel = run.start([])
  let names = match call(channel, 1, "env") {
    { "names": Array(names), .. } => names
    result => fail("unexpected env result: \{result.stringify()}")
  }
  let documented = run.fixture.documented_environment()
  for name in names {
    guard name is String(name) && documented.contains(name) else {
      fail("the worker sees an undocumented variable: \{name.stringify()}")
    }
  }
  channel.send(notification("exit"))
  ignore(channel.close())
}

///|
async fn empty_working_directory(run : Run) -> Unit {
  let channel = run.start([])
  match call(channel, 1, "cwd") {
    // Unix: only the worker's user may use the directory (mode 0700).
    { "entries": 0, "mode": 448, "ownedByWorker": True, .. } => ()
    // Windows has no mode bits; the fixture reports none.
    { "entries": 0, "mode": Null, "ownedByWorker": Null, .. } => ()
    result =>
      fail(
        "the working directory is not empty and private: \{result.stringify()}",
      )
  }
  channel.send(notification("exit"))
  ignore(channel.close())
}

///|
async fn inherited_descriptors(run : Run) -> Unit {
  let held = run.fixture.held_open()
  let channel = run.start([])
  let descriptors = match call(channel, 1, "fds") {
    // Windows has no descriptor list; the case does not apply.
    { "descriptors": Null, .. } => {
      channel.send(notification("exit"))
      ignore(channel.close())
      return
    }
    { "descriptors": Array(descriptors), .. } => descriptors
    result => fail("unexpected fds result: \{result.stringify()}")
  }
  let fds = descriptors.filter_map(entry => {
    guard entry is { "fd": Number(fd, ..), "id": String(id), .. } else {
      return None
    }
    Some((fd.to_int(), id))
  })
  for expected in [0, 1, 2] {
    guard fds.iter().any(entry => entry.0 == expected) else {
      fail("the worker has no descriptor \{expected}")
    }
  }
  for entry in fds {
    let (fd, id) = entry
    guard fd <= 2 || !held.contains(id) else {
      fail("the worker inherited the host's descriptor for \{id} as \{fd}")
    }
  }
  channel.send(notification("exit"))
  ignore(channel.close())
}

///|
async fn unread_stdin(run : Run) -> Unit {
  let channel = run.start([IgnoreStdin])
  // More than a pipe holds: the write cannot finish.
  let message = request(1, "echo", params=Json("x".repeat(2 * 1024 * 1024)))
  guard @async.with_timeout_opt(300, () => channel.send(message)) is None else {
    fail("a send to a worker that does not read stdin finished")
  }
  let stop = channel.abort(Deadline)
  expect_stop(stop, Terminated(Deadline), run.fixture.ownership().stop_method())
}

///|
async fn console_before_frame(run : Run) -> Unit {
  let channel = run.start([])
  channel.send(request(1, "console"))
  // `console.log` writes `x` and a bare LF, then the worker hangs.
  let refused = @async.with_timeout_opt(5000, () => {
    channel_error(() => ignore(channel.receive()))
  })
  guard refused is Some(FrameInvalid(_)) else {
    fail(
      "console output was not an invalid frame at once: \{@debug.to_string(refused)}",
    )
  }
  ignore(channel.abort(Fault))
}

///|
async fn receive_during_abort(run : Run) -> Unit {
  let channel = run.start([])
  channel.send(request(1, "hang"))
  let (refused, stop) = @async.with_task_group(group => {
    let receiving = group.spawn(() => {
      channel_error(() => ignore(channel.receive()))
    })
    @async.sleep(100)
    let stop = channel.abort(Fault)
    (receiving.wait(), stop)
  })
  guard refused is Stopped else {
    fail("a receive that overlaps an abort raised \{@debug.to_string(refused)}")
  }
  expect_stop(stop, Terminated(Fault), run.fixture.ownership().stop_method())
}

///|
async fn output_after_input(run : Run) -> Unit {
  let channel = run.start([FloodOnExit])
  ignore(call(channel, 1, "echo"))
  channel.send(notification("exit"))
  let started = @async.now()
  let stop = channel.close()
  expect_stop(stop, Exited(code=0), ExitedAfterExit)
  guard @async.now() - started < @process.EXIT_GRACE_MS.to_int64() else {
    fail("the host waited for the grace")
  }
}

///|
async fn log_on_stdout(run : Run) -> Unit {
  let channel = run.start([])
  channel.send(request(1, "log"))
  guard channel_error(() => ignore(channel.receive())) is FrameInvalid(_) else {
    fail("a log line on stdout was not an invalid frame")
  }
  let stop = channel.abort(Fault)
  expect_stop(stop, Terminated(Fault), run.fixture.ownership().stop_method())
}

///|
async fn oversized_response(run : Run) -> Unit {
  let channel = run.start([])
  channel.send(request(1, "oversized"))
  let limit = @worker.Limits::host().response_bytes
  guard channel_error(() => ignore(channel.receive()))
    is FrameLimit(direction=Response, declared=16777217L, limit=refused) &&
    refused == limit else {
    fail("an oversized response was not refused at its declared size")
  }
  ignore(channel.abort(Fault))
}

///|
async fn launch_limits(run : Run) -> Unit {
  let limits = @worker.Limits::new(
    request_bytes=256,
    response_bytes=128,
    model=@worker.Limits::host().model,
  )
  let channel = run.start([], limits~)
  // The request fits in 256 bytes; its echo does not fit in 128.
  channel.send(request(1, "echo", params=Json("x".repeat(100))))
  guard channel_error(() => ignore(channel.receive()))
    is FrameLimit(direction=Response, declared~, limit=128) &&
    declared > 128L else {
    fail("a response above the launch limit was not refused")
  }
  guard channel_error(() => {
      channel.send(request(2, "echo", params=Json("x".repeat(300))))
    })
    is FrameLimit(direction=Request, declared~, limit=256) &&
    declared > 256L else {
    fail("a request above the launch limit was not refused")
  }
  ignore(channel.abort(Fault))
}

///|
async fn noisy_stderr(run : Run) -> Unit {
  let channel = run.start([])
  let bytes = 10 * 1024 * 1024
  assert_eq(call(channel, 1, "stderr", params={ "bytes": Json(bytes) }), {
    "written": Json(bytes),
  })
  channel.send(notification("exit"))
  let stop = channel.close()
  expect_stop(stop, Exited(code=0), ExitedAfterExit)
  let tail = stop.stderr.bytes()
  assert_eq(tail.length(), 65536)
  assert_true(stop.stderr.truncated())
  assert_eq(tail[tail.length() - 12:].to_owned(), b"\nstderr end\n")
}

///|
async fn early_exit(run : Run) -> Unit {
  let channel = run.start([])
  channel.send(request(1, "crash"))
  guard channel_error(() => ignore(channel.receive())) is WorkerClosed else {
    fail("an early exit did not close the stream")
  }
  expect_stop(channel.close(), Exited(code=3), ExitedAfterExit)
}

///|
async fn deadline_stops_tree(run : Run) -> Unit {
  let channel = run.start([Grandchild])
  let (worker, grandchild) = pids(channel, 1)
  channel.send(request(2, "hang"))
  // A timeout cancels the receive; the channel must let it pass.
  guard @async.with_timeout_opt(200, () => channel.receive()) is None else {
    fail("a hanging worker answered")
  }
  let stop = channel.abort(Deadline)
  expect_stop(stop, Terminated(Deadline), run.fixture.ownership().stop_method())
  expect_gone(run, [worker, grandchild])
}

///|
async fn cancellation_stops_tree(run : Run) -> Unit {
  let channel = run.start([Grandchild])
  let (worker, grandchild) = pids(channel, 1)
  channel.send(request(2, "hang"))
  @async.with_task_group(group => {
    let task = group.spawn(allow_failure=true, () => ignore(channel.receive()))
    @async.sleep(100)
    task.cancel()
  })
  let stop = channel.abort(Cancelled)
  expect_stop(
    stop,
    Terminated(Cancelled),
    run.fixture.ownership().stop_method(),
  )
  expect_gone(run, [worker, grandchild])
}

///|
async fn ignored_exit(run : Run) -> Unit {
  let channel = run.start([IgnoreExit, Grandchild])
  let (worker, grandchild) = pids(channel, 1)
  channel.send(notification("exit"))
  let started = @async.now()
  let stop = channel.close()
  let waited = @async.now() - started
  expect_stop(
    stop,
    Terminated(GraceExpired),
    run.fixture.ownership().stop_method(),
  )
  guard waited >= (@process.EXIT_GRACE_MS - 100).to_int64() else {
    fail("the host stopped the worker after \{waited} ms, before the grace")
  }
  expect_gone(run, [worker, grandchild])
}

///|
async fn abort_during_grace(run : Run) -> Unit {
  let channel = run.start([IgnoreExit])
  ignore(call(channel, 1, "echo"))
  channel.send(notification("exit"))
  let started = @async.now()
  let (closed, aborted) = @async.with_task_group(group => {
    let closing = group.spawn(() => channel.close())
    @async.sleep(200)
    let aborted = channel.abort(Deadline)
    (closing.wait(), aborted)
  })
  let waited = @async.now() - started
  expect_stop(
    aborted,
    Terminated(Deadline),
    run.fixture.ownership().stop_method(),
  )
  assert_eq(closed, aborted)
  guard waited < @process.EXIT_GRACE_MS.to_int64() else {
    fail("the abort waited \{waited} ms for the grace")
  }
}

///|
async fn first_stop_kept(run : Run) -> Unit {
  let channel = run.start([])
  channel.send(notification("exit"))
  let stop = channel.close()
  assert_eq(channel.abort(Deadline), stop)
  assert_eq(channel.close(), stop)
  guard channel_error(() => channel.send(request(1, "echo"))) is Stopped else {
    fail("send after the stop was not refused")
  }
  guard channel_error(() => ignore(channel.receive())) is Stopped else {
    fail("receive after the stop was not refused")
  }
}

///|
async fn end_of_input(run : Run) -> Unit {
  let channel = run.start([])
  ignore(call(channel, 1, "echo"))
  // Without `exit`, the end of stdin stops the fixture.
  expect_stop(channel.close(), Exited(code=0), ExitedAfterExit)
}

///|
async fn descendants_after_exit(run : Run) -> Unit {
  let ownership = run.fixture.ownership()
  guard ownership is (Group | Job) else { return }
  let channel = run.start([Grandchild])
  let (worker, grandchild) = pids(channel, 1)
  channel.send(notification("exit"))
  let stop = channel.close()
  expect_stop(stop, Exited(code=0), ownership.stop_method())
  expect_gone(run, [worker, grandchild])
}

///|
/// Every case, in the order the suite runs them.
pub fn cases() -> Array[Case] {
  [
    { name: "echo round trip and exit", run: echo_round_trip, },
    { name: "arguments forwarded unchanged", run: arguments_unchanged, },
    {
      name: "environment holds only documented variables",
      run: documented_environment,
    },
    {
      name: "working directory is empty and private",
      run: empty_working_directory,
    },
    {
      name: "worker inherits no descriptor that the host holds",
      run: inherited_descriptors,
    },
    { name: "log on stdout is an invalid frame", run: log_on_stdout, },
    {
      name: "console output before a frame is an invalid frame at once",
      run: console_before_frame,
    },
    {
      name: "oversized response is refused at its declared size",
      run: oversized_response,
    },
    {
      name: "launch limits apply to requests and responses",
      run: launch_limits,
    },
    { name: "noisy stderr keeps the last 64 KiB", run: noisy_stderr, },
    { name: "early exit closes the stream", run: early_exit, },
    {
      name: "deadline stops the worker and its grandchild",
      run: deadline_stops_tree,
    },
    {
      name: "cancellation stops the worker and its grandchild",
      run: cancellation_stops_tree,
    },
    {
      name: "worker that ignores exit is stopped after the grace",
      run: ignored_exit,
    },
    { name: "abort during the grace wait wins", run: abort_during_grace, },
    {
      name: "first stop is kept and later calls are refused",
      run: first_stop_kept,
    },
    { name: "end of stdin stops the worker", run: end_of_input, },
    {
      name: "worker that writes after its input ends exits within the grace",
      run: output_after_input,
    },
    {
      name: "send to a worker that does not read stdin passes the deadline",
      run: unread_stdin,
    },
    {
      name: "receive that overlaps an abort raises Stopped",
      run: receive_during_abort,
    },
    {
      name: "descendants stop after the worker exits",
      run: descendants_after_exit,
    },
  ]
}

///|
/// Runs one case and then aborts every channel it started.
pub async fn Case::check(self : Case, fixture : &Fixture) -> Unit {
  let run = { fixture, channels: [], }
  defer @async.protect_from_cancel(() => {
    for channel in run.channels {
      ignore(channel.abort(Fault))
    }
  })
  @async.with_timeout(30000, () => (self.run)(run))
}

///|
/// Runs every case and fails with the name and error of each failed case.
pub async fn check(fixture : &Fixture) -> Unit {
  let failures = []
  for case in cases() {
    case.check(fixture) catch {
      error => failures.push("\{case.name}: \{error}")
    }
  }
  guard failures.is_empty() else {
    fail("process launcher conformance failed:\n" + failures.join("\n"))
  }
}
