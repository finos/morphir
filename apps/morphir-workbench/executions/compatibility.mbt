///|
pub using @shared {
  type Host,
  type SchemeSelection,
  type Invalid,
  decode,
  decode_reply,
}

///|
/// Preserve Workbench presentation while the shared cursor owns evidence.
pub struct Client {
  priv inner : @shared.Client
}

///|
fn project(value : Json) -> Json {
  @outcomes.prepare(value, expected_ids=Some(["workbench"])).0
}

///|
pub fn Client::new() -> Client {
  { inner: @shared.Client::new(project_result=project), }
}

///|
pub fn Client::handle(self : Client, source : String) -> Json {
  self.inner.handle(source)
}

///|
pub fn evaluate_scheme_claim(request : Json) -> Json raise {
  @shared.evaluate_scheme_claim(request, project_result=project)
}
