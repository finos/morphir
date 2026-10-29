///|
#cfg(target="native")
fn process_result(code : Int32, output : String, error : String) -> Json {
  Json::object(
    Map::from_array([
      ("exitCode", Json::number(code.to_double())),
      ("stdout", Json::string(output)),
      ("stderr", Json::string(error)),
    ]),
  )
}

///|
let process_observer : Ref[((String) -> Unit)?] = Ref(None)

///|
/// Observe launches owned by this process. Nested scopes close in reverse order.
pub struct ProcessScope {
  priv previous : ((String) -> Unit)?
  priv mut open : Bool
}

///|
pub fn ProcessScope::install(started : (String) -> Unit) -> ProcessScope {
  let previous = process_observer.val
  process_observer.val = Some(started)
  { previous, open: true, }
}

///|
pub fn ProcessScope::close(self : ProcessScope) -> Unit {
  if self.open {
    self.open = false
    process_observer.val = self.previous
  }
}

///|
/// A local JS helper can announce an owned child without changing its payloads.
pub fn process_started(program : String) -> Unit {
  if process_observer.val is Some(observe) {
    observe(program)
  }
}
