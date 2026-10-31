///|
test "stderr buffer keeps every byte below the tail size" {
  let buffer = @process.StderrBuffer::new()
  buffer..write(b"warning: one\n").write(b"warning: two\n")
  assert_eq(buffer.tail().bytes(), b"warning: one\nwarning: two\n")
  assert_false(buffer.tail().truncated())
}

///|
test "stderr buffer keeps the last 64 KiB of a noisy worker" {
  let buffer = @process.StderrBuffer::new()
  let chunk = Bytes::make(4096, b'a')
  for _ in 0..<2560 {
    buffer.write(chunk)
  }
  buffer.write(b"last line\n")
  let tail = buffer.tail().bytes()
  assert_eq(tail.length(), 65536)
  assert_eq(tail[65526:].to_owned(), b"last line\n")
  assert_true(buffer.tail().truncated())
}

///|
test "stderr buffer is not truncated at exactly 64 KiB" {
  let buffer = @process.StderrBuffer::new()
  buffer.write(Bytes::make(65536, b'x'))
  assert_eq(buffer.tail().bytes().length(), 65536)
  assert_false(buffer.tail().truncated())
  buffer.write(b"y")
  assert_true(buffer.tail().truncated())
}

///|
test "stderr buffer keeps the end of one chunk larger than the tail" {
  let buffer = @process.StderrBuffer::new()
  let large = Bytes::makei(70000, i => (i % 251).to_byte())
  buffer.write(large)
  assert_eq(buffer.tail().bytes(), large[70000 - 65536:].to_owned())
  assert_true(buffer.tail().truncated())
}
