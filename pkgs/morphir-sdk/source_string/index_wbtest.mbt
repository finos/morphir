///|
test "source String indexing counts units and adjusts surrogate splits" {
  let source = @sdk.Text::from_string("A😀é")
  let low = @int.to_int32(@integer.parse("-2147483648")).unwrap()
  let high = @int.to_int32(@integer.parse("2147483647")).unwrap()
  let one = @int.to_int32(@integer.parse("1")).unwrap()
  let two = @int.to_int32(@integer.parse("2")).unwrap()
  let three = @int.to_int32(@integer.parse("3")).unwrap()
  assert_eq(
    @integer.to_string(@int.from_int32(length_int32(source, 1048576))),
    "5",
  )
  assert_eq(slice_owned(source, low, high, 1048576).to_string(), "A😀é")
  assert_eq(slice_owned(source, one, three, 1048576).to_string(), "😀")
  assert_eq(slice_owned(source, two, three, 1048576).to_string(), "")
  assert_eq(slice_owned(source, one, two, 1048576).to_string(), "")
  assert_eq(slice_owned(source, high, low, 1048576).to_string(), "")
  assert_eq(
    slice_owned(@sdk.Text::from_string(""), low, high, 1048576).to_string(),
    "",
  )
}

///|
test "source String indexing rejects malformed UTF-16 and excess length" {
  let zero = @int.to_int32(@integer.parse("0")).unwrap()
  let one = @int.to_int32(@integer.parse("1")).unwrap()
  let broken = @sdk.Text::from_units([(55296).to_uint16()])
  try {
    ignore(length_int32(broken, 1048576))
    fail("Expected malformed UTF-16 rejection")
  } catch {
    @sdk.UnrepresentableText(_) => ()
    error => raise error
  }
  try {
    ignore(slice_owned(broken, zero, one, 1048576))
    fail("Expected malformed UTF-16 rejection")
  } catch {
    @sdk.UnrepresentableText(_) => ()
    error => raise error
  }
  try {
    ignore(length_int32(@sdk.Text::from_string("ab"), 1))
    fail("Expected size rejection")
  } catch {
    @sdk.OutOfRange(_) => ()
    error => raise error
  }
}
