///|
test "capability policy returns an untaken hole and reports the reached hole" {
  let unit = selected_unit(
    @ir.ValueDefinition::ExpressionBody(
      [],
      selected_int(),
      @ir.Value::Unit(@ir.ValueAttributes::default()),
    ),
  )
  guard unit.distribution.distribution is Library(_, _, definition) else {
    abort("test library")
  }
  let values = definition.modules[@ir.Path::parse("main")].value.values
  let old = values[@ir.Name::parse("answer")]
  for taken in [false, true] {
    values[@ir.Name::parse("answer")] = {
      ..old,
      value: {
        ..old.value,
        value: @ir.ValueDefinition::ExpressionBody(
          [],
          selected_int(),
          @ir.Value::IfThenElse(
            @ir.ValueAttributes::default(),
            @ir.Value::Literal(
              @ir.ValueAttributes::default(),
              @ir.Literal::BoolLiteral(taken),
            ),
            @ir.Value::Hole(
              @ir.ValueAttributes::default(),
              @ir.HoleReason::DeletedDuringRefactor("private source"),
              Some(selected_int()),
            ),
            @ir.Value::Literal(
              @ir.ValueAttributes::default(),
              @ir.Literal::IntegerLiteral("42"),
            ),
          ),
        ),
      },
    }
    let plan = @execution.plan_scheme_capabilities(
      unit,
      selected_suite(),
      policy=@execution.Permissive,
    )
    let observed = plan.evaluate_outcomes()
    if taken {
      assert_eq(
        observed.calls[0].outcome,
        @protocol.Failed({
          stage: Evaluate,
          code: "execution.unsupported_reached",
          message: "Unsupported operation reached",
        }),
      )
    } else {
      assert_eq(
        observed.calls[0].outcome,
        @protocol.Returned(
          @protocol.Value::from_json({ "type": "int", "value": "42" }),
        ),
      )
    }
  }
}

///|
fn capability_body(unit : @data.IRUnit, body : @ir.Value) -> Unit raise {
  guard unit.distribution.distribution is Library(_, _, definition) else {
    abort("test library")
  }
  let values = definition.modules[@ir.Path::parse("main")].value.values
  let name = @ir.Name::parse("answer")
  let old = values[name]
  values[name] = {
    ..old,
    value: {
      ..old.value,
      value: @ir.ValueDefinition::ExpressionBody([], selected_int(), body),
    },
  }
}

///|
test "capability terminals retain source calls and selected context after edits" {
  let unit = selected_unit(
    @ir.ValueDefinition::ExpressionBody(
      [],
      selected_int(),
      @ir.Value::Unit(@ir.ValueAttributes::default()),
    ),
  )
  let suite = selected_suite()
  let plan = @execution.plan_scheme_capabilities(
    unit,
    suite,
    policy=@execution.Permissive,
  )
  capability_body(
    unit,
    @ir.Value::Hole(
      @ir.ValueAttributes::default(),
      @ir.HoleReason::DeletedDuringRefactor("changed"),
      Some(selected_int()),
    ),
  )
  suite.calls[0].arguments.push(@protocol.Unit)
  suite.calls.clear()
  if plan.boundary_json() is Object(fields) {
    fields.clear()
  }
  let observed = plan.evaluate_outcomes()
  assert_eq(observed.calls[0].id, "answer")
  assert_eq(
    observed.calls[0].outcome,
    @protocol.Returned(
      @protocol.Value::from_json({ "type": "int", "value": "42" }),
    ),
  )
  plan.validate_outcomes(observed)
}

///|
test "capability completion validates values inventory metadata and cleanup" {
  let unit = selected_unit(
    @ir.ValueDefinition::ExpressionBody(
      [],
      selected_int(),
      @ir.Value::Unit(@ir.ValueAttributes::default()),
    ),
  )
  let plan = @execution.plan_scheme_capabilities(
    unit,
    selected_suite(),
    policy=@execution.Permissive,
  )
  let evidence = plan.evaluate_outcomes()
  let failures = [
    (
      {
        ..evidence,
        calls: [{ id: "answer", outcome: Returned(@protocol.Boolean(false)), }],
      } : @protocol.Outcomes),
    ({ ..evidence, calls: [], } : @protocol.Outcomes),
    (
      { ..evidence, calls: [{ id: "other", outcome: Cancelled, }], } :
      @protocol.Outcomes),
    (
      { ..evidence, extensions: Some(b"\xe0\x01\x00\xea\x0f"), } :
      @protocol.Outcomes),
  ]
  let codes = failures.map(failure => {
    try {
      plan.validate_outcomes(failure)
      "accepted"
    } catch {
      @protocol.Invalid(code) => code.split(":").next().unwrap_or("").to_owned()
      _ => "unexpected"
    }
  })
  assert_eq(codes, [
    "execution.wrong_type", "execution.result_count", "execution.call_identity",
    "execution.outcome_extensions",
  ])
  let cleanup : @protocol.OutcomeFailure = {
    stage: Cleanup,
    code: "provider.cleanup",
    message: "Cleanup failed",
  }
  let primary : @protocol.OutcomeFailure = {
    stage: Evaluate,
    code: "provider.failed",
    message: "Provider failed",
  }
  for terminal in [@protocol.Cancelled, @protocol.Failed(primary)] {
    let supplied : @protocol.Outcomes = {
      ..evidence,
      calls: [{ id: "answer", outcome: terminal, }],
      cleanup: Some(cleanup),
    }
    plan.validate_outcomes(supplied)
    assert_eq(supplied.cleanup, Some(cleanup))
    assert_eq(supplied.calls[0].outcome, terminal)
  }
}

///|
test "capability actual cancellation and wrong returned type stay distinct" {
  let unit = selected_unit(
    @ir.ValueDefinition::ExpressionBody(
      [],
      selected_int(),
      @ir.Value::Unit(@ir.ValueAttributes::default()),
    ),
  )
  let plan = @execution.plan_scheme_capabilities(
    unit,
    selected_suite(),
    policy=@execution.Permissive,
  )
  assert_eq(
    plan.evaluate_outcomes(cancelled=fn() { true }).calls[0].outcome,
    @protocol.Cancelled,
  )
  capability_body(
    unit,
    @ir.Value::Literal(
      @ir.ValueAttributes::default(),
      @ir.Literal::BoolLiteral(true),
    ),
  )
  let wrong = @execution.plan_scheme_capabilities(
    unit,
    selected_suite(),
    policy=@execution.Permissive,
  ).evaluate_outcomes()
  assert_eq(
    wrong.calls[0].outcome,
    @protocol.Failed({
      stage: Evaluate,
      code: "execution.evaluator_type",
      message: "Invalid typed evaluation result",
    }),
  )
}

///|
test "capability checking retains omitted strict and frozen selected behavior" {
  let unit = selected_unit(
    @ir.ValueDefinition::IncompleteBody(
      [],
      Some(selected_int()),
      @ir.Incompleteness::Draft,
      None,
    ),
  )
  let strict = try {
    ignore(@execution.plan_scheme_capabilities(unit, selected_suite()))
    "accepted"
  } catch {
    @moonbit.Invalid(code, _, _) => code
    _ => "unexpected"
  }
  assert_eq(strict, "moonbit.incomplete_body")
  capability_body(
    unit,
    @ir.Value::IfThenElse(
      @ir.ValueAttributes::default(),
      @ir.Value::Literal(
        @ir.ValueAttributes::default(),
        @ir.Literal::BoolLiteral(false),
      ),
      @ir.Value::Hole(
        @ir.ValueAttributes::default(),
        @ir.HoleReason::DeletedDuringRefactor("dormant"),
        Some(selected_int()),
      ),
      @ir.Value::Literal(
        @ir.ValueAttributes::default(),
        @ir.Literal::IntegerLiteral("42"),
      ),
    ),
  )
  let frozen = @execution.plan_scheme(
    unit,
    selected_suite(),
    policy=@execution.Permissive,
  )
  let legacy = try {
    ignore(frozen.evaluate())
    "accepted"
  } catch {
    @scheme.Unsupported(_) => "unsupported"
    _ => "unexpected"
  }
  assert_eq(legacy, "unsupported")
  let full = @execution.plan_scheme_capabilities(
    unit,
    selected_suite(),
    policy=@execution.Permissive,
  )
  assert_eq(
    full.evaluate_outcomes().calls[0].outcome,
    @protocol.Returned(
      @protocol.Value::from_json({ "type": "int", "value": "42" }),
    ),
  )
}

///|
test "capability plans validate SDK Int32 inputs and captured completion bounds" {
  let unit = @data.IRUnit::new("bounded", @fixtures.invocation_library())
  for policy in [@execution.Strict, @execution.Permissive] {
    for value in ["-2147483649", "2147483648"] {
      let suite : @protocol.Suite = {
        extensions: None,
        calls: [
          {
            id: "bounded",
            entry: "calls:main#signed32",
            arguments: [int32_boundary(value)],
          },
        ],
      }
      try
        ignore(@execution.plan_scheme_capabilities(unit, suite, policy~))
      catch {
        @protocol.Invalid(code) => assert_eq(code, "execution.int32_range")
        error => raise error
      } noraise {
        _ => fail("Invalid SDK input must fail before execution")
      }
    }
    let suite : @protocol.Suite = {
      extensions: None,
      calls: [
        {
          id: "bounded",
          entry: "calls:main#signed32",
          arguments: [int32_boundary("0")],
        },
      ],
    }
    let plan = @execution.plan_scheme_capabilities(unit, suite, policy~)
    for value in ["-2147483649", "2147483648"] {
      try plan.validate_outputs([int32_boundary(value)]) catch {
        @protocol.Invalid(code) => assert_eq(code, "execution.int32_range")
        error => raise error
      } noraise {
        _ => fail("Invalid SDK output must not be published")
      }
      let outcomes : @protocol.Outcomes = {
        calls: [{ id: "bounded", outcome: Returned(int32_boundary(value)), }],
        cleanup: None,
        extensions: None,
      }
      try plan.validate_outcomes(outcomes) catch {
        @protocol.Invalid(code) => assert_eq(code, "execution.int32_range")
        error => raise error
      } noraise {
        _ => fail("Invalid SDK completion must not be published")
      }
    }
    for value in ["-2147483648", "2147483647"] {
      plan.validate_outcomes({
        calls: [{ id: "bounded", outcome: Returned(int32_boundary(value)), }],
        cleanup: None,
        extensions: None,
      })
    }
  }
}
