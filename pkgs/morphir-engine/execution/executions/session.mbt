///|
pub(all) suberror Invalid {
  Invalid(String)
}

///|
/// An in-memory host owner. Callers serialize access across asynchronous tasks.
/// Authentication and provider grants belong to the composing host.
pub struct Session {
  priv offer : @receipts.Offer
  priv executions : Map[String, Execution]
  priv max_executions : Int32
  priv max_bytes : Int32
  priv mut reserved : Int32
  priv mut next : Int32
}

///|
priv struct Execution {
  identity : @receipts.Identity
  unit_id : String
  snapshot : Bytes
  suite : Bytes
  cursor : @receipts.Cursor
  reserved : Int32
  kind : ExecutionKind
}

///|
priv enum Publication {
  Submitted
  Running
  Terminal(@protocol.Outcomes)
}

///|
/// Reserve a full receipt budget at submission so terminal publication does not
/// compete with other executions for space. This bounds serialized retained evidence,
/// not allocator overhead or temporary planning allocations.
pub fn Session::new(
  offer : @receipts.Offer,
  max_executions~ : Int32 = 8,
  max_bytes~ : Int32 = 16 * 1024 * 1024,
) -> Session raise {
  if max_executions <= 0 ||
    max_executions > 64 ||
    max_bytes < 1024 * 1024 ||
    max_bytes > 64 * 1024 * 1024 {
    raise Invalid("workbench.host_limits")
  }
  {
    offer,
    executions: Map([]),
    max_executions,
    max_bytes,
    reserved: 0,
    next: 1,
  }
}

///|
pub fn Session::offer(self : Session) -> @receipts.Offer {
  self.offer
}

///|
/// Capture the full rich unit and invocation suite before planning. No caller's
/// mutable IR, argument, metadata or manifest arrays enter retained state.
pub fn Session::submit(
  self : Session,
  unit : @data.IRUnit,
  suite : @protocol.Suite,
) -> @receipts.Receipt raise {
  self.submit_with(unit, suite, None)
}

///|
fn Session::submit_with(
  self : Session,
  unit : @data.IRUnit,
  suite : @protocol.Suite,
  policy : @execution.CapabilityPolicy?,
) -> @receipts.Receipt raise {
  if self.executions.length() >= self.max_executions || self.next == 2147483647 {
    raise Invalid("workbench.host_capacity")
  }
  let registry = @data.Registry::new()
  let snapshot = match registry.encode("ion-binary", unit) {
    Binary(bytes) => bytes
    Text(_) => raise Invalid("workbench.host_snapshot")
  }
  let encoded_suite = suite.encode("json")
  // Decode through the bounded public codec before any provider can acquire.
  let captured_suite = @protocol.Suite::decode(encoded_suite, "json")
  let mut reserved = snapshot.length() + encoded_suite.length() + 1024 * 1024
  if reserved > self.max_bytes - self.reserved {
    raise Invalid("workbench.host_capacity")
  }
  let captured = registry.decode("ion-binary", {
    unit_id: unit.id,
    content: Binary(snapshot),
  })
  captured.validate()
  let kind = match policy {
    None => {
      ignore(@execution.plan(captured, captured_suite))
      Legacy
    }
    Some(policy) => {
      let plan = @execution.plan_scheme_capabilities(
        captured,
        captured_suite,
        policy~,
      )
      let boundary = @utf8.encode(plan.boundary_json().stringify())
      reserved += boundary.length()
      if reserved > self.max_bytes - self.reserved {
        raise Invalid("workbench.host_capacity")
      }
      Scheme("plan-" + self.next.to_string(), Scheme, policy, boundary)
    }
  }
  guard self.offer.to_json() is Object(authority) else {
    raise Invalid("workbench.host_authority")
  }
  let identity = @receipts.Identity::from_json({
    "hostId": authority["hostId"],
    "sessionId": authority["sessionId"],
    "providerId": authority["providerId"],
    "executionId": "execution-" + self.next.to_string(),
    "snapshotId": "snapshot-" + self.next.to_string(),
  })
  let initial = receipt(identity, 0, Submitted, false)
  let cursor = @receipts.Cursor::start(
    self.offer,
    identity,
    captured_suite.calls.map(c => c.id),
    initial,
  )
  let execution = Execution::{
    identity,
    unit_id: unit.id,
    snapshot,
    suite: encoded_suite,
    cursor,
    reserved,
    kind,
  }
  // All operations that can raise precede changes to the owner.
  self.executions[key(identity)] = execution
  self.reserved += reserved
  self.next += 1
  initial
}

///|
fn key(identity : @receipts.Identity) -> String {
  identity.to_json().stringify()
}

///|
fn Session::lookup(
  self : Session,
  identity : @receipts.Identity,
) -> Execution raise {
  guard self.executions.get(key(identity)) is Some(execution) &&
    execution.identity == identity else {
    raise Invalid("workbench.host_unknown_execution")
  }
  execution
}

///|
/// Each query decodes a fresh receipt; changing the result cannot edit history.
pub fn Session::query(
  self : Session,
  identity : @receipts.Identity,
) -> @receipts.Receipt raise {
  self.lookup(identity).cursor.latest()
}

///|
fn Execution::plan(self : Execution) -> @execution.Plan raise {
  guard self.kind is Legacy else {
    raise Invalid("workbench.host_execution_kind")
  }
  let unit = @data.Registry::new().decode("ion-binary", {
    unit_id: self.unit_id,
    content: Binary(self.snapshot),
  })
  @execution.plan(unit, @protocol.Suite::decode(self.suite, "json"))
}

///|
/// A single worker claims a validated, independently decoded plan. Claiming again
/// rejects even if the first worker loses its connection. There is no retry lease.
pub fn Session::claim(
  self : Session,
  identity : @receipts.Identity,
) -> @execution.Plan raise {
  let execution = self.lookup(identity)
  let latest = execution.cursor.latest()
  guard latest.state() is Submitted else {
    raise Invalid("workbench.host_already_claimed")
  }
  let plan = execution.plan()
  ignore(
    self.advance(
      execution,
      receipt(
        identity,
        latest.sequence() + 1,
        Running,
        latest.cancel_requested(),
      ),
    ),
  )
  plan
}

///|
/// Acknowledgement is authoritative; termination remains the worker's outcome.
/// Query-only providers must never be composed with a cancellation control.
pub fn Session::cancel(
  self : Session,
  identity : @receipts.Identity,
) -> @receipts.Receipt raise {
  let execution = self.lookup(identity)
  let latest = execution.cursor.latest()
  match execution.cursor.cancel_action() {
    AlreadyTerminal | Pending => latest
    Unavailable | Disconnected =>
      raise Invalid("workbench.host_cancel_unavailable")
    Send =>
      self.advance(
        execution,
        receipt(
          identity,
          latest.sequence() + 1,
          if latest.state() is Running {
            Running
          } else {
            Submitted
          },
          true,
        ),
      )
  }
}

///|
/// Reconstruct declarations from the retained snapshot, not from a worker's
/// mutable Plan. Validate every output before changing the authoritative cursor.
/// Cleanup must already be final when a composing host calls this method.
pub fn Session::complete(
  self : Session,
  identity : @receipts.Identity,
  outcomes : @protocol.Outcomes,
) -> @receipts.Receipt raise {
  let execution = self.lookup(identity)
  match execution.kind {
    Legacy => {
      let plan = execution.plan()
      @protocol.validate_outcomes(
        outcomes,
        plan.suite,
        plan.library.invocations.map(e => @protocol.PublicEntry::{
          name: e.fqname,
          inputs: e.inputs,
          output: e.output,
        }),
        plan.library.invocation_types,
      )
    }
    Scheme(_, _, _, _) => execution.scheme_plan().validate_outcomes(outcomes)
  }
  let latest = execution.cursor.latest()
  let sequence = if latest.state() is Terminal(_) {
    latest.sequence()
  } else {
    latest.sequence() + 1
  }
  self.advance(
    execution,
    receipt(identity, sequence, Terminal(outcomes), latest.cancel_requested()),
  )
}

///|
fn Session::advance(
  self : Session,
  execution : Execution,
  receipt : @receipts.Receipt,
) -> @receipts.Receipt raise {
  let (cursor, _) = execution.cursor.observe(receipt)
  let result = cursor.latest()
  self.executions[key(execution.identity)] = { ..execution, cursor, }
  result
}

///|
/// Only an explicit terminal release frees storage. Pending work is never evicted.
pub fn Session::release(
  self : Session,
  identity : @receipts.Identity,
) -> Unit raise {
  let execution = self.lookup(identity)
  guard execution.cursor.latest().state() is Terminal(_) else {
    raise Invalid("workbench.host_not_terminal")
  }
  self.executions.remove(key(identity))
  self.reserved -= execution.reserved
}

///|
fn receipt(
  identity : @receipts.Identity,
  sequence : Int32,
  state : Publication,
  acknowledged : Bool,
) -> @receipts.Receipt raise {
  let (state, outcomes) = match state {
    Submitted => ("submitted", Json::null())
    Running => ("running", Json::null())
    Terminal(outcomes) => ("terminal", outcomes.to_json())
  }
  @receipts.Receipt::from_json({
    "contractVersion": "0.2.0-draft.1",
    "identity": identity.to_json(),
    "sequence": sequence,
    "state": state,
    "cancelRequested": acknowledged,
    "outcomes": outcomes,
  })
}
