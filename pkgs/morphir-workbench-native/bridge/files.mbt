///|
/// A routing hint only. FileOwner independently decodes the complete frame.
pub fn is_file_request(source : String) -> Bool {
  if source.length() > @filewire.FRAME_LIMIT {
    return false
  }
  try {
    let value = @wire.parse_bounded(
      source,
      max_depth=16,
      max_nodes=1024,
      max_string_units=@filewire.FRAME_LIMIT,
    )
    value is Object(fields) &&
    fields.get("profile") == Some(Json::string(@filewire.PROFILE))
  } catch {
    _ => false
  }
}

///|
pub struct FileOwner {
  priv session : @session.Session
  priv services : Map[String, @workspace.FileService]
  priv enabled : Bool
}

///|
pub fn FileOwner::new(enabled~ : Bool) -> FileOwner {
  { session: @session.Session::new(), services: Map([]), enabled, }
}

///|
pub fn FileOwner::revoke(self : FileOwner) -> Unit {
  self.session.revoke()
  for _, service in self.services {
    service.close()
  }
  self.services.clear()
}

///|
pub fn FileOwner::close(self : FileOwner) -> Unit {
  self.revoke()
  self.session.shutdown()
}

///|
pub async fn FileOwner::request(
  self : FileOwner,
  source : String,
  caller : () -> @session.Caller raise,
  choose : async () -> String?,
) -> String {
  let request = @filewire.decode_request(@utf8.encode(source))
  try {
    guard self.enabled else {
      raise @session.Rejected("workbench.workspace_unavailable")
    }
    let current = caller()
    guard request.session_id() is Some(id) else {
      let value = self.session.open(current, @request.Executions.version())
      let id = @filewire.SessionId::parse(text(value, "sessionId"))
      for (old, service) in self.services.to_array() {
        if old != id.to_string() {
          service.close()
          self.services.remove(old)
        }
      }
      if !self.services.contains(id.to_string()) {
        self.services[id.to_string()] = @workspace.FileService::new()
      }
      return raw(@filewire.success(request, id, @filewire.descriptor()))
    }
    ignore(self.session.check(current, id.to_string()))
    guard self.services.get(id.to_string()) is Some(service) &&
      request.command() is Some(command) else {
      raise @session.Rejected("workbench.workspace_unavailable")
    }
    let value = match command {
      CheckSession => @filewire.descriptor()
      CloseSession => {
        ignore(self.session.close(current, id.to_string()))
        service.close()
        self.services.remove(id.to_string())
        {}
      }
      CancelPicker => {
        service.cancel_choose()
        {}
      }
      ChooseWrite => {
        let ticket = service.begin_choose()
        errdefer service.cancel_choose(ticket=Some(ticket))
        let path = choose()
        // Read trusted native context after the OS dialog yields. A cancelled
        // or superseded page must never turn a delayed result into authority.
        ignore(self.session.check(caller(), id.to_string()))
        service.finish_choose(ticket, path)
      }
      _ => service.request(command)
    }
    raw(@filewire.success(request, id, value))
  } catch {
    error => {
      let reason = match error {
        @session.Rejected(code) =>
          @filewire.Denied(
            code, "The native file session is unavailable or no longer current.",
          )
        _ => @workspace.file_failure(error)
      }
      raw(@filewire.failure(request, reason))
    }
  }
}
