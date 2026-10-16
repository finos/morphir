///|
let zero : @ast.Range = {
  start: { row: 0, column: 0, },
  end: { row: 0, column: 0, },
}

///|
fn[T] node(value : T) -> @ast.Node[T] {
  { range: zero, value, }
}

///|
let default_imports : Array[String] = [
  "Basics", "List", "Maybe", "Result", "String", "Char", "Tuple", "Debug",
]

///|
priv enum Kind {
  Value
  Constructor
  TypeName
}

///|
priv enum Resolved {
  Qualified(Array[String], String)
  Op(String)
}

///|
/// One context per generated Elm module. `scope` maps IR local names (canonical) to Elm names.
priv struct Ctx {
  options : Options
  package_name : @ir.Path
  module_path : @ir.Path
  imports : Map[String, String?]
  mut uses_sdk_package : Bool
  foreign_packages : Map[String, Bool]
  mut scope : Map[String, String]
  /// Elm names that a new binder must not take: the top-level names, the locals of the enclosing scopes and the
  /// fresh names. `with_scope` restores it, so sibling scopes can use the same name.
  mut used : Map[String, Bool]
  /// Elm names of the let blocks being lowered that are not bound yet, with a count. Elm sees every name of a let
  /// block in each of its definitions, so a binder inside a definition must not take one.
  mut pending : Map[String, Int32]
  mut fresh : Int32
  /// Elm names of the type variables of the declaration being lowered, by canonical IR name.
  mut type_variables : Map[String, String]
  /// Elm names of the module's top-level values.
  top_values : Map[String, Bool]
  /// Elm names of the module's types and constructors.
  module_types : Map[String, Bool]
  /// Elm names of every binder in the top-level declaration being lowered.
  mut binders : Map[String, Bool]
}

///|
fn Ctx::new(
  options : Options,
  package_name : @ir.Path,
  module_path : @ir.Path,
) -> Ctx {
  {
    options,
    package_name,
    module_path,
    imports: Map([]),
    uses_sdk_package: false,
    foreign_packages: Map([]),
    scope: Map([]),
    used: Map([]),
    pending: Map([]),
    fresh: 0,
    type_variables: Map([]),
    top_values: Map([]),
    module_types: Map([]),
    binders: Map([]),
  }
}

///|
fn split_qualified(text : String) -> (Array[String], String) {
  let parts = text.split(".").map(p => p.to_owned()).collect()
  let last = parts.pop().unwrap()
  (parts, last)
}

///|
fn Ctx::add_import_line(self : Ctx, line : String) -> Unit {
  let parts = line.split(" as ").map(p => p.to_owned()).collect()
  match parts {
    [import_name, alias_name] => self.imports[import_name] = Some(alias_name)
    _ => self.imports[line] = None
  }
}

///|
/// A reference into another Morphir package needs that package in elm.json, mapped or not.
fn Ctx::note_foreign_package(self : Ctx, name : @ir.FQName) -> Unit {
  let package_text = name.package_name.to_canonical()
  if package_text != "morphir/SDK" && name.package_name != self.package_name {
    self.foreign_packages[package_text] = true
  }
}

///|
fn Ctx::resolve(self : Ctx, name : @ir.FQName, kind : Kind) -> Resolved {
  let space : Namespace = match kind {
    TypeName => TypeSpace
    Value | Constructor => ValueSpace
  }
  if self.options.profile is Model {
    match self.options.mapping.lookup(name, space) {
      Some(Operator(op)) => return Op(op)
      Some(Function(text, import_line)) | Some(Type(text, import_line)) => {
        let (qualifier, name_text) = split_qualified(text)
        match import_line {
          Some(line) => self.add_import_line(line)
          None =>
            if !qualifier.is_empty() &&
              !default_imports.contains(qualifier.join(".")) {
              self.imports[qualifier.join(".")] = None
            }
        }
        self.note_foreign_package(name)
        if !self.options.mapping.is_override(name, space) &&
          self.can_print_bare(qualifier, name_text) {
          return Qualified([], name_text)
        }
        return Qualified(qualifier, name_text)
      }
      _ => ()
    }
  }
  let local_text = match kind {
    Value => value_name(name.local_name)
    Constructor | TypeName => type_name(name.local_name)
  }
  if name.package_name == self.package_name &&
    name.module_name == self.module_path {
    return Qualified([], local_text)
  }
  let package_text = name.package_name.to_canonical()
  if package_text == "morphir/SDK" {
    self.uses_sdk_package = true
  } else if name.package_name != self.package_name {
    self.foreign_packages[package_text] = true
  }
  let qualifier = module_name(name.package_name, name.module_name)
  self.imports[qualifier.join(".")] = None
  Qualified(qualifier, local_text)
}

///|
/// The names that a default import exposes unqualified.
fn default_exposes(qualifier : String, name_text : String) -> Bool {
  match qualifier {
    "Basics" => true
    "Maybe" => ["Maybe", "Just", "Nothing"].contains(name_text)
    "Result" => ["Result", "Ok", "Err"].contains(name_text)
    "List" | "String" | "Char" => name_text == qualifier
    _ => false
  }
}

///|
/// In Elm a module's own names win over a default import, so a mapped name prints bare only when
/// nothing in the module or the declaration can capture it.
fn Ctx::can_print_bare(
  self : Ctx,
  qualifier : Array[String],
  name_text : String,
) -> Bool {
  guard qualifier is [single] && default_exposes(single, name_text) else {
    return false
  }
  let first = name_text.get_char(0)
  if first is Some(c) && c >= 'A' && c <= 'Z' {
    !self.module_types.contains(name_text)
  } else {
    !self.top_values.contains(name_text) &&
    !self.binders.contains(name_text) &&
    !self.used.contains(name_text)
  }
}

///|
fn pattern_binders(p : @ir.Pattern, out : Map[String, Bool]) -> Unit {
  match p {
    AsPattern(_, inner, name) => {
      out[value_name(name)] = true
      pattern_binders(inner, out)
    }
    TuplePattern(_, items) | ConstructorPattern(_, _, items) =>
      for item in items {
        pattern_binders(item, out)
      }
    HeadTailPattern(_, head, tail) => {
      pattern_binders(head, out)
      pattern_binders(tail, out)
    }
    WildcardPattern(_)
    | EmptyListPattern(_)
    | LiteralPattern(_, _)
    | UnitPattern(_) => ()
  }
}

///|
fn definition_binders(
  definition : @ir.ValueDefinition,
  out : Map[String, Bool],
) -> Unit {
  let (inputs, body) = match definition {
    ExpressionBody(inputs, _, body) => (inputs, Some(body))
    NativeBody(inputs, _, _) => (inputs, None)
    ExternalBody(inputs, _, _, fallback) => (inputs, fallback)
    IncompleteBody(inputs, _, _, partial) => (inputs, partial)
  }
  for input in inputs {
    out[value_name(input.0)] = true
  }
  if body is Some(value) {
    value_binders(value, out)
  }
}

///|
/// Every name that a value binds anywhere inside it, as an Elm name.
fn value_binders(v : @ir.Value, out : Map[String, Bool]) -> Unit {
  match v {
    Literal(_, _)
    | Constructor(_, _)
    | Variable(_, _)
    | Reference(_, _)
    | FieldFunction(_, _)
    | Unit(_)
    | Hole(_, _, _) => ()
    Tuple(_, items) | List(_, items) =>
      for item in items {
        value_binders(item, out)
      }
    Record(_, fields) =>
      for _, field in fields {
        value_binders(field, out)
      }
    Field(_, target, _) => value_binders(target, out)
    Apply(_, f, argument) => {
      value_binders(f, out)
      value_binders(argument, out)
    }
    Lambda(_, pattern, body) => {
      pattern_binders(pattern, out)
      value_binders(body, out)
    }
    LetDefinition(_, name, definition, next) => {
      out[value_name(name)] = true
      definition_binders(definition, out)
      value_binders(next, out)
    }
    LetRecursion(_, definitions, next) => {
      for name, definition in definitions {
        out[value_name(name)] = true
        definition_binders(definition, out)
      }
      value_binders(next, out)
    }
    Destructure(_, pattern, value, next) => {
      pattern_binders(pattern, out)
      value_binders(value, out)
      value_binders(next, out)
    }
    IfThenElse(_, condition, then_branch, else_branch) => {
      value_binders(condition, out)
      value_binders(then_branch, out)
      value_binders(else_branch, out)
    }
    PatternMatch(_, subject, cases) => {
      value_binders(subject, out)
      for c in cases {
        pattern_binders(c.0, out)
        value_binders(c.1, out)
      }
    }
    UpdateRecord(_, target, fields) => {
      value_binders(target, out)
      for _, field in fields {
        value_binders(field, out)
      }
    }
  }
}

///|
fn Ctx::elm_imports(self : Ctx) -> Array[@ast.Node[@ast.Import]] {
  let names = self.imports.keys().collect()
  names.sort()
  names.map(import_name => {
    let alias_name = self.imports.get(import_name).unwrap()
    node({
      module_name: node(
        import_name.split(".").map(p => p.to_owned()).collect()[:],
      ),
      module_alias: alias_name.map(a => node([a][:])),
      exposing_list: None,
    })
  })
}

///|
/// Elm comments nest, so `{-` would open a comment and `-}` would end one early. The doc body writes them as
/// `{ -` and `- }`. Attribute lines are Elm strings, so they write them as `{\u{002D}` and `-\u{007D}`.
/// An empty doc is no doc, so it gives no comment unless there are attributes.
fn doc_comment(doc : String?, attributes : Array[String]) -> @ast.Node[String]? {
  if doc.unwrap_or("") == "" && attributes.is_empty() {
    return None
  }
  let body = doc
    .unwrap_or("")
    .replace_all(old="{-", new="{ -")
    .replace_all(old="-}", new="- }")
  let block = if attributes.is_empty() {
    ""
  } else {
    "\n\n```attributes\n" +
    attributes
    .map(a => {
      a
      .replace_all(old="-}", new="-\\u{007D}")
      .replace_all(old="{-", new="{\\u{002D}")
    })
    .join("\n") +
    "\n```\n"
  }
  Some(node("{-| " + body + block + "\n-}"))
}
