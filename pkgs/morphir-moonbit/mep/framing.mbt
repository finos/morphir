///|
pub const MAX_FRAME_BYTES : Int32 = 16777216

///|
pub(all) suberror FrameError {
  InvalidFrame(String)
} derive(Debug)

///|
pub extend FrameError with @debug.Debug::{to_repr}

///|
priv enum FrameState {
  Header(Array[Byte])
  Body(Int32, Array[Byte])
}

///|
pub struct Decoder {
  priv mut state : FrameState
}

///|
pub fn Decoder::new() -> Decoder {
  { state: Header([]), }
}

///|
fn content_length(header : Array[Byte]) -> Int32 raise {
  let text = @utf8.decode(Bytes::from_array(header)[:])
  let mut length : Int32? = None
  for line in text.split("\r\n") {
    if line.is_empty() {
      continue
    }
    let pieces = line.split(":").collect()
    guard pieces.length() >= 2 else { raise InvalidFrame("Invalid MEP header") }
    if pieces[0].to_owned().to_lower() != "content-length" {
      continue
    }
    guard length is None && pieces.length() == 2 else {
      raise InvalidFrame("Repeated or invalid Content-Length")
    }
    let digits = pieces[1].trim().to_owned()
    guard !digits.is_empty() else { raise InvalidFrame("Empty Content-Length") }
    let mut n = 0
    for c in digits {
      guard c >= '0' && c <= '9' else {
        raise InvalidFrame("Invalid Content-Length")
      }
      // Check each digit before multiplication, including huge decimal inputs.
      let digit = c.to_int() - 48
      guard n <= (MAX_FRAME_BYTES - digit) / 10 else {
        raise InvalidFrame("MEP payload exceeds 16 MiB")
      }
      n = n * 10 + digit
    }
    length = Some(n)
  }
  length.unwrap_or_else(() => raise InvalidFrame("Missing Content-Length"))
}

///|
pub fn Decoder::feed(self : Decoder, bytes : Bytes) -> Array[Bytes] raise {
  let frames = []
  for byte in bytes {
    match self.state {
      Header(header) => {
        header.push(byte)
        guard header.length() <= 8192 else {
          raise InvalidFrame("MEP header exceeds 8 KiB")
        }
        let n = header.length()
        if n >= 4 &&
          header[n - 4] == b'\r' &&
          header[n - 3] == b'\n' &&
          header[n - 2] == b'\r' &&
          header[n - 1] == b'\n' {
          let length = content_length(header)
          if length == 0 {
            frames.push(b"")
            self.state = Header([])
          } else {
            self.state = Body(length, [])
          }
        }
      }
      Body(length, body) => {
        body.push(byte)
        if body.length() == length {
          frames.push(Bytes::from_array(body))
          self.state = Header([])
        }
      }
    }
  }
  frames
}

///|
pub fn Decoder::finish(self : Decoder) -> Unit raise FrameError {
  match self.state {
    Header(header) if header.is_empty() => ()
    _ => raise InvalidFrame("Truncated MEP frame")
  }
}

///|
pub fn encode_frame(body : String) -> Bytes raise FrameError {
  let bytes = @utf8.encode(body)
  guard bytes.length() <= MAX_FRAME_BYTES else {
    raise InvalidFrame("MEP response exceeds 16 MiB")
  }
  let buffer = @buffer.Buffer::Buffer()
  buffer.write_string_utf8("Content-Length: \{bytes.length()}\r\n\r\n")
  buffer.write_bytes(bytes[:])
  buffer.to_bytes()
}
