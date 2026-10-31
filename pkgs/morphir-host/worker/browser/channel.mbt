///|
/// An event of a Web Worker, in the order the worker sent it.
priv enum PortEvent {
  Response(Bytes)
  Report(String)
  Exited(Int32)
  Crashed(String)
}

///|
/// The host end of a WASM guest in a browser Web Worker: the message-port
/// channel. Messages travel as whole MEP messages through the worker's port.
/// The channel enforces the per-call deadline: when a request has no
/// response within it, the channel terminates the Web Worker and raises
/// `CallDeadline`. A stop terminates the Web Worker, which is final at once.
pub struct PortChannel {
  priv port : HostPort
  priv events : @aqueue.Queue[PortEvent]
  priv stderr : @shared.StderrBuffer
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
/// Listens on `target` and gives the guest its module and limits.
fn PortChannel::open(
  target : PortTarget,
  abi : @worker.WasmAbi,
  module_ : Bytes,
  limits : @worker.Limits,
  call_ms~ : Int32,
  grace_ms~ : Int32,
) -> PortChannel {
  let events = @aqueue.Queue(kind=Unbounded)
  let push = (event : PortEvent) => {
    ignore(events.try_put(event) catch { _ => false })
  }
  let port = HostPort::over(target, (kind, bytes, text) => {
    match kind {
      0 => push(Response(bytes))
      1 => push(Report(text))
      2 => push(Exited(@strconv.parse_int(text) catch { _ => 1 }))
      _ => push(Crashed(text))
    }
  })
  port.start(
    abi.to_string(),
    module_,
    limits.request_bytes,
    limits.response_bytes,
    call_ms,
  )
  {
    port,
    events,
    stderr: @shared.StderrBuffer::new(),
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
/// Terminates the Web Worker. Returns the first stop on every call.
fn PortChannel::terminate(
  self : PortChannel,
  reason : @worker.StopReason,
) -> @worker.WorkerStop {
  if self.stop is Some(stop) {
    return stop
  }
  self.port.terminate()
  self.stopped(
    match self.exit_code {
      Some(code) => Exited(code~)
      None => Terminated(reason)
    },
  )
}

///|
fn PortChannel::stopped(
  self : PortChannel,
  status : @worker.StopStatus,
) -> @worker.WorkerStop {
  if self.stop is Some(stop) {
    return stop
  }
  // A Web Worker ends on termination, like a Node worker thread.
  let stop = @worker.WorkerStop::new(
    status,
    stop_method=ThreadTermination,
    stderr=self.stderr.tail(),
  )
  self.stop = Some(stop)
  stop
}

///|
/// The fault or refusal of one report event, and keeps the event's text in
/// the stderr tail.
fn PortChannel::report(
  self : PortChannel,
  text : String,
) -> @worker.ChannelError? {
  let line = @utf8.encode(text + "\n")
  self.stderr.write(line)
  @guest.WorkerEvent::ending_in(line)
}

///|
pub extend PortChannel with @worker.Channel::{
  send,
  receive,
  close,
  abort,
  bounds,
}

///|
pub impl @worker.Channel for PortChannel with fn send(self, message) {
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
  self.port.post(bytes)
}

///|
pub impl @worker.Channel for PortChannel with fn receive(self) {
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
      // Web Worker ends.
      self.ended_by = Some(@worker.GuestFailed(CallDeadline))
      ignore(self.terminate(Deadline))
      raise @worker.GuestFailed(CallDeadline)
    }
    match event {
      Response(bytes) => {
        guard bytes.length() <= self.response_limit else {
          raise @worker.FrameLimit(
            direction=@worker.FrameDirection::Response,
            declared=bytes.length().to_int64(),
            limit=self.response_limit,
          )
        }
        let message = @worker.Message::parse(bytes)
        // Only an answer ends the call. A notification leaves the call and
        // its deadline running.
        if message.json() is Object(fields) && fields.contains("id") {
          self.call_started = None
        }
        return message
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
/// Waits `grace_ms` for the guest to exit after `exit`, then terminates the
/// Web Worker.
pub impl @worker.Channel for PortChannel with fn close(self) {
  if self.stop is Some(stop) {
    return stop
  }
  if self.exit_code is None {
    let exited = @async.protect_from_cancel(() => {
      @async.with_timeout_opt(self.grace_ms, () => {
        while true {
          match self.events.get() {
            Exited(code) => return code
            Report(text) => ignore(self.report(text))
            Response(_) | Crashed(_) => ()
          }
        }
        -1
      })
    }) catch {
      _ => None
    }
    if exited is Some(code) {
      self.exit_code = Some(code)
    }
  }
  match self.exit_code {
    Some(code) => {
      // The guest closed its scope after it reported the exit.
      self.port.terminate()
      self.stopped(Exited(code~))
    }
    None => self.terminate(GraceExpired)
  }
}

///|
pub impl @worker.Channel for PortChannel with fn abort(self, reason) {
  self.terminate(reason)
}

///|
/// The js engine caps memory by rewriting the module's maximum; it meters no
/// instructions. The channel enforces the call deadline by terminating the
/// Web Worker.
pub impl @worker.Channel for PortChannel with fn bounds(_) {
  Some(
    @worker.EnforcedBounds::new(
      memory_ceiling=Enforced,
      instruction_budget=NotEnforced(NoInstructionMetering),
      call_deadline=Enforced,
    ),
  )
}
