///|
pub fn read_reason(json : Json) -> @model.HoleReason raise {
  read_reason_with_context(json, None)
}

///|
pub fn read_reason_with_context(
  json : Json,
  context : @wire.DocumentNameContext?,
) -> @model.HoleReason raise {
  let read_fqname = fn(child) raise {
    @wire.read_context_fqname(child, context)
  }
  let (tag, payload) = variant(json)
  match tag {
    "UnresolvedReference" => {
      @wire.fields(payload, ["target"])
      @model.UnresolvedReference(read_fqname(@wire.field(payload, "target")))
    }
    "DeletedDuringRefactor" => {
      @wire.fields(payload, ["tx-id"])
      @model.DeletedDuringRefactor(@wire.string(@wire.field(payload, "tx-id")))
    }
    "TypeMismatch" => {
      @wire.fields(payload, ["expected", "found"])
      @model.TypeMismatch(
        @wire.string(@wire.field(payload, "expected")),
        @wire.string(@wire.field(payload, "found")),
      )
    }
    _ => raise @wire.Invalid("unknown_node", tag)
  }
}

///|
pub fn write_reason(value : @model.HoleReason) -> Json raise {
  match value {
    UnresolvedReference(target) =>
      @wire.tag(
        "UnresolvedReference",
        @wire.obj([("target", @wire.write_fqname(target))]),
      )
    DeletedDuringRefactor(id) =>
      @wire.tag("DeletedDuringRefactor", @wire.obj([("tx-id", @wire.text(id))]))
    TypeMismatch(expected, found) =>
      @wire.tag(
        "TypeMismatch",
        @wire.obj([
          ("expected", @wire.text(expected)),
          ("found", @wire.text(found)),
        ]),
      )
  }
}

///|
pub fn read_incompleteness(json : Json) -> @model.Incompleteness raise {
  read_incompleteness_with_context(json, None)
}

///|
pub fn read_incompleteness_with_context(
  json : Json,
  context : @wire.DocumentNameContext?,
) -> @model.Incompleteness raise {
  let read_reason = fn(child) raise { read_reason_with_context(child, context) }
  let read_type = fn(child) raise { read_type_with_context(child, context) }
  let (tag, payload) = variant(json)
  match tag {
    "Draft" => {
      @wire.fields(payload, [])
      @model.Draft
    }
    "Hole" => {
      @wire.fields(payload, ["reason", "partialBody"])
      @model.Incompleteness::Hole(
        read_reason(@wire.field(payload, "reason")),
        read_optional(payload, "partialBody", read_type),
      )
    }
    _ => raise @wire.Invalid("unknown_node", tag)
  }
}

///|
pub fn write_incompleteness(value : @model.Incompleteness) -> Json raise {
  match value {
    Draft => @wire.tag("Draft", @wire.obj([]))
    Hole(reason, partial) => {
      let fields = [("reason", write_reason(reason))]
      if partial is Some(tpe) {
        fields.push(("partialBody", write_type(tpe)))
      }
      @wire.tag("Hole", @wire.obj(fields))
    }
  }
}

///|
fn read_native_info(json : Json) -> @model.NativeInfo raise {
  @wire.fields(json, ["hint", "description"])
  let (tag, payload) = variant(@wire.field(json, "hint"))
  if tag != "PlatformSpecific" {
    @wire.fields(payload, [])
  }
  let hint = match tag {
    "Arithmetic" => @model.Arithmetic
    "Comparison" => @model.Comparison
    "StringOp" => @model.StringOp
    "CollectionOp" => @model.CollectionOp
    "PlatformSpecific" => {
      @wire.fields(payload, ["platform"])
      @model.PlatformSpecific(@wire.string(@wire.field(payload, "platform")))
    }
    _ => raise @wire.Invalid("unknown_node", tag)
  }
  {
    hint,
    description: match @wire.optional(json, "description") {
      None => None
      Some(value) => Some(@wire.string(value))
    },
  }
}

///|
fn write_native_info(value : @model.NativeInfo) -> Json {
  let hint = match value.hint {
    Arithmetic => @wire.tag("Arithmetic", @wire.obj([]))
    Comparison => @wire.tag("Comparison", @wire.obj([]))
    StringOp => @wire.tag("StringOp", @wire.obj([]))
    CollectionOp => @wire.tag("CollectionOp", @wire.obj([]))
    PlatformSpecific(platform) =>
      @wire.tag(
        "PlatformSpecific",
        @wire.obj([("platform", @wire.text(platform))]),
      )
  }
  let fields = [("hint", hint)]
  if value.description is Some(description) {
    fields.push(("description", @wire.text(description)))
  }
  @wire.obj(fields)
}

///|
fn read_binding(json : Json) -> @model.ExternalBinding raise {
  @wire.fields(json, ["targetPlatform", "externalName"])
  {
    target_platform: @wire.string(@wire.field(json, "targetPlatform")),
    external_name: @wire.string(@wire.field(json, "externalName")),
  }
}

///|
fn write_binding(value : @model.ExternalBinding) -> Json {
  @wire.obj([
    ("targetPlatform", @wire.text(value.target_platform)),
    ("externalName", @wire.text(value.external_name)),
  ])
}

///|
/// Preserve input parameter order; refuse duplicate names in accepted pair arrays.
pub fn read_inputs(json : Json) -> Array[(@model.Name, @model.Type)] raise {
  read_inputs_with_context(json, None)
}

///|
pub fn read_inputs_with_context(
  json : Json,
  context : @wire.DocumentNameContext?,
  preserve_input_order~ : Bool = false,
) -> Array[(@model.Name, @model.Type)] raise {
  let read_type = fn(child) raise { read_type_with_context(child, context) }
  let entries = match json {
    Array(entries) =>
      entries.map(entry => {
        let pair = @wire.tuple(entry, 2)
        (pair[0], pair[1])
      })
    Object(fields) =>
      if preserve_input_order || context is Some(_) {
        // Contextual trees may contain both compacted and ordinary files.
        fields.iter().map(entry => (Json::string(entry.0), entry.1)).collect()
      } else {
        let names = fields.keys().collect()
        names.sort()
        names.map(name => (Json::string(name), fields[name]))
      }
    _ =>
      raise @wire.Invalid(
        "invalid_type", "Expected input map or ordered pair array",
      )
  }
  let seen = Map([])
  entries.map(entry => {
    let name = @wire.read_name(entry.0)
    if seen.contains(name) {
      raise @wire.Invalid("duplicate_member", name.to_canonical())
    }
    seen[name] = true
    (name, read_type(entry.1))
  })
}

///|
pub fn write_inputs(value : Array[(@model.Name, @model.Type)]) -> Json raise {
  let fields : Map[String, Json] = Map([])
  for (name, tpe) in value {
    let key = @wire.string(name_key(name))
    if fields.contains(key) {
      raise @wire.Invalid("duplicate_member", key)
    }
    fields[key] = write_type(tpe)
  }
  let sorted = value.map(p => p.0.to_canonical())
  sorted.sort()
  if sorted == value.map(p => p.0.to_canonical()) {
    Json::object(fields)
  } else {
    Json::array(value.map(p => Json::array([name_key(p.0), write_type(p.1)])))
  }
}

///|
pub fn read_definition(json : Json) -> @model.ValueDefinition raise {
  read_definition_with_context(json, None)
}

///|
pub fn read_definition_with_context(
  json : Json,
  context : @wire.DocumentNameContext?,
  preserve_input_order~ : Bool = false,
) -> @model.ValueDefinition raise {
  let read_inputs = fn(child) raise {
    read_inputs_with_context(child, context, preserve_input_order~)
  }
  let read_type = fn(child) raise { read_type_with_context(child, context) }
  let read_value = fn(child) raise {
    read_value_with_context(child, context, preserve_input_order~)
  }
  let read_incompleteness = fn(child) raise {
    read_incompleteness_with_context(child, context)
  }
  let (tag, payload) = variant(json)
  let inputs = read_inputs(@wire.field(payload, "inputTypes"))
  match tag {
    "ExpressionBody" => {
      @wire.fields(payload, ["inputTypes", "outputType", "body"])
      @model.ExpressionBody(
        inputs,
        read_type(@wire.field(payload, "outputType")),
        read_value(@wire.field(payload, "body")),
      )
    }
    "NativeBody" => {
      @wire.fields(payload, ["inputTypes", "outputType", "nativeInfo"])
      @model.NativeBody(
        inputs,
        read_type(@wire.field(payload, "outputType")),
        read_native_info(@wire.field(payload, "nativeInfo")),
      )
    }
    "ExternalBody" => {
      @wire.fields(payload, [
        "inputTypes", "outputType", "externals", "body", "externalName", "targetPlatform",
      ])
      let externals = match @wire.optional(payload, "externals") {
        Some(bindings) => {
          if @wire.optional(payload, "externalName") is Some(_) ||
            @wire.optional(payload, "targetPlatform") is Some(_) {
            raise @wire.Invalid("duplicate_member", "externals")
          }
          @wire.array(bindings).map(read_binding)
        }
        None =>
          [
            read_binding(
              @wire.obj([
                ("externalName", @wire.field(payload, "externalName")),
                ("targetPlatform", @wire.field(payload, "targetPlatform")),
              ]),
            ),
          ]
      }
      if externals.is_empty() {
        raise @wire.Invalid(
          "invalid_external_bindings", "Expected at least one binding",
        )
      }
      let targets : Map[String, Bool] = Map([])
      for binding in externals {
        if targets.contains(binding.target_platform) {
          raise @wire.Invalid("duplicate_member", binding.target_platform)
        }
        targets[binding.target_platform] = true
      }
      @model.ExternalBody(
        inputs,
        read_type(@wire.field(payload, "outputType")),
        externals,
        read_optional(payload, "body", read_value),
      )
    }
    "IncompleteBody" => {
      @wire.fields(payload, [
        "inputTypes", "outputType", "incompleteness", "partialBody",
      ])
      @model.IncompleteBody(
        inputs,
        read_optional(payload, "outputType", read_type),
        read_incompleteness(@wire.field(payload, "incompleteness")),
        read_optional(payload, "partialBody", read_value),
      )
    }
    _ => raise @wire.Invalid("unknown_node", tag)
  }
}

///|
pub fn write_definition(value : @model.ValueDefinition) -> Json raise {
  match value {
    ExpressionBody(inputs, output, body) =>
      @wire.tag(
        "ExpressionBody",
        @wire.obj([
          ("inputTypes", write_inputs(inputs)),
          ("outputType", write_type(output)),
          ("body", write_value(body)),
        ]),
      )
    NativeBody(inputs, output, info) =>
      @wire.tag(
        "NativeBody",
        @wire.obj([
          ("inputTypes", write_inputs(inputs)),
          ("outputType", write_type(output)),
          ("nativeInfo", write_native_info(info)),
        ]),
      )
    ExternalBody(inputs, output, externals, body) => {
      let fields = [
        ("inputTypes", write_inputs(inputs)),
        ("outputType", write_type(output)),
        ("externals", Json::array(externals.map(write_binding))),
      ]
      if body is Some(value) {
        fields.push(("body", write_value(value)))
      }
      let json = @wire.tag("ExternalBody", @wire.obj(fields))
      ignore(read_definition(json))
      json
    }
    IncompleteBody(inputs, output, incompleteness, body) => {
      let fields = [("inputTypes", write_inputs(inputs))]
      if output is Some(tpe) {
        fields.push(("outputType", write_type(tpe)))
      }
      fields.push(("incompleteness", write_incompleteness(incompleteness)))
      if body is Some(value) {
        fields.push(("partialBody", write_value(value)))
      }
      @wire.tag("IncompleteBody", @wire.obj(fields))
    }
  }
}
