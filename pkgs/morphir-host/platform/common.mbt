///|
pub(all) suberror IOError {
  IOError(String)
}

///|
#cfg(any(target="wasm", target="wasm-gc"))
pub fn rename_directory_new(_a : String, _b : String) -> Unit raise {
  raise IOError("publication.create_unavailable")
}

///|
#cfg(not(target="wasm-gc"))
fn check(code : Int32, operation : String) -> Unit raise {
  if code != 0 {
    raise IOError(operation + ": host error " + code.to_string())
  }
}

///|
#cfg(not(target="wasm-gc"))
pub fn bytes_supported() -> Bool {
  true
}

///|
#cfg(any(target="wasm", target="wasm-gc"))
pub fn file_chunks(
  _path : String,
  _limit : Int32,
  _consume : (Bytes) -> Unit raise,
) -> Unit raise {
  raise IOError(
    "metadata.restore_runtime_unavailable: executable pin reads are not qualified on this runtime",
  )
}

///|
#cfg(any(target="wasm", target="wasm-gc"))
pub fn file_chunks_supported() -> Bool {
  false
}
