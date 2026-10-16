///|
fn fields(
  value : @ion.IonValue,
  owner : String,
) -> Map[String, @ion.IonValue] raise {
  guard value.kind() is Struct(entries) else {
    raise Invalid("metadata.invalid_object", owner, "Expected an Ion struct")
  }
  let result = Map([])
  for entry in entries {
    guard entry.name().text() is Some(key) else {
      raise Invalid(
        "metadata.symbol_catalog_missing", owner, "Resolve field symbols before interpretation",
      )
    }
    if result.contains(key) {
      raise Invalid(
        "metadata.duplicate_field",
        owner,
        "Duplicate field '" + key + "'; retain one unambiguous value",
      )
    }
    result[key] = entry.value()
  }
  result
}

///|
fn required(
  values : Map[String, @ion.IonValue],
  key : String,
  owner : String,
) -> @ion.IonValue raise {
  guard values.get(key) is Some(value) else {
    raise Invalid(
      "metadata.missing_field",
      owner,
      "Supply required field '" + key + "'",
    )
  }
  value
}

///|
fn text(value : @ion.IonValue, owner : String) -> String raise {
  guard value.annotations().is_empty() && value.kind() is String(result) else {
    raise Invalid(
      "metadata.invalid_string", owner, "Expected an unannotated string",
    )
  }
  result
}

///|
pub fn valid_language_id(value : String) -> Bool {
  let parts = value.split("-").collect()
  if parts.is_empty() || parts.any(p => p.is_empty()) {
    return false
  }
  let first = value.to_array()[0]
  if first < 'a' || first > 'z' {
    return false
  }
  parts.all(p => {
    p.iter().all(c => (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))
  })
}

///|
/// One closed typed data object, with both maps required. Empty maps are valid.
pub fn TargetNames::from_ion(
  value : @ion.IonValue,
  owner~ : String = "targetNames",
  language_ids~ : Bool = true,
) -> TargetNames raise {
  if !value.annotations().is_empty() {
    raise Invalid(
      "metadata.invalid_data", owner, "TargetNames must be plain typed @json data",
    )
  }
  let record = fields(value, owner)
  if record.length() != 2 ||
    !record.contains("frontend") ||
    !record.contains("backend") {
    raise Invalid(
      "metadata.invalid_target_names", owner, "Supply exactly frontend and backend maps; use empty maps when no spelling is supplied",
    )
  }
  fn names(value : @ion.IonValue, role : String) -> Map[String, String] raise {
    if !value.annotations().is_empty() {
      raise Invalid(
        "metadata.invalid_data", owner, "Language maps must be unannotated objects",
      )
    }
    let result = Map([])
    for language, value in fields(value, owner + "/" + role) {
      if language_ids && !valid_language_id(language) {
        raise Invalid(
          "metadata.invalid_language_id",
          owner,
          "Language ID '" +
          language +
          "' must match ^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$",
        )
      }
      result[language] = text(value, owner + "/" + role + "/" + language)
    }
    result
  }
  {
    frontend: names(record["frontend"], "frontend"),
    backend: names(record["backend"], "backend"),
  }
}

///|
fn digest(value : String) -> Bool {
  value.length() == 64 &&
  value.to_array().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
}
