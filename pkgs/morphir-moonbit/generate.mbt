///|
pub fn generate(
  input : Input,
  limits? : Limits? = None,
  naming? : NamingStyle = Readable,
  metadata_capabilities? : @linked_metadata.Capabilities = @linked_metadata.Capabilities::unavailable(),
  cancelled? : () -> Bool = fn() { false },
) -> Output raise GenerationError {
  generate_library(
    input,
    limits.unwrap_or(Limits::default()),
    cancelled,
    naming,
    metadata_capabilities,
  ) catch {
    Invalid(_, _, _) as error => raise error
    @linked_metadata.Invalid(code, owner, message) =>
      raise Invalid(code, owner, message)
    @wire.Invalid(code, message) => raise Invalid(code, input.unit_id, message)
    error =>
      raise Invalid("moonbit.invalid_input", input.unit_id, error.to_string())
  }
}

///|
fn generate_library(
  input : Input,
  limits : Limits,
  cancelled : () -> Bool,
  naming : NamingStyle,
  metadata_capabilities : @linked_metadata.Capabilities,
) -> Output raise {
  fn check_cancelled() -> Unit raise {
    if cancelled() {
      raise Invalid("moonbit.cancelled", input.unit_id, "Cancelled")
    }
  }
  check_cancelled()
  if input.unit_id == "" ||
    limits.max_declarations <= 0 ||
    limits.max_bytes <= 0 {
    raise Invalid(
      "moonbit.invalid_input",
      input.unit_id,
      "Nonempty unit identity and positive limits are required",
    )
  }
  let (package_name, package_def) = match input.ir.distribution {
    Library(name, _, definition) => (name, definition)
    _ =>
      raise Invalid(
        "moonbit.unsupported_distribution",
        input.unit_id,
        "A complete library implementation is required",
      )
  }
  validate_path(package_name)
  let source_ir = canonical_json(@ir_json.to_json(input.ir))
  if @utf8.encode(source_ir).length() > limits.max_bytes {
    raise Invalid(
      "moonbit.byte_limit",
      input.unit_id,
      "Source IR snapshot exceeds the output budget",
    )
  }
  let owned = Map::from_array(
    @identities.nodes(input.unit_id, input.ir).map(id => (id, true)),
  )
  let index : Map[@ir.FQName, Declaration] = Map([])
  let lowering : Lowering = {
    names: TargetNames::new(input, naming, metadata_capabilities),
    locals: None,
    types: Map([]),
    constructors: Map([]),
    values: index,
    shapes: Map([]),
    exported_shapes: Map([]),
    abstract_types: Map([]),
    imports: Map::from_array([("sdk", true)]),
  }
  for module_name, access in package_def.modules {
    for name, entry in access.value.types {
      let fqname : @ir.FQName = { package_name, module_name, local_name: name, }
      ignore(value_name(fqname))
      lowering.types[fqname] = {
        definition: entry.value.value,
        public: access.access == @ir.Access::Public &&
        entry.access == @ir.Access::Public,
        exposed: entry.access == @ir.Access::Public,
      }
    }
  }
  let type_names = lowering.types.keys().collect()
  type_names.sort()
  let enums : Array[(@ir.FQName, Bool, Array[String])] = []
  for name in type_names {
    let context = "type:" + name.to_canonical()
    owned[context] = true
    let entry = lowering.types[name]
    match entry.definition {
      TypeAliasDefinition(params, target) => {
        if !params.is_empty() {
          raise Invalid("moonbit.unsupported_type", context, "Generic alias")
        }
        ignore(lower_type(lowering, target, context, trail=[name]))
      }
      CustomTypeDefinition(params, constructors) => {
        if !params.is_empty() {
          raise Invalid(
            "moonbit.unsupported_type", context, "Generic custom type",
          )
        }
        let constructor_names = constructors.value.keys().collect()
        constructor_names.sort()
        let cases = []
        for constructor_name in constructor_names {
          let fqname = { ..name, local_name: constructor_name, }
          let inputs = constructors.value[constructor_name].map(p => {
            lower_type(lowering, p.1, context)
          })
          // MoonBit checks the payload types of a `pub` type even when its constructors are hidden.
          if entry.public {
            for t in inputs {
              export_type(lowering, t)
            }
          }
          if lowering.constructors.contains(fqname) {
            raise Invalid(
              "moonbit.name_collision",
              context,
              fqname.to_canonical(),
            )
          }
          lowering.constructors[fqname] = {
            inputs,
            output: Nominal(name),
            module_name: name.module_name,
            public: entry.public && constructors.access == @ir.Access::Public,
            exposed: entry.exposed && constructors.access == @ir.Access::Public,
          }
          owned["constructor:" + fqname.to_canonical()] = true
          cases.push(
            "  " +
            lowering.names.names["constructor:" + fqname.to_canonical()] +
            (if inputs.is_empty() {
              ""
            } else {
              "(" + inputs.map(t => type_source(lowering, t)).join(", ") + ")"
            }),
          )
        }
        enums.push((name, constructors.access == @ir.Access::Public, cases))
      }
      _ =>
        raise Invalid(
          "moonbit.incomplete_type", context, "Incomplete type definition",
        )
    }
  }
  let module_names = package_def.modules.keys().collect()
  module_names.sort()
  for module_name in module_names {
    check_cancelled()
    validate_path(module_name)
    let access = package_def.modules[module_name]
    let module_def = access.value
    let module_id = "module:" +
      package_name.to_canonical() +
      ":" +
      module_name.to_canonical()
    owned[module_id] = true
    for name, value in module_def.values {
      check_cancelled()
      validate_name(name)
      let fqname : @ir.FQName = { package_name, module_name, local_name: name, }
      let context = value_node(fqname)
      let (inputs, output, body) = match value.value.value {
        ExpressionBody(inputs, output, body) =>
          (
            inputs.map(p => {
              (
                p.0,
                lower_type(
                  lowering,
                  p.1,
                  context + "/input/" + p.0.to_canonical(),
                ),
              )
            }),
            lower_type(lowering, output, context + "/output"),
            body,
          )
        IncompleteBody(_, _, _, _) =>
          raise Invalid(
            "moonbit.incomplete_body", context, "Incomplete definition",
          )
        NativeBody(_, _, _) | ExternalBody(_, _, _, _) =>
          raise Invalid(
            "moonbit.unresolved_implementation", context, "No target implementation is registered",
          )
      }
      let seen_inputs = Map([])
      for parameter in inputs {
        validate_name(parameter.0)
        if seen_inputs.contains(parameter.0) {
          raise Invalid(
            "moonbit.duplicate_parameter",
            context,
            parameter.0.to_canonical(),
          )
        }
        seen_inputs[parameter.0] = true
        owned[context + "/input/" + parameter.0.to_canonical()] = true
      }
      index[fqname] = {
        fqname,
        module_name,
        output,
        inputs,
        body,
        public: access.access == @ir.Access::Public &&
        value.access == @ir.Access::Public,
        exposed: value.access == @ir.Access::Public,
      }
      for node in [context, context + "/output", context + "/body"] {
        owned[node] = true
      }
      if index.length() > limits.max_declarations {
        raise Invalid(
          "moonbit.declaration_limit", context, "Too many declarations",
        )
      }
    }
  }
  let names = index.keys().collect()
  names.sort()
  let imports = lowering.imports
  let definitions = []
  let symbols = []
  let generated = Map([])
  for name in names {
    check_cancelled()
    let declaration = index[name]
    let identifier = lowering.names.names[value_node(name)]
    lowering.locals = Some(LocalNames::new(lowering.names, declaration))
    if generated.contains(identifier) {
      raise Invalid("moonbit.name_collision", name.to_canonical(), identifier)
    }
    generated[identifier] = true
    if declaration.public {
      export_type(lowering, declaration.output)
      for parameter in declaration.inputs {
        export_type(lowering, parameter.1)
      }
    }
    let output = type_source(
      lowering,
      curry_type(declaration.inputs.map(p => p.1), declaration.output),
    )
    let env = Map::from_array(declaration.inputs)
    let body = curry_source(
      lowering,
      declaration.inputs.map(p => (lowering.locals.unwrap().names[p.0], p.1)),
      declaration.output,
      expression(
        lowering,
        declaration.body,
        declaration.output,
        env,
        declaration.fqname,
        value_node(name) + "/body",
      ),
    )
    definitions.push(
      "///|\n" +
      (if declaration.public { "pub " } else { "" }) +
      "fn " +
      identifier +
      "() -> " +
      output +
      " raise @sdk.SdkError {\n  " +
      body +
      "\n}\n",
    )
    let source_node = value_node(name)
    symbols.push({
      fqname: name.to_canonical(),
      generated_name: identifier,
      public: declaration.public,
      source_node,
      generated_node: "moonbit:fn:" + identifier,
      origins: [source_node, source_node + "/body"],
    })
  }
  // Rendered after the values, because their signatures can make a type abstract.
  let type_definitions = enums.map(e => {
    let (name, open, cases) = e
    let entry = lowering.types[name]
    "///|\n" +
    (if entry.public && open {
      "pub(all) "
    } else if entry.public {
      "pub "
    } else if lowering.abstract_types.contains(name) {
      ""
    } else {
      "priv "
    }) +
    "enum " +
    lowering.names.names["type:" + name.to_canonical()] +
    " {\n" +
    cases.join("\n") +
    "\n}\n"
  })
  let shape_names = lowering.shapes.keys().collect()
  shape_names.sort()
  for name in shape_names {
    type_definitions.push(
      "///|\n" +
      (if lowering.exported_shapes.contains(name) {
        "pub(all) "
      } else {
        "priv "
      }) +
      "struct " +
      name +
      " {\n" +
      lowering.shapes[name]
      .map(p => {
        "  " +
        field_name(lowering, name, p.0) +
        " : " +
        type_source(lowering, p.1)
      })
      .join("\n") +
      "\n}\n",
    )
  }
  let import_names = imports.keys().collect()
  import_names.sort()
  let package_manifest = "import {\n" +
    import_names
    .map(name => {
      "  " +
      quote("finos/morphir-sdk" + (if name == "sdk" { "" } else { "/" + name })) +
      " @" +
      name +
      ","
    })
    .join("\n") +
    "\n}\n"
  let module_name = "morphir-generated/p_" + hex(package_name.to_canonical())
  let module_manifest = "name = " +
    quote(module_name) +
    "\nversion = \"0.0.0\"\nimport {\n  \"finos/morphir-sdk@0.1.0\",\n}\n"
  check_cancelled()
  lowering.names.allocations.sort_by(fn(a, b) { a.owner.compare(b.owner) })
  lowering.names.warnings.sort_by(fn(a, b) { a.key().compare(b.key()) })
  let metadata = symbol_metadata(
    input,
    source_ir,
    symbols,
    owned,
    lowering.names,
  )
  let artifacts : Array[Artifact] = [
    { path: "moon.mod", role: ModuleManifest, content: Text(module_manifest), },
    {
      path: "moon.pkg",
      role: PackageManifest,
      content: Text(package_manifest),
    },
    {
      path: "library.mbt",
      role: Source,
      content: Text((type_definitions + definitions).join("\n")),
    },
    { path: "symbols.10n", role: Metadata, content: Binary(metadata), },
  ]
  let mut bytes = 0
  for artifact in artifacts {
    bytes += match artifact.content {
      Text(text) => @utf8.encode(text).length()
      Binary(data) => data.length()
    }
  }
  if bytes > limits.max_bytes {
    raise Invalid(
      "moonbit.byte_limit",
      input.unit_id,
      "Generated artifacts exceed the byte budget",
    )
  }
  check_cancelled()
  let invocations = names.filter_map(name => {
    invocation_entry(lowering, index[name])
  })
  let (invocation_codecs, invocation_types) = invocation_codecs(
    lowering, invocations,
  )
  {
    artifacts,
    symbols,
    naming_style: naming,
    naming_facts: lowering.names.facts,
    naming_allocations: lowering.names.allocations,
    warnings: lowering.names.warnings,
    invocations,
    invocation_codecs,
    invocation_types,
    invocation_rejections: names.filter_map(name => {
      let d = index[name]
      if d.public && !invocations.any(e => e.fqname == name.to_canonical()) {
        Some(
          (
            name.to_canonical(),
            if boundary_type(d.output) is None ||
              d.inputs.any(p => boundary_type(p.1) is None) {
              "execution.boundary_function"
            } else {
              "execution.constructor_visibility"
            },
          ),
        )
      } else {
        None
      }
    }),
    project: {
      module_name,
      root: "",
      members: artifacts.map(artifact => artifact.path),
      dependencies: [
        {
          module_name: "finos/morphir-sdk",
          version: "0.1.0",
          api_profile: "morphir-sdk-concrete-v1",
          semantic_pin: "bc99af69a8b24d391311fae3822a87eafef3c334",
        },
      ],
    },
  }
}
