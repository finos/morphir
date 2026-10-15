///|
#cfg(any(target="native", target="js"))
test "bounded file chunks preserve bytes and reject oversized or unsupported inputs" {
  let root = @platform.temporary()
  defer @platform.remove_dir(root)
  let path = root + "/binary"
  let original = Bytes::from_array(
    Array::makei(196613, i => (i % 256).to_byte()),
  )
  @platform.write_bytes(path, original)
  defer @platform.remove_file(path)
  let collected : Array[Bytes] = []
  @platform.file_chunks(path, 200000, chunk => collected.push(chunk))
  assert_true(collected.length() > 1)
  assert_true(
    collected.all(chunk => chunk.length() > 0 && chunk.length() <= 65536),
  )
  assert_eq(
    Bytes::from_array(
      collected.iter().flat_map(chunk => chunk.iter()).collect(),
    ),
    original,
  )
  let reads = Ref(0)
  for
    (selected, limit) in [
      (path, 196612),
      (root, 200000),
      (root + "/missing", 200000),
    ] {
    let refused = try {
      @platform.file_chunks(selected, limit, fn(_) { reads.val += 1 })
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
  assert_eq(reads.val, 0)
  let interrupted = try {
    @platform.file_chunks(path, 200000, fn(_) raise {
      raise @platform.IOError("consumer stopped")
    })
    false
  } catch {
    @platform.IOError(message) => message == "consumer stopped"
    _ => false
  }
  assert_true(interrupted)
}

///|
#cfg(any(target="wasm", target="wasm-gc"))
test "unqualified pin reads refuse without invoking consumers" {
  assert_false(@platform.file_chunks_supported())
  let called = Ref(false)
  let refused = try {
    @platform.file_chunks("/ignored", 1, fn(_) { called.val = true })
    false
  } catch {
    @platform.IOError(message) =>
      message.has_prefix("metadata.restore_runtime_unavailable")
    _ => false
  }
  assert_true(refused)
  assert_false(called.val)
}
