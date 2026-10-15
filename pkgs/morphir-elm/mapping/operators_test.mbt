///|
test "the operator table is morphir-elm's mapOperator" {
  let table = [
    ("||", "morphir/SDK:basics#or"),
    ("&&", "morphir/SDK:basics#and"),
    ("==", "morphir/SDK:basics#equal"),
    ("/=", "morphir/SDK:basics#not-equal"),
    ("<", "morphir/SDK:basics#less-than"),
    (">", "morphir/SDK:basics#greater-than"),
    ("<=", "morphir/SDK:basics#less-than-or-equal"),
    (">=", "morphir/SDK:basics#greater-than-or-equal"),
    ("++", "morphir/SDK:basics#append"),
    ("+", "morphir/SDK:basics#add"),
    ("-", "morphir/SDK:basics#subtract"),
    ("*", "morphir/SDK:basics#multiply"),
    ("/", "morphir/SDK:basics#divide"),
    ("//", "morphir/SDK:basics#integer-divide"),
    ("^", "morphir/SDK:basics#power"),
    ("<<", "morphir/SDK:basics#compose-left"),
    (">>", "morphir/SDK:basics#compose-right"),
    ("::", "morphir/SDK:list#cons"),
  ]
  for entry in table {
    assert_eq(
      @mapping.morphir_operator(entry.0).map(fq => fq.to_canonical()),
      Some(entry.1),
    )
  }
  assert_eq(@mapping.morphir_operator("</>"), None)
  assert_eq(@mapping.morphir_operator("|>"), None)
}
