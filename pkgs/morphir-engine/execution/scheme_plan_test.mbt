///|
fn selected_unit(unused : @ir.ValueDefinition) -> @data.IRUnit raise {
  let int = @ir.Type::Reference(
    @ir.TypeAttributes::default(),
    @ir.FQName::parse("morphir/SDK:basics#int"),
    [],
  )
  let public_value = fn(body) {
    @ir.AccessControlled::{
      access: @ir.Access::Public,
      value: @ir.Documented::{ doc: None, value: body, },
    }
  }
  @data.IRUnit::new(
    "selected",
    @ir.IRFile::new(
      @ir.Distribution::Library(@ir.Path::parse("selected"), Map([]), {
        modules: Map::from_array([
          (
            @ir.Path::parse("main"),
            {
              access: @ir.Access::Public,
              value: {
                types: Map([]),
                values: Map::from_array([
                  (
                    @ir.Name::parse("answer"),
                    public_value(
                      @ir.ValueDefinition::ExpressionBody(
                        [],
                        int,
                        @ir.Value::Literal(
                          @ir.ValueAttributes::default(),
                          @ir.Literal::IntegerLiteral("42"),
                        ),
                      ),
                    ),
                  ),
                  (@ir.Name::parse("unused"), public_value(unused)),
                ]),
                doc: None,
              },
            },
          ),
        ]),
      }),
    ),
  )
}

///|
fn selected_suite() -> @protocol.Suite {
  {
    extensions: None,
    calls: [{ id: "answer", entry: "selected:main#answer", arguments: [], }],
  }
}

///|
test "selected permissive Scheme call ignores an unused unsupported body" {
  let int = @ir.Type::Reference(
    @ir.TypeAttributes::default(),
    @ir.FQName::parse("morphir/SDK:basics#int"),
    [],
  )
  let unit = selected_unit(
    @ir.ValueDefinition::ExpressionBody(
      [],
      int,
      @ir.Value::Hole(
        @ir.ValueAttributes::default(),
        @ir.HoleReason::DeletedDuringRefactor("unused"),
        Some(int),
      ),
    ),
  )
  let selected = @execution.plan_scheme(
    unit,
    selected_suite(),
    policy=@execution.Permissive,
  )
  assert_eq(selected.policy(), @execution.Permissive)
  assert_eq(selected.evaluate().map(v => v.to_json()), [
    { "type": "int", "value": "42" },
  ])
}

///|
fn selected_int() -> @ir.Type raise {
  @ir.Type::Reference(
    @ir.TypeAttributes::default(),
    @ir.FQName::parse("morphir/SDK:basics#int"),
    [],
  )
}

///|
fn selected_definition(
  unit : @data.IRUnit,
  inputs : Array[(@ir.Name, @ir.Type)],
  output : @ir.Type,
) -> Unit raise {
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
      value: @ir.ValueDefinition::ExpressionBody(
        inputs,
        output,
        @ir.Value::Literal(
          @ir.ValueAttributes::default(),
          @ir.Literal::IntegerLiteral("42"),
        ),
      ),
    },
  }
}

///|
test "selected boundary rejects a function inside an empty input container" {
  let int = selected_int()
  let unit = selected_unit(
    @ir.ValueDefinition::ExpressionBody(
      [],
      int,
      @ir.Value::Unit(@ir.ValueAttributes::default()),
    ),
  )
  selected_definition(
    unit,
    [
      (
        @ir.Name::parse("items"),
        @ir.Type::Reference(
          @ir.TypeAttributes::default(),
          @ir.FQName::parse("morphir/SDK:list#list"),
          [@ir.Type::Function(@ir.TypeAttributes::default(), int, int)],
        ),
      ),
    ],
    int,
  )
  let suite = selected_suite()
  suite.calls[0].arguments.push(@protocol.Sequence([]))
  let code = try {
    ignore(@execution.plan_scheme(unit, suite, policy=@execution.Permissive))
    "accepted"
  } catch {
    @execution.AdmissionInvalid(code) => code
    _ => "unexpected"
  }
  assert_eq(code, "execution.boundary_function")
}

///|
test "omitted and explicit strict retain existing whole-library rejection" {
  let int = selected_int()
  let unit = selected_unit(
    @ir.ValueDefinition::IncompleteBody(
      [],
      Some(int),
      @ir.Incompleteness::Draft,
      None,
    ),
  )
  for explicit in [false, true] {
    let code = try {
      ignore(
        if explicit {
          @execution.plan_scheme(
            unit,
            selected_suite(),
            policy=@execution.Strict,
          )
        } else {
          @execution.plan_scheme(unit, selected_suite())
        },
      )
      "accepted"
    } catch {
      @moonbit.Invalid(code, _, _) => code
      _ => "unexpected"
    }
    assert_eq(code, "moonbit.incomplete_body")
  }
}

///|
test "unused incomplete native and external declarations are not linked or emitted" {
  let int = selected_int()
  for
    unused in [
      @ir.ValueDefinition::IncompleteBody(
        [],
        Some(int),
        @ir.Incompleteness::Draft,
        None,
      ),
      @ir.ValueDefinition::NativeBody([], int, {
        hint: @ir.NativeHint::Arithmetic,
        description: None,
      }),
      @ir.ValueDefinition::ExternalBody(
        [],
        int,
        [{ target_platform: "scheme", external_name: "missing", }],
        None,
      ),
    ] {
    let plan = @execution.plan_scheme(
      selected_unit(unused),
      selected_suite(),
      policy=@execution.Permissive,
    )
    assert_eq(plan.evaluate().map(v => v.to_json()), [
      { "type": "int", "value": "42" },
    ])
  }
}

///|
test "selected entry authority arity and values remain mandatory" {
  let unit = @data.IRUnit::new("test", @fixtures.invocation_library())
  for
    (entry, arguments, expected) in [
      ("calls:main#private", [], "execution.entry_not_public_or_supported"),
      ("calls:main#missing", [], "execution.entry_not_public_or_supported"),
      ("calls:main#subtract", [], "execution.wrong_arity"),
      ("calls:main#integer", [@protocol.Boolean(false)], "execution.wrong_type"),
    ] {
    let code = try {
      ignore(
        @execution.plan_scheme(
          unit,
          { extensions: None, calls: [{ id: "c", entry, arguments, }], },
          policy=@execution.Permissive,
        ),
      )
      "accepted"
    } catch {
      @protocol.Invalid(code) => code.split(":").next().unwrap().to_owned()
      _ => "unexpected"
    }
    assert_eq(code, expected)
  }
}

///|
fn selected_tree_unit(hidden : Bool, bad_variant : Bool) -> @data.IRUnit raise {
  let int = selected_int()
  let tree = @ir.Type::Reference(
    @ir.TypeAttributes::default(),
    @ir.FQName::parse("selected:main#tree"),
    [],
  )
  let unit = selected_unit(
    @ir.ValueDefinition::IncompleteBody(
      [],
      Some(int),
      @ir.Incompleteness::Draft,
      None,
    ),
  )
  guard unit.distribution.distribution is Library(_, _, package_def) else {
    abort("test")
  }
  let module_def = package_def.modules[@ir.Path::parse("main")].value
  module_def.types[@ir.Name::parse("tree")] = {
    access: @ir.Access::Public,
    value: {
      doc: None,
      value: @ir.TypeDefinition::CustomTypeDefinition([], {
        access: if hidden {
          @ir.Access::Private
        } else {
          @ir.Access::Public
        },
        value: Map::from_array([
          (@ir.Name::parse("empty"), []),
          (
            @ir.Name::parse("node"),
            [
              (
                @ir.Name::parse("child"),
                if bad_variant {
                  @ir.Type::Function(@ir.TypeAttributes::default(), int, int)
                } else {
                  tree
                },
              ),
            ],
          ),
        ]),
      }),
    },
  }
  module_def.values[@ir.Name::parse("answer")] = {
    access: @ir.Access::Public,
    value: {
      doc: None,
      value: @ir.ValueDefinition::ExpressionBody(
        [(@ir.Name::parse("item"), tree)],
        tree,
        @ir.Value::Variable(
          @ir.ValueAttributes::default(),
          @ir.Name::parse("item"),
        ),
      ),
    },
  }
  unit
}

///|
test "selected named recursive custom closure includes every declared constructor" {
  let suite = selected_suite()
  suite.calls[0].arguments.push(
    @protocol.Constructor("selected:main#tree", "selected:main#empty", []),
  )
  let plan = @execution.plan_scheme(
    selected_tree_unit(false, false),
    suite,
    policy=@execution.Permissive,
  )
  assert_eq(plan.evaluate(), suite.calls.map(c => c.arguments[0]))
  assert_eq(plan.boundary_json(), {
    "entries": [
      {
        "name": "selected:main#answer",
        "inputs": [{ "type": "custom", "name": "selected:main#tree" }],
        "output": { "type": "custom", "name": "selected:main#tree" },
      },
    ],
    "definitions": [
      {
        "name": "selected:main#tree",
        "constructors": [
          { "name": "selected:main#empty", "inputs": [] },
          {
            "name": "selected:main#node",
            "inputs": [{ "type": "custom", "name": "selected:main#tree" }],
          },
        ],
      },
    ],
  })
  for
    (hidden, bad_variant, expected) in [
      (true, false, "execution.constructor_visibility"),
      (false, true, "execution.boundary_function"),
    ] {
    let code = try {
      ignore(
        @execution.plan_scheme(
          selected_tree_unit(hidden, bad_variant),
          suite,
          policy=@execution.Permissive,
        ),
      )
      "accepted"
    } catch {
      @execution.AdmissionInvalid(code) => code
      _ => "unexpected"
    }
    assert_eq(code, expected)
  }
}

///|
test "captured source calls and boundary projections cannot be edited by callers" {
  let unit = @data.IRUnit::new("test", @fixtures.invocation_library())
  let suite = scalar_suite("45", "3")
  let plan = @execution.plan_scheme(unit, suite, policy=@execution.Permissive)
  suite.calls[0].arguments[0] = @protocol.Boolean(false)
  guard unit.distribution.distribution is Library(_, _, package_def) else {
    abort("test")
  }
  package_def.modules.clear()
  let boundary = plan.boundary_json()
  guard boundary is Object(fields) && fields["entries"] is Array(entries) else {
    abort("test")
  }
  entries.clear()
  assert_eq(plan.evaluate().map(v => v.to_json()), [
    { "type": "int", "value": "42" },
  ])
  guard plan.boundary_json() is Object(fresh) &&
    fresh["entries"] is Array(retained) else {
    abort("test")
  }
  assert_eq(retained.length(), 1)
}

///|
test "Scheme output publication uses the captured selected declared type" {
  let int = selected_int()
  let unit = selected_unit(
    @ir.ValueDefinition::IncompleteBody(
      [],
      Some(int),
      @ir.Incompleteness::Draft,
      None,
    ),
  )
  selected_definition(
    unit,
    [],
    @ir.Type::Reference(
      @ir.TypeAttributes::default(),
      @ir.FQName::parse("morphir/SDK:basics#bool"),
      [],
    ),
  )
  let plan = @execution.plan_scheme(
    unit,
    selected_suite(),
    policy=@execution.Permissive,
  )
  let rejected = try {
    ignore(plan.evaluate())
    false
  } catch {
    @protocol.Invalid(_) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "selected preparation retains a global function and its curried arguments" {
  let int = selected_int()
  let parameter = @ir.Name::parse("item")
  let attrs = @ir.ValueAttributes::default()
  let unit = selected_unit(
    @ir.ValueDefinition::ExpressionBody(
      [(parameter, int)],
      int,
      @ir.Value::Variable(attrs, parameter),
    ),
  )
  guard unit.distribution.distribution is Library(_, _, package_def) else {
    abort("test")
  }
  let values = package_def.modules[@ir.Path::parse("main")].value.values
  let name = @ir.Name::parse("answer")
  let previous = values[name]
  values[name] = {
    ..previous,
    value: {
      ..previous.value,
      value: @ir.ValueDefinition::ExpressionBody(
        [],
        int,
        @ir.Value::Apply(
          attrs,
          @ir.Value::Reference(attrs, @ir.FQName::parse("selected:main#unused")),
          @ir.Value::Literal(attrs, @ir.Literal::IntegerLiteral("42")),
        ),
      ),
    },
  }
  let plan = @execution.plan_scheme(
    unit,
    selected_suite(),
    policy=@execution.Permissive,
  )
  assert_eq(plan.evaluate().map(v => v.to_json()), [
    { "type": "int", "value": "42" },
  ])
}

///|
test "a local binding shadows an unsupported global while scanning conditional branches" {
  let int = selected_int()
  let parameter = @ir.Name::parse("unused")
  let attrs = @ir.ValueAttributes::default()
  let unit = selected_unit(
    @ir.ValueDefinition::NativeBody([], int, {
      hint: @ir.NativeHint::Arithmetic,
      description: None,
    }),
  )
  guard unit.distribution.distribution is Library(_, _, package_def) else {
    abort("test")
  }
  let values = package_def.modules[@ir.Path::parse("main")].value.values
  let name = @ir.Name::parse("answer")
  let previous = values[name]
  values[name] = {
    ..previous,
    value: {
      ..previous.value,
      value: @ir.ValueDefinition::ExpressionBody(
        [],
        int,
        @ir.Value::LetDefinition(
          attrs,
          parameter,
          @ir.ValueDefinition::ExpressionBody(
            [],
            int,
            @ir.Value::Literal(attrs, @ir.Literal::IntegerLiteral("42")),
          ),
          @ir.Value::IfThenElse(
            attrs,
            @ir.Value::Literal(attrs, @ir.Literal::BoolLiteral(true)),
            @ir.Value::Variable(attrs, parameter),
            @ir.Value::Variable(attrs, parameter),
          ),
        ),
      ),
    },
  }
  let plan = @execution.plan_scheme(
    unit,
    selected_suite(),
    policy=@execution.Permissive,
  )
  assert_eq(plan.evaluate().map(v => v.to_json()), [
    { "type": "int", "value": "42" },
  ])
}

///|
test "selected runtime constructors produce values admitted by the recursive context" {
  let unit = selected_tree_unit(false, false)
  guard unit.distribution.distribution is Library(_, _, package_def) else {
    abort("test")
  }
  let values = package_def.modules[@ir.Path::parse("main")].value.values
  let name = @ir.Name::parse("answer")
  let previous = values[name]
  let tree = @ir.Type::Reference(
    @ir.TypeAttributes::default(),
    @ir.FQName::parse("selected:main#tree"),
    [],
  )
  let attrs = @ir.ValueAttributes::default()
  values[name] = {
    ..previous,
    value: {
      ..previous.value,
      value: @ir.ValueDefinition::ExpressionBody(
        [],
        tree,
        @ir.Value::Apply(
          attrs,
          @ir.Value::Constructor(attrs, @ir.FQName::parse("selected:main#node")),
          @ir.Value::Constructor(
            attrs,
            @ir.FQName::parse("selected:main#empty"),
          ),
        ),
      ),
    },
  }
  let plan = @execution.plan_scheme(
    unit,
    selected_suite(),
    policy=@execution.Permissive,
  )
  assert_eq(plan.evaluate(), [
    @protocol.Constructor("selected:main#tree", "selected:main#node", [
      @protocol.Constructor("selected:main#tree", "selected:main#empty", []),
    ]),
  ])
}

///|
test "whole source budgets and dormant duplicate identities remain admission checks" {
  let int = selected_int()
  let unit = selected_unit(
    @ir.ValueDefinition::IncompleteBody(
      [],
      Some(int),
      @ir.Incompleteness::Draft,
      None,
    ),
  )
  let code = try {
    ignore(
      @execution.plan_scheme(
        unit,
        selected_suite(),
        policy=@execution.Permissive,
        limits={ max_bytes: 1, max_depth: 128, max_values: 100000, },
      ),
    )
    "accepted"
  } catch {
    @data.Invalid(code, _) => code
    _ => "unexpected"
  }
  assert_eq(code, "data.byte_limit")
  guard unit.distribution.distribution is Library(_, _, package_def) else {
    abort("test")
  }
  let values = package_def.modules[@ir.Path::parse("main")].value.values
  let name = @ir.Name::parse("unused")
  let previous = values[name]
  values[name] = {
    ..previous,
    value: {
      ..previous.value,
      value: @ir.ValueDefinition::IncompleteBody(
        [(@ir.Name::parse("same"), int), (@ir.Name::parse("same"), int)],
        Some(int),
        @ir.Incompleteness::Draft,
        None,
      ),
    },
  }
  let rejected = try {
    ignore(
      @execution.plan_scheme(
        unit,
        selected_suite(),
        policy=@execution.Permissive,
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "selected output closure rejects unresolved references alias cycles and open types" {
  let int = selected_int()
  let cyclic = @ir.Type::Reference(
    @ir.TypeAttributes::default(),
    @ir.FQName::parse("selected:main#loop"),
    [],
  )
  let missing = @ir.Type::Reference(
    @ir.TypeAttributes::default(),
    @ir.FQName::parse("selected:main#missing"),
    [],
  )
  for
    (output, expected) in [
      (cyclic, "execution.unsupported_type"),
      (missing, "execution.unresolved_custom_type"),
      (
        @ir.Type::Function(@ir.TypeAttributes::default(), int, int),
        "execution.boundary_function",
      ),
      (
        @ir.Type::ExtensibleRecord(
          @ir.TypeAttributes::default(),
          @ir.Name::parse("row"),
          Map([]),
        ),
        "execution.unsupported_type",
      ),
    ] {
    let unit = selected_unit(
      @ir.ValueDefinition::IncompleteBody(
        [],
        Some(int),
        @ir.Incompleteness::Draft,
        None,
      ),
    )
    guard unit.distribution.distribution is Library(_, _, package_def) else {
      abort("test")
    }
    package_def.modules[@ir.Path::parse("main")].value.types[@ir.Name::parse(
      "loop",
    )] = {
      access: @ir.Access::Public,
      value: {
        doc: None,
        value: @ir.TypeDefinition::TypeAliasDefinition([], cyclic),
      },
    }
    selected_definition(unit, [], output)
    let code = try {
      ignore(
        @execution.plan_scheme(
          unit,
          selected_suite(),
          policy=@execution.Permissive,
        ),
      )
      "accepted"
    } catch {
      @execution.AdmissionInvalid(code) => code
      _ => "unexpected"
    }
    assert_eq(code, expected)
  }
}

///|
test "all selected custom alternatives obey constructor payload limits" {
  let unit = selected_tree_unit(false, false)
  guard unit.distribution.distribution is Library(_, _, package_def) else {
    abort("test")
  }
  let types = package_def.modules[@ir.Path::parse("main")].value.types
  let name = @ir.Name::parse("tree")
  let previous = types[name]
  guard previous.value.value is CustomTypeDefinition(_, variants) else {
    abort("test")
  }
  variants.value[@ir.Name::parse("oversized")] = Array::makei(65, i => {
    (@ir.Name::parse("field-" + i.to_string()), selected_int())
  })
  let suite = selected_suite()
  suite.calls[0].arguments.push(
    @protocol.Constructor("selected:main#tree", "selected:main#empty", []),
  )
  let code = try {
    ignore(@execution.plan_scheme(unit, suite, policy=@execution.Permissive))
    "accepted"
  } catch {
    @execution.AdmissionInvalid(code) => code
    _ => "unexpected"
  }
  assert_eq(code, "execution.type_limit")
}

///|
test "constructor identity conflicts reject globally while separate type and value names coexist" {
  let unit = selected_tree_unit(false, false)
  guard unit.distribution.distribution is Library(_, _, package_def) else {
    abort("test")
  }
  let module_def = package_def.modules[@ir.Path::parse("main")].value
  let tree = module_def.types[@ir.Name::parse("tree")]
  let suite = selected_suite()
  suite.calls[0].arguments.push(
    @protocol.Constructor("selected:main#tree", "selected:main#empty", []),
  )
  module_def.values[@ir.Name::parse("tree")] = module_def.values[@ir.Name::parse(
      "unused",
    )]
  ignore(
    @execution.plan_scheme(unit, suite, policy=@execution.Permissive).evaluate(),
  )
  module_def.types[@ir.Name::parse("duplicate")] = tree
  let code = try {
    ignore(@execution.plan_scheme(unit, suite, policy=@execution.Permissive))
    "accepted"
  } catch {
    @execution.AdmissionInvalid(code) => code
    _ => "unexpected"
  }
  assert_eq(code, "execution.ambiguous_identity")
}

///|
test "output validator rejects wrong inventories values and unrecognized model errors" {
  let int = selected_int()
  let plan = @execution.plan_scheme(
    selected_unit(
      @ir.ValueDefinition::IncompleteBody(
        [],
        Some(int),
        @ir.Incompleteness::Draft,
        None,
      ),
    ),
    selected_suite(),
    policy=@execution.Permissive,
  )
  for
    values in [
      [],
      [@protocol.Boolean(true)],
      [@protocol.ModelError("private-sentinel")],
    ] {
    let rejected = try {
      plan.validate_outputs(values)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "private aliases remain transparent locally but cannot cross module access boundaries" {
  let int = selected_int()
  for
    (owner, expected) in [
      ("main", "accepted"),
      ("other", "execution.constructor_visibility"),
    ] {
    let unit = selected_unit(
      @ir.ValueDefinition::IncompleteBody(
        [],
        Some(int),
        @ir.Incompleteness::Draft,
        None,
      ),
    )
    guard unit.distribution.distribution is Library(_, _, package_def) else {
      abort("test")
    }
    let module_name = @ir.Path::parse(owner)
    if owner != "main" {
      package_def.modules[module_name] = {
        access: @ir.Access::Public,
        value: { types: Map([]), values: Map([]), doc: None, },
      }
    }
    package_def.modules[module_name].value.types[@ir.Name::parse("hidden")] = {
      access: @ir.Access::Private,
      value: {
        doc: None,
        value: @ir.TypeDefinition::TypeAliasDefinition([], int),
      },
    }
    selected_definition(
      unit,
      [],
      @ir.Type::Reference(
        @ir.TypeAttributes::default(),
        @ir.FQName::parse("selected:" + owner + "#hidden"),
        [],
      ),
    )
    let code = try {
      ignore(
        @execution.plan_scheme(
          unit,
          selected_suite(),
          policy=@execution.Permissive,
        ),
      )
      "accepted"
    } catch {
      @execution.AdmissionInvalid(code) => code
      _ => "unexpected"
    }
    assert_eq(code, expected)
  }
}

///|
test "needed private values reject cross module access while local private calls remain valid" {
  let int = selected_int()
  for
    (owner, expected) in [
      ("main", "accepted"),
      ("other", "execution.reference_visibility"),
    ] {
    let unit = selected_unit(
      @ir.ValueDefinition::IncompleteBody(
        [],
        Some(int),
        @ir.Incompleteness::Draft,
        None,
      ),
    )
    guard unit.distribution.distribution is Library(_, _, package_def) else {
      abort("test")
    }
    let module_name = @ir.Path::parse(owner)
    if owner != "main" {
      package_def.modules[module_name] = {
        access: @ir.Access::Public,
        value: { types: Map([]), values: Map([]), doc: None, },
      }
    }
    let attrs = @ir.ValueAttributes::default()
    package_def.modules[module_name].value.values[@ir.Name::parse("helper")] = {
      access: @ir.Access::Private,
      value: {
        doc: None,
        value: @ir.ValueDefinition::ExpressionBody(
          [],
          int,
          @ir.Value::Literal(attrs, @ir.Literal::IntegerLiteral("42")),
        ),
      },
    }
    let values = package_def.modules[@ir.Path::parse("main")].value.values
    let name = @ir.Name::parse("answer")
    let old = values[name]
    values[name] = {
      ..old,
      value: {
        ..old.value,
        value: @ir.ValueDefinition::ExpressionBody(
          [],
          int,
          @ir.Value::Reference(
            attrs,
            @ir.FQName::parse("selected:" + owner + "#helper"),
          ),
        ),
      },
    }
    let code = try {
      ignore(
        @execution.plan_scheme(
          unit,
          selected_suite(),
          policy=@execution.Permissive,
        ).evaluate(),
      )
      "accepted"
    } catch {
      @execution.AdmissionInvalid(code) => code
      _ => "unexpected"
    }
    assert_eq(code, expected)
  }
}

///|
test "private constructor use remains local even when the public boundary is scalar" {
  let int = selected_int()
  let attrs = @ir.ValueAttributes::default()
  for
    (owner, expected) in [
      ("main", "accepted"),
      ("other", "execution.constructor_visibility"),
    ] {
    let unit = selected_unit(
      @ir.ValueDefinition::IncompleteBody(
        [],
        Some(int),
        @ir.Incompleteness::Draft,
        None,
      ),
    )
    guard unit.distribution.distribution is Library(_, _, package_def) else {
      abort("test")
    }
    let module_name = @ir.Path::parse(owner)
    if owner != "main" {
      package_def.modules[module_name] = {
        access: @ir.Access::Public,
        value: { types: Map([]), values: Map([]), doc: None, },
      }
    }
    package_def.modules[module_name].value.types[@ir.Name::parse("hidden")] = {
      access: @ir.Access::Private,
      value: {
        doc: None,
        value: @ir.TypeDefinition::CustomTypeDefinition([], {
          access: @ir.Access::Private,
          value: Map::from_array([(@ir.Name::parse("empty"), [])]),
        }),
      },
    }
    let values = package_def.modules[@ir.Path::parse("main")].value.values
    let name = @ir.Name::parse("answer")
    let previous = values[name]
    values[name] = {
      ..previous,
      value: {
        ..previous.value,
        value: @ir.ValueDefinition::ExpressionBody(
          [],
          int,
          @ir.Value::PatternMatch(
            attrs,
            @ir.Value::Constructor(
              attrs,
              @ir.FQName::parse("selected:" + owner + "#empty"),
            ),
            [
              (
                @ir.Pattern::WildcardPattern(attrs),
                @ir.Value::Literal(attrs, @ir.Literal::IntegerLiteral("42")),
              ),
            ],
          ),
        ),
      },
    }
    let code = try {
      ignore(
        @execution.plan_scheme(
          unit,
          selected_suite(),
          policy=@execution.Permissive,
        ).evaluate(),
      )
      "accepted"
    } catch {
      @execution.AdmissionInvalid(code) => code
      _ => "unexpected"
    }
    assert_eq(code, expected)
  }
}

///|
test "unused constructor metadata does not register unsupported runtime arities" {
  let int = selected_int()
  let unit = selected_unit(
    @ir.ValueDefinition::IncompleteBody(
      [],
      Some(int),
      @ir.Incompleteness::Draft,
      None,
    ),
  )
  guard unit.distribution.distribution is Library(_, _, package_def) else {
    abort("test")
  }
  package_def.modules[@ir.Path::parse("main")].value.types[@ir.Name::parse(
    "unused-type",
  )] = {
    access: @ir.Access::Public,
    value: {
      doc: None,
      value: @ir.TypeDefinition::CustomTypeDefinition([], {
        access: @ir.Access::Public,
        value: Map::from_array([
          (
            @ir.Name::parse("large"),
            Array::makei(300, i => {
              (@ir.Name::parse("field-" + i.to_string()), int)
            }),
          ),
        ]),
      }),
    },
  }
  let plan = @execution.plan_scheme(
    unit,
    selected_suite(),
    policy=@execution.Permissive,
  )
  assert_eq(plan.evaluate().map(v => v.to_json()), [
    { "type": "int", "value": "42" },
  ])
}

///|
test "needed missing native bindings keep their own evaluation failure" {
  let int = selected_int()
  let unit = selected_unit(
    @ir.ValueDefinition::NativeBody([], int, {
      hint: @ir.NativeHint::Arithmetic,
      description: None,
    }),
  )
  let suite : @protocol.Suite = {
    extensions: None,
    calls: [{ id: "native", entry: "selected:main#unused", arguments: [], }],
  }
  let plan = @execution.plan_scheme(unit, suite, policy=@execution.Permissive)
  let unbound = try {
    ignore(plan.evaluate())
    false
  } catch {
    @scheme.Unbound(_) => true
    _ => false
  }
  assert_true(unbound)
}

///|
test "admitted context byte budget bounds repeated alias expansion" {
  let int = selected_int()
  let unit = selected_unit(
    @ir.ValueDefinition::IncompleteBody(
      [],
      Some(int),
      @ir.Incompleteness::Draft,
      None,
    ),
  )
  guard unit.distribution.distribution is Library(_, _, package_def) else {
    abort("test")
  }
  let fields = Map([])
  let prefix = Array::make(1000, "a").join("")
  for i = 0; i < 4; i = i + 1 {
    fields[@ir.Name::parse(prefix + i.to_string())] = int
  }
  package_def.modules[@ir.Path::parse("main")].value.types[@ir.Name::parse(
    "wide",
  )] = {
    access: @ir.Access::Public,
    value: {
      doc: None,
      value: @ir.TypeDefinition::TypeAliasDefinition(
        [],
        @ir.Type::Record(@ir.TypeAttributes::default(), fields),
      ),
    },
  }
  let repeated = @ir.Type::Reference(
    @ir.TypeAttributes::default(),
    @ir.FQName::parse("selected:main#wide"),
    [],
  )
  selected_definition(
    unit,
    [],
    @ir.Type::Tuple(@ir.TypeAttributes::default(), Array::make(300, repeated)),
  )
  let code = try {
    ignore(
      @execution.plan_scheme(
        unit,
        selected_suite(),
        policy=@execution.Permissive,
      ),
    )
    "accepted"
  } catch {
    @execution.AdmissionInvalid(code) => code
    _ => "unexpected"
  }
  assert_eq(code, "execution.type_limit")
}

///|
test "public aliases resolve private helper aliases in their declaring module" {
  let int = selected_int()
  for
    (target, expected) in [
      ("public-alias", "accepted"),
      ("helper", "execution.constructor_visibility"),
    ] {
    let unit = selected_unit(
      @ir.ValueDefinition::IncompleteBody(
        [],
        Some(int),
        @ir.Incompleteness::Draft,
        None,
      ),
    )
    guard unit.distribution.distribution is Library(_, _, package_def) else {
      abort("test")
    }
    let helper = @ir.Type::Reference(
      @ir.TypeAttributes::default(),
      @ir.FQName::parse("selected:other#helper"),
      [],
    )
    package_def.modules[@ir.Path::parse("other")] = {
      access: @ir.Access::Public,
      value: {
        types: Map::from_array([
          (
            @ir.Name::parse("helper"),
            {
              access: @ir.Access::Private,
              value: {
                doc: None,
                value: @ir.TypeDefinition::TypeAliasDefinition([], int),
              },
            },
          ),
          (
            @ir.Name::parse("public-alias"),
            {
              access: @ir.Access::Public,
              value: {
                doc: None,
                value: @ir.TypeDefinition::TypeAliasDefinition([], helper),
              },
            },
          ),
        ]),
        values: Map([]),
        doc: None,
      },
    }
    selected_definition(
      unit,
      [],
      @ir.Type::Reference(
        @ir.TypeAttributes::default(),
        @ir.FQName::parse("selected:other#" + target),
        [],
      ),
    )
    let code = try {
      let plan = @execution.plan_scheme(
        unit,
        selected_suite(),
        policy=@execution.Permissive,
      )
      assert_eq(plan.evaluate().map(v => v.to_json()), [
        { "type": "int", "value": "42" },
      ])
      "accepted"
    } catch {
      @execution.AdmissionInvalid(code) => code
      _ => "unexpected"
    }
    assert_eq(code, expected)
  }
}

///|
test "missing expression and pattern constructors reject during selected planning" {
  let int = selected_int()
  let attrs = @ir.ValueAttributes::default()
  for
    (key, pattern) in [
      ("selected:main#missing", false),
      ("selected:main#missing", true),
      ("morphir/SDK:maybe#missing", false),
      ("morphir/SDK:result#missing", true),
    ] {
    let unit = selected_unit(
      @ir.ValueDefinition::IncompleteBody(
        [],
        Some(int),
        @ir.Incompleteness::Draft,
        None,
      ),
    )
    guard unit.distribution.distribution is Library(_, _, package_def) else {
      abort("test")
    }
    let values = package_def.modules[@ir.Path::parse("main")].value.values
    let name = @ir.Name::parse("answer")
    let old = values[name]
    let missing = @ir.FQName::parse(key)
    let body = if pattern {
      @ir.Value::PatternMatch(attrs, @ir.Value::Unit(attrs), [
        (
          @ir.Pattern::ConstructorPattern(attrs, missing, []),
          @ir.Value::Literal(attrs, @ir.Literal::IntegerLiteral("42")),
        ),
      ])
    } else {
      @ir.Value::Constructor(attrs, missing)
    }
    values[name] = {
      ..old,
      value: {
        ..old.value,
        value: @ir.ValueDefinition::ExpressionBody([], int, body),
      },
    }
    let rejected = try {
      ignore(
        @execution.plan_scheme(
          unit,
          selected_suite(),
          policy=@execution.Permissive,
        ),
      )
      false
    } catch {
      @scheme.Unbound(actual) => actual == key
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "the four registered SDK constructors remain valid expressions and patterns" {
  let int = selected_int()
  let attrs = @ir.ValueAttributes::default()
  let cases : Array[(String, Json)] = [
    ("morphir/SDK:maybe#nothing", { "type": "maybe", "case": "nothing" }),
    (
      "morphir/SDK:maybe#just",
      {
        "type": "maybe",
        "case": "just",
        "value": { "type": "int", "value": "42" },
      },
    ),
    (
      "morphir/SDK:result#ok",
      {
        "type": "result",
        "case": "ok",
        "value": { "type": "int", "value": "42" },
      },
    ),
    (
      "morphir/SDK:result#err",
      {
        "type": "result",
        "case": "err",
        "value": { "type": "int", "value": "42" },
      },
    ),
  ]
  for (key, expected) in cases {
    for pattern in [false, true] {
      let unit = selected_unit(
        @ir.ValueDefinition::IncompleteBody(
          [],
          Some(int),
          @ir.Incompleteness::Draft,
          None,
        ),
      )
      guard unit.distribution.distribution is Library(_, _, package_def) else {
        abort("test")
      }
      let fqname = @ir.FQName::parse(key)
      let unary = key != "morphir/SDK:maybe#nothing"
      let value = @ir.Value::Constructor(attrs, fqname)
      let value = if unary {
        @ir.Value::Apply(
          attrs,
          value,
          @ir.Value::Literal(attrs, @ir.Literal::IntegerLiteral("42")),
        )
      } else {
        value
      }
      let maybe = key.has_prefix("morphir/SDK:maybe#")
      let output = if pattern {
        int
      } else {
        @ir.Type::Reference(
          @ir.TypeAttributes::default(),
          @ir.FQName::parse(
            if maybe {
              "morphir/SDK:maybe#maybe"
            } else {
              "morphir/SDK:result#result"
            },
          ),
          if maybe {
            [int]
          } else {
            [int, int]
          },
        )
      }
      let body = if pattern {
        @ir.Value::PatternMatch(attrs, value, [
          (
            @ir.Pattern::ConstructorPattern(
              attrs,
              fqname,
              if unary {
                [@ir.Pattern::WildcardPattern(attrs)]
              } else {
                []
              },
            ),
            @ir.Value::Literal(attrs, @ir.Literal::IntegerLiteral("42")),
          ),
        ])
      } else {
        value
      }
      let values = package_def.modules[@ir.Path::parse("main")].value.values
      let name = @ir.Name::parse("answer")
      let old = values[name]
      values[name] = {
        ..old,
        value: {
          ..old.value,
          value: @ir.ValueDefinition::ExpressionBody([], output, body),
        },
      }
      let plan = @execution.plan_scheme(
        unit,
        selected_suite(),
        policy=@execution.Permissive,
      )
      assert_eq(plan.evaluate(), [
        @protocol.Value::from_json(
          if pattern {
            { "type": "int", "value": "42" }
          } else {
            expected
          },
        ),
      ])
    }
  }
}
