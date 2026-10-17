///|
fn supported_source() -> String {
  "pub fn choose_for(name : String, enabled : Bool, first : Int32, second : Int) -> Int32 { let greeting : String = welcome(name, enabled); if greeting == \"Hello, Morphir\" { identity(first) } else { identity(second) } }\npub fn welcome(name : String, enabled : Bool) -> String { if enabled { \"Hello, \" + name } else { \"\" } }\nfn identity(value : Int32) -> Int { (value : Int32) }"
}

///|
test "supported profile combines Bool, String and Int32 through the checked pipeline" {
  let output = @frontend.compile_supported_library(input(supported_source()))
  ignore(library_generated(output))
  let runtime = string_runtime(output)
  let entry = output.entries.filter(e => {
      e.local_name.to_canonical() == "choose-for"
    })[0]
  for
    (name, enabled, expected) in [
      ("Morphir", true, "-2147483648"),
      ("Morphir", false, "2147483647"),
      ("😀", true, "2147483647"),
    ] {
    let result = @backend.call_entry(runtime, entry, [
      @scheme.Text(name),
      @scheme.Boolean(enabled),
      @scheme.Tagged("morphir/SDK:int#int32", [@scheme.integer("-2147483648")]),
      @scheme.Tagged("morphir/SDK:int#int32", [@scheme.integer("2147483647")]),
    ])
    guard result is Tagged("morphir/SDK:int#int32", [Number(Integer(n))]) else {
      fail("Expected Int32 result")
    }
    assert_eq(n.to_string(), expected)
  }
  let stored = @ir_json.write(output.ir)
  assert_true(stored.contains("well-formed-utf16"))
  assert_true(stored.contains("signed-32"))
  assert_true(stored.contains("public-argument"))
  assert_true(
    output.provenance[0].kind() is @ion.Struct(fields) &&
    fields.any(f => {
      f
      .value()
      .equals(@ion.IonValue::string(@frontend.SUPPORTED_LIBRARY_PROFILE))
    }),
  )
  // The cumulative profile does not silently widen either pinned lane.
  for
    narrow in [
      fn(input) raise { @frontend.compile_string_library(input) },
      fn(input) raise { @frontend.compile_typed_library(input) },
    ] {
    try {
      ignore(narrow(input(supported_source())))
      fail("Expected lane refusal")
    } catch {
      @frontend.Invalid(diagnostic) =>
        assert_eq(diagnostic.code, "moonbit_frontend.unsupported_type")
      error => raise error
    }
  }
}

///|
test "supported profile keeps String guards on public entries returning Int32" {
  let output = @frontend.compile_supported_library(
    input("pub fn keep(s : String, value : Int32) -> Int32 { value }"),
    max_string_code_units=1,
  )
  let runtime = string_runtime(output)
  for
    (text, expected) in [
      (@scheme.Value::Text("ab"), "sdk.out_of_range"),
      (
        @scheme.Tagged("sdk-text", [@scheme.Vector([@scheme.integer("55296")])]),
        "sdk.unrepresentable_text",
      ),
    ] {
    try {
      ignore(
        @backend.call_entry(runtime, output.entries[0], [
          text,
          @scheme.Tagged("morphir/SDK:int#int32", [@scheme.integer("0")]),
        ]),
      )
      fail("Expected public String refusal")
    } catch {
      @scheme.Domain(code, _) => assert_eq(code, expected)
      error => raise error
    }
  }
}

///|
test "supported profile refuses source operations beyond the qualified union" {
  for
    source in [
      "pub fn f(a : Int32, b : Int32) -> Int32 { a + b }", "pub fn f(a : Int32, b : Int32) -> Bool { a == b }",
      "pub fn f() -> Int32 { 1 }", "pub fn f(s : String) -> Int32 { s.length() }",
      "pub fn f(s : String) -> Bool { s < \"a\" }", "pub fn f(x : Double) -> Double { x }",
      "pub fn f(s : String) -> String { f(s) }",
    ] {
    try {
      ignore(@frontend.compile_supported_library(input(source)))
      fail("Expected qualification refusal")
    } catch {
      @frontend.Invalid(_) => ()
      error => raise error
    }
  }
}
