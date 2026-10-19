///|
test "Union substitution preserves authored duplicate alternatives" {
  let t : @ir.Type = Union(tattrs(), [tv("a"), tr(STRING, [])])
  assert_eq(
    substitute_type(t, Map([("a", tr(STRING, []))])),
    Union(tattrs(), [tr(STRING, []), tr(STRING, [])]),
  )
}

///|
test "Union conversion preserves member and outer source attributes" {
  let a : @ir.TypeAttributes = {
    ..tattrs(),
    source: Some({ start_line: 1, start_column: 2, end_line: 3, end_column: 4, }),
  }
  let t : @ir.Type = Union(a, [Reference(a, fq(STRING), []), t_int()])
  let solver = Solver::new((_, _) => None)
  assert_eq(Namer::new().to_ir(solver, to_ty(t, (n, _) => Rigid(n, []))), t)
}

///|
test "Union declared result accepts a member and preserves the entire parameter" {
  let i = new_infer()
  let union : @ir.Type = Union(tattrs(), [tr(STRING, []), t_int()])
  let d : @ir.ValueDefinition = ExpressionBody([], union, v_str("ok"))
  assert_eq(failure(() => ignore(i.definition(d, "f"))), ("", ""))
  let bad : @ir.ValueDefinition = ExpressionBody(
    [(nm("x"), union)],
    tr(STRING, []),
    v_var("x"),
  )
  assert_eq(
    failure(() => ignore(new_infer().definition(bad, "f"))).0,
    "type_mismatch",
  )
}

///|
test "Union calls accept members independently of alternative order" {
  for arms in [[Con(STRING, []), Con(INT, [])], [Con(INT, []), Con(STRING, [])]] {
    let i = new_infer()
    i.bind(nm("f"), Fun(Union(arms), Con(STRING, [])))
    assert_eq(
      failure(() => ignore(i.value(Apply(va(), v_var("f"), v_str("x")), "v"))),
      ("", ""),
    )
  }
}

///|
test "Union shape equivalence backtracks across the entire signature" {
  let a : @ir.Type = Function(
    tattrs(),
    Union(tattrs(), [tv("a"), tv("b")]),
    tv("a"),
  )
  let b : @ir.Type = Function(
    tattrs(),
    Union(tattrs(), [tv("x"), tv("y")]),
    tv("y"),
  )
  assert_true(types_equivalent(a, b))
  assert_false(
    types_equivalent(
      Union(tattrs(), [tv("a"), tv("b")]),
      Union(tattrs(), [tv("x"), tv("x")]),
    ),
  )
}

///|
test "Union equality accepts reordering but cannot narrow a live meta through an arm" {
  let s = Solver::new((_, _) => None)
  s.unify(
    Union([Con(STRING, []), Con(INT, [])]),
    Union([Con(INT, []), Con(STRING, [])]),
  )
  let meta = s.fresh(1, [])
  assert_eq(
    s.assignable(Con(STRING, []), Union([meta, Con(INT, [])])),
    Unknown(UnresolvedVariable),
  )
  assert_eq(s.peek(meta), meta)
}

///|
test "Union obligations apply at their authored level" {
  let s = Solver::new((_, _) => None)
  let attrs : @ir.TypeAttributes = {
    ..tattrs(),
    extensions: Map([("example.refinement", Text("positive"))]),
  }
  let int = Con(INT, [])
  let refined = Attributed(attrs, int)
  assert_eq(s.assignable(int, refined), Unknown(UnsupportedExtension))
  assert_eq(s.assignable(refined, int), Proven)
  assert_eq(s.assignable(refined, refined), Proven)
  assert_eq(s.assignable(int, Union([refined, int])), Proven)
  assert_eq(
    s.assignable(int, Attributed(attrs, Union([int, Con(STRING, [])]))),
    Unknown(UnsupportedExtension),
  )
}

///|
test "Union scope keeps alternative bijections for later comparisons" {
  let scope = TypeScope::of_definition(
    ExpressionBody([], Unit(tattrs()), Unit(va())),
  )
  assert_true(
    scope.equivalent(
      Union(tattrs(), [tv("a"), tv("b")]),
      Union(tattrs(), [tv("x"), tv("y")]),
    ),
  )
  assert_true(scope.equivalent(tv("a"), tv("y")))
  assert_false(scope.equivalent(tv("b"), tv("y")))
  assert_true(scope.equivalent(tv("b"), tv("x")))
}

///|
test "Union substitution refuses conflicting occurrence attributes" {
  let a : @ir.TypeAttributes = {
    ..tattrs(),
    extensions: Map([("r", Text("one"))]),
  }
  let b : @ir.TypeAttributes = {
    ..tattrs(),
    extensions: Map([("r", Text("two"))]),
  }
  let template : @ir.Type = Union(a, [Variable(a, nm("x")), t_int()])
  try
    substitute_type(template, Map([("x", Reference(b, fq(STRING), []))]))
  catch {
    AttributeConflict => ()
  } noraise {
    _ => fail("attribute conflict was erased")
  }
  let substituted = substitute_type(template, Map([("x", tr(STRING, []))]))
  assert_eq(substituted, Union(a, [Reference(a, fq(STRING), []), t_int()]))
}

///|
test "Union aliases preserve reference and body obligations in semantic proof" {
  let a : @ir.TypeAttributes = {
    ..tattrs(),
    extensions: Map([("r", Text("one"))]),
  }
  let b : @ir.TypeAttributes = {
    ..tattrs(),
    constraints: Map([("c", Text("two"))]),
  }
  let s = Solver::new((name, _) => {
    if name == "alias" {
      Some(Attributed(b, Con(INT, [])))
    } else {
      None
    }
  })
  let aliased = Attributed(a, Con("alias", []))
  assert_eq(
    s.assignable(aliased, Attributed(a, Attributed(b, Con(INT, [])))),
    Proven,
  )
  assert_eq(s.assignable(Con(INT, []), aliased), Unknown(UnsupportedExtension))
  assert_eq(s.assignable(Union([aliased, Con(INT, [])]), Con(INT, [])), Proven)
}

///|
test "Union generic result preserves rigid identity and refuses numeric guessing" {
  let union : @ir.Type = Union(tattrs(), [tv("a"), tr(STRING, [])])
  let d : @ir.ValueDefinition = ExpressionBody(
    [(nm("x"), tv("a"))],
    union,
    v_var("x"),
  )
  assert_eq(failure(() => ignore(new_infer().definition(d, "f"))), ("", ""))
  let numeric : @ir.Type = Union(tattrs(), [t_int(), t_float()])
  assert_eq(
    failure(() => {
      ignore(
        new_infer().definition(ExpressionBody([], numeric, v_int("1")), "f"),
      )
    }).0,
    "unsupported",
  )
}

///|
test "shared inference metas do not transfer occurrence source positions" {
  let a : @ir.TypeAttributes = {
    ..tattrs(),
    source: Some({ start_line: 1, start_column: 1, end_line: 1, end_column: 2, }),
  }
  let b : @ir.TypeAttributes = {
    ..tattrs(),
    source: Some({ start_line: 2, start_column: 1, end_line: 2, end_column: 2, }),
  }
  let s = Solver::new((_, _) => None)
  let shared = s.fresh(1, [])
  let first = Attributed(a, shared)
  let second = Attributed(b, Con(STRING, []))
  s.unify(first, second)
  let namer = Namer::new()
  assert_eq(namer.to_ir(s, first), Reference(a, fq(STRING), []))
  assert_false(namer.conflicts.val)
  assert_eq(namer.to_ir(s, second), Reference(b, fq(STRING), []))
}

///|
test "rigid diagnostics see through descriptive occurrence attributes" {
  let a : @ir.TypeAttributes = {
    ..tattrs(),
    source: Some({ start_line: 1, start_column: 1, end_line: 1, end_column: 2, }),
  }
  let s = Solver::new((_, _) => None)
  let variable = Attributed(a, Rigid("a", []))
  let number = s.fresh(1, [NUMBER])
  assert_eq(
    rigid_message(s, "", variable, number, tv("a"), tv("number")),
    Some("the variable `a` is annotated as any type, but the body needs number"),
  )
}

///|
test "legacy alias shape expansion ignores occurrence source conflicts" {
  let a : @ir.TypeAttributes = {
    ..tattrs(),
    source: Some({ start_line: 1, start_column: 1, end_line: 1, end_column: 2, }),
  }
  let b : @ir.TypeAttributes = {
    ..tattrs(),
    source: Some({ start_line: 2, start_column: 1, end_line: 2, end_column: 2, }),
  }
  let env = Env::new()
  env.types["example:types#label"] = Alias([], Reference(b, fq(STRING), []))
  assert_true(
    types_equivalent(
      env.expand_shape(Reference(a, fq("example:types#label"), [])),
      tr(STRING, []),
    ),
  )
}
