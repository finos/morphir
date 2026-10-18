///|
fn host_scope(identity : Json) -> String {
  canonical(
    (
      [
        field(identity, "hostId"),
        field(identity, "sessionId"),
        field(identity, "providerId"),
      ] : Json),
  )
}

///|
fn Runtime::executions(
  self : Runtime,
  session : String,
) -> @bridge.ExecutionsService raise {
  let session_name = self.aliases.session(session)
  self.log({ "event": "executions.create", "session": session_name })
  if field(field(self.input, "services"), "executions") ==
    Json::string("unavailable") {
    raise @workspace.Rejected("controlled executions unavailable")
  }
  self.next_service += 1
  let offer : Json = {
    "profile": "morphir/workbench/executions",
    "contractVersion": "0.2.0-draft.1",
    "hostId": "controlled-host-" + self.next_service.to_string(),
    "sessionId": session,
    "providerId": "moonbit-scheme",
    "operations": ["query", "cancel"],
  }
  let cleanup = self.cleanups
    .get(session_name)
    .unwrap_or_else(fn() { { gate: Gate::new(None, false), success: true, } })
  let service : ControlledExecutions = {
    host: @executions.Host::new(offer.stringify()),
    session,
    cleanup,
    closed: false,
    reserved: 0,
  }
  self.services[canonical(
    (
      [
        field(offer, "hostId"),
        Json::string(session),
        field(offer, "providerId"),
      ] : Json),
  )] = service
  {
    offer: fn() {
      self.log({ "event": "executions.offer", "session": session_name })
      offer
    },
    request: fn(operation, payload) {
      self.execution_request(service, operation, payload)
    },
    close: fn() {
      self.log({ "event": "executions.close", "session": session_name })
      service.closed = true
      // Owner::revoke immediately schedules one background shutdown for this
      // synchronous close. Reserve its work before that coroutine can start.
      service.reserved += 1
      self.runnable += 1
    },
    shutdown: async fn() { self.execution_shutdown(service) },
  }
}

///|
async fn Runtime::execution_shutdown(
  self : Runtime,
  service : ControlledExecutions,
) -> Unit {
  let background = service.reserved > 0
  if background {
    service.reserved -= 1
  }
  defer (if background { self.finished() })
  service.closed = true
  let gate = service.cleanup.gate
  let session = self.aliases.session(service.session)
  let id = gate.id.map(Json::string).unwrap_or(Json::null())
  self.log({ "event": "cleanup.begin", "session": session, "id": id })
  if !gate.entered && gate.id != None {
    self.used_cleanups += 1
  }
  gate.entered = true
  self.wait_gate(gate)
  // Success/failure is fixed for the service lifetime. Every waiter observes
  // the same settled result, including waiters arriving after delivery.
  self.log({
    "event": "cleanup.result",
    "session": session,
    "id": id,
    "success": service.cleanup.success,
  })
  if !service.cleanup.success {
    raise @workspace.Rejected("controlled cleanup failure")
  }
}

///|
fn Runtime::execution_request(
  self : Runtime,
  service : ControlledExecutions,
  operation : String,
  payload : Json,
) -> Bytes {
  self.log({
    "event": "executions.request",
    "session": self.aliases.session(service.session),
    "operation": operation,
    "payload": canonical(self.aliases.execution_value(payload)),
  })
  if service.closed {
    return @reply.failure(@reply.Unavailable, @reply.NoEffect)
  }
  let path = match operation {
    "execution.submit" => "submit"
    "execution.query" => "query"
    "execution.cancel" => "cancel"
    "execution.release" => "release"
    _ => return @reply.failure(@reply.InvalidRequest, @reply.NoEffect)
  }
  if self.contract == @request.CapabilityChecks {
    return self.policy_execution_request(service, operation, payload, path)
  }
  try {
    let result = service.host.handle(
      ({ "op": path, "body": payload.stringify() } : Json).stringify(),
    )
    if field(result, "ok") == Json::boolean(false) {
      return @reply.failure(
        @native.native_code(text(field(result, "code"))),
        @reply.NoEffect,
      )
    }
    let value = field(result, "value")
    if path == "submit" {
      let identity = field(value, "identity")
      let normalized = self.aliases.identity(identity)
      let claim = service.host.handle(
        ({ "op": "claim", "identity": identity } : Json).stringify(),
      )
      guard field(claim, "ok") == Json::boolean(true) &&
        field(claim, "value") is Object(request) else {
        abort("native owner MCK: submitted execution could not be claimed")
      }
      let request = request.copy()
      // Production emits model JSON as opaque source text. This diagnostic
      // projection excludes that one field instead of freezing its serializer.
      request.remove("source")
      self.log({
        "event": "executions.claim",
        "session": self.aliases.session(service.session),
        "execution": field(normalized, "executionId"),
        "request": canonical(Json::object(request)),
      })
    }
    @reply.success(operation, value)
  } catch {
    _ => @reply.failure(@reply.Unavailable, @reply.UnknownEffect)
  }
}

///|
fn Runtime::complete(
  self : Runtime,
  execution_name : String,
  outcomes : Json,
) -> Json {
  guard execution_name.has_prefix("execution-") &&
    self.aliases.reverse.get(execution_name) is Some(identity) &&
    self.services.get(host_scope(identity)) is Some(service) else {
    return Json::string("unavailable")
  }
  let result = service.host.handle(
    ({ "op": "complete", "identity": identity, "outcomes": outcomes } : Json).stringify(),
  )
  guard result is Object(fields) else {
    abort("native owner MCK: invalid Host completion")
  }
  let fields = fields.copy()
  if fields.get("value") is Some(value) {
    fields["value"] = self.aliases.execution_value(value)
  }
  Json::string(canonical(Json::object(fields)))
}
