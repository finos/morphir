///|
pub fn scalar(name : String) -> @ir.Type raise {
  @ir.Type::Reference(
    { source: None, constraints: Map([]), extensions: Map([]), },
    @ir.FQName::parse(name),
    [],
  )
}

///|
pub fn attrs() -> @ir.ValueAttributes {
  { source: None, inferred_type: None, extensions: Map([]), }
}

///|
pub fn definition(
  output : @ir.Type,
  body : @ir.Value,
  access~ : @ir.Access = @ir.Access::Public,
) -> @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]] {
  {
    access,
    value: {
      doc: Some("Scalar fixture"),
      value: @ir.ValueDefinition::ExpressionBody([], output, body),
    },
  }
}

///|
pub fn library(reverse~ : Bool = false) -> @ir.IRFile raise {
  let integer = scalar("morphir/SDK:basics#int")
  let decimal = scalar("morphir/SDK:decimal#decimal")
  let boolean = scalar("morphir/SDK:basics#bool")
  let float = scalar("morphir/SDK:basics#float")
  let text = scalar("morphir/SDK:string#string")
  let character = scalar("morphir/SDK:char#char")
  let unit = @ir.Type::Unit({
    source: None,
    constraints: Map([]),
    extensions: Map([]),
  })
  let entries = [
    (
      "huge",
      definition(
        integer,
        @ir.Value::Literal(
          attrs(),
          @ir.Literal::IntegerLiteral(
            "1234567890123456789012345678901234567890",
          ),
        ),
      ),
    ),
    (
      "rate",
      definition(
        decimal,
        @ir.Value::Literal(attrs(), @ir.Literal::DecimalLiteral("+12.3400E-2")),
      ),
    ),
    (
      "negative-zero",
      definition(
        float,
        @ir.Value::Literal(attrs(), @ir.Literal::FloatLiteral(-0.0)),
      ),
    ),
    (
      "tiny",
      definition(
        float,
        @ir.Value::Literal(attrs(), @ir.Literal::FloatLiteral(5.0e-324)),
      ),
    ),
    (
      "enabled",
      definition(
        boolean,
        @ir.Value::Literal(attrs(), @ir.Literal::BoolLiteral(true)),
      ),
    ),
    (
      "label",
      definition(
        text,
        @ir.Value::Literal(
          attrs(),
          @ir.Literal::StringLiteral("λ😀\n\"\\$(forbidden)"),
        ),
      ),
    ),
    (
      "letter",
      definition(
        character,
        @ir.Value::Literal(attrs(), @ir.Literal::CharLiteral('😀')),
      ),
    ),
    ("nothing", definition(unit, @ir.Value::Unit(attrs()))),
    (
      "hidden",
      definition(
        boolean,
        @ir.Value::Literal(attrs(), @ir.Literal::BoolLiteral(false)),
        access=@ir.Access::Private,
      ),
    ),
    (
      "SDK",
      definition(
        boolean,
        @ir.Value::Literal(attrs(), @ir.Literal::BoolLiteral(true)),
      ),
    ),
    (
      "sdk",
      definition(
        boolean,
        @ir.Value::Literal(attrs(), @ir.Literal::BoolLiteral(false)),
      ),
    ),
  ]
  let entries = if reverse {
    Array::makei(entries.length(), fn(i) { entries[entries.length() - 1 - i] })
  } else {
    entries
  }
  let values = Map([])
  for (name, value) in entries {
    values[@ir.Name::parse(name)] = value
  }
  let main : @ir.ModuleDefinition = {
    types: Map([]),
    values,
    doc: Some("Main scalars"),
  }
  let other : @ir.ModuleDefinition = {
    types: Map([]),
    doc: None,
    values: Map::from_array([
      (
        @ir.Name::parse("copy"),
        definition(
          integer,
          @ir.Value::Reference(
            attrs(),
            @ir.FQName::parse("pricing:scalars#huge"),
          ),
        ),
      ),
    ]),
  }
  let internal : @ir.ModuleDefinition = {
    types: Map([]),
    doc: None,
    values: Map::from_array([
      (
        @ir.Name::parse("secret"),
        definition(
          boolean,
          @ir.Value::Literal(attrs(), @ir.Literal::BoolLiteral(true)),
        ),
      ),
    ]),
  }
  let modules = [
    (
      @ir.Path::parse("scalars"),
      @ir.AccessControlled::{ access: @ir.Access::Public, value: main, },
    ),
    (
      @ir.Path::parse("other"),
      @ir.AccessControlled::{ access: @ir.Access::Public, value: other, },
    ),
    (
      @ir.Path::parse("internal"),
      @ir.AccessControlled::{ access: @ir.Access::Private, value: internal, },
    ),
  ]
  let modules = if reverse {
    Array::makei(modules.length(), fn(i) { modules[modules.length() - 1 - i] })
  } else {
    modules
  }
  @ir.IRFile::new(
    @ir.Distribution::Library(@ir.Path::parse("pricing"), Map([]), {
      modules: Map::from_array(modules),
    }),
  )
}
