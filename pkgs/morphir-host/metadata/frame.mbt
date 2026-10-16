///|
/// An untrusted frame never establishes provider authenticity. The process host
/// must first qualify its executable and freshly complete the scoped operation.
pub(all) suberror TransportError {
  Invalid(String)
}

///|
pub const SERVICE_ID : String = "morphir-package/provider-snapshot/0.1.0-draft.1"

///|
pub const MAX_REQUEST_BYTES : Int32 = 4194304

///|
pub const MAX_RESPONSE_BYTES : Int32 = 16777216

///|
fn[T] invalid(detail : String) -> T raise {
  raise Invalid("metadata.restore_invalid_response: " + detail)
}

///|
/// Bound raw binary structure before the general Ion reader allocates values.
/// Native artifacts are blobs and are skipped without examining their contents.
fn preflight(bytes : Bytes) -> Unit raise {
  if bytes.length() < 4 ||
    bytes.length() > MAX_RESPONSE_BYTES ||
    bytes[0] != b'\xe0' ||
    bytes[1] != b'\x01' ||
    bytes[2] != b'\x00' ||
    bytes[3] != b'\xea' {
    invalid("Require one bounded Ion 1.0 binary frame")
  }
  let mut count = 0
  fn uint(position : Int32, end : Int32) -> (Int32, Int32) raise {
    let mut value = 0
    let mut cursor = position
    for _ in 0..<5 {
      if cursor >= end {
        invalid("Truncated binary length")
      }
      let byte = bytes[cursor].to_int()
      cursor += 1
      if value > 16777216 / 128 {
        invalid("Binary integer exceeds framing limit")
      }
      value = value * 128 + (byte & 127)
      if (byte & 128) != 0 {
        return (value, cursor)
      }
    }
    invalid("Overlong binary integer")
  }
  fn value(position : Int32, end : Int32, depth : Int32) -> Int32 raise {
    count += 1
    if count > 8192 || depth > 16 || position >= end {
      invalid("Binary structure limit")
    }
    let descriptor = bytes[position].to_int()
    let kind = descriptor >> 4
    let nibble = descriptor & 15
    if kind == 15 {
      invalid("Reserved binary descriptor")
    }
    let mut start = position + 1
    if nibble == 15 {
      return start
    }
    if kind == 1 {
      if nibble != 0 && nibble != 1 {
        invalid("Invalid Boolean descriptor")
      }
      return start
    }
    let length = if nibble == 14 || (kind == 13 && nibble == 1) {
      let (length, next) = uint(start, end)
      start = next
      length
    } else {
      nibble
    }
    if length > end - start {
      invalid("Truncated binary value")
    }
    let stop = start + length
    if (kind == 2 || kind == 3) && length > 4 {
      invalid("Protocol integer exceeds range")
    }
    if kind == 11 || kind == 12 || kind == 13 {
      let mut cursor = start
      while cursor < stop {
        if kind == 13 {
          let (_, next) = uint(cursor, stop)
          cursor = next
        }
        cursor = value(cursor, stop, depth + 1)
      }
    } else if kind == 14 {
      let (annotation_bytes, after_length) = uint(start, stop)
      if annotation_bytes == 0 || annotation_bytes > stop - after_length {
        invalid("Invalid annotation wrapper")
      }
      let annotation_end = after_length + annotation_bytes
      let mut cursor = after_length
      while cursor < annotation_end {
        let (_, next) = uint(cursor, annotation_end)
        cursor = next
      }
      if value(annotation_end, stop, depth + 1) != stop {
        invalid("Trailing annotated value")
      }
    }
    stop
  }
  let mut cursor = 4
  while cursor < bytes.length() {
    if cursor + 4 <= bytes.length() &&
      bytes[cursor] == b'\xe0' &&
      bytes[cursor + 1] == b'\x01' &&
      bytes[cursor + 2] == b'\x00' &&
      bytes[cursor + 3] == b'\xea' {
      cursor += 4
    } else {
      cursor = value(cursor, bytes.length(), 0)
    }
  }
}

///|
fn members(value : @ion.IonValue) -> Map[String, @ion.IonValue] raise {
  if value.has_annotations() {
    invalid("Unexpected nested annotation")
  }
  guard value.kind() is @ion.Struct(entries) else {
    invalid("Expected a struct")
  }
  let result = Map([])
  for entry in entries {
    guard entry.name().text() is Some(name) && !result.contains(name) else {
      invalid("Duplicate or unresolved field")
    }
    result[name] = entry.value()
  }
  result
}

///|
fn fields(
  value : @ion.IonValue,
  names : Array[String],
) -> Map[String, @ion.IonValue] raise {
  let result = members(value)
  if result.length() != names.length() ||
    !result.keys().all(name => names.contains(name)) {
    invalid("Unknown or missing field")
  }
  result
}

///|
fn frame(
  bytes : Bytes,
  annotation : String,
  names : Array[String],
) -> Map[String, @ion.IonValue] raise {
  preflight(bytes)
  let value = @binary.read_binary_value(bytes[:])
  if value.annotations().map(a => a.text()) != [Some(annotation)] {
    invalid("Wrong response profile")
  }
  fields(value.with_annotations([]), names)
}

///|
fn required(
  values : Map[String, @ion.IonValue],
  key : String,
) -> @ion.IonValue raise {
  values.get(key).unwrap_or_else(fn() raise { invalid("Missing " + key) })
}

///|
fn text(value : @ion.IonValue) -> String raise {
  if value.has_annotations() {
    invalid("Annotated scalar")
  }
  guard value.kind() is @ion.String(text) &&
    text.length() <= 4096 &&
    !text.contains("\u0000") else {
    invalid("Expected a bounded string")
  }
  text
}

///|
fn blob(value : @ion.IonValue) -> Bytes raise {
  if value.has_annotations() {
    invalid("Annotated blob")
  }
  guard value.kind() is @ion.Blob(bytes) else {
    invalid("Expected exact byte blob")
  }
  bytes
}

///|
fn list(value : @ion.IonValue, limit : Int32) -> Array[@ion.IonValue] raise {
  if value.has_annotations() {
    invalid("Annotated list")
  }
  guard value.kind() is @ion.List(values) && values.length() <= limit else {
    invalid("Expected bounded list")
  }
  values
}

///|
fn raw_digest(value : String) -> String raise {
  if value.length() != 71 ||
    !value.has_prefix("sha256:") ||
    !value[7:]
    .to_owned()
    .to_array()
    .all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
    invalid("Invalid raw SHA-256 identity")
  }
  value[7:].to_owned()
}

///|
fn record(values : Array[(String, @ion.IonValue)]) -> @ion.IonValue {
  @ion.IonValue::from_fields(values.map(v => @ion.Field::new(v.0, v.1)))
}
