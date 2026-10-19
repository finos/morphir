///|
test "signed Int32 literal crosses the source and Scheme boundary" {
  let output = @frontend.compile_int32_library(
    input("pub fn answer() -> Int32 { 42 }"),
  )
  let runtime = string_runtime(output)
  guard @backend.call_entry(runtime, output.entries[0], [])
    is Tagged("morphir/SDK:int#int32", [Number(Integer(value))]) else {
    fail("Expected the qualified Int32 wrapper")
  }
  assert_eq(value.to_string(), "42")
}

///|
test "signed Int32 addition wraps after exact calculation" {
  let output = @frontend.compile_int32_library(
    input("pub fn overflow() -> Int32 { 2147483647 + 1 }"),
  )
  ignore(library_generated(output))
  let runtime = string_runtime(output)
  guard @backend.call_entry(runtime, output.entries[0], [])
    is Tagged("morphir/SDK:int#int32", [Number(Integer(value))]) else {
    fail("Expected the qualified Int32 wrapper")
  }
  assert_eq(value.to_string(), "-2147483648")
}

///|
test "signed Int32 lexical boundaries preserve their source values" {
  for
    (literal, expected) in [
      ("-2147483648", "-2147483648"),
      ("2147483647", "2147483647"),
      ("0x8000_0000", "-2147483648"),
      ("0xffff_ffff", "-1"),
      ("0b1111_0000", "240"),
      ("0o17", "15"),
    ] {
    let output = @frontend.compile_int32_library(
      input("pub fn value() -> Int32 { " + literal + " }"),
    )
    let runtime = string_runtime(output)
    guard @backend.call_entry(runtime, output.entries[0], [])
      is Tagged("morphir/SDK:int#int32", [Number(Integer(actual))]) else {
      fail("Expected Int32 wrapper")
    }
    assert_eq(actual.to_string(), expected)
    assert_true(@ir_json.write(output.ir).contains(literal))
  }
}

///|
test "signed Int32 source rejects values beyond its 32-bit width" {
  for literal in ["2147483648", "-2147483649", "0x1_0000_0000"] {
    try {
      ignore(
        @frontend.compile_int32_library(
          input("pub fn value() -> Int32 { " + literal + " }"),
        ),
      )
      fail("Expected out-of-range source literal")
    } catch {
      @frontend.Invalid(_) => ()
      error => raise error
    }
  }
}

///|
test "Int alias retains authored spelling on its own numeric type use" {
  let output = @frontend.compile_int32_library(
    input("pub fn identity(value : Int) -> Int32 { value }"),
  )
  guard output.ir.distribution is Library(_, _, package_def) else {
    fail("Expected a library")
  }
  let definition = package_def.modules.values().collect()[0].value.values[@ir.Name::parse(
      "identity",
    )].value.value
  guard definition is ExpressionBody([(_, Reference(attrs, _, []))], _, _) else {
    fail("Expected concrete parameter type")
  }
  guard attrs.extensions.get("moonbit-source-number-v1")
    is Some(@ir.Data::Object(facts)) else {
    fail("Expected numeric type-use facts")
  }
  assert_eq(facts["authored"], @ir.Data::Text("Int"))
  assert_eq(facts["canonical_type"], @ir.Data::Text("Int32"))
  assert_eq(facts["profile"], @ir.Data::Text(@frontend.INT32_LIBRARY_PROFILE))
}

///|
test "negating the signed minimum remains the signed minimum" {
  let output = @frontend.compile_int32_library(
    input("pub fn negate(value : Int32) -> Int32 { -value }"),
  )
  let runtime = string_runtime(output)
  guard @backend.call_entry(runtime, output.entries[0], [
      @scheme.Tagged("morphir/SDK:int#int32", [@scheme.integer("-2147483648")]),
    ])
    is Tagged("morphir/SDK:int#int32", [Number(Integer(actual))]) else {
    fail("Expected Int32 wrapper")
  }
  assert_eq(actual.to_string(), "-2147483648")
}

///|
test "signed Int32 arithmetic and comparisons retain typed call behavior" {
  let output = @frontend.compile_int32_library(
    input(
      "pub fn total(a : Int32, b : Int32) -> Int32 { let product = a * b; if product > 1000 { product - 100 } else { product } }\npub fn before(a : Int32, b : Int32) -> Bool { a < b }\npub fn same(a : Int32, b : Int32) -> Bool { a == b }",
    ),
  )
  ignore(library_generated(output))
  let runtime = string_runtime(output)
  let number = fn(n : String) raise {
    @scheme.Tagged("morphir/SDK:int#int32", [@scheme.integer(n)])
  }
  let total = output.entries.filter(e => e.local_name.to_canonical() == "total")[0]
  guard @backend.call_entry(runtime, total, [number("65536"), number("65536")])
    is Tagged("morphir/SDK:int#int32", [Number(Integer(product))]) else {
    fail("Expected wrapped product")
  }
  assert_eq(product.to_string(), "0")
  let before = output.entries.filter(e => {
      e.local_name.to_canonical() == "before"
    })[0]
  guard @backend.call_entry(runtime, before, [number("-1"), number("1")])
    is Boolean(ordered) else {
    fail("Expected comparison")
  }
  assert_true(ordered)
  let same = output.entries.filter(e => e.local_name.to_canonical() == "same")[0]
  guard @backend.call_entry(runtime, same, [number("-1"), number("1")])
    is Boolean(equal) else {
    fail("Expected equality")
  }
  assert_false(equal)
}
