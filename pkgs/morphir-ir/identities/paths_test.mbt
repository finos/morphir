///|
test "logical path grammar" {
  let fq = @ir.FQName::parse("p:m#f") catch { _ => fail("fqname") }
  let root = @identities.value_root(fq)
  assert_eq(root, "value:p:m#f")
  assert_eq(@identities.path_body(root), "value:p:m#f/body")
  assert_eq(
    @identities.path_argument(@identities.path_body(root)),
    "value:p:m#f/body/argument",
  )
  let x = @ir.Name::parse("x") catch { _ => fail("name") }
  assert_eq(@identities.path_input(root, x), "value:p:m#f/inputs/x")
  assert_eq(@identities.path_output(root), "value:p:m#f/output")
  assert_eq(@identities.path_arg("t", 0), "t/args/0")
  assert_eq(@identities.path_parameter("t"), "t/parameter")
  assert_eq(@identities.path_return("t"), "t/return")
  assert_eq(@identities.path_expected("h"), "h/expected")
  assert_eq(@identities.path_case_body("c", 2), "c/cases/2/body")
  assert_eq(@identities.path_definitions_body("l", x), "l/definitions/x/body")
}
