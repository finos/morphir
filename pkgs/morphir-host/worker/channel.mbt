///|
/// Whole MEP messages between the host and one worker. `close` follows `exit`:
/// it waits for the grace period, then stops the worker's tree and confirms.
/// `abort` stops the tree at once. Both complete their cleanup under
/// `@async.protect_from_cancel` and return the first stop on every call.
///
/// `send` and `receive` raise `ChannelError` for transport faults. They must
/// let the `moonbitlang/async` cancellation pass through unchanged: an
/// implementation never turns it into `WorkerClosed` or `Stopped`.
pub(open) trait Channel {
  async fn send(Self, Message) -> Unit
  async fn receive(Self) -> Message
  async fn close(Self) -> WorkerStop
  async fn abort(Self, StopReason) -> WorkerStop
}

///|
/// Starts a worker from a specification and returns its channel. It raises
/// `LaunchError` when it cannot start the worker, and lets cancellation pass
/// through unchanged.
pub(open) trait Launcher {
  async fn launch(Self, WorkerSpec) -> &Channel
}
