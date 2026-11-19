///|
struct AttributeRequest {
  document : String
  pointer : String
}

///|
struct Request {
  case_id : String
  binding : String
  root : String
  snapshot : String
  ir_version : String
  encoding : @yaml.TreeEncoding
  extension : String
  selection : String
  page_size : Int32
  document_limit : Int32
  attributes : Array[AttributeRequest]
}

///|
fn require(condition : Bool, message : String) -> Unit raise {
  guard condition else { fail(message) }
}

///|
fn string_field(value : Json, key : String) -> String raise {
  @wire.string(@wire.field(value, key))
}

///|
fn positive_integer(value : Json, key : String, maximum : Int32) -> Int32 raise {
  let raw = @wire.integer_text(@wire.field(value, key))
  let number = @string.parse_int(raw)
  require(number > 0 && number <= maximum, "Invalid " + key)
  number
}

///|
fn value_end(text : String, start : Int32) -> Int32 {
  let mut depth = 0
  let mut quoted = false
  let mut escaped = false
  for i = start; i < text.length(); i = i + 1 {
    let character = text[i]
    if quoted {
      if escaped {
        escaped = false
      } else if character == '\\' {
        escaped = true
      } else if character == '"' {
        quoted = false
      }
    } else {
      match character {
        '"' => quoted = true
        '{' | '[' => depth += 1
        '}' | ']' => if depth == 0 { return i } else { depth -= 1 }
        ',' => if depth == 0 { return i }
        _ => ()
      }
    }
  }
  text.length()
}

///|
/// The duplicate-aware bounded decoder has already validated the entire JSON.
/// This scan retains the opaque binding's original JSON value text.
fn raw_binding(text : String) -> String raise {
  let mut offset = text.find("{").unwrap() + 1
  while offset < text.length() {
    while text[offset] == ' ' ||
          text[offset] == '\n' ||
          text[offset] == '\r' ||
          text[offset] == '\t' ||
          text[offset] == ',' {
      offset += 1
    }
    let start = offset
    offset += 1
    let mut escaped = false
    while offset < text.length() {
      let ch = text[offset]
      offset += 1
      if escaped {
        escaped = false
      } else if ch == '\\' {
        escaped = true
      } else if ch == '"' {
        break
      }
    }
    let key = @wire.string(@wire.parse(text[start:offset].to_owned()))
    while text[offset] != ':' {
      offset += 1
    }
    offset += 1
    let finish = value_end(text, offset)
    if key == "binding" {
      return text[offset:finish].to_owned()
    }
    offset = finish + 1
  }
  fail("Missing binding")
}

///|
fn read_request(bytes : Bytes) -> Request raise {
  require(bytes.length() <= 16384, "Request exceeds 16384 bytes")
  let text = @utf8.decode(bytes[:], ignore_bom=false)
  let value = @wire.parse_bounded(
    text,
    max_depth=32,
    max_nodes=8192,
    max_string_units=16384,
  )
  request_shape(value)
  @wire.fields(value, [
    "scope", "caseId", "binding", "treeRoot", "snapshot", "irVersion", "profile",
    "selection", "pageSize", "documentLimit", "attributes",
  ])
  require(
    string_field(value, "scope") == "native-reader-adapter",
    "Invalid scope",
  )
  ignore(@wire.object(@wire.field(value, "binding")))
  let root = string_field(value, "treeRoot")
  require(@path.Path(root).is_absolute(), "treeRoot must be absolute")
  let snapshot = string_field(value, "snapshot")
  require(
    snapshot.length() == 64 &&
    snapshot
    .iter()
    .all(ch => (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f')),
    "Invalid lowercase SHA-256",
  )
  let ir_version = string_field(value, "irVersion")
  require(ir_version == "3.1.0" || ir_version == "4.0.0", "Unsupported IR")
  let profile = string_field(value, "profile")
  let (encoding, extension) = match profile {
    "plainJson" => (@yaml.Plain, ".json")
    "plainYaml" => (@yaml.Plain, ".yaml")
    "contextualJson" => (@yaml.ContextualDraft1, ".json")
    "contextualYaml" => (@yaml.ContextualDraft1, ".yaml")
    _ => fail("Unsupported profile")
  }
  let case_id = string_field(value, "caseId")
  require(
    case_id == "acme-orders/" + ir_version + "/" + profile,
    "caseId does not match tuple",
  )
  let selection = string_field(value, "selection")
  require(
    selection.has_suffix("/module") &&
    !selection.has_prefix("/") &&
    !selection.contains("\\") &&
    !selection.split("/").any(part => part == "" || part == "." || part == ".."),
    "Invalid logical module document ID",
  )
  let attributes = @wire.array(@wire.field(value, "attributes")).map(item => {
    @wire.fields(item, ["document", "pointer"])
    let document = string_field(item, "document")
    let pointer = string_field(item, "pointer")
    require(
      document != "" &&
      !document.has_prefix("/") &&
      !document.contains("\\") &&
      !document
      .split("/")
      .any(part => part == ".." || part == "." || part == ""),
      "Unsafe document ID",
    )
    require(pointer == "" || pointer.has_prefix("/"), "Invalid JSON pointer")
    { document, pointer, }
  })
  require(
    ir_version != "4.0.0" || attributes.is_empty(),
    "v4 attributes must be empty",
  )
  {
    case_id,
    binding: raw_binding(text),
    root,
    snapshot,
    ir_version,
    encoding,
    extension,
    selection,
    page_size: positive_integer(value, "pageSize", 256),
    document_limit: positive_integer(value, "documentLimit", 8192),
    attributes,
  }
}

///|
fn request_shape(value : Json) -> Unit raise {
  match value {
    Object(fields) => {
      require(fields.length() <= 64, "Request object exceeds 64 properties")
      for key, child in fields {
        require(key.length() <= 4096, "Request key exceeds 4096 units")
        request_shape(child)
      }
    }
    Array(items) => {
      require(items.length() <= 256, "Request array exceeds 256 entries")
      for child in items {
        request_shape(child)
      }
    }
    String(text) =>
      require(text.length() <= 4096, "Request string exceeds 4096 units")
    _ => ()
  }
}
