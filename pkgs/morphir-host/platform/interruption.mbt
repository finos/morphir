///|
/// One command owns the interruption handler between start and stop. Embedders
/// may supply the JS shared flag without installing a process handler here.
#cfg(any(target="wasm", target="wasm-gc"))
pub fn interruption_start() -> Unit {
  ()
}

///|
#cfg(any(target="wasm", target="wasm-gc"))
pub fn interruption_stop() -> Unit {
  ()
}

///|
#cfg(target="wasm")
fn raw_interruption_requested() -> Bool {
  false
}

///|
#cfg(target="wasm")
pub fn interruption_supported() -> Bool {
  false
}

///|
#cfg(any(target="native", target="js"))
pub fn interruption_supported() -> Bool {
  true
}

///|
let hosted_interruption : Ref[(() -> Bool)?] = Ref(None)

///|
/// A process owner may bind its cooperative cancellation state for the whole
/// run. Scopes must close in reverse installation order; close is idempotent.
/// Native adapters call this probe from their bounded synchronous waits too.
pub struct InterruptionScope {
  previous : (() -> Bool)?
  mut open : Bool
}

///|
pub fn InterruptionScope::install(probe : () -> Bool) -> InterruptionScope {
  let previous = hosted_interruption.val
  hosted_interruption.val = Some(probe)
  { previous, open: true, }
}

///|
pub fn InterruptionScope::close(self : InterruptionScope) -> Unit {
  if self.open {
    self.open = false
    hosted_interruption.val = self.previous
  }
}

///|
pub fn interruption_requested() -> Bool {
  match hosted_interruption.val {
    Some(probe) => probe()
    None => raw_interruption_requested()
  }
}

///|
#cfg(target="native")
pub fn interruption_start() -> Unit {
  if hosted_interruption.val is None {
    raw_interruption_start()
  }
}

///|
#cfg(target="native")
pub fn interruption_stop() -> Unit {
  if hosted_interruption.val is None {
    raw_interruption_stop()
  }
}
