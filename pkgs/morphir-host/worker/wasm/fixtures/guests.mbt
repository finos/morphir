///|
/// The three byte callbacks of `morphir-bytes-v1`, as functions 0, 1 and 2.
pub fn byte_callbacks() -> Array[ImportedFunction] {
  [
    ImportedFunction::new("morphir_bytes_v1", "input_len", [], [I32]),
    ImportedFunction::new("morphir_bytes_v1", "input_byte", [I32], [I32]),
    ImportedFunction::new("morphir_bytes_v1", "output_byte", [I32], []),
  ]
}

///|
/// A `morphir-bytes-v1` guest whose `handle` runs `code`, with two `i32`
/// locals and a memory of one page without a maximum.
pub fn bytes_guest(code : Bytes) -> Bytes {
  module_(
    imports=byte_callbacks(),
    functions=[
      DefinedFunction::new(export_name="handle", locals=[I32, I32], code),
    ],
    memory=Memory::new(1),
  )
}

///|
/// Echoes the request and returns its length. Local 0 is the index, local 1
/// the length.
pub fn echo_code() -> Bytes {
  b"\x10\x00\x21\x01" + // n = input_len()
  b"\x02\x40\x03\x40" + // block loop
  b"\x20\x00\x20\x01\x4e\x0d\x01" + // if i >= n break
  b"\x20\x00\x10\x01\x10\x02" + // output_byte(input_byte(i))
  b"\x20\x00\x41\x01\x6a\x21\x00" + // i = i + 1
  b"\x0c\x00\x0b\x0b" + // continue; end end
  b"\x20\x01" // n
}

///|
/// A guest that echoes each request.
pub fn echo_guest() -> Bytes {
  bytes_guest(echo_code())
}

///|
/// A guest whose `handle` returns `value` without output.
pub fn constant_guest(value : Int32) -> Bytes {
  bytes_guest(Bytes::from_array([b'\x41', ..sleb(value)]))
}

///|
/// A guest that writes `bytes` and returns `length`.
pub fn writing_guest(bytes : Bytes, length : Int32) -> Bytes {
  let code = []
  for byte in bytes {
    code.push(b'\x41')
    code.append(sleb(byte.to_int()))
    code.append([b'\x10', b'\x02'])
  }
  code.push(b'\x41')
  code.append(sleb(length))
  bytes_guest(Bytes::from_array(code))
}

///|
/// A guest whose `handle` loops forever.
pub fn runaway_guest() -> Bytes {
  bytes_guest(b"\x03\x40\x0c\x00\x0b\x41\x00")
}

///|
/// A guest whose `handle` traps with `unreachable`.
pub fn trapping_guest() -> Bytes {
  bytes_guest(b"\x00\x41\x00")
}

///|
/// A guest whose `handle` grows its memory by `pages` pages and returns the
/// result of `memory.grow`.
pub fn growing_guest(pages : Int32) -> Bytes {
  bytes_guest(Bytes::from_array([b'\x41', ..sleb(pages), b'\x40', b'\x00']))
}

///|
pub fn sleb(value : Int32) -> Array[Byte] {
  let bytes = []
  let mut rest = value
  while true {
    let byte = rest & 0x7f
    rest = rest >> 7
    let done = (rest == 0 && (byte & 0x40) == 0) ||
      (rest == -1 && (byte & 0x40) != 0)
    if done {
      bytes.push(byte.to_byte())
      break
    }
    bytes.push((byte | 0x80).to_byte())
  }
  bytes
}
