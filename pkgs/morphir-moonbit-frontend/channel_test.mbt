///|
test "stable is a cumulative typed library and experimental preserves its behavior" {
  let source = input(
    "fn bound(s : String) -> Int32 { s.length() }\npub fn choose(s : String, flag : Bool) -> String { let n : Int = bound(s); if @basics.not_(flag) && n > 0 { s[0:n].to_owned() } else { \"\" } }",
  )
  for channel in [@frontend.Stable, @frontend.Experimental] {
    let output = @frontend.compile_library(source, channel~)
    assert_eq(output.entries.length(), 1)
    let runtime = string_runtime(output)
    let actual = @backend.call_entry(runtime, output.entries[0], [
      @scheme.Value::Text("abc"),
      @scheme.Boolean(false),
    ])
    guard actual is @scheme.Text(text) else { fail("Expected String") }
    assert_eq(text, "abc")
    guard output.provenance[0].kind() is @ion.Struct(fields) else {
      fail("Expected source provenance")
    }
    assert_true(
      fields.any(f => {
        f.name().text() == Some("profile") &&
        f.value().equals(@ion.IonValue::string(channel.profile()))
      }),
    )
  }
}

///|
test "stable rejects unpromoted capabilities in signatures and unused expressions" {
  for
    source in [
      "pub fn wide(v : UInt64) -> UInt64 { v }", "pub fn floating(v : Double) -> Double { v }",
      "pub fn optional(v : Double?) -> Double? { v }", "fn hidden() -> Float { 1.0F }\npub fn ready() -> Bool { true }",
      "pub fn ready() -> Bool { let unused = 1.0; true }", "pub fn ready() -> Bool { let unused = 1UL; true }",
      "pub fn ready() -> Bool { let unused = (1.0 : Double); true }",
    ] {
    try {
      ignore(@frontend.compile_library(input(source)))
      fail("Stable must reject unpromoted capability")
    } catch {
      @frontend.Invalid(d) => {
        assert_eq(d.code, "moonbit_frontend.experimental_capability")
        assert_true(d.detail.contains(@frontend.EXPERIMENTAL_PROFILE))
        assert_true(d.source is Some(_))
      }
      error => raise error
    }
    ignore(
      @frontend.compile_library(input(source), channel=@frontend.Experimental),
    )
  }
}

///|
test "host numeric bindings cannot widen stable channel authority" {
  let bindings = @frontend.PinnedSourceBindings::sdk_decimal(
    "finos/morphir-sdk/decimal",
    "0.1.0",
    @frontend.DECIMAL_SDK_TREE,
    "decimal",
  )
  let source = input("pub fn ready() -> Bool { @basics.sqrt(4.0) > 1.0 }")
  try {
    ignore(@frontend.compile_library(source, bindings=Some(bindings)))
    fail("Bindings must not promote source capabilities")
  } catch {
    @frontend.Invalid(d) =>
      assert_eq(d.code, "moonbit_frontend.experimental_capability")
    error => raise error
  }
  ignore(
    @frontend.compile_library(
      source,
      channel=@frontend.Experimental,
      bindings=Some(bindings),
    ),
  )
}
