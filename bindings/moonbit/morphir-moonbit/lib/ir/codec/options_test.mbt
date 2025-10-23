///|
test "default morphir json options" {
  let options : MorphirJsonOptions = Default::default()
  assert_eq(options.name_encoding, NameJsonEncoding::AsList)
  assert_eq(options.unit_encoding, UnitJsonEncoding::AsEmptyObject)
}
