///|
/// A pattern, by morphir-elm's `mapPattern`. Each name that the pattern binds
/// goes into `bound`. A variable is `AsPattern(WildcardPattern, name)`, a list
/// pattern is a chain of `HeadTailPattern` that ends in `EmptyListPattern`, and
/// unqualified `True` and `False` are bool literals. A record pattern is not
/// supported.
fn Lowering::pattern(
  self : Lowering,
  node : @ast.Node[@ast.Pattern],
  bound : Map[String, Bool],
) -> @ir.Pattern raise LowerError {
  let a = value_attributes(node.range)
  match node.value {
    AllPattern => WildcardPattern(a)
    UnitPattern => UnitPattern(a)
    CharPattern(c) => LiteralPattern(a, CharLiteral(c))
    StringPattern(s) => LiteralPattern(a, StringLiteral(s))
    IntPattern(n) | HexPattern(n) =>
      LiteralPattern(a, IntegerLiteral(n.to_string()))
    FloatPattern(d) => LiteralPattern(a, FloatLiteral(d))
    TuplePattern(items) => TuplePattern(a, self.patterns(items, bound))
    RecordPattern(_) =>
      raise LowerError(
        "elm.unsupported",
        "a record pattern is not supported",
        Some(node.range),
      )
    UnConsPattern(head, tail) => {
      let h = self.pattern(head, bound)
      HeadTailPattern(a, h, self.pattern(tail, bound))
    }
    ListPattern(items) => {
      let lowered = self.patterns(items, bound)
      let mut result : @ir.Pattern = EmptyListPattern(a)
      for i = lowered.length() - 1; i >= 0; i = i - 1 {
        result = HeadTailPattern(a, lowered[i], result)
      }
      result
    }
    VarPattern(name) => {
      bound[name] = true
      AsPattern(a, WildcardPattern(a), @mapping.elm_name(name))
    }
    NamedPattern({ module_name: [], name: "True", }, _) =>
      LiteralPattern(a, BoolLiteral(true))
    NamedPattern({ module_name: [], name: "False", }, _) =>
      LiteralPattern(a, BoolLiteral(false))
    NamedPattern({ module_name, name, }, args) => {
      // A constructor is never a local name.
      let resolved = self.scope.resolve_value(module_name.to_owned(), name, _ => {
        false
      }) catch {
        @resolve.ResolveError(code, message) =>
          raise LowerError(code, message, Some(node.range))
      }
      match resolved {
        Global(fq) => ConstructorPattern(a, fq, self.patterns(args, bound))
        BoolLiteral(b) => LiteralPattern(a, BoolLiteral(b))
        Local(n) =>
          raise LowerError(
            "elm.unresolved_name",
            "the constructor \{n} is not defined or imported",
            Some(node.range),
          )
      }
    }
    AsPattern(inner, name) => {
      let p = self.pattern(inner, bound)
      bound[name.value] = true
      AsPattern(a, p, @mapping.elm_name(name.value))
    }
    ParenthesizedPattern(inner) => self.pattern(inner, bound)
  }
}

///|
fn Lowering::patterns(
  self : Lowering,
  nodes : ArrayView[@ast.Node[@ast.Pattern]],
  bound : Map[String, Bool],
) -> Array[@ir.Pattern] raise LowerError {
  let result = []
  for node in nodes {
    result.push(self.pattern(node, bound))
  }
  result
}
