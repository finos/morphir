///|
test "Union inspection lists every member and refuses an unqualified input editor" {
  let t : @ir.Type = Union(Default::default(), [
    Reference(
      Default::default(),
      @ir.FQName::parse("morphir/SDK:string#string"),
      [],
    ),
    Reference(Default::default(), @ir.FQName::parse("morphir/SDK:basics#int"), []),
  ])
  assert_true(type_label(t).contains(" | "))
  try input_schema(t, Map([]), Map([]), 0) catch {
    @scheme.Unsupported(_) => ()
    _ => fail("wrong input editor error")
  } noraise {
    _ => fail("Union became an input selection")
  }
}
