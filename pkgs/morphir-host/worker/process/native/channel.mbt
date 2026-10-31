///|
/// The largest chunk that one read from a worker's stdout or stderr takes.
const READ_CHUNK_BYTES : Int32 = 65536

///|
/// After the leader has exited, a read of stdout waits at most this long
/// for more bytes. A grandchild that keeps stdout open then cannot hold a
/// `receive` until the session's deadline.
pub const EXITED_READ_MS : Int32 = 200

///|
/// What ends one wait for stdout: a read, or the exit of the leader.
priv enum OutputEvent {
  Read(Bytes?)
  LeaderGone
}

///|
/// How a stop began: the worker exited during the grace period of `close`,
/// or the host stopped it.
priv enum Ending {
  LeaderExited(Int32)
  Stop(@worker.StopReason)
}

///|
/// The host end of a native process worker. Messages travel as
/// Content-Length frames on the worker's stdin and stdout; stderr is drained
/// while any call runs and only its last 64 KiB are kept.
pub struct ProcessChannel {
  priv worker : Spawned
  priv staged : @shared.StagedArtifact
  priv grace_ms : Int32
  priv confirm_ms : Int32
  priv reader : @shared.FrameReader
  priv writer : @shared.FrameWriter
  priv pending : Array[@worker.Message]
  priv leader : Leader
  priv drain : StderrDrain
  priv lock : @async.Mutex
  priv mut active : Int32
  priv mut input_closed : Bool
  priv mut sending : Bool
  priv mut stopping : Bool
  priv mut output_ended : Bool
  priv mut streams_closed : Bool
  priv mut stop : @worker.WorkerStop?
}

///|
fn ProcessChannel::new(
  worker : Spawned,
  staged : @shared.StagedArtifact,
  limits : @worker.Limits,
  grace_ms~ : Int32,
  confirm_ms~ : Int32,
) -> ProcessChannel {
  {
    worker,
    staged,
    grace_ms,
    confirm_ms,
    reader: @shared.FrameReader::new(limit=limits.response_bytes),
    writer: @shared.FrameWriter::new(limit=limits.request_bytes),
    pending: [],
    leader: Leader::new(worker.pid),
    drain: StderrDrain::new(worker.errors),
    lock: @async.Mutex(),
    active: 0,
    input_closed: false,
    sending: false,
    stopping: false,
    output_ended: false,
    streams_closed: false,
    stop: None,
  }
}

///|
/// The PID of the worker, which is also its process group ID on Unix.
pub fn ProcessChannel::pid(self : ProcessChannel) -> Int32 {
  self.worker.pid
}

///|
/// Runs `f` while stderr is drained, so a worker that writes much to stderr
/// cannot block on it while the host waits for stdout or for its exit.
async fn[X] ProcessChannel::with_stderr(
  self : ProcessChannel,
  f : async () -> X,
) -> X {
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => self.drain.run())
    f()
  })
}

///|
/// Runs `f` while stdout is read and dropped, when no `receive` reads it. A
/// worker that writes after `exit` then cannot block on a full pipe while
/// the host waits for it to exit.
async fn[X] ProcessChannel::with_output_drain(
  self : ProcessChannel,
  f : async () -> X,
) -> X {
  guard self.active == 0 && !self.output_ended else { return f() }
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      let output = self.worker.output
      while (output.read_some(max_len=READ_CHUNK_BYTES) catch { _ => None })
            is Some(_) {
        ()
      }
      self.output_ended = true
    })
    f()
  })
}

///|
/// Closes the host's stream ends once no call uses them, after a stop.
fn ProcessChannel::release_streams(self : ProcessChannel) -> Unit {
  if self.stopping && self.active == 0 && !self.streams_closed {
    self.streams_closed = true
    (self.worker.close_streams)()
  }
}

///|
/// Counts a call that uses the streams; the last call after a stop closes
/// them, because closing a stream that a call waits on would strand it.
async fn[X] ProcessChannel::in_call(
  self : ProcessChannel,
  f : async () -> X,
) -> X {
  guard self.stop is None else { raise @worker.Stopped }
  self.active += 1
  defer {
    self.active -= 1
    self.release_streams()
  }
  f()
}

///|
/// Closes the worker's stdin, unless a `send` waits on it: that `send` then
/// fails when the worker's tree stops, and the last call closes the stream.
fn ProcessChannel::close_input(self : ProcessChannel) -> Unit {
  if !self.input_closed && !self.sending {
    self.input_closed = true
    (self.worker.close_input)()
  }
}

///|
/// Whether an operating system error says that the reader of a pipe has gone:
/// `EPIPE` on Unix, `ERROR_BROKEN_PIPE` or `ERROR_NO_DATA` on Windows.
fn broken_pipe(error : Error) -> Bool {
  match error {
    @os_error.OSError(code, ..) =>
      match @async.platform {
        Windows => code == 109 || code == 232
        _ => code == 32
      }
    _ => false
  }
}

///|
/// Keeps a channel error and reports any other stream error as a transport
/// fault. A write to a worker that has closed its stdin is the end of the
/// worker's stream, as on Node. Cancellation is not an error, so it passes
/// through.
fn transport_error(error : Error) -> @worker.ChannelError {
  match error {
    @worker.WorkerClosed => WorkerClosed
    @worker.FrameInvalid(text) => FrameInvalid(text)
    @worker.FrameLimit(direction~, declared~, limit~) =>
      FrameLimit(direction~, declared~, limit~)
    @worker.TransportFailed(text) => TransportFailed(text)
    @worker.Stopped => Stopped
    error if broken_pipe(error) => WorkerClosed
    error => TransportFailed(error.to_string())
  }
}

///|
pub extend ProcessChannel with @worker.Channel::{
  send,
  receive,
  close,
  abort,
  bounds,
}

///|
pub impl @worker.Channel for ProcessChannel with fn send(self, message) {
  let frame = self.writer.encode(message)
  self.in_call(() => {
    guard !self.input_closed else { raise @worker.WorkerClosed }
    self.sending = true
    defer {
      self.sending = false
    }
    self.with_stderr(() => self.worker.input.write(frame)) catch {
      error => raise transport_error(error)
    }
  })
}

///|
pub impl @worker.Channel for ProcessChannel with fn receive(self) {
  self.in_call(() => {
    while true {
      if self.pending.length() > 0 {
        return self.pending.remove(0)
      }
      guard !self.output_ended else { raise @worker.WorkerClosed }
      let chunk = self.with_stderr(() => self.read_output()) catch {
        // A stop that runs while the read waits ends the read.
        error =>
          raise if self.stopping {
            @worker.Stopped
          } else {
            transport_error(error)
          }
      }
      guard self.stop is None && !self.stopping else { raise @worker.Stopped }
      match chunk {
        None => {
          self.output_ended = true
          self.reader.finish() catch {
            error => self.fault(error)
          }
        }
        Some(bytes) =>
          self.pending.append(
            self.reader.feed(bytes) catch {
              error => self.fault(error)
            },
          )
      }
    }
    panic()
  })
}

///|
/// Reads the next bytes of stdout, or `None` at its end. While the leader
/// runs, the read also watches for its exit. After the exit, the bytes that
/// the leader wrote are in the pipe already, so a read that waits longer
/// than `EXITED_READ_MS` is the end of stdout, even when a grandchild still
/// holds the pipe open.
async fn ProcessChannel::read_output(self : ProcessChannel) -> Bytes? {
  let output = self.worker.output
  if self.leader.status is Some(_) {
    let read = @async.with_timeout_opt(EXITED_READ_MS, () => {
      output.read_some(max_len=READ_CHUNK_BYTES)
    })
    return match read {
      Some(chunk) => chunk
      None => None
    }
  }
  // The watcher cancels the read task, which keeps its bytes if it has
  // read them already. A cancelled read has consumed nothing. A wait that
  // fails leaves the read to end by itself.
  let event = @async.with_task_group(group => {
    let read = group.spawn(() => output.read_some(max_len=READ_CHUNK_BYTES))
    group.spawn_bg(no_wait=true, () => {
      if self.leader.wait() is Some(_) {
        read.cancel()
      }
    })
    Read(read.wait()) catch {
      @async.WaitedTaskAlreadyCancelled => LeaderGone
      error => raise error
    }
  })
  match event {
    Read(chunk) => chunk
    LeaderGone => self.read_output()
  }
}

///|
/// A frame fault ends the session: the host stops the worker's tree at once
/// and raises the fault.
async fn[X] ProcessChannel::fault(
  self : ProcessChannel,
  error : @worker.ChannelError,
) -> X raise @worker.ChannelError {
  ignore(self.finish(Stop(Fault)))
  raise error
}

///|
pub impl @worker.Channel for ProcessChannel with fn close(self) {
  if self.stop is Some(stop) {
    return stop
  }
  self.close_input()
  // An abort during the grace period stops the tree; the leader then exits,
  // the wait ends and `finish` returns the abort's stop, which came first.
  let exited = @async.handle_cancellation(() => {
    self.with_stderr(() => {
      self.with_output_drain(() => self.leader.wait_for(self.grace_ms))
    })
  }) catch {
    _ => Some(None)
  }
  self.finish(
    match exited {
      Some(Some(raw)) => LeaderExited(raw)
      Some(None) => Stop(GraceExpired)
      None => Stop(Cancelled)
    },
  )
}

///|
pub impl @worker.Channel for ProcessChannel with fn abort(self, reason) {
  match self.stop {
    Some(stop) => stop
    None => self.finish(Stop(reason))
  }
}

///|
/// Waits at most `ms` for the leader to exit. The wait reaps it.
async fn ProcessChannel::leader_exited(
  self : ProcessChannel,
  ms : Int32,
) -> Bool noraise {
  self.leader.wait_for(ms) is Some(_)
}

///|
/// Stops the tree, confirms that it is gone, collects the stderr tail and
/// removes the private directory. The first stop wins; every later call
/// returns it.
async fn ProcessChannel::finish(
  self : ProcessChannel,
  ending : Ending,
) -> @worker.WorkerStop noraise {
  @async.protect_from_cancel(() => self.finish_now(ending)) catch {
    _ => abort("finish_now does not raise")
  }
}

///|
async fn ProcessChannel::finish_now(
  self : ProcessChannel,
  ending : Ending,
) -> @worker.WorkerStop noraise {
  self.lock.acquire()
  defer self.lock.release()
  if self.stop is Some(stop) {
    return stop
  }
  self.stopping = true
  self.close_input()
  let tree = self.worker.tree
  let leader_exited = ms => self.leader_exited(ms)
  let (status, stop_method) = match ending {
    LeaderExited(raw) => {
      // The worker stopped by itself. Anything it left behind in its tree
      // is stopped too, before the host reports or removes anything.
      let left = tree.state() is (Live | Unknown(_))
      let confirmed = !left ||
        stop_tree(tree, leader_exited, confirm_ms=self.confirm_ms)
      let status : @worker.StopStatus = match (confirmed, raw < 0) {
        (false, _) => Unconfirmed(GraceExpired)
        (true, true) => Signalled(signal=-raw)
        (true, false) => Exited(code=raw)
      }
      (status, if left { self.worker.stop_method } else { ExitedAfterExit })
    }
    Stop(reason) => {
      let confirmed = stop_tree(tree, leader_exited, confirm_ms=self.confirm_ms)
      (
        if confirmed {
          Terminated(reason)
        } else {
          Unconfirmed(reason)
        },
        self.worker.stop_method,
      )
    }
  }
  let confirmed = status is (Exited(..) | Signalled(..) | Terminated(_))
  if confirmed {
    // Every writer of stderr has stopped, so the drain reaches its end.
    ignore(
      @async.with_timeout_opt(STDERR_FINISH_MS, () => self.drain.run()) catch {
        _ => None
      },
    )
  }
  self.release_streams()
  // A private directory that cannot be removed may still be in use: the stop
  // is then unconfirmed.
  let status : @worker.StopStatus = if confirmed {
    tree.release()
    match (remove_staged(self.staged), status) {
      (true, status) => status
      (false, Terminated(reason)) => Unconfirmed(reason)
      (false, _) => Unconfirmed(GraceExpired)
    }
  } else {
    status
  }
  let stop = @worker.WorkerStop::new(
    status,
    stop_method~,
    stderr=self.drain.buffer.tail(),
  )
  self.stop = Some(stop)
  stop
}
