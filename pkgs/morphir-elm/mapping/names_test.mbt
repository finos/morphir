///|
test "elm names split like morphir-elm Name.fromString" {
  assert_eq(@mapping.elm_words("notExposed"), ["not", "exposed"])
  assert_eq(@mapping.elm_words("LocalDate"), ["local", "date"])
  assert_eq(@mapping.elm_words("atan2"), ["atan", "2"])
  assert_eq(@mapping.elm_words("SDK"), ["s", "d", "k"])
  assert_eq(@mapping.elm_words("valueInUSD"), ["value", "in", "u", "s", "d"])
  assert_eq(@mapping.elm_name("notExposed").to_canonical(), "not-exposed")
  assert_eq(@mapping.elm_name("SDK").to_canonical(), "SDK")
  assert_eq(
    @mapping.elm_name("isNaN").to_canonical(),
    @ir.Name::from_words(["is", "na", "n"]).to_canonical(),
  )
  assert_eq(
    @mapping.elm_path(["My", "Pkg"]).to_canonical(),
    @ir.Path::parse("my/pkg").to_canonical(),
  )
}
