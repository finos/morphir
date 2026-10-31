///|
fn read_all(
  reader : @process.FrameReader,
  chunks : Array[Bytes],
) -> Array[@worker.Message] raise @worker.ChannelError {
  let messages = []
  for chunk in chunks {
    messages.append(reader.feed(chunk))
  }
  messages
}

///|
test "frame reader returns whole messages across chunk boundaries" {
  let frames = @process.FrameWriter::new(limit=1024).encode(
    @worker.Message::new({ "jsonrpc": "2.0", "id": 1, "result": "λ" }),
  )
  for split = 0; split <= frames.length(); split = split + 1 {
    let reader = @process.FrameReader::new(limit=1024)
    let messages = read_all(reader, [
      frames[:split].to_owned(),
      frames[split:].to_owned(),
    ])
    reader.finish()
    assert_eq(messages.map(message => message.json()), [
      { "jsonrpc": "2.0", "id": 1, "result": "λ" },
    ])
  }
}

///|
test "frame reader refuses a declared body above its limit before the body" {
  let reader = @process.FrameReader::new(limit=8)
  let refused = try {
    reader.feed(@utf8.encode("Content-Length: 9\r\n\r\n")) |> ignore
    None
  } catch {
    error => Some(error)
  }
  debug_inspect(
    refused,
    content="Some(FrameLimit(direction=Response, declared=9, limit=8))",
  )
}

///|
test "frame reader treats a log line on stdout as an invalid frame" {
  let reader = @process.FrameReader::new(limit=1024)
  let refused = try {
    reader.feed(@utf8.encode("starting worker\r\n\r\n")) |> ignore
    None
  } catch {
    error => Some(error)
  }
  guard refused is Some(FrameInvalid(_)) else { fail("accepted a log line") }
}

///|
test "frame reader refuses a body that is not JSON" {
  let reader = @process.FrameReader::new(limit=1024)
  let refused = try {
    reader.feed(@utf8.encode("Content-Length: 3\r\n\r\nabc")) |> ignore
    None
  } catch {
    error => Some(error)
  }
  debug_inspect(refused, content="Some(FrameInvalid(\"message is not JSON\"))")
}

///|
test "frame reader refuses a truncated frame at the end of the stream" {
  let reader = @process.FrameReader::new(limit=1024)
  reader.feed(@utf8.encode("Content-Length: 4\r\n\r\n{}")) |> ignore
  let refused = try {
    reader.finish()
    None
  } catch {
    error => Some(error)
  }
  debug_inspect(refused, content="Some(FrameInvalid(\"Truncated MEP frame\"))")
}

///|
test "frame writer refuses a message above its limit" {
  let message = @worker.Message::new({ "params": "x".repeat(64) })
  let refused = try {
    @process.FrameWriter::new(limit=32).encode(message) |> ignore
    None
  } catch {
    error => Some(error)
  }
  guard refused is Some(FrameLimit(direction=Request, limit=32, ..)) else {
    fail("accepted an oversized request")
  }
}
