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
  Active(String, String)
  Closed
}

///|
pub struct Session {
  priv mut state : State
  priv mut next : Int32
}

///|
pub fn Session::new() -> Session {
  { state: Idle, next: 0, }
}

///|
fn descriptor(id : String) -> Json {
  {
    "ok": true,
    "bridgeVersion": "0.1.0-draft.1",
    "sessionId": id,
    "operations": [],
  }
}

///|
/// Bootstrap identities are not credentials. Native caller context is required
/// on every command. No job, filesystem or public native profile is offered.
pub fn Session::open(
  self : Session,
  caller : Caller,
  version : String,
) -> Json raise Invalid {
  guard version == "0.1.0-draft.1" else {
    raise Rejected("workbench.native_version")
  }
  match self.state {
    Closed => raise Rejected("workbench.native_closed")
    Active(page, id) if page == caller.page => return descriptor(id)
    _ => ()
  }
  guard self.next < 2147483647 else {
    raise Rejected("workbench.native_capacity")
  }
  self.next += 1
  let id = "proton-session-" + self.next.to_string()
  self.state = Active(caller.page, id)
  descriptor(id)
}

///|
pub fn Session::check(
  self : Session,
  caller : Caller,
  id : String,
) -> Json raise Invalid {
  guard self.state is Active(page, current) &&
    page == caller.page &&
    current == id else {
    raise Rejected("workbench.native_stale_session")
  }
  descriptor(current)
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
