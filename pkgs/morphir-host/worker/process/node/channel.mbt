///|
/// A process worker that Node's `child_process` runs. It owns the worker's
/// tree: a process group on Unix, the root's tree on Windows.
pub struct NodeProcessChannel {
  priv child : Child
  priv pid : Int32
  priv tree : Tree
  priv directory : String
  priv stdout : @js_async.ReadableStream
  priv reader : @process.FrameReader
  priv writer : @process.FrameWriter
  priv pending : @deque.Deque[@worker.Message]
  priv stderr : @process.StderrBuffer
  /// Abort reasons that reach a `close` waiting for the grace period.
  priv aborts : @aqueue.Queue[@worker.StopReason]
  priv stopped : @async.CondVar
  /// Whether a `receive` reads stdout now.
  priv mut reading : Bool
  priv mut stopping : Bool
  priv mut stop : @worker.WorkerStop?
}

///|
/// Starts the staged artifact with the argument array, unchanged, in its
/// empty private working directory. The channel owns the staged directory
/// from now on and checks frames against `limits`.
///
/// A launch that is cancelled stops what it already started: before the
/// spawn it removes the directory, and after the spawn it aborts the channel,
/// which stops the tree, confirms the stop and removes the directory.
pub async fn NodeProcessChannel::start(
  staged : @process.StagedArtifact,
  args : Array[String],
  limits~ : @worker.Limits = @worker.Limits::host(),
) -> NodeProcessChannel {
  NodeProcessChannel::start_with(staged, args, limits~, spawned=_ => ())
}

///|
/// `start` with a step that runs, safe from cancellation, between the spawn
/// and the cancellation checkpoint. Tests use it to cancel a launch there.
async fn NodeProcessChannel::start_with(
  staged : @process.StagedArtifact,
  args : Array[String],
  limits~ : @worker.Limits,
  spawned~ : async (Child) -> Unit,
) -> NodeProcessChannel {
  let directory = staged.directory()
  if @async.is_being_cancelled() {
    @async.protect_from_cancel(() => ignore(remove_directory(directory)))
    @async.pause()
  }
  let stderr = @process.StderrBuffer::new()
  // The spawn cannot be cancelled: Node starts the process or fails at once.
  let child = Child::spawn(
    staged.executable(),
    FixedArray::from_array(args),
    staged.working_directory(),
    chunk => stderr.write(chunk),
  ).wait() catch {
    error => {
      @async.protect_from_cancel(() => ignore(remove_directory(directory)))
      raise @worker.LaunchFailed("cannot start the worker: \{error}")
    }
  }
  let channel = {
    child,
    pid: child.pid(),
    tree: Tree::host(),
    directory,
    stdout: @js_async.ReadableStream::from_js(child.stdout()),
    reader: @process.FrameReader::new(limit=limits.response_bytes),
    writer: @process.FrameWriter::new(limit=limits.request_bytes),
    pending: @deque.Deque([]),
    stderr,
    aborts: @aqueue.Queue(kind=Unbounded),
    stopped: @async.CondVar::Cond(),
    reading: false,
    stopping: false,
    stop: None,
  }
  @async.protect_from_cancel(() => spawned(child))
  // The checkpoint: a launch cancelled during the spawn stops the worker
  // before the cancellation leaves this function.
  if @async.is_being_cancelled() {
    ignore(channel.abort(Cancelled))
    @async.pause()
  }
  channel
}

///|
/// The exit status, once the `exit` event has arrived.
fn Child::status(self : Child) -> @worker.StopStatus? {
  match (self.exit_code(), self.exit_signal()) {
    (code, _) if code >= 0 => Some(Exited(code~))
    (_, signal) if signal > 0 => Some(Signalled(signal~))
    _ => None
  }
}

///|
async fn NodeProcessChannel::wait_exit(self : NodeProcessChannel) -> Unit {
  @js_async.run_promise(signal => self.child.exited(signal))
}

///|
/// Waits at most `bound` ms for the worker's exit. Returns whether it exited.
async fn NodeProcessChannel::exits_within(
  self : NodeProcessChannel,
  bound : Int32,
) -> Bool {
  @async.with_timeout_opt(bound, () => self.wait_exit()) is Some(_)
}

///|
/// Waits until the process group that a signal reached has no member left.
/// The members keep the group ID, so it cannot be reused while they remain.
async fn NodeProcessChannel::group_emptied(
  self : NodeProcessChannel,
  started : Int64,
) -> Bool {
  while group_present(self.pid) {
    guard @async.now() - started < @process.STOP_CONFIRM_MS.to_int64() else {
      return false
    }
    @async.sleep(10)
  }
  true
}

///|
/// Signals the worker's process group and confirms that it is empty. The
/// host signals the group only while the worker has not exited; the `exit`
/// listener sweeps it in the same tick as the reap, and the host never
/// signals it after that.
async fn NodeProcessChannel::stop_group(
  self : NodeProcessChannel,
) -> TreeAction {
  let started = @async.now()
  // 1: the group is gone. 0 and 2 (macOS refuses a group that holds only
  // zombies) leave the confirmation to decide.
  let signalled = self.child.signal_group() != 1
  guard self.exits_within(@process.STOP_CONFIRM_MS) else { return Unconfirmed }
  match self.child.sweep() {
    1 => if signalled { Stopped } else { NotNeeded }
    // The sweep reached descendants that outlived the worker.
    _ => if self.group_emptied(started) { Stopped } else { Unconfirmed }
  }
}

///|
/// Stops the worker's tree with `taskkill /T /F` and confirms that the root
/// has exited. After the root has exited, `taskkill` cannot reach its tree.
async fn NodeProcessChannel::stop_root(
  self : NodeProcessChannel,
  before : @worker.StopStatus?,
) -> TreeAction {
  if before is Some(_) {
    return NotNeeded
  }
  ignore(
    @async.with_timeout_opt(@process.STOP_CONFIRM_MS, () => {
      @js_async.run_promise(signal => kill_tree(self.pid, signal))
    }) catch {
      _ => None
    },
  )
  if self.exits_within(@process.STOP_CONFIRM_MS) {
    Stopped
  } else {
    Unconfirmed
  }
}

///|
/// Stops the tree, records the first stop and wakes every waiter. The host
/// removes the private directory only after it confirms the stop, and a
/// directory that it cannot remove makes the stop unconfirmed.
async fn NodeProcessChannel::stop_tree(
  self : NodeProcessChannel,
  reason : @worker.StopReason,
) -> @worker.WorkerStop {
  let before = self.child.status()
  let action = match self.tree {
    Group => self.stop_group()
    RootTree => self.stop_root(before)
  }
  let removed = if action != Unconfirmed {
    // The stopped tree no longer holds stderr open; take its last bytes.
    ignore(
      @async.with_timeout_opt(1000, () => {
        @js_async.run_promise(signal => self.child.stderr_closed(signal))
      }) catch {
        _ => None
      },
    )
    remove_directory(self.directory)
  } else {
    // The tree may still run; it must not keep the host alive.
    self.child.release()
    false
  }
  let (status, stop_method) = stop_result(
    self.tree,
    reason,
    action,
    before~,
    after=self.child.status(),
    removed~,
  )
  let stop = @worker.WorkerStop::new(
    status,
    stop_method~,
    stderr=self.stderr.tail(),
  )
  self.stop = Some(stop)
  self.stdout.close()
  self.aborts.close()
  self.stopped.broadcast()
  stop
}

///|
/// Waits for the stop that another call has started.
async fn NodeProcessChannel::wait_stop(
  self : NodeProcessChannel,
) -> @worker.WorkerStop {
  @async.protect_from_cancel(() => {
    while self.stop is None {
      self.stopped.wait()
    }
    self.stop.unwrap()
  })
}

///|
/// Refuses a call once the stop has started, and raises the first pipe fault.
fn NodeProcessChannel::check_open(
  self : NodeProcessChannel,
) -> Unit raise @worker.ChannelError {
  guard !self.stopping else { raise Stopped }
  if self.child.fault() is Some(fault) {
    raise TransportFailed(fault)
  }
}

///|
/// Reads and discards stdout until it ends, so that a worker which writes
/// after the end of its input does not block on a full pipe. It waits for a
/// `receive` that reads now, which discards what it reads.
async fn NodeProcessChannel::discard_output(self : NodeProcessChannel) -> Unit {
  while self.reading {
    @async.sleep(5)
  }
  while (self.stdout.read_some() catch { _ => None }) is Some(_) {

  }
}

///|
/// Reads one chunk of stdout and records that a read is in progress.
async fn NodeProcessChannel::read_chunk(self : NodeProcessChannel) -> Bytes? {
  self.reading = true
  defer {
    self.reading = false
  }
  self.stdout.read_some()
}

///|
pub extend NodeProcessChannel with @worker.Channel::{
  send,
  receive,
  close,
  abort,
}

///|
pub impl @worker.Channel for NodeProcessChannel with fn send(self, message) {
  self.check_open()
  let frame = self.writer.encode(message)
  let written = @js_async.run_promise(signal => self.child.write(frame, signal)) catch {
    _ => 2
  }
  // A write that overlaps a stop ends with the stop.
  guard !self.stopping else { raise @worker.Stopped }
  match written {
    0 => ()
    1 => raise @worker.WorkerClosed
    _ =>
      raise @worker.TransportFailed(
        self.child.fault().unwrap_or("the worker's stdin pipe failed"),
      )
  }
}

///|
pub impl @worker.Channel for NodeProcessChannel with fn receive(self) {
  self.check_open()
  while self.pending.is_empty() {
    let chunk = self.read_chunk() catch {
      error => {
        // A read that overlaps a stop ends with the stop.
        guard !self.stopping else { raise @worker.Stopped }
        raise @worker.TransportFailed(
          self.child
          .fault()
          .unwrap_or("the worker's stdout pipe failed: \{error}"),
        )
      }
    }
    guard !self.stopping else { raise @worker.Stopped }
    guard chunk is Some(bytes) else {
      self.reader.finish()
      raise @worker.WorkerClosed
    }
    for message in self.reader.feed(bytes) {
      self.pending.push_back(message)
    }
  }
  self.pending.pop_front().unwrap()
}

///|
pub impl @worker.Channel for NodeProcessChannel with fn close(self) {
  if self.stop is Some(stop) {
    return stop
  }
  if self.stopping {
    return self.wait_stop()
  }
  self.stopping = true
  @async.protect_from_cancel(() => {
    self.child.end_input()
    let woken = @async.with_timeout_opt(@process.EXIT_GRACE_MS, () => {
      @async.any([
        () => {
          self.wait_exit()
          None
        },
        () => Some(self.aborts.get()),
        () => {
          self.discard_output()
          self.wait_exit()
          None
        },
      ])
    }) catch {
      _ => None
    }
    // An abort during the wait wins; otherwise the grace has passed or the
    // worker has exited, and `stop_tree` sees its exit.
    let reason : @worker.StopReason = match woken {
      Some(Some(reason)) => reason
      _ => GraceExpired
    }
    self.stop_tree(reason)
  })
}

///|
pub impl @worker.Channel for NodeProcessChannel with fn abort(self, reason) {
  if self.stop is Some(stop) {
    return stop
  }
  if self.stopping {
    ignore(self.aborts.try_put(reason) catch { _ => false })
    return self.wait_stop()
  }
  self.stopping = true
  @async.protect_from_cancel(() => self.stop_tree(reason))
}
