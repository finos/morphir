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
  priv jobs : Bool
  priv workspace : Bool
}

///|
pub fn Session::new(jobs~ : Bool = false, workspace~ : Bool = false) -> Session {
  { state: Idle, next: 0, jobs, workspace, }
}

///|
fn Session::descriptor(self : Session, id : String) -> Json {
  let operations : Array[Json] = []
  if self.jobs {
    operations.push(Json::string("jobs"))
  }
  if self.workspace {
    operations.push(Json::string("workspace"))
  }
  {
    "ok": true,
    "bridgeVersion": "0.1.0-draft.1",
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
  guard version == "0.1.0-draft.1" else {
    raise Rejected("workbench.native_version")
  }
  match self.state {
    Closed => raise Rejected("workbench.native_closed")
    Active(page, id) if page == caller.page => return self.descriptor(id)
    _ => ()
  }
  guard self.next < 2147483647 else {
    raise Rejected("workbench.native_capacity")
  }
  self.next += 1
  let id = "proton-session-" + self.next.to_string()
  self.state = Active(caller.page, id)
  self.descriptor(id)
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
  self.descriptor(current)
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
