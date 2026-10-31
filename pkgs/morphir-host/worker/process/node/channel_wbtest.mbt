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
/// Creates a file and opens it with no sharing, through libuv's
/// `UV_FS_O_EXLOCK` flag (0x10000000, Windows only). While the descriptor is
/// open, no other handle can open or delete the file. Returns the descriptor.
extern "js" fn open_unshared(path : String) -> Int32 =
  #| (path) => {
  #|   const fs = process.getBuiltinModule('node:fs');
  #|   const UV_FS_O_EXLOCK = 0x10000000;
  #|   return fs.openSync(path, fs.constants.O_RDWR | fs.constants.O_CREAT | UV_FS_O_EXLOCK);
  #| }

///|
extern "js" fn close_file(fd : Int32) -> Unit =
  #| (fd) => process.getBuiltinModule('node:fs').closeSync(fd)

///|
/// What keeps the host from removing a worker's working directory in a test.
priv enum RemovalBlock {
  /// Unix: the directory is read-only, so its entry `kept` stays.
  ReadOnly(String)
  /// Windows: the test holds the entry `kept` open with no sharing, so no
  /// one can delete it.
  OpenFile(Int32)
}

///|
/// Puts an entry `kept` in the directory that the host cannot remove.
fn RemovalBlock::hold(directory : String) -> RemovalBlock {
  let kept = join_path(directory, "kept")
  match Tree::host() {
    Group => {
      write_file(kept, "")
      set_writable(directory, false)
      ReadOnly(directory)
    }
    RootTree => OpenFile(open_unshared(kept))
  }
}

///|
/// Lets the host remove the directory again.
fn RemovalBlock::release(self : RemovalBlock) -> Unit {
  match self {
    ReadOnly(directory) => set_writable(directory, true)
    OpenFile(fd) => close_file(fd)
  }
}

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
async test "a late close after an early exit does not stop the tree again" {
  let tree = Tree::host()
  // On Unix the grandchild shows that the exit listener swept the group. On
  // Windows `taskkill` cannot reach the tree after its root has exited, so
  // the worker starts no grandchild that would outlive the test.
  let flags : Array[@conformance.FixtureFlag] = match tree {
    Group => [Grandchild]
    RootTree => []
  }
  let channel = NodeProcessChannel::start(test_staged(), fixture_args(flags))
  channel.send(
    @worker.Message::new({ "jsonrpc": "2.0", "id": 1, "method": "crash" }),
  )
  ignore(channel.receive()) catch {
    _ => ()
  }
  channel.wait_exit()
  let signals = channel.child.group_signals()
  if tree is Group {
    // The exit listener swept the group with the grandchild in it.
    assert_eq(channel.child.sweep(), 0)
    assert_eq(signals, 1)
  }
  @async.sleep(100)
  let stop = channel.close()
  debug_inspect(stop.status, content="Exited(code=3)")
  match tree {
    // No signal after the sweep: another process can have the group ID now.
    Group => {
      assert_eq(channel.child.group_signals(), signals)
      debug_inspect(stop.stop_method, content="GroupSignal")
    }
    // No `taskkill` after the exit: another process can have the root's PID
    // now. A tree termination would report `TreeTermination`.
    RootTree => debug_inspect(stop.stop_method, content="ExitedAfterExit")
  }
}

///|
async test "a private directory that cannot be removed makes the stop unconfirmed" {
  let staged = test_staged()
  let channel = NodeProcessChannel::start(staged, fixture_args([]))
  // The worker's working directory keeps an entry that the host cannot
  // remove: on Unix the directory is read-only, on Windows the test holds
  // the entry open with no sharing.
  let block = RemovalBlock::hold(staged.working_directory())
  channel.send(@worker.Message::new({ "jsonrpc": "2.0", "method": "exit" }))
  let started = @async.now()
  let stop = channel.close()
  let waited = @async.now() - started
  block.release()
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
