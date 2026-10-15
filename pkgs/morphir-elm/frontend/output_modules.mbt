///|
/// Which modules the output of `compile_project` keeps.
pub(all) enum OutputModules {
  /// The modules that `morphir-elm make` 2.100.0 keeps (README rule 2). A kept module can name a type of a module
  /// that the output drops.
  Parity
  /// The `Parity` modules and every processed module that a kept module names, transitively: in its type
  /// definitions, value signatures, value bodies, patterns and inferred types. Code generators use it, so that the
  /// generated code names no missing module.
  Referenced
} derive(Eq, Debug)

///|
pub extend OutputModules with Eq::{equal, not_equal}

///|
pub extend OutputModules with @debug.Debug::{to_repr}

///|
/// Adds to `selected` every module of `modules` that a selected module names, transitively. Only the names of
/// `package_name` count, and only modules that `modules` holds are added.
fn add_referenced_modules(
  package_name : @ir.Path,
  modules : Map[@ir.Path, @ir.AccessControlled[@ir.ModuleDefinition]],
  selected : Set[@ir.Path],
) -> Unit {
  let work : Array[@ir.Path] = selected.iter().collect()
  while work.pop() is Some(path) {
    guard modules.get(path) is Some(m) else { continue }
    let names : Array[@ir.FQName] = []
    module_names(m.value, names)
    for name in names {
      if name.package_name == package_name &&
        modules.contains(name.module_name) &&
        !selected.contains(name.module_name) {
        selected.add(name.module_name)
        work.push(name.module_name)
      }
    }
  }
}

///|
/// Every name in a module: type definitions, value signatures, value bodies, patterns and inferred types.
fn module_names(m : @ir.ModuleDefinition, out : Array[@ir.FQName]) -> Unit {
  for _, t in m.types {
    type_definition_references(t.value.value, out)
  }
  for _, v in m.values {
    definition_names(v.value.value, out)
  }
}

///|
fn definition_names(d : @ir.ValueDefinition, out : Array[@ir.FQName]) -> Unit {
  value_signature_references(d, out)
  match d {
    ExpressionBody(_, _, body)
    | ExternalBody(_, _, _, Some(body))
    | IncompleteBody(_, _, _, Some(body)) => value_names(body, out)
    _ => ()
  }
}

///|
fn attribute_names(a : @ir.ValueAttributes, out : Array[@ir.FQName]) -> Unit {
  if a.inferred_type is Some(t) {
    type_references(t, out)
  }
}

///|
fn push_name(name : @ir.FQName, out : Array[@ir.FQName]) -> Unit {
  if !out.contains(name) {
    out.push(name)
  }
}

///|
fn value_names(v : @ir.Value, out : Array[@ir.FQName]) -> Unit {
  match v {
    Literal(a, _) | Variable(a, _) | FieldFunction(a, _) | Unit(a) =>
      attribute_names(a, out)
    Constructor(a, name) | Reference(a, name) => {
      attribute_names(a, out)
      push_name(name, out)
    }
    Tuple(a, items) | List(a, items) => {
      attribute_names(a, out)
      for item in items {
        value_names(item, out)
      }
    }
    Record(a, fields) => {
      attribute_names(a, out)
      for _, field in fields {
        value_names(field, out)
      }
    }
    Field(a, record, _) => {
      attribute_names(a, out)
      value_names(record, out)
    }
    Apply(a, f, x) => {
      attribute_names(a, out)
      value_names(f, out)
      value_names(x, out)
    }
    Lambda(a, p, body) => {
      attribute_names(a, out)
      pattern_names(p, out)
      value_names(body, out)
    }
    LetDefinition(a, _, d, rest) => {
      attribute_names(a, out)
      definition_names(d, out)
      value_names(rest, out)
    }
    LetRecursion(a, defs, rest) => {
      attribute_names(a, out)
      for _, d in defs {
        definition_names(d, out)
      }
      value_names(rest, out)
    }
    Destructure(a, p, value, rest) => {
      attribute_names(a, out)
      pattern_names(p, out)
      value_names(value, out)
      value_names(rest, out)
    }
    IfThenElse(a, c, t, e) => {
      attribute_names(a, out)
      value_names(c, out)
      value_names(t, out)
      value_names(e, out)
    }
    PatternMatch(a, subject, cases) => {
      attribute_names(a, out)
      value_names(subject, out)
      for c in cases {
        pattern_names(c.0, out)
        value_names(c.1, out)
      }
    }
    UpdateRecord(a, record, fields) => {
      attribute_names(a, out)
      value_names(record, out)
      for _, field in fields {
        value_names(field, out)
      }
    }
    Hole(a, _, t) => {
      attribute_names(a, out)
      if t is Some(t) {
        type_references(t, out)
      }
    }
  }
}

///|
fn pattern_names(p : @ir.Pattern, out : Array[@ir.FQName]) -> Unit {
  match p {
    WildcardPattern(a)
    | EmptyListPattern(a)
    | LiteralPattern(a, _)
    | UnitPattern(a) => attribute_names(a, out)
    AsPattern(a, inner, _) => {
      attribute_names(a, out)
      pattern_names(inner, out)
    }
    TuplePattern(a, items) => {
      attribute_names(a, out)
      for item in items {
        pattern_names(item, out)
      }
    }
    ConstructorPattern(a, name, args) => {
      attribute_names(a, out)
      push_name(name, out)
      for arg in args {
        pattern_names(arg, out)
      }
    }
    HeadTailPattern(a, head, tail) => {
      attribute_names(a, out)
      pattern_names(head, out)
      pattern_names(tail, out)
    }
  }
}
