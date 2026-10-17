///|
fn selected_hole() -> @ir.Value {
  @ir.Value::Hole(
    attrs(),
    @ir.HoleReason::DeletedDuringRefactor("private source detail"),
    None,
  )
}

///|
fn selected_run(value : @ir.Value) -> @scheme.Value raise {
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime, accelerators=false, model_errors=true)
  @backend.run_selected_in(
    runtime,
    file(
      @ir.ValueDefinition::ExpressionBody(
        [],
        @ir.Type::Unit(@ir.TypeAttributes::default()),
        value,
      ),
    ),
    @ir.FQName::parse("test:main#main"),
    [],
  )
}

///|
test "selected capability check skips an untaken hole and fails when reached" {
  for take in [false, true] {
    let result = @scheme.value_to_string(
      selected_run(
        @ir.Value::IfThenElse(
          attrs(),
          @ir.Value::Literal(attrs(), @ir.Literal::BoolLiteral(take)),
          selected_hole(),
          int("42"),
        ),
      ),
    ) catch {
      @scheme.Stage("evaluate", "execution.unsupported_reached") =>
        "unsupported"
      error => error.to_string()
    }
    assert_eq(result, if take { "unsupported" } else { "42" })
  }
}

///|
fn selected_observe(value : @ir.Value) -> String {
  @scheme.value_to_string(selected_run(value)) catch {
    @scheme.Stage("evaluate", "execution.unsupported_reached") => "unsupported"
    @scheme.Domain(_, _) => "model-error"
    @scheme.Invalid(_) => "invalid"
    @scheme.Unbound(_) => "unbound"
    error => error.to_string()
  }
}

///|
test "selected match and syntactic Boolean operations only check reached branches" {
  let a = attrs()
  for choose in [false, true] {
    assert_eq(
      selected_observe(
        @ir.Value::PatternMatch(
          a,
          @ir.Value::Literal(a, @ir.Literal::BoolLiteral(choose)),
          [
            (
              @ir.Pattern::LiteralPattern(
                a,
                @ir.PatternLiteral::BoolLiteral(true),
              ),
              selected_hole(),
            ),
            (@ir.Pattern::WildcardPattern(a), int("42")),
          ],
        ),
      ),
      if choose {
        "unsupported"
      } else {
        "42"
      },
    )
  }
  for
    (operation, value, expected) in [
      ("and", false, "#f"),
      ("or", true, "#t"),
      ("and", true, "unsupported"),
      ("or", false, "unsupported"),
    ] {
    assert_eq(
      selected_observe(
        sdk_apply_ir("morphir/SDK:basics#" + operation, [
          @ir.Value::Literal(a, @ir.Literal::BoolLiteral(value)),
          selected_hole(),
        ]),
      ),
      expected,
    )
  }
}

///|
test "selected first class and partially applied Boolean arguments remain eager" {
  let a = attrs()
  let output = @ir.Type::Unit(@ir.TypeAttributes::default())
  for partial in [false, true] {
    let reference = @ir.Value::Reference(
      a,
      @ir.FQName::parse("morphir/SDK:basics#and"),
    )
    let implementation = if partial {
      @ir.Value::Apply(
        a,
        reference,
        @ir.Value::Literal(a, @ir.Literal::BoolLiteral(false)),
      )
    } else {
      reference
    }
    let variable = @ir.Value::Variable(a, name("chosen"))
    let call = if partial {
      variable
    } else {
      @ir.Value::Apply(
        a,
        variable,
        @ir.Value::Literal(a, @ir.Literal::BoolLiteral(false)),
      )
    }
    assert_eq(
      selected_observe(
        @ir.Value::LetDefinition(
          a,
          name("chosen"),
          @ir.ValueDefinition::ExpressionBody([], output, implementation),
          @ir.Value::Apply(a, call, selected_hole()),
        ),
      ),
      "unsupported",
    )
  }
}

///|
test "selected uncalled functions defer checks but eager local values do not" {
  let a = attrs()
  let output = @ir.Type::Unit(@ir.TypeAttributes::default())
  for inputs in [[], [(name("argument"), output)]] {
    assert_eq(
      selected_observe(
        @ir.Value::LetDefinition(
          a,
          name("unused"),
          @ir.ValueDefinition::ExpressionBody(inputs, output, selected_hole()),
          int("42"),
        ),
      ),
      if inputs.is_empty() {
        "unsupported"
      } else {
        "42"
      },
    )
    assert_eq(
      selected_observe(
        @ir.Value::LetRecursion(
          a,
          Map::from_array([
            (
              name("unused"),
              @ir.ValueDefinition::ExpressionBody(
                inputs,
                output,
                selected_hole(),
              ),
            ),
          ]),
          int("42"),
        ),
      ),
      if inputs.is_empty() {
        "unsupported"
      } else {
        "42"
      },
    )
  }
  let incomplete = @ir.ValueDefinition::IncompleteBody(
    [(name("argument"), output)],
    Some(output),
    @ir.Incompleteness::Draft,
    None,
  )
  assert_eq(
    selected_observe(
      @ir.Value::LetDefinition(a, name("unfinished"), incomplete, int("42")),
    ),
    "42",
  )
  assert_eq(
    selected_observe(
      @ir.Value::LetDefinition(
        a,
        name("unfinished"),
        incomplete,
        @ir.Value::Apply(
          a,
          @ir.Value::Variable(a, name("unfinished")),
          int("1"),
        ),
      ),
    ),
    "unsupported",
  )
}

///|
test "selected capability traps preserve operator argument and curried application order" {
  let a = attrs()
  let model_error = sdk_apply_ir("morphir/SDK:basics#integer-divide", [
    int("1"),
    int("0"),
  ])
  assert_eq(
    selected_observe(@ir.Value::Apply(a, selected_hole(), model_error)),
    "unsupported",
  )
  assert_eq(
    selected_observe(
      sdk_apply_ir("morphir/SDK:basics#add", [model_error, selected_hole()]),
    ),
    "model-error",
  )
  let bad_partial = @ir.Value::Apply(
    a,
    @ir.Value::Apply(
      a,
      @ir.Value::Lambda(a, bind("ignored"), int("3")),
      int("1"),
    ),
    int("2"),
  )
  assert_eq(
    selected_observe(@ir.Value::Apply(a, bad_partial, selected_hole())),
    "invalid",
  )
}

///|
fn selected_file_with_helper(
  main : @ir.Value,
  helper : @ir.ValueDefinition,
) -> @ir.IRFile raise {
  let original = file(
    @ir.ValueDefinition::ExpressionBody(
      [],
      @ir.Type::Unit(@ir.TypeAttributes::default()),
      main,
    ),
  )
  guard original.distribution is Library(package_name, dependencies, definition) else {
    abort("library")
  }
  let module_name = @ir.Path::parse("main")
  let module_definition = definition.modules[module_name]
  module_definition.value.values[name("helper")] = {
    access: @ir.Access::Public,
    value: { doc: None, value: helper, },
  }
  @ir.IRFile::new(
    @ir.Distribution::Library(package_name, dependencies, definition),
  )
}

///|
test "selected global incomplete functions trap inside currying and strict remains eager" {
  let a = attrs()
  let output = @ir.Type::Unit(@ir.TypeAttributes::default())
  let helper = @ir.ValueDefinition::IncompleteBody(
    [(name("x"), output)],
    Some(output),
    @ir.Incompleteness::Draft,
    None,
  )
  for reached in [false, true] {
    let source = selected_file_with_helper(
      @ir.Value::IfThenElse(
        a,
        @ir.Value::Literal(a, @ir.Literal::BoolLiteral(reached)),
        @ir.Value::Apply(
          a,
          @ir.Value::Reference(a, @ir.FQName::parse("test:main#helper")),
          int("1"),
        ),
        int("42"),
      ),
      helper,
    )
    let runtime = @scheme.Runtime::new()
    @backend.install(runtime)
    let result = @scheme.value_to_string(
      @backend.run_selected_in(
        runtime,
        source,
        @ir.FQName::parse("test:main#main"),
        [],
      ),
    ) catch {
      @scheme.Stage("evaluate", "execution.unsupported_reached") =>
        "unsupported"
      error => error.to_string()
    }
    assert_eq(result, if reached { "unsupported" } else { "42" })
    let strict = try {
      @backend.link_file(runtime, source)
      false
    } catch {
      @scheme.Unsupported(_) => true
      _ => false
    }
    assert_true(strict)
  }
  let strict = try {
    ignore(@backend.emit_expression(selected_hole()))
    false
  } catch {
    @scheme.Unsupported(_) => true
    _ => false
  }
  assert_true(strict)
}

///|
test "selected native fallback preserves selection arity failure and no retry" {
  let a = attrs()
  let output = @ir.Type::Unit(@ir.TypeAttributes::default())
  let entry = @ir.FQName::parse("test:main#main")
  for registered in [false, true] {
    let source = file(
      @ir.ValueDefinition::ExternalBody(
        [],
        output,
        [{ target_platform: "morphir-scheme", external_name: "answer", }],
        Some(if registered { selected_hole() } else { int("42") }),
      ),
    )
    let runtime = @scheme.Runtime::new()
    @backend.install(runtime)
    if registered {
      @backend.register_external(runtime, "answer", 0, fn(_rt, _args) raise {
        @scheme.integer("43")
      })
    }
    assert_eq(
      @scheme.value_to_string(
        @backend.run_selected_in(runtime, source, entry, []),
      ),
      if registered {
        "43"
      } else {
        "42"
      },
    )
  }
  let source = file(
    @ir.ValueDefinition::ExternalBody(
      [],
      output,
      [{ target_platform: "morphir-scheme", external_name: "failure", }],
      Some(int("42")),
    ),
  )
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  @backend.register_external(runtime, "failure", 0, fn(_rt, _args) raise {
    raise @scheme.Invalid("native failure")
  })
  let failure = try {
    ignore(@backend.run_selected_in(runtime, source, entry, []))
    false
  } catch {
    @scheme.Invalid("native failure") => true
    _ => false
  }
  assert_true(failure)
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  @backend.register_external(runtime, "failure", 1, fn(_rt, _args) raise {
    @scheme.integer("43")
  })
  let mismatch = try {
    ignore(@backend.run_selected_in(runtime, source, entry, []))
    false
  } catch {
    @scheme.Invalid(message) => message.contains("arity mismatch")
    _ => false
  }
  assert_true(mismatch)
  let source = selected_file_with_helper(
    @ir.Value::Apply(
      a,
      @ir.Value::Reference(a, @ir.FQName::parse("test:main#helper")),
      selected_hole(),
    ),
    @ir.ValueDefinition::NativeBody([(name("x"), output)], output, {
      hint: @ir.NativeHint::Arithmetic,
      description: None,
    }),
  )
  let missing = try {
    ignore(@backend.run_selected_in(runtime, source, entry, []))
    false
  } catch {
    @scheme.Unbound(_) => true
    _ => false
  }
  assert_true(missing)
}

///|
test "selected checks preserve cancellation and constructor resource refusal" {
  let entry = @ir.FQName::parse("test:main#main")
  let source = file(
    @ir.ValueDefinition::ExpressionBody(
      [],
      @ir.Type::Unit(@ir.TypeAttributes::default()),
      selected_hole(),
    ),
  )
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  runtime.set_cancelled(fn() { true })
  let cancelled = try {
    ignore(@backend.run_selected_in(runtime, source, entry, []))
    false
  } catch {
    @scheme.Limit("cancelled") => true
    _ => false
  }
  assert_true(cancelled)
  let original = selected_file_with_helper(
    int("42"),
    @ir.ValueDefinition::IncompleteBody(
      [],
      None,
      @ir.Incompleteness::Draft,
      None,
    ),
  )
  guard original.distribution is Library(package_name, dependencies, definition) else {
    abort("library")
  }
  let constructor_name = @ir.FQName::parse("test:main#large")
  let parameters : Array[(@ir.Name, @ir.Type)] = []
  for i = 0; i < 257; i = i + 1 {
    parameters.push(
      (
        name("arg" + i.to_string()),
        @ir.Type::Unit(@ir.TypeAttributes::default()),
      ),
    )
  }
  let module_definition = definition.modules[@ir.Path::parse("main")]
  module_definition.value.types[name("large")] = {
    access: @ir.Access::Public,
    value: {
      doc: None,
      value: @ir.TypeDefinition::CustomTypeDefinition([], {
        access: @ir.Access::Public,
        value: Map::from_array([(name("large"), parameters)]),
      }),
    },
  }
  let source = @ir.IRFile::new(
    @ir.Distribution::Library(package_name, dependencies, definition),
  )
  ignore(@backend.emit_selected(source, entry))
  module_definition.value.values[name("main")] = {
    access: @ir.Access::Public,
    value: {
      doc: None,
      value: @ir.ValueDefinition::ExpressionBody(
        [],
        @ir.Type::Unit(@ir.TypeAttributes::default()),
        @ir.Value::IfThenElse(
          attrs(),
          @ir.Value::Literal(attrs(), @ir.Literal::BoolLiteral(false)),
          @ir.Value::Constructor(attrs(), constructor_name),
          int("42"),
        ),
      ),
    },
  }
  let retained = @ir.IRFile::new(
    @ir.Distribution::Library(package_name, dependencies, definition),
  )
  let limited = try {
    ignore(@backend.emit_selected(retained, entry))
    false
  } catch {
    @scheme.Limit("Constructor arity") => true
    _ => false
  }
  assert_true(limited)
}

///|
test "selected dormant code retains structural pattern literal and reference checks" {
  let a = attrs()
  let entry = @ir.FQName::parse("test:main#main")
  let output = @ir.Type::Unit(@ir.TypeAttributes::default())
  let incomplete = @ir.ValueDefinition::IncompleteBody(
    [(name("x"), output)],
    Some(output),
    @ir.Incompleteness::Draft,
    Some(@ir.Value::Reference(a, @ir.FQName::parse("test:main#missing"))),
  )
  let source = selected_file_with_helper(
    @ir.Value::IfThenElse(
      a,
      @ir.Value::Literal(a, @ir.Literal::BoolLiteral(false)),
      @ir.Value::Reference(a, @ir.FQName::parse("test:main#helper")),
      int("42"),
    ),
    incomplete,
  )
  let missing = try {
    ignore(@backend.emit_selected(source, entry))
    false
  } catch {
    @scheme.Unbound(_) => true
    _ => false
  }
  assert_true(missing)
  let duplicate = @ir.Pattern::TuplePattern(a, [bind("same"), bind("same")])
  let dormant = @ir.Value::IfThenElse(
    a,
    @ir.Value::Literal(a, @ir.Literal::BoolLiteral(false)),
    @ir.Value::Lambda(a, duplicate, int("0")),
    int("42"),
  )
  assert_eq(selected_observe(dormant), "invalid")
  let mut deep = @ir.Pattern::WildcardPattern(a)
  for i = 0; i < 258; i = i + 1 {
    deep = @ir.Pattern::TuplePattern(a, [deep])
  }
  let limited = try {
    ignore(
      selected_run(
        @ir.Value::IfThenElse(
          a,
          @ir.Value::Literal(a, @ir.Literal::BoolLiteral(false)),
          @ir.Value::Lambda(a, deep, int("0")),
          int("42"),
        ),
      ),
    )
    false
  } catch {
    @scheme.Limit(_) => true
    _ => false
  }
  assert_true(limited)
  let malformed = @ir.Value::IfThenElse(
    a,
    @ir.Value::Literal(a, @ir.Literal::BoolLiteral(false)),
    int("invalid"),
    int("42"),
  )
  let rejected = try {
    ignore(selected_run(malformed))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "selected execution shares one budget across file loading and invocation" {
  let entry = @ir.FQName::parse("test:main#main")
  let source = file(
    @ir.ValueDefinition::ExpressionBody(
      [],
      @ir.Type::Unit(@ir.TypeAttributes::default()),
      int("42"),
    ),
  )
  let emitted = @backend.emit_selected(source, entry)
  let mut observed_shared_budget = false
  for steps = 1; steps < 100; steps = steps + 1 {
    let separate = @scheme.Runtime::new(limits={
      steps,
      depth: 256,
      frames: 100000,
    })
    let separate_succeeds = try {
      @backend.install(separate)
      ignore(separate.eval(emitted))
      ignore(@backend.call_entry(separate, entry, []))
      true
    } catch {
      _ => false
    }
    if separate_succeeds {
      let combined = @scheme.Runtime::new(limits={
        steps,
        depth: 256,
        frames: 100000,
      })
      @backend.install(combined)
      let shared_limit = try {
        ignore(@backend.run_selected_in(combined, source, entry, []))
        false
      } catch {
        @scheme.Limit(_) => true
        _ => false
      }
      if shared_limit {
        observed_shared_budget = true
        break
      }
    }
  }
  assert_true(observed_shared_budget)
}

///|
test "selected local native bodies retain binding failures at their original RHS" {
  let a = attrs()
  let output = @ir.Type::Unit(@ir.TypeAttributes::default())
  let native = @ir.ValueDefinition::NativeBody([(name("x"), output)], output, {
    hint: @ir.NativeHint::Arithmetic,
    description: None,
  })
  let local_native = @ir.Value::LetDefinition(
    a,
    name("unused"),
    native,
    int("42"),
  )
  assert_eq(selected_observe(local_native), "unbound")
  for reached in [false, true] {
    assert_eq(
      selected_observe(
        @ir.Value::IfThenElse(
          a,
          @ir.Value::Literal(a, @ir.Literal::BoolLiteral(reached)),
          local_native,
          int("42"),
        ),
      ),
      if reached {
        "unbound"
      } else {
        "42"
      },
    )
  }
  assert_eq(
    selected_observe(
      @ir.Value::LetDefinition(
        a,
        name("outer"),
        @ir.ValueDefinition::ExpressionBody(
          [(name("ignored"), output)],
          output,
          local_native,
        ),
        int("42"),
      ),
    ),
    "42",
  )
}

///|
test "selected dormant variables require lexical or module bindings" {
  let a = attrs()
  let dormant = @ir.Value::IfThenElse(
    a,
    @ir.Value::Literal(a, @ir.Literal::BoolLiteral(false)),
    @ir.Value::Variable(a, name("missing")),
    int("42"),
  )
  assert_eq(selected_observe(dormant), "unbound")
}

///|
test "selected variable validation preserves parameter local recursive pattern and global scopes" {
  let a = attrs()
  let output = @ir.Type::Unit(@ir.TypeAttributes::default())
  let x = name("x")
  let variable = @ir.Value::Variable(a, x)
  let identity = @ir.ValueDefinition::ExpressionBody(
    [(x, output)],
    output,
    variable,
  )
  let local_binding = @ir.Value::LetDefinition(
    a,
    x,
    @ir.ValueDefinition::ExpressionBody([], output, int("42")),
    variable,
  )
  let recursive = @ir.Value::LetRecursion(
    a,
    Map::from_array([(name("identity"), identity)]),
    @ir.Value::Apply(a, @ir.Value::Variable(a, name("identity")), int("42")),
  )
  let matched = @ir.Value::PatternMatch(a, int("42"), [(bind("x"), variable)])
  let destructured = @ir.Value::Destructure(a, bind("x"), int("42"), variable)
  let lambda = @ir.Value::Apply(
    a,
    @ir.Value::Lambda(a, bind("x"), variable),
    int("42"),
  )
  for expression in [local_binding, recursive, matched, destructured, lambda] {
    assert_eq(selected_observe(expression), "42")
  }
  let source = selected_file_with_helper(
    @ir.Value::Variable(a, name("helper")),
    @ir.ValueDefinition::ExpressionBody([], output, int("42")),
  )
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  assert_eq(
    @scheme.value_to_string(
      @backend.run_selected_in(
        runtime,
        source,
        @ir.FQName::parse("test:main#main"),
        [],
      ),
    ),
    "42",
  )
}
