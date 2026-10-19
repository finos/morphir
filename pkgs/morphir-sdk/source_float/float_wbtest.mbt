///|
test "binary32 rounds at each source arithmetic boundary" {
  assert_eq(round32(16777217.0), 16777216.0)
  assert_eq(round32(16777218.0), 16777218.0)
  assert_eq(add32(add32(16777216.0, 1.0), 1.0), 16777216.0)
  assert_eq(add32(16777216.0, 2.0), 16777218.0)
}

///|
test "binary32 decimal midpoint follows the pinned source literal parser" {
  let original : Float = 1.000000059604644775390626F
  assert_eq(round32(1.000000059604644775390626), original.to_double())
}

///|
test "binary32 keeps signed zero subnormals and nonfinite outcomes observable" {
  assert_eq(round32(-0.0).reinterpret_as_uint64(), 9223372036854775808UL)
  assert_eq(round32(1.401298464324817e-45), 1.401298464324817e-45)
  assert_true(divide32(1.0, 0.0).is_inf())
  assert_true(divide32(0.0, 0.0).is_nan())
}

///|
test "checked exact float to integer rejects fraction and nonfinite values" {
  assert_eq(from_float64_exact(1.5), None)
  assert_eq(from_float64_exact(1.0 / 0.0), None)
  assert_eq(from_float64_exact(0.0 / 0.0), None)
  assert_eq(
    from_float64_exact(9007199254740992.0),
    Some(@integer.parse("9007199254740992")),
  )
  assert_eq(from_float64_truncated(-1.75), Some(@integer.from_int(-1)))
}
