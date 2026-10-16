///|
/// The modules that `morphir-elm make` 2.100.0 processes: the exposed modules and every project module that they
/// import, transitively, in work-list order. An unused import counts; a module that nothing imports does not.
fn imported_modules(
  modules : Array[@resolve.ParsedModule],
  roots : Array[@resolve.ParsedModule],
) -> Array[@resolve.ParsedModule] {
  let by_name : Map[String, @resolve.ParsedModule] = Map([])
  for m in modules {
    by_name[dotted(m.name)] = m
  }
  let seen : Set[String] = Set([])
  let processed : Array[@resolve.ParsedModule] = []
  for m in roots {
    seen.add(dotted(m.name))
    processed.push(m)
  }
  let mut i = 0
  while i < processed.length() {
    for name in processed[i].imports() {
      let key = dotted(name)
      if !seen.contains(key) && by_name.get(key) is Some(m) {
        seen.add(key)
        processed.push(m)
      }
    }
    i += 1
  }
  processed
}

///|
/// The modules that one module depends on in the morphir-elm module graph: the modules of the names in its type
/// definitions (every constructor, whatever its access) and of the value references in its bodies. Value
/// signatures and constructors in bodies do not count. morphir-elm compares module paths only, without the
/// package, so an SDK module such as `basics` stands for a project module with the same path.
fn module_dependencies(
  path : @ir.Path,
  definition : @ir.ModuleDefinition,
  body_values : Array[@ir.FQName],
) -> Array[@ir.Path] {
  let names : Array[@ir.FQName] = []
  for _, t in definition.types {
    type_definition_references(t.value.value, names)
  }
  names.append(body_values)
  let out : Array[@ir.Path] = []
  for name in names {
    if name.module_name != path && !out.contains(name.module_name) {
      out.push(name.module_name)
    }
  }
  out
}

///|
/// The exposed modules and every module that they reach in the module graph `edges`, transitively.
fn used_modules(
  exposed : Array[@ir.Path],
  edges : Map[@ir.Path, Array[@ir.Path]],
) -> Set[@ir.Path] {
  let used : Set[@ir.Path] = Set([])
  let work : Array[@ir.Path] = []
  for path in exposed {
    if !used.contains(path) {
      used.add(path)
      work.push(path)
    }
  }
  while work.pop() is Some(path) {
    for next in edges.get(path).unwrap_or([]) {
      if !used.contains(next) {
        used.add(next)
        work.push(next)
      }
    }
  }
  used
}

///|
/// The modules that morphir-elm makes `Public` although they are not exposed (`collectImplicitlyExposedModules`).
/// It starts from the names in the public type definitions and the public value signatures of the exposed
/// modules. It takes the least name each time, in Elm order. A name of this package in a module that is not
/// exposed and not yet public makes the module public and adds the names of the type definition it names. A name
/// in a module that is already public adds nothing, so only the first name of each module is followed.
fn implicitly_exposed(
  package_name : @ir.Path,
  modules : Map[@ir.Path, @ir.ModuleDefinition],
  exposed : Array[@ir.Path],
) -> Set[@ir.Path] {
  let pending : Array[@ir.FQName] = []
  for path in exposed {
    guard modules.get(path) is Some(m) else { continue }
    for _, t in m.types {
      exposed_type_references(t, pending)
    }
    for _, v in m.values {
      if v.access is Public {
        value_signature_references(v.value.value, pending)
      }
    }
  }
  let implicit : Set[@ir.Path] = Set([])
  while least(pending) is Some(name) {
    if name.package_name != package_name ||
      exposed.contains(name.module_name) ||
      implicit.contains(name.module_name) {
      continue
    }
    if modules.get(name.module_name) is Some(m) &&
      m.types.get(name.local_name) is Some(t) {
      exposed_type_references(t, pending)
    }
    implicit.add(name.module_name)
  }
  implicit
}

///|
/// Removes and returns the least name of `names` in Elm order. `names` holds each name once.
fn least(names : Array[@ir.FQName]) -> @ir.FQName? {
  if names.is_empty() {
    return None
  }
  let mut index = 0
  for i in 1..<names.length() {
    if elm_compare_fqname(names[i], names[index]) < 0 {
      index = i
    }
  }
  Some(names.remove(index))
}

///|
/// The names that a public type definition shows: the target of a type alias, and the constructor arguments of a
/// custom type with public constructors. They are added to `out` once each.
fn exposed_type_references(
  t : @ir.AccessControlled[@ir.Documented[@ir.TypeDefinition]],
  out : Array[@ir.FQName],
) -> Unit {
  guard t.access is Public else { return }
  match t.value.value {
    CustomTypeDefinition(_, constructors) if constructors.access is Private =>
      ()
    definition => type_definition_references(definition, out)
  }
}

///|
fn type_definition_references(
  definition : @ir.TypeDefinition,
  out : Array[@ir.FQName],
) -> Unit {
  match definition {
    TypeAliasDefinition(_, target) => type_references(target, out)
    CustomTypeDefinition(_, constructors) =>
      for _, args in constructors.value {
        for arg in args {
          type_references(arg.1, out)
        }
      }
    IncompleteTypeDefinition(_, _, target) =>
      if target is Some(t) {
        type_references(t, out)
      }
  }
}

///|
fn value_signature_references(
  definition : @ir.ValueDefinition,
  out : Array[@ir.FQName],
) -> Unit {
  match definition {
    ExpressionBody(inputs, output, _)
    | NativeBody(inputs, output, _)
    | ExternalBody(inputs, output, _, _) => {
      type_references(output, out)
      for input in inputs {
        type_references(input.1, out)
      }
    }
    IncompleteBody(inputs, output, _, _) => {
      if output is Some(t) {
        type_references(t, out)
      }
      for input in inputs {
        type_references(input.1, out)
      }
    }
  }
}

///|
/// The names of the type references in `t`, added to `out` once each.
fn type_references(t : @ir.Type, out : Array[@ir.FQName]) -> Unit {
  match t {
    Variable(_, _) | Unit(_) => ()
    Reference(_, name, args) => {
      if !out.contains(name) {
        out.push(name)
      }
      for a in args {
        type_references(a, out)
      }
    }
    Tuple(_, items) =>
      for item in items {
        type_references(item, out)
      }
    Record(_, fields) | ExtensibleRecord(_, _, fields) =>
      for _, field in fields {
        type_references(field, out)
      }
    Function(_, argument, result) => {
      type_references(argument, out)
      type_references(result, out)
    }
  }
}

///|
/// Elm `compare` on a morphir-elm `FQName`: the package path, the module path and the local name, each a list of
/// names, and each name a list of words that compare by code units.
fn elm_compare_fqname(a : @ir.FQName, b : @ir.FQName) -> Int32 {
  let package_order = elm_compare_path(a.package_name, b.package_name)
  if package_order != 0 {
    return package_order
  }
  let module_order = elm_compare_path(a.module_name, b.module_name)
  if module_order != 0 {
    return module_order
  }
  elm_compare_list(
    a.local_name.to_words(),
    b.local_name.to_words(),
    elm_compare_string,
  )
}

///|
fn elm_compare_path(a : @ir.Path, b : @ir.Path) -> Int32 {
  elm_compare_list(a.to_names(), b.to_names(), (x, y) => {
    elm_compare_list(x.to_words(), y.to_words(), elm_compare_string)
  })
}

///|
fn[T] elm_compare_list(
  a : Array[T],
  b : Array[T],
  item : (T, T) -> Int32,
) -> Int32 {
  let shorter = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<shorter {
    let order = item(a[i], b[i])
    if order != 0 {
      return order
    }
  }
  a.length().compare(b.length())
}

///|
/// Strings in code-unit order, as Elm compares them. `String::compare` puts shorter strings first.
fn elm_compare_string(a : String, b : String) -> Int32 {
  let shorter = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<shorter {
    if a.code_unit_at(i) != b.code_unit_at(i) {
      return a.code_unit_at(i).compare(b.code_unit_at(i))
    }
  }
  a.length().compare(b.length())
}
