///|
/// Stable diagnostic code and detail. Callers need not parse error prose.
#derive(Eq, Debug)
pub(all) suberror CodecError {
  Invalid(String, String)
}

///|
pub extend CodecError with Eq::{equal, not_equal}

///|
pub extend CodecError with @debug.Debug::{to_repr}

///|
priv struct Reader {
  chars : Array[Char]
  mut index : Int32
  max_depth : Int32
  allow_document_layer : Bool
  mut used_document_layer : Bool
  mut nodes : Int32?
  mut string_units : Int32?
  context_duplicates : Ref[(String, String, String)?]?
}

///|
fn Reader::space(self : Reader) -> Unit {
  while self.index < self.chars.length() &&
        (
          self.chars[self.index] == ' ' ||
          self.chars[self.index] == '\n' ||
          self.chars[self.index] == '\r' ||
          self.chars[self.index] == '\t'
        ) {
    self.index += 1
  }
}

///|
fn Reader::take(self : Reader, expected : Char) -> Unit raise CodecError {
  self.space()
  if self.index >= self.chars.length() || self.chars[self.index] != expected {
    raise Invalid(
      "invalid_json",
      "Expected \{expected} at character \{self.index}",
    )
  }
  self.index += 1
}

///|
fn Reader::string(self : Reader) -> String raise CodecError {
  self.space()
  let start = self.index
  self.take('"')
  while self.index < self.chars.length() {
    let character = self.chars[self.index]
    self.index += 1
    if character == '\\' {
      self.index += 1
    } else if character == '"' {
      let text = String::from_array(self.chars[start:self.index])
      let parsed = @json.parse(text) catch {
        _ => raise Invalid("invalid_json", "Invalid JSON string")
      }
      return match parsed {
        String(value) => {
          if self.string_units is Some(remaining) {
            guard value.length() <= remaining else {
              raise Invalid("json_limit", "Decoded string budget exceeded")
            }
            self.string_units = Some(remaining - value.length())
          }
          value
        }
        _ => raise Invalid("invalid_json", "Expected string")
      }
    }
  }
  raise Invalid("invalid_json", "Unterminated string")
}

///|
fn Reader::depth_error(self : Reader) -> CodecError {
  Invalid(
    if self.nodes is None {
      "invalid_json"
    } else {
      "json_limit"
    },
    "Depth budget exceeded",
  )
}

///|
fn Reader::value(
  self : Reader,
  depth : Int32,
  context_path : String?,
  in_document~ : Bool = false,
) -> Json raise CodecError {
  self.space()
  if depth > self.max_depth {
    guard in_document && depth == self.max_depth + 1 else {
      raise self.depth_error()
    }
    self.used_document_layer = true
  }
  if self.nodes is Some(remaining) {
    guard remaining > 0 else {
      raise Invalid("json_limit", "Node budget exceeded")
    }
    self.nodes = Some(remaining - 1)
  }
  if self.index >= self.chars.length() {
    raise Invalid("invalid_json", "Unexpected end of input")
  }
  match self.chars[self.index] {
    '"' => Json::string(self.string())
    '{' => {
      self.index += 1
      let fields : Map[String, Json] = Map([])
      self.space()
      if self.index < self.chars.length() && self.chars[self.index] == '}' {
        self.index += 1
        return Json::object(fields)
      }
      while true {
        let key = self.string()
        let duplicate = fields.contains(key)
        if duplicate {
          let code = if key == "formatVersion" && depth == 0 {
            "duplicate_format_version"
          } else {
            "duplicate_member"
          }
          if self.context_duplicates is Some(first) &&
            context_path is Some(parent) {
            if first.val is None {
              let component = key
                .replace_all(old="~", new="~0")
                .replace_all(old="/", new="~1")
              first.val = Some((code, key, parent + "/" + component))
            }
          } else {
            raise Invalid(code, key)
          }
        }
        self.take(':')
        let child_path = match context_path {
          Some("") if key == "context" => Some("/context")
          Some("/context") => {
            let child = "/context/" + key
            if is_context_duplicate_scope(child) {
              Some(child)
            } else {
              None
            }
          }
          _ => None
        }
        let in_document = in_document ||
          (self.allow_document_layer && depth == 0 && key == "document")
        let item = self.value(depth + 1, child_path, in_document~)
        if !duplicate {
          fields[key] = item
        }
        self.space()
        if self.index < self.chars.length() && self.chars[self.index] == '}' {
          self.index += 1
          break
        }
        self.take(',')
      }
      Json::object(fields)
    }
    '[' => {
      self.index += 1
      let items : Array[Json] = []
      self.space()
      if self.index < self.chars.length() && self.chars[self.index] == ']' {
        self.index += 1
        return Json::array(items)
      }
      while true {
        items.push(self.value(depth + 1, None, in_document~))
        self.space()
        if self.index < self.chars.length() && self.chars[self.index] == ']' {
          self.index += 1
          break
        }
        self.take(',')
      }
      Json::array(items)
    }
    _ => {
      let start = self.index
      while self.index < self.chars.length() &&
            self.chars[self.index] != ',' &&
            self.chars[self.index] != ']' &&
            self.chars[self.index] != '}' &&
            self.chars[self.index] != ' ' &&
            self.chars[self.index] != '\n' &&
            self.chars[self.index] != '\r' &&
            self.chars[self.index] != '\t' {
        self.index += 1
      }
      let text = String::from_array(self.chars[start:self.index])
      let parsed = @json.parse(text) catch {
        _ => raise Invalid("invalid_json", "Invalid scalar: " + text)
      }
      match parsed {
        Number(number, ..) => Json::number(number, repr=text)
        Null | True | False => parsed
        _ => raise Invalid("invalid_json", "Invalid scalar")
      }
    }
  }
}

///|
const PlainDocumentMaxDepth = 512

///|
/// Reject duplicate members and preserve every numeric lexeme before decoding IR.
pub fn parse(text : String) -> Json raise CodecError {
  parse_with_limits(text, PlainDocumentMaxDepth, None, None, false)
}

///|
/// Bounded duplicate-aware JSON decoding for external frames. Root depth is zero;
/// each JSON value consumes one node, and keys and values share a UTF-16 budget.
pub fn parse_bounded(
  text : String,
  max_depth~ : Int32 = 64,
  max_nodes~ : Int32 = 100000,
  max_string_units~ : Int32 = 1048576,
  contextual~ : Bool = false,
) -> Json raise CodecError {
  parse_with_limits(
    text,
    max_depth,
    Some(max_nodes),
    Some(max_string_units),
    contextual,
  )
}

///|
fn parse_with_limits(
  text : String,
  max_depth : Int32,
  nodes : Int32?,
  string_units : Int32?,
  contextual : Bool,
  allow_document_layer~ : Bool = false,
) -> Json raise CodecError {
  let duplicates : Ref[(String, String, String)?]? = if contextual {
    Some(Ref(None))
  } else {
    None
  }
  let reader = Reader::{
    chars: text.iter().collect(),
    index: 0,
    max_depth,
    allow_document_layer,
    used_document_layer: false,
    nodes,
    string_units,
    context_duplicates: duplicates,
  }
  let result = reader.value(0, if contextual { Some("") } else { None })
  reader.space()
  if reader.index != reader.chars.length() {
    raise Invalid("invalid_json", "Trailing input")
  }
  // The document is a full plain IR payload. Its envelope may add one level.
  // Confirm the marker here because JSON can place it after the document.
  if reader.used_document_layer {
    guard result is Object(fields) &&
      fields.get("$schema") is Some(String(url)) &&
      url == ContextualSchema else {
      raise reader.depth_error()
    }
  }
  if duplicates is Some(first) && first.val is Some((code, key, path)) {
    if result is Object(fields) && fields.contains("$schema") {
      raise Invalid("context.duplicate_entry", path)
    }
    raise Invalid(code, key)
  }
  result
}
