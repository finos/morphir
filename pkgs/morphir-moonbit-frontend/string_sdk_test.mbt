///|
fn string_sdk_source() -> String {
  "pub fn empty(s : String) -> Bool { s.is_empty() }\n" +
  "pub fn has(s : String, needle : String) -> Bool { s.contains(needle) }\n" +
  "pub fn starts(s : String, prefix : String) -> Bool { s.has_prefix(prefix) }\n" +
  "pub fn ends(s : String, suffix : String) -> Bool { s.has_suffix(suffix) }\n" +
  "pub fn literal() -> Bool { \"a😀b\".contains(\"😀\") && !\"\".has_prefix(\"a\") }"
}

///|
fn string_sdk(
  source : String,
  channel~ : @frontend.SourceChannel = @frontend.Experimental,
  limit~ : Int32 = 1048576,
) -> @frontend.LibraryOutput raise {
  @frontend.compile_library(
    input(source),
    channel~,
    max_string_code_units=limit,
  )
}

///|
fn string_sdk_failure(
  source : String,
  channel~ : @frontend.SourceChannel = @frontend.Experimental,
  bindings~ : @frontend.PinnedSourceBindings? = None,
) -> @frontend.Diagnostic raise {
  try {
    ignore(@frontend.compile_library(input(source), channel~, bindings~))
    fail("Expected String SDK refusal: " + source)
  } catch {
    @frontend.Invalid(diagnostic) => diagnostic
    error => raise error
  }
}

///|
fn string_sdk_bool(
  runtime : @scheme.Runtime,
  output : @frontend.LibraryOutput,
  name : String,
  arguments : Array[String],
) -> Bool raise {
  let entry = output.entries.filter(e => e.local_name.to_canonical() == name)[0]
  guard @backend.call_entry(
      runtime,
      entry,
      arguments.map(text => @scheme.Value::Text(text)),
    )
    is Boolean(value) else {
    fail("Expected Bool from " + name)
  }
  value
}

///|
/// Hand-authored from the pinned MoonBit core contracts; the typed-source gate
/// checks the same rows against the original compiler.
fn string_sdk_rows() -> Array[(String, Array[String], Bool)] {
  [
    ("empty", [""], true),
    ("empty", ["a"], false),
    ("empty", ["😀"], false),
    ("empty", ["́"], false),
    ("has", ["", ""], true),
    ("has", ["abc", ""], true),
    ("has", ["", "a"], false),
    ("has", ["a😀b", "😀"], true),
    ("has", ["a😀b", "b"], true),
    ("has", ["😀", "😁"], false),
    ("has", ["é", "e"], false),
    ("has", ["é", "e"], true),
    ("has", ["é", "́"], true),
    ("starts", ["😀a", "😀"], true),
    ("starts", ["abc", ""], true),
    ("starts", ["", "a"], false),
    ("starts", ["ab", "abc"], false),
    ("starts", ["é", "e"], false),
    ("starts", ["é", "e"], true),
    ("ends", ["a😀", "😀"], true),
    ("ends", ["", ""], true),
    ("ends", ["abc", "abcd"], false),
    ("ends", ["é", "́"], true),
    ("ends", ["😁", "😀"], false),
  ]
}

///|
test "pinned String predicates follow MoonBit UTF-16 code-unit semantics" {
  let output = string_sdk(string_sdk_source())
  let runtime = string_runtime(output)
  for row in string_sdk_rows() {
    let (name, arguments, expected) = row
    assert_eq(string_sdk_bool(runtime, output, name, arguments), expected)
  }
  assert_true(string_sdk_bool(runtime, output, "literal", []))
  let generated = library_generated(output)
  assert_eq(generated.symbols.filter(s => s.public).length(), 5)
  guard generated.artifacts.filter(a => a.path == "library.mbt")[0].content
    is Text(text) else {
    fail("Expected generated library")
  }
  for
    call in [
      "@string.is_empty(", "@string.contains(", "@string.starts_with(", "@string.ends_with(",
    ] {
    assert_true(text.contains(call))
  }
  assert_eq(@ir_json.read(@ir_json.write(output.ir)), output.ir)
}

///|
test "String predicates bind the receiver first and apply the SDK needle first" {
  let output = string_sdk(
    "pub fn has(s : String, needle : String) -> Bool { s.contains(needle) }",
  )
  guard output.ir.distribution is Library(_, _, package_def) else {
    fail("Expected source library")
  }
  let definition = package_def.modules.values().collect()[0].value.values[@ir.Name::parse(
      "has",
    )].value.value
  // Two public String guards precede the call body.
  guard definition
    is ExpressionBody(
      _,
      _,
      @ir.Value::LetDefinition(
        _,
        _,
        _,
        @ir.Value::LetDefinition(
          _,
          _,
          _,
          @ir.Value::LetDefinition(
            _,
            receiver,
            ExpressionBody(_, _, @ir.Value::Variable(_, receiver_source)),
            @ir.Value::LetDefinition(
              _,
              needle,
              ExpressionBody(_, _, @ir.Value::Variable(_, needle_source)),
              @ir.Value::Apply(
                call_attrs,
                @ir.Value::Apply(
                  _,
                  @ir.Value::Reference(reference_attrs, canonical),
                  @ir.Value::Variable(_, first)
                ),
                @ir.Value::Variable(_, second)
              )
            )
          )
        )
      )
    ) else {
    fail("Expected source-ordered temporaries and a canonical SDK call")
  }
  assert_eq(receiver_source.to_canonical(), "s")
  assert_eq(needle_source.to_canonical(), "needle")
  assert_eq(first, needle)
  assert_eq(second, receiver)
  assert_eq(canonical.to_canonical(), "morphir/SDK:string#contains")
  for attrs in [call_attrs, reference_attrs] {
    guard attrs.extensions.get("moonbit-source-binding-v1")
      is Some(@ir.Data::Object(facts)) else {
      fail("Expected source binding facts")
    }
    assert_eq(facts["source_form"], @ir.Data::Text("string-method"))
    assert_eq(facts["source_name"], @ir.Data::Text("contains"))
    assert_eq(
      facts["source_package"],
      @ir.Data::Text(@frontend.MOONBIT_CORE_PACKAGE),
    )
    assert_eq(facts["source_tree"], @ir.Data::Text(@frontend.MOONBIT_CORE_TREE))
    assert_eq(
      facts["source_signature"],
      @ir.Data::Text("(String, StringView) -> Bool"),
    )
    assert_eq(
      facts["argument_coercion"],
      @ir.Data::Text("pinned-implicit-string-to-stringview"),
    )
    assert_eq(facts["canonical_argument_order"], @ir.Data::Text("1,0"))
    assert_eq(
      facts["conversion_policy"],
      @ir.Data::Text("utf16-code-unit-substring"),
    )
    assert_eq(facts["sdk_classification"], @ir.Data::Text("classic"))
  }
  let receipts = @ion.IonValue::from_fields([
    @ion.Field::new(
      "source_metadata",
      @ion.IonValue::list(output.metadata.map(m => m.data)),
    ),
    @ion.Field::new("future_fact", @ion.IonValue::string("retain-me")),
  ])
  let text = @ion_text.write_ion(receipts)
  assert_true(text.contains("String::contains"))
  assert_true(text.contains(@frontend.MOONBIT_CORE_TREE))
  assert_true(@ion_text.read_ion(text.view()).equals(receipts))
  let binary = @ion_binary.write_binary_value(receipts)
  assert_true(@ion_binary.read_binary_value(binary[:]).equals(receipts))
}

///|
test "String predicate boundaries refuse malformed and oversized host text" {
  let output = string_sdk(
    "pub fn has(s : String, needle : String) -> Bool { s.contains(needle) }",
    limit=3,
  )
  let runtime = string_runtime(output)
  for
    (receiver, needle, code) in [
      (
        @scheme.Value::Text("abc"),
        @scheme.Tagged("sdk-text", [@scheme.Vector([@scheme.integer("55357")])]),
        "sdk.unrepresentable_text",
      ),
      (
        @scheme.Tagged("sdk-text", [@scheme.Vector([@scheme.integer("56832")])]),
        @scheme.Text(""),
        "sdk.unrepresentable_text",
      ),
      (@scheme.Text("abcd"), @scheme.Text("a"), "sdk.out_of_range"),
    ] {
    try {
      ignore(
        @backend.call_entry(runtime, output.entries[0], [receiver, needle]),
      )
      fail("Expected source boundary refusal")
    } catch {
      @scheme.Domain(actual, _) => assert_eq(actual, code)
      error => raise error
    }
  }
}

///|
test "unpinned String forms and wrong signatures refuse contextually" {
  for
    (source, code) in [
      ("pub fn f(s : String) -> String { s.to_upper() }", "unsupported_method"),
      ("pub fn f(s : String) -> String { s.to_lower() }", "unsupported_method"),
      (
        "pub fn f(s : String, p : String) -> Bool { s.starts_with(p) }", "unsupported_method",
      ),
      (
        "pub fn f(s : String, p : String) -> Bool { s.ends_with(p) }", "unsupported_method",
      ),
      (
        "pub fn f(s : String) -> Bool { s.split(\",\").is_empty() }", "unsupported_method",
      ),
      (
        "pub fn f(s : String, p : String) -> Bool { s.find(p) }", "unsupported_method",
      ),
      ("pub fn f(s : String) -> String { s.trim() }", "unsupported_method"),
      ("pub fn f(s : String) -> String { s.to_owned() }", "unsupported_method"),
      ("pub fn f(s : String) -> Bool { s.contains() }", "binding_arity"),
      ("pub fn f(s : String) -> Bool { s.is_empty(s) }", "binding_arity"),
      ("pub fn f(s : String) -> Bool { s.contains(1) }", "type_mismatch"),
      ("pub fn f(n : Int32) -> Bool { n.is_empty() }", "type_mismatch"),
      (
        "pub fn f(b : Bool, s : String) -> Bool { b.has_prefix(s) }", "type_mismatch",
      ),
      ("pub fn f(s : String) -> String { s.contains(s) }", "type_mismatch"),
      (
        "pub fn f(s : String, p : String) -> Bool { s.contains(str=p) }", "unsupported_arguments",
      ),
      (
        "pub fn f(s : String, p : String) -> Bool { @String.contains(s, p) }", "unknown_binding",
      ),
      (
        "pub fn f(s : String, p : String) -> Bool { @string.contains(p, s) }", "unknown_binding",
      ),
      (
        "pub fn f(s : String) -> Bool { s.contains_any(chars=s) }", "unsupported_arguments",
      ),
    ] {
    let diagnostic = string_sdk_failure(source)
    assert_eq(diagnostic.code, "moonbit_frontend." + code)
    assert_true(diagnostic.source is Some(_))
  }
}

///|
test "a user function cannot replace a pinned String method" {
  let output = string_sdk(
    "fn contains(s : String, p : String) -> Bool { false }\npub fn has(s : String, p : String) -> Bool { s.contains(p) || contains(s, p) }",
  )
  let runtime = string_runtime(output)
  assert_true(string_sdk_bool(runtime, output, "has", ["abc", "b"]))
  assert_false(string_sdk_bool(runtime, output, "has", ["abc", "d"]))
}

///|
test "a host binding map without String methods cannot admit them" {
  let narrow = @frontend.PinnedSourceBindings::sdk_basics_not(
    "finos/morphir-sdk/basics", "0.1.0", "9c83a100383570236b3d781362524008f76dd56d",
    "basics",
  )
  let diagnostic = string_sdk_failure(
    "pub fn f(s : String) -> Bool { s.is_empty() }",
    bindings=Some(narrow),
  )
  assert_eq(diagnostic.code, "moonbit_frontend.unknown_binding")
  assert_true(diagnostic.detail.contains("String::is_empty"))
  for
    (package_name, version, tree) in [
      (
        "attacker/core/builtin",
        @frontend.MOONBIT_CORE_VERSION,
        @frontend.MOONBIT_CORE_TREE,
      ),
      (@frontend.MOONBIT_CORE_PACKAGE, "0.10.16", @frontend.MOONBIT_CORE_TREE),
      (
        @frontend.MOONBIT_CORE_PACKAGE,
        @frontend.MOONBIT_CORE_VERSION,
        "wrong-tree",
      ),
    ] {
    let rejected = try {
      ignore(narrow.with_string_predicates(package_name, version, tree))
      false
    } catch {
      @frontend.Invalid(d) => d.code == "moonbit_frontend.binding_identity"
    }
    assert_true(rejected)
  }
  let pinned = narrow.with_string_predicates(
    @frontend.MOONBIT_CORE_PACKAGE,
    @frontend.MOONBIT_CORE_VERSION,
    @frontend.MOONBIT_CORE_TREE,
  )
  let duplicate = try {
    ignore(
      pinned.with_string_predicates(
        @frontend.MOONBIT_CORE_PACKAGE,
        @frontend.MOONBIT_CORE_VERSION,
        @frontend.MOONBIT_CORE_TREE,
      ),
    )
    false
  } catch {
    @frontend.Invalid(d) => d.code == "moonbit_frontend.binding_identity"
  }
  assert_true(duplicate)
}

///|
test "String predicates are promoted to stable without widening its binding map" {
  let output = string_sdk(string_sdk_source(), channel=@frontend.Stable)
  let runtime = string_runtime(output)
  for row in string_sdk_rows() {
    let (name, arguments, expected) = row
    assert_eq(string_sdk_bool(runtime, output, name, arguments), expected)
  }
  guard output.provenance[0].kind() is @ion.Struct(fields) else {
    fail("Expected source provenance")
  }
  assert_true(
    fields.any(f => {
      f.name().text() == Some("profile") &&
      f.value().equals(@ion.IonValue::string(@frontend.STABLE_PROFILE))
    }),
  )
  let narrow = @frontend.PinnedSourceBindings::sdk_basics_not(
    "finos/morphir-sdk/basics", "0.1.0", "9c83a100383570236b3d781362524008f76dd56d",
    "basics",
  )
  let diagnostic = string_sdk_failure(
    "pub fn f(s : String) -> Bool { s.contains(\"a\") }",
    channel=@frontend.Stable,
    bindings=Some(narrow),
  )
  assert_eq(diagnostic.code, "moonbit_frontend.unknown_binding")
}
