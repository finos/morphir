///|
fn ta() -> @ir.TypeAttributes {
  { source: None, constraints: Map([]), extensions: Map([]), }
}

///|
fn arrow(a : @ir.Type, b : @ir.Type) -> @ir.Type {
  @ir.Type::Function(ta(), a, b)
}

///|
fn va(t : @ir.Type) -> @ir.ValueAttributes {
  { ..attrs(), inferred_type: Some(t), }
}

///|
fn ref_value(name : String, t : @ir.Type) -> @ir.Value raise {
  @ir.Value::Reference(va(t), @ir.FQName::parse(name))
}

///|
fn variable(name : String) -> @ir.Value raise {
  @ir.Value::Variable(attrs(), @ir.Name::parse(name))
}

///|
fn apply(f : @ir.Value, a : @ir.Value) -> @ir.Value {
  @ir.Value::Apply(attrs(), f, a)
}

///|
fn lit_int(n : String) -> @ir.Value {
  @ir.Value::Literal(attrs(), @ir.Literal::IntegerLiteral(n))
}

///|
fn lit_dec(n : String) -> @ir.Value {
  @ir.Value::Literal(attrs(), @ir.Literal::DecimalLiteral(n))
}

///|
fn function(
  inputs : Array[(String, @ir.Type)],
  output : @ir.Type,
  body : @ir.Value,
) -> @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]] raise {
  {
    access: @ir.Access::Public,
    value: {
      doc: None,
      value: @ir.ValueDefinition::ExpressionBody(
        inputs.map(p => (@ir.Name::parse(p.0), p.1)),
        output,
        body,
      ),
    },
  }
}

///|
/// Independent multi-module pricing model, with exact quantities and decimal prices.
pub fn pricing() -> @ir.IRFile raise {
  let base = library()
  guard base.distribution is Library(package_name, dependencies, def) else {
    abort("fixture")
  }
  let modules = def.modules.copy()
  let int = scalar("morphir/SDK:basics#int")
  let dec = scalar("morphir/SDK:decimal#decimal")
  let bool = scalar("morphir/SDK:basics#bool")
  let quote_type = @ir.Type::Record(
    ta(),
    Map::from_array([
      (@ir.Name::parse("price"), dec),
      (@ir.Name::parse("quantity"), int),
    ]),
  )
  let quote_reference = scalar("pricing:quotes#quote")
  let status = scalar("pricing:quotes#status")
  let type_defs : Map[
    @ir.Name,
    @ir.AccessControlled[@ir.Documented[@ir.TypeDefinition]],
  ] = Map::from_array([
    (
      @ir.Name::parse("quote"),
      {
        access: @ir.Access::Public,
        value: {
          doc: None,
          value: @ir.TypeDefinition::TypeAliasDefinition([], quote_type),
        },
      },
    ),
    (
      @ir.Name::parse("status"),
      {
        access: @ir.Access::Public,
        value: {
          doc: None,
          value: @ir.TypeDefinition::CustomTypeDefinition([], {
            access: @ir.Access::Public,
            value: Map::from_array([
              (@ir.Name::parse("approved"), [(@ir.Name::parse("amount"), dec)]),
              (@ir.Name::parse("rejected"), []),
            ]),
          }),
        },
      },
    ),
  ])
  let mul = ref_value("morphir/SDK:decimal#mul", arrow(dec, arrow(dec, dec)))
  let from_int = ref_value("morphir/SDK:decimal#from-int", arrow(int, dec))
  let add = ref_value("morphir/SDK:basics#add", arrow(int, arrow(int, int)))
  let subtract = ref_value(
    "morphir/SDK:basics#subtract",
    arrow(int, arrow(int, int)),
  )
  let quote = @ir.Value::Record(
    va(quote_reference),
    Map::from_array([
      (@ir.Name::parse("quantity"), lit_int("3")),
      (@ir.Name::parse("price"), lit_dec("12.50")),
    ]),
  )
  let total_body = apply(
    apply(
      mul,
      @ir.Value::Field(attrs(), variable("quote"), @ir.Name::parse("price")),
    ),
    apply(
      from_int,
      @ir.Value::Field(attrs(), variable("quote"), @ir.Name::parse("quantity")),
    ),
  )
  let values = Map::from_array([
    (
      @ir.Name::parse("total"),
      function([("quote", quote_reference)], dec, total_body),
    ),
    (@ir.Name::parse("sample"), definition(quote_reference, quote)),
    (
      @ir.Name::parse("reprice"),
      function(
        [("quote", quote_reference), ("price", dec)],
        quote_reference,
        @ir.Value::UpdateRecord(
          attrs(),
          variable("quote"),
          Map::from_array([(@ir.Name::parse("price"), variable("price"))]),
        ),
      ),
    ),
    (
      @ir.Name::parse("difference"),
      function(
        [("first", int), ("second", int)],
        int,
        apply(apply(subtract, variable("first")), variable("second")),
      ),
    ),
    (
      @ir.Name::parse("captured"),
      function(
        [("offset", int)],
        arrow(int, int),
        @ir.Value::Lambda(
          attrs(),
          @ir.Pattern::AsPattern(
            attrs(),
            @ir.Pattern::WildcardPattern(attrs()),
            @ir.Name::parse("amount"),
          ),
          apply(apply(add, variable("offset")), variable("amount")),
        ),
      ),
    ),
    (
      @ir.Name::parse("approved"),
      definition(
        status,
        apply(
          @ir.Value::Constructor(
            va(arrow(dec, status)),
            @ir.FQName::parse("pricing:quotes#approved"),
          ),
          lit_dec("37.50"),
        ),
      ),
    ),
    (
      @ir.Name::parse("status-amount"),
      function(
        [("status", status)],
        dec,
        @ir.Value::PatternMatch(attrs(), variable("status"), [
          (
            @ir.Pattern::ConstructorPattern(
              attrs(),
              @ir.FQName::parse("pricing:quotes#approved"),
              [
                @ir.Pattern::AsPattern(
                  attrs(),
                  @ir.Pattern::WildcardPattern(attrs()),
                  @ir.Name::parse("amount"),
                ),
              ],
            ),
            variable("amount"),
          ),
          (
            @ir.Pattern::ConstructorPattern(
              attrs(),
              @ir.FQName::parse("pricing:quotes#rejected"),
              [],
            ),
            lit_dec("0"),
          ),
        ]),
      ),
    ),
  ])
  modules[@ir.Path::parse("quotes")] = {
    access: @ir.Access::Public,
    value: { types: type_defs, values, doc: None, },
  }
  let total = ref_value("pricing:quotes#total", arrow(quote_reference, dec))
  let sample = ref_value("pricing:quotes#sample", quote_reference)
  let reprice = ref_value(
    "pricing:quotes#reprice",
    arrow(quote_reference, arrow(dec, quote_reference)),
  )
  let int_fn = arrow(int, int)
  let capture = ref_value("pricing:quotes#captured", arrow(int, int_fn))
  let list_int = @ir.Type::Reference(
    ta(),
    @ir.FQName::parse("morphir/SDK:list#list"),
    [int],
  )
  let mapped = apply(
    apply(
      ref_value(
        "morphir/SDK:list#map",
        arrow(int_fn, arrow(list_int, list_int)),
      ),
      apply(capture, lit_int("10")),
    ),
    @ir.Value::List(attrs(), [lit_int("1"), lit_int("2"), lit_int("3")]),
  )
  let divide_zero = apply(
    apply(
      ref_value(
        "morphir/SDK:basics#integer-divide",
        arrow(int, arrow(int, int)),
      ),
      lit_int("1"),
    ),
    lit_int("0"),
  )
  let failing_bool = apply(
    apply(
      ref_value("morphir/SDK:basics#equal", arrow(int, arrow(int, bool))),
      divide_zero,
    ),
    lit_int("0"),
  )
  let results = Map::from_array([
    (@ir.Name::parse("total"), definition(dec, apply(total, sample))),
    (
      @ir.Name::parse("repriced"),
      definition(
        dec,
        apply(total, apply(apply(reprice, sample), lit_dec("4.25"))),
      ),
    ),
    (
      @ir.Name::parse("mapped-sum"),
      definition(
        int,
        apply(ref_value("morphir/SDK:list#sum", arrow(list_int, int)), mapped),
      ),
    ),
    (
      @ir.Name::parse("ordered"),
      definition(
        int,
        apply(
          apply(
            ref_value("pricing:quotes#difference", arrow(int, arrow(int, int))),
            lit_int("100"),
          ),
          lit_int("3"),
        ),
      ),
    ),
    (
      @ir.Name::parse("safe-branch"),
      definition(
        int,
        @ir.Value::IfThenElse(
          attrs(),
          @ir.Value::Literal(attrs(), @ir.Literal::BoolLiteral(true)),
          lit_int("42"),
          divide_zero,
        ),
      ),
    ),
    (
      @ir.Name::parse("safe-and"),
      definition(
        bool,
        apply(
          apply(
            ref_value("morphir/SDK:basics#and", arrow(bool, arrow(bool, bool))),
            @ir.Value::Literal(attrs(), @ir.Literal::BoolLiteral(false)),
          ),
          failing_bool,
        ),
      ),
    ),
    (@ir.Name::parse("failure"), definition(int, divide_zero)),
    (
      @ir.Name::parse("approved-amount"),
      definition(
        dec,
        apply(
          ref_value("pricing:quotes#status-amount", arrow(status, dec)),
          ref_value("pricing:quotes#approved", status),
        ),
      ),
    ),
  ])
  modules[@ir.Path::parse("results")] = {
    access: @ir.Access::Public,
    value: { types: Map([]), values: results, doc: None, },
  }
  let text = scalar("morphir/SDK:string#string")
  let character = scalar("morphir/SDK:char#char")
  let float = scalar("morphir/SDK:basics#float")
  let maybe_int = @ir.Type::Reference(
    ta(),
    @ir.FQName::parse("morphir/SDK:maybe#maybe"),
    [int],
  )
  let result_int = @ir.Type::Reference(
    ta(),
    @ir.FQName::parse("morphir/SDK:result#result"),
    [text, int],
  )
  let tuple = @ir.Type::Tuple(ta(), [dec, int])
  let boundaries = Map([])
  for
    (name, t) in [
      ("float", float),
      ("text", text),
      ("character", character),
      ("decimal", dec),
      ("list", list_int),
      ("tuple", tuple),
      ("maybe", maybe_int),
      ("result", result_int),
    ] {
    boundaries[@ir.Name::parse(name)] = function(
      [("input", t)],
      t,
      variable("input"),
    )
  }
  boundaries[@ir.Name::parse("upper-character")] = function(
    [("input", character)],
    character,
    apply(
      ref_value("morphir/SDK:char#to-upper", arrow(character, character)),
      variable("input"),
    ),
  )
  modules[@ir.Path::parse("boundaries")] = {
    access: @ir.Access::Public,
    value: { types: Map([]), values: boundaries, doc: None, },
  }
  @ir.IRFile::new(
    @ir.Distribution::Library(package_name, dependencies, { modules, }),
  )
}
