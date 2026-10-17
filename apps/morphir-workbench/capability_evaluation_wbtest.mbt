///|
fn capability_fixture(taken : Bool) -> @ir.IRFile raise {
  let int = @ir.Type::Reference(
    @ir.TypeAttributes::default(),
    @ir.FQName::parse("morphir/SDK:basics#int"),
    [],
  )
  let attrs = @ir.ValueAttributes::default()
  @ir.IRFile::new(
    @ir.Distribution::Library(@ir.Path::parse("selected"), Map([]), {
      modules: Map::from_array([
        (
          @ir.Path::parse("main"),
          {
            access: @ir.Access::Public,
            value: {
              types: Map([]),
              doc: None,
              values: Map::from_array([
                (
                  @ir.Name::parse("answer"),
                  {
                    access: @ir.Access::Public,
                    value: {
                      doc: None,
                      value: @ir.ValueDefinition::ExpressionBody(
                        [],
                        int,
                        @ir.Value::IfThenElse(
                          attrs,
                          @ir.Value::Literal(
                            attrs,
                            @ir.Literal::BoolLiteral(taken),
                          ),
                          @ir.Value::Hole(
                            attrs,
                            @ir.HoleReason::DeletedDuringRefactor("test"),
                            Some(int),
                          ),
                          @ir.Value::Literal(
                            attrs,
                            @ir.Literal::IntegerLiteral("42"),
                          ),
                        ),
                      ),
                    },
                  },
                ),
              ]),
            },
          },
        ),
      ]),
    }),
  )
}

///|
fn capability_request(file : @ir.IRFile, policy : String) -> Json raise {
  {
    "operation": "evaluate",
    "executionMode": "capability",
    "source": @codec.to_json(file).stringify(),
    "entry": "selected:main#answer",
    "arguments": [],
    "admission": {
      "profile": "morphir/workbench/admission",
      "contractVersion": "0.1.0-draft.1",
      "policy": policy,
    },
  }
}

///|
test "standalone boundaries survive whole generation failure and policy is explicit" {
  let file = capability_fixture(false)
  let inspected = execute({
    "operation": "inspect",
    "source": @codec.to_json(file).stringify(),
  })
  assert_eq(@wire.field(inspected, "success"), Json::boolean(true))
  assert_true(
    @wire.optional(@wire.field(inspected, "typedEvaluations"), "reason")
    is Some(String(_)),
  )
  let capability = @wire.field(inspected, "capabilityEvaluations")
  assert_eq(
    @wire.field(
      @wire.field(@wire.field(capability, "entries"), "selected:main#answer"),
      "supported",
    ),
    Json::boolean(true),
  )
  assert_eq(@wire.field(inspected, "ir"), @codec.to_json(file))
  let strict = execute(capability_request(file, "strict"))
  assert_eq(@wire.field(strict, "success"), Json::boolean(false))
  assert_eq(
    @wire.field(@wire.field(strict, "admission"), "policy"),
    Json::string("strict"),
  )
  let omitted = capability_request(file, "strict")
  guard omitted is Object(fields) else { abort("request object") }
  fields.remove("admission") |> ignore
  assert_eq(@wire.field(execute(omitted), "success"), Json::boolean(false))
  let result = execute(capability_request(file, "permissive"))
  assert_eq(@wire.field(result, "success"), Json::boolean(true))
  assert_eq(@wire.field(result, "typed"), { "type": "int", "value": "42" })
  assert_eq(
    @wire.field(@wire.field(result, "admission"), "policy"),
    Json::string("permissive"),
  )
  let reached = execute(
    capability_request(capability_fixture(true), "permissive"),
  )
  assert_eq(@wire.field(reached, "success"), Json::boolean(false))
  let calls = @wire.array(
    @wire.field(@wire.field(reached, "terminalOutcomes"), "calls"),
  )
  assert_eq(
    @wire.field(
      @wire.field(@wire.field(calls[0], "outcome"), "failure"),
      "code",
    ),
    Json::string("execution.unsupported_reached"),
  )
}

///|
test "standalone policies reject unknown profiles and cannot reach legacy runtime" {
  let request = capability_request(capability_fixture(false), "permissive")
  guard request is Object(fields) else { abort("request object") }
  for mode in ["typed", "local"] {
    fields["executionMode"] = Json::string(mode)
    assert_eq(@wire.field(execute(request), "success"), Json::boolean(false))
  }
  fields["executionMode"] = Json::string("capability")
  fields["admission"] = {
    "profile": "morphir/workbench/admission",
    "contractVersion": "future",
    "policy": "permissive",
  }
  assert_eq(@wire.field(execute(request), "success"), Json::boolean(false))
  fields["admission"] = {
    "profile": "morphir/workbench/admission",
    "contractVersion": "0.1.0-draft.1",
    "policy": "future",
  }
  assert_eq(@wire.field(execute(request), "success"), Json::boolean(false))
}
