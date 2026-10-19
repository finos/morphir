///|
test "Union declared branches Fill then Check preserve signature and facts" {
  let union : @ir.Type = Union(tattrs(), [t_string(), t_int()])
  let file = library([
    (
      "m",
      [
        (
          "choose",
          ExpressionBody(
            [(nm("flag"), tr(BOOL, []))],
            union,
            IfThenElse(
              va(),
              Variable(va(), nm("flag")),
              v_str("yes"),
              fact_int("1"),
            ),
          ),
        ),
      ],
    ),
  ])
  let filled = fill(file)
  assert_eq(check(filled), filled)
  guard definition_in(filled, "m", "choose") is ExpressionBody(_, output, _) else {
    fail("definition lost")
  }
  assert_eq(output, union)
}

///|
test "Union semantic context expands visible aliases and keeps opaque identities" {
  let file = library_with_types([
    ("m", [("label", TypeAliasDefinition([], t_string()))], []),
  ])
  let context = @typing.TypeContext::from(file, deps())
  let label = tr("acme/app:m#label", [])
  let union : @ir.Type = Union(tattrs(), [t_string(), label])
  assert_eq(context.equivalent(union, t_string()), @typing.TypeRelation::Proven)
  assert_eq(
    context.assignable(t_int(), t_string()),
    @typing.TypeRelation::Refuted,
  )
  assert_eq(
    context.assignable(Union(tattrs(), [t_int(), t_string()]), t_string()),
    @typing.TypeRelation::Refuted,
  )
}

///|
test "Union generic calls and nested let results survive Fill then Check" {
  let generic : @ir.Type = Union(tattrs(), [tv("a"), t_string()])
  let concrete : @ir.Type = Union(tattrs(), [tr(BOOL, []), t_string()])
  let file = library([
    (
      "m",
      [
        (
          "widen",
          ExpressionBody([(nm("x"), tv("a"))], generic, Variable(va(), nm("x"))),
        ),
        (
          "call",
          ExpressionBody(
            [],
            concrete,
            Apply(
              va(),
              Reference(va(), fq("acme/app:m#widen")),
              Literal(va(), BoolLiteral(true)),
            ),
          ),
        ),
        (
          "local",
          ExpressionBody(
            [],
            Union(tattrs(), [t_string(), t_int()]),
            LetDefinition(
              va(),
              nm("inner"),
              ExpressionBody(
                [],
                Union(tattrs(), [t_string(), t_int()]),
                v_str("ok"),
              ),
              Variable(va(), nm("inner")),
            ),
          ),
        ),
      ],
    ),
  ])
  assert_eq(problems(() => fill(file)), [])
  let filled = fill(file)
  assert_eq(problems(() => check(filled)), [])
  assert_eq(check(filled), filled)
  guard definition_in(filled, "m", "call") is ExpressionBody(_, out, _) else {
    fail("call lost")
  }
  assert_eq(out, concrete)
}

///|
test "Union partially solved signatures and facts keep authored source attributes" {
  let source : @ir.SourceLocation = {
    start_line: 1,
    start_column: 1,
    end_line: 1,
    end_column: 9,
  }
  let a : @ir.TypeAttributes = { ..tattrs(), source: Some(source), }
  let marked : @ir.Type = Variable(a.with_unknown(), nm("t-0"))
  let union : @ir.Type = Union(a, [t_string(), t_int()])
  let partial : @ir.Type = Tuple(a, [marked, union])
  let fact_type : @ir.Type = Tuple(a, [Variable(a, nm("free")), union])
  let body : @ir.Value = Tuple({ ..va(), inferred_type: Some(fact_type), }, [
    v_str("ok"),
    Variable(va(), nm("x")),
  ])
  let file = library([
    ("m", [("pair", ExpressionBody([(nm("x"), union)], partial, body))]),
  ])
  assert_eq(problems(() => fill(file)), [])
  let filled = fill(file)
  assert_eq(check(filled), filled)
  guard definition_in(filled, "m", "pair")
    is ExpressionBody(
      _,
      Tuple(out, [Reference(member_attrs, _, _), _]),
      Tuple(fact, _)
    ) else {
    fail("solved shape lost")
  }
  assert_eq(out.source, Some(source))
  assert_eq(member_attrs.source, Some(source))
  guard fact.inferred_type
    is Some(Tuple(fact_attrs, [Reference(child_attrs, _, _), _])) else {
    fail("solved fact lost")
  }
  assert_eq(fact_attrs.source, Some(source))
  assert_eq(child_attrs.source, Some(source))
}

///|
test "Union TypeContext does not expose opaque representation" {
  let opaque_spec : @ir.PackageSpecification = {
    modules: Map([
      (
        pkg("ids"),
        {
          annotations: [],
          doc: None,
          values: Map([]),
          types: Map([
            (
              nm("user"),
              {
                doc: None,
                value: { annotations: [], body: OpaqueTypeSpecification([]), },
              },
            ),
            (
              nm("order"),
              {
                doc: None,
                value: { annotations: [], body: OpaqueTypeSpecification([]), },
              },
            ),
          ]),
        },
      ),
    ]),
  }
  let dependencies = deps()
  dependencies[pkg("example")] = opaque_spec
  let context = @typing.TypeContext::from(library([]), dependencies)
  let user_type = tr("example:ids#user", [])
  let order_type = tr("example:ids#order", [])
  assert_eq(
    context.assignable(user_type, user_type),
    @typing.TypeRelation::Proven,
  )
  assert_eq(
    context.assignable(user_type, order_type),
    @typing.TypeRelation::Refuted,
  )
  assert_eq(
    context.assignable(user_type, t_int()),
    @typing.TypeRelation::Refuted,
  )
}

///|
test "Union expected elements guide list and case results without synthesizing a choice" {
  let u : @ir.Type = Union(tattrs(), [t_string(), t_int()])
  let list : @ir.Value = List(va(), [v_str("ok"), fact_int("1")])
  let cases : @ir.Value = PatternMatch(va(), Literal(va(), BoolLiteral(true)), [
    (LiteralPattern(va(), BoolLiteral(true)), v_str("ok")),
    (WildcardPattern(va()), fact_int("1")),
  ])
  let file = library([
    (
      "m",
      [
        ("items", ExpressionBody([], t_list(u), list)),
        ("matched", ExpressionBody([], u, cases)),
      ],
    ),
  ])
  assert_eq(problems(() => fill(file)), [])
  let filled = fill(file)
  assert_eq(check(filled), filled)
}

///|
fn assert_contextual_union_continuation(
  wrap : (@ir.ValueAttributes, @ir.Value) -> @ir.Value,
) -> Unit raise {
  let union : @ir.Type = Union(tattrs(), [t_string(), tr(BOOL, [])])
  let source : @ir.SourceLocation = {
    start_line: 2,
    start_column: 1,
    end_line: 5,
    end_column: 1,
  }
  let attributed = (t : @ir.Type) => @ir.ValueAttributes::{
    ..fact(t),
    source: Some(source),
  }
  let mixed : @ir.Value = IfThenElse(
    va(),
    Variable(va(), nm("flag")),
    v_str("ok"),
    Literal(va(), BoolLiteral(false)),
  )
  let file = library([
    (
      "m",
      [
        (
          "accept",
          ExpressionBody([(nm("input"), union)], t_string(), v_str("accepted")),
        ),
        (
          "choose",
          ExpressionBody(
            [(nm("flag"), tr(BOOL, []))],
            union,
            wrap(attributed(union), mixed),
          ),
        ),
        (
          "items",
          ExpressionBody(
            [],
            t_list(union),
            wrap(
              attributed(t_list(union)),
              List(va(), [v_str("ok"), Literal(va(), BoolLiteral(false))]),
            ),
          ),
        ),
        (
          "argument",
          ExpressionBody(
            [(nm("flag"), tr(BOOL, []))],
            t_string(),
            Apply(
              va(),
              Reference(va(), fq("acme/app:m#accept")),
              wrap(attributed(union), mixed),
            ),
          ),
        ),
        (
          "narrow",
          ExpressionBody([], union, wrap(attributed(t_string()), v_str("ok"))),
        ),
      ],
    ),
  ])
  assert_eq(problems(() => fill(file)), [])
  let filled = fill(file)
  assert_eq(check(filled), filled)
  for
    (name, expected) in [
      ("choose", union),
      ("items", t_list(union)),
      ("narrow", t_string()),
    ] {
    guard definition_in(filled, "m", name) is ExpressionBody(_, _, body) else {
      fail("missing wrapper definition")
    }
    let attrs = match body {
      LetDefinition(a, _, _, _)
      | LetRecursion(a, _, _)
      | Destructure(a, _, _, _) => a
      _ => fail("wrapper erased")
    }
    assert_eq(attrs.source, Some(source))
    assert_eq(attrs.inferred_type, Some(expected))
  }
  let bad : @ir.Value = IfThenElse(
    va(),
    Variable(va(), nm("flag")),
    v_str("ok"),
    Unit(va()),
  )
  let outside = library([
    (
      "m",
      [
        (
          "bad",
          ExpressionBody([(nm("flag"), tr(BOOL, []))], union, wrap(va(), bad)),
        ),
      ],
    ),
  ])
  assert_eq(problems(() => fill(outside)), [
    ("type_mismatch", "value:acme/app:m#bad/body/in/else"),
  ])
  let wrong_fact = library([
    (
      "m",
      [
        (
          "bad",
          ExpressionBody(
            [(nm("flag"), tr(BOOL, []))],
            union,
            wrap(fact(t_string()), mixed),
          ),
        ),
      ],
    ),
  ])
  assert_eq(problems(() => fill(wrong_fact)), [
    ("annotation_mismatch", "value:acme/app:m#bad/body"),
  ])
  let unknown = library([
    (
      "m",
      [
        (
          "unannotated",
          ExpressionBody(
            [(nm("flag"), tr(BOOL, []))],
            tmarked("result"),
            wrap(va(), mixed),
          ),
        ),
      ],
    ),
  ])
  assert_true(!problems(() => fill(unknown)).is_empty())
}

///|
test "Union context reaches let continuation results and function arguments" {
  assert_contextual_union_continuation((a, rest) => {
    LetDefinition(
      a,
      nm("unused"),
      ExpressionBody([], Unit(tattrs()), Unit(va())),
      rest,
    )
  })
}

///|
test "Union context reaches recursive let continuation results and function arguments" {
  assert_contextual_union_continuation((a, rest) => {
    LetRecursion(
      a,
      Map([(nm("unused"), ExpressionBody([], Unit(tattrs()), Unit(va())))]),
      rest,
    )
  })
}

///|
test "Union context reaches destructuring continuation results and function arguments" {
  assert_contextual_union_continuation((a, rest) => {
    Destructure(
      a,
      AsPattern(va(), WildcardPattern(va()), nm("unused")),
      Unit(va()),
      rest,
    )
  })
}
