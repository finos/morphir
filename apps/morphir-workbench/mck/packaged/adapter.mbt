///|
extern "wasm" fn input_len() -> Int32 = "morphir_bytes_v1" "input_len"

///|
extern "wasm" fn input_byte(index : Int32) -> Int32 = "morphir_bytes_v1" "input_byte"

///|
extern "wasm" fn output_byte(value : Int32) -> Unit = "morphir_bytes_v1" "output_byte"

///|
/// Local core-Wasm byte ABI: 0 means exit, a positive result is the exact
/// response byte length, -1 means infrastructure failure. No pointers escape.
pub fn handle() -> Int32 {
  let size = input_len()
  if size < 0 || size > 3146752 {
    return -1
  }
  let bytes : Array[Byte] = []
  for i in 0..<size {
    let value = input_byte(i)
    if value < 0 || value > 255 {
      return -1
    }
    bytes.push(value.to_byte())
  }
  try {
    let source = @utf8.decode(Bytes::from_array(bytes)[:])
    guard @mck.handle_line(source) is Some(response) else { return 0 }
    let output = @utf8.encode(response.stringify())
    if output.length() == 0 || output.length() > 2097152 {
      return -1
    }
    for byte in output {
      output_byte(byte.to_int())
    }
    output.length()
  } catch {
    _ => -1
  }
}
