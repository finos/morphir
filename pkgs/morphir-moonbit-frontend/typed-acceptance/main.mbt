///|
fn main raise {
  let sources = [
    (
      "foundation", "pub fn choose(flag : Bool, a : Int32, b : Int) -> Int32 { let value : Int = if flag { a } else { b }; identity(value) }\nfn identity(value : Int32) -> Int { value }",
    ),
    (
      "strings", "// λ😀 literal offsets\nfn prefix() -> String { \"Hello, \" }\npub fn greet(name : String) -> String { let greeting : String = prefix(); greeting + name }\npub fn welcome(name : String, enabled : Bool) -> String { if enabled { greet(name) } else { \"\" } }\npub fn same(a : String, b : String) -> Bool { a == b }\npub fn escapes() -> String { \"\\u{1f600}\\u0301\\x41\\o101\\n\" }\npub fn ignore_text(s : String) -> Bool { true }\npub fn choose(a : String, b : String, flag : Bool) -> String { let value = if flag { a } else { b }; identity(value) }\nfn identity(s : String) -> String { s }",
    ),
    (
      "bounded", "pub fn join(a : String, b : String) -> String { a + b }\npub fn short() -> Bool { false && (join(\"abc\", \"def\") == \"\") }\npub fn ignore_text(s : String) -> Bool { true }\npub fn order() -> String { take(fail_growth(), fail_literal()) }\nfn take(a : String, b : String) -> String { a }\nfn fail_growth() -> String { \"abc\" + \"def\" }\nfn fail_literal() -> String { \"123456\" }",
    ),
  ]
  let v1_cases = sources +
    sources.map(row => ("supported" + row.0, row.1)) +
    [
      (
        "supported", "pub fn choose_for(name : String, enabled : Bool, first : Int32, second : Int) -> Int32 { let greeting : String = welcome(name, enabled); if greeting == \"Hello, Morphir\" { identity(first) } else { identity(second) } }\npub fn welcome(name : String, enabled : Bool) -> String { if enabled { \"Hello, \" + name } else { \"\" } }\nfn identity(value : Int32) -> Int { (value : Int32) }",
      ),
      (
        "supportedbool", "pub fn both(a : Bool, b : Bool) -> Bool { let a : Bool = identity(a); a && b }\npub fn either(a : Bool, b : Bool) -> Bool { identity(a) || identity(b) }\npub fn equal(a : Bool, b : Bool) -> Bool { identity(a) == identity(b) }\npub fn unequal(a : Bool, b : Bool) -> Bool { identity(a) != identity(b) }\npub fn shadow(a : Bool) -> Bool { let a = !a; let a : Bool = !a; (a : Bool) }\npub fn yes() -> Bool { identity(true) }\nfn identity(a : Bool) -> Bool { a }",
      ),
    ]
  let cases = v1_cases +
    v1_cases.map(row => ("current" + row.0, row.1)) +
    [
      (
        "currentordered", "pub fn lt(a : String, b : String) -> Bool { identity(a) < identity(b) }\npub fn le(a : String, b : String) -> Bool { a <= b }\npub fn gt(a : String, b : String) -> Bool { a > b }\npub fn ge(a : String, b : String) -> Bool { a >= b }\npub fn choose(a : String, b : String, yes : Int32, no : Int) -> Int32 { let before : Bool = lt(a, b); if before { yes } else { no } }\nfn identity(s : String) -> String { s }",
      ),
      (
        "currentorderedbounded", "fn growth() -> String { \"abc\" + \"def\" }\nfn literal() -> String { \"123456\" }\npub fn first() -> Bool { growth() < literal() }\npub fn second() -> Bool { literal() >= growth() }\npub fn eager() -> Bool { \"\" < literal() }\npub fn short() -> Bool { false && first() }",
      ),
    ]
  let models = []
  for (id, source) in cases {
    let source = "/// Qualification fixture documentation.\n///\n/// Preserve **Markdown** and λ😀.\n" +
      source
    let model_id = id
      .strip_prefix("current")
      .map(s => s.to_owned())
      .unwrap_or(id)
    let kind = model_id
      .strip_prefix("supported")
      .map(s => s.to_owned())
      .unwrap_or(model_id)
    let input : @frontend.Input = {
      unit_id: id + ".mbt",
      package_name: "typed/acceptance/" + id,
      module_name: "main",
      source,
    }
    let output = if id.has_prefix("current") {
      @frontend.compile_supported_library_2026_10_17(
        input,
        max_string_code_units=if kind == "bounded" || kind == "orderedbounded" {
          5
        } else {
          1048576
        },
      )
    } else if id.has_prefix("supported") {
      @frontend.compile_supported_library(
        input,
        max_string_code_units=if kind == "bounded" { 5 } else { 1048576 },
      )
    } else if id == "foundation" {
      @frontend.compile_typed_library(input)
    } else {
      @frontend.compile_string_library(
        input,
        max_string_code_units=if id == "bounded" { 5 } else { 1048576 },
      )
    }
    let generated = @generator.generate({
      unit_id: output.unit_id,
      ir: output.ir,
      metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
      annotations: output.annotations,
      provenance: output.provenance,
    })
    guard generated.artifacts.filter(a => a.path == "library.mbt")[0].content
      is Text(text) else {
      fail("Expected source")
    }
    assert_true(
      text.contains(
        "/// Qualification fixture documentation.\n///\n/// Preserve **Markdown** and λ😀.",
      ),
    )
    let runtime = @scheme.Runtime::new()
    @backend.install(runtime, model_errors=true)
    ignore(runtime.eval(@backend.emit_file(output.ir)))
    fn entry(name : String) -> @ir.FQName {
      output.entries.filter(e => e.local_name.to_canonical() == name)[0]
    }
    if kind == "foundation" {
      for flag in [false, true] {
        guard @backend.call_entry(runtime, entry("choose"), [
            @scheme.Boolean(flag),
            @scheme.Tagged("morphir/SDK:int#int32", [
              @scheme.integer("-2147483648"),
            ]),
            @scheme.Tagged("morphir/SDK:int#int32", [
              @scheme.integer("2147483647"),
            ]),
          ])
          is Tagged(_, [Number(Integer(n))]) else {
          fail("Int32 result")
        }
        assert_eq(
          n.to_string(),
          if flag {
            "-2147483648"
          } else {
            "2147483647"
          },
        )
      }
    } else if kind == "strings" {
      assert_eq(
        @backend.call_entry(runtime, entry("greet"), [@scheme.Text("😀")]).as_text(),
        "Hello, 😀",
      )
      for enabled in [false, true] {
        assert_eq(
          @backend.call_entry(runtime, entry("welcome"), [
            @scheme.Text("Morphir"),
            @scheme.Boolean(enabled),
          ]).as_text(),
          if enabled {
            "Hello, Morphir"
          } else {
            ""
          },
        )
      }
      assert_eq(
        @backend.call_entry(runtime, entry("escapes"), []).as_text(),
        "😀́AA\n",
      )
      guard @backend.call_entry(runtime, entry("same"), [
          @scheme.Text("é"),
          @scheme.Text("é"),
        ])
        is Boolean(equal) else {
        fail("Bool result")
      }
      assert_false(equal)
    } else if kind == "bounded" {
      assert_eq(
        @backend.call_entry(runtime, entry("join"), [
          @scheme.Text("a"),
          @scheme.Text("😀"),
        ]).as_text(),
        "a😀",
      )
      guard @backend.call_entry(runtime, entry("short"), []) is Boolean(value) else {
        fail("Bool result")
      }
      assert_false(value)
      for name in ["order"] {
        try {
          ignore(@backend.call_entry(runtime, entry(name), []))
          fail("Expected bound refusal")
        } catch {
          @scheme.Domain(code, _) => assert_eq(code, "sdk.out_of_range")
          error => raise error
        }
      }
    }
    if kind == "ordered" {
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
          guard @backend.call_entry(runtime, entry(name), [
              @scheme.Text(a),
              @scheme.Text(b),
            ])
            is Boolean(actual) else {
            fail("Expected Bool")
          }
          assert_eq(actual, expected)
        }
        guard @backend.call_entry(runtime, entry("choose"), [
            @scheme.Text(a),
            @scheme.Text(b),
            @scheme.Tagged("morphir/SDK:int#int32", [
              @scheme.integer("-2147483648"),
            ]),
            @scheme.Tagged("morphir/SDK:int#int32", [
              @scheme.integer("2147483647"),
            ]),
          ])
          is Tagged(_, [Number(Integer(n))]) else {
          fail("Expected Int32")
        }
        assert_eq(
          n.to_string(),
          if order < 0 {
            "-2147483648"
          } else {
            "2147483647"
          },
        )
      }
      for units in [[55296], [56320], [56320, 55296], [55296, 97]] {
        let invalid = @scheme.Tagged("sdk-text", [
          @scheme.Vector(units.map(u => @scheme.integer(u.to_string()))),
        ])
        for args in [[invalid, @scheme.Text("")], [@scheme.Text(""), invalid]] {
          try {
            ignore(@backend.call_entry(runtime, entry("lt"), args))
            fail("Expected malformed UTF-16 refusal")
          } catch {
            @scheme.Domain(code, _) =>
              assert_eq(code, "sdk.unrepresentable_text")
            error => raise error
          }
        }
      }
    } else if kind == "orderedbounded" {
      for
        (name, fragment) in [
          ("first", "concatenation"),
          ("second", "code-unit limit"),
          ("eager", "code-unit limit"),
        ] {
        try {
          ignore(@backend.call_entry(runtime, entry(name), []))
          fail("Expected ordered bound refusal")
        } catch {
          @scheme.Domain(code, detail) => {
            assert_eq(code, "sdk.out_of_range")
            assert_true(detail.contains(fragment))
          }
          error => raise error
        }
      }
      guard @backend.call_entry(runtime, entry("short"), []) is Boolean(actual) else {
        fail("Expected Bool")
      }
      assert_false(actual)
    }
    if model_id == "supported" {
      for
        (name, enabled, expected) in [
          ("Morphir", true, "-2147483648"),
          ("Morphir", false, "2147483647"),
          ("😀", true, "2147483647"),
        ] {
        guard @backend.call_entry(runtime, entry("choose-for"), [
            @scheme.Text(name),
            @scheme.Boolean(enabled),
            @scheme.Tagged("morphir/SDK:int#int32", [
              @scheme.integer("-2147483648"),
            ]),
            @scheme.Tagged("morphir/SDK:int#int32", [
              @scheme.integer("2147483647"),
            ]),
          ])
          is Tagged(_, [Number(Integer(n))]) else {
          fail("Mixed Int32 result")
        }
        assert_eq(n.to_string(), expected)
      }
    } else if model_id == "supportedbool" {
      for a in [false, true] {
        for b in [false, true] {
          for
            (name, expected) in [
              ("both", a && b),
              ("either", a || b),
              ("equal", a == b),
              ("unequal", a != b),
            ] {
            guard @backend.call_entry(runtime, entry(name), [
                @scheme.Boolean(a),
                @scheme.Boolean(b),
              ])
              is Boolean(actual) else {
              fail("Bool result")
            }
            assert_eq(actual, expected)
          }
          guard @backend.call_entry(runtime, entry("shadow"), [
              @scheme.Boolean(a),
            ])
            is Boolean(actual) else {
            fail("Bool result")
          }
          assert_eq(actual, a)
        }
      }
      guard @backend.call_entry(runtime, entry("yes"), []) is Boolean(actual) else {
        fail("Bool result")
      }
      assert_true(actual)
    }
    models.push(
      (
        {
          "id": id,
          "profile": if id.has_prefix("current") {
            @frontend.CURRENT_LIBRARY_PROFILE
          } else if id.has_prefix("supported") {
            @frontend.SUPPORTED_LIBRARY_PROFILE
          } else if id == "foundation" {
            @frontend.TYPED_FOUNDATION_PROFILE
          } else {
            @frontend.STRING_LIBRARY_PROFILE
          },
          "source": source,
          "module": generated.project.module_name,
          "symbols": generated.symbols.map(s => {
            (
              {
                "fqname": s.fqname,
                "function": s.generated_name,
                "public": s.public,
              } : Json)
          }),
          "artifacts": generated.artifacts.map(a => {
            (
              {
                "path": a.path,
                "content": match a.content {
                  Text(text) => Json::string(text)
                  Binary(bytes) =>
                    Json::array(
                      bytes
                      .to_array()
                      .map(b => Json::number(b.to_int().to_double())),
                    )
                },
              } : Json)
          }),
          "sdkProfile": generated.project.dependencies[0].api_profile,
        } : Json),
    )
  }
  println(
    ({ "models": models, "parser": @frontend.PARSER_VERSION } : Json).stringify(),
  )
}
