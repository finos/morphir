///|
// Oracle: elm/core 1.0.5 Elm/Kernel/Basics.js; source pin in SDK design.
test "Elm numeric and angle semantics" {
  assert_eq(@integer.to_string(round(-1.5)), "-1")
  assert_eq(@integer.to_string(round(1.5)), "2")
  assert_eq(@integer.to_string(floor(-1.5)), "-2")
  assert_eq(@integer.to_string(ceiling(-1.5)), "-1")
  assert_eq(@integer.to_string(truncate(-1.5)), "-1")
  assert_eq(
    @integer.to_string(
      integer_divide(@integer.from_int(-7), @integer.from_int(3)),
    ),
    "-2",
  )
  assert_eq(
    @integer.to_string(mod_by(@integer.from_int(3), @integer.from_int(-7))),
    "2",
  )
  assert_eq(
    @integer.to_string(
      remainder_by(@integer.from_int(3), @integer.from_int(-7)),
    ),
    "-1",
  )
  assert_true(is_nan(divide(0.0, 0.0)))
  assert_true(is_infinite(divide(1.0, 0.0)))
  assert_true(abs_float(degrees(180.0) - pi()) < 0.000000000001)
  let (radius, angle) = to_polar((0.0, 1.0))
  assert_true(abs_float(radius - 1.0) < 0.000000000001)
  assert_true(abs_float(angle - pi() / 2.0) < 0.000000000001)
}

///|
test "checked conversion and callback order" {
  let bad = try {
    ignore(round(1.0 / 0.0))
    false
  } catch {
    @sdk.InvalidNumber(_) => true
    _ => false
  }
  assert_true(bad)
  assert_eq(compose_left((n : Int32) => n * 2, (n : Int32) => n + 1, 3), 8)
  assert_eq(compose_right((n : Int32) => n + 1, (n : Int32) => n * 2, 3), 8)
  assert_eq(always(5, "ignored"), 5)
  assert_eq(compare(2, 3), @sdk.LT)
  let ab = @sdk.Text::from_string("ab")
  let b = @sdk.Text::from_string("b")
  assert_eq(compare_string(ab, b), @sdk.LT)
  assert_eq(max_string(ab, b), b)
  assert_eq(append_string(@sdk.Text::from_string("a"), b), ab)
  assert_eq(
    @list.to_array(append_list(@list.from_array([1]), @list.from_array([2]))),
    [1, 2],
  )
  let invalid_compare = try {
    ignore(compare_float(0.0 / 0.0, 1.0))
    false
  } catch {
    @sdk.InvalidComparison(_) => true
    _ => false
  }
  assert_true(invalid_compare)
}
