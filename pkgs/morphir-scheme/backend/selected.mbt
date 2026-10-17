///|
pub(all) suberror SelectedReferenceError {
  SelectedReferenceInvalid(String)
}

///|
/// Prepare a static declaration-reference closure for one selected call. This
/// walks dormant code too; deferred emission does not relax identity or access checks.
pub fn selected_file(file : @ir.IRFile, entry : @ir.FQName) -> @ir.IRFile raise {
  guard file.distribution is Library(package_name, dependencies, package_def) else {
    raise @scheme.Unsupported("Selected Scheme planning requires a library")
  }
  let definitions = file_definitions(file)
  let needed : Map[String, Bool] = Map([])
  let constructors : Map[String, Bool] = Map([])
  let module_globals : Map[@ir.ModuleName, Map[@ir.Name, String]] = Map([])
  let value_access : Map[String, (@ir.ModuleName, Bool)] = Map([])
  let constructor_access : Map[String, (@ir.ModuleName, Bool)] = Map([])
  for module_name, module_def in package_def.modules {
    let globals : Map[@ir.Name, String] = Map([])
    for local_name, definition in module_def.value.values {
      let name : @ir.FQName = { package_name, module_name, local_name, }
      globals[local_name] = name.to_canonical()
      value_access[name.to_canonical()] = (
        module_name,
        definition.access is Public,
      )
    }
    for _, definition in module_def.value.types {
      if definition.value.value is CustomTypeDefinition(_, variants) {
        for local_name, _ in variants.value {
          let name : @ir.FQName = { package_name, module_name, local_name, }
          constructor_access[name.to_canonical()] = (
            module_name,
            definition.access is Public && variants.access is Public,
          )
        }
      }
    }
    module_globals[module_name] = globals
  }
  let pending = [entry.to_canonical()]
  while !pending.is_empty() {
    let name = pending.pop().unwrap()
    if needed.contains(name) {
      continue
    }
    guard definitions.get(name) is Some(definition) else {
      raise @scheme.Unbound(name)
    }
    needed[name] = true
    let owner = @ir.FQName::parse(name)
    let globals = module_globals[owner.module_name]
    let references = SelectedReferences::{
      globals,
      pending,
      constructors,
      value_access,
      constructor_access,
      owner: owner.module_name,
    }
    references.definition(definition, Map([]), 0)
  }
  let modules : Map[@ir.ModuleName, @ir.AccessControlled[@ir.ModuleDefinition]] = Map([],
  )
  for module_name, module_def in package_def.modules {
    let values = Map([])
    for name, definition in module_def.value.values {
      let fq : @ir.FQName = { package_name, module_name, local_name: name, }
      if needed.contains(fq.to_canonical()) {
        values[name] = definition
      }
    }
    let types = Map([])
    for name, definition in module_def.value.types {
      if definition.value.value is CustomTypeDefinition(params, variants) {
        let selected = Map([])
        for constructor_name, inputs in variants.value {
          let fq : @ir.FQName = {
            package_name,
            module_name,
            local_name: constructor_name,
          }
          if constructors.contains(fq.to_canonical()) {
            selected[constructor_name] = inputs
          }
        }
        if !selected.is_empty() {
          types[name] = {
            ..definition,
            value: {
              ..definition.value,
              value: CustomTypeDefinition(params, {
                ..variants,
                value: selected,
              }),
            },
          }
        }
      }
    }
    modules[module_name] = {
      ..module_def,
      value: { ..module_def.value, values, types, },
    }
  }
  @ir.IRFile::new(
    Library(package_name, dependencies, { modules, }),
    format_version=file.format_version,
  )
}

///|
priv struct SelectedReferences {
  globals : Map[@ir.Name, String]
  pending : Array[String]
  constructors : Map[String, Bool]
  value_access : Map[String, (@ir.ModuleName, Bool)]
  constructor_access : Map[String, (@ir.ModuleName, Bool)]
  owner : @ir.ModuleName
}

///|
fn SelectedReferences::include_constructor(
  self : SelectedReferences,
  name : @ir.FQName,
) -> Unit raise {
  let key = name.to_canonical()
  match self.constructor_access.get(key) {
    Some((owner, exposed)) => {
      if owner != self.owner && !exposed {
        raise SelectedReferenceInvalid("execution.constructor_visibility")
      }
      self.constructors[key] = true
    }
    None =>
      match key {
        "morphir/SDK:maybe#just"
        | "morphir/SDK:maybe#nothing"
        | "morphir/SDK:result#ok"
        | "morphir/SDK:result#err" => ()
        _ => raise @scheme.Unbound(key)
      }
  }
}

///|
fn SelectedReferences::pattern(
  self : SelectedReferences,
  pattern : @ir.Pattern,
  bound : Map[@ir.Name, Bool],
  depth : Int32,
) -> Unit raise {
  if depth > 256 {
    raise @scheme.Limit("Pattern depth")
  }
  match pattern {
    AsPattern(_, pattern, name) => {
      bound[name] = true
      self.pattern(pattern, bound, depth + 1)
    }
    TuplePattern(_, patterns) | ConstructorPattern(_, _, patterns) => {
      if pattern is ConstructorPattern(_, name, _) {
        self.include_constructor(name)
      }
      for pattern in patterns {
        self.pattern(pattern, bound, depth + 1)
      }
    }
    HeadTailPattern(_, head, tail) => {
      self.pattern(head, bound, depth + 1)
      self.pattern(tail, bound, depth + 1)
    }
    _ => ()
  }
}

///|
fn SelectedReferences::definition(
  self : SelectedReferences,
  definition : @ir.ValueDefinition,
  bound : Map[@ir.Name, Bool],
  depth : Int32,
) -> Unit raise {
  match definition {
    ExpressionBody(inputs, _, body)
    | ExternalBody(inputs, _, _, Some(body))
    | IncompleteBody(inputs, _, _, Some(body)) => {
      let scope = bound.copy()
      for input in inputs {
        scope[input.0] = true
      }
      self.value(body, scope, depth + 1)
    }
    _ => ()
  }
}

///|
fn SelectedReferences::value(
  self : SelectedReferences,
  value : @ir.Value,
  bound : Map[@ir.Name, Bool],
  depth : Int32,
) -> Unit raise {
  if depth > 256 {
    raise @scheme.Limit("IR backend depth")
  }
  fn child(value : @ir.Value) -> Unit raise {
    self.value(value, bound, depth + 1)
  }
  match value {
    Variable(_, name) =>
      if !bound.contains(name) {
        match self.globals.get(name) {
          Some(global) => self.pending.push(global)
          None => raise @scheme.Unbound(name.to_canonical())
        }
      }
    Reference(_, name) =>
      if name.package_name.to_canonical() != "morphir/SDK" &&
        source_string_arity(name.to_canonical()) is None {
        if self.value_access.get(name.to_canonical()) is Some((owner, exposed)) &&
          owner != self.owner &&
          !exposed {
          raise SelectedReferenceInvalid("execution.reference_visibility")
        }
        self.pending.push(name.to_canonical())
      }
    Constructor(_, name) => self.include_constructor(name)
    Tuple(_, values) | List(_, values) => values.each(child)
    Record(_, values) => values.values().each(child)
    Field(_, value, _) => child(value)
    Apply(_, function, argument) => {
      child(function)
      child(argument)
    }
    Lambda(_, pattern, body) => {
      let scope = bound.copy()
      self.pattern(pattern, scope, 0)
      self.value(body, scope, depth + 1)
    }
    LetDefinition(_, name, definition, body) => {
      self.definition(definition, bound, depth + 1)
      let scope = bound.copy()
      scope[name] = true
      self.value(body, scope, depth + 1)
    }
    LetRecursion(_, definitions, body) => {
      let scope = bound.copy()
      for name, _ in definitions {
        scope[name] = true
      }
      for _, definition in definitions {
        self.definition(definition, scope, depth + 1)
      }
      self.value(body, scope, depth + 1)
    }
    Destructure(_, pattern, value, body) => {
      child(value)
      let scope = bound.copy()
      self.pattern(pattern, scope, 0)
      self.value(body, scope, depth + 1)
    }
    IfThenElse(_, condition, yes, no) => {
      child(condition)
      child(yes)
      child(no)
    }
    PatternMatch(_, value, cases) => {
      child(value)
      for (pattern, body) in cases {
        let scope = bound.copy()
        self.pattern(pattern, scope, 0)
        self.value(body, scope, depth + 1)
      }
    }
    UpdateRecord(_, value, fields) => {
      child(value)
      fields.values().each(child)
    }
    _ => ()
  }
}
