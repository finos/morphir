///|
test "selected Scheme planners refuse a reachable private Union alias helper" {
  let union : @ir.Type = Union(Default::default(), [
    selected_int(),
    selected_int(),
  ])
  let hidden : @ir.Type = Reference(
    Default::default(),
    @ir.FQName::parse("selected:main#hidden"),
    [],
  )
  let unit = selected_unit(
    ExpressionBody(
      [],
      hidden,
      @ir.Value::Literal(Default::default(), IntegerLiteral("1")),
    ),
  )
  guard unit.distribution.distribution is Library(_, _, d) else {
    fail("library")
  }
  let m = d.modules[@ir.Path::parse("main")].value
  m.types[@ir.Name::parse("hidden")] = {
    access: Private,
    value: { doc: None, value: TypeAliasDefinition([], union), },
  }
  let helper = m.values[@ir.Name::parse("unused")]
  m.values[@ir.Name::parse("unused")] = { ..helper, access: Private, }
  let answer = m.values[@ir.Name::parse("answer")]
  m.values[@ir.Name::parse("answer")] = {
    ..answer,
    value: {
      ..answer.value,
      value: ExpressionBody(
        [],
        selected_int(),
        Reference(Default::default(), @ir.FQName::parse("selected:main#unused")),
      ),
    },
  }
  try @execution.plan_scheme(unit, selected_suite(), policy=Permissive) catch {
    @execution.AdmissionInvalid(code) =>
      assert_eq(code, "execution.unsupported_type")
    error => fail("wrong error: " + error.to_string())
  } noraise {
    _ => fail("reachable Union helper planned")
  }
  try
    @execution.plan_scheme_capabilities(
      unit,
      selected_suite(),
      policy=Permissive,
    )
  catch {
    @execution.AdmissionInvalid(code) =>
      assert_eq(code, "execution.unsupported_type")
    error => fail("wrong error: " + error.to_string())
  } noraise {
    _ => fail("reachable Union helper capability planned")
  }
}

///|
test "selected Scheme permits an unrelated Union declaration and rejects public Union boundaries" {
  let union : @ir.Type = Union(Default::default(), [
    selected_int(),
    selected_int(),
  ])
  let unit = selected_unit(
    ExpressionBody(
      [],
      union,
      @ir.Value::Literal(Default::default(), IntegerLiteral("1")),
    ),
  )
  ignore(
    @execution.plan_scheme_capabilities(
      unit,
      selected_suite(),
      policy=Permissive,
    ),
  )
  selected_definition(unit, [], union)
  try @execution.plan_scheme(unit, selected_suite(), policy=Permissive) catch {
    @execution.AdmissionInvalid(code) =>
      assert_eq(code, "execution.unsupported_type")
    error => fail("wrong error: " + error.to_string())
  } noraise {
    _ => fail("Union boundary planned")
  }
}

///|
test "selected planners reject reached dependency alias signatures" {
  let int = selected_int()
  let unit = selected_unit(
    ExpressionBody([], int, Literal(Default::default(), IntegerLiteral("1"))),
  )
  guard unit.distribution.distribution is Library(_, dependencies, d) else {
    fail("library")
  }
  let module_name = @ir.Path::parse("basics")
  let hidden = @ir.FQName::parse("morphir/SDK:basics#hidden")
  dependencies[@ir.Path::parse("morphir/SDK")] = {
    modules: Map([
      (
        module_name,
        {
          annotations: [],
          doc: None,
          types: Map([
            (
              @ir.Name::parse("hidden"),
              {
                doc: None,
                value: {
                  annotations: [],
                  body: TypeAliasSpecification(
                    [],
                    Union(Default::default(), [int, int]),
                  ),
                },
              },
            ),
          ]),
          values: Map([
            (
              @ir.Name::parse("identity"),
              {
                doc: None,
                value: {
                  annotations: [],
                  inputs: [(@ir.Name::parse("value"), int)],
                  output: Reference(Default::default(), hidden, []),
                },
              },
            ),
          ]),
        },
      ),
    ]),
  }
  let m = d.modules[@ir.Path::parse("main")].value
  let answer = m.values[@ir.Name::parse("answer")]
  m.values[@ir.Name::parse("answer")] = {
    ..answer,
    value: {
      ..answer.value,
      value: ExpressionBody(
        [],
        int,
        Apply(
          Default::default(),
          Reference(
            Default::default(),
            @ir.FQName::parse("morphir/SDK:basics#identity"),
          ),
          Literal(Default::default(), IntegerLiteral("42")),
        ),
      ),
    },
  }
  try @execution.plan_scheme(unit, selected_suite(), policy=Permissive) catch {
    @execution.AdmissionInvalid(code) =>
      assert_eq(code, "execution.unsupported_type")
    e => fail("wrong error: " + e.to_string())
  } noraise {
    _ => fail("dependency union planned")
  }
  try
    @execution.plan_scheme_capabilities(
      unit,
      selected_suite(),
      policy=Permissive,
    )
  catch {
    @execution.AdmissionInvalid(code) =>
      assert_eq(code, "execution.unsupported_type")
    e => fail("wrong error: " + e.to_string())
  } noraise {
    _ => fail("dependency union capability planned")
  }
}
