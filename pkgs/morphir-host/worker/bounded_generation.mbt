///|
/// A reply to a bounded generation request or its cancellation.
#derive(Eq, Debug)
pub(all) enum GenerationReply {
  Stepped(@model_access.GenerationStep)
  CancelledGeneration(@model_access.Cancel)
}

///|
pub extend GenerationReply with Eq::{equal, not_equal}

///|
pub extend GenerationReply with @debug.Debug::{to_repr}

///|
#derive(Eq, Debug)
pub struct GenerationAnswer {
  class : OutcomeClass[GenerationReply]
  diagnostics : Array[Diagnostic]
}

///|
pub extend GenerationAnswer with Eq::{equal, not_equal}

///|
pub extend GenerationAnswer with @debug.Debug::{to_repr}

///|
#derive(Eq, Debug)
priv enum PendingGeneration {
  Next(@model_access.GenerationRun)
  Cancel(@model_access.GenerationRun, close~ : Bool)
}

///|
fn PendingGeneration::run(
  self : PendingGeneration,
) -> @model_access.GenerationRun {
  match self {
    Next(run) | Cancel(run, ..) => run
  }
}

///|
fn Conversation::generation_refusal(
  self : Conversation,
  code : RefusalCode,
  message : String,
) -> (Conversation, Step) {
  (
    self,
    BoundedAnswered(sends=[], {
      class: Refused(code~, message~),
      diagnostics: [],
    }),
  )
}

///|
fn Conversation::send_generation(
  self : Conversation,
  pending : PendingGeneration,
  method_name : String,
  params : Json,
) -> (Conversation, Step) {
  let id = self.next_id
  let message = Message::new({
    "jsonrpc": "2.0",
    "id": id,
    "method": method_name,
    "params": params,
  })
  let size = framed_size(message.size())
  let ceiling = pending.run().limits.frame_bytes()
  guard size.to_int64() <= ceiling && id < 2147483647 else {
    return self.generation_refusal(
      RequestLimit,
      "the bounded request exceeds the frame limit or request ID space",
    )
  }
  let used = if pending is Next(run) && run.round == 0 {
    [..self.used_generation_ids, run.session_id]
  } else {
    self.used_generation_ids
  }
  (
    {
      ..self,
      phase: CallingGeneration(pending),
      pending: id,
      next_id: id + 1,
      used_generation_ids: used,
    },
    Exchange(sends=[message], awaiting=id),
  )
}

///|
/// Starts a new operation only after live draft.2 admission.
pub fn Conversation::start_generation(
  self : Conversation,
  request : @model_access.Start,
) -> (Conversation, Step) raise SessionUnavailable {
  guard self.phase is Ready else {
    raise SessionUnavailable("the session is not ready for generation")
  }
  guard self.negotiated is Some({ model_access: Some(access), .. }) &&
    self.expected is Some(claims) else {
    return self.generation_refusal(
      ProtocolUnavailable,
      "bounded access was not admitted",
    )
  }
  guard self.generation is None &&
    !self.used_generation_ids.contains(request.session_id) else {
    return self.generation_refusal(
      AgreementMismatch,
      "the generation ID is active or has already been used",
    )
  }
  guard access.tuples().contains(request.input) else {
    return self.generation_refusal(
      TupleUnavailable,
      "the requested bounded tuple was not agreed",
    )
  }
  guard claims.targets
    .iter()
    .any(target => target.to_string() == request.target) else {
    return self.generation_refusal(
      CapabilityUnavailable,
      "the worker did not claim this generation target",
    )
  }
  guard request.limits.at_most(access.limits) else {
    return self.generation_refusal(
      RequestLimit,
      "the start raises an agreed limit",
    )
  }
  let run = @model_access.GenerationRun::new(request)
  self.send_generation(Next(run), @model_access.START, request.to_json())
}

///|
/// An invalid advance consumes neither the pending delivery list nor a wire ID.
pub fn Conversation::advance_generation(
  self : Conversation,
  request : @model_access.Advance,
) -> (Conversation, Step) raise SessionUnavailable {
  guard self.phase is Ready else {
    raise SessionUnavailable("there is another exchange in flight")
  }
  guard self.generation is Some(run) && run.accepts(request) else {
    return self.generation_refusal(
      AgreementMismatch,
      "the advance does not match the active session, round or requests",
    )
  }
  self.send_generation(Next(run), @model_access.ADVANCE, request.to_json())
}

///|
pub fn Conversation::cancel_generation(
  self : Conversation,
  request : @model_access.Cancel,
) -> (Conversation, Step) raise SessionUnavailable {
  guard self.phase is Ready else {
    raise SessionUnavailable("there is another exchange in flight")
  }
  guard self.generation is Some(run) && run.session_id == request.session_id else {
    return self.generation_refusal(
      AgreementMismatch,
      "the cancellation names no active generation",
    )
  }
  self.send_generation(
    Cancel(run, close=false),
    @model_access.CANCEL,
    request.to_json(),
  )
}

///|
fn Conversation::bad_generation_reply(
  self : Conversation,
  message : String,
) -> (Conversation, Step) {
  self.over(
    Abort(Fault),
    EndedEarly(Failed(Host(code=UnexpectedResponse, message~))),
  )
}

///|
fn Conversation::generation_reply(
  self : Conversation,
  pending : PendingGeneration,
  reply : Reply,
) -> (Conversation, Step) {
  match reply {
    GuestError(code~, message~, data~) => {
      let fault : Fault = Guest(code~, message~, data~)
      if pending is Cancel(_, ..) {
        return self.over(Abort(Fault), EndedEarly(Failed(fault)))
      }
      // Invalid parameters can be corrected and retried against the same round.
      let generation = if code == -32602 { self.generation } else { None }
      (
        { ..self, phase: Ready, pending: 0, generation, },
        BoundedAnswered(sends=[], { class: Failed(fault), diagnostics: [], }),
      )
    }
    Answer(value) => {
      let run = pending.run()
      match pending {
        Cancel(_, close~) => {
          let acknowledgement = @model_access.Cancel::from_json(value) catch {
            _ =>
              return self.bad_generation_reply(
                "invalid bounded cancellation acknowledgement",
              )
          }
          guard acknowledgement.session_id == run.session_id else {
            return self.bad_generation_reply(
              "cancellation acknowledgement names another generation",
            )
          }
          let settled = { ..self, phase: Ready, pending: 0, generation: None, }
          if close {
            return settled.shutdown(ShuttingDown)
          }
          (
            settled,
            BoundedAnswered(sends=[], {
              class: Completed(CancelledGeneration(acknowledgement)),
              diagnostics: [],
            }),
          )
        }
        Next(_) => {
          let step = @model_access.GenerationStep::from_json(value) catch {
            @model_wire.Invalid(code, detail) =>
              return self.bad_generation_reply(
                "invalid generation result: \{code}: \{detail}",
              )
          }
          let generation = run.accept_step(step) catch {
            @model_wire.Invalid(_, detail) =>
              return self.bad_generation_reply(detail)
          }
          let diagnostics = step.diagnostics().map(Diagnostic::decode) catch {
              error =>
                return self.bad_generation_reply(
                  "invalid generation diagnostic: \{error}",
                )
            }
          (
            { ..self, phase: Ready, pending: 0, generation, },
            BoundedAnswered(sends=[], {
              class: Completed(Stepped(step)),
              diagnostics,
            }),
          )
        }
      }
    }
  }
}
