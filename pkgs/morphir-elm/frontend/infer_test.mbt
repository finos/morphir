///|
fn compile_one(content : String) -> @ir.IRFile raise @frontend.ElmFailed {
  @frontend.compile_project([{ path: "My/Pkg/A.elm", content, }], "My.Pkg", [
    "A",
  ])
}

///|
fn a_value(file : @ir.IRFile, name : String) -> @ir.ValueDefinition {
  guard file.distribution is Library(_, _, def) else { abort("library") }
  def.modules[@ir.Path::parse("a") catch { _ => panic() }].value.values[@ir.Name::parse(
    name,
  ) catch {
    _ => panic()
  }].value.value
}

///|
/// The number of value and pattern nodes without an inferred type, let definitions included.
fn untyped(v : @ir.Value) -> Int {
  let sum = (items : Array[@ir.Value]) => {
    items.fold(init=0, (n, x) => n + untyped(x))
  }
  let in_definition = (d : @ir.ValueDefinition) => {
    match d {
      ExpressionBody(_, _, body) => untyped(body)
      _ => 0
    }
  }
  match v {
    Literal(a, _) => missing(a)
    Constructor(a, _) => missing(a)
    Variable(a, _) => missing(a)
    Reference(a, _) => missing(a)
    FieldFunction(a, _) => missing(a)
    Unit(a) => missing(a)
    Hole(a, _, _) => missing(a)
    Tuple(a, items) | List(a, items) => missing(a) + sum(items)
    Record(a, fields) => missing(a) + sum(fields.values().collect())
    Field(a, r, _) => missing(a) + untyped(r)
    Apply(a, f, x) => missing(a) + untyped(f) + untyped(x)
    Lambda(a, p, b) => missing(a) + untyped_pattern(p) + untyped(b)
    LetDefinition(a, _, d, i) => missing(a) + in_definition(d) + untyped(i)
    LetRecursion(a, defs, i) =>
      missing(a) +
      defs.values().fold(init=0, (n, d) => n + in_definition(d)) +
      untyped(i)
    Destructure(a, p, x, i) =>
      missing(a) + untyped_pattern(p) + untyped(x) + untyped(i)
    IfThenElse(a, c, t, e) => missing(a) + untyped(c) + untyped(t) + untyped(e)
    PatternMatch(a, s, cases) =>
      missing(a) +
      untyped(s) +
      cases.fold(init=0, (n, c) => n + untyped_pattern(c.0) + untyped(c.1))
    UpdateRecord(a, r, fields) =>
      missing(a) + untyped(r) + sum(fields.values().collect())
  }
}

///|
fn untyped_pattern(p : @ir.Pattern) -> Int {
  match p {
    WildcardPattern(a) => missing(a)
    EmptyListPattern(a) => missing(a)
    LiteralPattern(a, _) => missing(a)
    UnitPattern(a) => missing(a)
    AsPattern(a, inner, _) => missing(a) + untyped_pattern(inner)
    TuplePattern(a, items) =>
      missing(a) + items.fold(init=0, (n, x) => n + untyped_pattern(x))
    ConstructorPattern(a, _, items) =>
      missing(a) + items.fold(init=0, (n, x) => n + untyped_pattern(x))
    HeadTailPattern(a, h, t) =>
      missing(a) + untyped_pattern(h) + untyped_pattern(t)
  }
}

///|
fn missing(a : @ir.ValueAttributes) -> Int {
  if a.inferred_type is None {
    1
  } else {
    0
  }
}

///|
test "every node of the output has an inferred type" {
  let file = compile_one(
    "module My.Pkg.A exposing (..)\n\n\npick : Maybe Int -> Int\npick m =\n    case m of\n        Just v ->\n            let\n                w =\n                    v + 1\n            in\n            w\n\n        Nothing ->\n            0\n",
  )
  guard a_value(file, "pick") is ExpressionBody(_, _, body) else {
    fail("pick")
  }
  assert_eq(untyped(body), 0)
}

///|
test "a whole number in a Float context becomes a float literal" {
  let file = compile_one(
    "module My.Pkg.A exposing (..)\n\n\nfi : Float\nfi =\n    2\n\n\nadd1 : Float -> Float\nadd1 x =\n    x + 1\n\n\nun =\n    1\n",
  )
  guard a_value(file, "fi") is ExpressionBody(_, _, Literal(_, FloatLiteral(f))) else {
    fail("fi")
  }
  assert_true(f == 2.0)
  guard a_value(file, "add-1")
    is ExpressionBody(_, _, Apply(_, _, Literal(_, FloatLiteral(g)))) else {
    fail("add1")
  }
  assert_true(g == 1.0)
  guard a_value(file, "un")
    is ExpressionBody(_, _, Literal(attrs, IntegerLiteral("1"))) else {
    fail("un")
  }
  guard attrs.inferred_type is Some(Variable(type_attrs, name)) else {
    fail("un type")
  }
  // A literal that nothing fixes keeps a `number` variable: the class is the constraint or the name prefix.
  assert_true(
    name.to_canonical().has_prefix("number") ||
    type_attrs.constraints.get("typeclass") is Some(Text("number")),
  )
}

///|
test "the float rewrite reaches let definitions and resolves one alias, as morphir-elm does" {
  // Probe t5-float of morphir-elm make 2.100.0: `pr` and `k` become float literals, `pr2` (an alias of an alias)
  // keeps its whole number, because `Distribution.resolveType` resolves one alias only.
  let file = compile_one(
    "module My.Pkg.A exposing (..)\n\n\ntype alias Price =\n    Float\n\n\ntype alias Price2 =\n    Price\n\n\npr : Price\npr =\n    3\n\n\npr2 : Price2\npr2 =\n    5\n\n\nlf : Float\nlf =\n    let\n        k : Float\n        k =\n            4\n    in\n    k\n",
  )
  guard a_value(file, "pr") is ExpressionBody(_, _, Literal(_, FloatLiteral(f))) else {
    fail("pr")
  }
  assert_true(f == 3.0)
  guard a_value(file, "lf")
    is ExpressionBody(
      _,
      _,
      LetDefinition(_, _, ExpressionBody(_, _, Literal(_, FloatLiteral(g))), _)
    ) else {
    fail("lf")
  }
  assert_true(g == 4.0)
  guard a_value(file, "pr-2")
    is ExpressionBody(_, _, Literal(_, IntegerLiteral("5"))) else {
    fail("pr2")
  }
}

///|
test "review focus 2: a type error is elm.type at its source" {
  let problems = try {
    ignore(
      compile_one(
        "module My.Pkg.A exposing (..)\n\n\nbad : Int\nbad =\n    \"a\"\n",
      ),
    )
    []
  } catch {
    @frontend.ElmFailed(problems) => problems
  }
  assert_eq(problems.map(p => (p.code, p.path)), [("elm.type", "My/Pkg/A.elm")])
  assert_true(problems[0].location is Some(_))
}

///|
test "an inference problem is at the source of its own module" {
  let problems = try {
    ignore(
      @frontend.compile_project(
        [
          {
            path: "My/Pkg/A.elm",
            content: "module My.Pkg.A exposing (..)\n\nimport My.Pkg.Sub.B\n\n\na : Int\na =\n    My.Pkg.Sub.B.b\n",
          },
          {
            path: "My/Pkg/Sub/B.elm",
            content: "module My.Pkg.Sub.B exposing (..)\n\n\nb : Int\nb =\n    1.5\n",
          },
        ],
        "My.Pkg",
        ["A"],
      ),
    )
    []
  } catch {
    @frontend.ElmFailed(problems) => problems
  }
  assert_eq(problems.map(p => (p.code, p.path, p.location)), [
    (
      "elm.type",
      "My/Pkg/Sub/B.elm",
      Some({ start_line: 6, start_column: 5, end_line: 6, end_column: 8, }),
    ),
  ])
  assert_true(
    problems[0].message.has_prefix("type_mismatch at value:my/pkg:sub/b#b"),
  )
}
