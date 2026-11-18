///|
fn field_text(value : Json, key : String) -> String raise @wire.CodecError {
  @wire.string(@wire.field(value, key))
}

///|
fn field_identity(value : Json, key : String) -> String raise @wire.CodecError {
  let text = field_text(value, key)
  guard !text.is_empty() else {
    raise @wire.Invalid("model_access.invalid_identity", key)
  }
  text
}

///|
fn field_optional_identity(
  value : Json,
  key : String,
) -> String? raise @wire.CodecError {
  match @wire.optional(value, key) {
    None => None
    Some(_) => Some(field_identity(value, key))
  }
}

///|
fn field_digest(value : Json, key : String) -> String raise @wire.CodecError {
  let hex = field_text(value, key)
  guard hex.length() == 64 &&
    hex.iter().all(ch => (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f')) else {
    raise @wire.Invalid("model_access.invalid_digest", key)
  }
  hex
}

///|
fn field_integer(
  value : Json,
  key : String,
  min~ : Int64,
  max~ : Int64,
) -> Int64 raise @wire.CodecError {
  let number = @strconv.parse_int64(@wire.integer_text(@wire.field(value, key))) catch {
    _ => raise @wire.Invalid("model_access.invalid_integer", key)
  }
  guard number >= min && number <= max else {
    raise @wire.Invalid("model_access.invalid_integer", key)
  }
  number
}

///|
fn field_int32(
  value : Json,
  key : String,
  minimum : Int64,
) -> Int32 raise @wire.CodecError {
  field_integer(value, key, min=minimum, max=2147483647L).to_int()
}

///|
fn integer_json(number : Int64) -> Json {
  Json::number(number.to_double(), repr=number.to_string())
}

///|
fn forbid_fields(
  value : Json,
  names : Array[String],
) -> Unit raise @wire.CodecError {
  let fields = @wire.object(value)
  for name in names {
    guard !fields.contains(name) else {
      raise @wire.Invalid("model_access.invalid_variant", name)
    }
  }
}
