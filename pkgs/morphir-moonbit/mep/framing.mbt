///|
pub const MAX_FRAME_BYTES : Int32 = 16777216

///|
pub(all) suberror FrameError {
  InvalidFrame(String)
  FrameTooLarge(declared~ : Int64, limit~ : Int32)
} derive(Debug)

///|
pub extend FrameError with @debug.Debug::{to_repr}

///|
/// A text for the user. A frame above the default limit keeps the original
/// 16 MiB text.
pub fn FrameError::message(self : FrameError) -> String {
  match self {
    InvalidFrame(message) => message
    FrameTooLarge(limit~, ..) if limit == MAX_FRAME_BYTES =>
      "MEP payload exceeds 16 MiB"
    FrameTooLarge(declared~, limit~) =>
      "MEP payload declares \{declared} bytes, above the limit of \{limit}"
  }
}

///|
priv enum FrameState {
  Header(Array[Byte])
  Body(Int32, Array[Byte])
}

///|
pub struct Decoder {
  priv mut state : FrameState
  /// Where the current header line starts.
  priv mut line_start : Int32
  priv max_body : Int32
}

///|
/// A decoder that refuses a declared body above `max_body` bytes before it
/// buffers the body. The limit is at most `MAX_FRAME_BYTES`.
pub fn Decoder::new(max_body~ : Int32 = MAX_FRAME_BYTES) -> Decoder {
  let max_body = if max_body < MAX_FRAME_BYTES {
    max_body
  } else {
    MAX_FRAME_BYTES
  }
  { state: Header([]), line_start: 0, max_body, }
}

///|
/// The largest Content-Length that the decoder reads: 18 decimal digits, which
/// fit in Int64.
const MAX_DECLARED : Int64 = 999999999999999999L

///|
fn content_length(header : Array[Byte], max_body : Int32) -> Int32 raise {
  let text = @utf8.decode(Bytes::from_array(header)[:])
  let mut length : Int64? = None
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
    let mut n = 0L
    for c in digits {
      guard c >= '0' && c <= '9' else {
        raise InvalidFrame("Invalid Content-Length")
      }
      // Check each digit before multiplication, including huge decimal inputs.
      let digit = (c.to_int() - 48).to_int64()
      guard n <= (MAX_DECLARED - digit) / 10L else {
        raise InvalidFrame("MEP payload exceeds 16 MiB")
      }
      n = n * 10L + digit
    }
    length = Some(n)
  }
  let declared = length.unwrap_or_else(() => {
    raise InvalidFrame("Missing Content-Length")
  })
  guard declared <= max_body.to_int64() else {
    raise FrameTooLarge(declared~, limit=max_body)
  }
  declared.to_int()
}

///|
/// Whether a header line is `Name: value`: a name of visible characters
/// without spaces, then a colon.
fn is_header_line(line : ArrayView[Byte]) -> Bool {
  for i, byte in line {
    match byte {
      b':' => return i > 0
      b'\x21'..<=b'\x7e' => continue
      _ => return false
    }
  }
  false
}

///|
/// Checks the header byte that was just added. Each line must end with CRLF
/// and be `Name: value`; the decoder refuses a fault at the line's end, so a
/// log line on the stream fails at once. Returns whether the header block
/// is complete.
fn Decoder::check_header(self : Decoder, header : Array[Byte]) -> Bool raise {
  let n = header.length()
  let byte = header[n - 1]
  let after_cr = n >= 2 && header[n - 2] == b'\r'
  guard byte == b'\n' else {
    guard !after_cr else {
      raise InvalidFrame("MEP header line does not end with CRLF")
    }
    return false
  }
  guard after_cr else {
    raise InvalidFrame("MEP header line does not end with CRLF")
  }
  let line = header[self.line_start:n - 2]
  self.line_start = n
  if line.is_empty() {
    return true
  }
  guard is_header_line(line) else { raise InvalidFrame("Invalid MEP header") }
  false
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
        if self.check_header(header) {
          let length = content_length(header, self.max_body)
          self.line_start = 0
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
