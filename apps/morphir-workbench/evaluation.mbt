///|
/// Private worker input descriptions; these are not an upstream RPC schema.
fn input_schema(
  tpe : @ir.Type,
  types : Map[String, @ir.TypeDefinition],
  variables : Map[@ir.Name, Json],
  depth : Int32,
) -> Json raise {
  if depth > 24 {
    raise @scheme.Unsupported(
      "Recursive or deeply nested input type: " + type_label(tpe),
    )
  }
  fn shape(
    kind : String,
    default_value : Json,
    extra : Array[(String, Json)],
  ) -> Json {
    let fields = [
      ("kind", @wire.text(kind)),
      ("label", @wire.text(type_label(tpe))),
      ("default", default_value),
    ]
    fields.append(extra)
    @wire.obj(fields)
  }
  match tpe {
    Variable(_, name) =>
      match variables.get(name) {
        Some(schema) => schema
        None =>
          raise @scheme.Unsupported(
            "Unresolved type parameter: " + name.to_canonical(),
          )
      }
    Unit(_) => shape("unit", Json::null(), [])
    Tuple(_, members) => {
      let schemas = members.map(item => {
        input_schema(item, types, variables, depth + 1)
      })
      shape(
        "tuple",
        Json::array(schemas.map(schema => @wire.field(schema, "default"))),
        [("items", Json::array(schemas))],
      )
    }
    Record(_, fields) => {
      let entries = fields.iter().collect()
      entries.sort_by((a, b) => {
        a.0.to_canonical().lexical_compare(b.0.to_canonical())
      })
      let schemas = entries.map(pair => {
        (
          pair.0.to_canonical(),
          input_schema(pair.1, types, variables, depth + 1),
        )
      })
      shape(
        "record",
        @wire.obj(schemas.map(pair => (pair.0, @wire.field(pair.1, "default")))),
        [("fields", @wire.obj(schemas))],
      )
    }
    Reference(_, name, args) => {
      let id = name.to_canonical()
      if args.is_empty() {
        match id {
          "morphir/SDK:basics#bool" =>
            return shape("bool", Json::boolean(false), [])
          "morphir/SDK:basics#int" | "morphir/SDK:int#int" =>
            return shape("int", @wire.text("0"), [])
          "morphir/SDK:basics#float" =>
            return shape("float", Json::number(0), [])
          "morphir/SDK:string#string" =>
            return shape("string", @wire.text(""), [])
          "morphir/SDK:char#char" => return shape("char", @wire.text("a"), [])
          _ => ()
        }
      }
      let schemas = args.map(arg => {
        input_schema(arg, types, variables, depth + 1)
      })
      if id == "morphir/SDK:list#list" && schemas.length() == 1 {
        return shape("list", Json::array([]), [("item", schemas[0])])
      }
      let definition = match types.get(id) {
        Some(definition) => definition
        None =>
          raise @scheme.Unsupported(
            "Input type is not available locally: " + id,
          )
      }
      let (params, alias_type, constructors) = match definition {
        TypeAliasDefinition(params, body) => (params, Some(body), None)
        CustomTypeDefinition(params, constructors) if constructors.access ==
          Public => (params, None, Some(constructors.value))
        _ =>
          raise @scheme.Unsupported(
            "Input type has private or incomplete constructors: " + id,
          )
      }
      if params.length() != schemas.length() {
        raise @scheme.Invalid("Type argument count for " + id)
      }
      let scope : Map[@ir.Name, Json] = Map([])
      for i, param in params {
        scope[param] = schemas[i]
      }
      if alias_type is Some(body) {
        return input_schema(body, types, scope, depth + 1)
      }
      let variants = constructors.unwrap().iter().collect()
      variants.sort_by((a, b) => {
        a.0.to_canonical().lexical_compare(b.0.to_canonical())
      })
      let choices = variants.map(pair => {
        let tag = name.package_name.to_canonical() +
          ":" +
          name.module_name.to_canonical() +
          "#" +
          pair.0.to_canonical()
        let arguments = pair.1.map(arg => {
          input_schema(arg.1, types, scope, depth + 1)
        })
        @wire.obj([
          ("constructor", @wire.text(tag)),
          ("label", @wire.text(display_name(pair.0, upper=true))),
          (
            "argumentLabels",
            Json::array(pair.1.map(arg => @wire.text(display_name(arg.0)))),
          ),
          ("arguments", Json::array(arguments)),
          (
            "default",
            @wire.obj([
              ("constructor", @wire.text(tag)),
              (
                "arguments",
                Json::array(
                  arguments.map(schema => @wire.field(schema, "default")),
                ),
              ),
            ]),
          ),
        ])
      })
      if choices.is_empty() {
        raise @scheme.Unsupported("Input type has no constructors: " + id)
      }
      shape("custom", @wire.field(choices[0], "default"), [
        ("variants", Json::array(choices)),
      ])
    }
    Function(_, _, _) | ExtensibleRecord(_, _, _) =>
      raise @scheme.Unsupported(
        "Input editor does not support " + type_label(tpe),
      )
  }
}

///|
fn evaluation_types(file : @ir.IRFile) -> Map[String, @ir.TypeDefinition] {
  let result : Map[String, @ir.TypeDefinition] = Map([])
  match file.distribution {
    Library(package_name, _, package_def)
    | Application(package_name, _, package_def, _) =>
      for module_name, module_def in package_def.modules {
        for name, item in module_def.value.types {
          result[package_name.to_canonical() +
          ":" +
          module_name.to_canonical() +
          "#" +
          name.to_canonical()] = item.value.value
        }
      }
    Specs(_, _, _) => ()
  }
  result
}

///|
fn evaluation_definitions(
  file : @ir.IRFile,
) -> Map[String, @ir.ValueDefinition] {
  let result : Map[String, @ir.ValueDefinition] = Map([])
  match file.distribution {
    Library(package_name, _, package_def)
    | Application(package_name, _, package_def, _) =>
      for module_name, module_def in package_def.modules {
        for name, item in module_def.value.values {
          if module_def.access != @ir.Access::Public ||
            item.access != @ir.Access::Public {
            continue
          }
          result[package_name.to_canonical() +
          ":" +
          module_name.to_canonical() +
          "#" +
          name.to_canonical()] = item.value.value
        }
      }
    Specs(_, _, _) => ()
  }
  result
}

///|
fn evaluation_profile(
  definition : @ir.ValueDefinition,
  types : Map[String, @ir.TypeDefinition],
) -> Json {
  try {
    let inputs = match definition {
      ExpressionBody(inputs, _, _) => inputs
      _ =>
        raise @scheme.Unsupported(
          "Local evaluation requires a portable definition",
        )
    }
    let schemas = inputs.map(input => {
      @wire.obj([
        ("name", @wire.text(input.0.to_canonical())),
        ("label", @wire.text(display_name(input.0))),
        ("schema", input_schema(input.1, types, Map([]), 0)),
      ])
    })
    @wire.obj([
      ("supported", Json::boolean(true)),
      ("inputs", Json::array(schemas)),
      (
        "default",
        Json::array(
          schemas.map(input => {
            @wire.field(@wire.field(input, "schema"), "default")
          }),
        ),
      ),
    ])
  } catch {
    error =>
      @wire.obj([
        ("supported", Json::boolean(false)),
        ("reason", @wire.text(@scheme.error_message(error))),
      ])
  }
}

///|
fn evaluation_profiles(file : @ir.IRFile) -> Json {
  let types = evaluation_types(file)
  @wire.obj(
    evaluation_definitions(file)
    .iter()
    .map(pair => (pair.0, evaluation_profile(pair.1, types)))
    .collect(),
  )
}

///|
/// Construct runtime data directly. Input text is never evaluated as Scheme.
fn input_value(
  schema : Json,
  value : Json,
  path : String,
) -> @scheme.Value raise {
  input_value_inner(schema, value, path) catch {
    @wire.Invalid(_, message) => raise @scheme.Invalid(path + ": " + message)
    error => raise error
  }
}

///|
fn input_value_inner(
  schema : Json,
  value : Json,
  path : String,
) -> @scheme.Value raise {
  fn invalid() -> @scheme.Value raise {
    raise @scheme.Invalid(
      path + ": expected " + @wire.string(@wire.field(schema, "label")),
    )
  }
  match @wire.string(@wire.field(schema, "kind")) {
    "unit" => if value == Json::null() { @scheme.Unit } else { invalid() }
    "bool" =>
      match value {
        True => @scheme.Boolean(true)
        False => @scheme.Boolean(false)
        _ => invalid()
      }
    "string" =>
      match value {
        String(text) => @scheme.Text(text)
        _ => invalid()
      }
    "char" => @scheme.Character(@wire.character(value))
    "int" =>
      match value {
        String(text) => {
          ignore(@wire.write_integer(text))
          @scheme.integer(text)
        }
        _ =>
          raise @scheme.Invalid(
            path + ": Int requires a decimal string to preserve precision",
          )
      }
    "float" => @scheme.Number(@scheme.Number::Real(@wire.float(value)))
    "record" => {
      let fields = @wire.object(@wire.field(schema, "fields"))
      let data = @wire.object(value)
      if fields.length() != data.length() {
        return invalid()
      }
      let result : Map[String, @scheme.Value] = Map([])
      for name, child in fields {
        let item = match data.get(name) {
          Some(item) => item
          None => return invalid()
        }
        result[name] = input_value(child, item, path + "." + name)
      }
      @scheme.Record(result)
    }
    "list" =>
      @scheme.list(
        @wire.array(value).mapi((i, item) => {
          input_value(
            @wire.field(schema, "item"),
            item,
            path + "[" + i.to_string() + "]",
          )
        }),
      )
    "tuple" => {
      let schemas = @wire.array(@wire.field(schema, "items"))
      let data = @wire.array(value)
      if schemas.length() != data.length() {
        return invalid()
      }
      @scheme.Vector(
        schemas.mapi((i, child) => {
          input_value(child, data[i], path + "[" + i.to_string() + "]")
        }),
      )
    }
    "custom" => {
      let fields = @wire.object(value)
      if fields.length() != 2 {
        return invalid()
      }
      let tag = @wire.string(@wire.field(value, "constructor"))
      let variant = @wire.array(@wire.field(schema, "variants"))
        .iter()
        .find_first(variant => node_text(variant, "constructor") == tag)
      let variant = match variant {
        Some(variant) => variant
        None => return invalid()
      }
      let schemas = @wire.array(@wire.field(variant, "arguments"))
      let data = @wire.array(@wire.field(value, "arguments"))
      if schemas.length() != data.length() {
        return invalid()
      }
      @scheme.Tagged(
        tag,
        schemas.mapi((i, child) => {
          input_value(
            child,
            data[i],
            path + ".arguments[" + i.to_string() + "]",
          )
        }),
      )
    }
    _ => invalid()
  }
}

///|
fn evaluate_model(file : @ir.IRFile, request : Json) -> Json raise {
  let entry = @wire.string(@wire.field(request, "entry"))
  let definition = match evaluation_definitions(file).get(entry) {
    Some(definition) => definition
    None => raise @scheme.Unsupported("No local definition for " + entry)
  }
  let profile = evaluation_profile(definition, evaluation_types(file))
  if @wire.field(profile, "supported") != Json::boolean(true) {
    raise @scheme.Unsupported(@wire.string(@wire.field(profile, "reason")))
  }
  let inputs = @wire.array(@wire.field(profile, "inputs"))
  let data = match @wire.optional(request, "argumentsIon") {
    Some(String(source)) =>
      @wire.array(@arguments.ion_arguments(profile, source, false))
    _ => @wire.array(@wire.field(request, "arguments"))
  }
  if inputs.length() != data.length() {
    raise @scheme.Invalid(
      "Expected " +
      inputs.length().to_string() +
      " arguments in parameter order",
    )
  }
  let arguments = inputs.mapi((i, input) => {
    input_value(
      @wire.field(input, "schema"),
      data[i],
      @wire.string(@wire.field(input, "name")),
    )
  })
  let value = @backend.run_file(file, @ir.FQName::parse(entry), arguments)
  @wire.obj([
    ("success", Json::boolean(true)),
    ("value", @wire.text(@scheme.value_to_string(value))),
    ("structured", result_tree(value)),
  ])
}
