///|
/// How often the driver reads the stop signal while it waits. A Moon-Lander
/// `StopToken` can only be read; it has no asynchronous wait.
let stop_poll_ms : Int32 = 10

///|
/// Waits until the stop signal is set.
async fn StopSignal::wait(self : StopSignal) -> Unit {
  while !self.requested() {
    @async.sleep(stop_poll_ms)
  }
}

///|
/// Runs `f`. When the task that runs it is cancelled, it runs `cleanup`
/// where cancellation cannot interrupt it, then lets the cancellation
/// continue.
async fn[X] cleanup_on_cancel(
  f : async () -> X,
  cleanup : async () -> Unit,
) -> X {
  guard @async.handle_cancellation(f) is Some(value) else {
    @async.protect_from_cancel(cleanup) catch {
      _ => ()
    }
    // The task is still cancelled, so this pause raises the cancellation
    // again.
    @async.pause()
    abort("a cancelled task resumed")
  }
  value
}

///|
/// One running worker: its channel, the session clock and the stop signal.
priv struct Running {
  channel : &Channel
  started : Int64
  deadline : Deadline
  stop : StopSignal
}

///|
fn Running::remaining_ms(self : Running) -> Int32 {
  (self.deadline.ms().to_int64() - (@async.now() - self.started)).to_int()
}

///|
fn Running::interrupted(self : Running) -> Event? {
  if self.stop.requested() {
    Some(StopRequested)
  } else if self.remaining_ms() <= 0 {
    Some(DeadlinePassed)
  } else {
    None
  }
}

///|
/// The event for an error that a channel raised. A channel raises
/// `ChannelError`; any other error is reported as an invalid frame.
fn channel_event(error : Error) -> Event {
  match error {
    WorkerClosed => ChannelFailed(WorkerClosed)
    Stopped => ChannelFailed(Stopped)
    FrameInvalid(text) => ChannelFailed(FrameInvalid(text))
    TransportFailed(text) => ChannelFailed(TransportFailed(text))
    FrameLimit(direction~, declared~, limit~) =>
      ChannelFailed(FrameLimit(direction~, declared~, limit~))
    _ => ChannelFailed(FrameInvalid("the channel raised an unknown error"))
  }
}

///|
/// Runs one channel operation until it finishes, the session deadline passes
/// or the stop signal is set, whichever comes first. A stop or the deadline
/// interrupts a pending send or receive. A channel error becomes its event.
async fn[X] Running::race(
  self : Running,
  work : async () -> X,
) -> Result[X, Event] {
  if self.interrupted() is Some(event) {
    return Err(event)
  }
  let stop = self.stop
  let raced = @async.with_timeout_opt(self.remaining_ms(), () => {
    @async.any([
      () => Ok(work()) catch { error => Err(channel_event(error)) },
      () => {
        stop.wait()
        Err(StopRequested)
      },
    ])
  })
  raced.unwrap_or(Err(DeadlinePassed))
}

///|
/// Sends each message in turn. It returns the event that stopped a send.
async fn Running::send_all(self : Running, sends : Array[Message]) -> Event? {
  for message in sends {
    if self.race(() => self.channel.send(message)) is Err(event) {
      return Some(event)
    }
  }
  None
}

///|
/// Waits for the next message, the deadline or the stop signal, whichever
/// comes first.
async fn Running::next_event(self : Running) -> Event {
  match self.race(() => self.channel.receive()) {
    Ok(message) => Received(message)
    Err(event) => event
  }
}

///|
priv enum Settled {
  Paused(Step)
  WorkerStopped(Conclusion, WorkerStop)
}

///|
fn StopPlan::after(self : StopPlan, event : Event?) -> StopPlan {
  match event {
    None => self
    Some(DeadlinePassed) => Abort(Deadline)
    Some(StopRequested) => Abort(Cancelled)
    Some(_) => Abort(Fault)
  }
}

///|
/// Executes steps over the channel until the session pauses or its worker
/// stops. When the task that drives the worker is cancelled, the worker is
/// aborted at once and the cancellation continues.
async fn Running::drive(
  self : Running,
  conversation : Conversation,
  step : Step,
) -> (Conversation, Settled) {
  cleanup_on_cancel(() => self.drive_steps(conversation, step), () => {
    ignore(self.channel.abort(Cancelled))
  })
}

///|
async fn Running::drive_steps(
  self : Running,
  conversation : Conversation,
  step : Step,
) -> (Conversation, Settled) {
  let mut conversation = conversation
  let mut step = step
  while true {
    match step {
      Exchange(sends~, ..) => {
        let event = match self.send_all(sends) {
          Some(event) => event
          None => self.next_event()
        }
        let (next, next_step) = conversation.on(event)
        conversation = next
        step = next_step
      }
      Activated(sends~, _) | Answered(sends~, _) =>
        match self.send_all(sends) {
          None => return (conversation, Paused(step))
          Some(event) => {
            let (next, next_step) = conversation.on(event)
            conversation = next
            step = next_step
          }
        }
      Finished(sends~, stop~, conclusion) => {
        let worker = match stop.after(self.send_all(sends)) {
          CloseAfterExit => self.channel.close()
          Abort(reason) => self.channel.abort(reason)
        }
        return (conversation, WorkerStopped(conclusion, worker))
      }
    }
  }
  panic()
}

///|
/// The worker host: it starts workers through its launcher and runs MEP
/// sessions with them.
pub struct Host {
  priv launcher : &Launcher
  priv platform : HostPlatform
  priv limits : Limits
}

///|
pub fn Host::new(
  launcher : &Launcher,
  platform : HostPlatform,
  limits~ : Limits = Limits::host(),
) -> Host {
  { launcher, platform, limits, }
}

///|
/// The runtime kinds this host can start.
pub fn Host::runtimes(self : Host) -> Array[RuntimeKind] {
  self.platform.runtimes()
}

///|
/// Whether this host can start the runtime.
pub fn Host::supports(self : Host, runtime : WorkerRuntime) -> Bool {
  self.platform.supports(runtime)
}

///|
fn launch_ending(error : Error) -> Ending {
  match error {
    PlatformMismatch(platform) =>
      Refused(
        code=PlatformMismatch,
        message="the artifact is built for \{platform}",
      )
    RuntimeUnavailable(supported~) =>
      Refused(
        code=RuntimeUnavailable,
        message="the launcher starts \{supported.map(kind => kind.to_string()).join(" and ")} workers",
      )
    DigestMismatch(expected~, actual~) =>
      Refused(
        code=DigestMismatch,
        message="the artifact has SHA-256 \{actual}; the specification names \{expected}",
      )
    AbiUnsupported(name) =>
      Refused(code=AbiUnsupported, message="the module imports \{name}")
    AbiMismatch(declared~, classified~) =>
      Refused(
        code=AbiMismatch,
        message="the specification declares \{declared}; the module is \{classified}",
      )
    WasmFeatureUnsupported(feature~) =>
      Refused(
        code=WasmFeatureUnsupported,
        message="the module needs \{feature.unwrap_or("a WASM feature")} that the engine does not have",
      )
    ArtifactUnreadable(_) =>
      Failed(
        Host(code=IncompleteSession, message="the artifact could not be read"),
      )
    LaunchFailed(text) =>
      Failed(
        Host(
          code=IncompleteSession,
          message="the worker did not start: \{text}",
        ),
      )
    _ =>
      Failed(Host(code=IncompleteSession, message="the worker did not start"))
  }
}

///|
fn before_start(
  ending : Ending,
  limits : Limits,
  extism : ExtismProfile?,
) -> HostError {
  Ended(ending, report=SessionReport::new(limits, extism?, ending~))
}

///|
async fn Host::start(
  self : Host,
  spec : WorkerSpec,
  deadline : Deadline,
  stop : StopSignal,
  limits : Limits,
  extism : ExtismProfile?,
) -> Running {
  self.platform.admit(spec.runtime) catch {
    Refusal(code~, message~) =>
      raise before_start(Refused(code~, message~), limits, extism)
  }
  if stop.requested() {
    raise before_start(Cancelled, limits, extism)
  }
  let started = @async.now()
  let launcher = self.launcher
  // The deadline or a stop cancels a launch that has not finished; the
  // launcher stops what it started.
  let launched = @async.with_timeout_opt(deadline.ms(), () => {
    @async.any([
      () => Some(launcher.launch(spec, limits)),
      () => {
        stop.wait()
        None
      },
    ])
  }) catch {
    error => raise before_start(launch_ending(error), limits, extism)
  }
  match launched {
    None => raise before_start(Deadline, limits, extism)
    Some(None) => raise before_start(Cancelled, limits, extism)
    Some(Some(channel)) => { channel, started, deadline, stop, }
  }
}

///|
/// Starts a worker, asks it to describe itself, sends `exit` and stops it.
/// The description grants no execution authority, and the host does not
/// keep it.
pub async fn Host::probe(
  self : Host,
  spec : WorkerSpec,
  deadline~ : Deadline = Deadline::default(),
  stop~ : StopSignal = StopSignal::never(),
) -> Description {
  let link = self.start(spec, deadline, stop, self.limits, None)
  let (conversation, step) = Conversation::probe(limits=self.limits)
  let (_, settled) = link.drive(conversation, step)
  let ended = (ending : Ending, worker : WorkerStop) => {
    Ended(ending, report=SessionReport::new(self.limits, stop=worker, ending~))
  }
  match settled {
    WorkerStopped(Described(description), _) => description
    WorkerStopped(EndedEarly(ending), worker) => raise ended(ending, worker)
    WorkerStopped(_, worker) =>
      raise ended(
        Failed(Host(code=DescribeFailed, message="the probe did not finish")),
        worker,
      )
    // A probe conversation never pauses.
    Paused(_) =>
      raise ended(
        Failed(
          Host(code=DescribeFailed, message="internal error: the probe paused"),
        ),
        link.channel.abort(Fault),
      )
  }
}

///|
/// Starts a worker, initializes it with `offer` and compares its identity and
/// capabilities with the `expected` claims before any operation. The session
/// deadline covers activation, the call and the close.
pub async fn Host::activate(
  self : Host,
  spec : WorkerSpec,
  expected~ : Claims,
  offer~ : Offer,
  deadline~ : Deadline = Deadline::default(),
  stop~ : StopSignal = StopSignal::never(),
) -> Session {
  let limits = self.limits.for_session(offer, spec.runtime)
  let extism = if offer is Legacy && spec.runtime is Wasm(..) {
    Some(ExtismProfile::restricted())
  } else {
    None
  }
  offer.check(expected) catch {
    Refusal(code~, message~) =>
      raise before_start(Refused(code~, message~), limits, extism)
  }
  let link = self.start(spec, deadline, stop, limits, extism)
  let (conversation, step) = Conversation::activate(offer, expected~, limits~)
  let (conversation, settled) = link.drive(conversation, step)
  match settled {
    Paused(_) => { link, conversation, extism, report: None, }
    WorkerStopped(conclusion, worker) => {
      let ending = match conclusion {
        EndedEarly(ending) => ending
        _ =>
          Failed(
            Host(code=IncompleteSession, message="activation did not finish"),
          )
      }
      raise Ended(
        ending,
        report=SessionReport::new(limits, extism?, stop=worker, ending~),
      )
    }
  }
}

///|
/// An activated worker that accepts one compile or generate call, then a
/// close. A session must be closed: until then its worker runs. Prefer
/// `Host::with_session`, which always closes the session, or aborts its
/// worker when the task is cancelled.
pub struct Session {
  priv link : Running
  priv mut conversation : Conversation
  priv extism : ExtismProfile?
  priv mut report : SessionReport?
}

///|
/// What activation agreed with the worker.
pub fn Session::negotiated(self : Session) -> Negotiated? {
  self.conversation.negotiated()
}

///|
fn Session::finish(
  self : Session,
  worker : WorkerStop,
  ending : Ending?,
) -> SessionReport {
  let report = SessionReport::new(
    self.conversation.limits(),
    negotiated?=self.conversation.negotiated(),
    extism?=self.extism,
    stop=worker,
    ending?,
  )
  self.report = Some(report)
  report
}

///|
async fn Session::run(
  self : Session,
  start : (Conversation, Step),
) -> Outcome[Json] {
  let (conversation, step) = start
  let (conversation, settled) = self.link.drive(conversation, step)
  self.conversation = conversation
  match settled {
    Paused(Answered(answer, ..)) =>
      // The worker still runs; its final stderr tail is in the close report.
      Outcome::new(
        answer.class,
        diagnostics=answer.diagnostics,
        stderr=StderrTail::empty(),
      )
    // A call conversation pauses only with its answer.
    Paused(_) => {
      let worker = self.link.channel.abort(Fault)
      let ending = Ending::Failed(
        Host(
          code=IncompleteSession,
          message="internal error: the call paused without an answer",
        ),
      )
      ignore(self.finish(worker, Some(ending)))
      Outcome::new(ending.class(), diagnostics=[], stderr=worker.stderr)
    }
    WorkerStopped(conclusion, worker) => {
      let ending = match conclusion {
        EndedEarly(ending) => ending
        _ =>
          Failed(
            Host(
              code=IncompleteSession,
              message="the worker stopped during the call",
            ),
          )
      }
      ignore(self.finish(worker, Some(ending)))
      Outcome::new(ending.class(), diagnostics=[], stderr=worker.stderr)
    }
  }
}

///|
fn Session::ready(self : Session) -> Unit raise SessionUnavailable {
  guard self.report is None else {
    raise SessionUnavailable("the session has ended")
  }
}

///|
/// Sends the session's compile call with the method of the negotiated
/// protocol line. A call that the session cannot make is refused without
/// sending anything.
pub async fn Session::compile(
  self : Session,
  request : CompileRequest,
) -> Outcome[Compiled] {
  self.ready()
  self.run(self.conversation.compile(request)).map(Compiled::new)
}

///|
/// Sends the session's generate call with the method of the negotiated
/// protocol line.
pub async fn Session::generate(
  self : Session,
  request : GenerateRequest,
) -> Outcome[Generated] {
  self.ready()
  self.run(self.conversation.generate(request)).map(Generated::new)
}

///|
/// Sends `shutdown` and `exit`, stops the worker and reports how it stopped.
/// A closed session returns the same report again.
pub async fn Session::close(self : Session) -> SessionReport {
  if self.report is Some(report) {
    return report
  }
  let start = self.conversation.close() catch {
    _ => {
      let worker = self.link.channel.abort(Fault)
      return self.finish(worker, None)
    }
  }
  let (conversation, step) = start
  let (conversation, settled) = self.link.drive(conversation, step)
  self.conversation = conversation
  match settled {
    WorkerStopped(Closed, worker) => self.finish(worker, None)
    WorkerStopped(EndedEarly(ending), worker) =>
      self.finish(worker, Some(ending))
    // A close conversation neither describes nor pauses.
    WorkerStopped(Described(_), worker) =>
      self.finish(
        worker,
        Some(internal_error("the close described the worker")),
      )
    Paused(_) =>
      self.finish(
        self.link.channel.abort(Fault),
        Some(internal_error("the close paused")),
      )
  }
}

///|
fn internal_error(text : String) -> Ending {
  Failed(Host(code=IncompleteSession, message="internal error: \{text}"))
}

///|
/// Aborts the worker of a session that has not ended, for a cancelled task.
async fn Session::cancel(self : Session) -> Unit {
  if self.report is None {
    ignore(self.finish(self.link.channel.abort(Cancelled), Some(Cancelled)))
  }
}

///|
/// Activates a worker, runs `f` with its session and always ends the
/// session. It closes the session when `f` returns or raises, and aborts the
/// worker at once when the task is cancelled. `f` may close the session
/// itself to read its report; a second close returns the same report.
/// Activation raises `HostError::Ended` as `Host::activate` does.
pub async fn[X] Host::with_session(
  self : Host,
  spec : WorkerSpec,
  expected~ : Claims,
  offer~ : Offer,
  deadline~ : Deadline = Deadline::default(),
  stop~ : StopSignal = StopSignal::never(),
  f : async (Session) -> X,
) -> X {
  let session = self.activate(spec, expected~, offer~, deadline~, stop~)
  let result = cleanup_on_cancel(
    () => Ok(f(session)) catch { error => Err(error) },
    () => session.cancel(),
  )
  ignore(session.close())
  match result {
    Ok(value) => value
    Err(error) => raise error
  }
}
