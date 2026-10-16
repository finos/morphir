///|
test "native frames bound lengths before allocating payloads" {
  assert_eq(frame_length(b"\x00\x00\x00\x01"), 1)
  assert_eq(frame_length(b"\x00\x10\x00\x00"), 1048576)
  for
    bytes in [
      b"", b"\x00\x00\x00\x00", b"\x00\x10\x00\x01", b"\xff\xff\xff\xff",
    ] {
    let rejected = try {
      ignore(frame_length(bytes))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  assert_eq(frame("42"), b"\x00\x00\x00\x0242")
}

///|
test "native bridge validates closed raw envelopes and rejects duplicate keys" {
  assert_eq(
    bridge_request("{\"sessionId\":\"s\",\"path\":\"session\",\"body\":null}"),
    ("s", "session", None),
  )
  for
    source in [
      "{\"sessionId\":\"s\",\"sessionId\":\"s\",\"path\":\"session\",\"body\":null}",
      "{\"sessionId\":\"s\",\"path\":\"session\",\"body\":null,\"extra\":true}",
      "{\"sessionId\":\"s\",\"path\":\"session\",\"body\":{}}",
    ] {
    let rejected = try {
      ignore(bridge_request(source))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "native memory observation measures the running process" {
  assert_true(rss(pid()) > 0.0)
  let start = now()
  assert_true(now() >= start)
}
