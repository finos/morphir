///|
/// Why a session ended before it closed normally.
pub(all) enum Ending {
  Refused(code~ : RefusalCode, message~ : String)
  Failed(Fault)
  Deadline
  Cancelled
} derive(Eq, Debug)

///|
pub extend Ending with Eq::{equal, not_equal}

///|
pub extend Ending with @debug.Debug::{to_repr}

///|
/// The outcome class of an early end.
pub fn[T] Ending::class(self : Ending) -> OutcomeClass[T] {
  match self {
    Refused(code~, message~) => Refused(code~, message~)
    Failed(fault) => Failed(fault)
    Deadline => Deadline
    Cancelled => Cancelled
  }
}

///|
/// Something that happened to a session while it waited for a reply.
pub(all) enum Event {
  Received(Message)
  ChannelFailed(ChannelError)
  DeadlinePassed
  StopRequested
} derive(Eq, Debug)

///|
pub extend Event with Eq::{equal, not_equal}

///|
pub extend Event with @debug.Debug::{to_repr}

///|
/// How the driver ends the worker: `CloseAfterExit` waits for the worker to
/// leave after `exit`; `Abort` stops it at once.
pub(all) enum StopPlan {
  CloseAfterExit
  Abort(StopReason)
} derive(Eq, Debug)

///|
pub extend StopPlan with Eq::{equal, not_equal}

///|
pub extend StopPlan with @debug.Debug::{to_repr}

///|
/// What a describe probe returns: the claims of the extension. A description
/// grants no execution authority, and the host does not keep it.
pub struct Description {
  claims : Claims
} derive(Eq, Debug)

///|
pub extend Description with Eq::{equal, not_equal}

///|
pub extend Description with @debug.Debug::{to_repr}

///|
/// The answer to one call, before it is typed as compiled or generated.
pub struct Answer {
  class : OutcomeClass[Json]
  diagnostics : Array[Diagnostic]
} derive(Eq, Debug)

///|
pub extend Answer with Eq::{equal, not_equal}

///|
pub extend Answer with @debug.Debug::{to_repr}

///|
/// How a session ended its worker.
pub(all) enum Conclusion {
  Described(Description)
  Closed
  EndedEarly(Ending)
} derive(Eq, Debug)

///|
pub extend Conclusion with Eq::{equal, not_equal}

///|
pub extend Conclusion with @debug.Debug::{to_repr}

///|
/// The next thing the driver does. It sends `sends` in order, then:
/// `Exchange` waits for the reply to `awaiting`; `Activated` and `Answered`
/// return to the caller with the worker still running; `Finished` ends the
/// worker as `stop` says.
pub(all) enum Step {
  Exchange(sends~ : Array[Message], awaiting~ : Int32)
  Activated(sends~ : Array[Message], Negotiated)
  Answered(sends~ : Array[Message], Answer)
  Finished(sends~ : Array[Message], stop~ : StopPlan, Conclusion)
} derive(Eq, Debug)

///|
pub extend Step with Eq::{equal, not_equal}

///|
pub extend Step with @debug.Debug::{to_repr}

///|
/// A caller used a session out of order: a second call, or a call after the
/// session ended.
pub(all) suberror SessionUnavailable {
  SessionUnavailable(String)
} derive(Eq, Debug)

///|
pub extend SessionUnavailable with Eq::{equal, not_equal}

///|
pub extend SessionUnavailable with @debug.Debug::{to_repr}

///|
priv enum Phase {
  Describing
  Initializing(Offer, Claims)
  Refusing(Ending)
  Ready
  Calling(CallKind, Operation)
  Called
  ShuttingDown
  Over
} derive(Eq, Debug)

///|
/// The pure state of one MEP session (SES-1). It takes events and returns
/// the next step; it never touches a channel. One type serves both protocol
/// lines (SES-2). A probe is `describe` then `exit`. An operation session is
/// `initialize`, `initialized`, the operation, `shutdown`, then `exit`, with
/// one request at a time.
pub struct Conversation {
  priv phase : Phase
  priv pending : Int32
  priv next_id : Int32
  priv answered : Array[Int32]
  priv limits : Limits
  priv expected : Claims?
  priv negotiated : Negotiated?
} derive(Eq, Debug)

///|
pub extend Conversation with Eq::{equal, not_equal}

///|
pub extend Conversation with @debug.Debug::{to_repr}

///|
/// Starts a probe: `describe`, then `exit`.
pub fn Conversation::probe(
  limits~ : Limits = Limits::host(),
) -> (Conversation, Step) {
  (
    {
      phase: Describing,
      pending: 1,
      next_id: 2,
      answered: [],
      limits,
      expected: None,
      negotiated: None,
    },
    Exchange(sends=[describe_message(1)], awaiting=1),
  )
}

///|
/// Refuses an offer that the recorded claims cannot serve, before any worker
/// starts.
pub fn Offer::check(self : Offer, claims : Claims) -> Unit raise Refusal {
  if self is Model(tuples) &&
    (tuples.is_empty() || self.operations().length() != 1) {
    raise Refusal(
      code=TupleUnavailable,
      message="a model offer has one or more tuples of one operation",
    )
  }
  let line = self.line()
  guard claims.protocol_lines.contains(line) else {
    raise Refusal(
      code=ProtocolUnavailable,
      message="\{claims.extension_id} does not claim MEP \{line}",
    )
  }
  guard self.operations().iter().any(operation => claims.offers(operation)) else {
    raise Refusal(
      code=CapabilityUnavailable,
      message="\{claims.extension_id} claims no operation of MEP \{line}",
    )
  }
  guard self is Model(tuples) else { return }
  // An offer made from a stale record names no tuple that the record still
  // has.
  guard tuples.iter().any(tuple => claims.model_tuples.contains(tuple)) else {
    raise Refusal(
      code=ClaimsMismatch,
      message="the recorded claims of \{claims.extension_id} have none of the offered tuples",
    )
  }
}

///|
/// Starts an operation session that initializes the worker with `offer` and
/// compares its answer with the `expected` claims.
pub fn Conversation::activate(
  offer : Offer,
  expected~ : Claims,
  limits~ : Limits = Limits::host(),
) -> (Conversation, Step) {
  (
    {
      phase: Initializing(offer, expected),
      pending: 1,
      next_id: 2,
      answered: [],
      limits,
      expected: Some(expected),
      negotiated: None,
    },
    Exchange(sends=[initialize_message(1, offer, limits)], awaiting=1),
  )
}

///|
/// What activation agreed, once the session is ready.
pub fn Conversation::negotiated(self : Conversation) -> Negotiated? {
  self.negotiated
}

///|
/// The limits that apply now: the host limits, then the effective limits
/// after activation.
pub fn Conversation::limits(self : Conversation) -> Limits {
  self.limits
}

///|
fn Conversation::over(
  self : Conversation,
  stop : StopPlan,
  conclusion : Conclusion,
  sends~ : Array[Message] = [],
) -> (Conversation, Step) {
  ({ ..self, phase: Over, pending: 0, }, Finished(sends~, stop~, conclusion))
}

///|
fn Conversation::exit(
  self : Conversation,
  conclusion : Conclusion,
) -> (Conversation, Step) {
  self.over(CloseAfterExit, conclusion, sends=[
    notification_message("morphir.exit"),
  ])
}

///|
fn Conversation::shutdown(
  self : Conversation,
  phase : Phase,
) -> (Conversation, Step) {
  let id = self.next_id
  (
    { ..self, phase, pending: id, next_id: id + 1, },
    Exchange(sends=[shutdown_message(id)], awaiting=id),
  )
}

///|
fn Conversation::transport_fault(
  self : Conversation,
  error : ChannelError,
) -> Ending {
  if self.phase is Refusing(ending) {
    return ending
  }
  // The transport found the request too large before it wrote it, so the
  // worker never saw it: the call is refused.
  if error is FrameLimit(direction=Request, declared~, limit~) {
    return Refused(
      code=RequestLimit,
      message="a request frame has \{declared} bytes; the limit is \{limit}",
    )
  }
  if error is GuestFailed(fault) {
    return fault.ending()
  }
  // The worker refused to serve before it read a request.
  if error is Refused(code~, message~) {
    return Refused(code~, message~)
  }
  Failed(
    match error {
      FrameInvalid(text) => Host(code=FrameInvalid, message=text)
      // A failed pipe ends the session before it is complete; the text keeps
      // which stream failed and why.
      TransportFailed(text) => Host(code=IncompleteSession, message=text)
      FrameLimit(declared~, limit~, ..) =>
        Host(
          code=ResponseLimit,
          message="a frame declared \{declared} bytes; the limit is \{limit}",
        )
      // A guest fault and a refusal returned above.
      WorkerClosed | Stopped | GuestFailed(_) | Refused(..) =>
        match self.phase {
          Describing =>
            Host(
              code=DescribeFailed,
              message="the worker stopped before it described itself",
            )
          ShuttingDown =>
            Host(
              code=IncompleteSession,
              message="the worker stopped before the shutdown response",
            )
          _ =>
            Host(
              code=IncompleteSession,
              message="the worker stopped before the session ended",
            )
        }
    },
  )
}

///|
/// Advances the session with one event. While the session refuses a worker,
/// the refusal stays the ending; a deadline or a stop only sets how the
/// worker is stopped.
pub fn Conversation::on(
  self : Conversation,
  event : Event,
) -> (Conversation, Step) {
  let ending = (ending : Ending) => {
    match self.phase {
      Refusing(refusal) => EndedEarly(refusal)
      _ => EndedEarly(ending)
    }
  }
  match event {
    StopRequested => self.over(Abort(Cancelled), ending(Cancelled))
    DeadlinePassed => self.over(Abort(Deadline), ending(Deadline))
    ChannelFailed(error) =>
      self.over(Abort(Fault), EndedEarly(self.transport_fault(error)))
    Received(message) => self.received(message)
  }
}

///|
fn Conversation::received(
  self : Conversation,
  message : Message,
) -> (Conversation, Step) {
  // A refusal stays the reason when the worker then answers badly.
  let fault = (fault : Fault) => {
    let ending = match self.phase {
      Refusing(ending) => ending
      _ => Failed(fault)
    }
    self.over(Abort(Fault), EndedEarly(ending))
  }
  if self.pending == 0 {
    return fault(
      Host(
        code=UnexpectedResponse,
        message="a message when no request was pending",
      ),
    )
  }
  let reply = match
    read_reply(
      message,
      pending=self.pending,
      answered=self.answered,
      limit=self.limits.response_bytes,
    ) {
    Ok(Some(reply)) => reply
    // A notification from the worker is skipped.
    Ok(None) => return (self, Exchange(sends=[], awaiting=self.pending))
    Err(error) => return fault(error)
  }
  { ..self, answered: [..self.answered, self.pending], }.replied(reply)
}

///|
fn Conversation::replied(
  self : Conversation,
  reply : Reply,
) -> (Conversation, Step) {
  match (self.phase, reply) {
    (Describing, GuestError(code~, message~, ..)) =>
      self.exit(
        EndedEarly(
          Failed(
            Host(
              code=DescribeFailed,
              message="describe returned error \{code}: \{message}",
            ),
          ),
        ),
      )
    (Describing, Answer(result)) => {
      let claims = read_claims(result) catch {
        error =>
          return self.exit(
            EndedEarly(
              Failed(
                Host(
                  code=DescribeFailed,
                  message="the describe result has no valid claims: \{error}",
                ),
              ),
            ),
          )
      }
      self.exit(Described({ claims, }))
    }
    (Initializing(_), GuestError(code~, message~, data~)) =>
      self.exit(EndedEarly(Failed(Guest(code~, message~, data~))))
    (Initializing(offer, expected), Answer(result)) =>
      self.initialized(offer, expected, result)
    (Refusing(ending), _) => self.exit(EndedEarly(ending))
    (Calling(kind, operation), reply) => {
      let answer = match reply {
        GuestError(code~, message~, data~) =>
          { class: Failed(Guest(code~, message~, data~)), diagnostics: [], }
        _ => self.answer(kind, operation, reply)
      }
      ({ ..self, phase: Called, pending: 0, }, Answered(sends=[], answer))
    }
    (ShuttingDown, GuestError(code~, message~, data~)) =>
      self.exit(EndedEarly(Failed(Guest(code~, message~, data~))))
    (ShuttingDown, _) => self.exit(Closed)
    // These phases have no pending request, so `received` refuses a reply
    // before it gets here.
    (Ready | Called | Over, _) =>
      self.over(
        Abort(Fault),
        EndedEarly(
          Failed(
            Host(code=UnexpectedResponse, message="an unsolicited response"),
          ),
        ),
      )
  }
}

///|
fn Conversation::initialized(
  self : Conversation,
  offer : Offer,
  expected : Claims,
  result : Json,
) -> (Conversation, Step) {
  let line = offer.line()
  guard field_at(result, ["protocolVersion"]) is Some(String(version)) &&
    version == line.to_string() else {
    return self.exit(
      EndedEarly(
        Refused(
          code=ProtocolUnavailable,
          message="the worker did not select MEP \{line}, which the host offered",
        ),
      ),
    )
  }
  let refuse = (code : RefusalCode, message : String) => {
    self.shutdown(Refusing(Refused(code~, message~)))
  }
  let live = read_claims(result) catch {
    error =>
      return refuse(
        ClaimsMismatch,
        "the initialize result has no valid claims: \{error}",
      )
  }
  if compare_claims(expected, live, offer) is Some(text) {
    return refuse(ClaimsMismatch, text)
  }
  let (tuple, limits) = match offer {
    Legacy => (None, self.limits)
    Model(offered) => {
      let tuple = match agreement(offered, result) {
        Agreed(tuple) => tuple
        Empty =>
          return refuse(
            TupleUnavailable,
            "the worker agreed on none of the offered tuples",
          )
        Mismatch(text) => return refuse(AgreementMismatch, text)
      }
      let worker = read_model_limits(
        field_at(result, ["capabilities", "modelTransport"]),
      ) catch {
        error =>
          return refuse(
            AgreementMismatch,
            "the worker declared no valid model limits: \{error}",
          )
      }
      (Some(tuple), { ..self.limits, model: self.limits.model.min(worker), })
    }
  }
  let negotiated = { offer, tuple, limits, }
  (
    { ..self, phase: Ready, pending: 0, limits, negotiated: Some(negotiated), },
    Activated(sends=[notification_message("morphir.initialized")], negotiated),
  )
}

///|
/// What a worker's answer to `initialize` agreed on the model line.
priv enum Agreement {
  Agreed(ModelTuple)
  Empty
  Mismatch(String)
}

///|
/// Checks the agreed tuples in an `initialize` result against the offer
/// (SES-3). The worker returns the intersection of its support with the
/// offer, in the host's order, and the session uses the first tuple. An
/// empty agreement is `Empty`. A tuple that the host did not offer, or an
/// order other than the host's, is `Mismatch`.
fn agreement(offered : Array[ModelTuple], result : Json) -> Agreement {
  let items = match
    field_at(result, ["capabilities", "modelTransport", "tuples"]) {
    Some(Array(items)) => items
    _ => []
  }
  let mut last = -1
  for item in items {
    guard tuple_of(item) is Some(tuple) && offered.search(tuple) is Some(index) else {
      return Mismatch(
        "the worker agreed on a tuple that the host did not offer: \{item.stringify()}",
      )
    }
    guard index > last else {
      return Mismatch("the agreed tuples do not keep the host's order")
    }
    last = index
  }
  guard items is [first, ..] && tuple_of(first) is Some(tuple) else {
    return Empty
  }
  Agreed(tuple)
}

///|
fn tuple_of(value : Json) -> ModelTuple? {
  let parts = ["operation", "profile", "codec", "envelopeVersion", "irVersion"].filter_map(name => {
      if field_at(value, [name]) is Some(String(text)) {
        Some(text)
      } else {
        None
      }
    },
  )
  guard parts.length() == 5 else { return None }
  try
    ModelTuple::parse(parts[0], parts[1], parts[2], parts[3], parts[4])
  catch {
    _ => None
  } noraise {
    tuple => Some(tuple)
  }
}

///|
fn utf8_length(text : String) -> Int32 {
  @utf8.encode(text).length()
}

///|
fn base64_digit(char : Char) -> Bool {
  (char >= 'A' && char <= 'Z') ||
  (char >= 'a' && char <= 'z') ||
  (char >= '0' && char <= '9') ||
  char == '+' ||
  char == '/'
}

///|
/// The number of bytes that padded base64 `content` decodes to, or `None`
/// when it is not padded base64. It reads the text and does not decode it.
fn base64_decoded_length(content : String) -> Int32? {
  let length = content.length()
  guard length % 4 == 0 else { return None }
  let mut padding = 0
  for index, char in content.iter().collect() {
    if char == '=' {
      guard index >= length - 2 else { return None }
      padding += 1
    } else {
      guard padding == 0 && base64_digit(char) else { return None }
    }
  }
  Some(length / 4 * 3 - padding)
}

///|
/// Checks a model payload against the effective model limits: its encoded
/// size, then the decoded length that its base64 content gives, which must be
/// the `decodedByteLength` it declares. The depth and node limits are
/// negotiated, and the party that decodes the model enforces them: the guest
/// for a request, the CLI's model decoder for a result. The host does not
/// check them.
fn model_payload_problem(payload : Json?, limits : ModelLimits) -> String? {
  guard payload is Some(payload) else { return None }
  guard field_at(payload, ["content"]) is Some(String(content)) else {
    return Some("the model payload has no base64 content")
  }
  guard integer(field_at(payload, ["decodedByteLength"])) is Some(declared) else {
    return Some("the model payload has no decodedByteLength")
  }
  let encoded = utf8_length(content)
  if encoded > limits.encoded_bytes {
    return Some(
      "the model has \{encoded} encoded bytes; the effective limit is \{limits.encoded_bytes}",
    )
  }
  guard base64_decoded_length(content) is Some(decoded) else {
    return Some("the model content is not padded base64")
  }
  if decoded != declared {
    return Some(
      "the model declares \{declared} decoded bytes; its content decodes to \{decoded}",
    )
  }
  if decoded > limits.decoded_bytes {
    return Some(
      "the model has \{decoded} decoded bytes; the effective limit is \{limits.decoded_bytes}",
    )
  }
  None
}

///|
/// Decodes the guest's diagnostics. A malformed entry does not drop the
/// valid ones: each one is kept, and a host warning names each malformed
/// entry by its index.
fn decode_diagnostics(
  items : Array[Json],
  operation : Operation,
) -> Array[Diagnostic] {
  let valid = []
  let malformed = []
  for index, item in items {
    try Diagnostic::decode(item) catch {
      error =>
        malformed.push({
          severity: Warning,
          code: Some(FaultCode::UnexpectedResponse.to_string()),
          message: "\{operation} returned a malformed diagnostic \{index}: \{error}",
          location: None,
          related: [],
          data: None,
        })
    } noraise {
      diagnostic => valid.push(diagnostic)
    }
  }
  [..valid, ..malformed]
}

///|
fn Conversation::answer(
  self : Conversation,
  kind : CallKind,
  operation : Operation,
  reply : Reply,
) -> Answer {
  let broken = (message : String) => {
    class: Failed(Host(code=UnexpectedResponse, message~)),
    diagnostics: [],
  }
  guard reply is Answer(Object(fields) as result) else {
    return broken("the result of \{operation} is not an object")
  }
  guard fields.get("success") is Some(True | False as success) else {
    return broken("the result of \{operation} has no success flag")
  }
  let diagnostics = match fields.get("diagnostics") {
    None => []
    Some(Array(items)) => decode_diagnostics(items, operation)
    Some(_) => return broken("the diagnostics of \{operation} are not a list")
  }
  if kind is CompileCall &&
    operation is CompileModel &&
    model_payload_problem(
      field_at(result, ["model", "payload"]),
      self.limits.model,
    )
    is Some(problem) {
    return {
      class: Failed(Host(code=ResponseLimit, message=problem)),
      diagnostics,
    }
  }
  {
    class: if success is True {
      Completed(result)
    } else {
      Unsuccessful
    },
    diagnostics,
  }
}

///|
fn Conversation::call(
  self : Conversation,
  call : Call,
) -> (Conversation, Step) raise SessionUnavailable {
  guard self.phase is Ready &&
    self.negotiated is Some(negotiated) &&
    self.expected is Some(expected) else {
    raise SessionUnavailable("the session is not ready for an operation")
  }
  let refuse = (code : RefusalCode, message : String) => {
    (
      self,
      Answered(sends=[], { class: Refused(code~, message~), diagnostics: [], }),
    )
  }
  let offer = negotiated.offer
  let operation = call.kind.operation(offer)
  guard offer.operations().contains(operation) else {
    return refuse(
      CapabilityUnavailable,
      "this session negotiated \{offer.operations()[0]}, not \{operation}",
    )
  }
  guard expected.offers(operation) else {
    return refuse(
      CapabilityUnavailable,
      "\{expected.extension_id} does not claim \{operation}",
    )
  }
  let call = if negotiated.tuple is Some(tuple) {
    let key = if call.kind is CompileCall { "output" } else { "input" }
    let params = call.params.copy()
    match params.get(key) {
      None => params[key] = tuple.to_json()
      Some(value) =>
        if tuple_of(value) != Some(tuple) {
          return refuse(
            TupleUnavailable,
            "the request names another tuple than the session negotiated",
          )
        }
    }
    { ..call, params, }
  } else {
    call
  }
  let id = self.next_id
  let message = call.message(id, operation)
  let size = framed_size(message.size())
  if size > self.limits.request_bytes {
    return refuse(
      RequestLimit,
      "the request frame has \{size} bytes; the limit is \{self.limits.request_bytes}",
    )
  }
  if operation is GenerateModel &&
    model_payload_problem(
      field_at(Json::object(call.params), ["model", "payload"]),
      self.limits.model,
    )
    is Some(problem) {
    return refuse(RequestLimit, problem)
  }
  (
    {
      ..self,
      phase: Calling(call.kind, operation),
      pending: id,
      next_id: id + 1,
    },
    Exchange(sends=[message], awaiting=id),
  )
}

///|
/// Starts the one compile call of a ready session. A call that the session
/// cannot make is refused without sending anything.
pub fn Conversation::compile(
  self : Conversation,
  request : CompileRequest,
) -> (Conversation, Step) raise SessionUnavailable {
  self.call(request.call)
}

///|
/// Starts the one generate call of a ready session.
pub fn Conversation::generate(
  self : Conversation,
  request : GenerateRequest,
) -> (Conversation, Step) raise SessionUnavailable {
  self.call(request.call)
}

///|
/// Starts the end of a ready session: `shutdown`, then `exit`.
pub fn Conversation::close(
  self : Conversation,
) -> (Conversation, Step) raise SessionUnavailable {
  guard self.phase is (Ready | Called) else {
    raise SessionUnavailable("the session cannot close in its current state")
  }
  self.shutdown(ShuttingDown)
}

///|
/// How a WASM guest fault ends a session. A per-call deadline is a deadline;
/// an exhausted instruction budget is a resource limit, not a timeout.
fn GuestFault::ending(self : GuestFault) -> Ending {
  match self {
    Trap(text) =>
      Failed(Host(code=GuestTrap, message="the guest trapped: \{text}"))
    MemoryLimit(text) =>
      Failed(
        Host(
          code=MemoryLimit,
          message="the guest grew its memory past the ceiling: \{text}",
        ),
      )
    CallDeadline => Deadline
    BudgetExhausted =>
      Failed(
        Host(
          code=BudgetExhausted,
          message="the guest used its instruction budget for the call",
        ),
      )
    Failure(text) => Failed(Host(code=IncompleteSession, message=text))
  }
}
