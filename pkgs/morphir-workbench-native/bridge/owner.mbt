///|
/// Trusted host wiring for an owned execution service. These callbacks cannot be
/// constructed or selected by renderer requests.
pub(all) struct ExecutionsService {
  offer : () -> Json raise
  request : (String, Json) -> Bytes
  close : () -> Unit
  shutdown : async () -> Unit
}

///|
/// A present factory enables the corresponding capability. The owner publishes
/// it only after construction and awaited predecessor cleanup succeed.
pub(all) struct ServiceFactories {
  executions : ((String, @request.Contract) -> ExecutionsService raise)?
  workspace : (() -> @workspace.Service)?
}

///|
/// The embedding host supplies caller context, executable and native picker.
/// Renderer input never supplies any of these authorities.
pub struct Owner {
  priv session : @session.Session
  priv group : @async.TaskGroup[Unit]
  priv factories : ServiceFactories
  priv services : Map[String, ExecutionsService]
  priv workspaces : Map[String, @workspace.Service]
  priv mut cleanup_failed : Bool
}

///|
pub fn Owner::new(
  group : @async.TaskGroup[Unit],
  executable : String,
  executions~ : Bool,
  workspace~ : Bool,
  contract~ : @request.Contract = Executions,
) -> Owner {
  let execution_factory : ((String, @request.Contract) -> ExecutionsService raise)? = if executions {
    Some(fn(id, selected_contract) raise {
      let service = @native.Service::new(group, executable, id)
      {
        offer: fn() { service.offer() },
        request: fn(operation, payload) {
          match selected_contract {
            Executions => service.native_request(operation, payload)
            CapabilityChecks =>
              service.native_policy_request(operation, payload)
          }
        },
        close: fn() { service.close() },
        shutdown: async fn() { service.shutdown() },
      }
    })
  } else {
    None
  }
  let workspace_factory : (() -> @workspace.Service)? = if workspace {
    Some(fn() { @workspace.Service::new() })
  } else {
    None
  }
  Owner::with_services(
    group,
    { executions: execution_factory, workspace: workspace_factory, },
    contract~,
  )
}

///|
/// Native host composition point. Capability factories and their resources are
/// trusted dependencies; they never come from the native wire envelope.
pub fn Owner::with_services(
  group : @async.TaskGroup[Unit],
  factories : ServiceFactories,
  contract~ : @request.Contract = Executions,
) -> Owner {
  {
    session: @session.Session::new(
      executions=factories.executions is Some(_),
      workspace=factories.workspace is Some(_),
      contract~,
    ),
    group,
    factories,
    services: Map([]),
    workspaces: Map([]),
    cleanup_failed: false,
  }
}

///|
fn text(value : Json, key : String) -> String raise {
  guard value is Object(fields) && fields.get(key) is Some(String(value)) else {
    raise @session.Rejected("workbench.native_shape")
  }
  value
}

///|
fn raw(bytes : Bytes) -> String {
  @utf8.decode(bytes) catch {
    _ => abort("Encoded native reply")
  }
}

///|
fn Owner::descriptor(
  self : Owner,
  id : String,
  contract : @request.Contract,
) -> Json raise {
  let operations : Array[Json] = []
  let fields : Map[String, Json] = {
    "profile": "morphir/workbench/native",
    "contractVersion": contract.version(),
    "sessionId": Json::string(id),
    "operations": Json::array(operations),
  }
  if self.factories.executions is Some(_) {
    guard self.services.get(id) is Some(service) else {
      raise @session.Rejected("workbench.native_executions_unavailable")
    }
    operations.push(Json::string("executions"))
    fields["offer"] = (service.offer)()
    if contract is CapabilityChecks {
      fields["capabilityChecks"] = @reply.policy_offer()
    }
  }
  if self.factories.workspace is Some(_) {
    guard self.workspaces.contains(id) else {
      raise @session.Rejected("workbench.workspace_unavailable")
    }
    operations.push(Json::string("workspace"))
  }
  Json::object(fields)
}

///|
/// Invoked for each originating command. The caller callback must read trusted
/// native context again after an await, never reuse renderer-supplied authority.
pub async fn Owner::request(
  self : Owner,
  source : String,
  caller : () -> @session.Caller raise,
  choose : async () -> String?,
) -> String {
  let mut effect = @reply.NoEffect
  let mut category = @reply.InvalidRequest
  try {
    guard source.length() <= 1048576 else {
      return raw(@reply.failure(@reply.Limit, effect))
    }
    let frame = @request.decode_current(@utf8.encode(source))
    let contract = frame.contract()
    fn success(operation : String, value : Json) -> String raise {
      raw(
        match contract {
          Executions => @reply.success(operation, value)
          CapabilityChecks => @reply.success_policy(operation, value)
        },
      )
    }
    let value = frame.to_json()
    let operation = frame.operation()
    category = @reply.Unauthorized
    let current = caller()
    if operation == "session.open" {
      // Opening can replace a previous page and invalidate its authority.
      effect = @reply.UnknownEffect
      let id = text(self.session.open(current, contract.version()), "sessionId")
      for (old_id, old) in self.workspaces.to_array() {
        if old_id != id {
          old.close()
          self.workspaces.remove(old_id)
        }
      }
      category = @reply.Unavailable
      for (old_id, old) in self.services.to_array() {
        if old_id != id {
          (old.shutdown)()
          self.services.remove(old_id)
        }
      }
      guard !self.cleanup_failed else {
        raise @session.Rejected("workbench.native_cleanup")
      }
      // Shutdown can yield while a replacement page opens. Re-admit both the
      // current trusted page and this original session before creating services.
      category = @reply.Unauthorized
      ignore(self.session.check(caller(), id, contract=Some(contract)))
      category = @reply.Unavailable
      if self.factories.executions is Some(factory) &&
        !self.services.contains(id) {
        self.services[id] = factory(id, contract)
      }
      if self.factories.workspace is Some(factory) &&
        !self.workspaces.contains(id) {
        self.workspaces[id] = factory()
      }
      return success(operation, self.descriptor(id, contract))
    }
    let id = text(value, "sessionId")
    ignore(self.session.check(current, id, contract=Some(contract)))
    if operation == "session.check" {
      category = @reply.Unavailable
      return success(operation, self.descriptor(id, contract))
    }
    if operation == "session.close" {
      effect = @reply.UnknownEffect
      ignore(self.session.close(current, id))
      if self.workspaces.get(id) is Some(service) {
        service.close()
        self.workspaces.remove(id)
      }
      category = @reply.Unavailable
      if self.services.get(id) is Some(service) {
        (service.shutdown)()
        self.services.remove(id)
      }
      return success(operation, {})
    }
    category = @reply.Unavailable
    guard value is Object(fields) else { abort("Admitted native request") }
    let payload = fields.get("payload").unwrap_or({})
    if operation.has_prefix("execution.") {
      guard self.services.get(id) is Some(service) else {
        return raw(@reply.failure(category, effect))
      }
      return raw((service.request)(operation, payload))
    }
    guard self.workspaces.get(id) is Some(service) else {
      return raw(@reply.failure(category, effect))
    }
    if operation == "workspace.choose" {
      category = @reply.Conflict
      // A rejected busy picker has not changed owner state.
      let ticket = service.begin_choose()
      effect = @reply.UnknownEffect
      errdefer service.cancel_choose_if_current(ticket)
      category = @reply.Unavailable
      let path = choose()
      category = @reply.Unauthorized
      ignore(self.session.check(caller(), id, contract=Some(contract)))
      category = @reply.Conflict
      guard service.finish_choose(ticket, path) is Object(result) else {
        abort("Workspace picker result")
      }
      result.remove("ok")
      return success(operation, Json::object(result))
    }
    raw(service.native_request(operation, payload))
  } catch {
    _ => raw(@reply.failure(category, effect))
  }
}

///|
pub fn Owner::revoke(self : Owner) -> Unit {
  self.session.revoke()
  for (_, service) in self.workspaces.to_array() {
    service.close()
  }
  self.workspaces.clear()
  for (id, service) in self.services.to_array() {
    (service.close)()
    self.group.spawn_bg(async fn() {
      try {
        (service.shutdown)()
        self.services.remove(id)
      } catch {
        _ => self.cleanup_failed = true
      }
    })
  }
}

///|
/// A closed main window cannot open another page session.
pub fn Owner::close(self : Owner) -> Unit {
  self.revoke()
  self.session.shutdown()
}

///|
pub async fn Owner::shutdown(self : Owner) -> Unit {
  self.session.shutdown()
  for (_, service) in self.workspaces.to_array() {
    service.close()
  }
  self.workspaces.clear()
  for (id, service) in self.services.to_array() {
    (service.shutdown)()
    self.services.remove(id)
  }
  self.cleanup_failed = false
}
