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

///|
fn refusal(decoder : @mep.Decoder, header : String) -> @mep.FrameError? {
  ignore(decoder.feed(@utf8.encode(header))) catch {
    @mep.InvalidFrame(message) => return Some(@mep.InvalidFrame(message))
    @mep.FrameTooLarge(declared~, limit~) =>
      return Some(@mep.FrameTooLarge(declared~, limit~))
    _ => return None
  }
  None
}

///|
test "framing refuses a declared body above the decoder limit before the body" {
  let refused = refusal(
    @mep.Decoder::new(max_body=4),
    "Content-Length: 5\r\n\r\n",
  )
  debug_inspect(refused, content="Some(FrameTooLarge(declared=5, limit=4))")
  let decoder = @mep.Decoder::new(max_body=4)
  assert_eq(decoder.feed(@mep.encode_frame("1234")), [b"1234"])
  decoder.finish()
}

///|
test "framing reports a declared body above 16 MiB as too large by default" {
  let refused = refusal(@mep.Decoder::new(), "Content-Length: 16777217\r\n\r\n")
  debug_inspect(
    refused,
    content="Some(FrameTooLarge(declared=16777217, limit=16777216))",
  )
  let refused = refusal(
    @mep.Decoder::new(),
    "Content-Length: 99999999999\r\n\r\n",
  )
  debug_inspect(
    refused,
    content="Some(FrameTooLarge(declared=99999999999, limit=16777216))",
  )
}

///|
test "framing keeps the 16 MiB message for the default limit" {
  let error = @mep.FrameTooLarge(declared=16777217L, limit=@mep.MAX_FRAME_BYTES)
  inspect(error.message(), content="MEP payload exceeds 16 MiB")
  let error = @mep.FrameTooLarge(declared=5L, limit=4)
  inspect(
    error.message(),
    content="MEP payload declares 5 bytes, above the limit of 4",
  )
  inspect(
    @mep.InvalidFrame("Truncated MEP frame").message(),
    content="Truncated MEP frame",
  )
}

///|
test "framing refuses a bare LF at once, before the header block ends" {
  // `console.log("x")` writes `x` and a bare LF; no blank line follows.
  debug_inspect(
    refusal(@mep.Decoder::new(), "x\n"),
    content="Some(InvalidFrame(\"MEP header line does not end with CRLF\"))",
  )
  debug_inspect(
    refusal(@mep.Decoder::new(), "Content-Length: 2\n"),
    content="Some(InvalidFrame(\"MEP header line does not end with CRLF\"))",
  )
  debug_inspect(
    refusal(@mep.Decoder::new(), "Content-Length: 2\rx"),
    content="Some(InvalidFrame(\"MEP header line does not end with CRLF\"))",
  )
}

///|
test "framing refuses a header line that is not Name: value at its CRLF" {
  for line in ["worker log line\r\n", ": 2\r\n", "Content Length: 2\r\n"] {
    debug_inspect(
      refusal(@mep.Decoder::new(), line),
      content="Some(InvalidFrame(\"Invalid MEP header\"))",
    )
  }
  // A valid line waits for the rest of the header block.
  debug_inspect(
    refusal(@mep.Decoder::new(), "Content-Type: application/json\r\n"),
    content="None",
  )
}

///|
test "framing keeps the 16 MiB text for a Content-Length too long to read" {
  debug_inspect(
    refusal(
      @mep.Decoder::new(),
      "Content-Length: 999999999999999999999\r\n\r\n",
    ),
    content="Some(InvalidFrame(\"MEP payload exceeds 16 MiB\"))",
  )
}
