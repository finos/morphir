///|
test "source widths wrap separately from checked SDK narrowing" {
  assert_eq(
    @int.from_uint64(normalize_uint64(@integer.parse("18446744073709551616"))),
    @integer.from_int(0),
  )
  assert_eq(
    @int.from_int64(normalize_int64(@integer.parse("9223372036854775808"))),
    @integer.parse("-9223372036854775808"),
  )
  assert_eq(
    @int.from_byte(normalize_byte(@integer.from_int(-1))),
    @integer.from_int(255),
  )
  assert_eq(@int.to_uint64(@integer.from_int(-1)), None)
}

///|
test "source integer arithmetic refuses results beyond the decimal digit budget" {
  let largest = @integer.parse(String::make(4096, '9'))
  assert_eq(
    add(@integer.from_int(1), @integer.from_int(2)),
    @integer.from_int(3),
  )
  try {
    ignore(multiply(largest, @integer.from_int(10)))
    fail("Expected integer result budget refusal")
  } catch {
    @sdk.OutOfRange(message) => assert_true(message.contains("digit budget"))
    error => raise error
  }
}
