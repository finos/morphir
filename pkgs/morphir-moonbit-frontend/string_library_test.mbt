///|
fn string_output(
  source : String,
  limit~ : Int32 = 1048576,
) -> @frontend.LibraryOutput raise {
  @frontend.compile_library(input(source), max_string_code_units=limit)
}

///|
fn string_runtime(output : @frontend.LibraryOutput) -> @scheme.Runtime raise {
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime, model_errors=true)
  ignore(runtime.eval(@backend.emit_file(output.ir)))
  runtime
}

///|
test "String basics compile real mixed libraries and preserve literal spelling" {
  let output = string_output(
    "// λ😀 scalar lexer coordinates\npub fn greet(name : String, enabled : Bool) -> String { let prefix : String = hello(); if enabled { prefix + name } else { \"\" } }\nfn hello() -> String { \"Hello, \\u{1f600} \\n\" }\npub fn same() -> Bool { \"😀\" == \"\\u{1f600}\" && \"é\" != \"e\\u0301\" }",
  )
  ignore(library_generated(output))
  let runtime = string_runtime(output)
  let entry = output.entries.filter(e => e.local_name.to_canonical() == "greet")[0]
  assert_eq(
    @backend.call_entry(runtime, entry, [
      @scheme.Text("Morphir"),
      @scheme.Boolean(true),
    ]).as_text(),
    "Hello, 😀 \nMorphir",
  )
  let same = output.entries.filter(e => e.local_name.to_canonical() == "same")[0]
  guard @backend.call_entry(runtime, same, []) is Boolean(value) else {
    fail("Expected Bool")
  }
  assert_true(value)
  let json = @ir_json.write(output.ir)
  assert_true(json.contains("authored_token"))
  assert_true(json.contains("well-formed-utf16"))
  assert_true(json.contains("public-argument"))
}

///|
test "public String guards apply even to unused parameters and Boolean results" {
  let output = string_output(
    "pub fn ignore_text(s : String) -> Bool { true }",
    limit=3,
  )
  let runtime = string_runtime(output)
  for
    argument in [
      @scheme.Tagged("sdk-text", [@scheme.Vector([@scheme.integer("55296")])]),
      @scheme.Text("abcd"),
    ] {
    try {
      ignore(@backend.call_entry(runtime, output.entries[0], [argument]))
      fail("Expected source boundary refusal")
    } catch {
      @scheme.Domain(code, _) =>
        assert_true(
          code == "sdk.unrepresentable_text" || code == "sdk.out_of_range",
        )
      error => raise error
    }
  }
}

///|
test "bounded concatenation rejects growth and preserves short circuiting" {
  let source = "fn large() -> String { \"ab\" + \"cd\" }\npub fn short() -> Bool { false && (large() == \"\") }\npub fn grow() -> String { large() }"
  let output = string_output(source, limit=3)
  let runtime = string_runtime(output)
  let short = output.entries.filter(e => e.local_name.to_canonical() == "short")[0]
  guard @backend.call_entry(runtime, short, []) is Boolean(value) else {
    fail("Expected Bool")
  }
  assert_false(value)
  let grow = output.entries.filter(e => e.local_name.to_canonical() == "grow")[0]
  try {
    ignore(@backend.call_entry(runtime, grow, []))
    fail("Expected growth refusal")
  } catch {
    @scheme.Domain(code, _) => assert_eq(code, "sdk.out_of_range")
    error => raise error
  }
}

///|
test "String basics refuse unqualified operations and malformed literal scalars" {
  for
    source in [
      "pub fn f(s : String) -> Bool { s.is_empty() }", "pub fn f(s : String) -> String { s + true }",
      "pub fn f(s : String) -> String { if s { s } else { s } }", "pub fn f(s : String) -> Bool { s == false }",
      "pub fn f() -> String { \"\\uD800\" }", "pub fn f() -> String { \"\\u{110000}\" }",
      "pub fn f() -> String { \"\\{true}\" }",
    ] {
    try {
      ignore(string_output(source))
      fail("Expected refusal")
    } catch {
      @frontend.Invalid(_) => ()
      error => raise error
    }
  }
}

///|
test "source String declarations cannot shadow runtime extension identities" {
  for package_name in ["morphir/SDK", "morphir/moonbit-source"] {
    try {
      ignore(
        @frontend.compile_library({
          ..input("pub fn require_valid(s : String) -> String { s }"),
          package_name,
        }),
      )
      fail("Expected reserved identity refusal")
    } catch {
      @frontend.Invalid(diagnostic) =>
        assert_eq(diagnostic.code, "moonbit_frontend.invalid_identity")
      error => raise error
    }
  }
}
