///|
fn collect_package_definitions(
  definitions : Map[String, @ir.ValueDefinition],
  package_name : @ir.PackageName,
  package_definition : @ir.PackageDefinition,
) -> Unit {
  for module_name, module_definition in package_definition.modules {
    for local_name, definition in module_definition.value.values {
      let name : @ir.FQName = { package_name, module_name, local_name, }
      definitions[name.to_canonical()] = definition.value.value
    }
  }
}

///|
fn file_definitions(
  file : @ir.IRFile,
) -> Map[String, @ir.ValueDefinition] raise @scheme.SchemeError {
  let definitions : Map[String, @ir.ValueDefinition] = Map([])
  match file.distribution {
    @ir.Distribution::Library(name, _, package_definition) =>
      collect_package_definitions(definitions, name, package_definition)
    @ir.Distribution::Application(name, dependencies, package_definition, _) => {
      for dependency, implementation in dependencies {
        collect_package_definitions(definitions, dependency, implementation)
      }
      collect_package_definitions(definitions, name, package_definition)
    }
    @ir.Distribution::Specs(_, _, _) =>
      raise @scheme.Unsupported("A Specs distribution has no executable bodies")
  }
  definitions
}

///|
fn native_arity(
  runtime : @scheme.Runtime,
  binding : String,
  expected : Int32,
) -> Unit raise @scheme.SchemeError {
  if runtime.native_arity(binding) is Some(actual) && actual != expected {
    raise @scheme.Invalid(
      "Native binding arity mismatch: " +
      binding +
      " expects " +
      expected.to_string() +
      ", registered " +
      actual.to_string(),
    )
  }
}

///|
fn runtime_external_bindings(
  bindings : Array[@ir.ExternalBinding],
) -> Array[String] {
  let names : Array[String] = []
  for candidate in bindings {
    if candidate.target_platform == "morphir-runtime" ||
      candidate.target_platform == "morphir-scheme" ||
      candidate.target_platform == "scheme" {
      names.push("external:" + candidate.external_name)
    }
  }
  names
}

///|
fn resolve_definition(
  runtime : @scheme.Runtime,
  name : String,
  definition : @ir.ValueDefinition,
) -> String? raise @scheme.SchemeError {
  match definition {
    @ir.ValueDefinition::ExpressionBody(inputs, _, _) => {
      let binding = "accelerator:" + name
      if runtime.has_native(binding) {
        native_arity(runtime, binding, inputs.length())
        Some(binding)
      } else {
        None
      }
    }
    @ir.ValueDefinition::NativeBody(inputs, _, _) => {
      let binding = "external:" + name
      if !runtime.has_native(binding) {
        raise @scheme.Unbound(binding)
      }
      native_arity(runtime, binding, inputs.length())
      Some(binding)
    }
    @ir.ValueDefinition::ExternalBody(inputs, _, bindings, fallback) => {
      for binding in runtime_external_bindings(bindings) {
        if runtime.has_native(binding) {
          native_arity(runtime, binding, inputs.length())
          return Some(binding)
        }
      }
      if fallback is None {
        raise @scheme.Unbound("No runtime binding or fallback for " + name)
      }
      None
    }
    @ir.ValueDefinition::IncompleteBody(_, _, _, _) =>
      raise @scheme.Unsupported("Cannot execute incomplete definition: " + name)
  }
}

///|
/// Check required bindings before executing any definitions.
pub fn link_file(runtime : @scheme.Runtime, file : @ir.IRFile) -> Unit raise {
  let definitions = file_definitions(file)
  for name, definition in definitions {
    ignore(resolve_definition(runtime, name, definition))
  }
}

///|
fn collect_call(value : @ir.Value, arguments : Array[@ir.Value]) -> @ir.FQName? {
  match value {
    @ir.Value::Apply(_, function, argument) => {
      arguments.push(argument)
      collect_call(function, arguments)
    }
    @ir.Value::Reference(_, name) => Some(name)
    _ => None
  }
}

///|
fn evaluate_native(
  runtime : @scheme.Runtime,
  value : @ir.Value,
) -> @scheme.Value raise {
  match value {
    @ir.Value::Literal(_, literal) =>
      match literal {
        @ir.Literal::BoolLiteral(value) => @scheme.Value::Boolean(value)
        @ir.Literal::CharLiteral(value) => @scheme.Value::Character(value)
        @ir.Literal::StringLiteral(value) => @scheme.Value::Text(value)
        @ir.Literal::IntegerLiteral(value) => @scheme.integer(value)
        @ir.Literal::FloatLiteral(value) =>
          @scheme.Value::Number(@scheme.Number::Real(value))
        @ir.Literal::DecimalLiteral(value) =>
          @scheme.Value::Tagged("decimal", [@scheme.Value::Text(value)])
        _ => runtime.eval(emit_expression(value))
      }
    _ => {
      let arguments : Array[@ir.Value] = []
      if collect_call(value, arguments) is Some(name) {
        let fq = name.to_canonical()
        if arguments.length() == 2 &&
          (fq == "morphir/SDK:basics#and" || fq == "morphir/SDK:basics#or") {
          let left = sdk_bool(evaluate_native(runtime, arguments[1]))
          if fq == "morphir/SDK:basics#and" && !left {
            return @scheme.Boolean(false)
          }
          if fq == "morphir/SDK:basics#or" && left {
            return @scheme.Boolean(true)
          }
          return @scheme.Boolean(
            sdk_bool(evaluate_native(runtime, arguments[0])),
          )
        }
        let binding = "accelerator:" + name.to_canonical()
        if runtime.native_arity(binding) is Some(expected) &&
          arguments.length() == expected {
          let values : Array[@scheme.Value] = []
          for i = arguments.length() - 1; i >= 0; i = i - 1 {
            values.push(evaluate_native(runtime, arguments[i]))
          }
          return runtime.call(runtime.lookup(binding), values)
        }
      }
      runtime.eval(emit_expression(value))
    }
  }
}

///|
/// Direct calls bypass Scheme emission and parsing when a full native binding
/// exists. Other expressions use the existing Scheme evaluator.
pub fn evaluate_in(
  runtime : @scheme.Runtime,
  value : @ir.Value,
) -> @scheme.Value raise {
  runtime.with_budget(rt => evaluate_native(rt, value))
}

///|
/// A host can install bindings on runtime before calling this function.
pub fn run_file_in(
  runtime : @scheme.Runtime,
  file : @ir.IRFile,
  entry : @ir.FQName,
  arguments : Array[@scheme.Value],
) -> @scheme.Value raise {
  let definitions = file_definitions(file)
  let entry_name = entry.to_canonical()
  let definition = match definitions.get(entry_name) {
    Some(definition) => definition
    None => raise @scheme.Unbound(entry_name)
  }
  for name, value in definitions {
    ignore(resolve_definition(runtime, name, value))
  }
  let binding = resolve_definition(runtime, entry_name, definition)
  let expected = match definition.to_specification() {
    Some(specification) => specification.inputs.length()
    None => raise @scheme.Unsupported("Entry has no complete signature")
  }
  runtime.with_budget(rt => {
    if binding is Some(binding) && arguments.length() == expected {
      return rt.call(rt.lookup(binding), arguments)
    }
    ignore(rt.eval(emit_file(file)))
    call_entry(rt, entry, arguments)
  })
}
