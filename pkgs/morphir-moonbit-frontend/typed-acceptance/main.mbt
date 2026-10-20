///|
/// Add explicit SDK conversion calls to the floating model for generated
/// consumer qualification. The original source fixture covers arithmetic;
/// these IR entries exercise the versioned SDK extension directly.
fn add_float_conversion_cases(
  output : @frontend.LibraryOutput,
) -> @frontend.LibraryOutput raise {
  guard output.ir.distribution
    is Library(package_name, dependencies, package_def) else {
    fail("Expected floating library")
  }
  let module_path = @ir.Path::parse("main")
  let module_entry = package_def.modules[module_path]
  let values = module_entry.value.values.copy()
  let entries = output.entries.copy()
  let int = @ir.Type::Reference(
    @ir.TypeAttributes::default(),
    @ir.FQName::parse("morphir/SDK:basics#int"),
    [],
  )
  let float64 = @ir.Type::Reference(
    @ir.TypeAttributes::default(),
    @ir.FQName::parse("morphir/SDK:basics#float"),
    [],
  )
  let float32 = @ir.Type::Reference(
    @ir.TypeAttributes::default(),
    @ir.FQName::parse("morphir/moonbit-source:float32#float32"),
    [],
  )
  fn maybe(t : @ir.Type) -> @ir.Type raise {
    @ir.Type::Reference(
      @ir.TypeAttributes::default(),
      @ir.FQName::parse("morphir/SDK:maybe#maybe"),
      [t],
    )
  }
  for
    (name, input, result) in [
      ("to-f32-rounded", int, float32),
      ("to-f32-exact", int, maybe(float32)),
      ("to-f64-rounded", int, float64),
      ("to-f64-exact", int, maybe(float64)),
      ("from-f32-exact", float32, maybe(int)),
      ("from-f32-truncated", float32, maybe(int)),
      ("from-f64-exact", float64, maybe(int)),
      ("from-f64-rounded", float64, maybe(int)),
    ] {
    let sdk_name = if name.has_prefix("to-") {
      "to-float" + name[4:].to_owned()
    } else {
      "from-float" + name[6:].to_owned()
    }
    let signature = @ir.Type::Function(
      @ir.TypeAttributes::default(),
      input,
      result,
    )
    let reference = @ir.Value::Reference(
      { ..@ir.ValueAttributes::default(), inferred_type: Some(signature), },
      @ir.FQName::parse("morphir/SDK:int#" + sdk_name),
    )
    let argument = @ir.Value::Variable(
      { ..@ir.ValueAttributes::default(), inferred_type: Some(input), },
      @ir.Name::parse("value"),
    )
    let body = @ir.Value::Apply(
      { ..@ir.ValueAttributes::default(), inferred_type: Some(result), },
      reference,
      argument,
    )
    values[@ir.Name::parse(name)] = {
      access: @ir.Access::Public,
      value: {
        doc: Some("Explicit SDK numeric conversion qualification"),
        value: @ir.ValueDefinition::ExpressionBody(
          [(@ir.Name::parse("value"), input)],
          result,
          body,
        ),
      },
    }
    entries.push(
      @ir.FQName::parse(package_name.to_canonical() + ":main#" + name),
    )
  }
  let modules = package_def.modules.copy()
  modules[module_path] = {
    ..module_entry,
    value: { ..module_entry.value, values, },
  }
  {
    ..output,
    ir: @ir.IRFile::new(
      @ir.Distribution::Library(package_name, dependencies, { modules, }),
      format_version=output.ir.format_version,
    ),
    entries,
  }
}

///|
// Independently rounded from mpmath 1.3.0 at 100 decimal digits. Tolerances
// belong to each function contract, never to integer or basic IEEE operations.
fn math_references() -> Array[(String, Double, Int32)] {
  [
    ("root-two", 1.4142135623730951, 0),
    ("root-half", 0.7071067811865476, 0),
    ("sine-one", 0.8414709848078965, 4),
    ("cosine-one", 0.5403023058681398, 4),
    ("sine-hundred", -0.5063656411097588, 4),
    ("cosine-hundred", 0.8623188722876839, 4),
    ("power-quarter", 1.7782794100389228, 4),
    ("power-integer", -8.0, 0),
    ("absolute", 3.5, 0),
    ("root-zero", -0.0, 0),
    ("sine-zero", -0.0, 0),
    ("absolute-zero", -0.0, 0),
    ("cosine-zero", 1.0, 0),
    ("power-nan-zero", 1.0, 0),
  ]
}

///|
fn math_categories() -> Array[(String, String)] {
  [
    ("root-invalid", "nan"),
    ("sine-invalid", "nan"),
    ("cosine-invalid", "nan"),
    ("power-invalid", "nan"),
    ("absolute-invalid", "nan"),
    ("root-infinity", "positive-infinity"),
    ("power-infinity", "positive-infinity"),
  ]
}

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
  let library_cases = sources +
    [
      (
        "supported", "pub fn choose_for(name : String, enabled : Bool, first : Int32, second : Int) -> Int32 { let greeting : String = welcome(name, enabled); if greeting == \"Hello, Morphir\" { identity(first) } else { identity(second) } }\npub fn welcome(name : String, enabled : Bool) -> String { if enabled { \"Hello, \" + name } else { \"\" } }\nfn identity(value : Int32) -> Int { (value : Int32) }",
      ),
      (
        "supportedbool", "pub fn both(a : Bool, b : Bool) -> Bool { let a : Bool = identity(a); a && b }\npub fn either(a : Bool, b : Bool) -> Bool { identity(a) || identity(b) }\npub fn equal(a : Bool, b : Bool) -> Bool { identity(a) == identity(b) }\npub fn unequal(a : Bool, b : Bool) -> Bool { identity(a) != identity(b) }\npub fn shadow(a : Bool) -> Bool { let a = !a; let a : Bool = !a; (a : Bool) }\npub fn yes() -> Bool { identity(true) }\nfn identity(a : Bool) -> Bool { a }",
      ),
    ]
  let cases = library_cases +
    [
      (
        "numeric", "pub fn overflow() -> Int32 { 2147483647 + 1 }\npub fn multiply_wrap() -> Int32 { 65536 * 65536 }\npub fn underflow() -> Int32 { -2147483648 - 1 }\npub fn total(a : Int32, b : Int32) -> Int32 { let subtotal = a * b; if subtotal > 1000 { subtotal - 100 } else { subtotal } }\npub fn before(a : Int32, b : Int32) -> Bool { a < b }\npub fn after(a : Int32, b : Int32) -> Bool { a > b }\npub fn same(a : Int32, b : Int32) -> Bool { a <= b && a >= b && a == b && !(a != b) }",
      ),
      (
        "integer", "pub fn wrap_i16() -> Int16 { 32767 + 1 }\npub fn wrap_i64() -> Int64 { 9223372036854775807L + 1L }\npub fn wrap_byte() -> Byte { 255 + 1 }\npub fn wrap_u16() -> UInt16 { 65535 + 1 }\npub fn wrap_u32() -> UInt32 { 4294967295U + 1U }\npub fn wrap_u64() -> UInt64 { 18446744073709551615UL + 1UL }\npub fn grow() -> BigInt { 18446744073709551616N + 1N }",
      ),
      (
        "float", "pub fn rounded() -> Float { 16777216.0F + 1.0F }\npub fn chained() -> Float { let a : Float = 16777216.0F + 1.0F; a + 1.0F }\npub fn scaled() -> Float { 1.5F * 2.0F / 3.0F }\npub fn wider() -> Double { 9007199254740992.0 + 2.0 }\npub fn identity(value : Float) -> Float { value }\npub fn negative_zero() -> Float { -0.0F }\npub fn tiny() -> Float { 1.401298464324817e-45F }\npub fn infinity() -> Float { 1.0F / 0.0F }\npub fn invalid() -> Float { 0.0F / 0.0F }\npub fn double_zero() -> Double { -0.0 }\npub fn double_tiny() -> Double { 5.0e-324 }\npub fn double_infinity() -> Double { 1.0 / 0.0 }\npub fn double_invalid() -> Double { 0.0 / 0.0 }",
      ),
      (
        "indexed", "pub fn count(s : String) -> Int32 { s.length() }\npub fn cut(s : String, start : Int32, end : Int32) -> String { s[start:end].to_owned() }\npub fn count_cut(s : String, start : Int32, end : Int32) -> Int32 { cut(s, start, end).length() + start }",
      ),
      ("pinnedsdk", "pub fn invert(flag : Bool) -> Bool { @basics.not_(flag) }"),
      (
        "math", "pub fn root_two() -> Double { @basics.sqrt(2.0) }\npub fn root_half() -> Double { @basics.sqrt(0.5) }\npub fn sine_one() -> Double { @basics.sin(1.0) }\npub fn cosine_one() -> Double { @basics.cos(1.0) }\npub fn sine_hundred() -> Double { @basics.sin(100.0) }\npub fn cosine_hundred() -> Double { @basics.cos(100.0) }\npub fn power_quarter() -> Double { @basics.power_float(10.0, 0.25) }\npub fn power_integer() -> Double { @basics.power_float(-2.0, 3.0) }\npub fn absolute() -> Double { @basics.abs_float(-3.5) }\npub fn root_zero() -> Double { @basics.sqrt(-0.0) }\npub fn sine_zero() -> Double { @basics.sin(-0.0) }\npub fn absolute_zero() -> Double { @basics.abs_float(-0.0) }\npub fn cosine_zero() -> Double { @basics.cos(-0.0) }\npub fn power_nan_zero() -> Double { @basics.power_float(0.0 / 0.0, 0.0) }\npub fn root_invalid() -> Double { @basics.sqrt(-1.0) }\npub fn sine_invalid() -> Double { @basics.sin(1.0 / 0.0) }\npub fn cosine_invalid() -> Double { @basics.cos(1.0 / 0.0) }\npub fn power_invalid() -> Double { @basics.power_float(-1.0, 0.5) }\npub fn absolute_invalid() -> Double { @basics.abs_float(0.0 / 0.0) }\npub fn root_infinity() -> Double { @basics.sqrt(1.0 / 0.0) }\npub fn power_infinity() -> Double { @basics.power_float(0.0, -1.0) }\npub fn mixed(label : String, enabled : Bool, count : Int32, amount : Double) -> Double { let yes = @basics.not_(enabled); if yes && label.length() > count { @basics.sqrt(amount * amount) } else { @basics.abs_float(-amount) } }",
      ),
      (
        "ordered", "pub fn lt(a : String, b : String) -> Bool { identity(a) < identity(b) }\npub fn le(a : String, b : String) -> Bool { a <= b }\npub fn gt(a : String, b : String) -> Bool { a > b }\npub fn ge(a : String, b : String) -> Bool { a >= b }\npub fn choose(a : String, b : String, yes : Int32, no : Int) -> Int32 { let before : Bool = lt(a, b); if before { yes } else { no } }\nfn identity(s : String) -> String { s }",
      ),
      (
        "orderedbounded", "fn growth() -> String { \"abc\" + \"def\" }\nfn literal() -> String { \"123456\" }\npub fn first() -> Bool { growth() < literal() }\npub fn second() -> Bool { literal() >= growth() }\npub fn eager() -> Bool { \"\" < literal() }\npub fn short() -> Bool { false && first() }",
      ),
    ]
  let sdk_source = "pub fn rounded(v : Double) -> @integer.Integer raise @sdk.SdkError { @basics.round(v) }\npub fn floored(v : Double) -> @integer.Integer raise @sdk.SdkError { @basics.floor(v) }\npub fn ceiling(v : Double) -> @integer.Integer raise @sdk.SdkError { @basics.ceiling(v) }\npub fn truncated(v : Double) -> @integer.Integer raise @sdk.SdkError { @basics.truncate(v) }\npub fn floating(v : @integer.Integer) -> Double { @basics.to_float(v) }\npub fn absolute(v : @integer.Integer) -> @integer.Integer { @basics.abs_int(v) }\npub fn exact(v : Double) -> @integer.Integer? { @int.from_float64_exact(v) }\npub fn trunc(v : Double) -> @integer.Integer? { @int.from_float64_truncated(v) }\npub fn floor(v : Double) -> @integer.Integer? { @int.from_float64_floor(v) }\npub fn ceil(v : Double) -> @integer.Integer? { @int.from_float64_ceiling(v) }\npub fn round(v : Double) -> @integer.Integer? { @int.from_float64_rounded(v) }\npub fn to_exact(v : @integer.Integer) -> Double? { @int.to_float64_exact(v) }\npub fn to_rounded(v : @integer.Integer) -> Double { @int.to_float64_rounded(v) }\npub fn optional(v : @integer.Integer?, flag : Bool) -> @integer.Integer? { if flag { identity(v) } else { v } }\nfn identity(v : @integer.Integer?) -> @integer.Integer? { v }\npub fn before(a : @integer.Integer, b : @integer.Integer) -> Bool { a < b && a != b }"
  let cases = cases +
    [("conversions", sdk_source), ("decimal", decimal_source())]
  let models = []
  for (id, source) in cases {
    let source = "/// Qualification fixture documentation.\n///\n/// Preserve **Markdown** and λ😀.\n" +
      source
    let model_id = id
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
    let output = @frontend.compile_library(
      channel=@frontend.Experimental,
      input,
      max_string_code_units=if kind == "bounded" || kind == "orderedbounded" {
        5
      } else {
        1048576
      },
    )
    let output = if kind == "float" {
      add_float_conversion_cases(output)
    } else {
      output
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
    } else if kind == "numeric" {
      for
        (name, expected) in [
          ("overflow", "-2147483648"),
          ("multiply-wrap", "0"),
          ("underflow", "2147483647"),
        ] {
        guard @backend.call_entry(runtime, entry(name), [])
          is Tagged("morphir/SDK:int#int32", [Number(Integer(value))]) else {
          fail("Expected numeric Int32 wrapper")
        }
        assert_eq(value.to_string(), expected)
      }
      guard @backend.call_entry(runtime, entry("total"), [
          @scheme.Tagged("morphir/SDK:int#int32", [@scheme.integer("3")]),
          @scheme.Tagged("morphir/SDK:int#int32", [@scheme.integer("400")]),
        ])
        is Tagged("morphir/SDK:int#int32", [Number(Integer(total))]) else {
        fail("Expected numeric total")
      }
      assert_eq(total.to_string(), "1100")
      let number = fn(n : String) raise {
        @scheme.Tagged("morphir/SDK:int#int32", [@scheme.integer(n)])
      }
      guard @backend.call_entry(runtime, entry("after"), [
          number("1"),
          number("-1"),
        ])
        is Boolean(after) else {
        fail("Expected Int32 comparison")
      }
      assert_true(after)
      guard @backend.call_entry(runtime, entry("same"), [
          number("2"),
          number("2"),
        ])
        is Boolean(same) else {
        fail("Expected Int32 equality")
      }
      assert_true(same)
    } else if kind == "float" {
      fn observed(name : String) -> Double raise {
        guard @backend.call_entry(runtime, entry(name), [])
          is Number(Real(value)) else {
          fail("Expected floating observation")
        }
        value
      }
      assert_eq(observed("rounded"), 16777216.0)
      assert_eq(observed("chained"), 16777216.0)
      assert_eq(observed("scaled"), 1.0)
      assert_eq(observed("wider"), 9007199254740994.0)
      guard @backend.call_entry(runtime, entry("identity"), [
          @scheme.Value::Number(@scheme.Number::Real(16777217.0)),
        ])
        is Number(Real(boundary)) else {
        fail("Expected Float public boundary")
      }
      assert_eq(boundary, 16777216.0)
      assert_eq(
        observed("negative-zero").reinterpret_as_uint64(),
        9223372036854775808UL,
      )
      assert_true(observed("tiny") > 0.0 && observed("tiny") < 1.0e-44)
      assert_true(observed("infinity").is_inf())
      assert_true(observed("invalid").is_nan())
      assert_eq(
        observed("double-zero").reinterpret_as_uint64(),
        9223372036854775808UL,
      )
      assert_eq(observed("double-tiny").reinterpret_as_uint64(), 1UL)
      assert_true(observed("double-infinity").is_inf())
      assert_true(observed("double-invalid").is_nan())
    } else if kind == "indexed" {
      guard @backend.call_entry(runtime, entry("count"), [
          @scheme.Text("A😀é"),
        ])
        is Tagged("morphir/SDK:int#int32", [Number(Integer(length))]) else {
        fail("Expected indexed length")
      }
      assert_eq(length.to_string(), "5")
      assert_eq(
        @backend.call_entry(runtime, entry("cut"), [
          @scheme.Text("A😀é"),
          @scheme.Tagged("morphir/SDK:int#int32", [@scheme.integer("1")]),
          @scheme.Tagged("morphir/SDK:int#int32", [@scheme.integer("3")]),
        ]).as_text(),
        "😀",
      )
    } else if kind == "decimal" {
      for (name, args, expected) in decimal_references() {
        guard @backend.call_entry(
            runtime,
            entry(name),
            args.map(text => @scheme.Value::Text(text)),
          )
          is Tagged("decimal", [Text(actual)]) else {
          fail("Expected Decimal")
        }
        assert_eq(actual, expected, msg=name)
      }
      for (name, a, b, expected) in decimal_comparisons() {
        guard @backend.call_entry(runtime, entry(name), [
            @scheme.Text(a),
            @scheme.Text(b),
          ])
          is Boolean(actual) else {
          fail("Expected comparison")
        }
        assert_eq(actual, expected, msg=name)
      }
      for (name, args, code) in decimal_failures() {
        try {
          ignore(
            @backend.call_entry(
              runtime,
              entry(name),
              args.map(text => @scheme.Value::Text(text)),
            ),
          )
          fail("Expected checked Decimal failure")
        } catch {
          @scheme.Domain(actual, _) => assert_eq(actual, "sdk.decimal." + code)
          error => raise error
        }
      }
    } else if kind == "math" {
      fn observed(name : String) -> Double raise {
        guard @backend.call_entry(runtime, entry(name), [])
          is Number(Real(value)) else {
          fail("Expected math result")
        }
        value
      }
      for (name, expected, ulps) in math_references() {
        let actual = observed(name).reinterpret_as_uint64()
        let wanted = expected.reinterpret_as_uint64()
        let distance = if actual > wanted {
          actual - wanted
        } else {
          wanted - actual
        }
        assert_true(distance <= ulps.to_uint64(), msg=name)
      }
      for (name, category) in math_categories() {
        let actual = observed(name)
        assert_true(
          if category == "nan" {
            actual.is_nan()
          } else {
            actual == 1.0 / 0.0
          },
          msg=name,
        )
      }
      guard @backend.call_entry(runtime, entry("mixed"), [
          @scheme.Text("A😀"),
          @scheme.Boolean(false),
          @scheme.Tagged("morphir/SDK:int#int32", [@scheme.integer("1")]),
          @scheme.Value::Number(@scheme.Number::Real(3.0)),
        ])
        is Number(Real(mixed)) else {
        fail("Expected mixed math")
      }
      assert_eq(mixed, 3.0)
    } else if kind == "pinnedsdk" {
      for flag in [false, true] {
        guard @backend.call_entry(runtime, entry("invert"), [
            @scheme.Boolean(flag),
          ])
          is Boolean(actual) else {
          fail("Expected pinned SDK Bool")
        }
        assert_eq(actual, !flag)
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
          "decimalReferences": if kind == "decimal" {
            decimal_references().map(row => {
              ({ "name": row.0, "args": row.1, "expected": row.2 } : Json)
            })
          } else {
            []
          },
          "decimalComparisons": if kind == "decimal" {
            decimal_comparisons().map(row => {
              (
                { "name": row.0, "a": row.1, "b": row.2, "expected": row.3 } :
                Json)
            })
          } else {
            []
          },
          "decimalFailures": if kind == "decimal" {
            decimal_failures().map(row => {
              ({ "name": row.0, "args": row.1, "code": row.2 } : Json)
            })
          } else {
            []
          },
          "mathReferences": if kind == "math" {
            math_references().map(row => {
              ({ "name": row.0, "expected": row.1, "ulps": row.2 } : Json)
            })
          } else {
            []
          },
          "mathCategories": if kind == "math" {
            math_categories().map(row => {
              ({ "name": row.0, "category": row.1 } : Json)
            })
          } else {
            []
          },
          "profile": @frontend.EXPERIMENTAL_PROFILE,
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
          "driverArtifacts": if id == "float" || id == "decimal" {
            @generator.invocation_driver(
              generated,
              if id == "decimal" {
                output.entries.map(@ir.FQName::to_canonical)
              } else {
                [entry("identity").to_canonical()]
              },
            ).map(a => {
              guard a.content is Text(text) else {
                fail("Expected text invocation driver artifact")
              }
              ({ "path": a.path, "content": text } : Json)
            })
          } else {
            []
          },
          "sdkProfile": generated.project.dependencies[0].api_profile,
        } : Json),
    )
  }
  println(
    ({ "models": models, "parser": @frontend.PARSER_VERSION } : Json).stringify(),
  )
}
