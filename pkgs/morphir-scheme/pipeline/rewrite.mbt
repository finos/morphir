///|
/// Bottom-up traversal; replacements are not visited a second time.
pub fn rewrite_value(
  value : @ir.Value,
  transform : (@ir.Value) -> @ir.Value raise,
) -> @ir.Value raise {
  walk(value, transform, 0)
}

///|
fn walk(
  value : @ir.Value,
  transform : (@ir.Value) -> @ir.Value raise,
  depth : Int32,
) -> @ir.Value raise {
  if depth > 256 {
    raise @scheme.Limit("IR rewrite depth")
  }
  fn child(value) raise {
    walk(value, transform, depth + 1)
  }
  fn definition(value) raise {
    map_definition(value, child)
  }
  let value = match value {
    Tuple(a, items) => @ir.Value::Tuple(a, items.map(child))
    List(a, items) => @ir.Value::List(a, items.map(child))
    Record(a, fields) => @ir.Value::Record(a, @wire.map_values(fields, child))
    Apply(a, function, argument) =>
      @ir.Value::Apply(a, child(function), child(argument))
    Field(a, target, name) => @ir.Value::Field(a, child(target), name)
    Lambda(a, pattern, body) => @ir.Value::Lambda(a, pattern, child(body))
    LetDefinition(a, name, body, rest) =>
      @ir.Value::LetDefinition(a, name, definition(body), child(rest))
    LetRecursion(a, definitions, rest) =>
      @ir.Value::LetRecursion(
        a,
        @wire.map_values(definitions, definition),
        child(rest),
      )
    Destructure(a, pattern, value, body) =>
      @ir.Value::Destructure(a, pattern, child(value), child(body))
    IfThenElse(a, condition, yes, no) =>
      @ir.Value::IfThenElse(a, child(condition), child(yes), child(no))
    PatternMatch(a, target, cases) =>
      @ir.Value::PatternMatch(
        a,
        child(target),
        cases.map(pair => (pair.0, child(pair.1))),
      )
    UpdateRecord(a, target, fields) =>
      @ir.Value::UpdateRecord(a, child(target), @wire.map_values(fields, child))
    _ => value
  }
  transform(value)
}

///|
fn map_definition(
  definition : @ir.ValueDefinition,
  transform : (@ir.Value) -> @ir.Value raise,
) -> @ir.ValueDefinition raise {
  match definition {
    ExpressionBody(inputs, output, body) =>
      @ir.ValueDefinition::ExpressionBody(inputs, output, transform(body))
    ExternalBody(inputs, output, bindings, body) =>
      @ir.ValueDefinition::ExternalBody(
        inputs,
        output,
        bindings,
        body.map(transform),
      )
    IncompleteBody(inputs, output, incompleteness, body) =>
      @ir.ValueDefinition::IncompleteBody(
        inputs,
        output,
        incompleteness,
        body.map(transform),
      )
    NativeBody(_, _, _) => definition
  }
}

///|
fn map_package(
  package_def : @ir.PackageDefinition,
  transform : (@ir.Value) -> @ir.Value raise,
) -> @ir.PackageDefinition raise {
  {
    modules: @wire.map_values(package_def.modules, fn(module_def) raise {
      let values : Map[
        @ir.Name,
        @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]],
      ] = @wire.map_values(module_def.value.values, fn(value) raise {
        {
          access: value.access,
          value: {
            doc: value.value.doc,
            value: map_definition(value.value.value, transform),
          },
        }
      })
      {
        access: module_def.access,
        value: {
          types: module_def.value.types,
          values,
          doc: module_def.value.doc,
        },
      }
    }),
  }
}

///|
/// Rewrite implementation expressions while retaining types, documentation and release.
pub fn rewrite_file(
  file : @ir.IRFile,
  transform : (@ir.Value) -> @ir.Value raise,
) -> @ir.IRFile raise {
  fn root(value) raise {
    rewrite_value(value, transform)
  }
  let distribution = match file.distribution {
    Library(name, dependencies, definition) =>
      @ir.Distribution::Library(
        name,
        dependencies,
        map_package(definition, root),
      )
    Application(name, dependencies, definition, entries) =>
      @ir.Distribution::Application(
        name,
        @wire.map_values(dependencies, fn(package_def) raise {
          map_package(package_def, root)
        }),
        map_package(definition, root),
        entries,
      )
    Specs(_, _, _) => file.distribution
  }
  @ir.IRFile::new(distribution, format_version=file.format_version)
}
