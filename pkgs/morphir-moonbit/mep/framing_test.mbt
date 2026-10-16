///|
test "framing handles every split of unicode bytes and multiple coalesced frames" {
  let body = "{\"text\":\"λ😀\"}"
  let bytes = @mep.encode_frame(body)
  assert_eq(bytes[:22].to_owned(), b"Content-Length: 17\r\n\r\n")
  for split = 0; split <= bytes.length(); split = split + 1 {
    let decoder = @mep.Decoder::new()
    let frames = decoder.feed(bytes[:split].to_owned()) catch {
      @mep.InvalidFrame(message) => fail(message)
      error => raise error
    }
    frames.append(
      decoder.feed(bytes[split:].to_owned()) catch {
        @mep.InvalidFrame(message) => fail(message)
        error => raise error
      },
    )
    decoder.finish()
    assert_eq(frames, [@utf8.encode(body)])
  }
  let decoder = @mep.Decoder::new()
  let buffer = @buffer.Buffer::Buffer()
  buffer.write_bytes(bytes[:])
  buffer.write_bytes(bytes[:])
  assert_eq(decoder.feed(buffer.to_bytes()).length(), 2)
  decoder.finish()
}

///|
test "framing rejects invalid headers and lengths before accepting a body" {
  for
    header in [
      "Content-Length: 1\r\nContent-Length: 1\r\n\r\n", "Content-Length: -1\r\n\r\n",
      "Content-Length: 999999999999999999999\r\n\r\n", "Content-Length: 16777217\r\n\r\n",
      "Content-Length: nope\r\n\r\n", "Other: 2\r\n\r\n", "stdout log\r\n\r\n",
    ] {
    let mut refused = false
    ignore(@mep.Decoder::new().feed(@utf8.encode(header))) catch {
      _ => refused = true
    }
    assert_true(refused, msg=header)
  }
}

///|
test "framing rejects truncated headers bodies and oversized header blocks" {
  for input in ["Content-Len", "Content-Length: 2\r\n\r\nx"] {
    let decoder = @mep.Decoder::new()
    ignore(decoder.feed(@utf8.encode(input)))
    let mut refused = false
    decoder.finish() catch {
      _ => refused = true
    }
    assert_true(refused)
  }
  let mut refused = false
  ignore(@mep.Decoder::new().feed(Bytes::make(8193, b'x'))) catch {
    _ => refused = true
  }
  assert_true(refused)
}
