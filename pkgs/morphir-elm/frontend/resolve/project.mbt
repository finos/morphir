///|
/// What a module exports. `all` is true for `exposing (..)`: every declaration, types with constructors.
/// Otherwise `types[name]` is true when the constructors are exported too (`T(..)`) and false for `T`.
pub(all) struct Exports {
  all : Bool
  values : Map[String, Bool]
  types : Map[String, Bool]
} derive(Eq, Debug)

///|
pub extend Exports with Eq::{equal, not_equal}

///|
pub extend Exports with @debug.Debug::{to_repr}

///|
/// The declarations of one project module, by Elm name.
priv struct Declarations {
  values : Map[String, Bool] // top-level values and constructors
  types : Map[String, Array[String]] // type name to its constructors (empty for an alias)
  owners : Map[String, String] // constructor to its type; a record alias is its own constructor
}

///|
/// The project symbol table: the declarations and exports of every project module.
pub struct Project {
  priv pkg_segs : Array[String]
  priv modules : Map[String, ParsedModule] // by dotted name
  priv paths : Map[@ir.Path, Array[String]] // IR module path to module name
  priv declarations : Map[String, Declarations]
  priv export_table : Map[String, Exports]
  priv core : @mapping.ElmCore
  priv sdk : @ir.PackageSpecification
}

///|
/// The kind of an imported module, which says where its names come from.
priv enum ModuleKind {
  ProjectModule
  Platform
  Core(String)
  Sdk(@ir.Path, @ir.ModuleSpecification)
  Unknown
}

///|
/// The Elm modules that exist but have no Morphir form.
let platform_modules : Array[String] = [
  "Debug", "Platform", "Platform.Cmd", "Platform.Sub",
]

///|
fn dotted(segments : Array[String]) -> String {
  segments.join(".")
}

///|
fn problem(
  code : String,
  message : String,
  path : String,
  range : @ast.Range,
) -> ResolveProblem {
  { code, message, path, range: Some(range), }
}

///|
/// Builds the symbol table. It checks every exposing list and every import, and raises all problems at once.
pub fn Project::new(
  pkg_segs : Array[String],
  modules : Array[ParsedModule],
) -> Project raise ResolveFailed {
  let (project, by_module) = Project::with_problems(pkg_segs, modules)
  let problems : Array[ResolveProblem] = []
  for m in modules {
    problems.append(by_module.get(dotted(m.name)).unwrap_or([]))
  }
  if !problems.is_empty() {
    raise ResolveFailed(problems)
  }
  project
}

///|
/// Builds the symbol table and checks the exposing list, the imports and the declarations of every module. The
/// problems are by dotted module name, in source order in each module: the header exposing list, the imports,
/// the declarations. A module without problems has an empty list.
pub fn Project::with_problems(
  pkg_segs : Array[String],
  modules : Array[ParsedModule],
) -> (Project, Map[String, Array[ResolveProblem]]) {
  let project : Project = {
    pkg_segs,
    modules: Map([]),
    paths: Map([]),
    declarations: Map([]),
    export_table: Map([]),
    core: @mapping.ElmCore::builtin(),
    sdk: @sdk_spec.sdk_specification(),
  }
  let declaration_problems : Map[String, Array[ResolveProblem]] = Map([])
  for m in modules {
    let key = dotted(m.name)
    project.modules[key] = m
    project.paths[project.module_path(m.name)] = m.name
    let (declarations, problems) = declarations_of(m)
    project.declarations[key] = declarations
    declaration_problems[key] = problems
  }
  let by_module : Map[String, Array[ResolveProblem]] = Map([])
  for m in modules {
    let key = dotted(m.name)
    let problems : Array[ResolveProblem] = []
    project.export_table[key] = project.exports_of(m, problems)
    project.check_imports(m, problems)
    problems.append(declaration_problems.get(key).unwrap_or([]))
    by_module[key] = problems
  }
  (project, by_module)
}

///|
fn declarations_of(m : ParsedModule) -> (Declarations, Array[ResolveProblem]) {
  let declarations : Declarations = {
    values: Map([]),
    types: Map([]),
    owners: Map([]),
  }
  let problems : Array[ResolveProblem] = []
  for d in m.file.declarations {
    match d.value {
      FunctionDeclaration(f) =>
        declarations.values[f.declaration.value.name.value] = true
      AliasDeclaration(a) => {
        let name = a.name.value
        declarations.types[name] = []
        // A record alias is also a value constructor.
        if a.type_annotation.value is Record(_) {
          declarations.values[name] = true
          declarations.owners[name] = name
        }
      }
      CustomTypeDeclaration(t) => {
        let constructors = t.constructors
          .iter()
          .map(c => c.value.name.value)
          .collect()
        declarations.types[t.name.value] = constructors
        for c in constructors {
          declarations.values[c] = true
          declarations.owners[c] = t.name.value
        }
      }
      PortDeclaration(_) =>
        problems.push(
          problem("elm.unsupported", "ports are not supported", m.path, d.range),
        )
      InfixDeclaration(_) =>
        problems.push(
          problem(
            "elm.unsupported",
            "infix declarations are not supported",
            m.path,
            d.range,
          ),
        )
      Destructuring(_, _) =>
        problems.push(
          problem(
            "elm.unsupported",
            "top-level destructuring is not supported",
            m.path,
            d.range,
          ),
        )
    }
  }
  (declarations, problems)
}

///|
/// The exports of a module from its header exposing list. An entry that names no declaration is a problem.
fn Project::exports_of(
  self : Project,
  m : ParsedModule,
  problems : Array[ResolveProblem],
) -> Exports {
  let declarations = self.declarations_by_name(m.name)
  let values : Map[String, Bool] = Map([])
  let types : Map[String, Bool] = Map([])
  guard m.header().exposing_list.value is Explicit(items) else {
    return { all: true, values, types, }
  }
  fn missing(name : String, range : @ast.Range) {
    problems.push(
      problem(
        "elm.unresolved_name",
        "the module does not declare \{name}",
        m.path,
        range,
      ),
    )
  }

  for item in items {
    match item.value {
      FunctionExpose(n) =>
        if declarations.values.contains(n) {
          values[n] = true
        } else {
          missing(n, item.range)
        }
      TypeOrAliasExpose(n) =>
        if declarations.types.contains(n) {
          types[n] = false
        } else {
          missing(n, item.range)
        }
      TypeExpose({ name, open, }) =>
        if declarations.types.contains(name) {
          types[name] = open is Some(_)
        } else {
          missing(name, item.range)
        }
      InfixExpose(op) =>
        problems.push(
          problem(
            "elm.unsupported",
            "exposing the operator \{op} is not supported",
            m.path,
            item.range,
          ),
        )
    }
  }
  { all: false, values, types, }
}

///|
/// Every import must be a project module, an Elm core module, a platform module or a `Morphir.SDK` module.
fn Project::check_imports(
  self : Project,
  m : ParsedModule,
  problems : Array[ResolveProblem],
) -> Unit {
  for i in m.file.imports {
    let name = i.value.module_name.value.to_owned()
    if self.kind_of(name) is Unknown {
      problems.push(
        problem(
          "elm.unsupported_module",
          "the package of \{dotted(name)} is not supported",
          m.path,
          i.range,
        ),
      )
    }
  }
}

///|
fn Project::kind_of(self : Project, module_name : Array[String]) -> ModuleKind {
  let key = dotted(module_name)
  if self.modules.contains(key) {
    return ProjectModule
  }
  if platform_modules.contains(key) {
    return Platform
  }
  if self.core.is_core_module(key) {
    return Core(key)
  }
  if module_name is ["Morphir", "SDK", sdk_module] {
    let path = @mapping.elm_path([sdk_module])
    if self.sdk.modules.get(path) is Some(spec) {
      return Sdk(path, spec)
    }
  }
  Unknown
}

///|
fn Project::declarations_by_name(
  self : Project,
  module_name : Array[String],
) -> Declarations {
  self.declarations
  .get(dotted(module_name))
  .unwrap_or({ values: Map([]), types: Map([]), owners: Map([]), })
}

///|
/// True when the project module exports the type.
fn Project::exports_type(
  self : Project,
  module_name : Array[String],
  name : String,
) -> Bool {
  let exports = self.exports(module_name)
  exports.all || exports.types.contains(name)
}

///|
/// True when the project module exports the value or constructor. A constructor goes with `T(..)`; a record
/// alias constructor goes with the alias.
fn Project::exports_value(
  self : Project,
  module_name : Array[String],
  name : String,
) -> Bool {
  let exports = self.exports(module_name)
  if exports.all || exports.values.contains(name) {
    return true
  }
  guard self.declarations_by_name(module_name).owners.get(name) is Some(owner) else {
    return false
  }
  if self.is_alias(module_name, owner) {
    exports.types.contains(owner)
  } else {
    exports.types.get(owner) is Some(true)
  }
}

///|
fn Project::is_alias(
  self : Project,
  module_name : Array[String],
  type_name : String,
) -> Bool {
  self.declarations_by_name(module_name).types.get(type_name)
  is Some(constructors) &&
  constructors.is_empty()
}

///|
/// True when `name` is a constructor of the type `type_name` of a project module.
fn Project::owns(
  self : Project,
  module_name : Array[String],
  type_name : String,
  name : String,
) -> Bool {
  self.declarations_by_name(module_name).owners.get(name) is Some(owner) &&
  owner == type_name
}

///|
fn Project::module_path(
  self : Project,
  module_name : Array[String],
) -> @ir.Path {
  let n = self.pkg_segs.length()
  let start = if module_name.length() > n &&
    module_name[:n].to_owned() == self.pkg_segs {
    n
  } else {
    0
  }
  @mapping.elm_path(module_name[start:].to_owned())
}

///|
/// The FQName of a declaration of a project module.
pub fn Project::fqname(
  self : Project,
  module_name : Array[String],
  name : String,
) -> @ir.FQName {
  {
    package_name: @mapping.elm_path(self.pkg_segs),
    module_name: self.module_path(module_name),
    local_name: @mapping.elm_name(name),
  }
}

///|
/// The project module of an FQName of this package, if there is one.
fn Project::module_of(self : Project, fq : @ir.FQName) -> Array[String]? {
  if fq.package_name != @mapping.elm_path(self.pkg_segs) {
    return None
  }
  self.paths.get(fq.module_name)
}

///|
/// What a project module exports. A module that is not in the project exports nothing.
pub fn Project::exports(self : Project, module_name : Array[String]) -> Exports {
  self.export_table
  .get(dotted(module_name))
  .unwrap_or({ all: false, values: Map([]), types: Map([]), })
}
