///|
test "String length counts UTF-16 units through the mixed source profile" {
  let output = @frontend.compile_library(
    input("pub fn count(s : String) -> Int32 { s.length() }"),
  )
  let runtime = string_runtime(output)
  guard @backend.call_entry(runtime, output.entries[0], [
      @scheme.Text("A😀é"),
    ])
    is Tagged("morphir/SDK:int#int32", [Number(Integer(value))]) else {
    fail("Expected Int32 length")
  }
  assert_eq(value.to_string(), "5")
  let malformed = @scheme.Tagged("sdk-text", [
    @scheme.Vector([@scheme.integer("55296")]),
  ])
  try {
    ignore(@backend.call_entry(runtime, output.entries[0], [malformed]))
    fail("Expected malformed String refusal")
  } catch {
    @scheme.Domain(code, _) => assert_eq(code, "sdk.unrepresentable_text")
    error => raise error
  }
}

///|
test "String slices adjust split surrogate boundaries inward" {
  let output = @frontend.compile_library(
    input(
      "pub fn cut(s : String, start : Int32, end : Int32) -> String { s[start:end].to_owned() }",
    ),
  )
  let runtime = string_runtime(output)
  let entry = output.entries[0]
  let source : @scheme.Value = @scheme.Text("A😀é")
  for
    (start, end, expected) in [
      (0, 5, "A😀é"),
      (1, 3, "😀"),
      (2, 3, ""),
      (1, 2, ""),
      (-100, 2, "A"),
      (3, 99, "é"),
      (-2147483648, 2147483647, "A😀é"),
      (2147483647, -2147483648, ""),
    ] {
    let args = [
      source,
      @scheme.Tagged("morphir/SDK:int#int32", [
        @scheme.integer(start.to_string()),
      ]),
      @scheme.Tagged("morphir/SDK:int#int32", [@scheme.integer(end.to_string())]),
    ]
    assert_eq(@backend.call_entry(runtime, entry, args).as_text(), expected)
  }
}

///|
test "indexed String syntax and bound types stay inside the cumulative profile" {
  for
    source in [
      "pub fn raw(s : String, a : Int32, b : Int32) -> String { s[a:b] }", "pub fn missing(s : String, a : Int32) -> String { s[a:].to_owned() }",
      "pub fn wrong(s : String, flag : Bool, b : Int32) -> String { s[flag:b].to_owned() }",
    ] {
    try {
      ignore(@frontend.compile_library(input(source)))
      fail("Expected indexed String admission failure")
    } catch {
      @frontend.Invalid(_) => ()
      error => raise error
    }
  }
  ignore(
    @frontend.compile_library(
      input("pub fn count(s : String) -> Int32 { s.length() }"),
    ),
  )
}

///|
test "cumulative source profile rejects arithmetic on String and Bool" {
  for
    source in [
      "pub fn bad() -> Bool { \"a\" - \"b\" }", "pub fn bad() -> Bool { \"a\" * \"b\" }",
      "pub fn bad() -> Bool { true - false }", "pub fn bad() -> Bool { true * false }",
    ] {
    try {
      ignore(@frontend.compile_library(input(source)))
      fail("Expected unsupported operand/operator pair: " + source)
    } catch {
      @frontend.Invalid(d) =>
        assert_eq(d.code, "moonbit_frontend.unsupported_operator", msg=source)
      error => raise error
    }
  }
}
