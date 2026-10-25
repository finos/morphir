///|
pub fn fail(code : String, detail : String) -> Json raise CodecError {
  raise Invalid(code, detail)
}

///|
pub fn array(value : Json) -> Array[Json] raise CodecError {
  match value {
    Array(items) => items
    _ => raise Invalid("invalid_type", "Expected array")
  }
}

///|
pub fn tuple(value : Json, length : Int32) -> Array[Json] raise CodecError {
  let items = array(value)
  if items.length() != length {
    raise Invalid("invalid_arity", "Expected \{length} items")
  }
  items
}

///|
pub fn object(value : Json) -> Map[String, Json] raise CodecError {
  match value {
    Object(fields) => fields
    _ => raise Invalid("invalid_type", "Expected object")
  }
}

///|
pub fn string(value : Json) -> String raise CodecError {
  match value {
    String(text) => text
    _ => raise Invalid("invalid_type", "Expected string")
  }
}

///|
pub fn field(value : Json, key : String) -> Json raise CodecError {
  match object(value).get(key) {
    Some(found) => found
    None =>
      raise Invalid(
        if key == "formatVersion" {
          "missing_format_version"
        } else {
          "missing_member"
        },
        key,
      )
  }
}

///|
pub fn optional(value : Json, key : String) -> Json? raise CodecError {
  object(value).get(key)
}

///|
pub fn fields(value : Json, allowed : Array[String]) -> Unit raise CodecError {
  for key, _ in object(value) {
    if !allowed.contains(key) {
      raise Invalid("unknown_member", key)
    }
  }
}

///|
pub fn unit(value : Json) -> Unit raise CodecError {
  match value {
    Null => ()
    Object(fields) if fields.is_empty() => ()
    _ => raise Invalid("invalid_type", "Expected unit attributes")
  }
}

///|
pub fn write_unit(_value : Unit) -> Json {
  Json::object({})
}

///|
pub fn obj(fields : Array[(String, Json)]) -> Json {
  Json::object(Map::from_array(fields))
}

///|
pub fn tag(name : String, payload : Json) -> Json {
  obj([(name, payload)])
}

///|
pub fn text(value : String) -> Json {
  Json::string(value)
}

///|
pub fn number(text : String) -> Json raise CodecError {
  match parse(text) {
    Number(_, ..) as value => value
    _ => raise Invalid("invalid_literal", "Expected number")
  }
}

///|
pub fn number_text(value : Json) -> String raise CodecError {
  match value {
    Number(_, repr=Some(text)) => text
    Number(number, ..) => number.to_string()
    _ => raise Invalid("invalid_type", "Expected number")
  }
}

///|
pub fn integer_text(value : Json) -> String raise CodecError {
  let text = number_text(value)
  if text.contains(".") || text.contains("e") || text.contains("E") {
    raise Invalid("invalid_literal", "Expected integer lexeme")
  }
  text
}

///|
pub fn read_version(value : Json) -> @version.FormatVersion raise {
  match value {
    String(text) => @version.FormatVersion::parse(text)
    Number(_, ..) => {
      let text = number_text(value)
      if text.contains(".") ||
        text.contains("e") ||
        text.contains("E") ||
        text.has_prefix("-") {
        raise Invalid("invalid_format_version_type", text)
      }
      // The exact string parser checks unsigned component bounds.
      if text == "1" {
        @version.FormatVersion::baseline(1U)
      } else if text == "2" {
        @version.FormatVersion::baseline(2U)
      } else {
        @version.FormatVersion::parse(text + ".0.0")
      }
    }
    _ =>
      raise Invalid(
        "invalid_format_version_type", "Expected integer or release string",
      )
  }
}

///|
pub fn write_version(value : @version.FormatVersion) -> Json raise CodecError {
  if value.minor == 0U && value.patch == 0U {
    number(value.major.to_string())
  } else {
    text(value.to_release_string())
  }
}

///|
pub fn read_name(value : Json) -> @common.Name raise {
  match value {
    String(text) => @common.Name::parse(text)
    Array(words) => {
      let words = words.map(string)
      for word in words {
        if word.is_empty() {
          raise Invalid("invalid_name", "Empty legacy word")
        }
        for character in word {
          if !((character >= 'a' && character <= 'z') ||
            (character >= '0' && character <= '9')) {
            raise Invalid("invalid_name", word)
          }
        }
      }
      @common.Name::from_words(words)
    }
    _ => raise Invalid("invalid_name", "Expected name string or word array")
  }
}

///|
pub fn write_name(name : @common.Name) -> Json raise {
  let canonical = name.to_canonical()
  ignore(@common.Name::parse(canonical))
  text(canonical)
}

///|
pub fn write_legacy_name(name : @common.Name) -> Json raise CodecError {
  let words = name.to_words()
  if @common.Name::from_words(words) != name {
    raise Invalid("unsupported_name_downgrade", name.to_canonical())
  }
  Json::array(words.map(text))
}

///|
pub fn read_path(value : Json) -> @common.Path raise {
  match value {
    String(text) => @common.Path::parse(text)
    Array(names) => @common.Path::from_names(names.map(read_name))
    _ => raise Invalid("invalid_name", "Expected path")
  }
}

///|
pub fn write_path(path : @common.Path) -> Json raise {
  let canonical = path.to_canonical()
  ignore(@common.Path::parse(canonical))
  text(canonical)
}

///|
pub fn write_legacy_path(path : @common.Path) -> Json raise {
  Json::array(path.to_names().map(write_legacy_name))
}

///|
pub fn read_fqname(value : Json) -> @common.FQName raise {
  match value {
    String(text) => @common.FQName::parse(text)
    Array(_) => {
      let parts = tuple(value, 3)
      {
        package_name: read_path(parts[0]),
        module_name: read_path(parts[1]),
        local_name: read_name(parts[2]),
      }
    }
    _ => raise Invalid("invalid_name", "Expected FQName")
  }
}

///|
pub fn write_fqname(name : @common.FQName) -> Json raise {
  let canonical = name.to_canonical()
  ignore(@common.FQName::parse(canonical))
  text(canonical)
}

///|
pub fn write_legacy_fqname(name : @common.FQName) -> Json raise {
  Json::array([
    write_legacy_path(name.package_name),
    write_legacy_path(name.module_name),
    write_legacy_name(name.local_name),
  ])
}

///|
pub fn[K : Eq + Hash, V] read_map(
  value : Json,
  key : (Json) -> K raise,
  item : (Json) -> V raise,
) -> Map[K, V] raise {
  let result : Map[K, V] = Map([])
  let entries = match value {
    Object(fields) =>
      fields.iter().collect().map(entry => (text(entry.0), entry.1))
    Array(entries) =>
      entries.map(entry => {
        let pair = tuple(entry, 2)
        (pair[0], pair[1])
      })
    _ => raise Invalid("invalid_type", "Expected map or pair array")
  }
  for (raw_key, raw_value) in entries {
    let decoded = key(raw_key)
    if result.contains(decoded) {
      raise Invalid("duplicate_member", raw_key.stringify())
    }
    result[decoded] = item(raw_value)
  }
  result
}

///|
pub fn[K, V] write_map(
  value : Map[K, V],
  key : (K) -> Json raise,
  item : (V) -> Json raise,
  legacy~ : Bool = false,
) -> Json raise {
  let entries = value
    .iter()
    .collect()
    .map(entry => (key(entry.0), item(entry.1)))
  if legacy {
    entries.sort_by((left, right) => compare_legacy_key(left.0, right.0))
    Json::array(entries.map(entry => Json::array([entry.0, entry.1])))
  } else {
    let fields : Map[String, Json] = Map([])
    for (k, v) in entries {
      fields[string(k)] = v
    }
    Json::object(fields)
  }
}

///|
pub fn boolean(value : Json) -> Bool raise CodecError {
  match value {
    True => true
    False => false
    _ => raise Invalid("invalid_literal", "Expected boolean")
  }
}

///|
pub fn character(value : Json) -> Char raise CodecError {
  let chars = string(value).iter().collect()
  if chars.length() != 1 {
    raise Invalid("invalid_literal", "Expected one Unicode scalar")
  }
  chars[0]
}

///|
pub fn float(value : Json) -> Double raise CodecError {
  match value {
    Number(number, repr~) if !number.is_nan() && !number.is_inf() => {
      if number == 0.0 && repr is Some(text) {
        for character in text {
          if character is ('e' | 'E') {
            break
          }
          if character >= '1' && character <= '9' {
            raise Invalid("invalid_literal", "Nonzero float underflows to zero")
          }
        }
      }
      number
    }
    _ => raise Invalid("invalid_literal", "Expected finite float")
  }
}

///|
/// Decimal grammar is broader than JSON number syntax, but never coerces the lexeme.
pub fn decimal(value : Json) -> String raise CodecError {
  let text = match value {
    String(text) => text
    _ => raise Invalid("invalid_literal", "Decimal requires a string")
  }
  let chars = text.iter().collect()
  let mut i = 0
  if i < chars.length() && (chars[i] == '+' || chars[i] == '-') {
    i += 1
  }
  let start = i
  while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
    i += 1
  }
  let mut digits = i - start
  if i < chars.length() && chars[i] == '.' {
    i += 1
    let fractional = i
    while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
      i += 1
    }
    digits += i - fractional
  }
  if digits == 0 {
    raise Invalid("invalid_literal", "Invalid decimal lexeme")
  }
  if i < chars.length() && (chars[i] == 'e' || chars[i] == 'E') {
    i += 1
    if i < chars.length() && (chars[i] == '+' || chars[i] == '-') {
      i += 1
    }
    let exponent = i
    while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
      i += 1
    }
    if exponent == i {
      raise Invalid("invalid_literal", "Invalid decimal exponent")
    }
  }
  if i != chars.length() {
    raise Invalid("invalid_literal", "Invalid decimal lexeme")
  }
  text
}

///|
pub fn nullable_string(value : Json) -> String? raise CodecError {
  match value {
    Null => None
    _ => Some(string(value))
  }
}

///|
pub fn write_nullable_string(value : String?) -> Json {
  match value {
    None => Json::null()
    Some(text) => Json::string(text)
  }
}

///|
pub fn read_data(value : Json) -> @common.Data {
  match value {
    Null => @common.Data::Null
    True => @common.Boolean(true)
    False => @common.Boolean(false)
    String(text) => @common.Text(text)
    Number(number, repr~) =>
      @common.Number(repr.unwrap_or_else(() => number.to_string()))
    Array(items) => @common.Array(items.map(read_data))
    Object(fields) => @common.Object(fields.map((_, value) => read_data(value)))
  }
}

///|
#warnings("-unused_error_type")
pub fn write_data(value : @common.Data) -> Json raise {
  match value {
    Null => Json::null()
    Boolean(value) => Json(value)
    Text(text) => Json::string(text)
    Number(text) => number(text)
    Array(items) => Json::array(items.map(write_data))
    Object(fields) => write_map(fields, fn(key) raise { text(key) }, write_data)
  }
}

///|
/// Transform a map while preserving keys and propagating conversion failures.
pub fn[K : Eq + Hash, V, W] map_values(
  source : Map[K, V],
  convert : (V) -> W raise,
) -> Map[K, W] raise {
  let result : Map[K, W] = Map([])
  for key, value in source {
    result[key] = convert(value)
  }
  result
}

///|
/// Stable diagnostic codes for codec, name and release errors.
pub fn diagnostic(error : Error) -> String {
  match error {
    Invalid(code, _) => code
    @common.InvalidName(_) => "invalid_name"
    @version.InvalidSyntax(_) => "invalid_format_version_syntax"
    @version.OutOfRange(_) => "format_version_out_of_range"
    @version.UnsupportedMajor(_) => "unsupported_format_version_major"
    @version.UnsupportedMinor(_, _) => "unsupported_format_version_minor"
    @version.FamilyMismatch(_, _) => "format_version_family_mismatch"
    @version.SpecsBefore3_1 => "unsupported_distribution_version"
    _ => "unknown_error"
  }
}

///|
pub fn write_integer(value : String) -> Json raise CodecError {
  let result = number(value)
  ignore(integer_text(result))
  result
}

///|
pub fn write_float(value : Double) -> Json raise CodecError {
  let result = if value.reinterpret_as_uint64() == 9223372036854775808UL {
    Json::number(value, repr="-0.0")
  } else {
    Json(value)
  }
  ignore(float(result))
  result
}

///|
/// Elm Dict orders names and paths lexicographically by their legacy word lists.
fn compare_legacy_key(left : Json, right : Json) -> Int32 {
  match (left, right) {
    (String(left), String(right)) => left.compare(right)
    (Array(left), Array(right)) => {
      let length = if left.length() < right.length() {
        left.length()
      } else {
        right.length()
      }
      for i = 0; i < length; i = i + 1 {
        let order = compare_legacy_key(left[i], right[i])
        if order != 0 {
          return order
        }
      }
      left.length().compare(right.length())
    }
    _ => left.stringify().compare(right.stringify())
  }
}
