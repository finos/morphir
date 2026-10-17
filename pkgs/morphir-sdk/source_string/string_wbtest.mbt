///|
test "source String extension accepts scalar text without normalization" {
  for value in ["", "😀", "é", "e\u{301}", "a\u0000b"] {
    let text = @sdk.Text::from_string(value)
    assert_eq(require_valid(text, MAX_CODE_UNITS), text)
  }
  assert_eq(
    append_bounded(
      @sdk.Text::from_string("a"),
      @sdk.Text::from_string("😀"),
      3,
    ).to_string(),
    "a😀",
  )
  assert_eq(require_valid(@sdk.Text::from_string(""), 0).length(), 0)
}

///|
test "source String extension rejects isolated halves, size growth and invalid limits" {
  for units in [[55296], [56320], [55296, 97], [97, 56320], [56320, 55296]] {
    try {
      ignore(
        require_valid(@sdk.Text::from_units(units.map(n => n.to_uint16())), 10),
      )
      fail("Expected malformed UTF-16 refusal")
    } catch {
      @sdk.UnrepresentableText(_) => ()
      error => raise error
    }
  }
  for limit in [-1, 0, 2, 1048577] {
    try {
      ignore(
        append_bounded(
          @sdk.Text::from_string("a"),
          @sdk.Text::from_string("😀"),
          limit,
        ),
      )
      fail("Expected bound refusal")
    } catch {
      @sdk.OutOfRange(_) => ()
      error => raise error
    }
  }
  let exact = @sdk.Text::from_units(
    Array::make(MAX_CODE_UNITS, (97).to_uint16()),
  )
  assert_eq(require_valid(exact, MAX_CODE_UNITS).length(), MAX_CODE_UNITS)
  try {
    ignore(append_bounded(exact, @sdk.Text::from_string("a"), MAX_CODE_UNITS))
    fail("Expected growth refusal")
  } catch {
    @sdk.OutOfRange(_) => ()
    error => raise error
  }
}
