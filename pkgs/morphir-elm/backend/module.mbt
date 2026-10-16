///|
priv enum TypeSource {
  Defined(@ir.TypeDefinition)
  Specified(@ir.TypeSpecification)
}

///|
priv enum ValueSource {
  DefinedValue(@ir.ValueDefinition)
  SpecifiedValue(@ir.ValueSpecification)
}

///|
priv struct ModuleInput {
  package_name : @ir.Path
  module_path : @ir.Path
  doc : String?
  types : Array[(@ir.Name, @ir.Access, String?, TypeSource)]
  values : Array[(@ir.Name, @ir.Access, String?, ValueSource)]
  entry_points : Map[String, @ir.EntryPoint]
}

///|
fn ModuleInput::from_definition(
  package_name : @ir.Path,
  module_path : @ir.Path,
  definition : @ir.ModuleDefinition,
  entry_points : Map[String, @ir.EntryPoint],
) -> ModuleInput {
  {
    package_name,
    module_path,
    doc: definition.doc,
    types: definition.types
    .iter()
    .map(entry => {
      (entry.0, entry.1.access, entry.1.value.doc, Defined(entry.1.value.value))
    })
    .collect(),
    values: definition.values
    .iter()
    .map(entry => {
      (
        entry.0,
        entry.1.access,
        entry.1.value.doc,
        DefinedValue(entry.1.value.value),
      )
    })
    .collect(),
    entry_points,
  }
}

///|
fn ModuleInput::from_specification(
  package_name : @ir.Path,
  module_path : @ir.Path,
  spec : @ir.ModuleSpecification,
) -> ModuleInput {
  {
    package_name,
    module_path,
    doc: spec.doc,
    types: spec.types
    .iter()
    .map(entry => {
      (entry.0, @ir.Access::Public, entry.1.doc, Specified(entry.1.value))
    })
    .collect(),
    values: spec.values
    .iter()
    .map(entry => {
      (entry.0, @ir.Access::Public, entry.1.doc, SpecifiedValue(entry.1.value))
    })
    .collect(),
    entry_points: Map([]),
  }
}

///|
priv struct ModuleOutput {
  elm_module : Array[String]
  source : String
  uses_sdk_package : Bool
  foreign_packages : Array[String]
}

///|
fn hex4(code : Int32) -> String {
  let digits = "0123456789ABCDEF"
  let mut out = ""
  for shift in [12, 8, 4, 0] {
    out = out +
      Int32::unsafe_to_char(digits[(code >> shift) & 15].to_int()).to_string()
  }
  out
}

///|
fn elm_string(text : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  for c in text {
    match c {
      '\\' => out.write_string("\\\\")
      '"' => out.write_string("\\\"")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      _ =>
        if c.to_int() < 0x20 || c.to_int() == 0x7F {
          out.write_string("\\u{" + hex4(c.to_int()) + "}")
        } else {
          out.write_char(c)
        }
    }
  }
  out.write_char('"')
  out.to_string()
}

///|
/// Annotation arguments are data: literals, unit, lists, tuples, records,
/// constructors and constructor applications of data.
fn is_annotation_data(value : @ir.Value) -> Bool {
  match value {
    Literal(_, _) | Unit(_) | Constructor(_, _) => true
    List(_, items) | Tuple(_, items) => items.iter().all(is_annotation_data)
    Record(_, fields) => fields.values().all(is_annotation_data)
    Apply(_, f, argument) =>
      is_annotation_data(argument) && is_constructor_chain(f)
    _ => false
  }
}

///|
fn is_constructor_chain(value : @ir.Value) -> Bool {
  match value {
    Constructor(_, _) => true
    Apply(_, f, argument) =>
      is_annotation_data(argument) && is_constructor_chain(f)
    _ => false
  }
}

///|
fn entry_kind(kind : @ir.EntryPointKind) -> String {
  match kind {
    Main => "main"
    Command => "command"
    Handler => "handler"
    Job => "job"
    Policy => "policy"
  }
}

///|
fn annotation_attribute(
  ctx : Ctx,
  annotation : @ir.Annotation,
  at : String,
) -> String raise ElmGenerationError {
  match annotation {
    Compact(name, text) =>
      "@morphir.annotation { fqname = " +
      elm_string(name.to_canonical()) +
      (match text {
        Some(t) => ", text = " + elm_string(t)
        None => ""
      }) +
      " }"
    Structured(name, arguments) => {
      for argument in arguments {
        let value = match argument {
          Positional(value) | Named(_, value) => value
        }
        if !is_annotation_data(value) {
          refuse(
            "annotation_argument", at, "annotation arguments must be data, not computed values",
          )
        }
      }
      let printed = arguments.map(argument => {
        match argument {
          Positional(value) =>
            "{ value = " +
            @printer.print_expression(node(lower_value(ctx, value, at))) +
            " }"
          Named(field, value) =>
            "{ name = " +
            elm_string(field.to_canonical()) +
            ", value = " +
            @printer.print_expression(node(lower_value(ctx, value, at))) +
            " }"
        }
      }) catch {
        Refused(_) as e => raise e
        e => refuse("print", at, e.to_string())
      }
      "@morphir.annotation { fqname = " +
      elm_string(name.to_canonical()) +
      ", arguments = [ " +
      printed.join(", ") +
      " ] }"
    }
  }
}

///|
fn signature(
  ctx : Ctx,
  elm_name : String,
  inputs : Array[(@ir.Name, @ir.Type)],
  output : @ir.Type,
  at : String,
) -> @ast.Node[@ast.Signature] raise ElmGenerationError {
  let types = inputs.map(input => input.1) + [output]
  ctx.with_type_variables([], types, at, fn() raise ElmGenerationError {
    let mut result = lower_type(ctx, output, at)
    for i = inputs.length() - 1; i >= 0; i = i - 1 {
      result = FunctionTypeAnnotation(
        node(lower_type(ctx, inputs[i].1, at)),
        node(result),
      )
    }
    node({ name: node(elm_name), type_annotation: node(result), })
  })
}

///|
fn value_declaration(
  ctx : Ctx,
  elm_name : String,
  doc : String?,
  source : ValueSource,
  attributes : Array[String],
  at : String,
) -> @ast.Declaration raise ElmGenerationError {
  let attributes = attributes.copy()
  let (inputs, output, body) : (
    Array[(@ir.Name, @ir.Type)],
    @ir.Type?,
    @ir.Value?,
  ) = match source {
    DefinedValue(ExpressionBody(inputs, output, body)) =>
      (inputs, Some(output), Some(body))
    DefinedValue(NativeBody(inputs, output, _)) => (inputs, Some(output), None)
    DefinedValue(ExternalBody(inputs, output, bindings, fallback)) => {
      for binding in bindings {
        attributes.push(
          "@morphir.external { platform = " +
          elm_string(binding.target_platform) +
          ", name = " +
          elm_string(binding.external_name) +
          " }",
        )
      }
      (inputs, Some(output), fallback)
    }
    DefinedValue(IncompleteBody(inputs, output, _, _)) => (inputs, output, None)
    SpecifiedValue(spec) => {
      for annotation in spec.annotations {
        attributes.push(annotation_attribute(ctx, annotation, at))
      }
      (spec.inputs, Some(spec.output), None)
    }
  }
  let reason = match source {
    DefinedValue(NativeBody(_, _, _)) => "native body"
    DefinedValue(ExternalBody(_, _, _, _)) => "external body without a fallback"
    DefinedValue(IncompleteBody(_, _, _, _)) => "incomplete definition"
    _ => "specification without a body"
  }
  let (arguments, expression) = match body {
    Some(value) => function_body(ctx, inputs, value, at)
    None =>
      ctx.with_scope(fn() raise ElmGenerationError {
        let arguments = inputs.map(input => {
          node(@ast.Pattern::VarPattern(ctx.bind(input.0)))
        })
        (arguments[:], node(placeholder(ctx, reason, at)))
      })
  }
  FunctionDeclaration({
    documentation: doc_comment(doc, attributes),
    signature: match output {
      Some(t) => Some(signature(ctx, elm_name, inputs, t, at))
      None => None
    },
    declaration: node({ name: node(elm_name), arguments, expression, }),
  })
}

///|
fn generate_module(
  options : Options,
  input : ModuleInput,
) -> ModuleOutput raise ElmGenerationError {
  let ctx = Ctx::new(options, input.package_name, input.module_path)
  let elm_module = module_name(input.package_name, input.module_path)
  let fq = fn(name : @ir.Name) {
    input.package_name.to_canonical() +
    ":" +
    input.module_path.to_canonical() +
    "#" +
    name.to_canonical()
  }
  // Top-level names first: they are in scope everywhere, and a collision is an error.
  let value_names : Map[String, String] = Map([])
  let top_level_names : Array[String] = []
  for value in input.values {
    let elm_name = value_name(value.0)
    if value_names.values().any(existing => existing == elm_name) {
      refuse(
        "name_collision",
        fq(value.0),
        "another value in this module is also " + elm_name,
      )
    }
    value_names[value.0.to_canonical()] = elm_name
    top_level_names.push(elm_name)
    ctx.reserve_top_level(elm_name)
    ctx.top_values[elm_name] = true
  }
  let type_names : Map[String, Bool] = Map([])
  let constructor_names : Map[String, Bool] = Map([])
  for t in input.types {
    let elm_name = type_name(t.0)
    if type_names.contains(elm_name) {
      refuse(
        "name_collision",
        fq(t.0),
        "another type in this module is also " + elm_name,
      )
    }
    type_names[elm_name] = true
    ctx.module_types[elm_name] = true
    let constructors : Array[@ir.Name] = match t.3 {
      Defined(CustomTypeDefinition(_, constructors)) =>
        constructors.value.keys().collect()
      Specified({ body: CustomTypeSpecification(_, constructors), .. }) =>
        constructors.keys().collect()
      Specified({ body: OpaqueTypeSpecification(_), .. }) =>
        [@ir.Name::parse(t.0.to_canonical() + "-opaque") catch { _ => t.0 }]
      _ => []
    }
    for c in constructors {
      let elm_constructor = type_name(c)
      if constructor_names.contains(elm_constructor) {
        refuse(
          "name_collision",
          fq(t.0),
          "another constructor in this module is also " + elm_constructor,
        )
      }
      constructor_names[elm_constructor] = true
      ctx.module_types[elm_constructor] = true
    }
  }
  let declarations : Array[(String, @ast.Node[@ast.Declaration])] = []
  let exposes : Array[@ast.Node[@ast.TopLevelExpose]] = []
  for t in input.types {
    let at = fq(t.0)
    let (declaration, expose) = match t.3 {
      Defined(definition) =>
        lower_type_definition(ctx, t.0, t.2, definition, at)
      Specified(spec) => {
        let (d, e) = lower_type_specification(ctx, t.0, t.2, spec, at)
        (d, Some(e))
      }
    }
    declarations.push((at, node(declaration)))
    if t.1 is Public && expose is Some(e) {
      exposes.push(node(e))
    }
  }
  for value in input.values {
    let at = fq(value.0)
    let elm_name = value_names.get(value.0.to_canonical()).unwrap()
    let attributes = []
    for key, entry in input.entry_points {
      if entry.target.to_canonical() == at {
        attributes.push(
          "@morphir.entry { kind = " +
          elm_string(entry_kind(entry.kind)) +
          ", name = " +
          elm_string(key) +
          " }",
        )
      }
    }
    ctx.used.clear()
    for name in top_level_names {
      ctx.reserve_top_level(name)
    }
    let binders : Map[String, Bool] = Map([])
    match value.3 {
      DefinedValue(definition) => definition_binders(definition, binders)
      SpecifiedValue(spec) =>
        for input in spec.inputs {
          binders[value_name(input.0)] = true
        }
    }
    ctx.binders = binders
    declarations.push(
      (
        at,
        node(value_declaration(ctx, elm_name, value.2, value.3, attributes, at)),
      ),
    )
    if value.1 is Public {
      exposes.push(node(FunctionExpose(elm_name)))
    }
  }
  let exposing : @ast.Exposing = if exposes.is_empty() {
    All(zero)
  } else {
    Explicit(exposes[:])
  }
  let file : @ast.File = {
    module_definition: node(
      NormalModule({
        module_name: node(elm_module[:]),
        exposing_list: node(exposing),
      }),
    ),
    imports: ctx.elm_imports()[:],
    declarations: declarations.map(d => d.1)[:],
    comments: match doc_comment(input.doc, []) {
      Some(comment) => [comment][:]
      None => [][:]
    },
  }
  let source = @printer.print_file(file, width=options.width) catch {
    error => {
      // Find the declaration that does not print, to report its IR path.
      for d in declarations {
        ignore(@printer.print_declaration(d.1, width=options.width)) catch {
          inner => refuse("print", d.0, @debug.to_string(inner))
        }
      }
      refuse("print", elm_module.join("."), @debug.to_string(error))
    }
  }
  {
    elm_module,
    source,
    uses_sdk_package: ctx.uses_sdk_package,
    foreign_packages: ctx.foreign_packages.keys().collect(),
  }
}
