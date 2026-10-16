///|
fn schema_fields(value : @ion.IonValue) -> Map[String, @ion.IonValue] raise {
  let fields = match value.kind() {
    Struct(fields) => fields
    _ => raise Invalid("data.invalid_profile", "Expected a struct")
  }
  let result : Map[String, @ion.IonValue] = Map([])
  for field in fields {
    let name = match field.name().text() {
      Some(text) => text
      None => raise Invalid("data.symbol_catalog_missing", "Schema field name")
    }
    if result.contains(name) {
      raise Invalid("data.duplicate_field", name)
    }
    result[name] = field.value()
  }
  result
}

///|
fn field(
  fields : Map[String, @ion.IonValue],
  name : String,
) -> @ion.IonValue raise BoundaryError {
  match fields.get(name) {
    Some(value) => value
    None => raise Invalid("data.missing_field", name)
  }
}

///|
fn string_field(
  fields : Map[String, @ion.IonValue],
  name : String,
) -> String raise {
  let value = field(fields, name)
  if value.has_annotations() {
    raise Invalid("data.profile_value_unsupported", name)
  }
  match value.kind() {
    String(text) => text
    _ => raise Invalid("data.invalid_profile", name)
  }
}

///|
fn read_envelope(
  value : @ion.IonValue,
  unit_id : String,
  limits : Limits,
) -> IRUnit raise {
  check_tree(value, limits)
  let annotations = value.annotations()
  if !annotations.any(token => token.text() == Some("morphir_pipeline")) {
    raise Invalid(
      "data.profile_mismatch", "Missing morphir_pipeline annotation",
    )
  }
  let fields = schema_fields(value)
  if string_field(fields, "profile") != PROFILE ||
    string_field(fields, "contract") != "ir-unit" {
    raise Invalid("data.profile_mismatch", "Unsupported profile or contract")
  }
  for name, _ in fields {
    if !["profile", "contract", "unit_id", "ir", "metadata", "provenance"].contains(
        name,
      ) {
      raise Invalid("data.unknown_field", name)
    }
  }
  let id = string_field(fields, "unit_id")
  if id != unit_id {
    raise Invalid("data.unit_mismatch", id)
  }
  let metadata = match field(fields, "metadata").kind() {
    List(items) => {
      let result : Array[NodeMetadata] = []
      for item in items {
        if item.has_annotations() {
          raise Invalid("data.profile_value_unsupported", "metadata entry")
        }
        let fields = schema_fields(item)
        for name, _ in fields {
          if !["node_id", "data"].contains(name) {
            raise Invalid("data.unknown_field", name)
          }
        }
        result.push({
          node_id: string_field(fields, "node_id"),
          data: field(fields, "data"),
        })
      }
      result
    }
    _ => raise Invalid("data.invalid_profile", "metadata must be a list")
  }
  if field(fields, "metadata").has_annotations() {
    raise Invalid("data.profile_value_unsupported", "metadata list")
  }
  let distribution = @migration.to_current(
    @versioned_json.from_json(read_semantic_ir(field(fields, "ir"))),
  )
  let provenance = match fields.get("provenance") {
    None => []
    Some(value) if !value.has_annotations() =>
      match value.kind() {
        List(values) => values
        _ => raise Invalid("data.invalid_profile", "provenance must be a list")
      }
    _ => raise Invalid("data.profile_value_unsupported", "provenance list")
  }
  { id, distribution, metadata, annotations, provenance, }
}

///|
fn write_envelope(unit : IRUnit, limits : Limits) -> @ion.IonValue raise {
  if unit.id == "" {
    raise Invalid("data.invalid_identity", "Empty unit ID")
  }
  if !unit.annotations.any(token => token.text() == Some("morphir_pipeline")) {
    raise Invalid(
      "data.profile_mismatch", "Missing morphir_pipeline annotation",
    )
  }
  let seen : Map[String, Bool] = Map([])
  let entries : Array[@ion.IonValue] = []
  for item in unit.metadata {
    if item.node_id == "" || seen.contains(item.node_id) {
      raise Invalid("data.invalid_identity", item.node_id)
    }
    seen[item.node_id] = true
    entries.push(
      @ion.IonValue::from_fields([
        @ion.Field::new("node_id", @ion.IonValue::string(item.node_id)),
        @ion.Field::new("data", item.data),
      ]),
    )
  }
  let value = @ion.IonValue::from_fields([
    @ion.Field::new("profile", @ion.IonValue::string(PROFILE)),
    @ion.Field::new("provenance", @ion.IonValue::list(unit.provenance)),
    @ion.Field::new("contract", @ion.IonValue::string("ir-unit")),
    @ion.Field::new("unit_id", @ion.IonValue::string(unit.id)),
    @ion.Field::new(
      "ir",
      write_semantic_ir(@ir_json.to_json(unit.distribution)),
    ),
    @ion.Field::new("metadata", @ion.IonValue::list(entries)),
  ]).with_annotations(unit.annotations)
  check_tree(value, limits)
  value
}

///|
/// The current semantic IR has a JSON-shaped schema. This mapping reuses its
/// validated versioned codecs without routing rich metadata through JSON.
/// Integers are native Ion ints; noncanonical/exponent numeric lexemes use an
/// explicit tagged string so spelling and decimal scale cannot be lost.
fn write_semantic_ir(value : Json) -> @ion.IonValue raise {
  match value {
    Null => @ion.IonValue::untyped_null()
    True => @ion.IonValue::bool(true)
    False => @ion.IonValue::bool(false)
    String(text) => @ion.IonValue::string(text)
    Number(_, ..) => {
      let lexeme = @wire.number_text(value)
      if !lexeme.contains(".") &&
        !lexeme.contains("e") &&
        !lexeme.contains("E") &&
        lexeme != "-0" {
        @ion_text.read_ion(lexeme[:])
      } else {
        @ion.IonValue::string(lexeme).with_annotation(
          @ion.SymbolToken::new("morphir_json_number"),
        )
      }
    }
    Array(items) => @ion.IonValue::list(items.map(write_semantic_ir))
    Object(fields) => {
      let names = fields.keys().collect()
      names.sort()
      @ion.IonValue::from_fields(
        names.map(name => @ion.Field::new(name, write_semantic_ir(fields[name]))),
      )
    }
  }
}

///|
fn read_semantic_ir(value : @ion.IonValue) -> Json raise {
  let annotations = value.annotations()
  if !annotations.is_empty() {
    if annotations.length() == 1 &&
      annotations[0].text() == Some("morphir_json_number") &&
      value.kind() is String(lexeme) {
      return @wire.number(lexeme)
    }
    raise Invalid(
      "data.profile_value_unsupported", "Semantic IR annotations must be represented as node metadata",
    )
  }
  match value.kind() {
    Null(@ion.Null) => Json::null()
    Bool(value) => Json(value)
    Int(value) => @wire.number(value.to_string())
    Float(value) => {
      let json = Json(value)
      ignore(@wire.float(json))
      json
    }
    String(text) => Json::string(text)
    List(items) => Json::array(items.map(read_semantic_ir))
    Struct(_) => {
      let fields = schema_fields(value)
      let result : Map[String, Json] = Map([])
      for name, item in fields {
        result[name] = read_semantic_ir(item)
      }
      Json::object(result)
    }
    _ =>
      raise Invalid(
        "data.profile_value_unsupported", "Use the semantic IR schema or the rich node metadata field",
      )
  }
}

///|
fn check_tree(
  value : @ion.IonValue,
  limits : Limits,
) -> Unit raise BoundaryError {
  let pending = [(value, 0)]
  let mut count = 0
  while pending.pop() is Some((value, depth)) {
    count += 1 + value.annotations().length()
    if depth > limits.max_depth {
      raise Invalid(
        "data.tree_limit",
        "Depth exceeds the limit of \{limits.max_depth}",
      )
    }
    if count > limits.max_values {
      raise Invalid(
        "data.tree_limit",
        "Value count exceeds the limit of \{limits.max_values}",
      )
    }
    for token in value.annotations() {
      check_symbol(token)
    }
    match value.kind() {
      String(text) => check_unicode(text)
      Symbol(token) => check_symbol(token)
      List(items) | Sexp(items) =>
        for item in items {
          pending.push((item, depth + 1))
        }
      Struct(fields) =>
        for item in fields {
          check_symbol(item.name())
          pending.push((item.value(), depth + 1))
        }
      _ => ()
    }
  }
}

///|
fn check_symbol(token : @ion.SymbolToken) -> Unit raise BoundaryError {
  match token.text() {
    Some(text) => check_unicode(text)
    None if token.import_location is Some(_) =>
      raise Invalid("data.symbol_catalog_missing", "Unresolved imported symbol")
    None => ()
  }
}

///|
/// Refuse invalid Unicode rather than letting UTF-8 publication replace it.
fn check_unicode(text : String) -> Unit raise BoundaryError {
  let units = text.code_units()
  let mut index = 0
  while index < units.length() {
    if units[index].is_leading_surrogate() {
      if index + 1 >= units.length() ||
        !units[index + 1].is_trailing_surrogate() {
        raise Invalid("data.unrepresentable_text", "Isolated UTF-16 surrogate")
      }
      index += 1
    } else if units[index].is_trailing_surrogate() {
      raise Invalid("data.unrepresentable_text", "Isolated UTF-16 surrogate")
    }
    index += 1
  }
}
