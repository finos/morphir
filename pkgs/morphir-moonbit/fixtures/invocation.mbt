///|
pub fn invocation_library() -> @ir.IRFile raise {
  let int = scalar("morphir/SDK:basics#int")
  let bool = scalar("morphir/SDK:basics#bool")
  let int32 = scalar("morphir/SDK:int#int-32")
  let unit = @ir.Type::Unit({
    source: None,
    constraints: Map([]),
    extensions: Map([]),
  })
  let a = @ir.Name::parse("a")
  let b = @ir.Name::parse("b")
  let values : Map[
    @ir.Name,
    @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]],
  ] = Map([])
  values[@ir.Name::parse("subtract")] = {
    access: @ir.Access::Public,
    value: {
      doc: None,
      value: @ir.ValueDefinition::ExpressionBody(
        [(a, int), (b, int)],
        int,
        @ir.Value::Apply(
          attrs(),
          @ir.Value::Apply(
            attrs(),
            ref_value(
              "morphir/SDK:basics#subtract",
              arrow(int, arrow(int, int)),
            ),
            @ir.Value::Variable(attrs(), a),
          ),
          @ir.Value::Variable(attrs(), b),
        ),
      ),
    },
  }
  for
    (name, tpe) in [
      ("boolean", bool),
      ("unit", unit),
      ("integer", int),
      ("signed32", int32),
    ] {
    values[@ir.Name::parse(name)] = {
      access: @ir.Access::Public,
      value: {
        doc: None,
        value: @ir.ValueDefinition::ExpressionBody(
          [(a, tpe)],
          tpe,
          @ir.Value::Variable(attrs(), a),
        ),
      },
    }
  }
  values[@ir.Name::parse("private")] = definition(
    int,
    @ir.Value::Literal(attrs(), @ir.Literal::IntegerLiteral("99")),
    access=@ir.Access::Private,
  )
  @ir.IRFile::new(
    @ir.Distribution::Library(@ir.Path::parse("calls"), Map([]), {
      modules: Map::from_array([
        (
          @ir.Path::parse("main"),
          {
            access: @ir.Access::Public,
            value: { types: Map([]), values, doc: None, },
          },
        ),
      ]),
    }),
  )
}
