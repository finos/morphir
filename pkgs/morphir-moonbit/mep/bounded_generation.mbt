///|
/// A bounded operation owns the state for one snapshot through release.
pub struct BoundedOperation {
  priv advance : (@model_access.Advance) -> @model_access.GenerationStep
  priv release : () -> Unit
}

///|
pub fn BoundedOperation::new(
  advance~ : (@model_access.Advance) -> @model_access.GenerationStep,
  release~ : () -> Unit,
) -> BoundedOperation {
  { advance, release, }
}

///|
/// The embedding registers bounded generation for the existing MoonBit target.
pub struct BoundedBackend {
  priv support : @model_access.Support
  priv start : (@model_access.Start) -> (
    @model_access.GenerationStep,
    BoundedOperation,
  )
}

///|
pub fn BoundedBackend::new(
  support : @model_access.Support,
  start : (@model_access.Start) -> (
    @model_access.GenerationStep,
    BoundedOperation,
  ),
) -> BoundedBackend {
  { support, start, }
}

///|
priv enum BoundedActivation {
  BoundedInactive
  BoundedWaiting(@model_access.Support?)
  BoundedReady(@model_access.Support?)
}

///|
priv struct GuestGeneration {
  run : @model_access.GenerationRun
  operation : BoundedOperation
}

///|
fn Session::release_generation(self : Session) -> Unit {
  if self.generation is Some(active) {
    self.generation = None
    (active.operation.release)()
  }
}

///|
fn Session::generation_result(
  self : Session,
  id : Json,
  active : GuestGeneration,
  step : @model_access.GenerationStep,
) -> Json {
  let encoded = step.to_json()
  let next = try {
    let checked = @model_access.GenerationStep::from_json(encoded)
    active.run.accept_step(checked)
  } catch {
    _ => {
      self.release_generation()
      return rpc_error(
        id, -32603, "The generation backend returned an invalid step",
      )
    }
  }
  match next {
    Some(run) => self.generation = Some({ ..active, run, })
    None => self.release_generation()
  }
  result(id, encoded)
}

///|
fn Session::bounded_message(
  self : Session,
  id : Json,
  operation : String,
  params : Json,
) -> Json {
  guard self.bounded_activation is BoundedReady(Some(agreed)) &&
    self.bounded is Some(backend) else {
    return rpc_error(id, -32013, "Bounded model access was not admitted")
  }
  match operation {
    method_name if method_name == @model_access.START => {
      let request = @model_access.Start::from_json(params) catch {
        _ => return rpc_error(id, -32602, "Invalid bounded start parameters")
      }
      guard self.generation is None &&
        !self.used_generation_ids.contains(request.session_id) &&
        agreed.tuples().contains(request.input) &&
        request.target == "moonbit" &&
        request.limits.at_most(agreed.limits) else {
        return rpc_error(
          id, -32602, "The start must use a fresh generation ID, an agreed tuple, a supported target and admitted limits",
        )
      }
      self.used_generation_ids.push(request.session_id)
      let (step, operation) = (backend.start)(request)
      let active = {
        run: @model_access.GenerationRun::new(request),
        operation,
      }
      self.generation = Some(active)
      self.generation_result(id, active, step)
    }
    method_name if method_name == @model_access.ADVANCE => {
      let request = @model_access.Advance::from_json(params) catch {
        _ => return rpc_error(id, -32602, "Invalid bounded advance parameters")
      }
      guard self.generation is Some(active) && active.run.accepts(request) else {
        return rpc_error(
          id, -32602, "The advance does not match the active generation, round or deliveries",
        )
      }
      let step = (active.operation.advance)(request)
      self.generation_result(id, active, step)
    }
    _ => {
      let request = @model_access.Cancel::from_json(params) catch {
        _ =>
          return rpc_error(
            id, -32602, "Invalid bounded cancellation parameters",
          )
      }
      guard self.generation is Some(active) &&
        active.run.session_id == request.session_id else {
        return rpc_error(
          id, -32602, "The cancellation names no active generation",
        )
      }
      self.release_generation()
      result(id, request.to_json())
    }
  }
}
