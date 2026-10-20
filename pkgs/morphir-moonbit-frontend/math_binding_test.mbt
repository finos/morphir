///|
fn math_bindings() -> @frontend.PinnedSourceBindings raise {
  @frontend.PinnedSourceBindings::sdk_numeric_math(
    "finos/morphir-sdk/basics", "0.1.0", "9c83a100383570236b3d781362524008f76dd56d",
    "basics",
  )
}

///|
test "math Scheme references and exceptional categories match independent expectations" {
  // mpmath 1.3.0 at 100 decimal digits, rounded to binary64.
  for
    (expression, expected, ulps) in [
      ("@basics.sqrt(2.0)", 1.4142135623730951, 0UL),
      ("@basics.sqrt(0.5)", 0.7071067811865476, 0UL),
      ("@basics.sin(1.0)", 0.8414709848078965, 4UL),
      ("@basics.cos(1.0)", 0.5403023058681398, 4UL),
      ("@basics.sin(100.0)", -0.5063656411097588, 4UL),
      ("@basics.cos(100.0)", 0.8623188722876839, 4UL),
      ("@basics.power_float(10.0, 0.25)", 1.7782794100389228, 4UL),
      ("@basics.abs_float(-3.5)", 3.5, 0UL),
      ("@basics.sqrt(-0.0)", -0.0, 0UL),
      ("@basics.sin(-0.0)", -0.0, 0UL),
      ("@basics.abs_float(-0.0)", -0.0, 0UL),
    ] {
    let output = @frontend.compile_library(
      channel=@frontend.Experimental,
      input("pub fn calculate() -> Double { " + expression + " }"),
      bindings=Some(math_bindings()),
    )
    let runtime = string_runtime(output)
    guard @backend.call_entry(runtime, output.entries[0], [])
      is Number(Real(value)) else {
      fail("Expected math result")
    }
    let actual = value.reinterpret_as_uint64()
    let expected = expected.reinterpret_as_uint64()
    assert_true(
      (if actual > expected { actual - expected } else { expected - actual }) <=
      ulps,
      msg=expression,
    )
  }
  for
    expression in [
      "@basics.sqrt(-1.0)", "@basics.sin(1.0 / 0.0)", "@basics.cos(1.0 / 0.0)", "@basics.power_float(-1.0, 0.5)",
      "@basics.abs_float(0.0 / 0.0)",
    ] {
    let output = @frontend.compile_library(
      channel=@frontend.Experimental,
      input("pub fn calculate() -> Double { " + expression + " }"),
      bindings=Some(math_bindings()),
    )
    let runtime = string_runtime(output)
    guard @backend.call_entry(runtime, output.entries[0], [])
      is Number(Real(value)) else {
      fail("Expected domain result")
    }
    assert_true(value.is_nan(), msg=expression)
  }
}

///|
test "math source facts own canonical references and survive checked IR roundtrip" {
  let output = @frontend.compile_library(
    channel=@frontend.Experimental,
    input("pub fn root(value : Double) -> Double { @basics.sqrt(value) }"),
    bindings=Some(math_bindings()),
  )
  guard output.ir.distribution is Library(_, _, package_def) else {
    fail("Expected library")
  }
  let definition = package_def.modules.values().collect()[0].value.values[@ir.Name::parse(
      "root",
    )].value.value
  guard definition
    is ExpressionBody(
      _,
      _,
      @ir.Value::LetDefinition(
        _,
        _,
        _,
        @ir.Value::Apply(
          call_attrs,
          @ir.Value::Reference(reference_attrs, canonical),
          _
        )
      )
    ) else {
    fail("Expected single-evaluation SDK call")
  }
  assert_eq(canonical.to_canonical(), "morphir/SDK:basics#sqrt")
  for attrs in [call_attrs, reference_attrs] {
    guard attrs.extensions.get("moonbit-source-binding-v1")
      is Some(@ir.Data::Object(facts)) else {
      fail("Expected binding facts")
    }
    assert_eq(facts["source_signature"], @ir.Data::Text("Double -> Double"))
    assert_eq(
      facts["conversion_policy"],
      @ir.Data::Text("binary64-sqrt-exact-reference-bits"),
    )
    assert_eq(
      facts["source_tree"],
      @ir.Data::Text("9c83a100383570236b3d781362524008f76dd56d"),
    )
    facts["future_fact"] = @ir.Data::Text("retain-me")
  }
  assert_eq(@ir_json.read(@ir_json.write(output.ir)), output.ir)
  let generated = library_generated(output)
  assert_true(generated.symbols.any(s => s.public))
}

///|
test "SDK calls require audited names and matching argument types" {
  for
    (source, code) in [
      ("pub fn f() -> Double { @math.sqrt(2.0) }", "unknown_binding"),
      ("pub fn f() -> Double { @basics.tan(2.0) }", "unknown_binding"),
      ("pub fn f() -> Double { @basics.sqrt(2) }", "type_mismatch"),
      ("pub fn f() -> Double { @basics.sqrt(2.0F) }", "type_mismatch"),
      ("pub fn f() -> Double { @basics.power_float(2.0) }", "binding_arity"),
      (
        "pub fn f(basics : Double) -> Double { @basics.sqrt(basics) }", "shadowed_binding",
      ),
    ] {
    try {
      ignore(
        @frontend.compile_library(
          channel=@frontend.Experimental,
          input(source),
          bindings=Some(math_bindings()),
        ),
      )
      fail("Expected binding refusal")
    } catch {
      @frontend.Invalid(diagnostic) => {
        assert_eq(diagnostic.code, "moonbit_frontend." + code)
        assert_true(diagnostic.source is Some(_))
      }
      error => raise error
    }
  }
  ignore(
    @frontend.compile_library(
      channel=@frontend.Experimental,
      input("pub fn f() -> Double { @basics.sqrt(2.0) }"),
    ),
  )
}
