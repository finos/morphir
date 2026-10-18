///|
test "compiled model executes through the IR backend and imports again" {
  let result = @pipeline.execute(
    @wire.obj([
      ("operation", @wire.text("run")),
      ("source", @wire.text("(define (inc x) (+ x 1)) (inc 41)")),
    ]),
  )
  assert_eq(@wire.field(result, "success"), Json::boolean(true))
  assert_eq(@wire.field(result, "value"), @wire.text("42"))
  let evaluated = @pipeline.execute(
    @wire.obj([
      ("operation", @wire.text("evaluate")),
      ("source", @wire.text(@wire.field(result, "ir").stringify())),
      ("entry", @wire.text("user:main#main")),
      ("arguments", Json::array([])),
    ]),
  )
  assert_eq(@wire.field(evaluated, "value"), @wire.text("42"))
  assert_eq(
    @wire.field(@wire.field(evaluated, "structured"), "text"),
    @wire.text("42"),
  )
  let imported = @pipeline.execute(
    @wire.obj([
      ("operation", @wire.text("inspect")),
      ("source", @wire.text(@wire.field(result, "ir").stringify())),
    ]),
  )
  assert_eq(@wire.field(imported, "success"), Json::boolean(true))
  assert_eq(@wire.field(imported, "nodes"), @wire.field(result, "nodes"))
}

///|
fn worksheet_request(source : String) -> Json {
  {
    "operation": "worksheet",
    "source": source,
    "worksheetRequest": (
      {
        "profile": "morphir/workbench/worksheet",
        "contractVersion": "0.1.0-draft.1",
        "source": { "id": "worksheet-source", "revision": 0, "text": source },
      } : Json).stringify(),
  }
}

///|
test "worksheet keeps definitions within a run and isolates subsequent runs" {
  let result = @pipeline.execute(
    worksheet_request("(define (square x) (* x x)) (square 7) (+ 1/3 2/3)"),
  )
  assert_eq(@wire.field(result, "success"), Json::boolean(true))
  let report = @json.parse(@wire.string(@wire.field(result, "worksheetReport")))
  let results = @wire.array(@wire.field(report, "observations"))
  assert_eq(@wire.field(results[1], "preview"), @wire.text("49"))
  assert_eq(@wire.field(results[2], "preview"), @wire.text("1"))
  let isolated = @pipeline.execute(worksheet_request("(square 7)"))
  let stopped = @json.parse(
    @wire.string(@wire.field(isolated, "worksheetReport")),
  )
  assert_eq(
    @wire.field(@wire.field(stopped, "completion"), "status"),
    @wire.text("failed"),
  )
}

///|
test "invalid source is returned as a diagnostic instead of escaping the worker" {
  let result = @pipeline.execute(
    @wire.obj([
      ("operation", @wire.text("compile")),
      ("source", @wire.text("(let ((x 1))")),
    ]),
  )
  assert_eq(@wire.field(result, "success"), Json::boolean(false))
  assert_true(@wire.string(@wire.field(result, "message")).length() > 0)
}

///|
test "type labels retain function precedence and record fields" {
  let attrs = @ir.TypeAttributes::default()
  let integer : @ir.Type = Reference(
    attrs,
    @ir.FQName::parse("morphir/SDK:basics#int"),
    [],
  )
  let maybe : @ir.Type = Reference(
    attrs,
    @ir.FQName::parse("morphir/SDK:maybe#maybe"),
    [integer],
  )
  assert_eq(
    @pipeline.type_label(
      Function(
        attrs,
        maybe,
        Function(attrs, Function(attrs, integer, integer), integer),
      ),
    ),
    "(Maybe.Maybe Basics.Int) → (Basics.Int → Basics.Int) → Basics.Int",
  )
  assert_eq(
    @pipeline.type_label(
      ExtensibleRecord(
        attrs,
        @ir.Name::parse("r"),
        Map([(@ir.Name::parse("count"), integer)]),
      ),
    ),
    "{ r | count : Basics.Int }",
  )
}

///|
fn inspect_distribution(distribution : @ir.Distribution) -> Json raise {
  let file = @ir.IRFile::new(distribution)
  @pipeline.execute(
    @wire.obj([
      ("operation", @wire.text("inspect")),
      ("source", @wire.text(@codec.to_json(file).stringify())),
    ]),
  )
}

///|
test "projection distinguishes shared type/value names and keeps docs and parameter order" {
  let attrs = @ir.TypeAttributes::default()
  let integer : @ir.Type = Reference(
    attrs,
    @ir.FQName::parse("morphir/SDK:basics#int"),
    [],
  )
  let quote = @ir.Name::parse("quote")
  let module_def : @ir.ModuleDefinition = {
    types: Map([
      (
        quote,
        {
          access: Public,
          value: {
            doc: Some("A documented quote."),
            value: TypeAliasDefinition(
              [],
              Record(attrs, Map([(@ir.Name::parse("amount"), integer)])),
            ),
          },
        },
      ),
    ]),
    values: Map([
      (
        quote,
        {
          access: Private,
          value: {
            doc: Some("Ordered inputs."),
            value: ExpressionBody(
              [
                (@ir.Name::parse("z-last"), integer),
                (@ir.Name::parse("a-first"), integer),
              ],
              integer,
              Reference(
                @ir.ValueAttributes::default(),
                @ir.FQName::parse("demo:main#other"),
              ),
            ),
          },
        },
      ),
    ]),
    doc: Some("Module documentation."),
  }
  let result = inspect_distribution(
    Library(@ir.Path::parse("demo"), Map([]), {
      modules: Map([
        (@ir.Path::parse("main"), { access: Public, value: module_def, }),
      ]),
    }),
  )
  assert_eq(@wire.field(result, "success"), Json::boolean(true))
  assert_eq(@wire.field(result, "package"), @wire.text("demo"))
  assert_eq(@wire.field(result, "distributionKind"), @wire.text("Library"))
  let nodes = @wire.array(@wire.field(result, "nodes"))
  assert_eq(@wire.field(nodes[0], "doc"), @wire.text("Module documentation."))
  assert_eq(@wire.field(nodes[1], "key"), @wire.text("type|demo:main#quote"))
  assert_eq(@wire.field(nodes[2], "key"), @wire.text("value|demo:main#quote"))
  assert_eq(@wire.field(nodes[2], "access"), @wire.text("Private"))
  assert_eq(@wire.field(nodes[2], "doc"), @wire.text("Ordered inputs."))
  let inputs = @wire.array(@wire.field(nodes[2], "inputs"))
  assert_eq(@wire.field(inputs[0], "name"), @wire.text("zLast"))
  assert_eq(@wire.field(inputs[1], "name"), @wire.text("aFirst"))
  let refs = @wire.array(@wire.field(nodes[2], "references"))
  assert_eq(refs.length(), 2)
  assert_eq(@wire.field(refs[1], "key"), @wire.text("value|demo:main#other"))
}

///|
test "custom constructors and opaque specifications keep their semantics" {
  let name = @ir.Name::parse("status")
  let spec : @ir.ModuleSpecification = {
    annotations: [],
    doc: None,
    types: Map([
      (
        name,
        {
          doc: None,
          value: {
            annotations: [],
            body: CustomTypeSpecification(
              [],
              Map([
                (@ir.Name::parse("pending"), []),
                (@ir.Name::parse("done"), []),
              ]),
            ),
          },
        },
      ),
      (
        @ir.Name::parse("secret"),
        {
          doc: None,
          value: { annotations: [], body: OpaqueTypeSpecification([]), },
        },
      ),
    ]),
    values: Map([]),
  }
  let result = inspect_distribution(
    Specs(@ir.Path::parse("demo"), Map([]), {
      modules: Map([(@ir.Path::parse("main"), spec)]),
    }),
  )
  assert_eq(@wire.field(result, "success"), Json::boolean(true))
  let nodes = @wire.array(@wire.field(result, "nodes"))
  assert_eq(
    @wire.field(nodes[1], "flavor"),
    @wire.text("Opaque type specification"),
  )
  let variants = @wire.array(@wire.field(nodes[2], "constructors"))
  assert_eq(@wire.field(variants[0], "name"), @wire.text("Done"))
  assert_eq(@wire.field(variants[1], "id"), @wire.text("demo:main#pending"))
}

///|
test "literal strings do not turn into declaration references" {
  let result = @pipeline.execute(
    @wire.obj([
      ("operation", @wire.text("compile")),
      ("source", @wire.text("\"demo:main#fake\"")),
    ]),
  )
  assert_eq(@wire.field(result, "success"), Json::boolean(true))
  let nodes = @wire.array(@wire.field(result, "nodes"))
  assert_false(
    @wire.field(nodes[1], "references").stringify().contains("demo:main#fake"),
  )
}

///|
fn identity_model(
  tpe : @ir.Type,
  types : Map[
    @ir.Name,
    @ir.AccessControlled[@ir.Documented[@ir.TypeDefinition]],
  ],
) -> Json raise {
  inspect_distribution(
    Library(@ir.Path::parse("demo"), Map([]), {
      modules: Map([
        (
          @ir.Path::parse("main"),
          {
            access: Public,
            value: {
              doc: None,
              types,
              values: Map([
                (
                  @ir.Name::parse("identity"),
                  {
                    access: Public,
                    value: {
                      doc: None,
                      value: ExpressionBody(
                        [(@ir.Name::parse("value"), tpe)],
                        tpe,
                        Variable(
                          @ir.ValueAttributes::default(),
                          @ir.Name::parse("value"),
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
fn evaluate_identity(model : Json, input : Json) -> Json raise {
  @pipeline.execute(
    @wire.obj([
      ("operation", @wire.text("evaluate")),
      ("source", @wire.text(@wire.field(model, "ir").stringify())),
      ("entry", @wire.text("demo:main#identity")),
      ("arguments", Json::array([input])),
    ]),
  )
}

///|
test "evaluation preserves exact integers and validates data without executing text" {
  let integer : @ir.Type = Reference(
    @ir.TypeAttributes::default(),
    @ir.FQName::parse("morphir/SDK:basics#int"),
    [],
  )
  let model = identity_model(integer, Map([]))
  let result = evaluate_identity(
    model,
    @wire.text("90071992547409931234567890"),
  )
  assert_eq(@wire.field(result, "success"), Json::boolean(true))
  assert_eq(
    @wire.field(result, "value"),
    @wire.text("90071992547409931234567890"),
  )
  let invalid = evaluate_identity(model, Json::number(42))
  assert_eq(@wire.field(invalid, "success"), Json::boolean(false))
  assert_true(
    @wire.string(@wire.field(invalid, "message")).contains("decimal string"),
  )
  let string : @ir.Type = Reference(
    @ir.TypeAttributes::default(),
    @ir.FQName::parse("morphir/SDK:string#string"),
    [],
  )
  let result = evaluate_identity(
    identity_model(string, Map([])),
    @wire.text("(error \"do not execute\")"),
  )
  assert_eq(@wire.field(result, "success"), Json::boolean(true))
  assert_true(
    @wire.string(@wire.field(result, "value")).contains("do not execute"),
  )
}

///|
test "generic aliases decode records lists and tuples with strict field checks" {
  let attrs = @ir.TypeAttributes::default()
  let integer : @ir.Type = Reference(
    attrs,
    @ir.FQName::parse("morphir/SDK:basics#int"),
    [],
  )
  let tpe : @ir.Type = Reference(attrs, @ir.FQName::parse("demo:main#box"), [
    integer,
  ])
  let model = identity_model(
    tpe,
    Map([
      (
        @ir.Name::parse("box"),
        {
          access: Public,
          value: {
            doc: None,
            value: TypeAliasDefinition(
              [@ir.Name::parse("a")],
              Record(
                attrs,
                Map([
                  (
                    @ir.Name::parse("items"),
                    Reference(
                      attrs,
                      @ir.FQName::parse("morphir/SDK:list#list"),
                      [
                        Tuple(attrs, [
                          Variable(attrs, @ir.Name::parse("a")),
                          Unit(attrs),
                        ]),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          },
        },
      ),
    ]),
  )
  let result = evaluate_identity(
    model,
    @wire.obj([
      ("items", Json::array([Json::array([@wire.text("42"), Json::null()])])),
    ]),
  )
  assert_eq(@wire.field(result, "success"), Json::boolean(true))
  assert_eq(
    @wire.field(result, "value"),
    @wire.text("#<record items=(#(42 #<unit>))>"),
  )
  for
    input in [
      @wire.obj([]),
      @wire.obj([("items", Json::array([])), ("extra", Json::null())]),
      @wire.obj([("items", Json::array([Json::array([@wire.text("42")])]))]),
    ] {
    assert_eq(
      @wire.field(evaluate_identity(model, input), "success"),
      Json::boolean(false),
    )
  }
}

///|
test "custom inputs validate constructor identity arity and generic arguments" {
  let attrs = @ir.TypeAttributes::default()
  let integer : @ir.Type = Reference(
    attrs,
    @ir.FQName::parse("morphir/SDK:basics#int"),
    [],
  )
  let model = identity_model(
    Reference(attrs, @ir.FQName::parse("demo:main#box"), [integer]),
    Map([
      (
        @ir.Name::parse("box"),
        {
          access: Public,
          value: {
            doc: None,
            value: CustomTypeDefinition([@ir.Name::parse("a")], {
              access: Public,
              value: Map([
                (
                  @ir.Name::parse("box"),
                  [
                    (
                      @ir.Name::parse("value"),
                      Variable(attrs, @ir.Name::parse("a")),
                    ),
                  ],
                ),
              ]),
            }),
          },
        },
      ),
    ]),
  )
  let valid = @wire.obj([
    ("constructor", @wire.text("demo:main#box")),
    ("arguments", Json::array([@wire.text("7")])),
  ])
  assert_eq(
    @wire.field(evaluate_identity(model, valid), "value"),
    @wire.text("#<demo:main#box 7>"),
  )
  for
    input in [
      @wire.obj([
        ("constructor", @wire.text("other:main#box")),
        ("arguments", Json::array([@wire.text("7")])),
      ]),
      @wire.obj([
        ("constructor", @wire.text("demo:main#box")),
        ("arguments", Json::array([])),
      ]),
    ] {
    assert_eq(
      @wire.field(evaluate_identity(model, input), "success"),
      Json::boolean(false),
    )
  }
}

///|
test "unsupported input types remain inspectable and evaluation rejects them" {
  let attrs = @ir.TypeAttributes::default()
  let model = identity_model(Function(attrs, Unit(attrs), Unit(attrs)), Map([]))
  assert_eq(@wire.field(model, "success"), Json::boolean(true))
  let profile = @wire.field(
    @wire.field(model, "evaluations"),
    "demo:main#identity",
  )
  assert_eq(@wire.field(profile, "supported"), Json::boolean(false))
  assert_eq(
    @wire.field(evaluate_identity(model, Json::null()), "success"),
    Json::boolean(false),
  )
  let recursive = identity_model(
    Reference(attrs, @ir.FQName::parse("demo:main#loop"), []),
    Map([
      (
        @ir.Name::parse("loop"),
        {
          access: Public,
          value: {
            doc: None,
            value: TypeAliasDefinition(
              [],
              Reference(attrs, @ir.FQName::parse("demo:main#loop"), []),
            ),
          },
        },
      ),
    ]),
  )
  assert_eq(@wire.field(recursive, "success"), Json::boolean(true))
  assert_eq(
    @wire.field(
      @wire.field(@wire.field(recursive, "evaluations"), "demo:main#identity"),
      "supported",
    ),
    Json::boolean(false),
  )
}
