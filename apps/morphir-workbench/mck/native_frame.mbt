///|
/// Compact fixture generation belongs to the implementation adapter, not the
/// shared runner. Malformed fixture envelopes terminate the adapter as an
/// infrastructure failure; they are never a native domain rejection.
fn fixture_fields(value : Json, keys : Array[String]) -> Map[String, Json] {
  guard value is Object(fields) &&
    fields.length() == keys.length() &&
    keys.all(key => fields.contains(key)) else {
    abort("workbench: invalid native frame fixture shape")
  }
  fields
}

///|
fn hex_digit(c : Char) -> Int32 {
  match c {
    '0'..<='9' => c.to_int() - '0'.to_int()
    'a'..<='f' => c.to_int() - 'a'.to_int() + 10
    'A'..<='F' => c.to_int() - 'A'.to_int() + 10
    _ => abort("workbench: invalid native frame fixture hex")
  }
}

///|
fn native_fixture_bytes(input : Json, keys : Array[String]) -> Bytes {
  guard @utf8.encode(input.stringify()).length() <= 1048576 else {
    abort("workbench: native frame fixture exceeds compact input limit")
  }
  guard input is Object(fields) else {
    abort("workbench: invalid native frame fixture")
  }
  ignore(
    fixture_fields(
      input,
      if fields.contains("generate") {
        keys + ["generate"]
      } else {
        keys
      },
    ),
  )
  guard fields["source"] is String(source) else {
    abort("workbench: native frame fixture requires source text")
  }
  let body = match fields["encoding"] {
    String("utf8") => @utf8.encode(source)
    String("hex") => {
      guard source.length() % 2 == 0 else {
        abort("workbench: native frame fixture hex must have even length")
      }
      let chars = source.iter().collect()
      let bytes : Array[Byte] = []
      let mut index = 0
      while index < chars.length() {
        bytes.push(
          ((hex_digit(chars[index]) << 4) | hex_digit(chars[index + 1])).to_byte(),
        )
        index += 2
      }
      Bytes::from_array(bytes)
    }
    _ => abort("workbench: invalid native frame fixture encoding")
  }
  if fields.get("generate") is Some(generate) {
    let generate = fixture_fields(generate, ["prefix"])
    let prefix = fixture_fields(generate["prefix"], ["repeat", "count"])
    guard prefix["repeat"] == Json::string(" ") &&
      prefix["count"] is Number(n, ..) &&
      n >= 0 &&
      n <= 1048576 &&
      n.floor() == n &&
      @wire.is_integral_number(prefix["count"]) &&
      n + body.length().to_double() <= 2097152 else {
      abort("workbench: invalid native frame fixture recipe")
    }
    @utf8.encode(" ".repeat(n.to_int())) + body
  } else {
    body
  }
}

///|
fn native_frame(id : Json, input : Json) -> Json {
  let bytes = native_fixture_bytes(input, ["encoding", "source"])
  try {
    ignore(@native_frame.decode(bytes))
    { "id": id, "status": "ok", "value": { "frameAccepted": true } }
  } catch {
    @native_frame.Invalid(code) => invalid(id, code)
  }
}
