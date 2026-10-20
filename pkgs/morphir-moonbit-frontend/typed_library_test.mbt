///|
test "source Int32 signatures resolve the pinned SDK declaration" {
  let output = @frontend.compile_library(
    input("pub fn identity(value : Int32) -> Int { value }"),
  )
  guard output.ir.distribution is Library(_, _, package_def) else {
    fail("Expected library")
  }
  let definition = package_def.modules.values().collect()[0].value.values[@ir.Name::parse(
      "identity",
    )].value.value
  guard definition
    is ExpressionBody(
      [(_, Reference(_, input_type, []))],
      Reference(_, output_type, []),
      _
    ) else {
    fail("Expected concrete signature")
  }
  assert_eq(input_type.to_canonical(), "morphir/SDK:int#int-32")
  assert_eq(input_type, output_type)
  let sdk = @sdk_spec.sdk_specification()
  assert_true(
    sdk.modules[input_type.module_name].types.contains(input_type.local_name),
  )
}

///|
test "typed foundation checks mixed branches, calls, shadowing and authored type uses" {
  let output = @frontend.compile_library(
    input(
      "pub fn choose(flag : Bool, a : Int32, b : Int) -> Int32 { let value : Int = if flag { a } else { b }; identity(value) }\nfn identity(value : Int32) -> Int { value }",
    ),
  )
  let generated = library_generated(output)
  assert_eq(generated.symbols.filter(s => s.public).length(), 1)
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  ignore(runtime.eval(@backend.emit_file(output.ir)))
  let value = fn(n : Int64) raise {
    @scheme.Tagged("morphir/SDK:int#int32", [@scheme.integer(n.to_string())])
  }
  for flag in [false, true] {
    guard @backend.call_entry(runtime, output.entries[0], [
        @scheme.Boolean(flag),
        value(-2147483648L),
        value(2147483647L),
      ])
      is Tagged("morphir/SDK:int#int32", [Number(Integer(n))]) else {
      fail("Expected Int32 wrapper")
    }
    assert_eq(n.to_string(), if flag { "-2147483648" } else { "2147483647" })
  }
}

///|
test "library rejects mismatched scalars" {
  for
    source in [
      "pub fn f(x : Int32) -> Bool { x }", "pub fn f(x : Int32) -> Int32 { if x { x } else { x } }",
      "pub fn f(x : Int32) -> Int32 { if true { x } else { false } }", "pub fn f(x : Int32) -> Int32 { let y : Bool = x; x }",
      "pub fn f(x : Int32) -> Int32 { g(x) }\nfn g(x : Bool) -> Int32 { f(true) }",
    ] {
    try {
      ignore(@frontend.compile_library(input(source)))
      fail("Expected mismatch")
    } catch {
      @frontend.Invalid(diagnostic) =>
        assert_eq(diagnostic.code, "moonbit_frontend.type_mismatch")
      error => raise error
    }
  }
  ignore(@frontend.compile_library(input("pub fn f(x : Int32) -> Int32 { x }")))
}

///|
test "expression constraints retain their own authored type use" {
  let output = @frontend.compile_library(
    input("pub fn identity(x : Int32) -> Int32 { (x : Int) }"),
  )
  // Int occurs only in the constraint, not in either declaration type use.
  assert_true(@ir_json.write(output.ir).contains("\"Int\""))
  ignore(library_generated(output))
}
