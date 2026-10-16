///|
fn t() -> @ir.TypeAttributes {
  { source: None, constraints: Map([]), extensions: Map([]), }
}

///|
fn v() -> @ir.ValueAttributes {
  { source: None, inferred_type: None, extensions: Map([]), }
}

///|
fn n(text : String) -> @ir.Name {
  @ir.Name::parse(text) catch {
    _ => panic()
  }
}

///|
fn fq(text : String) -> @ir.FQName {
  @ir.FQName::parse(text) catch {
    _ => panic()
  }
}

///|
fn ty(name : String, args~ : Array[@ir.Type] = []) -> @ir.Type {
  Reference(t(), fq(name), args)
}

///|
fn call(f : String, args : Array[@ir.Value]) -> @ir.Value {
  args.fold(init=@ir.Value::Reference(v(), fq(f)), (acc, a) => {
    @ir.Value::Apply(v(), acc, a)
  })
}

///|
fn var_ref(name : String) -> @ir.Value {
  Variable(v(), n(name))
}

///|
fn public_value(
  inputs : Array[(String, @ir.Type)],
  output : @ir.Type,
  body : @ir.Value,
  doc~ : String? = None,
) -> @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]] {
  {
    access: Public,
    value: {
      doc,
      value: ExpressionBody(inputs.map(i => (n(i.0), i.1)), output, body),
    },
  }
}

///|
fn library(
  package_name : String,
  modules : Array[(String, @ir.ModuleDefinition)],
) -> @ir.IRFile {
  @ir.IRFile::new(
    Library(@ir.Path::parse(package_name) catch { _ => panic() }, Map([]), {
      modules: Map::from_array(
        modules.map(m => {
          (
            @ir.Path::parse(m.0) catch {
              _ => panic()
            },
            { access: @ir.Access::Public, value: m.1, },
          )
        }),
      ),
    }),
  ) catch {
    _ => panic()
  }
}

///|
/// The rentals model of the v2 conformance fixture, in current IR.
pub fn rentals() -> @ir.IRFile {
  let int = ty("morphir/SDK:basics#int")
  let result = ty("morphir/SDK:result#result", args=[
    ty("morphir/SDK:string#string"),
    int,
  ])
  let body = @ir.Value::IfThenElse(
    v(),
    call("morphir/SDK:basics#less-than-or-equal", [
      var_ref("requested-quantity"),
      var_ref("availability"),
    ]),
    @ir.Value::Apply(
      v(),
      Constructor(v(), fq("morphir/SDK:result#ok")),
      var_ref("requested-quantity"),
    ),
    @ir.Value::Apply(
      v(),
      Constructor(v(), fq("morphir/SDK:result#err")),
      Literal(v(), StringLiteral("Insufficient availability")),
    ),
  )
  library("morphir/example/app", [
    (
      "rentals",
      {
        types: Map([]),
        doc: Some("Rentals."),
        values: Map::from_array([
          (
            n("request"),
            public_value(
              [("availability", int), ("requested-quantity", int)],
              result,
              body,
            ),
          ),
        ]),
      },
    ),
  ])
}

///|
/// Types, records, cases, lets, lambdas, lists, Maybe and a constrained variable, across two modules.
pub fn shapes() -> @ir.IRFile {
  let float = ty("morphir/SDK:basics#float")
  let shape = ty("acme/shapes:geometry#shape")
  let constructors : @ir.Constructors = Map::from_array([
    (n("circle"), [(n("radius"), float)]),
    (n("rectangle"), [(n("width"), float), (n("height"), float)]),
  ])
  let area = @ir.Value::PatternMatch(v(), var_ref("shape"), [
    (
      ConstructorPattern(v(), fq("acme/shapes:geometry#circle"), [
        AsPattern(v(), WildcardPattern(v()), n("r")),
      ]),
      call("morphir/SDK:basics#multiply", [
        Reference(v(), fq("morphir/SDK:basics#pi")),
        call("morphir/SDK:basics#multiply", [var_ref("r"), var_ref("r")]),
      ]),
    ),
    (
      ConstructorPattern(v(), fq("acme/shapes:geometry#rectangle"), [
        AsPattern(v(), WildcardPattern(v()), n("w")),
        AsPattern(v(), WildcardPattern(v()), n("h")),
      ]),
      call("morphir/SDK:basics#multiply", [var_ref("w"), var_ref("h")]),
    ),
  ])
  let number = @ir.Type::Variable(
    {
      ..t(),
      constraints: Map::from_array([("typeclass", @ir.Data::Text("number"))]),
    },
    n("a"),
  )
  let largest_body = call("morphir/SDK:list#maximum", [var_ref("values")])
  let total = @ir.Value::LetDefinition(
    v(),
    n("areas"),
    ExpressionBody(
      [],
      ty("morphir/SDK:list#list", args=[float]),
      call("morphir/SDK:list#map", [
        Reference(v(), fq("acme/shapes:geometry#area")),
        var_ref("shapes"),
      ]),
    ),
    call("morphir/SDK:list#sum", [var_ref("areas")]),
  )
  let scaled = @ir.Value::Lambda(
    v(),
    AsPattern(v(), WildcardPattern(v()), n("s")),
    @ir.Value::UpdateRecord(
      v(),
      var_ref("s"),
      Map::from_array([(n("scale"), Literal(v(), FloatLiteral(2.0)))]),
    ),
  )
  library("acme/shapes", [
    (
      "geometry",
      {
        types: Map::from_array([
          (
            n("shape"),
            {
              access: Public,
              value: {
                doc: Some("A shape."),
                value: CustomTypeDefinition([], {
                  access: Public,
                  value: constructors,
                }),
              },
            },
          ),
        ]),
        doc: Some("Geometry."),
        values: Map::from_array([
          (n("area"), public_value([("shape", shape)], float, area)),
          (
            n("largest"),
            public_value(
              [("values", ty("morphir/SDK:list#list", args=[number]))],
              ty("morphir/SDK:maybe#maybe", args=[number]),
              largest_body,
            ),
          ),
        ]),
      },
    ),
    (
      "report",
      {
        types: Map::from_array([
          (
            n("view"),
            {
              access: Public,
              value: {
                doc: None,
                value: TypeAliasDefinition(
                  [],
                  Record(t(), Map::from_array([(n("scale"), float)])),
                ),
              },
            },
          ),
        ]),
        doc: None,
        values: Map::from_array([
          (
            n("total-area"),
            public_value(
              [("shapes", ty("morphir/SDK:list#list", args=[shape]))],
              float,
              total,
            ),
          ),
          (
            n("double-scale"),
            public_value(
              [],
              Function(
                t(),
                ty("acme/shapes:report#view"),
                ty("acme/shapes:report#view"),
              ),
              scaled,
            ),
          ),
        ]),
      },
    ),
  ])
}

///|
/// Two modules that each hold a decimal literal, which the backend refuses.
pub fn refused() -> @ir.IRFile {
  let decimal = ty("morphir/SDK:decimal#decimal")
  let make = fn(doc : String) -> @ir.ModuleDefinition {
    {
      types: Map([]),
      doc: Some(doc),
      values: Map::from_array([
        (
          n("rate"),
          public_value([], decimal, Literal(v(), DecimalLiteral("1.5"))),
        ),
      ]),
    }
  }
  library("acme/rates", [("first", make("First.")), ("second", make("Second."))])
}

///|
/// A specification distribution: types only and value specifications.
pub fn specs() -> @ir.IRFile {
  let int = ty("morphir/SDK:basics#int")
  @ir.IRFile::new(
    Specs(@ir.Path::parse("acme/api") catch { _ => panic() }, Map([]), {
      modules: Map::from_array([
        (
          @ir.Path::parse("limits") catch {
            _ => panic()
          },
          {
            annotations: [],
            types: Map::from_array([
              (
                n("limit"),
                {
                  doc: None,
                  value: {
                    annotations: [],
                    body: TypeAliasSpecification([], int),
                  },
                },
              ),
              (
                n("token"),
                {
                  doc: None,
                  value: { annotations: [], body: OpaqueTypeSpecification([]), },
                },
              ),
            ]),
            values: Map::from_array([
              (
                n("max-limit"),
                {
                  doc: None,
                  value: {
                    annotations: [Compact(fq("acme/api:tags#stable"), None)],
                    inputs: [],
                    output: int,
                  },
                },
              ),
            ]),
            doc: None,
          },
        ),
      ]),
    }),
  ) catch {
    _ => panic()
  }
}

///|
fn classic(text : String) -> @ir.IRFile {
  @migration.to_current(@versioned_json.read(text)) catch {
    _ => panic()
  }
}

///|
/// The v3 greeting fixture of the IR conformance corpus, migrated to current IR.
pub fn classic_greeting() -> @ir.IRFile {
  classic(classic_greeting_json())
}

///|
/// The morphir-elm rentals example in format version 1, migrated to current IR.
pub fn classic_rentals_v1() -> @ir.IRFile {
  classic(classic_rentals_v1_json())
}

///|
/// The morphir-elm rentals example in format version 2, migrated to current IR.
pub fn classic_rentals_v2() -> @ir.IRFile {
  classic(classic_rentals_v2_json())
}

///|
fn sdk_type_variable(name : String, typeclass : String) -> @ir.Type {
  Variable(
    {
      ..t(),
      constraints: Map::from_array([("typeclass", @ir.Data::Text(typeclass))]),
    },
    n(name),
  )
}

///|
fn sdk_constructor_pattern(name : String) -> @ir.Pattern {
  ConstructorPattern(v(), fq(name), [])
}

///|
/// SDK references that `elm make` must accept: a case on `compare`, `Maybe.map2`, a comparable type variable,
/// Decimal and LocalDate from the SDK Elm package, and a top-level `max` that would capture `Basics.max`.
pub fn sdk_tour() -> @ir.IRFile {
  let int = ty("morphir/SDK:basics#int")
  let string = ty("morphir/SDK:string#string")
  let maybe_int = ty("morphir/SDK:maybe#maybe", args=[int])
  let key = sdk_type_variable("k", "comparable")
  let decimal = ty("morphir/SDK:decimal#decimal")
  let local_date = ty("morphir/SDK:local-date#local-date")
  let text = fn(s : String) -> @ir.Value { Literal(v(), StringLiteral(s)) }
  let integer = fn(s : String) -> @ir.Value { Literal(v(), IntegerLiteral(s)) }
  let describe = @ir.Value::PatternMatch(
    v(),
    call("morphir/SDK:basics#compare", [var_ref("a"), var_ref("b")]),
    [
      (sdk_constructor_pattern("morphir/SDK:basics#LT"), text("less")),
      (sdk_constructor_pattern("morphir/SDK:basics#EQ"), text("same")),
      (sdk_constructor_pattern("morphir/SDK:basics#GT"), text("more")),
    ],
  )
  let own_max = @ir.Value::IfThenElse(
    v(),
    call("morphir/SDK:basics#greater-than-or-equal", [
      var_ref("a"),
      var_ref("b"),
    ]),
    var_ref("a"),
    var_ref("b"),
  )
  library("acme/sdk-tour", [
    (
      "tour",
      {
        types: Map::from_array([
          (
            n("ranked"),
            {
              access: Public,
              value: {
                doc: Some("A key with a score."),
                value: TypeAliasDefinition(
                  [n("k")],
                  Record(
                    t(),
                    Map::from_array([(n("key"), key), (n("score"), int)]),
                  ),
                ),
              },
            },
          ),
        ]),
        doc: Some("A tour of SDK references."),
        values: Map::from_array([
          (
            n("max"),
            public_value(
              [("a", int), ("b", int)],
              int,
              own_max,
              doc=Some("This module's own max."),
            ),
          ),
          (
            n("biggest"),
            public_value(
              [],
              int,
              call("morphir/SDK:basics#max", [integer("1"), integer("2")]),
            ),
          ),
          (
            n("describe"),
            public_value([("a", int), ("b", int)], string, describe),
          ),
          (
            n("add-both"),
            public_value(
              [("x", maybe_int), ("y", maybe_int)],
              maybe_int,
              call("morphir/SDK:maybe#map-2", [
                Reference(v(), fq("morphir/SDK:basics#add")),
                var_ref("x"),
                var_ref("y"),
              ]),
            ),
          ),
          (
            n("best"),
            public_value(
              [("a", key), ("b", key)],
              key,
              call("morphir/SDK:basics#max", [var_ref("a"), var_ref("b")]),
            ),
          ),
          (
            n("best-ranked"),
            public_value(
              [("ranked", ty("acme/sdk-tour:tour#ranked", args=[key]))],
              key,
              @ir.Value::Field(v(), var_ref("ranked"), n("key")),
            ),
          ),
          (
            n("price"),
            public_value(
              [],
              decimal,
              call("morphir/SDK:decimal#from-int", [integer("100")]),
            ),
          ),
          (
            n("due"),
            public_value([("date", local_date)], local_date, var_ref("date")),
          ),
        ]),
      },
    ),
  ])
}
