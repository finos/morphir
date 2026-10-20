///|
test "pinned Basics not owns a canonical typed call and replayable source facts" {
  let source = "pub fn invert(flag : Bool) -> Bool { @basics.not_(flag) }"
  let output = @frontend.compile_library(
    channel=@frontend.Experimental,
    input(source),
    bindings=Some(
      @frontend.PinnedSourceBindings::sdk_basics_not(
        "finos/morphir-sdk/basics", "0.1.0", "9c83a100383570236b3d781362524008f76dd56d",
        "basics",
      ),
    ),
  )
  assert_eq(output.entries.length(), 1)
  assert_false(library_result(output, output.entries[0], [true]))
  assert_true(library_result(output, output.entries[0], [false]))
  let generated = library_generated(output)
  assert_eq(generated.symbols.filter(s => s.public).length(), 1)
  assert_eq(@ir_json.read(@ir_json.write(output.ir)), output.ir)
  guard output.ir.distribution is Library(_, _, package_def) else {
    fail("Expected source library")
  }
  let definition = package_def.modules.values().collect()[0].value.values[@ir.Name::parse(
      "invert",
    )].value.value
  guard definition
    is ExpressionBody(
      _,
      _,
      @ir.Value::LetDefinition(
        _,
        _,
        _,
        @ir.Value::Apply(
          call_attrs,
          @ir.Value::Reference(reference_attrs, canonical),
          _
        )
      )
    ) else {
    fail("Expected one evaluated argument and a canonical SDK call")
  }
  assert_eq(canonical.to_canonical(), "morphir/SDK:basics#not")
  for attrs in [call_attrs, reference_attrs] {
    guard attrs.extensions.get("moonbit-source-binding-v1")
      is Some(@ir.Data::Object(facts)) else {
      fail("Expected source binding facts on the call and reference")
    }
    assert_eq(facts["source_alias"], @ir.Data::Text("basics"))
    assert_eq(
      facts["source_package"],
      @ir.Data::Text("finos/morphir-sdk/basics"),
    )
    assert_eq(
      facts["source_tree"],
      @ir.Data::Text("9c83a100383570236b3d781362524008f76dd56d"),
    )
    assert_eq(facts["conversion_policy"], @ir.Data::Text("exact-bool"))
    assert_eq(facts["source_signature"], @ir.Data::Text("Bool -> Bool"))
  }
  let receipts = @ion.IonValue::from_fields([
    @ion.Field::new(
      "source_metadata",
      @ion.IonValue::list(output.metadata.map(m => m.data)),
    ),
    @ion.Field::new("future_fact", @ion.IonValue::string("retain-me")),
  ])
  let text = @ion_text.write_ion(receipts)
  assert_true(text.contains("@basics.not_"))
  assert_true(text.contains("retain-me"))
  assert_true(@ion_text.read_ion(text.view()).equals(receipts))
  let binary = @ion_binary.write_binary_value(receipts)
  assert_true(@ion_binary.read_binary_value(binary[:]).equals(receipts))
}

///|
test "a source alias without an adapter supplied binding is refused" {
  let failed = try {
    ignore(
      @frontend.compile_library(
        channel=@frontend.Experimental,
        input("pub fn invert(flag : Bool) -> Bool { @basics.not_(flag) }"),
        bindings=Some(@frontend.PinnedSourceBindings::empty()),
      ),
    )
    false
  } catch {
    @frontend.Invalid(diagnostic) => {
      assert_eq(diagnostic.code, "moonbit_frontend.unknown_binding")
      assert_true(diagnostic.source is Some(_))
      true
    }
    error => raise error
  }
  assert_true(failed)
}

///|
test "a textual alias cannot turn another package tree into an SDK binding" {
  for
    (package_name, version, tree, package_alias) in [
      (
        "attacker/basics", "0.1.0", "9c83a100383570236b3d781362524008f76dd56d", "basics",
      ),
      (
        "finos/morphir-sdk/basics", "0.2.0", "9c83a100383570236b3d781362524008f76dd56d",
        "basics",
      ),
      ("finos/morphir-sdk/basics", "0.1.0", "wrong-tree", "basics"),
      (
        "finos/morphir-sdk/basics", "0.1.0", "9c83a100383570236b3d781362524008f76dd56d",
        "other",
      ),
    ] {
    let rejected = try {
      ignore(
        @frontend.PinnedSourceBindings::sdk_basics_not(
          package_name, version, tree, package_alias,
        ),
      )
      false
    } catch {
      @frontend.Invalid(diagnostic) => {
        assert_eq(diagnostic.code, "moonbit_frontend.binding_identity")
        true
      }
      error => raise error
    }
    assert_true(rejected)
  }
}

///|
test "pinned calls cannot be redirected by a source package owning the SDK identity" {
  let source = "pub fn not(flag : Bool) -> Bool { flag }\npub fn invert(flag : Bool) -> Bool { @basics.not_(flag) }"
  let selected = input(source)
  let bad : @frontend.Input = {
    ..selected,
    package_name: "morphir/SDK",
    module_name: "basics",
  }
  let rejected = try {
    ignore(
      @frontend.compile_library(
        channel=@frontend.Experimental,
        bad,
        bindings=Some(
          @frontend.PinnedSourceBindings::sdk_basics_not(
            "finos/morphir-sdk/basics", "0.1.0", "9c83a100383570236b3d781362524008f76dd56d",
            "basics",
          ),
        ),
      ),
    )
    false
  } catch {
    @frontend.Invalid(diagnostic) => {
      assert_eq(diagnostic.code, "moonbit_frontend.invalid_identity")
      true
    }
    error => raise error
  }
  assert_true(rejected)
}

///|
test "narrow binding environments require audited SDK type uses even without calls" {
  for
    source in [
      "pub fn f(v : @integer.Integer) -> @integer.Integer { v }", "pub fn f(v : @integer.Integer?) -> @integer.Integer? { v }",
      "pub fn f(v : @decimal.Decimal) -> @decimal.Decimal { v }", "pub fn f() -> Bool raise @sdk.SdkError { true }",
      "pub fn f() -> Bool raise @decimal.DecimalError { true }",
    ] {
    try {
      ignore(
        @frontend.compile_library(
          channel=@frontend.Experimental,
          input(source),
          bindings=Some(@frontend.PinnedSourceBindings::empty()),
        ),
      )
      fail("Expected missing SDK type refusal")
    } catch {
      @frontend.Invalid(d) =>
        assert_eq(d.code, "moonbit_frontend.binding_identity")
      error => raise error
    }
    ignore(
      @frontend.compile_library(channel=@frontend.Experimental, input(source)),
    )
  }
}
