///|
test "checked construction retains exact coefficients and normalizes zero" {
  for
    (text, coefficient, exponent) in [
      ("12.3400", "1234", -2),
      ("0.00000000000000000000000000000001", "1", -32),
      ("0.000000000000000000000000000000010", "1", -32),
      ("-0.000000000000000000000000000000000", "0", 0),
      ("9007199254740993.00", "9007199254740993", 0),
      ("1.25e2", "125", 0),
    ] {
    let value = from_string_exact(text)
    assert_eq(value.coefficient.to_string(), coefficient)
    assert_eq(value.exponent, exponent)
  }
  try {
    ignore(from_string_exact("0.000000000000000000000000000000001"))
    fail("Expected precision refusal")
  } catch {
    PrecisionLoss => ()
    error => raise error
  }
  for text in ["NaN", "1e999999999", "1e-33", "1_0", ""] {
    try {
      ignore(from_string_exact(text))
      fail("Expected invalid literal")
    } catch {
      InvalidLiteral => ()
      error => raise error
    }
  }
}

///|
test "checked division distinguishes zero divisor underflow and successful zero" {
  let tiny = from_string_exact("1e-32")
  let two = from_string_exact("2")
  assert_eq(
    to_string(divide(one(), from_string_exact("3"))),
    "0.33333333333333333333333333333333",
  )
  assert_eq(to_string(divide(negate(one()), two)), "-0.5")
  assert_eq(divide(zero(), two), zero())
  try {
    ignore(divide(one(), zero()))
    fail("Expected zero divisor")
  } catch {
    DivisionByZero => ()
    error => raise error
  }
  try {
    ignore(divide(tiny, two))
    fail("Expected underflow")
  } catch {
    Underflow => ()
    error => raise error
  }
  assert_eq(divide_with_default(two, tiny, two), two)
  assert_eq(divide_with_default(two, one(), zero()), two)
  // The classic versioned compatibility contract is still Maybe/fallback.
  assert_eq(div(tiny, two), None)
  assert_eq(div(one(), zero()), None)
  assert_eq(div_with_default(two, one(), zero()), two)
}
