///|
// The stock moonrun test loader does not supply morphir_host_v1. Test the pure
// request boundary here; actual GC host enumeration is exercised by CLI tests.
#cfg(target="wasm-gc")
test "bounded directory requests validate before the GC host boundary" {
  for (path, limit) in [("ignored", -1), ("ignored", 65537), ("a\u0000b", 1)] {
    let rejected = try {
      directory_request(path, limit)
      false
    } catch {
      IOError("directory.invalid_request") => true
      _ => false
    }
    assert_true(rejected)
  }
}
