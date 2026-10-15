// White-box tests of the placeholder rules of `compare_types`. They came from the typing oracle
// (`pkgs/morphir-typing-tools/oracle`), with the comparison.

///|
/// Whether `want` and `have` are the same type outside the placeholders of `want`.
fn same_outside_placeholders(want : @ir.Type, have : @ir.Type) -> Bool {
  let (a, b) = mask_placeholders(want, have)
  types_equivalent(a, b)
}

///|
test "placeholders: only t-<digits> names are morphir-elm placeholders" {
  assert_true(is_placeholder(@ir.Name::from_words(["t", "8"])))
  assert_true(is_placeholder(@ir.Name::from_words(["t", "12"])))
  assert_false(is_placeholder(@ir.Name::from_words(["t"])))
  assert_false(is_placeholder(@ir.Name::from_words(["t", "a"])))
  assert_false(is_placeholder(@ir.Name::from_words(["comparable"])))
}

///|
test "a signature type is compared outside its placeholders" {
  let int = tr("morphir/SDK:basics#int", [])
  let float = t_float()
  let string = tr("morphir/SDK:string#string", [])
  let list = (t : @ir.Type) => tr("morphir/SDK:list#list", [t])
  let maybe = (t : @ir.Type) => tr("morphir/SDK:maybe#maybe", [t])
  let t8 = tv("t-8")
  assert_true(same_outside_placeholders(t8, int))
  assert_true(same_outside_placeholders(list(t8), list(int)))
  assert_false(same_outside_placeholders(maybe(t8), list(int)))
  assert_true(same_outside_placeholders(tfn(t8, int), tfn(string, int)))
  assert_false(same_outside_placeholders(tfn(t8, int), tfn(string, float)))
  // A placeholder row compares only the fields that the signature lists.
  let name_field = (nm("name"), string)
  let age_field = (nm("age"), int)
  let open_ : @ir.Type = ExtensibleRecord(
    tattrs(),
    nm("t-9"),
    Map::from_array([name_field]),
  )
  let have : @ir.Type = Record(
    tattrs(),
    Map::from_array([name_field, age_field]),
  )
  assert_true(same_outside_placeholders(open_, have))
  assert_false(
    same_outside_placeholders(
      open_,
      Record(tattrs(), Map::from_array([age_field])),
    ),
  )
}

///|
test "mask_signatures frees the placeholders of a top-level signature only" {
  let def : @ir.ValueDefinition = ExpressionBody(
    [(nm("a"), tv("t-0")), (nm("b"), tv("a"))],
    ExtensibleRecord(tattrs(), nm("t-1"), Map([])),
    Unit(va()),
  )
  guard mark_placeholders(def)
    is ExpressionBody(
      [(_, Variable(first, _)), (_, Variable(second, _))],
      ExtensibleRecord(row, _, _),
      _
    ) else {
    fail("shape")
  }
  assert_true(is_unknown(first))
  assert_false(is_unknown(second))
  assert_true(is_unknown(row))
}
