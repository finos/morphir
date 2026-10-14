///|
/// `case subject of cases`: each pattern takes the type of the subject, and all bodies have one type.
fn Infer::value_case(
  self : Infer,
  subject : @ir.Value,
  cases : Array[(@ir.Pattern, @ir.Value)],
  path : String,
) -> Ty raise Located {
  let st = self.value(subject, @identities.path_subject(path))
  let result = self.fresh()
  for i, case_ in cases {
    let (p, body) = case_
    self.scoped(() => {
      let pt = self.pattern(p, @identities.path_case_pattern(path, i))
      self.unify(@identities.path_case_pattern(path, i), st, pt)
      let bt = self.value(body, @identities.path_case_body(path, i))
      self.unify(@identities.path_case_body(path, i), result, bt)
    })
  }
  result
}

///|
/// Infers the type of the pattern `p` at `path` and records it in `types`. The variables that it binds enter
/// `locals` monomorphically; the caller opens the scope.
fn Infer::pattern(
  self : Infer,
  p : @ir.Pattern,
  path : String,
) -> Ty raise Located {
  let t = match p {
    WildcardPattern(_) => self.fresh()
    AsPattern(_, inner, name) => {
      let t = self.pattern(inner, @identities.path_pattern(path))
      self.bind(name, t)
      t
    }
    TuplePattern(_, []) | UnitPattern(_) => UnitTy
    TuplePattern(_, items) => {
      let types = []
      for i, item in items {
        types.push(self.pattern(item, @identities.path_item(path, i)))
      }
      Tup(types)
    }
    ConstructorPattern(_, name, args) =>
      self.pattern_constructor(name, args, path)
    EmptyListPattern(_) => Con(LIST, [self.fresh()])
    HeadTailPattern(_, head, tail) => {
      let ht = self.pattern(head, @identities.path_head(path))
      let tt = self.pattern(tail, @identities.path_tail(path))
      self.unify(path, Con(LIST, [ht]), tt)
      tt
    }
    LiteralPattern(_, lit) => self.pattern_literal(lit)
  }
  self.fact(pattern_attributes(p).inferred_type, t, path)
  self.types[path] = t
  t
}

///|
fn Infer::pattern_literal(self : Infer, lit : @ir.PatternLiteral) -> Ty {
  match lit {
    BoolLiteral(_) => Con(BOOL, [])
    CharLiteral(_) => Con(CHAR, [])
    StringLiteral(_) => Con(STRING, [])
    IntegerLiteral(_) => self.solver.fresh(self.level, [NUMBER])
    FloatLiteral(_) => Con(FLOAT, [])
    DecimalLiteral(_) => Con(DECIMAL, [])
  }
}

///|
/// A constructor pattern takes one pattern for each constructor argument. Another count is `arity`.
fn Infer::pattern_constructor(
  self : Infer,
  name : @ir.FQName,
  args : Array[@ir.Pattern],
  path : String,
) -> Ty raise Located {
  guard self.env.constructors.get(name.to_canonical()) is Some(poly) else {
    return self.unknown(path, name)
  }
  let ct = self.global(poly, path)
  let types = []
  for i, arg in args {
    types.push(self.pattern(arg, @identities.path_arg(path, i)))
  }
  let result = self.fresh()
  let found = curry(types, result)
  if arity_of(ct) != args.length() {
    raise MismatchAt(path, Mismatch("arity", ct, found))
  }
  self.unify(path, ct, found)
  result
}

///|
/// The number of arguments of a curried function type.
fn arity_of(t : Ty) -> Int {
  match t {
    Fun(_, output) => 1 + arity_of(output)
    _ => 0
  }
}
