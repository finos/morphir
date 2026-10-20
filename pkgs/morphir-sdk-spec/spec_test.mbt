///|
fn sdk_module(name : String) -> @ir.ModuleSpecification {
  @sdk_spec.sdk_specification().modules
  .get(@ir.Path::parse(name) catch { _ => panic() })
  .unwrap()
}

///|
test "checked Decimal is a versioned extension and classic Decimal remains identical" {
  let classic = @sdk_spec.sdk_specification()
  let extended = @sdk_spec.numeric_sdk_specification()
  let path = @ir.Path::parse("decimal-checked-v1")
  assert_false(classic.modules.contains(path))
  let checked = extended.modules[path]
  assert_eq(checked.values.length(), 3)
  for
    (name, arity) in [
      ("from-string-exact", 1),
      ("divide", 2),
      ("divide-with-default", 3),
    ] {
    let spec = checked.values[@ir.Name::parse(name)].value
    assert_eq(spec.inputs.length(), arity)
    assert_true(
      spec.annotations.contains(
        @ir.Annotation::Compact(
          @ir.FQName::parse("morphir/moonbit-source:numeric#sdk-extension"),
          Some("morphir-sdk-decimal-checked-v1"),
        ),
      ),
    )
  }
  assert_eq(
    extended.modules[@ir.Path::parse("decimal")],
    classic.modules[@ir.Path::parse("decimal")],
  )
}

///|
test "the SDK specification has the hand-written types" {
  let basics = sdk_module("basics")
  for t in ["int", "float", "bool", "never", "order"] {
    assert_true(
      basics.types.contains(@ir.Name::parse(t) catch { _ => panic() }),
      msg=t,
    )
  }
  for
    m in [
      "char", "string", "list", "maybe", "result", "dict", "set", "decimal", "int",
    ] {
    assert_false(sdk_module(m).types.is_empty(), msg=m)
  }
}

///|
test "the SDK specification has every value from bindings" {
  let total = @sdk_spec.sdk_specification().modules
    .values()
    .fold(init=0, (n, m) => n + m.values.length())
  assert_eq(total, 248)
  let list = sdk_module("list")
  assert_true(
    list.values.contains(@ir.Name::parse("map-2") catch { _ => panic() }),
  )
}

///|
test "numeric extension adds unsigned Int declarations without changing classic inventory" {
  let classic = @sdk_spec.sdk_specification()
  let extended = @sdk_spec.numeric_sdk_specification()
  let key = @ir.Path::parse("int")
  let original = classic.modules[key]
  let additions = extended.modules[key]
  let marker = @sdk_spec.source_integer_specification().modules[@ir.Path::parse(
      "numeric",
    )]
  assert_true(marker.types.contains(@ir.Name::parse("sdk-extension")))
  assert_eq(original.types.length(), 4)
  for
    (type_name, conversion_name) in [
      ("byte", "to-byte"),
      ("uint-16", "to-uint-16"),
      ("uint-32", "to-uint-32"),
      ("uint-64", "to-uint-64"),
    ] {
    assert_false(original.types.contains(@ir.Name::parse(type_name)))
    assert_true(additions.types.contains(@ir.Name::parse(type_name)))
    assert_true(additions.values.contains(@ir.Name::parse(conversion_name)))
    assert_true(
      !additions.types[@ir.Name::parse(type_name)].value.annotations.is_empty(),
    )
  }
  assert_eq(@sdk_spec.sdk_specification(), classic)
}

///|
test "floating numeric additions have explicit conversion policies and source provenance" {
  let classic = @sdk_spec.sdk_specification()
  let extended = @sdk_spec.numeric_sdk_specification()
  let original = classic.modules[@ir.Path::parse("int")]
  let added = extended.modules[@ir.Path::parse("int")]
  assert_eq(added.values.length(), original.values.length() + 22)
  for
    name in [
      "from-float64-exact", "from-float64-truncated", "from-float64-floor", "from-float64-ceiling",
      "from-float64-rounded", "from-float32-exact", "from-float32-truncated", "from-float32-floor",
      "from-float32-ceiling", "from-float32-rounded", "to-float64-exact", "to-float64-rounded",
      "to-float32-exact", "to-float32-rounded",
    ] {
    let key = @ir.Name::parse(name)
    assert_false(original.values.contains(key))
    assert_true(added.values.contains(key))
    assert_true(!added.values[key].value.annotations.is_empty())
  }
  let float_source = @sdk_spec.source_float_specification()
  let float_module = float_source.modules[@ir.Path::parse("float32")]
  assert_true(float_module.types.contains(@ir.Name::parse("float32")))
  assert_true(float_module.values.contains(@ir.Name::parse("from-float64")))
  assert_true(!float_module.annotations.is_empty())
  assert_eq(@sdk_spec.sdk_specification(), classic)
}

///|
test "the SDK specification has local-date and constructor arities" {
  let local_date = sdk_module("local-date")
  guard local_date.types.get(
      @ir.Name::parse("local-date") catch {
        _ => panic()
      },
    )
    is Some(t) else {
    fail("local-date#local-date is missing")
  }
  assert_true(t.value.body is OpaqueTypeSpecification([]))
  let maybe = sdk_module("maybe")
  guard maybe.types.get(@ir.Name::parse("maybe") catch { _ => panic() })
    is Some({ value: { body: CustomTypeSpecification(_, ctors), .. }, .. }) else {
    fail("maybe#maybe is not a custom type")
  }
  guard ctors.get(@ir.Name::parse("just") catch { _ => panic() }) is Some(args) else {
    fail("maybe#just is missing")
  }
  assert_eq(args.length(), 1)
}
