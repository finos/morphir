///|
/// Independently authored capture and namespace fixtures for compiler consumers.
pub fn naming_library(reverse~ : Bool = false) -> @ir.IRFile raise {
  let boolean = scalar("morphir/SDK:basics#bool")
  let a = { ..attrs(), inferred_type: Some(boolean), }
  fn literal(value : Bool) -> @ir.Value {
    @ir.Value::Literal(a, @ir.Literal::BoolLiteral(value))
  }
  fn variable(name : String) -> @ir.Value raise {
    @ir.Value::Variable(a, @ir.Name::parse(name))
  }
  let inputs = [
    (@ir.Name::parse("argument-1"), boolean),
    (@ir.Name::parse("function-1"), boolean),
  ]
  let function_type = @ir.Type::Function(
    { source: None, constraints: Map([]), extensions: Map([]), },
    boolean,
    boolean,
  )
  let identity = @ir.Value::Lambda(
    { ..a, inferred_type: Some(function_type), },
    @ir.Pattern::AsPattern(
      a,
      @ir.Pattern::WildcardPattern(a),
      @ir.Name::parse("argument"),
    ),
    variable("argument"),
  )
  let applied = @ir.Value::Apply(a, identity, variable("argument-1"))
  let global = @ir.Value::Reference(a, @ir.FQName::parse("naming:main#ready"))
  let shadowed_global = @ir.Value::LetDefinition(
    a,
    @ir.Name::parse("ready"),
    @ir.ValueDefinition::ExpressionBody([], boolean, literal(false)),
    global,
  )
  let entries = [
    (@ir.Name::parse("ready"), definition(boolean, literal(true))),
    (@ir.Name::parse("if"), definition(boolean, literal(false))),
    (@ir.Name::parse("if-value"), definition(boolean, literal(true))),
    (@ir.Name::parse("copy"), definition(boolean, literal(true))),
    (@ir.Name::parse("other-copy"), definition(boolean, literal(true))),
    (@ir.Name::parse("captured-global"), definition(boolean, shadowed_global)),
    (
      @ir.Name::parse("capture"),
      {
        access: @ir.Access::Public,
        value: {
          doc: None,
          value: @ir.ValueDefinition::ExpressionBody(inputs, boolean, applied),
        },
      },
    ),
  ]
  entries.push(
    (
      @ir.Name::parse("second-capture"),
      {
        access: @ir.Access::Public,
        value: {
          doc: None,
          value: @ir.ValueDefinition::ExpressionBody(
            inputs,
            boolean,
            variable("argument-1"),
          ),
        },
      },
    ),
  )
  let flag = @ir.Name::parse("flag")
  let record_type = @ir.Type::Record(
    { source: None, constraints: Map([]), extensions: Map([]), },
    Map::from_array([(flag, boolean)]),
  )
  let record_attrs = { ..a, inferred_type: Some(record_type), }
  let record = @ir.Value::Record(
    record_attrs,
    Map::from_array([(flag, literal(false))]),
  )
  let updated = @ir.Value::UpdateRecord(
    record_attrs,
    record,
    Map::from_array([(flag, variable("record-1"))]),
  )
  entries.push(
    (
      @ir.Name::parse("record-capture"),
      {
        access: @ir.Access::Public,
        value: {
          doc: None,
          value: @ir.ValueDefinition::ExpressionBody(
            [(@ir.Name::parse("record-1"), boolean)],
            boolean,
            @ir.Value::Field(a, updated, flag),
          ),
        },
      },
    ),
  )
  // These IR types must compile without shadowing MoonBit 0.10.15 built-ins.
  let types : Array[
    (@ir.Name, @ir.AccessControlled[@ir.Documented[@ir.TypeDefinition]]),
  ] = [
    "int-16", "int-32", "u-int-16", "u-int-32", "fixed-array", "bytes-view", "string-view",
  ].map(name => {
    (
      @ir.Name::parse(name),
      {
        access: @ir.Access::Public,
        value: {
          doc: None,
          value: @ir.TypeDefinition::CustomTypeDefinition([], {
            access: @ir.Access::Public,
            value: Map::from_array([(@ir.Name::parse("wrap-" + name), [])]),
          }),
        },
      },
    )
  })
  let modules : Array[(@ir.Path, @ir.AccessControlled[@ir.ModuleDefinition])] = [
    (
      @ir.Path::parse("main"),
      {
        access: @ir.Access::Public,
        value: {
          doc: None,
          types: Map::from_array(if reverse { types.rev() } else { types }),
          values: Map::from_array(if reverse { entries.rev() } else { entries }),
        },
      },
    ),
    (
      @ir.Path::parse("other"),
      {
        access: @ir.Access::Public,
        value: {
          doc: None,
          types: Map([]),
          values: Map::from_array([
            (@ir.Name::parse("copy"), definition(boolean, literal(false))),
          ]),
        },
      },
    ),
  ]
  @ir.IRFile::new(
    @ir.Distribution::Library(@ir.Path::parse("naming"), Map([]), {
      modules: Map::from_array(if reverse { modules.rev() } else { modules }),
    }),
  )
}
