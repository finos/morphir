///|
priv struct Link {
  to_worker : @aqueue.Queue[Message]
  to_host : @aqueue.Queue[Message]
  exits : @aqueue.Queue[Int32]
  grace_ms : Int32
  stderr : Buffer
  mut exited : Int32?
  mut stop : WorkerStop?
}

///|
/// The host end of an in-memory channel, for tests and fake workers. Its
/// worker runs in the host's own thread, so a stop by the host is a
/// `ThreadTermination`.
pub struct MemoryChannel {
  priv link : Link
}

///|
/// The worker end of an in-memory channel.
pub struct MemoryWorker {
  priv link : Link
}

///|
/// A connected host end and worker end. `close` waits `grace_ms` for the
/// worker to exit.
pub fn MemoryChannel::pair(
  grace_ms~ : Int32 = 2000,
) -> (MemoryChannel, MemoryWorker) {
  let link = {
    to_worker: @aqueue.Queue(kind=Unbounded),
    to_host: @aqueue.Queue(kind=Unbounded),
    exits: @aqueue.Queue(kind=Unbounded),
    grace_ms,
    stderr: Buffer(),
    exited: None,
    stop: None,
  }
  ({ link, }, { link, })
}

///|
/// Records the first stop and ends both directions. A later stop returns the
/// first one; closing `exits` wakes a `close` that waits for the worker.
fn Link::stopped(self : Link, status : StopStatus) -> WorkerStop {
  if self.stop is Some(first) {
    return first
  }
  let stop = WorkerStop::new(
    status,
    stop_method=match status {
      Exited(..) | Signalled(..) => ExitedAfterExit
      Terminated(_) | Unconfirmed(_) => ThreadTermination
    },
    stderr=StderrTail::of(self.stderr.to_bytes()),
  )
  self.stop = Some(stop)
  self.to_worker.close(error=WorkerClosed, clear=true)
  self.to_host.close(error=Stopped, clear=true)
  self.exits.close()
  stop
}

///|
fn Link::ended(self : Link, reason : StopReason) -> WorkerStop {
  self.stopped(
    match self.exited {
      Some(code) => Exited(code~)
      None => Terminated(reason)
    },
  )
}

///|
pub extend MemoryChannel with Channel::{send, receive, close, abort}

///|
pub impl Channel for MemoryChannel with fn send(self, message) {
  let link = self.link
  guard link.stop is None else { raise Stopped }
  guard link.exited is None else { raise WorkerClosed }
  link.to_worker.put(message)
}

///|
pub impl Channel for MemoryChannel with fn receive(self) {
  let link = self.link
  guard link.stop is None else { raise Stopped }
  // The queue raises WorkerClosed or Stopped when it is closed, and passes
  // cancellation through.
  link.to_host.get()
}

///|
pub impl Channel for MemoryChannel with fn close(self) {
  let link = self.link
  if link.stop is Some(stop) {
    return stop
  }
  link.to_worker.close(error=WorkerClosed)
  @async.protect_from_cancel(() => {
    if link.exited is None {
      // An abort closes `exits`, which ends this wait early.
      ignore(
        @async.with_timeout_opt(link.grace_ms, () => link.exits.get()) catch {
          _ => None
        },
      )
    }
    // An abort during the wait has already recorded the first stop.
    link.ended(GraceExpired)
  })
}

///|
pub impl Channel for MemoryChannel with fn abort(self, reason) {
  self.link.ended(reason)
}

///|
/// Reads the host's next message. The end of the host's input raises
/// `WorkerClosed`.
pub async fn MemoryWorker::receive(self : MemoryWorker) -> Message {
  self.link.to_worker.get()
}

///|
pub async fn MemoryWorker::send(self : MemoryWorker, message : Message) -> Unit {
  let link = self.link
  guard link.stop is None && link.exited is None else { raise Stopped }
  link.to_host.put(message)
}

///|
/// Appends bytes to the worker's stderr. The stop keeps the last 64 KiB.
pub fn MemoryWorker::write_stderr(self : MemoryWorker, bytes : Bytes) -> Unit {
  self.link.stderr.write_bytes(bytes)
}

///|
/// Ends the worker. The host reads the messages sent before the exit, then
/// the end of the stream.
pub fn MemoryWorker::exit(self : MemoryWorker, code~ : Int32 = 0) -> Unit {
  let link = self.link
  guard link.exited is None && link.stop is None else { return }
  link.exited = Some(code)
  link.to_host.close(error=WorkerClosed)
  ignore(link.exits.try_put(code) catch { _ => false })
}

///|
/// A launcher that hands out one prepared in-memory channel.
pub struct MemoryLauncher {
  priv mut channel : MemoryChannel?
}

///|
pub fn MemoryLauncher::new(channel : MemoryChannel) -> MemoryLauncher {
  { channel: Some(channel), }
}

///|
pub extend MemoryLauncher with Launcher::{launch}

///|
pub impl Launcher for MemoryLauncher with fn launch(self, _spec) {
  guard self.channel is Some(channel) else {
    raise LaunchFailed("the in-memory channel is already in use")
  }
  self.channel = None
  channel
}
