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
/// Starts a worker from a specification and returns its channel. The channel
/// applies the frame limits of `limits`, the limits of the session: a request
/// over `request_bytes` or a response over `response_bytes` raises
/// `FrameLimit` with its direction. It raises `LaunchError` when it cannot
/// start the worker, and lets cancellation pass through unchanged. The host
/// cancels a launch when the session deadline passes or its stop signal is
/// set; a cancelled launch stops whatever it already started.
pub(open) trait Launcher {
  async fn launch(Self, WorkerSpec, Limits) -> &Channel
}
