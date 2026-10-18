///|
extern "wasm" fn response_bytes(size : Int32) -> Unit = "morphir_diagnostics_v1" "response_bytes"

///|
pub fn handle() -> Int32 {
  let result = @packaged.handle()
  if result > 0 {
    response_bytes(result)
  }
  result
}
