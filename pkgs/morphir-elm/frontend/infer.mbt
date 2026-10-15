///|
/// Infers the type of every value and pattern node of the library with the shared IR inference, then makes each
/// whole-number literal of type `Float` a float literal, as morphir-elm does. `module_sources` maps the canonical
/// module path (`foo/bar`) to the source path of the module. Each inference problem is an `elm.type` problem at
/// the source of its module.
fn infer_library(
  file : @ir.IRFile,
  module_sources : Map[String, String],
) -> @ir.IRFile raise ElmFailed {
  let deps = Map::from_array([
    (@sdk_spec.sdk_package_name(), @sdk_spec.sdk_specification()),
  ])
  let filled = @typing.infer(file, deps, Fill) catch {
    @typing.InferenceFailed(problems) =>
      raise ElmFailed(
        problems.map(p => {
          code: "elm.type",
          message: p.display(),
          path: module_sources.get(node_module(p.node)).unwrap_or(""),
          location: p.source,
        }),
      )
  }
  fix_number_literals(filled, deps)
}

///|
/// The canonical module path of a logical path `value:<package>:<module>#<name>…` or `type:<package>:<module>#<name>`.
/// Empty when the path has no module.
fn node_module(node : String) -> String {
  let declaration = match node.find("#") {
    Some(i) => node.unsafe_substring(start=0, end=i)
    None => node
  }
  let parts = declaration.split(":").map(s => s.to_owned()).collect()
  if parts.length() == 3 {
    parts[2]
  } else {
    ""
  }
}

///|
/// morphir-elm `Infer.fixNumberLiterals`: a whole-number literal whose inferred type is `Float`, or an alias of
/// `Float` resolved one level as `Distribution.resolveType` does, becomes a float literal. It rewrites the values of
/// every body and let definition, but not the patterns.
fn fix_number_literals(
  file : @ir.IRFile,
  deps : Map[@ir.Path, @ir.PackageSpecification],
) -> @ir.IRFile {
  guard file.distribution is Library(package_name, dependencies, def) else {
    return file
  }
  let aliases = Aliases::{ package_name, def, deps, }
  let modules : Map[@ir.Path, @ir.AccessControlled[@ir.ModuleDefinition]] = Map([],
  )
  for path, m in def.modules {
    let values : Map[
      @ir.Name,
      @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]],
    ] = Map([])
    for name, v in m.value.values {
      values[name] = {
        ..v,
        value: { ..v.value, value: aliases.fix_definition(v.value.value), },
      }
    }
    modules[path] = { ..m, value: { ..m.value, values, }, }
  }
  @ir.IRFile::new(
    Library(package_name, dependencies, { modules, }),
    format_version=file.format_version,
  ) catch {
    e => abort("the current IR version is not valid: " + @debug.to_string(e))
  }
}

///|
/// The type aliases that `fix_number_literals` can resolve: those of the library and of its dependencies.
priv struct Aliases {
  package_name : @ir.Path
  def : @ir.PackageDefinition
  deps : Map[@ir.Path, @ir.PackageSpecification]
}

///|
fn Aliases::fix_definition(
  self : Aliases,
  d : @ir.ValueDefinition,
) -> @ir.ValueDefinition {
  match d {
    ExpressionBody(inputs, output, body) =>
      ExpressionBody(inputs, output, self.fix(body))
    other => other
  }
}

///|
fn Aliases::fix(self : Aliases, v : @ir.Value) -> @ir.Value {
  let all = (items : Array[@ir.Value]) => items.map(x => self.fix(x))
  let fields = (items : Map[@ir.Name, @ir.Value]) => {
    items.map((_, x) => self.fix(x))
  }
  match v {
    Literal(attrs, IntegerLiteral(text)) =>
      match attrs.inferred_type {
        Some(t) if self.is_float(t) =>
          Literal(
            attrs,
            FloatLiteral(@string.parse_double(text) catch { _ => return v }),
          )
        _ => v
      }
    Tuple(a, items) => Tuple(a, all(items))
    List(a, items) => List(a, all(items))
    Record(a, items) => Record(a, fields(items))
    Field(a, r, name) => Field(a, self.fix(r), name)
    Apply(a, f, x) => Apply(a, self.fix(f), self.fix(x))
    Lambda(a, p, b) => Lambda(a, p, self.fix(b))
    LetDefinition(a, name, d, i) =>
      LetDefinition(a, name, self.fix_definition(d), self.fix(i))
    LetRecursion(a, defs, i) =>
      LetRecursion(a, defs.map((_, d) => self.fix_definition(d)), self.fix(i))
    Destructure(a, p, x, i) => Destructure(a, p, self.fix(x), self.fix(i))
    IfThenElse(a, c, t, e) =>
      IfThenElse(a, self.fix(c), self.fix(t), self.fix(e))
    PatternMatch(a, s, cases) =>
      PatternMatch(a, self.fix(s), cases.map(c => (c.0, self.fix(c.1))))
    UpdateRecord(a, r, items) => UpdateRecord(a, self.fix(r), fields(items))
    _ => v
  }
}

///|
/// Whether `t`, with one alias resolved, is `Float`.
fn Aliases::is_float(self : Aliases, t : @ir.Type) -> Bool {
  is_float_reference(t) ||
  self.resolve(t).map(is_float_reference).unwrap_or(false)
}

///|
fn is_float_reference(t : @ir.Type) -> Bool {
  match t {
    Reference(_, fq, []) =>
      fq.package_name == @sdk_spec.sdk_package_name() &&
      fq.module_name.to_canonical() == "basics" &&
      fq.local_name.to_canonical() == "float"
    _ => false
  }
}

///|
/// The target of the alias that `t` refers to, with the alias parameters replaced by the arguments of `t`. Only a
/// bare parameter matters to `is_float`, so only a target that is a parameter is replaced.
fn Aliases::resolve(self : Aliases, t : @ir.Type) -> @ir.Type? {
  guard t is Reference(_, fq, args) else { return None }
  let found = if fq.package_name == self.package_name {
    match self.def.modules.get(fq.module_name) {
      Some(m) =>
        match m.value.types.get(fq.local_name) {
          Some(
            { value: { value: TypeAliasDefinition(params, target), .. }, .. }
          ) => Some((params, target))
          _ => None
        }
      None => None
    }
  } else {
    match self.deps.get(fq.package_name) {
      Some(spec) =>
        match spec.modules.get(fq.module_name) {
          Some(m) =>
            match m.types.get(fq.local_name) {
              Some(
                {
                  value: { body: TypeAliasSpecification(params, target), .. },
                  ..
                }
              ) => Some((params, target))
              _ => None
            }
          None => None
        }
      None => None
    }
  }
  guard found is Some((params, target)) else { return None }
  match target {
    Variable(_, name) =>
      match params.search(name) {
        Some(i) if i < args.length() => Some(args[i])
        _ => Some(target)
      }
    _ => Some(target)
  }
}
