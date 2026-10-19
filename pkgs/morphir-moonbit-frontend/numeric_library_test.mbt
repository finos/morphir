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
test "integer library preserves UInt64 maximum and BigInt above UInt64" {
  let output = @frontend.compile_integer_library(
    input(
      "pub fn unsigned() -> UInt64 { 18446744073709551615UL }\npub fn unbounded() -> BigInt { 18446744073709551616N }",
    ),
  )
  let encoded = @ir_json.write(output.ir)
  assert_true(encoded.contains("18446744073709551615"))
  assert_true(encoded.contains("18446744073709551616"))
  assert_true(encoded.contains("moonbit-source-number-v1"))
  guard output.ir.distribution is Library(_, _, package_def) else {
    fail("Expected an integer library")
  }
  let definition = package_def.modules.values().collect()[0].value.values[@ir.Name::parse(
      "unsigned",
    )].value.value
  guard definition is ExpressionBody(_, Reference(attrs, _, []), _) else {
    fail("Expected a UInt64 output type")
  }
  guard attrs.extensions.get("moonbit-source-number-v1")
    is Some(@ir.Data::Object(facts)) else {
    fail("Expected UInt64 type-use facts")
  }
  assert_eq(facts["canonical_type"], @ir.Data::Text("UInt64"))
  assert_eq(facts["signedness"], @ir.Data::Text("unsigned"))
  assert_eq(facts["width"], @ir.Data::Number("64"))
}

///|
test "UInt64 addition wraps and BigInt addition remains exact" {
  let output = @frontend.compile_integer_library(
    input(
      "pub fn wrap() -> UInt64 { 18446744073709551615UL + 1UL }\npub fn grow() -> BigInt { 18446744073709551616N + 1N }",
    ),
  )
  ignore(library_generated(output))
  let receipt = @ir_json.write(output.ir)
  assert_true(receipt.contains("exact-widening"))
  assert_true(receipt.contains("source-width-wrap"))
  let runtime = string_runtime(output)
  for
    (name, tag, expected) in [
      ("wrap", "morphir/SDK:int#uint-64", "0"),
      ("grow", "", "18446744073709551617"),
    ] {
    let entry = output.entries.filter(e => e.local_name.to_canonical() == name)[0]
    let actual = @backend.call_entry(runtime, entry, [])
    if tag == "" {
      guard actual is Number(Integer(value)) else { fail("Expected BigInt") }
      assert_eq(value.to_string(), expected)
    } else {
      guard actual is Tagged(found, [Number(Integer(value))]) else {
        fail("Expected UInt64")
      }
      assert_eq(found, tag)
      assert_eq(value.to_string(), expected)
    }
  }
}

///|
test "each additional fixed integer width wraps at its source boundary" {
  for
    (type_name, expression, tag, expected) in [
      ("Int16", "32767 + 1", "int16", "-32768"),
      ("Int64", "9223372036854775807L + 1L", "int64", "-9223372036854775808"),
      ("Byte", "255 + 1", "byte", "0"),
      ("UInt16", "65535 + 1", "uint-16", "0"),
      ("UInt32", "4294967295U + 1U", "uint-32", "0"),
    ] {
    let output = @frontend.compile_integer_library(
      input("pub fn wrap() -> " + type_name + " { " + expression + " }"),
    )
    ignore(library_generated(output))
    let runtime = string_runtime(output)
    guard @backend.call_entry(runtime, output.entries[0], [])
      is Tagged(found, [Number(Integer(value))]) else {
      fail("Expected fixed-width result: " + type_name)
    }
    assert_eq(found, "morphir/SDK:int#" + tag)
    assert_eq(value.to_string(), expected)
  }
}

///|
test "integer radix and suffix literals retain exact extrema" {
  for
    (type_name, literal, expected) in [
      ("Int16", "-32768", "-32768"),
      ("Int64", "-9223372036854775808L", "-9223372036854775808"),
      ("Int64", "0xffff_ffff_ffff_ffffL", "-1"),
      ("Byte", "255", "255"),
      ("UInt16", "65535", "65535"),
      ("UInt32", "0xffff_ffffU", "4294967295"),
      ("UInt64", "0xffff_ffff_ffff_ffffUL", "18446744073709551615"),
      ("BigInt", "0x1_0000_0000_0000_0000N", "18446744073709551616"),
    ] {
    let output = @frontend.compile_integer_library(
      input("pub fn value() -> " + type_name + " { " + literal + " }"),
    )
    let runtime = string_runtime(output)
    let actual = @backend.call_entry(runtime, output.entries[0], [])
    match actual {
      Tagged(_, [Number(Integer(n))]) | Number(Integer(n)) =>
        assert_eq(n.to_string(), expected)
      _ => fail("Expected exact integer literal")
    }
    assert_true(@ir_json.write(output.ir).contains(literal))
  }
}

///|
test "integer literals reject overflow and an excessive digit count" {
  for
    (type_name, literal) in [
      ("Int16", "32768"),
      ("Byte", "256"),
      ("UInt16", "65536"),
      ("UInt32", "4294967296U"),
      ("UInt64", "18446744073709551616UL"),
      ("BigInt", String::make(4097, '9') + "N"),
    ] {
    try {
      ignore(
        @frontend.compile_integer_library(
          input("pub fn value() -> " + type_name + " { " + literal + " }"),
        ),
      )
      fail("Expected integer literal refusal")
    } catch {
      @frontend.Invalid(_) => ()
      error => raise error
    }
  }
}

///|
test "BigInt source multiplication checks its result budget" {
  let output = @frontend.compile_integer_library(
    input("pub fn grow(value : BigInt) -> BigInt { value * value }"),
  )
  ignore(library_generated(output))
  let runtime = string_runtime(output)
  try {
    ignore(
      @backend.call_entry(runtime, output.entries[0], [
        @scheme.integer(String::make(4096, '9')),
      ]),
    )
    fail("Expected result digit budget refusal")
  } catch {
    @scheme.Domain(code, detail) => {
      assert_eq(code, "sdk.out_of_range")
      assert_true(detail.contains("digit budget"))
    }
    error => raise error
  }
}

///|
test "BigInt public boundaries refuse oversized arguments even for identity" {
  let output = @frontend.compile_integer_library(
    input("pub fn identity(value : BigInt) -> BigInt { value }"),
  )
  let runtime = string_runtime(output)
  try {
    ignore(
      @backend.call_entry(runtime, output.entries[0], [
        @scheme.integer(String::make(4097, '9')),
      ]),
    )
    fail("Expected public BigInt boundary refusal")
  } catch {
    @scheme.Domain(code, detail) => {
      assert_eq(code, "sdk.out_of_range")
      assert_true(detail.contains("digit budget"))
    }
    error => raise error
  }
}

///|
test "generation refuses a missing declared source integer extension" {
  let output = @frontend.compile_integer_library(
    input("pub fn wrap() -> UInt64 { 18446744073709551615UL + 1UL }"),
  )
  guard output.ir.distribution is Library(name, _, definition) else {
    fail("Expected an integer library")
  }
  let stripped = @ir.IRFile::new(
    @ir.Distribution::Library(name, Map([]), definition),
  )
  try {
    ignore(@generator.generate(@generator.Input::new(output.unit_id, stripped)))
    fail("Expected missing extension refusal")
  } catch {
    @generator.Invalid(code, context, _) => {
      assert_eq(code, "moonbit.missing_source_extension")
      assert_true(context.contains("wrap"))
    }
    error => raise error
  }
}

///|
test "mixed typed integer calls preserve their declared widths" {
  let output = @frontend.compile_integer_library(
    input(
      "fn before(a : Int16, b : Int16) -> Bool { a < b }\npub fn advance(a : Int16, b : UInt64) -> UInt64 { if before(a, a + 1) { b + 1UL } else { b } }",
    ),
  ) catch {
    @frontend.Invalid(diagnostic) =>
      fail(diagnostic.code + ": " + diagnostic.detail)
    error => raise error
  }
  ignore(library_generated(output))
  let runtime = string_runtime(output)
  let arguments = [
    @scheme.Tagged("morphir/SDK:int#int16", [@scheme.integer("2")]),
    @scheme.Tagged("morphir/SDK:int#uint-64", [
      @scheme.integer("18446744073709551615"),
    ]),
  ]
  guard @backend.call_entry(runtime, output.entries[0], arguments)
    is Tagged("morphir/SDK:int#uint-64", [Number(Integer(result))]) else {
    fail("Expected mixed integer call to retain UInt64")
  }
  assert_eq(result.to_string(), "0")
}

///|
test "Float and Double source arithmetic retain distinct precision" {
  let output = @frontend.compile_float_library(
    input(
      "pub fn rounded() -> Float { 16777216.0F + 1.0F }\npub fn wider() -> Double { 9007199254740992.0 + 2.0 }",
    ),
  )
  let runtime = string_runtime(output)
  assert_true(@ir_json.write(output.ir).contains("binary32-operation-rounding"))
  for
    (name, expected) in [("rounded", 16777216.0), ("wider", 9007199254740994.0)] {
    let entry = output.entries.filter(e => e.local_name.to_canonical() == name)[0]
    guard @backend.call_entry(runtime, entry, []) is Number(Real(actual)) else {
      fail("Expected floating source result")
    }
    assert_eq(actual, expected)
  }
  ignore(library_generated(output))
}

///|
test "Float public boundaries round inputs and retain signed zero" {
  let output = @frontend.compile_float_library(
    input(
      "pub fn identity(value : Float) -> Float { value }\npub fn negative_zero() -> Float { -0.0F }",
    ),
  )
  let generated = library_generated(output)
  assert_true(@ir_json.write(output.ir).contains("rounded-to-binary32"))
  assert_true(
    generated.artifacts.any(artifact => {
      match artifact.content {
        @generator.Text(source) => source.contains("round32")
        _ => false
      }
    }),
  )
  let runtime = string_runtime(output)
  let identity = output.entries.filter(e => {
      e.local_name.to_canonical() == "identity"
    })[0]
  guard @backend.call_entry(runtime, identity, [
      @scheme.Value::Number(Real(16777217.0)),
    ])
    is Number(Real(rounded)) else {
    fail("Expected rounded Float")
  }
  assert_eq(rounded, 16777216.0)
  let zero = output.entries.filter(e => {
      e.local_name.to_canonical() == "negative-zero"
    })[0]
  guard @backend.call_entry(runtime, zero, []) is Number(Real(value)) else {
    fail("Expected negative zero")
  }
  assert_eq(value.reinterpret_as_uint64(), 9223372036854775808UL)
}

///|
test "generation refuses a missing declared Float32 source extension" {
  let output = @frontend.compile_float_library(
    input("pub fn rounded() -> Float { 16777216.0F + 1.0F }"),
  )
  guard output.ir.distribution is Library(name, _, definition) else {
    fail("Expected Float library")
  }
  let stripped = @ir.IRFile::new(
    @ir.Distribution::Library(name, Map([]), definition),
  )
  try {
    ignore(@generator.generate(@generator.Input::new(output.unit_id, stripped)))
    fail("Expected missing Float extension refusal")
  } catch {
    @generator.Invalid(code, context, _) => {
      assert_eq(code, "moonbit.missing_source_extension")
      assert_true(context.contains("rounded"))
    }
    error => raise error
  }
}

///|
test "Float32 comparisons use rounded operands and preserve NaN ordering" {
  let output = @frontend.compile_float_library(
    input("pub fn before(a : Float, b : Float) -> Bool { a < b && a != b }"),
  )
  ignore(library_generated(output))
  let runtime = string_runtime(output)
  for
    (left, right, expected) in [
      (1.0, 2.0, true),
      (2.0, 1.0, false),
      (0.0 / 0.0, 1.0, false),
    ] {
    guard @backend.call_entry(runtime, output.entries[0], [
        @scheme.Value::Number(Real(left)),
        @scheme.Value::Number(Real(right)),
      ])
      is Boolean(actual) else {
      fail("Expected Float32 comparison")
    }
    assert_eq(actual, expected)
  }
}

///|
test "nonfinite source floating literals remain refused" {
  try {
    ignore(
      @frontend.compile_float_library(
        input("pub fn unsupported() -> Double { 1.0e400 }"),
      ),
    )
    fail("Expected nonfinite literal refusal")
  } catch {
    @frontend.Invalid(_) => ()
    error => raise error
  }
}

///|
test "Double source retains signed zero and the minimum subnormal bit pattern" {
  let output = @frontend.compile_float_library(
    input(
      "pub fn zero() -> Double { -0.0 }\npub fn tiny() -> Double { 5.0e-324 }",
    ),
  )
  ignore(library_generated(output))
  let runtime = string_runtime(output)
  for (name, expected_bits) in [("zero", 9223372036854775808UL), ("tiny", 1UL)] {
    let entry = output.entries.filter(e => e.local_name.to_canonical() == name)[0]
    guard @backend.call_entry(runtime, entry, []) is Number(Real(value)) else {
      fail("Expected Double observation")
    }
    assert_eq(value.reinterpret_as_uint64(), expected_bits)
  }
}

///|
test "integer division remainder and source casts are individually refused" {
  for expression in ["a / b", "a % b", "a.to_int()"] {
    try {
      ignore(
        @frontend.compile_integer_library(
          input(
            "pub fn unsupported(a : Int16, b : Int16) -> Int16 { " +
            expression +
            " }",
          ),
        ),
      )
      fail("Expected source operation refusal: " + expression)
    } catch {
      @frontend.Invalid(_) => ()
      error => raise error
    }
  }
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
