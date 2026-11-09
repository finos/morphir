///|
/// A library of `count` public integer literal values in one module.
fn literal_values(count : Int32) -> @ir.IRFile raise {
  let values = StringBuilder()
  for index in 0..<count {
    if index > 0 {
      values.write_char(',')
    }
    values.write_string(
      "\"value\{index}x\":{\"Public\":{\"ExpressionBody\":{\"inputTypes\":{},\"outputType\":\"morphir/SDK:basics#int\",\"body\":{\"Literal\":{\"IntegerLiteral\":42}}}}}",
    )
  }
  @ir_json.from_json(
    @wire.parse(
      "{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"generated\",\"dependencies\":{},\"def\":{\"modules\":{\"main\":{\"Public\":{\"types\":{},\"values\":{\{values.to_string()}}}}}}}}}",
    ),
  )
}

///|
test "name sets: a copy shares the base and copies only its own names" {
  let base = Map::from_array([("global", true)])
  let names = NameSet::over(base)
  names.add("local")
  let copy = names.copy()
  copy.add("later")
  assert_true(copy.contains("global"))
  assert_true(copy.contains("local"))
  assert_true(copy.contains("later"))
  assert_false(names.contains("later"))
  assert_false(base.contains("local"))
  assert_eq(copy.own.length(), 2)
  assert_true(NameSet::of(["Some"]).contains("Some"))
  assert_false(NameSet::of([]).contains("Some"))
}

///|
// Bead morphir-ukvn.5.64.36.29: each declaration copied every global name,
// so generation was quadratic in the number of values.
test "local names: a declaration blocks the global names without a copy of them" {
  let input = Input::new("dense", literal_values(2000))
  let plan = TargetNames::new(
    input,
    Readable,
    @linked_metadata.Capabilities::unavailable(),
    @identities.node_set(input.unit_id, input.ir),
  )
  assert_eq(plan.reserved.length(), 2000)
  guard input.ir.distribution is Library(package_name, _, definition) else {
    fail("not a library")
  }
  let (module_name, access) = definition.modules.iter().collect()[0]
  let (name, value) = access.value.values.iter().collect()[0]
  guard value.value.value is ExpressionBody(_, _, body) else {
    fail("not an expression body")
  }
  let fqname : @ir.FQName = { package_name, module_name, local_name: name, }
  let declaration : Declaration = {
    fqname,
    doc: None,
    module_name,
    public: true,
    exposed: true,
    output: Atom(Integer),
    inputs: [],
    body,
  }
  let locals = LocalNames::new(plan, declaration)
  assert_eq(locals.used.own.length(), 0)
  assert_true(locals.used.contains(plan.names[value_node(fqname)]))
  assert_eq(locals.fresh("tuple"), "tuple_1")
  assert_eq(locals.used.own.length(), 1)
  assert_eq(plan.reserved.length(), 2000)
}
