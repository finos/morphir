///|
fn ordered_source() -> String {
  "pub fn lt(a : String, b : String) -> Bool { identity(a) < identity(b) }\npub fn le(a : String, b : String) -> Bool { a <= b }\npub fn gt(a : String, b : String) -> Bool { a > b }\npub fn ge(a : String, b : String) -> Bool { a >= b }\npub fn choose(a : String, b : String, yes : Int32, no : Int) -> Int32 { let before : Bool = lt(a, b); if before { yes } else { no } }\nfn identity(s : String) -> String { s }"
}

///|
test "ordered cumulative profile preserves UTF-16 shortlex rather than SDK lexical order" {
  let output = @frontend.compile_supported_library_v2(input(ordered_source()))
  ignore(library_generated(output))
  let runtime = string_runtime(output)
  for
    (a, b, order) in [
      ("b", "aa", -1),
      ("aa", "b", 1),
      ("", "a", -1),
      ("", "", 0),
      ("😀", "\u{e000}a", -1),
      ("\u{e000}a", "😀", 1),
      ("😀", "\u{e000}", 1),
      ("é", "é", -1),
      ("ab", "aa", 1),
      ("😀", "😀", 0),
      ("a\u0000", "aa", -1),
    ] {
    for
      (name, expected) in [
        ("lt", order < 0),
        ("le", order <= 0),
        ("gt", order > 0),
        ("ge", order >= 0),
      ] {
      let entry = output.entries.filter(e => e.local_name.to_canonical() == name)[0]
      guard @backend.call_entry(runtime, entry, [
          @scheme.Text(a),
          @scheme.Text(b),
        ])
        is Boolean(actual) else {
        fail("Expected Bool")
      }
      assert_eq(actual, expected, msg=name + ": " + a + ", " + b)
    }
  }
  let stored = @ir_json.write(output.ir)
  assert_true(stored.contains("utf16-shortlex"))
  assert_true(stored.contains("length-first-lexical-tie"))
  assert_true(stored.contains("signed-32"))
}

///|
test "ordering is String-only and does not widen pinned v1 profiles" {
  for
    compile in [
      fn(i) raise { @frontend.compile_library(i) },
      fn(i) raise { @frontend.compile_typed_library(i) },
      fn(i) raise { @frontend.compile_string_library(i) },
      fn(i) raise { @frontend.compile_supported_library(i) },
    ] {
    try {
      ignore(
        compile(input("pub fn f(a : String, b : String) -> Bool { a < b }")),
      )
      fail("Expected pinned refusal")
    } catch {
      @frontend.Invalid(_) => ()
      error => raise error
    }
  }
  for
    source in [
      "pub fn f(a : Int32, b : Int32) -> Bool { a < b }", "pub fn f(a : Bool, b : Bool) -> Bool { a >= b }",
      "pub fn f(a : String, b : Bool) -> Bool { a <= b }", "pub fn f(a : String) -> Int32 { a.compare(\"a\") }",
    ] {
    try {
      ignore(@frontend.compile_supported_library_v2(input(source)))
      fail("Expected type refusal")
    } catch {
      @frontend.Invalid(diagnostic) => assert_true(diagnostic.source is Some(_))
      error => raise error
    }
  }
}

///|
test "ordering evaluates operands strictly left to right and retains source guards" {
  let output = @frontend.compile_supported_library_v2(
    input(
      "fn growth() -> String { \"abc\" + \"def\" }\nfn literal() -> String { \"123456\" }\npub fn first() -> Bool { growth() < literal() }\npub fn second() -> Bool { literal() >= growth() }\npub fn eager() -> Bool { \"\" < literal() }\npub fn short() -> Bool { false && first() }\npub fn less(a : String, b : String) -> Bool { a < b }",
    ),
    max_string_code_units=5,
  )
  let runtime = string_runtime(output)
  for
    (name, fragment) in [
      ("first", "concatenation"),
      ("second", "code-unit limit"),
      ("eager", "code-unit limit"),
    ] {
    let entry = output.entries.filter(e => e.local_name.to_canonical() == name)[0]
    try {
      ignore(@backend.call_entry(runtime, entry, []))
      fail("Expected bound refusal")
    } catch {
      @scheme.Domain(code, detail) => {
        assert_eq(code, "sdk.out_of_range")
        assert_true(detail.contains(fragment))
      }
      error => raise error
    }
  }
  let short = output.entries.filter(e => e.local_name.to_canonical() == "short")[0]
  guard @backend.call_entry(runtime, short, []) is Boolean(actual) else {
    fail("Expected Bool")
  }
  assert_false(actual)
  let less = output.entries.filter(e => e.local_name.to_canonical() == "less")[0]
  for units in [[55296], [56320], [56320, 55296], [55296, 97]] {
    let invalid = @scheme.Tagged("sdk-text", [
      @scheme.Vector(units.map(u => @scheme.integer(u.to_string()))),
    ])
    for args in [[invalid, @scheme.Text("")], [@scheme.Text(""), invalid]] {
      try {
        ignore(@backend.call_entry(runtime, less, args))
        fail("Expected UTF-16 refusal")
      } catch {
        @scheme.Domain(code, _) => assert_eq(code, "sdk.unrepresentable_text")
        error => raise error
      }
    }
  }
}

///|
test "ordered profile retains observation neutrality and cancellation boundaries" {
  let source = input(ordered_source())
  let expected = @frontend.compile_supported_library_v2(source)
  let records = []
  let actual = @frontend.compile_supported_library_v2(
    source,
    scope=observer(records, Ref(0)).scope(),
  )
  assert_eq(actual.ir, expected.ir)
  assert_eq(actual.entries, expected.entries)
  for (a, b) in actual.metadata.zip(expected.metadata) {
    assert_eq(a.node_id, b.node_id)
    assert_true(a.data.equals(b.data))
  }
  for phase = 1; phase <= 6; phase = phase + 1 {
    let starts = Ref(0)
    let o = observer([], Ref(0))
    let o = {
      ..o,
      try_record: fn(record) {
        if record.signal == @observe.Started {
          starts.val += 1
        }
        @observe.Accepted
      },
    }
    try {
      ignore(
        @frontend.compile_supported_library_v2(source, scope=o.scope(), cancelled=fn() {
          starts.val == phase
        }),
      )
      fail("Expected cancellation")
    } catch {
      @frontend.Invalid(diagnostic) =>
        assert_eq(diagnostic.code, "moonbit_frontend.cancelled")
      error => raise error
    }
    assert_eq(starts.val, phase)
  }
  try {
    ignore(
      @frontend.compile_supported_library_v2(source, limits={
        ..@frontend.LibraryLimits::default(),
        max_expressions: 1,
      }),
    )
    fail("Expected source expression limit")
  } catch {
    @frontend.Invalid(diagnostic) =>
      assert_eq(diagnostic.code, "moonbit_frontend.expression_limit")
    error => raise error
  }
}
