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

///|
/// A protocol helper that receives the selected cancel file can reclaim its
/// own children before the process adapter escalates. Nested scopes restore
/// the enclosing delivery policy and never create another cancellation state.
pub struct CooperativeProcessScope {
  priv previous : (() -> Bool)?
  priv mut open : Bool
}

///|
let cooperative_process_stop : Ref[(() -> Bool)?] = Ref(None)

///|
pub fn CooperativeProcessScope::install(
  ready : () -> Bool,
) -> CooperativeProcessScope {
  let previous = cooperative_process_stop.val
  cooperative_process_stop.val = Some(ready)
  { previous, open: true, }
}

///|
pub fn CooperativeProcessScope::close(self : CooperativeProcessScope) -> Unit {
  if self.open {
    self.open = false
    cooperative_process_stop.val = self.previous
  }
}

///|
#cfg(any(target="js", target="native"))
priv enum ProcessStopDelivery {
  Running
  Signal
  Cooperative
}

///|
#cfg(any(target="js", target="native"))
fn process_stop_delivery() -> ProcessStopDelivery {
  if !interruption_requested() {
    return Running
  }
  match cooperative_process_stop.val {
    Some(ready) if ready() => Cooperative
    _ => Signal
  }
}

///|
/// Private native/worker adapter encoding; process result payloads stay intact.
#cfg(any(target="js", target="native"))
fn process_stop_code() -> Int32 {
  match process_stop_delivery() {
    Running => 0
    Signal => 1
    Cooperative => 2
  }
}
