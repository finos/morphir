// Black-box tests for `compare_types`. The helpers of `driver_test.mbt` (`nm`, `tv`, `tr`, `library`, …) are shared.

///|
fn int_type() -> @ir.Type {
  t_int()
}

///|
/// A morphir-elm placeholder variable, such as `t-0`, without the unknown marker (classic IR has no marker).
fn placeholder_variable(text : String) -> @ir.Type {
  tv(text)
}

///|
/// A one-module library with one value `v : output = 1`, whose literal has the type `Int`.
fn file_with_output(output : @ir.Type) -> @ir.IRFile {
  file_with_body(output, typed_literal(int_type()))
}

///|
fn typed_literal(t : @ir.Type) -> @ir.Value {
  Literal({ ..va(), inferred_type: Some(t), }, IntegerLiteral("1"))
}

///|
/// A one-module library `acme/app` with one value `m#v`, of no inputs.
fn file_with_body(output : @ir.Type, body : @ir.Value) -> @ir.IRFile {
  library([("m", [("v", ExpressionBody([], output, body))])])
}

///|
test "compare_types masks top-level placeholders only when asked" {
  let expected = file_with_output(placeholder_variable("t-0"))
  let actual = file_with_output(int_type())
  assert_true(@typing.compare_types(expected, actual, Map([])).length() > 0)
  assert_eq(
    @typing.compare_types(expected, actual, Map([]), mask_signatures=true),
    [],
  )
}

///|
test "compare_types writes one line per path, with both types" {
  let expected = file_with_body(int_type(), typed_literal(int_type()))
  let actual = file_with_body(int_type(), typed_literal(t_string()))
  assert_eq(@typing.compare_types(expected, expected, Map([])), [])
  assert_eq(@typing.compare_types(expected, actual, Map([])), [
    "value:acme/app:m#v/body: expected morphir/SDK:basics#int, found morphir/SDK:string#string",
  ])
  // A path on one side only is a difference too.
  let untyped = file_with_body(int_type(), v_int("1"))
  assert_eq(@typing.compare_types(expected, untyped, Map([])), [
    "value:acme/app:m#v/body: expected morphir/SDK:basics#int, found no type",
  ])
  let other = library([
    ("m", [("w", ExpressionBody([], int_type(), typed_literal(int_type())))]),
  ])
  assert_eq(@typing.compare_types(expected, other, Map([])), [
    "value:acme/app:m#v:output: expected morphir/SDK:basics#int, found no path",
    "value:acme/app:m#v/body: expected morphir/SDK:basics#int, found no path", "value:acme/app:m#w:output: expected no path, found morphir/SDK:basics#int",
    "value:acme/app:m#w/body: expected no path, found morphir/SDK:basics#int",
  ])
}

///|
test "compare_types expands the aliases of the dependencies" {
  let count : @ir.Documented[@ir.TypeSpecification] = {
    doc: None,
    value: { annotations: [], body: TypeAliasSpecification([], int_type()), },
  }
  let dependency : @ir.PackageSpecification = {
    modules: Map([(pkg("m"), module_spec([("count", count)], []))]),
  }
  let expected = file_with_output(tr("acme/dep:m#count", []))
  let actual = file_with_output(int_type())
  assert_eq(
    @typing.compare_types(
      expected,
      actual,
      Map([(pkg("acme/dep"), dependency)]),
    ),
    [],
  )
  assert_eq(@typing.compare_types(expected, actual, Map([])).length(), 1)
}

///|
test "compare_types renames the variables of one declaration consistently" {
  // `v : a = (x : a)`: the signature variable `a` is rigid, so a node of type `b` differs.
  let body = (t : @ir.Type) => {
    (Variable({ ..va(), inferred_type: Some(t), }, nm("x")) : @ir.Value)
  }
  let expected = file_with_body(tv("a"), body(tv("a")))
  assert_eq(
    @typing.compare_types(
      expected,
      file_with_body(tv("a"), body(tv("b"))),
      Map([]),
    ).length(),
    1,
  )
  // A morphir-elm placeholder of a top-level signature is free when it is masked: `t-0` pairs with `a`.
  let placeholder = file_with_body(tv("t-0"), body(tv("t-0")))
  let solved = file_with_body(tv("a"), body(tv("a")))
  assert_eq(
    @typing.compare_types(placeholder, solved, Map([]), mask_signatures=true),
    [],
  )
  assert_eq(@typing.compare_types(placeholder, solved, Map([])).length(), 2)
  // Classes count: a `number` variable is not a variable of no class.
  let number = file_with_body(int_type(), body(tclass("t-4", "number")))
  let plain = file_with_body(int_type(), body(tv("t-4")))
  assert_eq(@typing.compare_types(plain, number, Map([])).length(), 1)
}

///|
test "compare_types masks let placeholders without the option" {
  // `v = let k : List t-3 = … in 1`: the let output is compared outside its placeholder.
  let with_let = (output : @ir.Type) => {
    let def : @ir.ValueDefinition = ExpressionBody(
      [],
      output,
      typed_literal(int_type()),
    )
    file_with_body(
      int_type(),
      @ir.Value::LetDefinition(
        { ..va(), inferred_type: Some(int_type()), },
        nm("k"),
        def,
        typed_literal(int_type()),
      ),
    )
  }
  let expected = with_let(t_list(tmarked("t-3")))
  assert_eq(
    @typing.compare_types(expected, with_let(t_list(int_type())), Map([])),
    [],
  )
  assert_eq(
    @typing.compare_types(
      expected,
      with_let(tr("morphir/SDK:maybe#maybe", [int_type()])),
      Map([]),
    ),
    [
      "value:acme/app:m#v/body/definition:output: expected (morphir/SDK:list#list t-3), found (morphir/SDK:maybe#maybe morphir/SDK:basics#int)",
    ],
  )
}
