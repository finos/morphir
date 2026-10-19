///|
/// A problem without types.
fn problem(
  code : String,
  node : String,
  message : String,
  source : @ir.SourceLocation?,
) -> InferenceProblem {
  { code, node, message, expected: None, found: None, source, }
}

///|
/// The problem of a failure in the declaration `d`. The types are named by one new namer.
fn problem_of(d : Decl, err : Located, s : Solver) -> InferenceProblem {
  match err {
    MismatchAt(path, Mismatch(code, e, f)) => {
      let namer = Namer::new(owner=d.key)
      namer.reserve_rigids(s, e)
      namer.reserve_rigids(s, f)
      let expected = namer.convert(s, e)
      let found = namer.convert(s, f)
      {
        code,
        node: path,
        message: mismatch_message(code, s, d.key, e, f, expected, found),
        expected: Some(expected),
        found: Some(found),
        source: source_at(d, path),
      }
    }
    UnknownAt(path, Unknown(code, name)) =>
      problem(code, path, unknown_message(code, name), source_at(d, path))
    ClassAt(path, class) =>
      problem(
        "unsupported",
        path,
        "inference does not support the type class `\{class}`",
        source_at(d, path),
      )
  }
}

///|
/// The message for a name that does not resolve or a construct that inference does not handle.
fn unknown_message(code : String, name : String) -> String {
  match code {
    "unknown_reference" => "`\{name}` is not defined"
    "arity" => "`\{name}` is applied to the wrong number of type arguments"
    "missing_dependency" =>
      "there is no specification for the package of `\{name}`"
    _ => "inference does not support `\{name}`"
  }
}

///|
/// The message for a unification failure in the declaration `owner`. `expected` and `found` are `e` and `f` in
/// IR.
fn mismatch_message(
  code : String,
  s : Solver,
  owner : String,
  e : Ty,
  f : Ty,
  expected : @ir.Type,
  found : @ir.Type,
) -> String {
  let fallback = "expected \{elm_text(expected)}, found \{elm_text(found)}"
  let message = match code {
    "occurs" =>
      Some(
        "the type would be infinite: \{elm_text(expected)} occurs in \{elm_text(found)}",
      )
    "rigid_variable" => rigid_message(s, owner, e, f, expected, found)
    "no_instance" => class_message(s, e, f, expected, found)
    "missing_field" => field_message(s, e, f)
    "arity" => Some(arity_message(e, f, found))
    "annotation_mismatch" =>
      Some(
        "the node has the type \{elm_text(expected)}, but inference gives \{elm_text(found)}",
      )
    _ => None
  }
  message.unwrap_or(fallback)
}

///|
/// `the variable `a` is annotated as any type, but the body needs Int`. When both sides are rigid, the variable
/// is the one that `owner` declares. The variable is named as in `expected` and `found`.
fn rigid_message(
  s : Solver,
  owner : String,
  e : Ty,
  f : Ty,
  expected : @ir.Type,
  found : @ir.Type,
) -> String? {
  let (key, classes, var_ir, other, other_ir) = match
    (diagnostic_head(s, e), diagnostic_head(s, f)) {
    (Rigid(a, _), Rigid(b, classes)) if rigid_owner(a) != owner &&
      rigid_owner(b) == owner => (b, classes, found, e, expected)
    (Rigid(key, classes), _) => (key, classes, expected, f, found)
    (_, Rigid(key, classes)) => (key, classes, found, e, expected)
    _ => return None
  }
  let name = match var_ir {
    Variable(_, name) => lower_camel(name)
    _ => lower_camel(parse_name(rigid_name(key)))
  }
  let declared = class_phrase(classes, "any type")
  let needs = match diagnostic_head(s, other) {
    Meta(id) if s.metas[id] is Unbound(classes=[class], ..) => class
    _ => elm_text(other_ir)
  }
  Some(
    "the variable `\{name}` is annotated as \{declared}, but the body needs \{needs}",
  )
}

///|
/// `the type String is not a number`, or `no type is both a number and appendable`.
fn class_message(
  s : Solver,
  e : Ty,
  f : Ty,
  expected : @ir.Type,
  found : @ir.Type,
) -> String? {
  let classes = fn(t : Ty) -> Array[String]? {
    match diagnostic_head(s, t) {
      Meta(id) if s.metas[id] is Unbound(classes~, ..) => Some(classes)
      _ => None
    }
  }
  match (classes(e), classes(f)) {
    (Some(c1), Some(c2)) =>
      Some(
        "no type is both \{class_phrase(c1, "any type")} and \{class_phrase(c2, "any type")}",
      )
    (Some(c), None) =>
      Some("the type \{elm_text(found)} is not \{class_phrase(c, "any type")}")
    (None, Some(c)) =>
      Some(
        "the type \{elm_text(expected)} is not \{class_phrase(c, "any type")}",
      )
    (None, None) => None
  }
}

///|
/// A class set in words: `a number`, `comparable`, `appendable`, `comparable and appendable`.
fn class_phrase(classes : Array[String], none : String) -> String {
  match classes {
    [] => none
    [NUMBER, ..] => "a number"
    [COMPAPPEND, ..] => "comparable and appendable"
    [class, ..] => class
  }
}

///|
/// `the record has no field `total``. The closed record of the pair lacks a field of the other record.
fn field_message(s : Solver, e : Ty, f : Ty) -> String? {
  let missing = match (diagnostic_head(s, e), diagnostic_head(s, f)) {
    (Rec(f1, _), Rec(f2, None)) => first_missing(f1, f2)
    (Rec(f1, None), Rec(f2, _)) => first_missing(f2, f1)
    _ => None
  }
  missing.map(name => {
    "the record has no field `\{lower_camel(parse_name(name))}`"
  })
}

///|
/// The first field of `a`, in sorted order, that `b` does not have.
fn first_missing(a : Map[String, Ty], b : Map[String, Ty]) -> String? {
  let names = a.keys().filter(name => !b.contains(name)).collect()
  names.sort()
  names.get(0)
}

///|
/// An `arity` failure: a value that is not a function is applied, or a constructor pattern has the wrong
/// number of arguments.
fn arity_message(e : Ty, f : Ty, found : @ir.Type) -> String {
  // An application fails against a type that is not a function. A constructor pattern's own type is a
  // function or a meta.
  if e is Fun(_, _) && !(f is (Fun(_, _) | Meta(_))) {
    "the type \{elm_text(found)} is not a function, so it cannot take an argument"
  } else {
    "the constructor takes \{arity_of(e)} arguments, but the pattern has \{arity_of(f)}"
  }
}

///|
/// Attributes do not change which variable or class a diagnostic describes.
fn diagnostic_head(s : Solver, t : Ty) -> Ty {
  match s.prune(t) {
    Attributed(_, inner) => diagnostic_head(s, inner)
    head => head
  }
}
