///|
fn numeric_sdk_bindings() -> @frontend.PinnedSourceBindings raise {
  @frontend.PinnedSourceBindings::sdk_numeric_conversions(
    "finos/morphir-sdk/basics", "0.1.0", "9c83a100383570236b3d781362524008f76dd56d",
    "basics",
  )
}

///|
fn numeric_sdk(source : String) -> @frontend.LibraryOutput raise {
  @frontend.compile_numeric_sdk_library(input(source), numeric_sdk_bindings())
}

///|
test "numeric SDK type call and effect facts survive checkpoints and generated receipts" {
  let output = numeric_sdk(
    "pub fn f(v : Double) -> @integer.Integer? { @int.from_float64_exact(v) }\npub fn g(v : Double) -> @integer.Integer raise @sdk.SdkError { @basics.round(v) }",
  )
  let stored = @ir_json.write(output.ir)
  for
    fact in [
      "moonbit-source-sdk-type-v1", "finos/morphir-sdk/integer", "sdk_classification",
      "morphir-sdk-moonbit-numeric-v1", "classic", "source_error_contract", "sdk.SdkError",
      "binary64-to-integer-checked-exact", "nearest-integer-ties-positive-infinity",
    ] {
    assert_true(stored.contains(fact), msg=fact)
  }
  assert_eq(@ir_json.read(stored), output.ir)
  let metadata = output.metadata.copy()
  let owner = metadata[0]
  metadata[0] = {
    ..owner,
    data: @ion.IonValue::from_fields([
      @ion.Field::new("source_facts", owner.data),
      @ion.Field::new("future_numeric", @ion.IonValue::string("retain-me")),
    ]),
  }
  let generated = library_generated({ ..output, metadata, })
  guard generated.artifacts.filter(a => a.path == "symbols.10n")[0].content
    is Binary(bytes) else {
    fail("Expected Ion receipt")
  }
  let receipt = @ion_binary.read_binary_value(bytes[:])
  let text = @ion_text.write_ion(receipt)
  for
    fact in [
      "future_numeric", "retain-me", "source_error_contract", "sdk.SdkError", "morphir-sdk-moonbit-numeric-v1",
    ] {
    assert_true(text.contains(fact), msg=fact)
  }
  assert_true(@ion_text.read_ion(text.view()).equals(receipt))
}

///|
test "classic rounding uses independently specified integer results and errors" {
  for
    (name, expected) in [
      ("round", ["-2", "-1", "0", "0", "1", "2", "3"]),
      ("floor", ["-3", "-2", "-1", "0", "0", "1", "2"]),
      ("ceiling", ["-2", "-1", "0", "0", "1", "2", "3"]),
      ("truncate", ["-2", "-1", "0", "0", "0", "1", "2"]),
    ] {
    let output = numeric_sdk(
      "pub fn f(v : Double) -> @integer.Integer raise @sdk.SdkError { @basics." +
      name +
      "(v) }",
    )
    let runtime = string_runtime(output)
    let inputs = [-2.5, -1.5, -0.5, -0.0, 0.5, 1.5, 2.5]
    for i = 0; i < inputs.length(); i = i + 1 {
      guard @backend.call_entry(runtime, output.entries[0], [
          @scheme.Number(@scheme.Real(inputs[i])),
        ])
        is Number(Integer(value)) else {
        fail("Expected Integer")
      }
      assert_eq(value.to_string(), expected[i], msg=name)
    }
    for
      (value, expected) in [
        (9007199254740992.0, "9007199254740992"),
        (
          1.0e100, "10000000000000000159028911097599180468360808563945281389781327557747838772170381060813469985856815104",
        ),
      ] {
      guard @backend.call_entry(runtime, output.entries[0], [
          @scheme.Number(@scheme.Real(value)),
        ])
        is Number(Integer(actual)) else {
        fail("Expected exact decoded binary64 integer")
      }
      assert_eq(actual.to_string(), expected)
    }
    for value in [1.0 / 0.0, -1.0 / 0.0, 0.0 / 0.0] {
      try {
        ignore(
          @backend.call_entry(runtime, output.entries[0], [
            @scheme.Number(@scheme.Real(value)),
          ]),
        )
        fail("Expected nonfinite refusal")
      } catch {
        @scheme.Domain(code, _) => assert_eq(code, "sdk.invalid_number")
        error => raise error
      }
    }
    ignore(library_generated(output))
  }
}

///|
test "checked binary64 conversions retain None and each distinct rounding policy" {
  for
    (name, positive, negative) in [
      ("exact", None, None),
      ("truncated", Some("1"), Some("-1")),
      ("floor", Some("1"), Some("-2")),
      ("ceiling", Some("2"), Some("-1")),
      ("rounded", Some("2"), Some("-1")),
    ] {
    let output = numeric_sdk(
      "pub fn f(v : Double) -> @integer.Integer? { @int.from_float64_" +
      name +
      "(v) }",
    )
    let runtime = string_runtime(output)
    for
      (value, expected) in [
        (1.5, positive),
        (-1.5, negative),
        (2.0, Some("2")),
        (-0.0, Some("0")),
        (1.0 / 0.0, None),
        (0.0 / 0.0, None),
      ] {
      let actual = @backend.call_entry(runtime, output.entries[0], [
        @scheme.Number(@scheme.Real(value)),
      ])
      match (actual, expected) {
        (Tagged("morphir/SDK:maybe#just", [Number(Integer(n))]), Some(wanted)) =>
          assert_eq(n.to_string(), wanted)
        (Tagged("morphir/SDK:maybe#nothing", []), None) => ()
        _ => fail("Unexpected checked conversion: " + name)
      }
    }
    ignore(library_generated(output))
  }
  for name in ["@basics.to_float", "@int.to_float64_rounded"] {
    let output = numeric_sdk(
      "pub fn f(v : @integer.Integer) -> Double { " + name + "(v) }",
    )
    let runtime = string_runtime(output)
    guard @backend.call_entry(runtime, output.entries[0], [
        @scheme.integer("9007199254740993"),
      ])
      is Number(Real(value)) else {
      fail("Expected binary64")
    }
    assert_eq(
      value.reinterpret_as_uint64(),
      9007199254740992.0.reinterpret_as_uint64(),
    )
  }
  let output = numeric_sdk(
    "pub fn f(v : @integer.Integer) -> Double? { @int.to_float64_exact(v) }",
  )
  let runtime = string_runtime(output)
  assert_true(
    @backend.call_entry(runtime, output.entries[0], [
      @scheme.integer("9007199254740993"),
    ])
    is Tagged("morphir/SDK:maybe#nothing", []),
  )
  guard @backend.call_entry(runtime, output.entries[0], [
      @scheme.integer("9007199254740992"),
    ])
    is Tagged("morphir/SDK:maybe#just", [Number(Real(value))]) else {
    fail("Expected exact binary64")
  }
  assert_eq(value, 9007199254740992.0)
}

///|
test "SDK Integer comparisons and optional boundaries keep exact values and budgets" {
  let output = numeric_sdk(
    "pub fn absolute(v : @integer.Integer) -> @integer.Integer { @basics.abs_int(v) }\npub fn before(a : @integer.Integer, b : @integer.Integer) -> Bool { a < b && a != b }\npub fn optional(v : @integer.Integer?, flag : Bool) -> @integer.Integer? { if flag { identity(v) } else { v } }\nfn identity(v : @integer.Integer?) -> @integer.Integer? { v }",
  )
  let runtime = string_runtime(output)
  // Derive the package from the fixture rather than assuming its spelling.
  fn named(name : String) -> @ir.FQName {
    output.entries.filter(e => e.to_canonical().has_suffix("#" + name))[0]
  }
  guard @backend.call_entry(runtime, named("absolute"), [
      @scheme.integer("-9007199254740993"),
    ])
    is Number(Integer(n)) else {
    fail("Expected exact abs")
  }
  assert_eq(n.to_string(), "9007199254740993")
  assert_true(
    @backend.call_entry(runtime, named("before"), [
      @scheme.integer("9007199254740992"),
      @scheme.integer("9007199254740993"),
    ])
    is Boolean(true),
  )
  let none = @scheme.Tagged("morphir/SDK:maybe#nothing", [])
  assert_true(
    @backend.call_entry(runtime, named("optional"), [
      none,
      @scheme.Boolean(true),
    ])
    is Tagged("morphir/SDK:maybe#nothing", []),
  )
  let huge = @scheme.integer("1" + "0".repeat(4096))
  for
    (name, args) in [
      ("absolute", [huge]),
      ("before", [huge, @scheme.integer("0")]),
      (
        "optional",
        [
          @scheme.Tagged("morphir/SDK:maybe#just", [huge]),
          @scheme.Boolean(false),
        ],
      ),
    ] {
    try {
      ignore(@backend.call_entry(runtime, named(name), args))
      fail("Expected public integer bound")
    } catch {
      @scheme.Domain(code, _) => assert_eq(code, "sdk.out_of_range")
      error => raise error
    }
  }
  ignore(library_generated(output))
}

///|
test "SDK effects propagate statically and source types remain distinct" {
  for
    (source, code) in [
      (
        "pub fn f(v : Double) -> @integer.Integer { @basics.round(v) }", "error_contract",
      ),
      (
        "pub fn f(v : Double) -> @integer.Integer { if false { g(v) } else { g(v) } }\nfn g(v : Double) -> @integer.Integer raise @sdk.SdkError { @basics.round(v) }",
        "error_contract",
      ),
      (
        "pub fn f(v : BigInt) -> Double { @basics.to_float(v) }", "type_mismatch",
      ),
      ("pub fn f(v : @integer.Integer) -> BigInt { v }", "type_mismatch"),
      ("pub fn f(v : @other.Integer) -> Double { 0.0 }", "unsupported_type"),
      (
        "pub fn f(v : Double) -> Double raise Error { v }", "unsupported_function",
      ),
      (
        "pub fn f(v : Double) -> Double raise @other.SdkError { v }", "unsupported_function",
      ),
      (
        "pub fn f(v : Double) -> Double? { @int.from_float64_exact(v) }", "type_mismatch",
      ),
      (
        "pub fn f(v : Float) -> @integer.Integer? { @int.from_float32_exact(v) }",
        "unknown_binding",
      ),
      (
        "pub fn f(v : @integer.Integer) -> @integer.Integer { v + v }", "unsupported_operator",
      ),
      (
        "pub fn f(v : @integer.Integer) -> @integer.Integer { -v }", "unsupported_operator",
      ),
      (
        "pub fn f(v : Double) -> @integer.Integer? { @other.from_float64_exact(v) }",
        "unknown_binding",
      ),
      (
        "pub fn f(int : Double) -> @integer.Integer? { @int.from_float64_exact(int) }",
        "shadowed_binding",
      ),
      (
        "pub fn f() -> @integer.Integer? { @int.from_float64_exact() }", "binding_arity",
      ),
      ("pub fn f() -> Bool? { true }", "unsupported_type"),
    ] {
    try {
      ignore(numeric_sdk(source))
      fail("Expected refusal: " + source)
    } catch {
      @frontend.Invalid(d) =>
        assert_eq(d.code, "moonbit_frontend." + code, msg=source)
      error => raise error
    }
  }
  let output = numeric_sdk(
    "pub fn f(v : Double) -> @integer.Integer raise @sdk.SdkError { g(v) }\nfn g(v : Double) -> @integer.Integer raise @sdk.SdkError { @basics.round(v) }",
  )
  ignore(library_generated(output))
  for
    source in [
      "pub fn f() -> Double? { Some(1.0) }", "pub fn f(v : Double?) -> Double { v.unwrap() }",
      "pub fn f(v : Double?) -> Double { match v { Some(x) => x; None => 0.0 } }",
      "pub fn f(v : Double) -> Double raise @sdk.SdkError { try { v } catch { _ => 0.0 } }",
    ] {
    let refused = try {
      ignore(numeric_sdk(source))
      false
    } catch {
      @frontend.Invalid(_) => true
      error => raise error
    }
    assert_true(refused, msg=source)
  }
}

///|
test "R3 requires the audited type environment and older profiles cannot borrow it" {
  for bindings in [@frontend.PinnedSourceBindings::empty(), math_bindings()] {
    try {
      ignore(
        @frontend.compile_numeric_sdk_library(
          input("pub fn f() -> Bool { true }"),
          bindings,
        ),
      )
      fail("Expected type identity refusal")
    } catch {
      @frontend.Invalid(d) =>
        assert_eq(d.code, "moonbit_frontend.binding_identity")
      error => raise error
    }
  }
  try {
    ignore(
      @frontend.compile_math_library(
        input(
          "pub fn f() -> Bool { let x = @int.from_float64_exact(1.0); true }",
        ),
        numeric_sdk_bindings(),
      ),
    )
    fail("Expected frozen profile")
  } catch {
    @frontend.Invalid(d) =>
      assert_eq(d.code, "moonbit_frontend.binding_identity")
    error => raise error
  }
  try {
    ignore(
      @frontend.compile_math_library(
        input("pub fn f(v : @integer.Integer) -> @integer.Integer { v }"),
        math_bindings(),
      ),
    )
    fail("Expected historical type refusal")
  } catch {
    @frontend.Invalid(d) =>
      assert_eq(d.code, "moonbit_frontend.unsupported_type")
    error => raise error
  }
}
