///|
/// Reads whole MEP messages from a worker's stdout with Content-Length
/// framing. A declared body above the limit is refused before the body is
/// buffered.
pub struct FrameReader {
  priv decoder : @mep.Decoder
}

///|
pub fn FrameReader::new(limit~ : Int32) -> FrameReader {
  { decoder: @mep.Decoder::new(max_body=limit), }
}

///|
/// The channel error for a fault in a frame that the worker sent.
fn read_error(error : Error) -> @worker.ChannelError {
  match error {
    @mep.FrameTooLarge(declared~, limit~) =>
      FrameLimit(direction=Response, declared~, limit~)
    @mep.InvalidFrame(message) => FrameInvalid(message)
    _ => FrameInvalid("MEP header is not UTF-8")
  }
}

///|
/// Returns the messages that the chunk completes, in order.
pub fn FrameReader::feed(
  self : FrameReader,
  chunk : Bytes,
) -> Array[@worker.Message] raise @worker.ChannelError {
  let bodies = self.decoder.feed(chunk) catch {
    error => raise read_error(error)
  }
  bodies.map(@worker.Message::parse)
}

///|
/// Checks the end of the stream: a partial frame is invalid.
pub fn FrameReader::finish(
  self : FrameReader,
) -> Unit raise @worker.ChannelError {
  self.decoder.finish() catch {
    error => raise read_error(error)
  }
}

///|
/// Encodes MEP messages for a worker's stdin with Content-Length framing.
pub struct FrameWriter {
  priv limit : Int32
}

///|
pub fn FrameWriter::new(limit~ : Int32) -> FrameWriter {
  { limit, }
}

///|
/// Encodes one message as a frame. A frame above the limit is refused.
pub fn FrameWriter::encode(
  self : FrameWriter,
  message : @worker.Message,
) -> Bytes raise @worker.ChannelError {
  // `encode_frame` refuses only a body above 16 MiB, which is above every
  // request limit.
  let frame = @mep.encode_frame(message.json().stringify()) catch {
    _ =>
      raise FrameLimit(
        direction=Request,
        declared=message.size().to_int64(),
        limit=self.limit,
      )
  }
  guard frame.length() <= self.limit else {
    raise FrameLimit(
      direction=Request,
      declared=frame.length().to_int64(),
      limit=self.limit,
    )
  }
  frame
}
