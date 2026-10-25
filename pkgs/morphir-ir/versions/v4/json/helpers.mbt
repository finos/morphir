///|
fn variant(json : Json) -> (String, Json) raise {
  let fields = @wire.object(json)
  if fields.length() != 1 {
    raise @wire.Invalid("invalid_type", "Expected one variant tag")
  }
  fields.iter().collect()[0]
}

///|
fn optional_object(json : Json, key : String) -> Json raise {
  @wire.optional(json, key).unwrap_or(Json::object(Map([])))
}

///|
fn optional_array(json : Json, key : String) -> Json raise {
  @wire.optional(json, key).unwrap_or(Json::array([]))
}

///|
fn[T] read_optional(
  json : Json,
  key : String,
  decode : (Json) -> T raise,
) -> T? raise {
  match @wire.optional(json, key) {
    None => None
    Some(value) => Some(decode(value))
  }
}

///|
fn read_source(json : Json) -> @model.SourceLocation raise {
  @wire.fields(json, ["startLine", "startColumn", "endLine", "endColumn"])
  fn component(key) raise {
    let text = @wire.integer_text(@wire.field(json, key))
    let value = @wire.float(@wire.number(text))
    if value < 1 || value > 2147483647 {
      raise @wire.Invalid("invalid_source_location", key)
    }
    value.to_int()
  }
  {
    start_line: component("startLine"),
    start_column: component("startColumn"),
    end_line: component("endLine"),
    end_column: component("endColumn"),
  }
}

///|
fn write_source(source : @model.SourceLocation) -> Json raise {
  let json = @wire.obj([
    ("startLine", Json(source.start_line)),
    ("startColumn", Json(source.start_column)),
    ("endLine", Json(source.end_line)),
    ("endColumn", Json(source.end_column)),
  ])
  ignore(read_source(json))
  json
}

///|
fn attr_payload(payload : Json) -> Json raise {
  match payload {
    Object(fields) => {
      if fields.contains("attributes") && fields.contains("attrs") {
        raise @wire.Invalid("duplicate_member", "attributes/attrs")
      }
      fields
      .get("attributes")
      .unwrap_or_else(() => fields.get("attrs").unwrap_or(Json::object(Map([]))))
    }
    _ => Json::object(Map([]))
  }
}

///|
pub fn read_type_attributes(json : Json) -> @model.TypeAttributes raise {
  @wire.fields(json, ["source", "constraints", "extensions"])
  {
    source: read_optional(json, "source", read_source),
    constraints: @wire.object(optional_object(json, "constraints")).map((
      _,
      value,
    ) => @wire.read_data(value)),
    extensions: @wire.object(optional_object(json, "extensions")).map((_, value) => {
      @wire.read_data(value)
    }),
  }
}

///|
pub fn write_type_attributes(value : @model.TypeAttributes) -> Json raise {
  let fields : Array[(String, Json)] = []
  if value.source is Some(source) {
    fields.push(("source", write_source(source)))
  }
  if !value.constraints.is_empty() {
    fields.push(
      ("constraints", @wire.write_data(@model.Data::Object(value.constraints))),
    )
  }
  if !value.extensions.is_empty() {
    fields.push(
      ("extensions", @wire.write_data(@model.Data::Object(value.extensions))),
    )
  }
  @wire.obj(fields)
}

///|
pub fn read_value_attributes(json : Json) -> @model.ValueAttributes raise {
  @wire.fields(json, ["source", "inferredType", "extensions"])
  {
    source: read_optional(json, "source", read_source),
    inferred_type: read_optional(json, "inferredType", read_type),
    extensions: @wire.object(optional_object(json, "extensions")).map((_, value) => {
      @wire.read_data(value)
    }),
  }
}

///|
pub fn write_value_attributes(value : @model.ValueAttributes) -> Json raise {
  let fields : Array[(String, Json)] = []
  if value.source is Some(source) {
    fields.push(("source", write_source(source)))
  }
  if value.inferred_type is Some(tpe) {
    fields.push(("inferredType", write_type(tpe)))
  }
  if !value.extensions.is_empty() {
    fields.push(
      ("extensions", @wire.write_data(@model.Data::Object(value.extensions))),
    )
  }
  @wire.obj(fields)
}

///|
fn payload_fields(payload : Json, keys : Array[String]) -> Unit raise {
  @wire.fields(payload, keys + ["attributes", "attrs"])
}

///|
fn alias_field(
  json : Json,
  canonical : String,
  aliases : Array[String],
) -> Json raise {
  let found : Array[Json] = []
  for key in [canonical] + aliases {
    if @wire.optional(json, key) is Some(value) {
      found.push(value)
    }
  }
  if found.length() != 1 {
    raise @wire.Invalid("invalid_member", canonical)
  }
  found[0]
}

///|
fn name_key(name : @model.Name) -> Json raise {
  ignore(@wire.read_name(@wire.write_name(name)))
  @wire.write_name(name)
}

///|
fn path_key(path : @model.Path) -> Json raise {
  ignore(@wire.read_path(@wire.write_path(path)))
  @wire.write_path(path)
}

///|
fn expanded(
  tag : String,
  attributes : Json,
  fields : Array[(String, Json)],
) -> Json {
  let result : Array[(String, Json)] = []
  if attributes != Json::object(Map([])) {
    result.push(("attributes", attributes))
  }
  result.append(fields)
  @wire.tag(tag, @wire.obj(result))
}
