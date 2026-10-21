///|
/// One import as the scope sees it. `module_name` is the dotted name; `exposing` is None for no exposing list.
priv struct ImportEntry {
  module_name : Array[String]
  import_alias : Array[String]?
  exposing : Exposed?
}

///|
priv enum Exposed {
  Everything
  Names(Map[String, Bool], Map[String, Bool]) // values, types (true = with constructors)
}

///|
/// The names that one module can use: its own declarations, its imports and the Elm default imports.
pub struct Scope {
  priv project : Project
  priv module_name : Array[String]
  priv imports : Array[ImportEntry]
  priv defaults : Array[ImportEntry]
}

///|
pub fn Project::scope(self : Project, module_name : Array[String]) -> Scope {
  let imports : Array[ImportEntry] = []
  if self.modules.get(dotted(module_name)) is Some(m) {
    for i in m.file.imports {
      imports.push({
        module_name: i.value.module_name.value.to_owned(),
        import_alias: i.value.module_alias.map(a => a.value.to_owned()),
        exposing: i.value.exposing_list.map(e => exposed_of(e.value)),
      })
    }
  }
  { project: self, module_name, imports, defaults: default_imports(), }
}

///|
fn exposed_of(exposing : @ast.Exposing) -> Exposed {
  match exposing {
    All(_) => Everything
    Explicit(items) => {
      let values : Map[String, Bool] = Map([])
      let types : Map[String, Bool] = Map([])
      for item in items {
        match item.value {
          FunctionExpose(n) | InfixExpose(n) => values[n] = true
          TypeOrAliasExpose(n) => types[n] = false
          TypeExpose({ name, open, }) => types[name] = open is Some(_)
        }
      }
      Names(values, types)
    }
  }
}

///|
/// The Elm 0.19.1 default imports.
fn default_imports() -> Array[ImportEntry] {
  fn names(values : Array[String], types : Array[(String, Bool)]) -> Exposed? {
    Some(
      Names(Map::from_array(values.map(v => (v, true))), Map::from_array(types)),
    )
  }

  [
    { module_name: ["Basics"], import_alias: None, exposing: Some(Everything), },
    {
      module_name: ["List"],
      import_alias: None,
      exposing: names(["::"], [("List", false)]),
    },
    {
      module_name: ["Maybe"],
      import_alias: None,
      exposing: names(["Just", "Nothing"], [("Maybe", true)]),
    },
    {
      module_name: ["Result"],
      import_alias: None,
      exposing: names(["Ok", "Err"], [("Result", true)]),
    },
    {
      module_name: ["String"],
      import_alias: None,
      exposing: names([], [("String", false)]),
    },
    {
      module_name: ["Char"],
      import_alias: None,
      exposing: names([], [("Char", false)]),
    },
    { module_name: ["Tuple"], import_alias: None, exposing: None, },
    { module_name: ["Debug"], import_alias: None, exposing: None, },
    {
      module_name: ["Platform"],
      import_alias: None,
      exposing: names([], [("Program", false)]),
    },
    {
      module_name: ["Platform", "Cmd"],
      import_alias: Some(["Cmd"]),
      exposing: names([], [("Cmd", false)]),
    },
    {
      module_name: ["Platform", "Sub"],
      import_alias: Some(["Sub"]),
      exposing: names([], [("Sub", false)]),
    },
  ]
}

///|
/// One name in one module. A project module must declare and export the name, unless it is this module. The
/// result is never `Local`; `True` and `False` of `Basics` are `BoolLiteral`.
fn Scope::lookup_in(
  self : Scope,
  module_name : Array[String],
  name : String,
  space : @mapping.Namespace,
) -> Resolved raise ResolveError {
  let project = self.project
  let qualified = dotted(module_name) + "." + name
  match project.kind_of(module_name) {
    ProjectModule => {
      let declarations = project.declarations_by_name(module_name)
      let own = module_name == self.module_name
      let found = match space {
        TypeSpace =>
          declarations.types.contains(name) &&
          (own || project.exports_type(module_name, name))
        ValueSpace =>
          declarations.values.contains(name) &&
          (own || project.exports_value(module_name, name))
      }
      guard found else {
        raise ResolveError(
          "elm.unresolved_name",
          "\{dotted(module_name)} does not expose \{name}",
        )
      }
      Global(project.fqname(module_name, name))
    }
    Platform =>
      raise ResolveError("elm.unsupported", "\{qualified} is not supported")
    Core(core_module) =>
      match space {
        TypeSpace =>
          match project.core.type_of(core_module, name) {
            Some(fq) => Global(fq)
            None =>
              raise ResolveError(
                "elm.unresolved_name",
                "\{qualified} is not a type",
              )
          }
        // The SDK `Bool` is opaque: morphir-elm writes `True` and `False` as literals.
        ValueSpace if core_module == "Basics" &&
          (name == "True" || name == "False") => BoolLiteral(name == "True")
        ValueSpace =>
          match project.core.value_of(core_module, name) {
            Some(fq) => Global(fq)
            None =>
              raise ResolveError(
                "elm.unsupported_value",
                "\{qualified} has no Morphir SDK binding",
              )
          }
      }
    Sdk(path, spec) => {
      let local_name = @mapping.elm_name(name)
      let found = match space {
        TypeSpace => spec.types.contains(local_name)
        ValueSpace =>
          spec.values.contains(local_name) ||
          spec.types
          .values()
          .any(t => {
            t.value.body is CustomTypeSpecification(_, constructors) &&
            constructors.contains(local_name)
          })
      }
      guard found else {
        raise ResolveError(
          "elm.unresolved_name",
          "\{qualified} is not in the Morphir SDK",
        )
      }
      Global({
        package_name: @sdk_spec.sdk_package_name(),
        module_name: path,
        local_name,
      })
    }
    Unknown =>
      raise ResolveError(
        "elm.unresolved_name",
        "the module \{dotted(module_name)} is not known",
      )
  }
}

///|
/// One lookup as data: `pick` compares the outcomes of several imports.
#warnings("-result_error_return")
fn Scope::attempt(
  self : Scope,
  module_name : Array[String],
  name : String,
  space : @mapping.Namespace,
) -> Result[Resolved, ResolveError] {
  try self.lookup_in(module_name, name, space) catch {
    e => Err(e)
  } noraise {
    r => Ok(r)
  }
}

///|
/// True when `type_name` exposed with `open` (true for `T(..)`) exposes the constructor `name`. A record alias
/// exposes its constructor with `T`. The core table does not record which type a constructor belongs to, so for
/// a core module any constructor of the module counts.
fn Scope::exposes_constructor(
  self : Scope,
  module_name : Array[String],
  type_name : String,
  open : Bool,
  name : String,
) -> Bool {
  let project = self.project
  match project.kind_of(module_name) {
    ProjectModule =>
      project.owns(module_name, type_name, name) &&
      (open || project.is_alias(module_name, type_name))
    Core(core_module) =>
      open &&
      starts_upper(name) &&
      self.attempt([core_module], name, ValueSpace) is Ok(_)
    Sdk(_, spec) =>
      open &&
      spec.types.get(@mapping.elm_name(type_name))
      is Some(
        { value: { body: CustomTypeSpecification(_, constructors), .. }, .. }
      ) &&
      constructors.contains(@mapping.elm_name(name))
    Platform | Unknown => false
  }
}

///|
fn starts_upper(name : String) -> Bool {
  for c in name {
    return c >= 'A' && c <= 'Z'
  }
  false
}

///|
/// True when the import makes `name` usable without a qualifier. `exposing (..)` counts only for the names that
/// the module has.
fn Scope::exposes(
  self : Scope,
  entry : ImportEntry,
  name : String,
  space : @mapping.Namespace,
) -> Bool {
  match entry.exposing {
    None => false
    Some(Everything) => self.attempt(entry.module_name, name, space) is Ok(_)
    Some(Names(values, types)) =>
      match space {
        TypeSpace => types.contains(name)
        ValueSpace =>
          values.contains(name) ||
          types
          .iter()
          .any(t => self.exposes_constructor(entry.module_name, t.0, t.1, name))
      }
  }
}

///|
/// The answer from several imports: one result, or `elm.ambiguous_name` for two or more different ones. When
/// none resolves, the first error.
fn pick(
  results : Array[Result[Resolved, ResolveError]],
  name : String,
) -> Resolved raise ResolveError {
  let found : Array[Resolved] = []
  let mut first_error : ResolveError? = None
  for r in results {
    match r {
      Ok(fq) => if !found.contains(fq) { found.push(fq) }
      Err(e) => if first_error is None { first_error = Some(e) }
    }
  }
  match (found, first_error) {
    ([fq], _) => fq
    ([], Some(e)) => raise e
    ([], None) =>
      raise ResolveError("elm.unresolved_name", "\{name} is not defined")
    _ =>
      raise ResolveError(
        "elm.ambiguous_name",
        "\{name} is ambiguous: " + found.map(describe).join(", "),
      )
  }
}

///|
fn describe(r : Resolved) -> String {
  match r {
    Local(n) => n
    Global(fq) => fq.to_canonical()
    BoolLiteral(b) => b.to_string()
  }
}

///|
/// A type lookup always gives a global name.
fn global(r : Resolved, name : String) -> @ir.FQName raise ResolveError {
  match r {
    Global(fq) => fq
    _ =>
      raise ResolveError(
        "elm.unresolved_name",
        "the type \{name} is not defined or imported",
      )
  }
}

///|
/// The name in the imports of one tier that expose it, or None when no import of the tier exposes it.
fn Scope::exposed_in(
  self : Scope,
  entries : Array[ImportEntry],
  name : String,
  space : @mapping.Namespace,
) -> Resolved? raise ResolveError {
  let results = entries
    .filter(e => self.exposes(e, name, space))
    .map(e => self.attempt(e.module_name, name, space))
  if results.is_empty() {
    None
  } else {
    Some(pick(results, name))
  }
}

///|
/// `Q.name`, as in Elm 0.19.1: the qualifier of an import is its alias when it has one, otherwise its full module
/// name. Every import (explicit or default) with the qualifier Q takes part; one success wins over failures, and
/// two different FQNames are `elm.ambiguous_name`.
fn Scope::qualified(
  self : Scope,
  qualifier : Array[String],
  name : String,
  space : @mapping.Namespace,
) -> Resolved raise ResolveError {
  let modules : Array[Array[String]] = []
  for e in [..self.imports, ..self.defaults] {
    if e.import_alias.unwrap_or(e.module_name) == qualifier &&
      !modules.contains(e.module_name) {
      modules.push(e.module_name)
    }
  }
  match modules {
    [] =>
      raise ResolveError(
        "elm.unresolved_name",
        "no import is called \{dotted(qualifier)}",
      )
    [module_name] => self.lookup_in(module_name, name, space)
    _ => pick(modules.map(m => self.attempt(m, name, space)), name)
  }
}

///|
/// A type name: a type of this module, then a type that an import exposes, then the default imports.
pub fn Scope::resolve_type(
  self : Scope,
  qualifier : Array[String],
  name : String,
) -> @ir.FQName raise ResolveError {
  if !qualifier.is_empty() {
    return global(self.qualified(qualifier, name, TypeSpace), name)
  }
  if self.project.declarations_by_name(self.module_name).types.contains(name) {
    return self.project.fqname(self.module_name, name)
  }
  if self.exposed_in(self.imports, name, TypeSpace) is Some(r) {
    return global(r, name)
  }
  if self.exposed_in(self.defaults, name, TypeSpace) is Some(r) {
    return global(r, name)
  }
  raise ResolveError(
    "elm.unresolved_name",
    "the type \{name} is not defined or imported",
  )
}

///|
/// A value or constructor name: a local, then a value or constructor of this module, then a name that an import
/// exposes, then the default imports.
pub fn Scope::resolve_value(
  self : Scope,
  qualifier : Array[String],
  name : String,
  is_local : (String) -> Bool,
) -> Resolved raise ResolveError {
  if !qualifier.is_empty() {
    return self.qualified(qualifier, name, ValueSpace)
  }
  if is_local(name) {
    return Local(name)
  }
  if self.project.declarations_by_name(self.module_name).values.contains(name) {
    return Global(self.project.fqname(self.module_name, name))
  }
  if self.exposed_in(self.imports, name, ValueSpace) is Some(r) {
    return r
  }
  if self.exposed_in(self.defaults, name, ValueSpace) is Some(r) {
    return r
  }
  raise ResolveError(
    "elm.unresolved_name",
    "the value \{name} is not defined or imported",
  )
}

///|
/// An operator, by morphir-elm's fixed operator table (`@mapping.morphir_operator`). Any other operator has
/// no Morphir SDK binding.
pub fn Scope::resolve_operator(
  self : Scope,
  symbol : String,
) -> @ir.FQName raise ResolveError {
  ignore(self)
  match @mapping.morphir_operator(symbol) {
    Some(fq) => fq
    None =>
      raise ResolveError(
        "elm.unsupported_value",
        "the operator \{symbol} has no Morphir SDK binding",
      )
  }
}
