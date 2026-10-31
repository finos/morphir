///|
/// How many times the host called `kill` on the worker's group with SIGKILL,
/// the sweep included, whether or not the call found a member.
extern "js" fn Child::group_signals(self : Child) -> Int32 =
  #| (handle) => handle.groupSignals

///|
/// Emits an `error` event on one of the worker's pipes, as Node does when a
/// read or write fails.
extern "js" fn Child::fail_pipe(self : Child, name : String) -> Unit =
  #| (handle, name) => { handle.child[name].emit('error', new Error('EIO test fault')); }

///|
/// Makes a directory read-only, so that the host cannot remove its entries,
/// or writable again.
extern "js" fn set_writable(path : String, writable : Bool) -> Unit =
  #| (path, writable) => process.getBuiltinModule('node:fs').chmodSync(path, writable ? 0o700 : 0o500)

///|
/// The fixture worker's arguments: its script, then the flags.
fn fixture_args(flags : Array[@conformance.FixtureFlag]) -> Array[String] {
  [fixture_script(), ..flags.map(flag => flag.argument())]
}

///|
async test "a launch cancelled during the spawn leaves no process and no directory" {
  let staged = test_staged()
  let pid = Ref(0)
  let started = @async.with_timeout_opt(50, () => {
    NodeProcessChannel::start_with(
      staged,
      fixture_args([]),
      limits=@worker.Limits::host(),
      // The deadline passes while the spawn completes.
      spawned=child => {
        pid.val = child.pid()
        @async.sleep(200)
      },
    )
  })
  assert_true(started is None)
  assert_true(pid.val > 0)
  assert_false(process_alive(pid.val))
  assert_false(path_exists(staged.directory()))
}

///|
async test "a launch cancelled before the spawn starts nothing and removes the directory" {
  let staged = test_staged()
  let spawned = Ref(false)
  let started = @async.with_task_group(group => {
    let task = group.spawn(allow_failure=true, () => {
      // The cancellation lands here and waits for `start`.
      @async.protect_from_cancel(() => @async.sleep(200))
      Some(
        NodeProcessChannel::start_with(
          staged,
          fixture_args([]),
          limits=@worker.Limits::host(),
          spawned=_ => spawned.val = true,
        ),
      )
    })
    @async.sleep(20)
    task.cancel()
    task.try_wait()
  })
  assert_true(started is None)
  assert_false(spawned.val)
  assert_false(path_exists(staged.directory()))
}

///|
async test "a late close after an early exit sends no signal to the group" {
  guard !host_is_windows() else { return }
  let channel = NodeProcessChannel::start(
    test_staged(),
    fixture_args([Grandchild]),
  )
  channel.send(
    @worker.Message::new({ "jsonrpc": "2.0", "id": 1, "method": "crash" }),
  )
  ignore(channel.receive()) catch {
    _ => ()
  }
  channel.wait_exit()
  // The exit listener swept the group with the grandchild in it.
  assert_eq(channel.child.sweep(), 0)
  let signals = channel.child.group_signals()
  assert_eq(signals, 1)
  @async.sleep(100)
  let stop = channel.close()
  assert_eq(channel.child.group_signals(), signals)
  debug_inspect(stop.status, content="Exited(code=3)")
  debug_inspect(stop.stop_method, content="GroupSignal")
}

///|
async test "a private directory that cannot be removed makes the stop unconfirmed" {
  guard !host_is_windows() else { return }
  let staged = test_staged()
  let channel = NodeProcessChannel::start(staged, fixture_args([]))
  // The worker's working directory keeps an entry that the host cannot
  // remove while the directory is read-only.
  write_file(join_path(staged.working_directory(), "kept"), "")
  set_writable(staged.working_directory(), false)
  channel.send(@worker.Message::new({ "jsonrpc": "2.0", "method": "exit" }))
  let started = @async.now()
  let stop = channel.close()
  let waited = @async.now() - started
  set_writable(staged.working_directory(), true)
  assert_true(path_exists(staged.directory()))
  ignore(remove_directory(staged.directory()))
  debug_inspect(stop.status, content="Unconfirmed(GraceExpired)")
  debug_inspect(stop.stop_method, content="ExitedAfterExit")
  // The host retried the removal for its bound.
  assert_true(waited >= (@process.REMOVE_RETRY_MS - 100).to_int64())
}

///|
async test "a failed pipe is a transport fault, and the host does not crash" {
  for name in ["stderr", "stdout", "stdin"] {
    let channel = NodeProcessChannel::start(test_staged(), fixture_args([]))
    channel.child.fail_pipe(name)
    let refused = try {
      ignore(channel.receive())
      None
    } catch {
      @worker.TransportFailed(message) => Some(message)
      _ => None
    }
    assert_eq(
      refused,
      Some("the worker's \{name} pipe failed: EIO test fault"),
      msg=name,
    )
    let refused = try {
      channel.send(@worker.Message::new({ "jsonrpc": "2.0", "method": "exit" }))
      None
    } catch {
      @worker.TransportFailed(message) => Some(message)
      _ => None
    }
    assert_true(refused is Some(_), msg=name)
    let stop = channel.abort(Fault)
    assert_true(stop.status is Terminated(Fault), msg=name)
  }
}
