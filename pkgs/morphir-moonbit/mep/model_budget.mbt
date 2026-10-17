///|
priv struct ModelBudget {
  limits : ModelLimits
  mut encoded : Int32
  mut decoded : Int32
  mut nodes : Int32
  mut system_nodes : Int32
}

///|
fn ModelBudget::new(limits : ModelLimits) -> ModelBudget {
  { limits, encoded: 0, decoded: 0, nodes: 0, system_nodes: 0, }
}

///|
fn ModelBudget::charge(
  self : ModelBudget,
  depth : Int32,
  system : Bool,
) -> Unit raise {
  guard depth <= self.limits.depth else { raise Refused("depth_limit") }
  if system {
    guard self.system_nodes < self.limits.nodes else {
      raise Refused("symbol_table_limit")
    }
    self.system_nodes += 1
  } else {
    guard self.nodes < self.limits.nodes else { raise Refused("node_limit") }
    self.nodes += 1
  }
}

///|
// Check aggregate wire sizes for every payload before decoding any base64.
fn ModelBudget::reserve(self : ModelBudget, payload : Json) -> Unit raise {
  let content = @wire.string(@wire.field(payload, "content"))
  let size = @strconv.parse_int(
    @wire.integer_text(@wire.field(payload, "decodedByteLength")),
  )
  guard size >= 0 else { raise Refused("length_mismatch") }
  guard content.length() <= self.limits.encoded - self.encoded else {
    raise Refused("encoded_limit")
  }
  guard size <= self.limits.decoded - self.decoded else {
    raise Refused("decoded_limit")
  }
  self.encoded += content.length()
  self.decoded += size
}

///|
fn ModelBudget::decode(_self : ModelBudget, payload : Json) -> Bytes raise {
  guard @wire.string(@wire.field(payload, "layout")) == "single-document" else {
    raise Refused("unsupported_layout")
  }
  let content = @wire.string(@wire.field(payload, "content"))
  let size = @strconv.parse_int(
    @wire.integer_text(@wire.field(payload, "decodedByteLength")),
  )
  guard content.length().to_int64() == (size.to_int64() + 2L) / 3L * 4L else {
    raise Refused("length_mismatch")
  }
  let bytes = @base64.decode(content) catch {
    _ => raise Refused("invalid_base64")
  }
  guard bytes.length() == size else { raise Refused("length_mismatch") }
  guard @base64.encode(bytes[:]) == content else {
    raise Refused("invalid_base64")
  }
  guard model_sha256(bytes) == model_digest(@wire.field(payload, "sha256")) else {
    raise Refused("digest_mismatch")
  }
  bytes
}

///|
priv struct BinaryCursor {
  bytes : Bytes
  mut pos : Int32
}

///|
fn BinaryCursor::var_uint(self : BinaryCursor, end : Int32) -> Int32 raise {
  let mut value = 0
  while self.pos < end {
    let octet = self.bytes[self.pos].to_int()
    self.pos += 1
    let low = octet & 127
    guard value <= (2147483647 - low) / 128 else {
      raise Refused("invalid_ion")
    }
    value = value * 128 + low
    if (octet & 128) != 0 {
      return value
    }
  }
  raise Refused("invalid_ion")
}

///|
priv struct BinaryHeader {
  kind : Int32
  nibble : Int32
  end : Int32
}

///|
fn BinaryCursor::header(self : BinaryCursor, end : Int32) -> BinaryHeader raise {
  guard self.pos < end else { raise Refused("invalid_ion") }
  let descriptor = self.bytes[self.pos].to_int()
  self.pos += 1
  let kind = descriptor >> 4
  let nibble = descriptor & 15
  let length = if kind == 1 || nibble == 15 {
    0
  } else if nibble == 14 || (kind == 13 && nibble == 1) {
    self.var_uint(end)
  } else {
    nibble
  }
  guard length <= end - self.pos else { raise Refused("invalid_ion") }
  { kind, nibble, end: self.pos + length, }
}

///|
priv struct BinaryFrame {
  end : Int32
  structure : Bool
  depth : Int32
  system : Bool
  local_table : Bool
}

///|
// An allocation admission pass, not another Ion decoder. It scans length
// boundaries and values without constructing trees or resolving symbol tables.
// The Ion package remains responsible for full scalar and stream validation.
fn ModelBudget::inspect_binary(self : ModelBudget, bytes : Bytes) -> Unit raise {
  guard @ion_binary.has_version_marker(bytes[:], 0) else {
    raise Refused("invalid_ion")
  }
  let cursor = { bytes, pos: 4, }
  let frames : Array[BinaryFrame] = [
    {
      end: bytes.length(),
      structure: false,
      depth: 0,
      system: false,
      local_table: false,
    },
  ]
  while !frames.is_empty() {
    let frame = frames[frames.length() - 1]
    if cursor.pos == frame.end {
      ignore(frames.pop())
      continue
    }
    guard cursor.pos < frame.end else { raise Refused("invalid_ion") }
    if frames.length() == 1 &&
      @ion_binary.has_version_marker(bytes[:], cursor.pos) {
      cursor.pos += 4
      continue
    }
    let sid = if frame.structure { cursor.var_uint(frame.end) } else { 0 }
    let mut header = cursor.header(frame.end)
    if header.kind == 0 && header.nibble != 15 {
      cursor.pos = header.end
      continue
    }
    let mut local_table = false
    if header.kind == 14 {
      let wrapper_end = header.end
      let size = cursor.var_uint(wrapper_end)
      guard size > 0 && size <= wrapper_end - cursor.pos else {
        raise Refused("invalid_ion")
      }
      let annotation_end = cursor.pos + size
      let first = cursor.var_uint(annotation_end)
      while cursor.pos < annotation_end {
        ignore(cursor.var_uint(annotation_end))
      }
      header = cursor.header(wrapper_end)
      guard header.kind != 14 &&
        (header.kind != 0 || header.nibble == 15) &&
        header.end == wrapper_end else {
        raise Refused("invalid_ion")
      }
      local_table = frames.length() == 1 &&
        first == 3 &&
        header.kind == 13 &&
        header.nibble != 15
    }
    // No shared catalog is negotiated. Refuse shared imports before the library
    // can reserve IDs or resolve them. Empty imports and local append are safe.
    if frame.local_table && sid == 6 && header.nibble != 15 {
      let empty_imports = header.kind == 11 && cursor.pos == header.end
      let append = header.kind == 7 &&
        header.end - cursor.pos == 1 &&
        bytes[cursor.pos] == b'\x03'
      guard empty_imports || append else {
        raise Refused("unsupported_shared_symbols")
      }
    }
    let system = frame.system || local_table
    self.charge(frame.depth + 1, system)
    if [11, 12, 13].contains(header.kind) && header.nibble != 15 {
      frames.push({
        end: header.end,
        structure: header.kind == 13,
        depth: frame.depth + 1,
        system,
        local_table,
      })
    } else {
      cursor.pos = header.end
    }
  }
}

///|
// Resolve system values one at a time only after the entire datagram passed
// preflight. Check resolved field names as well as raw SIDs, since a local
// symbol can alias a system symbol. No shared symbol catalog is admitted.
fn read_model_binary(
  bytes : Bytes,
  limits : ModelLimits,
) -> @ion.IonValue raise {
  let table = @ion.SymbolTable::system()
  let mut offset = 0
  let mut root : @ion.IonValue? = None
  while offset < bytes.length() {
    if @ion_binary.has_version_marker(bytes[:], offset) {
      table.reset()
      offset += 4
      continue
    }
    match @ion_binary.decode_value(bytes[:], offset, table) {
      None => {
        guard @ion_binary.is_padding_only(bytes[:], offset) else {
          raise Refused("invalid_ion")
        }
        break
      }
      Some((value, consumed)) => {
        offset += consumed
        if value.annotations() is [first, ..] &&
          first.text() == Some("$ion_symbol_table") &&
          value.kind() is Struct(fields) {
          for field in fields {
            if field.name().text() == Some("imports") &&
              field.value().kind() is List(imports) &&
              !imports.is_empty() {
              raise Refused("unsupported_shared_symbols")
            }
          }
        }
        match @ion_binary.accept_value(table, value) {
          Some(value) => {
            guard root is None else { raise Refused("invalid_ion") }
            root = Some(value)
          }
          None => {
            guard table.max_id() >= 9 && table.max_id() - 9 <= limits.nodes else {
              raise Refused("symbol_table_limit")
            }
          }
        }
      }
    }
  }
  guard root is Some(value) else { raise Refused("invalid_ion") }
  value
}

///|
fn ModelBudget::read_json(self : ModelBudget, bytes : Bytes) -> Json raise {
  let remaining = self.limits.nodes - self.nodes
  guard remaining > 0 else { raise Refused("node_limit") }
  let value = @wire.parse_bounded(
    @utf8.decode(bytes[:]),
    max_depth=self.limits.depth - 1,
    max_nodes=remaining,
    max_string_units=self.limits.decoded,
  )
  let pending = [value]
  while pending.pop() is Some(value) {
    self.nodes += 1
    match value {
      Array(values) =>
        for child in values {
          pending.push(child)
        }
      Object(fields) =>
        for _, child in fields {
          pending.push(child)
        }
      _ => ()
    }
  }
  value
}
