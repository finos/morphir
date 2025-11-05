///|
pub(all) suberror JsonDecodeError (@json.JsonPath, String) derive (
  Eq,
  Show,
  ToJson,
)

///|
pub(open) trait FromMorphirJson {
  from_json(Json, @json.JsonPath, MorphirJsonOptions) -> Self raise JsonDecodeError
}

///|
pub fn[A : FromMorphirJson] from_json(
  json : Json,
  path : @json.JsonPath,
  options? : MorphirJsonOptions = Default::default(),
) -> A raise JsonDecodeError {
  A::from_json(json, path, options)
}

///|
pub fn[T] decode_error(
  path : @json.JsonPath,
  msg : String,
) -> T raise JsonDecodeError {
  raise JsonDecodeError((path, msg))
}

///|
pub impl FromMorphirJson for Bool with from_json(
  json : Json,
  path : @json.JsonPath,
  _ : MorphirJsonOptions,
) -> Bool raise JsonDecodeError {
  match json {
    true => true
    false => false
    _ => decode_error(path, "Bool::from_json: expected boolean")
  }
}

///|
pub impl FromMorphirJson for String with from_json(
  json : Json,
  path : @json.JsonPath,
  _ : MorphirJsonOptions,
) -> String raise JsonDecodeError {
  guard json is String(s) else {
    decode_error(path, "String::from_json: expected string")
  }
  s
}

///|
pub impl FromMorphirJson for StringView with from_json(
  json : Json,
  path : @json.JsonPath,
  _ : MorphirJsonOptions,
) -> StringView raise JsonDecodeError {
  guard json is String(s) else {
    decode_error(path, "StringView::from_json: expected string")
  }
  s[:]
}

///|
pub impl FromMorphirJson for Json with from_json(
  json : Json,
  _ : @json.JsonPath,
  _ : MorphirJsonOptions,
) -> Json raise JsonDecodeError {
  json
}
