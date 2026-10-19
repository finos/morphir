///|
#cfg(any(target="native", target="js"))
test "bounded command input preserves arbitrary bytes and rejects oversized files" {
  let root = @platform.temporary()
  defer @platform.remove_dir(root)
  let path = root + "/source"
  defer @platform.remove_file(path)
  let bytes = b"\x00\xff\r\n\xf0\x9f\x98\x80"
  @platform.write_bytes(path, bytes)
  assert_eq(@platform.read_input(path, bytes.length()), bytes)
  for limit in [0, bytes.length() - 1, 16777217] {
    let rejected = try {
      ignore(@platform.read_input(path, limit))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  let rejected = try {
    ignore(@platform.read_input(root, 1024))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
