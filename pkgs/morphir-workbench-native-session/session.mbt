///|
pub(all) suberror Invalid {
  Rejected(String)
}

///|
/// Constructed only from Proton's native request context, never renderer data.
pub struct Caller {
  priv page : String
}

///|
pub fn Caller::admit(
  window : String,
  origin : String,
  page : String?,
) -> Caller raise Invalid {
  guard window == "main" && origin == "app" else {
    raise Rejected("workbench.native_caller")
  }
  guard page is Some(page) && !page.is_empty() && page.length() <= 128 else {
    raise Rejected("workbench.native_page")
  }
  { page, }
}

///|
enum State {
  Idle
  Active(String, String, @request.Contract)
  Closed
}

///|
pub struct Session {
  priv mut state : State
  priv mut next : Int32
  priv executions : Bool
  priv workspace : Bool
  priv contract : @request.Contract
}

///|
pub fn Session::new(
  executions~ : Bool = false,
  workspace~ : Bool = false,
  contract~ : @request.Contract = Executions,
) -> Session {
  { state: Idle, next: 0, executions, workspace, contract, }
}

///|
fn Session::descriptor(
  self : Session,
  id : String,
  contract : @request.Contract,
) -> Json {
  let operations : Array[Json] = []
  if self.executions {
    operations.push(Json::string("executions"))
  }
  if self.workspace {
    operations.push(Json::string("workspace"))
  }
  {
    "ok": true,
    "bridgeVersion": contract.version(),
    "sessionId": id,
    "operations": Json::array(operations),
  }
}

///|
/// Bootstrap identities are not credentials. Native caller context is required
/// on every command. Operations come from qualified host configuration. The
/// private bootstrap does not claim the proposed public native profile.
pub fn Session::open(
  self : Session,
  caller : Caller,
  version : String,
) -> Json raise Invalid {
  let contract = @request.Contract::from_string(version) catch {
    _ => raise Rejected("workbench.native_version")
  }
  guard contract == @request.Executions || self.contract == contract else {
    raise Rejected("workbench.native_version")
  }
  match self.state {
    Closed => raise Rejected("workbench.native_closed")
    Active(page, id, accepted) if page == caller.page => {
      guard accepted == contract else {
        raise Rejected("workbench.native_version")
      }
      return self.descriptor(id, accepted)
    }
    _ => ()
  }
  guard self.next < 2147483647 else {
    raise Rejected("workbench.native_capacity")
  }
  self.next += 1
  let id = "proton-session-" + self.next.to_string()
  self.state = Active(caller.page, id, contract)
  self.descriptor(id, contract)
}

///|
pub fn Session::check(
  self : Session,
  caller : Caller,
  id : String,
  contract~ : @request.Contract? = None,
) -> Json raise Invalid {
  guard self.state is Active(page, current, accepted) &&
    page == caller.page &&
    current == id &&
    (contract is None || contract == Some(accepted)) else {
    raise Rejected("workbench.native_stale_session")
  }
  self.descriptor(current, accepted)
}

///|
pub fn Session::close(
  self : Session,
  caller : Caller,
  id : String,
) -> Json raise Invalid {
  ignore(self.check(caller, id))
  self.state = Idle
  { "ok": true }
}

///|
pub fn Session::revoke(self : Session) -> Unit {
  match self.state {
    Closed => ()
    _ => self.state = Idle
  }
}

///|
pub fn Session::shutdown(self : Session) -> Unit {
  self.state = Closed
}

///|
pub fn failure(error : Error) -> Json {
  let code = match error {
    Rejected(code) => code
    _ => "workbench.native_session"
  }
  { "ok": false, "code": code }
}
