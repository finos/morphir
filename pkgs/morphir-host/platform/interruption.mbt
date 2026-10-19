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
pub fn interruption_requested() -> Bool {
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
