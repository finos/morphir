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
/// Runs `work` until it finishes or the stop signal is set, whichever comes
/// first. Returns `None` when the stop came first. A result of `work` is never
/// lost: `@async.any` runs a losing task to its end, and a probe can report a
/// stop in that cancelled task without a pause, so the poll's answer cannot
/// replace a result that `work` has already given.
async fn[X] StopSignal::race(self : StopSignal, work : async () -> X) -> X? {
  let mut finished = None
  @async.any([() => finished = Some(work()), () => self.wait()])
  finished
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
  expires_at : Int64
  stop : StopSignal
  require_clean_exit : Bool
}

///|
fn Running::remaining_ms(self : Running) -> Int32 {
  @cmp.maximum(0L, self.expires_at - @async.now()).to_int()
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
    GuestFailed(fault) => ChannelFailed(GuestFailed(fault))
    Refused(code~, message~) => ChannelFailed(Refused(code~, message~))
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
  let raced = @async.with_timeout_opt(self.remaining_ms(), () => {
    self.stop.race(() => Ok(work()) catch { error => Err(channel_event(error)) })
  })
  match raced {
    None => Err(DeadlinePassed)
    Some(None) => Err(StopRequested)
    Some(Some(result)) => result
  }
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
fn Running::guest_state_refusal(
  self : Running,
  limits : @model_access.Limits,
) -> String? {
  let selected = limits.guest_state_bytes()
  if self.channel.guest_state_ceiling() is Some(ceiling) && selected < ceiling {
    Some(
      "maxGuestStateBytes=\{selected} is below this worker's fixed retained-variable ceiling of \{ceiling} bytes",
    )
  } else {
    None
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
  bounded_expiry? : Int64,
) -> (Conversation, Settled) {
  cleanup_on_cancel(
    () => self.drive_steps(conversation, step, bounded_expiry),
    () => ignore(self.channel.abort(Cancelled)),
  )
}

///|
async fn Running::drive_steps(
  self : Running,
  conversation : Conversation,
  step : Step,
  bounded_expiry : Int64?,
) -> (Conversation, Settled) {
  let mut conversation = conversation
  let mut step = step
  while true {
    if step is Activated({ model_access: Some(access), .. }, ..) {
      self.channel.limit_frames(access.limits.frame_bytes().to_int())
      if self.guest_state_refusal(access.limits) is Some(message) {
        let refusal = Ending::Refused(code=AgreementMismatch, message~)
        let worker = self.channel.abort(Fault)
        return (conversation, WorkerStopped(EndedEarly(refusal), worker))
      }
    }
    match step {
      Exchange(sends~, ..) => {
        // A bounded cancel may continue into ordinary shutdown after its ack.
        let running = if conversation.phase is CallingGeneration(_) &&
          bounded_expiry is Some(expiry) {
          { ..self, expires_at: @cmp.minimum(self.expires_at, expiry), }
        } else {
          self
        }
        let event = match running.send_all(sends) {
          Some(event) => event
          None => running.next_event()
        }
        let (next, next_step) = conversation.on(event)
        conversation = next
        step = next_step
      }
      Activated(sends~, _) | Answered(sends~, _) | BoundedAnswered(sends~, _) =>
        match self.send_all(sends) {
          None => return (conversation, Paused(step))
          Some(event) => {
            let (next, next_step) = conversation.on(event)
            conversation = next
            step = next_step
          }
        }
      Finished(sends~, stop~, conclusion) => {
        let plan = stop.after(self.send_all(sends))
        let worker = match plan {
          CloseAfterExit => self.channel.close_within(self.remaining_ms())
          Abort(reason) => self.channel.abort(reason)
        }
        let conclusion = match (stop, plan, worker.status) {
          (CloseAfterExit, Abort(Deadline), _)
          | (
            CloseAfterExit,
            CloseAfterExit,
            Terminated(Deadline)
            | Unconfirmed(Deadline),
          ) => EndedEarly(Deadline)
          (CloseAfterExit, Abort(Cancelled), _) => EndedEarly(Cancelled)
          (CloseAfterExit, Abort(Fault), _) if self.require_clean_exit =>
            EndedEarly(
              incomplete_exit("the worker did not accept morphir.exit"),
            )
          (CloseAfterExit, CloseAfterExit, _) if self.require_clean_exit &&
            (
              worker.status != Exited(code=0) ||
              worker.stop_method != ExitedAfterExit
            ) => EndedEarly(incomplete_exit("the worker did not exit cleanly"))
          _ => conclusion
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
    ExportMissing(name~, signature~) =>
      Refused(
        code=AbiUnsupported,
        message="the module does not export \{name} as \{signature}",
      )
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
    WorkerRuntimeMismatch(host~, worker~) =>
      Refused(
        code=WorkerRuntimeMismatch,
        message="the worker runtime is build \{worker}; the host is build \{host}",
      )
    MemoryAboveCeiling(initial~, ceiling~) =>
      Failed(
        Host(
          code=MemoryLimit,
          message="the module's initial memory of \{initial} pages is above the ceiling of \{ceiling} pages",
        ),
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
  // launcher stops what it started. A launch that has finished gives its
  // channel to the session, which aborts it at a stop or the deadline.
  let launched = @async.with_timeout_opt(deadline.ms(), () => {
    stop.race(() => launcher.launch(spec, limits))
  }) catch {
    error => raise before_start(launch_ending(error), limits, extism)
  }
  match launched {
    None => raise before_start(Deadline, limits, extism)
    Some(None) => raise before_start(Cancelled, limits, extism)
    Some(Some(channel)) =>
      {
        channel,
        expires_at: started + deadline.ms().to_int64(),
        stop,
        require_clean_exit: false,
      }
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
  let limits = self.limits.for_probe()
  let link = self.start(spec, deadline, stop, limits, None)
  let (conversation, step) = Conversation::probe(limits~)
  let (_, settled) = link.drive(conversation, step)
  let ended = (ending : Ending, worker : WorkerStop) => {
    Ended(
      ending,
      report=SessionReport::new(
        limits,
        bounds?=link.channel.bounds(),
        stop=worker,
        ending~,
      ),
    )
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
  self.activate_with_claims(spec, Some(expected), offer, deadline, stop)
}

///|
async fn Host::activate_with_claims(
  self : Host,
  spec : WorkerSpec,
  expected : Claims?,
  offer : Offer,
  deadline : Deadline,
  stop : StopSignal,
) -> Session {
  let limits = self.limits.for_session(offer, spec.runtime)
  let extism = if offer is Legacy && spec.runtime is Wasm(..) {
    Some(ExtismProfile::restricted())
  } else {
    None
  }
  if expected is Some(claims) {
    offer.check(claims) catch {
      Refusal(code~, message~) =>
        raise before_start(Refused(code~, message~), limits, extism)
    }
  }
  let link = self.start(spec, deadline, stop, limits, extism)
  let (conversation, step) = Conversation::initialize(offer, expected, limits)
  let (conversation, settled) = link.drive(conversation, step)
  match settled {
    Paused(_) =>
      {
        link,
        conversation,
        extism,
        report: None,
        generation_expiry: None,
        busy: @async.Mutex(),
      }
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
        report=SessionReport::new(
          limits,
          extism?,
          bounds?=link.channel.bounds(),
          stop=worker,
          ending~,
        ),
      )
    }
  }
}

///|
/// An activated worker that accepts one compile or generate call, then a
/// close. A session must be closed: until then its worker runs. Prefer
/// `Host::with_session`, which always closes the session, or aborts its
/// worker when the task is cancelled.
///
/// A session runs one exchange at a time. A compile or generate call made
/// while another call or a close is in flight raises `SessionUnavailable` and
/// sends nothing. A close made during a call waits for the call to finish,
/// then closes; it never sends `shutdown` during the call.
pub struct Session {
  priv link : Running
  priv mut conversation : Conversation
  priv extism : ExtismProfile?
  priv mut report : SessionReport?
  priv mut generation_expiry : Int64?
  // Held from the readiness check to the end of each exchange.
  priv busy : @async.Mutex
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
    bounds?=self.link.channel.bounds(),
    stop=worker,
    ending?,
  )
  self.report = Some(report)
  report
}

///|
fn Session::bounded_expiry(
  self : Session,
  conversation : Conversation,
) -> Int64? {
  guard conversation.phase is CallingGeneration(pending) else { return None }
  let run = pending.run()
  let now = @async.now()
  let expires_at = if run.round == 0 {
    let expiry = now + run.limits.session_milliseconds().to_int64()
    self.generation_expiry = Some(expiry)
    expiry
  } else {
    self.generation_expiry.unwrap_or(now)
  }
  Some(
    @cmp.minimum(expires_at, now + run.limits.call_milliseconds().to_int64()),
  )
}

///|
async fn[T] Session::exchange(
  self : Session,
  start : (Conversation, Step),
  read_answer : (Step) -> (OutcomeClass[T], Array[Diagnostic])?,
) -> Outcome[T] {
  let (conversation, step) = start
  let bounded_expiry = self.bounded_expiry(conversation)
  let (conversation, settled) = self.link.drive(
    conversation,
    step,
    bounded_expiry?,
  )
  self.conversation = conversation
  // Keep the last bounded horizon for shutdown after a terminal reply.
  // A subsequent bounded start replaces it.
  match settled {
    Paused(step) =>
      match read_answer(step) {
        Some((outcome, diagnostics)) =>
          // The worker still runs; its final stderr tail is in the close report.
          Outcome::new(outcome, diagnostics~, stderr=StderrTail::empty())
        None => {
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
async fn Session::run(
  self : Session,
  start : (Conversation, Step),
) -> Outcome[Json] {
  self.exchange(start, step => {
    match step {
      Answered(answer, ..) => Some((answer.class, answer.diagnostics))
      _ => None
    }
  })
}

///|
async fn Session::run_generation(
  self : Session,
  start : (Conversation, Step),
) -> Outcome[GenerationReply] {
  self.exchange(start, step => {
    match step {
      BoundedAnswered(answer, ..) => Some((answer.class, answer.diagnostics))
      _ => None
    }
  })
}

///|
/// Claims the session for one call. The caller releases `busy` when the
/// call ends.
fn Session::ready(self : Session) -> Unit raise SessionUnavailable {
  guard self.report is None else {
    raise SessionUnavailable("the session has ended")
  }
  guard self.busy.try_acquire() else {
    raise SessionUnavailable("another exchange of the session is in flight")
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
  defer self.busy.release()
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
  defer self.busy.release()
  self.run(self.conversation.generate(request)).map(Generated::new)
}

///|
/// Starts one bounded generation and returns its first typed reply.
pub async fn Session::start_generation(
  self : Session,
  request : @model_access.Start,
) -> Outcome[GenerationReply] {
  self.ready()
  defer self.busy.release()
  if self.link.guest_state_refusal(request.limits) is Some(message) {
    return self.run_generation(
      self.conversation.generation_refusal(AgreementMismatch, message),
    )
  }
  self.run_generation(self.conversation.start_generation(request))
}

///|
/// Delivers the outstanding requested data for the exact active round.
pub async fn Session::advance_generation(
  self : Session,
  request : @model_access.Advance,
) -> Outcome[GenerationReply] {
  self.ready()
  defer self.busy.release()
  self.run_generation(self.conversation.advance_generation(request))
}

///|
/// Requests and verifies acknowledgement of bounded cancellation.
pub async fn Session::cancel_generation(
  self : Session,
  request : @model_access.Cancel,
) -> Outcome[GenerationReply] {
  self.ready()
  defer self.busy.release()
  self.run_generation(self.conversation.cancel_generation(request))
}

///|
/// Cancels active bounded work, then sends `shutdown` and `exit`.
/// A close during a call waits for the call to finish. A closed session
/// returns the same report again.
pub async fn Session::close(self : Session) -> SessionReport {
  self.close_before(None)
}

///|
async fn Session::close_before(
  self : Session,
  caller_expiry : Int64?,
  require_clean_exit~ : Bool = false,
) -> SessionReport {
  self.busy.acquire()
  defer self.busy.release()
  if self.report is Some(report) {
    return report
  }
  let start = self.conversation.close() catch {
    _ => {
      let worker = self.link.channel.abort(Fault)
      let ending = if require_clean_exit {
        Some(incomplete_exit("the worker could not begin shutdown"))
      } else {
        None
      }
      return self.finish(worker, ending)
    }
  }
  let (conversation, step) = start
  let bounded_expiry = self.bounded_expiry(conversation)
  let command_or_caller = @cmp.minimum(
    self.link.expires_at,
    caller_expiry.unwrap_or(self.link.expires_at),
  )
  let expires_at = @cmp.minimum(
    command_or_caller,
    self.generation_expiry.unwrap_or(command_or_caller),
  )
  // The horizon applies to the cancel, shutdown and exit, including when
  // the last generation reply already settled the operation.
  let link = { ..self.link, expires_at, require_clean_exit, }
  let (conversation, settled) = link.drive(conversation, step, bounded_expiry?)
  self.conversation = conversation
  if conversation.generation is None {
    self.generation_expiry = None
  }
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
fn incomplete_exit(message : String) -> Ending {
  Failed(Host(code=IncompleteSession, message~))
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
  self.with_session_claims(spec, Some(expected), offer, deadline, stop, f)
}

///|
async fn[X] Host::with_session_claims(
  self : Host,
  spec : WorkerSpec,
  expected : Claims?,
  offer : Offer,
  deadline : Deadline,
  stop : StopSignal,
  f : async (Session) -> X,
) -> X {
  let session = self.activate_with_claims(spec, expected, offer, deadline, stop)
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
