///|
test "numeric extension separates exact float conversion from rounding" {
  assert_eq(from_float64_exact(1.5), None)
  assert_eq(from_float64_exact(1.0 / 0.0), None)
  assert_eq(
    from_float64_exact(9007199254740992.0),
    Some(@integer.parse("9007199254740992")),
  )
  assert_eq(from_float64_truncated(-1.75), Some(@integer.from_int(-1)))
  assert_eq(from_float64_floor(-1.75), Some(@integer.from_int(-2)))
  assert_eq(from_float64_ceiling(-1.75), Some(@integer.from_int(-1)))
  assert_eq(from_float32_exact(1.5), None)
  assert_eq(from_float32_truncated(-1.75), Some(@integer.from_int(-1)))
  assert_eq(from_float32_floor(-1.75), Some(@integer.from_int(-2)))
  assert_eq(from_float32_ceiling(-1.75), Some(@integer.from_int(-1)))
  assert_eq(from_float32_rounded(-1.75), Some(@integer.from_int(-2)))
  assert_eq(from_float32_exact(1.0 / 0.0), None)
  assert_eq(from_float32_exact(-0.0), Some(@integer.from_int(0)))
  assert_eq(from_float32_exact(1.401298464324817e-45), None)
  assert_eq(to_int32(from_float32_exact(2147483648.0).unwrap()), None)
  assert_eq(to_int32(from_float64_exact(2147483648.0).unwrap()), None)
  assert_eq(to_float64_exact(@integer.parse("9007199254740993")), None)
  assert_eq(
    to_float64_exact(@integer.parse("9007199254740992")),
    Some(9007199254740992.0),
  )
  assert_eq(
    to_float64_rounded(@integer.parse("9007199254740993")),
    9007199254740992.0,
  )
  assert_eq(to_float32_exact(@integer.from_int(16777217)), None)
  assert_eq(to_float32_exact(@integer.from_int(16777216)), Some(16777216.0))
  assert_eq(to_float32_rounded(@integer.from_int(16777217)), 16777216.0)
  assert_eq(
    to_float32_rounded(@integer.parse("18014399583223809")),
    18014400656965632.0,
  )
}
