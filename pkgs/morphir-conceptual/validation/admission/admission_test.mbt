///|
fn fixture_env() -> @admission.TypeEnvironment {
  @admission.TypeEnvironment::new(profile=@admission.supported_profile, declarations=[
    (
      "PositiveAmount",
      @admission.Transparent([], @admission.TInt, Some(@admission.PositiveInt)),
    ),
    (
      "BorrowerName",
      @admission.Transparent(
        [],
        @admission.TString,
        Some(@admission.NonEmptyString),
      ),
    ),
    (
      "UserId",
      @admission.Opaque([], @admission.TString, Some(@admission.NonEmptyString)),
    ),
    (
      "Loan",
      @admission.Custom([], [
        (
          "Loan",
          [
            @admission.TRecord([
              ("borrower", @admission.TReference("BorrowerName", [])),
              ("amount", @admission.TReference("PositiveAmount", [])),
              ("tags", @admission.TList(@admission.TString)),
            ]),
          ],
        ),
      ]),
    ),
    (
      "Tree",
      @admission.Custom([], [
        ("Leaf", [@admission.TInt]),
        (
          "Node",
          [@admission.TReference("Tree", []), @admission.TReference("Tree", [])],
        ),
      ]),
    ),
    (
      "Maybe",
      @admission.Custom(["a"], [
        ("None", []),
        ("Some", [@admission.TVariable("a")]),
      ]),
    ),
    (
      "Box",
      @admission.Transparent(
        ["a"],
        @admission.TRecord([("item", @admission.TVariable("a"))]),
        None,
      ),
    ),
    (
      "IntOrText",
      @admission.Transparent(
        [],
        @admission.TUnion([@admission.TInt, @admission.TString]),
        None,
      ),
    ),
    (
      "CycleA",
      @admission.Transparent([], @admission.TReference("CycleB", []), None),
    ),
    (
      "CycleB",
      @admission.Transparent([], @admission.TReference("CycleA", []), None),
    ),
    ("Id", @admission.Transparent(["a"], @admission.TVariable("a"), None)),
    ("Number", @admission.Transparent([], @admission.TInt, None)),
    (
      "Grow",
      @admission.Transparent(
        ["a"],
        @admission.TReference("Grow", [
          @admission.TList(@admission.TVariable("a")),
        ]),
        None,
      ),
    ),
    (
      "Loop",
      @admission.Transparent([], @admission.TReference("Loop", []), None),
    ),
    (
      "NamedOk",
      @admission.Transparent(
        [],
        @admission.TString,
        Some(@admission.NamedRefinement("string.nonEmpty")),
      ),
    ),
    (
      "Weird",
      @admission.Transparent(
        [],
        @admission.TString,
        Some(@admission.NamedRefinement("text.uppercase")),
      ),
    ),
  ])
}

///|
fn expect_valid(outcome : @admission.Outcome) -> Unit raise {
  assert_true(outcome is Valid)
}

///|
fn expect_invalid(outcome : @admission.Outcome, code : String) -> Unit raise {
  match outcome {
    Invalid(diagnostics) =>
      assert_true(diagnostics.iter().any(d => d.code == code))
    _ => fail("expected Invalid(" + code + "), got a different outcome")
  }
}

///|
fn expect_unsupported(
  outcome : @admission.Outcome,
  code : String,
) -> Unit raise {
  match outcome {
    Unsupported(diagnostic) => assert_eq(diagnostic.code, code)
    _ => fail("expected Unsupported(" + code + "), got a different outcome")
  }
}

///|
test "tracer: a well-formed record value is admitted" {
  let outcome = @admission.admit(
    fixture_env(),
    @admission.TRecord([
      ("borrower", @admission.TString),
      ("amount", @admission.TInt),
    ]),
    @admission.VRecord([
      ("borrower", @admission.VString("Ada")),
      ("amount", @admission.int_value("1200")),
    ]),
  )
  expect_valid(outcome)
}

///|
test "records reject missing, extra and mistyped fields" {
  let ty = @admission.TRecord([
    ("borrower", @admission.TString),
    ("amount", @admission.TInt),
  ])
  expect_invalid(
    @admission.admit(
      fixture_env(),
      ty,
      @admission.VRecord([("borrower", @admission.VString("Ada"))]),
    ),
    "contracts.invalid_value",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      ty,
      @admission.VRecord([
        ("borrower", @admission.VString("Ada")),
        ("amount", @admission.int_value("1")),
        ("extra", @admission.VBool(true)),
      ]),
    ),
    "contracts.invalid_value",
  )
  let outcome = @admission.admit(
    fixture_env(),
    ty,
    @admission.VRecord([
      ("borrower", @admission.VString("Ada")),
      ("amount", @admission.VString("lots")),
    ]),
  )
  match outcome {
    Invalid(diagnostics) => {
      assert_eq(diagnostics[0].code, "contracts.invalid_value")
      assert_eq(diagnostics[0].path, "/amount")
    }
    _ => fail("expected Invalid for a mistyped field")
  }
}

///|
test "custom types check constructors recursively" {
  let leaf = @admission.VConstructed("Leaf", [@admission.int_value("1")])
  let tree = @admission.VConstructed("Node", [
    leaf,
    @admission.VConstructed("Node", [
      leaf,
      @admission.VConstructed("Leaf", [@admission.int_value("2")]),
    ]),
  ])
  expect_valid(
    @admission.admit(fixture_env(), @admission.TReference("Tree", []), tree),
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TReference("Tree", []),
      @admission.VConstructed("Node", [
        leaf,
        @admission.VConstructed("Leaf", [@admission.VString("x")]),
      ]),
    ),
    "contracts.invalid_value",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TReference("Tree", []),
      @admission.VConstructed("Branch", [leaf]),
    ),
    "contracts.invalid_value",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TReference("Tree", []),
      @admission.VConstructed("Leaf", []),
    ),
    "contracts.invalid_value",
  )
}

///|
test "generic declarations instantiate at concrete argument types" {
  let maybe_int = @admission.TReference("Maybe", [@admission.TInt])
  expect_valid(
    @admission.admit(
      fixture_env(),
      maybe_int,
      @admission.VConstructed("Some", [@admission.int_value("5")]),
    ),
  )
  expect_valid(
    @admission.admit(
      fixture_env(),
      maybe_int,
      @admission.VConstructed("None", []),
    ),
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      maybe_int,
      @admission.VConstructed("Some", [@admission.VString("five")]),
    ),
    "contracts.invalid_value",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TReference("Maybe", []),
      @admission.VConstructed("None", []),
    ),
    "contracts.invalid_value",
  )
  let box_text = @admission.TReference("Box", [@admission.TString])
  expect_valid(
    @admission.admit(
      fixture_env(),
      box_text,
      @admission.VRecord([("item", @admission.VString("sealed"))]),
    ),
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      box_text,
      @admission.VRecord([("item", @admission.int_value("3"))]),
    ),
    "contracts.invalid_value",
  )
}

///|
test "tuples of arbitrary arity check element by element" {
  let ty = @admission.TTuple([
    @admission.TBool,
    @admission.TInt,
    @admission.TString,
    @admission.TInt,
    @admission.TBool,
  ])
  expect_valid(
    @admission.admit(
      fixture_env(),
      ty,
      @admission.VTuple([
        @admission.VBool(true),
        @admission.int_value("1"),
        @admission.VString("x"),
        @admission.int_value("2"),
        @admission.VBool(false),
      ]),
    ),
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      ty,
      @admission.VTuple([@admission.VBool(true)]),
    ),
    "contracts.invalid_value",
  )
}

///|
test "collections check elements and reject duplicate set or dict keys" {
  expect_valid(
    @admission.admit(
      fixture_env(),
      @admission.TList(@admission.TInt),
      @admission.VList([@admission.int_value("1"), @admission.int_value("2")]),
    ),
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TList(@admission.TInt),
      @admission.VList([@admission.VString("one")]),
    ),
    "contracts.invalid_value",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TSet(@admission.TInt),
      @admission.VSet([@admission.int_value("1"), @admission.int_value("1")]),
    ),
    "contracts.invalid_value",
  )
  let dict_ty = @admission.TDict(@admission.TString, @admission.TInt)
  expect_valid(
    @admission.admit(
      fixture_env(),
      dict_ty,
      @admission.VDict([(@admission.VString("a"), @admission.int_value("1"))]),
    ),
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      dict_ty,
      @admission.VDict([
        (@admission.VString("a"), @admission.int_value("1")),
        (@admission.VString("a"), @admission.int_value("2")),
      ]),
    ),
    "contracts.invalid_value",
  )
}

///|
test "refinements are respected and exact integers stay exact" {
  let amount = @admission.TReference("PositiveAmount", [])
  expect_valid(
    @admission.admit(
      fixture_env(),
      amount,
      @admission.int_value("9223372036854775807000"),
    ),
  )
  expect_invalid(
    @admission.admit(fixture_env(), amount, @admission.int_value("0")),
    "contracts.refinement_failed",
  )
  expect_invalid(
    @admission.admit(fixture_env(), amount, @admission.int_value("-3")),
    "contracts.refinement_failed",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TReference("BorrowerName", []),
      @admission.VString(""),
    ),
    "contracts.refinement_failed",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TReference("NamedOk", []),
      @admission.VString(""),
    ),
    "contracts.refinement_failed",
  )
}

///|
test "opaque types accept only constructed values for the same name" {
  let user_id = @admission.TReference("UserId", [])
  expect_valid(
    @admission.admit(
      fixture_env(),
      user_id,
      @admission.VOpaque("UserId", @admission.VString("user-1")),
    ),
  )
  expect_invalid(
    @admission.admit(fixture_env(), user_id, @admission.VString("user-1")),
    "contracts.opaque_construction",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      user_id,
      @admission.VOpaque("OtherId", @admission.VString("user-1")),
    ),
    "contracts.opaque_construction",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      user_id,
      @admission.VOpaque("UserId", @admission.VString("")),
    ),
    "contracts.refinement_failed",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TString,
      @admission.VOpaque("UserId", @admission.VString("user-1")),
    ),
    "contracts.opaque_construction",
  )
}

///|
test "unions admit exactly one matching member and report ambiguity" {
  let union_ty = @admission.TReference("IntOrText", [])
  expect_valid(
    @admission.admit(fixture_env(), union_ty, @admission.int_value("7")),
  )
  expect_valid(
    @admission.admit(fixture_env(), union_ty, @admission.VString("seven")),
  )
  expect_invalid(
    @admission.admit(fixture_env(), union_ty, @admission.VBool(true)),
    "contracts.invalid_value",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TUnion([
        @admission.TReference("PositiveAmount", []),
        @admission.TInt,
      ]),
      @admission.int_value("5"),
    ),
    "contracts.ambiguous_value",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TUnion([]),
      @admission.int_value("5"),
    ),
    "contracts.invalid_value",
  )
}

///|
test "unsupported types and missing information are reported" {
  expect_unsupported(
    @admission.admit(
      fixture_env(),
      @admission.TFunction([@admission.TInt], @admission.TInt),
      @admission.int_value("1"),
    ),
    "contracts.unsupported_type",
  )
  expect_unsupported(
    @admission.admit(
      fixture_env(),
      @admission.TUnsupported("Decimal"),
      @admission.int_value("1"),
    ),
    "contracts.unsupported_type",
  )
  expect_unsupported(
    @admission.admit(
      fixture_env(),
      @admission.TReference("Missing", []),
      @admission.int_value("1"),
    ),
    "contracts.unknown_type",
  )
  expect_unsupported(
    @admission.admit(
      fixture_env(),
      @admission.TVariable("a"),
      @admission.int_value("1"),
    ),
    "contracts.unbound_variable",
  )
  expect_unsupported(
    @admission.admit(
      fixture_env(),
      @admission.TReference("Weird", []),
      @admission.VString("HELLO"),
    ),
    "contracts.unsupported_refinement",
  )
  expect_unsupported(
    @admission.admit(
      fixture_env(),
      @admission.TUnion([
        @admission.TInt,
        @admission.TFunction([], @admission.TInt),
      ]),
      @admission.int_value("1"),
    ),
    "contracts.unsupported_type",
  )
}

///|
test "budgets never pass an exhausted check" {
  let no_nodes : @admission.Limits = {
    max_depth: 64,
    max_value_nodes: 0,
    max_int_digits: 256,
  }
  let outcome = @admission.admit(
    fixture_env(),
    @admission.TBool,
    @admission.VBool(true),
    limits=no_nodes,
  )
  assert_true(outcome is Exhausted(NodeLimit))
  let shallow : @admission.Limits = {
    max_depth: 2,
    max_value_nodes: 100,
    max_int_digits: 256,
  }
  let deep = @admission.admit(
    fixture_env(),
    @admission.TList(@admission.TList(@admission.TInt)),
    @admission.VList([@admission.VList([@admission.int_value("1")])]),
    limits=shallow,
  )
  assert_true(deep is Exhausted(DepthLimit))
  let tree_ty = @admission.TReference("Tree", [])
  let mut value = @admission.VConstructed("Leaf", [@admission.int_value("0")])
  for _ in 0..<40 {
    value = @admission.VConstructed("Node", [value, value])
  }
  let bounded : @admission.Limits = {
    max_depth: 16,
    max_value_nodes: 100000,
    max_int_digits: 256,
  }
  assert_true(
    @admission.admit(fixture_env(), tree_ty, value, limits=bounded)
    is Exhausted(_),
  )
}

///|
test "alias cycles fail instead of looping" {
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TReference("CycleA", []),
      @admission.VString("x"),
    ),
    "contracts.alias_cycle",
  )
}

///|
test "profile and declaration errors are reported before checking" {
  let wrong_profile = @admission.TypeEnvironment::new(
    profile="morphir-contracts/9.9.9",
    declarations=[],
  )
  expect_unsupported(
    @admission.admit(wrong_profile, @admission.TBool, @admission.VBool(true)),
    "contracts.unsupported_profile",
  )
  let duplicated = @admission.TypeEnvironment::new(
    profile=@admission.supported_profile,
    declarations=[
      ("Dup", @admission.Transparent([], @admission.TInt, None)),
      ("Dup", @admission.Transparent([], @admission.TString, None)),
    ],
  )
  expect_invalid(
    @admission.admit(
      duplicated,
      @admission.TReference("Dup", []),
      @admission.int_value("1"),
    ),
    "contracts.duplicate_declaration",
  )
}

///|
test "nested declarations compose inside custom payloads" {
  let loan = @admission.VConstructed("Loan", [
    @admission.VRecord([
      ("borrower", @admission.VString("Ada")),
      ("amount", @admission.int_value("1200")),
      ("tags", @admission.VList([@admission.VString("first")])),
    ]),
  ])
  expect_valid(
    @admission.admit(fixture_env(), @admission.TReference("Loan", []), loan),
  )
  let bad_loan = @admission.VConstructed("Loan", [
    @admission.VRecord([
      ("borrower", @admission.VString("Ada")),
      ("amount", @admission.int_value("-1")),
      ("tags", @admission.VList([])),
    ]),
  ])
  expect_invalid(
    @admission.admit(fixture_env(), @admission.TReference("Loan", []), bad_loan),
    "contracts.refinement_failed",
  )
}

///|
test "integer digit limits use the pinned budget and allow exactly the limit" {
  let digits256 = "1" + "0".repeat(255)
  expect_valid(
    @admission.admit(
      fixture_env(),
      @admission.TInt,
      @admission.int_value(digits256),
    ),
  )
  let digits257 = "1" + "0".repeat(256)
  let outcome = @admission.admit(
    fixture_env(),
    @admission.TInt,
    @admission.int_value(digits257),
  )
  assert_true(outcome is Exhausted(IntDigitLimit))
  let small : @admission.Limits = {
    max_depth: 64,
    max_value_nodes: 10000,
    max_int_digits: 3,
  }
  expect_valid(
    @admission.admit(
      fixture_env(),
      @admission.TInt,
      @admission.int_value("-123"),
      limits=small,
    ),
  )
  assert_true(
    @admission.admit(
      fixture_env(),
      @admission.TInt,
      @admission.int_value("1234"),
      limits=small,
    )
    is Exhausted(IntDigitLimit),
  )
}

///|
test "profile default limits bound depth and value nodes at their exact edges" {
  let mut deep_value = @admission.VBool(true)
  let mut deep_ty = @admission.TBool
  for _ in 0..<63 {
    deep_value = @admission.VList([deep_value])
    deep_ty = @admission.TList(deep_ty)
  }
  // The boolean sits at depth 64: exactly the default maxDepth.
  expect_valid(@admission.admit(fixture_env(), deep_ty, deep_value))
  let too_deep_value = @admission.VList([deep_value])
  let too_deep_ty = @admission.TList(deep_ty)
  assert_true(
    @admission.admit(fixture_env(), too_deep_ty, too_deep_value)
    is Exhausted(DepthLimit),
  )
  // 9,999 elements plus the list itself visit exactly 10,000 value nodes.
  let at_limit : Array[@admission.Value] = []
  for _ in 0..<9999 {
    at_limit.push(@admission.VBool(true))
  }
  expect_valid(
    @admission.admit(
      fixture_env(),
      @admission.TList(@admission.TBool),
      @admission.VList(at_limit),
    ),
  )
  let over_limit : Array[@admission.Value] = []
  for _ in 0..<10000 {
    over_limit.push(@admission.VBool(true))
  }
  assert_true(
    @admission.admit(
      fixture_env(),
      @admission.TList(@admission.TBool),
      @admission.VList(over_limit),
    )
    is Exhausted(NodeLimit),
  )
}

///|
test "generic aliases nest without tripping cycle detection" {
  let nested = @admission.TReference("Box", [
    @admission.TReference("Box", [@admission.TInt]),
  ])
  expect_valid(
    @admission.admit(
      fixture_env(),
      nested,
      @admission.VRecord([
        ("item", @admission.VRecord([("item", @admission.int_value("1"))])),
      ]),
    ),
  )
}

///|
test "set equality ignores element order at every nesting level" {
  let set_of_sets = @admission.TSet(@admission.TSet(@admission.TInt))
  expect_invalid(
    @admission.admit(
      fixture_env(),
      set_of_sets,
      @admission.VSet([
        @admission.VSet([@admission.int_value("1"), @admission.int_value("2")]),
        @admission.VSet([@admission.int_value("2"), @admission.int_value("1")]),
      ]),
    ),
    "contracts.invalid_value",
  )
  let dict_ty = @admission.TDict(
    @admission.TSet(@admission.TInt),
    @admission.TString,
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      dict_ty,
      @admission.VDict([
        (
          @admission.VSet([@admission.int_value("1"), @admission.int_value("2")]),
          @admission.VString("a"),
        ),
        (
          @admission.VSet([@admission.int_value("2"), @admission.int_value("1")]),
          @admission.VString("b"),
        ),
      ]),
    ),
    "contracts.invalid_value",
  )
}

///|
test "nested union ambiguity is preserved by the enclosing union" {
  let nested_union = @admission.TUnion([
    @admission.TUnion([
      @admission.TInt,
      @admission.TReference("PositiveAmount", []),
    ]),
    @admission.TInt,
  ])
  expect_invalid(
    @admission.admit(fixture_env(), nested_union, @admission.int_value("5")),
    "contracts.ambiguous_value",
  )
}

///|
test "unsupported members are reported even when no payload is visited" {
  expect_unsupported(
    @admission.admit(
      fixture_env(),
      @admission.TList(@admission.TFunction([], @admission.TInt)),
      @admission.VList([]),
    ),
    "contracts.unsupported_type",
  )
  expect_unsupported(
    @admission.admit(
      fixture_env(),
      @admission.TReference("Maybe", [@admission.TFunction([], @admission.TInt)]),
      @admission.VConstructed("None", []),
    ),
    "contracts.unsupported_type",
  )
}

///|
test "generic substitution is charged to the node budget" {
  let phantom_env = @admission.TypeEnvironment::new(
    profile=@admission.supported_profile,
    declarations=[("Phantom", @admission.Custom(["a"], [("Make", [])]))],
  )
  let mut arg = @admission.TInt
  for _ in 0..<200 {
    arg = @admission.TTuple([arg, arg])
  }
  let tiny : @admission.Limits = {
    max_depth: 64,
    max_value_nodes: 50,
    max_int_digits: 256,
  }
  let outcome = @admission.admit(
    phantom_env,
    @admission.TReference("Phantom", [arg]),
    @admission.VConstructed("Make", []),
    limits=tiny,
  )
  assert_true(outcome is Exhausted(NodeLimit))
}

///|
test "identity aliases nest by instantiation, not by name" {
  let nested = @admission.TReference("Id", [
    @admission.TReference("Id", [@admission.TInt]),
  ])
  expect_valid(
    @admission.admit(fixture_env(), nested, @admission.int_value("1")),
  )
}

///|
test "transparent aliases consume no value depth or value nodes" {
  let values : Array[@admission.Value] = []
  for i in 0..<5000 {
    values.push(@admission.int_value(i.to_string()))
  }
  expect_valid(
    @admission.admit(
      fixture_env(),
      @admission.TList(@admission.TReference("Number", [])),
      @admission.VList(values),
    ),
  )
  let flat : @admission.Limits = {
    max_depth: 1,
    max_value_nodes: 10000,
    max_int_digits: 256,
  }
  expect_valid(
    @admission.admit(
      fixture_env(),
      @admission.TReference("Number", []),
      @admission.int_value("42"),
      limits=flat,
    ),
  )
}

///|
test "union branches fail whole before their inner ambiguity counts" {
  let branchy = @admission.TUnion([
    @admission.TRecord([
      (
        "x",
        @admission.TUnion([
          @admission.TInt,
          @admission.TReference("PositiveAmount", []),
        ]),
      ),
      ("tag", @admission.TBool),
    ]),
    @admission.TRecord([("x", @admission.TInt), ("tag", @admission.TString)]),
  ])
  expect_valid(
    @admission.admit(
      fixture_env(),
      branchy,
      @admission.VRecord([
        ("x", @admission.int_value("5")),
        ("tag", @admission.VString("text")),
      ]),
    ),
  )
  expect_valid(
    @admission.admit(
      fixture_env(),
      branchy,
      @admission.VRecord([
        ("tag", @admission.VString("text")),
        ("x", @admission.int_value("5")),
      ]),
    ),
  )
  // When the first branch is otherwise viable, its ambiguity still counts.
  expect_invalid(
    @admission.admit(
      fixture_env(),
      branchy,
      @admission.VRecord([
        ("x", @admission.int_value("5")),
        ("tag", @admission.VBool(true)),
      ]),
    ),
    "contracts.ambiguous_value",
  )
}

///|
test "deeply nested types report exhaustion instead of overflowing" {
  let mut deep_ty = @admission.TInt
  for _ in 0..<2000 {
    deep_ty = @admission.TList(deep_ty)
  }
  let outcome = @admission.admit(fixture_env(), deep_ty, @admission.VList([]))
  assert_true(outcome is Exhausted(_))
  let grown = @admission.admit(
    fixture_env(),
    @admission.TReference("Grow", [@admission.TInt]),
    @admission.int_value("1"),
  )
  assert_true(grown is Exhausted(_))
}

///|
fn branch_env() -> @admission.TypeEnvironment {
  @admission.TypeEnvironment::new(profile=@admission.supported_profile, declarations=[
    (
      "PositiveAmount",
      @admission.Transparent([], @admission.TInt, Some(@admission.PositiveInt)),
    ),
    ("Seq", @admission.Opaque([], @admission.TReference("Cons", []), None)),
    (
      "Cons",
      @admission.Custom([], [
        ("Nil", []),
        ("Cons", [@admission.TInt, @admission.TReference("Seq", [])]),
      ]),
    ),
  ])
}

///|
fn outcome_kind(o : @admission.Outcome) -> String {
  match o {
    Valid => "valid"
    Invalid(ds) => "invalid:" + ds[0].code
    Unsupported(d) => "unsupported:" + d.code
    Exhausted(_) => "exhausted"
  }
}

///|
test "recursive opaque types keep their valid branch" {
  let value = @admission.VOpaque(
    "Seq",
    @admission.VConstructed("Cons", [
      @admission.int_value("1"),
      @admission.VOpaque("Seq", @admission.VConstructed("Nil", [])),
    ]),
  )
  assert_eq(
    outcome_kind(
      @admission.admit(branch_env(), @admission.TReference("Seq", []), value),
    ),
    "valid",
  )
}

///|
test "a refinement-rejected record branch does not block a union" {
  let ty = @admission.TUnion([
    @admission.TRecord([
      ("x", @admission.TReference("PositiveAmount", [])),
      ("tag", @admission.TBool),
    ]),
    @admission.TRecord([("x", @admission.TInt), ("tag", @admission.TString)]),
  ])
  let value = @admission.VRecord([
    ("x", @admission.int_value("-5")),
    ("tag", @admission.VString("t")),
  ])
  assert_eq(outcome_kind(@admission.admit(branch_env(), ty, value)), "valid")
}

///|
test "nested refined unions count only viable matches" {
  let ty = @admission.TUnion([
    @admission.TUnion([
      @admission.TReference("PositiveAmount", []),
      @admission.TInt,
    ]),
    @admission.TString,
  ])
  assert_eq(
    outcome_kind(@admission.admit(branch_env(), ty, @admission.int_value("-5"))),
    "valid",
  )
  assert_eq(
    outcome_kind(@admission.admit(branch_env(), ty, @admission.int_value("5"))),
    "invalid:contracts.ambiguous_value",
  )
}

///|
test "a refined alias rejected on refinement contributes no ambiguity" {
  let env = @admission.TypeEnvironment::new(
    profile=@admission.supported_profile,
    declarations=[
      (
        "PositiveAmount",
        @admission.Transparent(
          [],
          @admission.TInt,
          Some(@admission.PositiveInt),
        ),
      ),
      (
        "R",
        @admission.Transparent(
          [],
          @admission.TRecord([
            (
              "x",
              @admission.TUnion([
                @admission.TInt,
                @admission.TReference("PositiveAmount", []),
              ]),
            ),
          ]),
          Some(@admission.NonEmptyString),
        ),
      ),
    ],
  )
  let ty = @admission.TUnion([
    @admission.TReference("R", []),
    @admission.TRecord([("x", @admission.TInt)]),
  ])
  let value = @admission.VRecord([("x", @admission.int_value("5"))])
  // R's refinement rejects every record value, so only the second
  // union member can admit this value.
  assert_eq(outcome_kind(@admission.admit(env, ty, value)), "valid")
}

///|
test "directly recursive opaque types admit nested wrappers" {
  let env = @admission.TypeEnvironment::new(
    profile=@admission.supported_profile,
    declarations=[
      (
        "Wrap",
        @admission.Opaque(
          [],
          @admission.TUnion([@admission.TReference("Wrap", []), @admission.TInt]),
          None,
        ),
      ),
    ],
  )
  let value = @admission.VOpaque(
    "Wrap",
    @admission.VOpaque("Wrap", @admission.int_value("7")),
  )
  assert_eq(
    outcome_kind(
      @admission.admit(env, @admission.TReference("Wrap", []), value),
    ),
    "valid",
  )
}

///|
test "deeply nested alias instantiations report exhaustion on every target" {
  let mut ty = @admission.TInt
  for _ in 0..<2000 {
    ty = @admission.TReference("Id", [ty])
  }
  let outcome = @admission.admit(fixture_env(), ty, @admission.int_value("1"))
  assert_true(outcome is Exhausted(_))
}

///|
test "alias through a recursive opaque admits nested wrappers" {
  let env = @admission.TypeEnvironment::new(
    profile=@admission.supported_profile,
    declarations=[
      (
        "Alias",
        @admission.Transparent([], @admission.TReference("Wrap", []), None),
      ),
      (
        "Wrap",
        @admission.Opaque(
          [],
          @admission.TUnion([
            @admission.TReference("Alias", []),
            @admission.TInt,
          ]),
          None,
        ),
      ),
    ],
  )
  let value = @admission.VOpaque(
    "Wrap",
    @admission.VOpaque("Wrap", @admission.int_value("7")),
  )
  expect_valid(@admission.admit(env, @admission.TReference("Alias", []), value))
  // 43 wrappers stay within the default depth budget.
  let mut deep = @admission.int_value("7")
  for _ in 0..<43 {
    deep = @admission.VOpaque("Wrap", deep)
  }
  expect_valid(@admission.admit(env, @admission.TReference("Alias", []), deep))
}

///|
test "declaration identity is structural, not a rendered string" {
  let env = @admission.TypeEnvironment::new(
    profile=@admission.supported_profile,
    declarations=[
      (
        "A",
        @admission.Transparent(
          ["a"],
          @admission.TList(
            @admission.TReference("A<ref:B", [@admission.TReference("C", [])]),
          ),
          None,
        ),
      ),
      (
        "A<ref:B",
        @admission.Transparent(
          ["a"],
          @admission.TFunction([], @admission.TInt),
          None,
        ),
      ),
      ("C", @admission.Transparent([], @admission.TBool, None)),
      ("B<ref:C", @admission.Transparent([], @admission.TBool, None)),
    ],
  )
  expect_unsupported(
    @admission.admit(
      env,
      @admission.TReference("A", [@admission.TReference("B<ref:C", [])]),
      @admission.VList([]),
    ),
    "contracts.unsupported_type",
  )
}

///|
test "diagnostic paths escape field names per RFC 6901" {
  let outcome = @admission.admit(
    fixture_env(),
    @admission.TRecord([("a/b~c", @admission.TInt)]),
    @admission.VRecord([("a/b~c", @admission.VBool(true))]),
  )
  match outcome {
    Invalid(diagnostics) => assert_eq(diagnostics[0].path, "/a~1b~0c")
    _ => fail("expected Invalid for the escaped-path field")
  }
}

///|
test "the root pointer is empty and empty field names stay distinct" {
  let outcome = @admission.admit(
    fixture_env(),
    @admission.TRecord([("", @admission.TRecord([("x", @admission.TInt)]))]),
    @admission.VRecord([
      ("", @admission.VRecord([("x", @admission.VBool(true))])),
    ]),
  )
  match outcome {
    Invalid(diagnostics) => assert_eq(diagnostics[0].path, "//x")
    _ => fail("expected Invalid for the nested empty-name field")
  }
  let root = @admission.admit(
    fixture_env(),
    @admission.TInt,
    @admission.VBool(true),
  )
  match root {
    Invalid(diagnostics) => assert_eq(diagnostics[0].path, "")
    _ => fail("expected Invalid at the root")
  }
}

///|
test "long alias chains across recursive values exhaust instead of overflowing" {
  let declarations : Array[(String, @admission.TypeDecl)] = []
  for i in 0..<100 {
    let next = if i == 99 {
      @admission.TUnion([
        @admission.TInt,
        @admission.TList(@admission.TReference("A0", [])),
      ])
    } else {
      @admission.TReference("A" + (i + 1).to_string(), [])
    }
    declarations.push(
      ("A" + i.to_string(), @admission.Transparent([], next, None)),
    )
  }
  let env = @admission.TypeEnvironment::new(
    profile=@admission.supported_profile,
    declarations~,
  )
  let mut value = @admission.int_value("1")
  for _ in 0..<5 {
    value = @admission.VList([value])
  }
  let outcome = @admission.admit(env, @admission.TReference("A0", []), value)
  assert_true(outcome is Exhausted(_))
}

///|
test "duplicate declaration members are rejected during inventory" {
  let dup_ctor = @admission.TypeEnvironment::new(
    profile=@admission.supported_profile,
    declarations=[
      (
        "Choice",
        @admission.Custom([], [
          ("C", [@admission.TInt]),
          ("C", [@admission.TString]),
        ]),
      ),
    ],
  )
  expect_invalid(
    @admission.admit(
      dup_ctor,
      @admission.TReference("Choice", []),
      @admission.VConstructed("C", [@admission.int_value("1")]),
    ),
    "contracts.invalid_value",
  )
  let dup_param = @admission.TypeEnvironment::new(
    profile=@admission.supported_profile,
    declarations=[
      (
        "Pair",
        @admission.Transparent(["a", "a"], @admission.TVariable("a"), None),
      ),
    ],
  )
  expect_invalid(
    @admission.admit(
      dup_param,
      @admission.TReference("Pair", [@admission.TInt, @admission.TString]),
      @admission.VString("x"),
    ),
    "contracts.invalid_value",
  )
}

///|
test "unguarded alias cycles are rejected wherever they appear" {
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TList(@admission.TReference("Loop", [])),
      @admission.VList([]),
    ),
    "contracts.alias_cycle",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TUnion([@admission.TReference("Loop", []), @admission.TInt]),
      @admission.int_value("1"),
    ),
    "contracts.alias_cycle",
  )
}

///|
test "recursive generic aliases behind constructors are guarded" {
  let env = @admission.TypeEnvironment::new(
    profile=@admission.supported_profile,
    declarations=[
      (
        "Maybe",
        @admission.Custom(["a"], [
          ("None", []),
          ("Some", [@admission.TVariable("a")]),
        ]),
      ),
      (
        "A",
        @admission.Transparent(
          [],
          @admission.TReference("Maybe", [@admission.TReference("A", [])]),
          None,
        ),
      ),
    ],
  )
  expect_valid(
    @admission.admit(
      env,
      @admission.TReference("A", []),
      @admission.VConstructed("None", []),
    ),
  )
  expect_valid(
    @admission.admit(
      env,
      @admission.TReference("A", []),
      @admission.VConstructed("Some", [@admission.VConstructed("None", [])]),
    ),
  )
}

///|
test "transparent generic collections guard recursive arguments" {
  let env = @admission.TypeEnvironment::new(
    profile=@admission.supported_profile,
    declarations=[
      (
        "Seq",
        @admission.Transparent(
          ["a"],
          @admission.TList(@admission.TVariable("a")),
          None,
        ),
      ),
      (
        "A",
        @admission.Transparent(
          [],
          @admission.TReference("Seq", [@admission.TReference("A", [])]),
          None,
        ),
      ),
    ],
  )
  expect_valid(
    @admission.admit(env, @admission.TReference("A", []), @admission.VList([])),
  )
  expect_valid(
    @admission.admit(
      env,
      @admission.TReference("A", []),
      @admission.VList([@admission.VList([])]),
    ),
  )
  expect_invalid(
    @admission.admit(
      env,
      @admission.TReference("A", []),
      @admission.VList([@admission.VBool(true)]),
    ),
    "contracts.invalid_value",
  )
}

///|
test "transparent generic identity does not guard recursive arguments" {
  let env = @admission.TypeEnvironment::new(
    profile=@admission.supported_profile,
    declarations=[
      ("Id", @admission.Transparent(["a"], @admission.TVariable("a"), None)),
      (
        "A",
        @admission.Transparent(
          [],
          @admission.TReference("Id", [@admission.TReference("A", [])]),
          None,
        ),
      ),
    ],
  )
  expect_invalid(
    @admission.admit(
      env,
      @admission.TReference("A", []),
      @admission.VBool(true),
    ),
    "contracts.alias_cycle",
  )
}

///|
test "unused generic arguments still reject self-contained alias cycles" {
  let env = @admission.TypeEnvironment::new(
    profile=@admission.supported_profile,
    declarations=[
      ("Phantom", @admission.Custom(["a"], [("Make", [])])),
      (
        "Loop",
        @admission.Transparent([], @admission.TReference("Loop", []), None),
      ),
    ],
  )
  expect_invalid(
    @admission.admit(
      env,
      @admission.TReference("Phantom", [@admission.TReference("Loop", [])]),
      @admission.VConstructed("Make", []),
    ),
    "contracts.alias_cycle",
  )
}

///|
test "duplicate declared record fields fail even without a visited payload" {
  let duplicate = @admission.TRecord([
    ("x", @admission.TInt),
    ("x", @admission.TString),
  ])
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TList(duplicate),
      @admission.VList([]),
    ),
    "contracts.invalid_value",
  )
  let env = @admission.TypeEnvironment::new(
    profile=@admission.supported_profile,
    declarations=[
      ("Choice", @admission.Custom([], [("None", []), ("Some", [duplicate])])),
    ],
  )
  expect_invalid(
    @admission.admit(
      env,
      @admission.TReference("Choice", []),
      @admission.VConstructed("None", []),
    ),
    "contracts.invalid_value",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TUnion([@admission.TBool, duplicate]),
      @admission.VBool(true),
    ),
    "contracts.invalid_value",
  )
}
