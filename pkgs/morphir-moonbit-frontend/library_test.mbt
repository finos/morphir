///|
fn library_failure(
  source : String,
  limits~ : @frontend.LibraryLimits = @frontend.LibraryLimits::default(),
) -> @frontend.Diagnostic raise {
  try {
    ignore(@frontend.compile_library(input(source), limits~))
    fail("Expected library failure")
  } catch {
    @frontend.Invalid(diagnostic) => diagnostic
    error => raise error
  }
}

///|
fn library_result(
  output : @frontend.LibraryOutput,
  entry : @ir.FQName,
  arguments : Array[Bool],
) -> Bool raise {
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  ignore(runtime.eval(@backend.emit_file(output.ir)))
  guard @backend.call_entry(
      runtime,
      entry,
      arguments.map(arg => @scheme.Value::Boolean(arg)),
    )
    is Boolean(value) else {
    fail("Expected Boolean outcome")
  }
  value
}

///|
fn library_generated(
  output : @frontend.LibraryOutput,
) -> @generator.Output raise {
  @generator.generate({
    unit_id: output.unit_id,
    ir: output.ir,
    metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
    annotations: output.annotations,
    provenance: output.provenance,
  })
}

///|
test "library forward calls, private helpers and zero argument entries have typed IR" {
  let output = @frontend.compile_library(
    input(
      "pub fn decide(a : Bool, b : Bool, c : Bool) -> Bool { let allowed : Bool = ready(a, b); allowed && !c }\n" +
      "pub fn default_ready() -> Bool { ready(true, false) }\n" +
      "fn ready(a : Bool, b : Bool) -> Bool { a || b }",
    ),
  )
  assert_eq(output.entries.length(), 2)
  let sorted = output.entries.map(e => e.to_canonical())
  sorted.sort()
  assert_eq(output.entries.map(e => e.to_canonical()), sorted)
  let generated = library_generated(output)
  assert_eq(generated.symbols.length(), 3)
  assert_eq(generated.symbols.filter(s => s.public).length(), 2)
  assert_eq(@ir_json.read(@ir_json.write(output.ir)), output.ir)
  for a in [false, true] {
    for b in [false, true] {
      for c in [false, true] {
        assert_eq(
          library_result(output, output.entries[0], [a, b, c]),
          (a || b) && !c,
        )
      }
    }
  }
  assert_true(library_result(output, output.entries[1], []))
}

///|
test "sequential shadowing and branch scopes preserve preceding binding identities" {
  let output = @frontend.compile_library(
    input(
      "pub fn f(x : Bool) -> Bool { let x = !x; let y : Bool = x; let x = !x; if y { let x = !x; x } else { x } }",
    ),
  )
  assert_true(library_result(output, output.entries[0], [false]))
  assert_true(library_result(output, output.entries[0], [true]))
  ignore(library_generated(output))
  assert_eq(
    library_failure("pub fn f() -> Bool { let x = x; x }").code,
    "moonbit_frontend.unknown_reference",
  )
  assert_eq(
    library_failure(
      "pub fn f() -> Bool { let y = if true { let x = true; x } else { false }; x }",
    ).code,
    "moonbit_frontend.unknown_reference",
  )
}

///|
test "all private libraries have no inferred public entry" {
  let output = @frontend.compile_library(
    input("fn f() -> Bool { g() }\nfn g() -> Bool { true }"),
  )
  assert_true(output.entries.is_empty())
  let generated = library_generated(output)
  assert_eq(generated.symbols.length(), 2)
  assert_true(generated.symbols.all(s => !s.public))
}

///|
test "library grammar and resolution reject unsupported forms deterministically" {
  for
    (source, code) in [
      ("", "declaration_count"),
      ("priv fn f() -> Bool { true }", "unsupported_visibility"),
      (
        "pub fn f() -> Bool { true }\nfn f() -> Bool { false }", "duplicate_function",
      ),
      ("pub fn f(x : Bool, x : Bool) -> Bool { x }", "duplicate_parameter"),
      ("pub fn f(x~ : Bool) -> Bool { x }", "unsupported_parameters"),
      ("pub fn f(x : Int) -> Bool { true }", "unsupported_type"),
      ("pub fn f() -> Bool { g }\nfn g() -> Bool { true }", "function_value"),
      ("pub fn f() -> Bool { g() }", "unknown_function"),
      (
        "pub fn f(g : Bool) -> Bool { g() }\nfn g() -> Bool { true }", "not_callable",
      ),
      ("pub fn f() -> Bool { g() }\nfn g(x : Bool) -> Bool { x }", "call_arity"),
      (
        "pub fn f() -> Bool { g(true, false) }\nfn g(x : Bool) -> Bool { x }", "call_arity",
      ),
      (
        "pub fn f() -> Bool { g(x=true) }\nfn g(x : Bool) -> Bool { x }", "unsupported_arguments",
      ),
      ("pub fn f() -> Bool { @other.g() }", "qualified_reference"),
      ("pub fn f() -> Bool { let x : Int = true; x }", "unsupported_type"),
      (
        "pub fn f() -> Bool { let (x, y) = (true, false); x }", "unsupported_binding",
      ),
      ("pub fn f() -> Bool { let mut x = true; x }", "unsupported_expression"),
      ("pub fn f() -> Bool { true; false }", "unsupported_expression"),
      ("pub fn f() -> Bool { fn g() { true }; g() }", "unsupported_expression"),
      (
        "pub fn f() -> Bool { true }\nfn hidden() -> Bool { missing }", "unknown_reference",
      ),
      ("pub fn f() -> Bool { f() }", "recursive_call"),
      (
        "pub fn f() -> Bool { true }\nfn g() -> Bool { if false { h() } else { true } }\nfn h() -> Bool { g() }",
        "recursive_call",
      ),
    ] {
    let diagnostic = library_failure(source)
    assert_eq(diagnostic.code, "moonbit_frontend." + code, msg=source)
    if code != "declaration_count" {
      assert_true(diagnostic.source is Some(_))
    }
  }
}

///|
test "library budgets cover aggregate expressions and calls and per function lets" {
  let defaults = @frontend.LibraryLimits::default()
  for
    (source, limits, code) in [
      ("fn f() -> Bool { true }", { ..defaults, max_bytes: 1, }, "byte_limit"),
      (
        "fn f() -> Bool { true }\nfn g() -> Bool { false }",
        { ..defaults, max_functions: 1, },
        "declaration_count",
      ),
      (
        "fn f(x : Bool) -> Bool { x }",
        { ..defaults, max_parameters: 0, },
        "parameter_limit",
      ),
      (
        "fn f() -> Bool { let x = true; x }",
        { ..defaults, max_lets: 0, },
        "let_limit",
      ),
      (
        "fn f() -> Bool { true }\nfn g() -> Bool { false }",
        { ..defaults, max_expressions: 1, },
        "expression_limit",
      ),
      (
        "fn f() -> Bool { g() }\nfn g() -> Bool { true }",
        { ..defaults, max_calls: 0, },
        "call_limit",
      ),
      (
        "fn f() -> Bool { !true }",
        { ..defaults, max_depth: 0, },
        "expression_limit",
      ),
      (
        "fn f() -> Bool { g() }\nfn g() -> Bool { true }",
        { ..defaults, max_call_depth: 0, },
        "call_depth_limit",
      ),
      (
        "fn f() -> Bool { true }",
        { ..defaults, max_functions: 65, },
        "invalid_limits",
      ),
    ] {
    assert_eq(library_failure(source, limits~).code, "moonbit_frontend." + code)
  }
  // Distinct repeated calls are sites, but a single dependency edge for graph depth.
  let source = "fn f() -> Bool { g() && g() }\nfn g() -> Bool { true }"
  ignore(
    @frontend.compile_library(input(source), limits={
      ..defaults,
      max_calls: 2,
      max_call_depth: 1,
    }),
  )
  assert_eq(
    library_failure(source, limits={ ..defaults, max_calls: 1, }).code,
    "moonbit_frontend.call_limit",
  )
}

///|
test "library native Ion origins preserve local binding and call annotations" {
  let output = @frontend.compile_library(
    input(
      "// λ😀\npub fn f(x : Bool) -> Bool { let y = !x; g(y) }\nfn g(x : Bool) -> Bool { x }",
    ),
  )
  assert_eq(output.metadata.length(), 4)
  let generated = library_generated(output)
  let artifact = generated.artifacts.filter(a => a.path == "symbols.10n")[0]
  guard artifact.content is @generator.Binary(bytes) else {
    fail("Expected native Ion")
  }
  let stored = @ion_binary.read_binary_value(bytes[:])
  assert_eq(@ion_binary.write_binary_value(stored), bytes)
  guard stored.kind() is @ion.Struct(fields) else {
    fail("Expected symbol storage")
  }
  let by_name = Map::from_array(
    fields.map(f => (f.name().text().unwrap(), f.value())),
  )
  assert_true(
    by_name["source_provenance"].equals(@ion.IonValue::list(output.provenance)),
  )
  guard by_name["metadata"].kind() is @ion.List(entries) else {
    fail("Expected origins")
  }
  let expected_by_id = Map::from_array(
    output.metadata.map(m => (m.node_id, m.data)),
  )
  assert_eq(entries.length(), expected_by_id.length())
  for entry in entries {
    guard entry.kind() is @ion.Struct(origin_fields) else {
      fail("Expected origin")
    }
    guard origin_fields[0].value().kind() is @ion.String(id) else {
      fail("Expected node ID")
    }
    assert_true(origin_fields[1].value().equals(expected_by_id[id]))
  }
  guard output.metadata[1].data.kind() is @ion.Struct(body_fields) else {
    fail("Expected body metadata")
  }
  guard body_fields[1].value().kind() is @ion.List(nodes) else {
    fail("Expected local origins")
  }
  assert_eq(nodes.length(), 2)
  guard nodes[0].kind() is @ion.Struct(binding_fields) else {
    fail("Expected binding origin")
  }
  guard binding_fields[0].value().kind() is @ion.Struct(binding_origin) else {
    fail("Expected source spelling")
  }
  assert_true(binding_origin[0].value().equals(@ion.IonValue::string("y")))
}

///|
test "call graph depth is bounded without expanding a diamond of shared callees" {
  let source = StringBuilder()
  source.write_string("pub fn f0(x : Bool) -> Bool { f1(x) == f1(x) }\n")
  for i = 1; i < 32; i = i + 1 {
    source.write_string(
      "fn f" +
      i.to_string() +
      "(x : Bool) -> Bool { f" +
      (i + 1).to_string() +
      "(x) == f" +
      (i + 1).to_string() +
      "(x) }\n",
    )
  }
  source.write_string("fn f32(x : Bool) -> Bool { x }")
  let output = @frontend.compile_library(input(source.to_string()))
  guard output.ir.distribution is Library(_, _, package_def) else {
    fail("Expected library")
  }
  assert_eq(package_def.modules.values().collect()[0].value.values.length(), 33)
  // Generation remains linear in source size; evaluation would be exponential.
  let generated = library_generated(output)
  assert_eq(generated.symbols.length(), 33)
  let artifact = generated.artifacts.filter(a => a.path == "library.mbt")[0]
  guard artifact.content is @generator.Text(text) else {
    fail("Expected source")
  }
  assert_true(text.length() < 100000)
  assert_eq(
    library_failure(source.to_string(), limits={
      ..@frontend.LibraryLimits::default(),
      max_call_depth: 31,
    }).code,
    "moonbit_frontend.call_depth_limit",
  )
}

///|
test "declaration and expression bounds accept their exact limits" {
  let source = StringBuilder()
  for i = 0; i < 64; i = i + 1 {
    source.write_string("fn f" + i.to_string() + "() -> Bool { true }\n")
  }
  let output = @frontend.compile_library(input(source.to_string()), limits={
    ..@frontend.LibraryLimits::default(),
    max_expressions: 64,
  })
  assert_eq(library_generated(output).symbols.length(), 64)
  assert_eq(
    library_failure(source.to_string(), limits={
      ..@frontend.LibraryLimits::default(),
      max_expressions: 63,
    }).code,
    "moonbit_frontend.expression_limit",
  )
  source.write_string("fn excess() -> Bool { true }")
  assert_eq(
    library_failure(source.to_string()).code,
    "moonbit_frontend.declaration_count",
  )
  // A call visits both Apply and its direct callee identifier, plus the leaf body.
  let call = "fn f() -> Bool { g() }\nfn g() -> Bool { true }"
  ignore(
    @frontend.compile_library(input(call), limits={
      ..@frontend.LibraryLimits::default(),
      max_expressions: 3,
    }),
  )
  assert_eq(
    library_failure(call, limits={
      ..@frontend.LibraryLimits::default(),
      max_expressions: 2,
    }).code,
    "moonbit_frontend.expression_limit",
  )
}
