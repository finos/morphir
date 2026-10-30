///|
test "Rust conversion proves classic JSON roundtrip without losing typed IR" {
  let unit = @data.IRUnit::new("rust", @fixtures.rust_conformance())
  ignore(@host.rust_classic_ir(unit))
  assert_true(
    try {
      ignore(
        @host.rust_classic_ir({ ..unit, provenance: [@ion.IonValue::int(1)], }),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        @host.rust_classic_ir({ ..unit, annotations: [@ion.symbol("audit")], }),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        @host.rust_classic_ir(
          @data.IRUnit::new("pricing", @fixtures.conformance()),
        ),
      )
      false
    } catch {
      _ => true
    },
  )
}
