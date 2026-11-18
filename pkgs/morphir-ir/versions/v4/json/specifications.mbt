///|
pub fn read_annotation(json : Json) -> @model.Annotation raise {
  read_annotation_with_context(json, None)
}

///|
fn read_annotation_with_context(
  json : Json,
  context : @wire.DocumentNameContext?,
  preserve_input_order~ : Bool = false,
) -> @model.Annotation raise {
  match json {
    String(text) => {
      let parts = text.split(":").map(part => part.to_owned()).collect()
      if parts.length() < 2 {
        raise @wire.Invalid("invalid_name", text)
      }
      let name = @model.FQName::parse(parts[0] + ":" + parts[1])
      let text = if parts.length() > 2 {
        Some(parts[2:].iter().collect().join(":"))
      } else {
        None
      }
      @model.Compact(name, text)
    }
    _ => {
      @wire.fields(json, ["name", "arguments"])
      @model.Structured(
        @wire.read_context_fqname(@wire.field(json, "name"), context),
        @wire.array(optional_array(json, "arguments")).map(argument => {
          match argument {
            Object(fields) if fields.contains("name") &&
              fields.contains("value") => {
              @wire.fields(argument, ["name", "value"])
              @model.Named(
                @wire.read_context_name(@wire.field(argument, "name"), context),
                read_value_with_context(
                  @wire.field(argument, "value"),
                  context,
                  preserve_input_order~,
                ),
              )
            }
            _ =>
              @model.Positional(
                read_value_with_context(
                  argument,
                  context,
                  preserve_input_order~,
                ),
              )
          }
        }),
      )
    }
  }
}

///|
pub fn write_annotation(annotation : @model.Annotation) -> Json raise {
  match annotation {
    Compact(name, text) => {
      ignore(@wire.write_fqname(name))
      @wire.text(
        name.to_canonical() +
        (match text {
          None => ""
          Some(text) => ":" + text
        }),
      )
    }
    Structured(name, arguments) => {
      let fields = [("name", @wire.write_fqname(name))]
      if !arguments.is_empty() {
        fields.push(
          (
            "arguments",
            Json::array(
              arguments.map(argument => {
                match argument {
                  Positional(value) => write_value(value)
                  Named(name, value) =>
                    @wire.obj([
                      ("name", @wire.write_name(name)),
                      ("value", write_value(value)),
                    ])
                }
              }),
            ),
          ),
        )
      }
      @wire.obj(fields)
    }
  }
}

///|
fn read_annotations(
  json : Json,
  context : @wire.DocumentNameContext?,
  preserve_input_order~ : Bool = false,
) -> Array[@model.Annotation] raise {
  @wire.array(optional_array(json, "annotations")).map(child => {
    read_annotation_with_context(child, context, preserve_input_order~)
  })
}

///|
fn put_annotations(
  fields : Array[(String, Json)],
  annotations : Array[@model.Annotation],
) -> Unit raise {
  if !annotations.is_empty() {
    fields.push(("annotations", Json::array(annotations.map(write_annotation))))
  }
}

///|
fn read_params(
  payload : Json,
  context : @wire.DocumentNameContext?,
) -> Array[@model.Name] raise {
  @wire.array(optional_array(payload, "typeParams")).map(child => {
    @wire.read_context_name(child, context)
  })
}

///|
fn read_constructors(
  json : Json,
  context : @wire.DocumentNameContext?,
) -> @model.Constructors raise {
  let read_name = fn(child) raise { @wire.read_context_name(child, context) }
  @wire.read_map(json, read_name, child => {
    read_typed_pair_inputs(child, context)
  })
}

///|
fn write_constructors(constructors : @model.Constructors) -> Json raise {
  // Constructor parameters have a pair-array wire form in v4.
  @wire.write_map(constructors, name_key, fn(parameters) raise {
    Json::array(
      parameters.map(parameter => {
        Json::array([name_key(parameter.0), write_type(parameter.1)])
      }),
    )
  })
}

///|
pub fn read_type_specification(json : Json) -> @model.TypeSpecification raise {
  read_type_specification_with_context(json, None)
}

///|
pub fn read_type_specification_with_context(
  json : Json,
  context : @wire.DocumentNameContext?,
  preserve_input_order~ : Bool = false,
) -> @model.TypeSpecification raise {
  let (tag, payload) = match json {
    Array(items) => {
      if items.length() < 2 {
        raise @wire.Invalid("invalid_arity", "Type specification")
      }
      let tag = @wire.string(items[0])
      let fields = [("typeParams", items[1])]
      if tag == "OpaqueTypeSpecification" {
        ignore(@wire.tuple(json, 2))
      } else {
        ignore(@wire.tuple(json, 3))
        match tag {
          "TypeAliasSpecification" => fields.push(("typeExp", items[2]))
          "CustomTypeSpecification" => fields.push(("constructors", items[2]))
          "DerivedTypeSpecification" =>
            fields.append(@wire.object(items[2]).iter().collect())
          _ => raise @wire.Invalid("unknown_node", tag)
        }
      }
      (tag, @wire.obj(fields))
    }
    _ => variant(json)
  }
  let annotations = read_annotations(payload, context, preserve_input_order~)
  let params = read_params(payload, context)
  let body = match tag {
    "TypeAliasSpecification" => {
      @wire.fields(payload, ["annotations", "typeParams", "typeExp"])
      ignore(@wire.field(payload, "typeParams"))
      @model.TypeAliasSpecification(
        params,
        read_type_with_context(@wire.field(payload, "typeExp"), context),
      )
    }
    "OpaqueTypeSpecification" => {
      @wire.fields(payload, ["annotations", "typeParams"])
      @model.OpaqueTypeSpecification(params)
    }
    "CustomTypeSpecification" => {
      @wire.fields(payload, ["annotations", "typeParams", "constructors"])
      ignore(@wire.field(payload, "typeParams"))
      @model.CustomTypeSpecification(
        params,
        read_constructors(@wire.field(payload, "constructors"), context),
      )
    }
    "DerivedTypeSpecification" => {
      @wire.fields(payload, [
        "annotations", "typeParams", "baseType", "fromBaseType", "toBaseType",
      ])
      ignore(@wire.field(payload, "typeParams"))
      @model.DerivedTypeSpecification(params, {
        base_type: read_type_with_context(
          @wire.field(payload, "baseType"),
          context,
        ),
        from_base_type: @wire.read_context_fqname(
          @wire.field(payload, "fromBaseType"),
          context,
        ),
        to_base_type: @wire.read_context_fqname(
          @wire.field(payload, "toBaseType"),
          context,
        ),
      })
    }
    _ => raise @wire.Invalid("unknown_node", tag)
  }
  { annotations, body, }
}

///|
pub fn write_type_specification(
  specification : @model.TypeSpecification,
) -> Json raise {
  let fields : Array[(String, Json)] = []
  put_annotations(fields, specification.annotations)
  let tag = match specification.body {
    TypeAliasSpecification(params, body) => {
      fields.append([
        ("typeParams", Json::array(params.map(name_key))),
        ("typeExp", write_type(body)),
      ])
      "TypeAliasSpecification"
    }
    OpaqueTypeSpecification(params) => {
      if !params.is_empty() {
        fields.push(("typeParams", Json::array(params.map(name_key))))
      }
      "OpaqueTypeSpecification"
    }
    CustomTypeSpecification(params, constructors) => {
      fields.append([
        ("typeParams", Json::array(params.map(name_key))),
        ("constructors", write_constructors(constructors)),
      ])
      "CustomTypeSpecification"
    }
    DerivedTypeSpecification(params, details) => {
      fields.append([
        ("typeParams", Json::array(params.map(name_key))),
        ("baseType", write_type(details.base_type)),
        ("fromBaseType", @wire.write_fqname(details.from_base_type)),
        ("toBaseType", @wire.write_fqname(details.to_base_type)),
      ])
      "DerivedTypeSpecification"
    }
  }
  @wire.tag(tag, @wire.obj(fields))
}

///|
pub fn read_type_definition(json : Json) -> @model.TypeDefinition raise {
  read_type_definition_with_context(json, None)
}

///|
pub fn read_type_definition_with_context(
  json : Json,
  context : @wire.DocumentNameContext?,
) -> @model.TypeDefinition raise {
  let (tag, payload) = variant(json)
  let params = @wire.array(@wire.field(payload, "typeParams")).map(child => {
    @wire.read_context_name(child, context)
  })
  match tag {
    "TypeAliasDefinition" => {
      @wire.fields(payload, ["typeParams", "typeExp"])
      @model.TypeAliasDefinition(
        params,
        read_type_with_context(@wire.field(payload, "typeExp"), context),
      )
    }
    "CustomTypeDefinition" => {
      @wire.fields(payload, ["typeParams", "access", "constructors"])
      let access = read_access_level(@wire.field(payload, "access"))
      @model.CustomTypeDefinition(params, {
        access,
        value: read_constructors(@wire.field(payload, "constructors"), context),
      })
    }
    "IncompleteTypeDefinition" => {
      @wire.fields(payload, ["typeParams", "incompleteness", "partialTypeExp"])
      @model.IncompleteTypeDefinition(
        params,
        read_incompleteness_with_context(
          @wire.field(payload, "incompleteness"),
          context,
        ),
        read_optional(payload, "partialTypeExp", child => {
          read_type_with_context(child, context)
        }),
      )
    }
    _ => raise @wire.Invalid("unknown_node", tag)
  }
}

///|
pub fn write_type_definition(value : @model.TypeDefinition) -> Json raise {
  match value {
    TypeAliasDefinition(params, body) =>
      @wire.tag(
        "TypeAliasDefinition",
        @wire.obj([
          ("typeParams", Json::array(params.map(name_key))),
          ("typeExp", write_type(body)),
        ]),
      )
    CustomTypeDefinition(params, constructors) =>
      @wire.tag(
        "CustomTypeDefinition",
        @wire.obj([
          ("typeParams", Json::array(params.map(name_key))),
          ("access", write_access_level(constructors.access)),
          ("constructors", write_constructors(constructors.value)),
        ]),
      )
    IncompleteTypeDefinition(params, incompleteness, partial) => {
      let fields = [
        ("typeParams", Json::array(params.map(name_key))),
        ("incompleteness", write_incompleteness(incompleteness)),
      ]
      if partial is Some(tpe) {
        fields.push(("partialTypeExp", write_type(tpe)))
      }
      @wire.tag("IncompleteTypeDefinition", @wire.obj(fields))
    }
  }
}

///|
pub fn read_value_specification(json : Json) -> @model.ValueSpecification raise {
  read_value_specification_with_context(json, None)
}

///|
pub fn read_value_specification_with_context(
  json : Json,
  context : @wire.DocumentNameContext?,
  preserve_input_order~ : Bool = false,
) -> @model.ValueSpecification raise {
  @wire.fields(json, ["annotations", "inputs", "output"])
  {
    annotations: read_annotations(json, context, preserve_input_order~),
    inputs: read_typed_pair_inputs(
      optional_object(json, "inputs"),
      context,
      preserve_input_order~,
    ),
    output: read_type_with_context(@wire.field(json, "output"), context),
  }
}

///|
pub fn write_value_specification(
  value : @model.ValueSpecification,
) -> Json raise {
  let fields : Array[(String, Json)] = []
  put_annotations(fields, value.annotations)
  if !value.inputs.is_empty() {
    fields.push(("inputs", write_inputs(value.inputs)))
  }
  fields.push(("output", write_type(value.output)))
  @wire.obj(fields)
}

///|
fn read_access_level(json : Json) -> @model.Access raise {
  match @wire.string(json) {
    "Public" | "public" | "pub" => @model.Access::Public
    "Private" | "private" => @model.Access::Private
    other => raise @wire.Invalid("invalid_access", other)
  }
}

///|
fn write_access_level(access : @model.Access) -> Json {
  @wire.text(
    match access {
      Public => "Public"
      Private => "Private"
    },
  )
}

///|
pub fn[T] read_access(
  json : Json,
  decode : (Json) -> T raise,
) -> @model.AccessControlled[T] raise {
  let fields = @wire.object(json)
  if fields.contains("access") {
    let access = read_access_level(@wire.field(json, "access"))
    let value = match fields.get("value") {
      Some(value) => {
        @wire.fields(json, ["access", "value"])
        value
      }
      None => {
        let rest = Map::from_array(fields.iter().collect())
        ignore(rest.remove("access"))
        Json::object(rest)
      }
    }
    { access, value: decode(value), }
  } else {
    let (tag, payload) = variant(json)
    { access: read_access_level(@wire.text(tag)), value: decode(payload), }
  }
}

///|
pub fn[T] write_access(
  value : @model.AccessControlled[T],
  encode : (T) -> Json raise,
) -> Json raise {
  @wire.tag(
    match value.access {
      Public => "Public"
      Private => "Private"
    },
    encode(value.value),
  )
}

///|
pub fn[T] read_documented(
  json : Json,
  decode : (Json) -> T raise,
) -> @model.Documented[T] raise {
  let fields = @wire.object(json)
  let doc = match fields.get("doc") {
    None => None
    Some(doc) => Some(@wire.string(doc))
  }
  if fields.contains("value") {
    @wire.fields(json, ["doc", "value"])
    { doc, value: decode(@wire.field(json, "value")), }
  } else {
    let body = Map::from_array(fields.iter().collect())
    ignore(body.remove("doc"))
    { doc, value: decode(Json::object(body)), }
  }
}

///|
pub fn[T] write_documented(
  value : @model.Documented[T],
  encode : (T) -> Json raise,
) -> Json raise {
  let fields : Array[(String, Json)] = []
  if value.doc is Some(doc) {
    fields.push(("doc", @wire.text(doc)))
  }
  fields.append(@wire.object(encode(value.value)).iter().collect())
  @wire.obj(fields)
}
