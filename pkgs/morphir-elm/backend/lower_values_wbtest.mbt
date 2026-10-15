///|
fn va() -> @ir.ValueAttributes {
  { source: None, inferred_type: None, extensions: Map([]), }
}

///|
fn n(text : String) -> @ir.Name {
  @ir.Name::parse(text) catch {
    _ => panic()
  }
}

///|
fn sdk(text : String) -> @ir.Value {
  @ir.Value::Reference(va(), @ir.FQName::parse(text) catch { _ => panic() })
}

///|
fn int(text : String) -> @ir.Value {
  @ir.Value::Literal(va(), IntegerLiteral(text))
}

///|
fn variable(name : String) -> @ir.Value {
  @ir.Value::Variable(va(), n(name))
}

///|
fn apply(f : @ir.Value, args : Array[@ir.Value]) -> @ir.Value {
  args.fold(init=f, (acc, a) => @ir.Value::Apply(va(), acc, a))
}

///|
fn bind_var(name : String) -> @ir.Pattern {
  @ir.Pattern::AsPattern(va(), WildcardPattern(va()), n(name))
}

///|
fn show(ctx : Ctx, v : @ir.Value) -> String raise {
  @printer.print_expression(node(lower_value(ctx, v, "acme/app:orders#v")))
}

///|
fn refusal(ctx : Ctx, v : @ir.Value) -> String {
  try {
    ignore(lower_value(ctx, v, "acme/app:orders#v"))
    ""
  } catch {
    Refused(problem) => problem.code
    _ => "other"
  }
}

///|
test "mapped operators become infix applications" {
  let ctx = ctx_for()
  ignore(ctx.bind(n("a")))
  ignore(ctx.bind(n("b")))
  assert_eq(
    show(
      ctx,
      apply(sdk("morphir/SDK:basics#add"), [variable("a"), variable("b")]),
    ),
    "a + b",
  )
  assert_eq(
    show(ctx, apply(sdk("morphir/SDK:basics#add"), [variable("a")])),
    "(+) a",
  )
  assert_eq(show(ctx, sdk("morphir/SDK:basics#add")), "(+)")
  assert_eq(
    show(
      ctx,
      apply(sdk("morphir/SDK:list#map"), [
        sdk("morphir/SDK:basics#negate"),
        variable("b"),
      ]),
    ),
    "List.map negate b",
  )
  let literal = ctx_for(profile=Literal)
  ignore(literal.bind(n("a")))
  ignore(literal.bind(n("b")))
  assert_eq(
    show(
      literal,
      apply(sdk("morphir/SDK:basics#add"), [variable("a"), variable("b")]),
    ),
    "Morphir.SDK.Basics.add a b",
  )
}

///|
test "literals" {
  let ctx = ctx_for()
  assert_eq(show(ctx, int("42")), "42")
  assert_eq(show(ctx, int("-7")), "-7")
  assert_eq(show(ctx, @ir.Value::Literal(va(), BoolLiteral(true))), "True")
  assert_eq(
    show(ctx, @ir.Value::Literal(va(), StringLiteral("hi \"you\""))),
    "\"hi \\\"you\\\"\"",
  )
  assert_eq(show(ctx, @ir.Value::Literal(va(), CharLiteral('x'))), "'x'")
  assert_eq(refusal(ctx, int("99999999999999999999999")), "elm.int_literal")
  assert_eq(
    refusal(ctx, @ir.Value::Literal(va(), DecimalLiteral("1.5"))),
    "elm.decimal_literal",
  )
  assert_eq(
    refusal(ctx, @ir.Value::Literal(va(), DocumentLiteral(Null))),
    "elm.document_literal",
  )
}

///|
test "records, fields and updates" {
  let ctx = ctx_for()
  ignore(ctx.bind(n("order")))
  let record = @ir.Value::Record(
    va(),
    Map::from_array([(n("total"), int("1"))]),
  )
  assert_eq(show(ctx, record), "{ total = 1 }")
  assert_eq(
    show(ctx, @ir.Value::Field(va(), variable("order"), n("total"))),
    "order.total",
  )
  assert_eq(show(ctx, @ir.Value::FieldFunction(va(), n("total"))), ".total")
  let update = @ir.Value::UpdateRecord(
    va(),
    variable("order"),
    Map::from_array([(n("total"), int("2"))]),
  )
  assert_eq(show(ctx, update), "{ order | total = 2 }")
  // A non-variable target is bound first; Elm only updates a named record.
  let nested = @ir.Value::UpdateRecord(
    va(),
    record,
    Map::from_array([(n("total"), int("2"))]),
  )
  let printed = show(ctx, nested)
  assert_true(
    printed.contains("record_1 =") &&
    printed.contains("{ record_1 | total = 2 }"),
  )
}

///|
test "an update of a top-level record names the record" {
  let ctx = ctx_for()
  let fields = Map::from_array([(n("total"), int("2"))])
  // A value of the same module prints bare, and Elm updates a bare name.
  let same_module = @ir.Value::UpdateRecord(
    va(),
    sdk("acme/app:orders#empty"),
    fields,
  )
  assert_eq(show(ctx, same_module), "{ empty | total = 2 }")
  // A value of another module prints qualified, which Elm cannot update.
  let other = @ir.Value::UpdateRecord(
    va(),
    sdk("acme/app:defaults#empty"),
    fields,
  )
  let printed = show(ctx, other)
  assert_true(
    printed.contains("Acme.App.Defaults.empty") &&
    printed.contains("{ record_1 | total = 2 }"),
  )
}

///|
test "lambdas, lets, ifs and cases" {
  let ctx = ctx_for()
  let lambda = @ir.Value::Lambda(
    va(),
    bind_var("x"),
    @ir.Value::Lambda(va(), bind_var("y"), variable("x")),
  )
  assert_eq(show(ctx, lambda), "\\x y -> x")
  let let_value = @ir.Value::LetDefinition(
    va(),
    n("total"),
    ExpressionBody(
      [],
      @ir.Type::Unit({
        source: None,
        constraints: Map([]),
        extensions: Map([]),
      }),
      int("1"),
    ),
    @ir.Value::Destructure(
      va(),
      @ir.Pattern::TuplePattern(va(), [bind_var("p"), bind_var("q")]),
      @ir.Value::Tuple(va(), [int("1"), int("2")]),
      variable("total"),
    ),
  )
  let printed = show(ctx, let_value)
  assert_true(printed.has_prefix("let\n"))
  assert_true(printed.contains("total =\n") && printed.contains("( p, q ) =\n"))
  assert_true(printed.contains("total : ()\n")) // a closed type gives a signature
  let branch = @ir.Value::IfThenElse(
    va(),
    @ir.Value::Literal(va(), BoolLiteral(true)),
    int("1"),
    int("2"),
  )
  assert_true(show(ctx, branch).has_prefix("if True then"))
  let case_value = @ir.Value::PatternMatch(va(), int("1"), [
    (@ir.Pattern::LiteralPattern(va(), IntegerLiteral("1")), int("10")),
    (@ir.Pattern::WildcardPattern(va()), int("0")),
  ])
  let printed_case = show(ctx, case_value)
  assert_true(
    printed_case.contains("case 1 of") && printed_case.contains("_ ->"),
  )
}

///|
test "shadowed names are renamed" {
  let ctx = ctx_for()
  ctx.reserve_top_level("total")
  // let total = 1 in let total = total + 1 in total
  let inner = @ir.Value::LetDefinition(
    va(),
    n("total"),
    ExpressionBody(
      [],
      @ir.Type::Unit({
        source: None,
        constraints: Map([]),
        extensions: Map([]),
      }),
      apply(sdk("morphir/SDK:basics#add"), [variable("total"), int("1")]),
    ),
    variable("total"),
  )
  let outer = @ir.Value::LetDefinition(
    va(),
    n("total"),
    ExpressionBody(
      [],
      @ir.Type::Unit({
        source: None,
        constraints: Map([]),
        extensions: Map([]),
      }),
      int("1"),
    ),
    inner,
  )
  let printed = show(ctx, outer)
  assert_true(printed.contains("total_1 =\n"))
  assert_true(printed.contains("total_2 =\n"))
  assert_true(printed.contains("total_1 + 1"))
  assert_true(printed.has_suffix("total_2"))
}

///|
fn unit_type() -> @ir.Type {
  @ir.Type::Unit({ source: None, constraints: Map([]), extensions: Map([]), })
}

///|
test "a name in sibling scopes keeps its name" {
  let ctx = ctx_for()
  // Each case branch and each lambda is its own scope, so the second `a` does not shadow the first.
  let branches = @ir.Value::PatternMatch(va(), int("1"), [
    (bind_var("a"), variable("a")),
    (bind_var("a"), variable("a")),
  ])
  let printed = show(ctx, branches)
  assert_false(printed.contains("a_"))
  let lambdas = @ir.Value::Tuple(va(), [
    @ir.Value::Lambda(va(), bind_var("x"), variable("x")),
    @ir.Value::Lambda(va(), bind_var("x"), variable("x")),
  ])
  assert_eq(show(ctx, lambdas), "( \\x -> x, \\x -> x )")
}

///|
test "a name in a let definition avoids the names of its let block" {
  let ctx = ctx_for()
  // Elm sees every name of a let block in each of its definitions: the lambda of `f` must not bind `a` or `f`.
  let block = @ir.Value::LetDefinition(
    va(),
    n("f"),
    ExpressionBody(
      [],
      unit_type(),
      @ir.Value::Lambda(
        va(),
        bind_var("a"),
        @ir.Value::Lambda(va(), bind_var("f"), variable("a")),
      ),
    ),
    @ir.Value::LetDefinition(
      va(),
      n("a"),
      ExpressionBody([], unit_type(), int("1")),
      apply(variable("f"), [variable("a"), variable("a")]),
    ),
  )
  let printed = show(ctx, block)
  assert_true(printed.contains("\n    f a_1 f_2 =\n        a_1\n"))
  assert_true(printed.contains("\n    a =\n"))
  assert_true(printed.has_suffix("f a a"))
  // A destructuring sees its own names too.
  let destructure = @ir.Value::Destructure(
    va(),
    @ir.Pattern::TuplePattern(va(), [bind_var("p"), bind_var("q")]),
    @ir.Value::Tuple(va(), [
      @ir.Value::Lambda(va(), bind_var("p"), variable("p")),
      int("2"),
    ]),
    variable("q"),
  )
  let printed_destructure = show(ctx, destructure)
  assert_true(printed_destructure.contains("( p, q ) ="))
  assert_false(printed_destructure.contains("\\p "))
}

///|
test "a let definition has a signature only when its type has no variables" {
  let ctx = ctx_for()
  let int_type = ref_type("morphir/SDK:basics#int")
  let identity = @ir.Value::Lambda(va(), bind_var("x"), variable("x"))
  let closed = @ir.Value::LetDefinition(
    va(),
    n("g"),
    ExpressionBody(
      [],
      @ir.Type::Function(@ir.TypeAttributes::default(), int_type, int_type),
      identity,
    ),
    apply(variable("g"), [int("1")]),
  )
  let printed = show(ctx, closed)
  assert_true(printed.contains("\n    g : Int -> Int\n    g x =\n        x\n"))
  // Elm reads a variable in a let signature as a new rigid variable, so a type with a variable gets none.
  let open_type = @ir.Value::LetDefinition(
    va(),
    n("g"),
    ExpressionBody(
      [],
      @ir.Type::Function(
        @ir.TypeAttributes::default(),
        @ir.Type::Variable(@ir.TypeAttributes::default(), n("a")),
        int_type,
      ),
      identity,
    ),
    apply(variable("g"), [int("1")]),
  )
  assert_false(show(ctx, open_type).contains("g :"))
}

///|
test "a let function takes the arguments of its lambdas" {
  let ctx = ctx_for()
  // Elm refuses `loop = \\n -> loop n` as a cyclic value, but accepts `loop n = loop n`.
  let recursive = @ir.Value::LetRecursion(
    va(),
    Map::from_array([
      (
        n("loop"),
        ExpressionBody(
          [],
          unit_type(),
          @ir.Value::Lambda(
            va(),
            bind_var("n"),
            apply(variable("loop"), [variable("n")]),
          ),
        ),
      ),
    ]),
    apply(variable("loop"), [int("1")]),
  )
  assert_true(show(ctx, recursive).contains("\n    loop n =\n        loop n\n"))
  let paid = @ir.FQName::parse("acme/app:orders#paid") catch { _ => panic() }
  let unwrap = @ir.Value::LetDefinition(
    va(),
    n("unwrap"),
    ExpressionBody(
      [],
      unit_type(),
      @ir.Value::Lambda(
        va(),
        @ir.Pattern::ConstructorPattern(va(), paid, [bind_var("amount")]),
        @ir.Value::Lambda(va(), WildcardPattern(va()), variable("amount")),
      ),
    ),
    variable("unwrap"),
  )
  assert_true(
    show(ctx, unwrap).contains(
      "\n    unwrap (Paid amount) _ =\n        amount\n",
    ),
  )
}

///|
test "constructors, patterns and placeholders" {
  let ctx = ctx_for()
  let just = apply(
    @ir.Value::Constructor(
      va(),
      @ir.FQName::parse("morphir/SDK:maybe#just") catch {
        _ => panic()
      },
    ),
    [int("1")],
  )
  assert_eq(show(ctx, just), "Just 1")
  let pattern = @ir.Pattern::ConstructorPattern(
    va(),
    @ir.FQName::parse("acme/app:orders#paid") catch {
      _ => panic()
    },
    [bind_var("amount")],
  )
  assert_eq(
    @printer.print_pattern(node(lower_pattern(ctx, pattern, "p"))),
    "Paid amount",
  )
  let float_pattern = @ir.Pattern::LiteralPattern(va(), FloatLiteral(1.5))
  let code = try {
    ignore(lower_pattern(ctx, float_pattern, "p"))
    ""
  } catch {
    Refused(problem) => problem.code
    _ => "other"
  }
  assert_eq(code, "elm.literal_pattern")
  let hole = @ir.Value::Hole(va(), DeletedDuringRefactor("gone"), None)
  assert_eq(refusal(ctx, hole), "elm.placeholder")
  let todo_ctx = Ctx::new(
    { ..Options::default(), placeholders: DebugTodo, },
    @ir.Path::parse("acme/app") catch {
      _ => panic()
    },
    @ir.Path::parse("orders") catch {
      _ => panic()
    },
  )
  assert_eq(
    show(todo_ctx, hole),
    "Debug.todo \"hole: deleted during refactor: gone\"",
  )
}

///|
fn as_pattern(inner : @ir.Pattern, name : String) -> @ir.Pattern {
  @ir.Pattern::AsPattern(va(), inner, n(name))
}

///|
fn head_tail(head : @ir.Pattern, tail : @ir.Pattern) -> @ir.Pattern {
  @ir.Pattern::HeadTailPattern(va(), head, tail)
}

///|
/// The pattern printed alone, and a module with a case on it that must parse back.
fn check_pattern(p : @ir.Pattern) -> String raise {
  let printed = @printer.print_pattern(
    node(lower_pattern(ctx_for(), p, "acme/app:orders#v")),
  )
  let value = defined(
    "pick",
    Public,
    None,
    ExpressionBody(
      [(n("subject"), int_type())],
      int_type(),
      @ir.Value::PatternMatch(va(), variable("subject"), [
        (p, int("1")),
        (WildcardPattern(va()), int("0")),
      ]),
    ),
  )
  let source = generate_module(Options::default(), module_with([value])).source
  assert_true(parses_back(source), msg=source)
  printed
}

///|
test "as-patterns are parenthesized inside cons and constructor patterns" {
  let wildcard = @ir.Pattern::WildcardPattern(va())
  // a :: (b :: _ as rest): rest binds the tail, not the whole list.
  assert_eq(
    check_pattern(
      head_tail(
        bind_var("a"),
        as_pattern(head_tail(bind_var("b"), wildcard), "rest"),
      ),
    ),
    "a :: ((b :: _) as rest)",
  )
  let pair = @ir.Pattern::TuplePattern(va(), [bind_var("x"), bind_var("y")])
  assert_eq(
    check_pattern(head_tail(as_pattern(pair, "first"), wildcard)),
    "(( x, y ) as first) :: _",
  )
  let just = @ir.FQName::parse("morphir/SDK:maybe#just") catch { _ => panic() }
  assert_eq(
    check_pattern(
      @ir.Pattern::ConstructorPattern(va(), just, [as_pattern(pair, "inner")]),
    ),
    "Just (( x, y ) as inner)",
  )
}
