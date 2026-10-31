///|
/// An event of a worker thread, in the order the thread sent it.
priv enum ThreadEvent {
  Response(Bytes)
  Report(String)
  Exited(Int32)
  Crashed(String)
}

///|
/// The host end of a WASM guest in a Node worker thread. Messages travel as
/// whole MEP messages through the thread's port. The channel enforces the
/// per-call deadline: when a request has no response within it, the channel
/// terminates the thread and raises `CallDeadline`. A stop terminates the
/// thread and waits until it has terminated.
pub struct ThreadChannel {
  priv worker : JsWorker
  priv events : @aqueue.Queue[ThreadEvent]
  priv stderr : @shared.StderrBuffer
  /// The guest's private workspace directory.
  priv workspace : String
  priv call_ms : Int32
  priv request_limit : Int32
  priv response_limit : Int32
  priv grace_ms : Int32
  /// When the request that waits for its response was sent.
  priv mut call_started : Int64?
  priv mut exit_code : Int32?
  priv mut ended_by : @worker.ChannelError?
  priv mut stop : @worker.WorkerStop?
}

///|
fn ThreadChannel::start(
  entry : String,
  abi : @worker.WasmAbi,
  module_ : Bytes,
  limits : @worker.Limits,
  call_ms~ : Int32,
  grace_ms~ : Int32,
) -> ThreadChannel raise @worker.LaunchError {
  let events = @aqueue.Queue(kind=Unbounded)
  let stderr = @shared.StderrBuffer::new()
  // The guest's workspace: an empty directory that only this user can use,
  // removed when the thread has stopped, as on native.
  let workspace = private_directory()
  let push = (event : ThreadEvent) => {
    ignore(events.try_put(event) catch { _ => false })
  }
  let worker = JsWorker::start(
    entry,
    abi.to_string(),
    module_,
    limits.request_bytes,
    limits.response_bytes,
    call_ms,
    workspace,
    (kind, bytes, text) => {
      match kind {
        0 => push(Response(bytes))
        1 => push(Report(text))
        2 => push(Exited(@strconv.parse_int(text) catch { _ => 1 }))
        _ => push(Crashed(text))
      }
    },
    bytes => stderr.write(bytes),
  )
  if worker.start_error() is error && error != "" {
    remove_directory(workspace)
    raise LaunchFailed("the worker thread did not start: \{error}")
  }
  {
    worker,
    events,
    stderr,
    workspace,
    call_ms,
    request_limit: limits.request_bytes,
    response_limit: limits.response_bytes,
    grace_ms,
    call_started: None,
    exit_code: None,
    ended_by: None,
    stop: None,
  }
}

///|
/// Terminates the thread and waits until it has terminated. Returns the
/// first stop on every call.
async fn ThreadChannel::terminate(
  self : ThreadChannel,
  reason : @worker.StopReason,
) -> @worker.WorkerStop {
  if self.stop is Some(stop) {
    return stop
  }
  @async.protect_from_cancel(() => {
    @js_async.run_promise(signal => self.worker.terminate(signal))
  }) catch {
    _ => ()
  }
  self.stopped(
    match self.exit_code {
      Some(code) => Exited(code~)
      None => Terminated(reason)
    },
  )
}

///|
fn ThreadChannel::stopped(
  self : ThreadChannel,
  status : @worker.StopStatus,
) -> @worker.WorkerStop {
  if self.stop is Some(stop) {
    return stop
  }
  let stop = @worker.WorkerStop::new(
    status,
    stop_method=ThreadTermination,
    stderr=self.stderr.tail(),
  )
  self.stop = Some(stop)
  // The thread has exited or terminated, so nothing uses the workspace.
  remove_directory(self.workspace)
  stop
}

///|
/// The fault or refusal of one report event, and keeps the event's text in
/// the stderr tail.
fn ThreadChannel::report(
  self : ThreadChannel,
  text : String,
) -> @worker.ChannelError? {
  let line = @utf8.encode(text + "\n")
  self.stderr.write(line)
  @guest.WorkerEvent::ending_in(line)
}

///|
pub extend ThreadChannel with @worker.Channel::{
  send,
  receive,
  close,
  abort,
  bounds,
}

///|
pub impl @worker.Channel for ThreadChannel with fn send(self, message) {
  guard self.stop is None else { raise @worker.Stopped }
  if self.ended_by is Some(error) {
    raise error
  }
  guard self.exit_code is None else { raise @worker.WorkerClosed }
  let bytes = message.to_bytes()
  guard bytes.length() <= self.request_limit else {
    raise @worker.FrameLimit(
      direction=@worker.FrameDirection::Request,
      declared=bytes.length().to_int64(),
      limit=self.request_limit,
    )
  }
  if message.json() is Object(fields) && fields.contains("id") {
    self.call_started = Some(@async.now())
  }
  self.worker.post(bytes)
}

///|
pub impl @worker.Channel for ThreadChannel with fn receive(self) {
  while true {
    guard self.stop is None else { raise @worker.Stopped }
    if self.ended_by is Some(error) {
      raise error
    }
    let event = match self.call_started {
      Some(started) => {
        let remaining = self.call_ms.to_int64() - (@async.now() - started)
        if remaining <= 0L {
          None
        } else {
          @async.with_timeout_opt(remaining.to_int(), () => self.events.get())
        }
      }
      None => Some(self.events.get())
    }
    guard event is Some(event) else {
      // The call ran past its deadline: the engine cannot stop it, so the
      // thread ends.
      self.ended_by = Some(@worker.GuestFailed(CallDeadline))
      ignore(self.terminate(Deadline))
      raise @worker.GuestFailed(CallDeadline)
    }
    match event {
      Response(bytes) => {
        self.call_started = None
        guard bytes.length() <= self.response_limit else {
          raise @worker.FrameLimit(
            direction=@worker.FrameDirection::Response,
            declared=bytes.length().to_int64(),
            limit=self.response_limit,
          )
        }
        return @worker.Message::parse(bytes)
      }
      Report(text) =>
        if self.report(text) is Some(error) {
          self.ended_by = Some(error)
          raise error
        }
      Exited(code) => {
        self.exit_code = Some(code)
        raise @worker.WorkerClosed
      }
      Crashed(text) => {
        let error = @worker.ChannelError::GuestFailed(Failure(text))
        self.ended_by = Some(error)
        raise error
      }
    }
  }
  raise @worker.WorkerClosed
}

///|
/// Waits `grace_ms` for the thread to exit after `exit`, then terminates it.
pub impl @worker.Channel for ThreadChannel with fn close(self) {
  if self.stop is Some(stop) {
    return stop
  }
  let exited = @async.protect_from_cancel(() => {
    @async.with_timeout_opt(self.grace_ms, () => {
      @js_async.run_promise(signal => self.worker.exited(signal))
    })
  }) catch {
    _ => None
  }
  if exited is Some(_) {
    let code = self.worker.exit_code()
    self.exit_code = Some(code)
    return self.stopped(Exited(code~))
  }
  self.terminate(GraceExpired)
}

///|
pub impl @worker.Channel for ThreadChannel with fn abort(self, reason) {
  self.terminate(reason)
}

///|
/// The js engine caps memory by rewriting the module's maximum; it meters no
/// instructions. The channel enforces the call deadline by terminating the
/// thread.
pub impl @worker.Channel for ThreadChannel with fn bounds(_) {
  Some(
    @worker.EnforcedBounds::new(
      memory_ceiling=Enforced,
      instruction_budget=NotEnforced(NoInstructionMetering),
      call_deadline=Enforced,
    ),
  )
}
