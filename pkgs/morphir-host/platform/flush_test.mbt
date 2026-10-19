///|
#cfg(target="js")
test "local flush rejects a FIFO and remains deadline bounded" {
  if @platform.system_type() == "windows" {
    return
  }
  let root = @platform.temporary()
  let fifo = root + "/blocked"
  ignore(@platform.process("mkfifo", [fifo], root, "", 1000))
  let rejected = try {
    ignore(@platform.read_bytes(fifo))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  let start = @platform.monotonic_seconds()
  assert_false(@platform.flush_file(fifo, b"record", 50))
  assert_true(@platform.monotonic_seconds() - start < 1.0)
  @platform.remove_file(fifo)
  @platform.remove_dir(root)
}

///|
#cfg(any(target="js", target="native"))
test "local flush owns complete snapshots and rotates three files" {
  // Do not depend on the process/temp capability: native Windows supports
  // local generation and its sink without a build process provider.
  let root = @platform.cwd() + "/morphir-log-" + @platform.observation_id()
  @platform.mkdir(root)
  defer @platform.remove_dir(root)
  let logs = root + "/.morphir/logs"
  let path = logs + "/execution.ionb"
  assert_true(
    @platform.flush_file(path, b"\xe0\x01\x00\xea first", 1000, root~),
  )
  defer {
    for suffix in ["", ".1", ".2", ".3"] {
      if @platform.kind(path + suffix) == 1 {
        @platform.remove_file(path + suffix)
      }
    }
    @platform.remove_dir(logs)
    @platform.remove_dir(root + "/.morphir")
  }
  for index, value in [b"second", b"third", b"fourth", b"fifth"] {
    assert_true(@platform.flush_file(path, value, 1000, root~))
    assert_eq(@platform.read_bytes(path), value)
    if index == 0 {
      assert_eq(@platform.read_bytes(path + ".1"), b"\xe0\x01\x00\xea first")
    }
  }
  assert_eq(@platform.read_bytes(path + ".1"), b"fourth")
  assert_eq(@platform.read_bytes(path + ".2"), b"third")
  assert_eq(@platform.read_bytes(path + ".3"), b"second")
  assert_eq(@platform.kind(path + ".4"), 0)
  for timeout in [0, 5001] {
    assert_false(@platform.flush_file(path, b"rejected", timeout, root~))
  }
  assert_false(
    @platform.flush_file(path, Bytes::make(4194305, b'x'), 1000, root~),
  )
  assert_eq(@platform.read_bytes(path), b"fifth")
  // A non-file rotation target must refuse before replacing the active batch.
  @platform.remove_file(path + ".3")
  @platform.mkdir(path + ".3")
  assert_false(@platform.flush_file(path, b"rejected", 1000, root~))
  assert_eq(@platform.read_bytes(path), b"fifth")
  @platform.remove_dir(path + ".3")
}
