///|
/// Stable diagnostic code and detail. Callers need not parse error prose.
pub(all) suberror CodecError {
  Invalid(String, String)
} derive(Eq, Debug)

///|
pub extend CodecError with Eq::{equal, not_equal}

///|
pub extend CodecError with @debug.Debug::{to_repr}

///|
priv struct Reader {
  chars : Array[Char]
  mut index : Int32
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
        String(value) => value
        _ => raise Invalid("invalid_json", "Expected string")
      }
    }
  }
  raise Invalid("invalid_json", "Unterminated string")
}

///|
fn Reader::value(self : Reader, depth : Int32) -> Json raise CodecError {
  self.space()
  if depth > 512 || self.index >= self.chars.length() {
    raise Invalid("invalid_json", "Depth limit or unexpected end of input")
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
        if fields.contains(key) {
          raise Invalid(
            if key == "formatVersion" && depth == 0 {
              "duplicate_format_version"
            } else {
              "duplicate_member"
            },
            key,
          )
        }
        self.take(':')
        fields[key] = self.value(depth + 1)
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
        items.push(self.value(depth + 1))
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
/// Reject duplicate members and preserve every numeric lexeme before decoding IR.
pub fn parse(text : String) -> Json raise CodecError {
  let reader = Reader::{ chars: text.iter().collect(), index: 0, }
  let result = reader.value(0)
  reader.space()
  if reader.index != reader.chars.length() {
    raise Invalid("invalid_json", "Trailing input")
  }
  result
}
