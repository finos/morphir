///|
#cfg(target="wasm-gc")
pub fn monotonic_seconds() -> Double {
  let response = call("monotonic_seconds") catch { _ => Json::number(0.0) }
  match response {
    Number(value, ..) => value
    _ => 0.0
  }
}

///|
pub fn wall_seconds() -> Double {
  0.0
}

///|
pub fn observation_id() -> String raise {
  raise IOError("observability.clock_capability_required")
}

///|
pub fn flush_file(
  _path : String,
  _data : Bytes,
  _timeout : Int32,
  root~ : String = "",
) -> Bool {
  ignore(root)
  false
}
