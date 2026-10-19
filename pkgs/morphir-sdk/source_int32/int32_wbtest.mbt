///|
test "source Int32 normalization wraps exact arithmetic at signed boundaries" {
  for
    (source, expected) in [
      ("42", "42"),
      ("2147483647", "2147483647"),
      ("2147483648", "-2147483648"),
      ("4294967296", "0"),
      ("-2147483649", "2147483647"),
      ("-4294967296", "0"),
    ] {
    assert_eq(
      @integer.to_string(@int.from_int32(normalize(@integer.parse(source)))),
      expected,
    )
  }
}
