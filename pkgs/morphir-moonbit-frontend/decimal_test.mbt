///|
fn decimal_source(source : String) -> @frontend.LibraryOutput raise {
  @frontend.compile_library(
    channel=@frontend.Experimental,
    input(source),
    bindings=Some(
      @frontend.PinnedSourceBindings::sdk_decimal(
        "finos/morphir-sdk/decimal",
        "0.1.0",
        @frontend.DECIMAL_SDK_TREE,
        "decimal",
      ),
    ),
  )
}

///|
test "checked Decimal calls execute and preserve owned source scale and concrete types" {
  let output = decimal_source(
    "pub fn f() -> @decimal.Decimal raise @decimal.DecimalError { let a = @decimal.from_string_exact(\"12.3400\"); let b = @decimal.from_string_exact(\"0.660\"); @decimal.round(@decimal.divide(@decimal.mul(@decimal.add(a, b), b), b)) }",
  )
  let stored = @ir_json.write(output.ir)
  for
    fact in [
      "original_literal", "12.3400", "literal_scale", "moonbit-source-decimal-v1",
      "decimal.DecimalError", "morphir-sdk-decimal-checked-v1", "decimal-checked-v1",
      "decimal-half-even-integer",
    ] {
    assert_true(stored.contains(fact), msg=fact)
  }
  assert_eq(@ir_json.read(stored), output.ir)
  for accelerators in [false, true] {
    let runtime = @scheme.Runtime::new()
    @backend.install(runtime, accelerators~, model_errors=true)
    ignore(runtime.eval(@backend.emit_file(output.ir)))
    let actual = @backend.call_entry(runtime, output.entries[0], [])
    guard actual is Tagged("decimal", [Text(text)]) else {
      fail("Expected Decimal")
    }
    assert_eq(text, "13")
  }
  let generated = library_generated(output)
  assert_true(
    generated.project.dependencies[0].api_profile.has_suffix(
      "+decimal-checked-v1",
    ),
  )
  guard generated.artifacts.filter(a => a.path == "symbols.10n")[0].content
    is Binary(bytes) else {
    fail("Expected symbol receipt")
  }
  let receipt = @ion_binary.read_binary_value(bytes[:])
  let receipt_text = @ion_text.write_ion(receipt)
  for
    fact in [
      "12.3400", "literal_scale", "moonbit-source-decimal-v1", "decimal.DecimalError",
      "generated_error_type", "Error",
    ] {
    assert_true(receipt_text.contains(fact), msg=fact)
  }
  assert_true(@ion_text.read_ion(receipt_text.view()).equals(receipt))
}

///|
test "checked Decimal bindings require their audited identity" {
  let bindings = @frontend.PinnedSourceBindings::sdk_decimal(
    "finos/morphir-sdk/decimal",
    "0.1.0",
    @frontend.DECIMAL_SDK_TREE,
    "decimal",
  )
  ignore(
    @frontend.compile_library(
      channel=@frontend.Experimental,
      input("pub fn f() -> Bool { true }"),
      bindings=Some(bindings),
    ),
  )
  for
    (tree, sdk_alias) in [
      ("9c83a100383570236b3d781362524008f76dd56d", "decimal"),
      (@frontend.DECIMAL_SDK_TREE, "other"),
    ] {
    try {
      ignore(
        @frontend.PinnedSourceBindings::sdk_decimal(
          "finos/morphir-sdk/decimal", "0.1.0", tree, sdk_alias,
        ),
      )
      fail("Expected identity refusal")
    } catch {
      @frontend.Invalid(d) =>
        assert_eq(d.code, "moonbit_frontend.binding_identity")
      error => raise error
    }
  }
}

///|
test "Decimal precision belongs to its type use without changing adjacent Bool facts" {
  let output = decimal_source(
    "pub fn f(flag : Bool, amount : @decimal.Decimal) -> Bool { if flag { @decimal.eq(amount, amount) } else { flag } }",
  )
  guard output.ir.distribution is Library(_, _, package_def) else {
    fail("Expected library")
  }
  let definition = package_def.modules.values().collect()[0].value.values[@ir.Name::parse(
      "f",
    )].value.value
  guard definition
    is ExpressionBody(
      [
        (_, Reference(bool_attrs, _, [])),
        (_, Reference(decimal_attrs, decimal_name, [])),
      ],
      Reference(result_attrs, _, []),
      _
    ) else {
    fail("Expected concrete types")
  }
  assert_eq(decimal_name.to_canonical(), "morphir/SDK:decimal#decimal")
  assert_true(decimal_attrs.extensions.contains("moonbit-source-decimal-v1"))
  assert_false(bool_attrs.extensions.contains("moonbit-source-decimal-v1"))
  assert_false(result_attrs.extensions.contains("moonbit-source-decimal-v1"))
  assert_eq(@ir_json.read(@ir_json.write(output.ir)), output.ir)
}

///|
test "checked Decimal source failures and explicit fallback remain distinct" {
  for
    (expression, code) in [
      (
        "@decimal.divide(@decimal.from_string_exact(\"1\"), @decimal.from_string_exact(\"0\"))",
        "division_by_zero",
      ),
      (
        "@decimal.divide(@decimal.from_string_exact(\"1e-32\"), @decimal.from_string_exact(\"2\"))",
        "underflow",
      ),
      (
        "@decimal.from_string_exact(\"0.000000000000000000000000000000001\")", "precision_loss",
      ),
      ("@decimal.from_string_exact(\"NaN\")", "invalid_literal"),
    ] {
    let output = decimal_source(
      "pub fn f() -> @decimal.Decimal raise @decimal.DecimalError { " +
      expression +
      " }",
    )
    try {
      ignore(@backend.call_entry(string_runtime(output), output.entries[0], []))
      fail("Expected typed failure")
    } catch {
      @scheme.Domain(actual, _) => assert_eq(actual, "sdk.decimal." + code)
      error => raise error
    }
    ignore(library_generated(output))
  }
}

///|
test "Decimal admission is closed and effects propagate through direct calls" {
  for
    (source, code) in [
      (
        "pub fn f(v : String) -> @decimal.Decimal { @decimal.from_string_exact(v) }",
        "error_contract",
      ),
      (
        "pub fn f(a : @decimal.Decimal, b : @decimal.Decimal) -> @decimal.Decimal raise @sdk.SdkError { @decimal.divide(a, b) }",
        "error_contract",
      ),
      (
        "pub fn f(a : @decimal.Decimal) -> @decimal.Decimal { g(a) }\nfn g(a : @decimal.Decimal) -> @decimal.Decimal raise @decimal.DecimalError { @decimal.divide(a, a) }",
        "error_contract",
      ),
      (
        "pub fn f(a : @decimal.Decimal) -> @decimal.Decimal { a + a }", "unsupported_operator",
      ),
      (
        "pub fn f(a : @decimal.Decimal) -> @decimal.Decimal? { a }", "unsupported_type",
      ),
      ("pub fn f(a : @other.Decimal) -> Bool { true }", "unsupported_type"),
      (
        "pub fn f(a : @decimal.Decimal) -> @decimal.Decimal { @decimal.div(a, a) }",
        "unknown_binding",
      ),
    ] {
    try {
      ignore(decimal_source(source))
      fail("Expected refusal")
    } catch {
      @frontend.Invalid(d) =>
        assert_eq(d.code, "moonbit_frontend." + code, msg=source)
      error => raise error
    }
  }
}
