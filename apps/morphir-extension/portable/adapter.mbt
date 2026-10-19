///|
extern "wasm" fn input_len() -> Int32 = "morphir_bytes_v1" "input_len"

///|
extern "wasm" fn input_byte(index : Int32) -> Int32 = "morphir_bytes_v1" "input_byte"

///|
extern "wasm" fn output_byte(value : Int32) -> Unit = "morphir_bytes_v1" "output_byte"

///|
let session : @mep.Session = @mep.Session::new(
  frontend=Some(@frontend.provider()),
)

///|
/// One persistent MEP session per instance. The existing protocol core owns
/// negotiation, model validation and lifecycle. Only bytes cross this facade.
pub fn handle() -> Int32 {
  let size = input_len()
  if size < 0 || size > @mep.MAX_FRAME_BYTES || session.exited() {
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
  match session.receive(Bytes::from_array(bytes)) {
    None => if session.exited() { 0 } else { -2 }
    Some(response) => {
      let output = @utf8.encode(response.stringify())
      if output.length() == 0 || output.length() > @mep.MAX_FRAME_BYTES {
        return -1
      }
      for byte in output {
        output_byte(byte.to_int())
      }
      output.length()
    }
  }
}
