///|
fn int_type() -> @ir.Type {
  ref_type("morphir/SDK:basics#int")
}

///|
fn defined(
  name : String,
  access : @ir.Access,
  doc : String?,
  definition : @ir.ValueDefinition,
) -> (@ir.Name, @ir.Access, String?, ValueSource) {
  (n(name), access, doc, DefinedValue(definition))
}

///|
fn module_with(
  values : Array[(@ir.Name, @ir.Access, String?, ValueSource)],
  doc~ : String? = None,
  entry_points~ : Map[String, @ir.EntryPoint] = Map([]),
) -> ModuleInput {
  {
    package_name: @ir.Path::parse("acme/app") catch {
      _ => panic()
    },
    module_path: @ir.Path::parse("orders") catch {
      _ => panic()
    },
    doc,
    types: [],
    values,
    entry_points,
  }
}

///|
fn module_code(options : Options, input : ModuleInput) -> String {
  try {
    ignore(generate_module(options, input))
    ""
  } catch {
    Refused(problem) => problem.code + " " + problem.node_path
    _ => "other"
  }
}

///|
test "a module prints with signatures, docs, exposing and imports" {
  let double = defined(
    "double",
    Public,
    Some("Twice the input."),
    ExpressionBody(
      [(n("x"), int_type())],
      int_type(),
      apply(sdk("morphir/SDK:basics#multiply"), [variable("x"), int("2")]),
    ),
  )
  let helper = defined(
    "helper",
    Private,
    None,
    ExpressionBody(
      [],
      ref_type("morphir/SDK:dict#dict", args=[int_type(), int_type()]),
      sdk("morphir/SDK:dict#empty"),
    ),
  )
  let output = generate_module(
    Options::default(),
    module_with([double, helper], doc=Some("Orders.")),
  )
  let source = output.source
  assert_eq(output.elm_module, ["Acme", "App", "Orders"])
  assert_true(source.has_prefix("module Acme.App.Orders exposing (double)\n"))
  assert_true(source.contains("import Dict\n"))
  assert_true(
    source.contains(
      "{-| Twice the input.\n-}\ndouble : Int -> Int\ndouble x =\n    x * 2",
    ),
  )
  assert_true(
    source.contains("helper : Dict.Dict Int Int\nhelper =\n    Dict.empty"),
  )
  let parsed = @krueger.parse_module(@krueger.SourceText::new(source))
  assert_true(parsed.diagnostics.is_empty())
}

///|
test "module documentation is printed" {
  let value = defined(
    "answer",
    Public,
    None,
    ExpressionBody([], int_type(), int("42")),
  )
  let source = generate_module(
      Options::default(),
      module_with([value], doc=Some("Orders.")),
    ).source
  assert_true(source.contains("{-| Orders.\n-}"))
}

///|
test "an empty doc gives no doc comment" {
  // An empty doc is no doc: Elm frontends read `{-| -}` back as the doc " ".
  let value = defined(
    "answer",
    Public,
    Some(""),
    ExpressionBody([], int_type(), int("42")),
  )
  let source = generate_module(
      Options::default(),
      module_with([value], doc=Some("")),
    ).source
  assert_false(source.contains("{-|"))
  assert_true(source.contains("\n\nanswer : Int\nanswer =\n"))
}

///|
test "documentation that contains the comment end is escaped" {
  let value = defined(
    "answer",
    Public,
    Some("Ends here -} not really"),
    ExpressionBody([], int_type(), int("42")),
  )
  let source = generate_module(Options::default(), module_with([value])).source
  assert_true(source.contains("Ends here - } not really"))
  assert_true(
    @krueger.parse_module(@krueger.SourceText::new(source)).diagnostics.is_empty(),
  )
}

///|
test "a module with no public members exposes everything" {
  let value = defined(
    "answer",
    Private,
    None,
    ExpressionBody([], int_type(), int("42")),
  )
  let source = generate_module(Options::default(), module_with([value])).source
  assert_true(source.has_prefix("module Acme.App.Orders exposing (..)\n"))
}

///|
test "two IR names with one Elm name are refused" {
  let first = defined(
    "x-BC",
    Public,
    None,
    ExpressionBody([], int_type(), int("1")),
  )
  let second = defined(
    "x-B-C",
    Public,
    None,
    ExpressionBody([], int_type(), int("2")),
  )
  // Both print as xBC.
  assert_eq(
    module_code(Options::default(), module_with([first, second])),
    "elm.name_collision acme/app:orders#x-B-C",
  )
}

///|
test "placeholders follow the policy" {
  let native = defined(
    "native",
    Public,
    None,
    NativeBody([(n("x"), int_type())], int_type(), {
      hint: Arithmetic,
      description: None,
    }),
  )
  assert_eq(
    module_code(Options::default(), module_with([native])),
    "elm.placeholder acme/app:orders#native",
  )
  let source = generate_module(
      { ..Options::default(), placeholders: DebugTodo, },
      module_with([native]),
    ).source
  assert_true(
    source.contains(
      "native : Int -> Int\nnative x =\n    Debug.todo \"native body\"",
    ),
  )
  let incomplete = defined(
    "draft",
    Public,
    None,
    IncompleteBody([], None, Draft, None),
  )
  let draft = generate_module(
      { ..Options::default(), placeholders: DebugTodo, },
      module_with([incomplete]),
    ).source
  assert_true(
    draft.contains("draft =\n    Debug.todo \"incomplete definition\""),
  )
  assert_false(draft.contains("draft :"))
}

///|
test "external bodies keep the fallback and record bindings" {
  let external = defined(
    "now",
    Public,
    None,
    ExternalBody(
      [],
      int_type(),
      [{ target_platform: "jvm", external_name: "System.currentTimeMillis", }],
      Some(int("0")),
    ),
  )
  let source = generate_module(Options::default(), module_with([external])).source
  assert_true(
    source.contains(
      "@morphir.external { platform = \"jvm\", name = \"System.currentTimeMillis\" }",
    ),
  )
  assert_true(source.contains("now =\n    0"))
}

///|
test "entry points become attributes" {
  let main = defined(
    "main",
    Public,
    None,
    ExpressionBody([], int_type(), int("0")),
  )
  let entry : @ir.EntryPoint = {
    target: @ir.FQName::parse("acme/app:orders#main") catch {
      _ => panic()
    },
    kind: Main,
    doc: None,
  }
  let source = generate_module(
      Options::default(),
      module_with([main], entry_points=Map::from_array([("start", entry)])),
    ).source
  assert_true(
    source.contains("@morphir.entry { kind = \"main\", name = \"start\" }"),
  )
}

///|
test "print failures name the declaration" {
  // NaN cannot print as Elm.
  let bad = defined(
    "bad",
    Public,
    None,
    ExpressionBody(
      [],
      ref_type("morphir/SDK:basics#float"),
      @ir.Value::Literal(va(), FloatLiteral(0.0 / 0.0)),
    ),
  )
  assert_eq(
    module_code(Options::default(), module_with([bad])),
    "elm.print acme/app:orders#bad",
  )
}

///|
test "locals of different declarations do not share names" {
  let body = apply(sdk("morphir/SDK:basics#multiply"), [variable("x"), int("2")])
  let f = defined(
    "f",
    Public,
    None,
    ExpressionBody([(n("x"), int_type())], int_type(), body),
  )
  let g = defined(
    "g",
    Public,
    None,
    ExpressionBody([(n("x"), int_type())], int_type(), body),
  )
  let source = generate_module(Options::default(), module_with([f, g])).source
  assert_true(source.contains("f x =\n    x * 2"))
  assert_true(source.contains("g x =\n    x * 2"))
  assert_false(source.contains("x_1"))
}

///|
test "elm_string escapes control characters" {
  assert_eq(elm_string("a\nb"), "\"a\\nb\"")
  assert_eq(elm_string("a\tb\rc"), "\"a\\tb\\rc\"")
  assert_eq(elm_string("q\"s\\"), "\"q\\\"s\\\\\"")
  assert_eq(elm_string("\u{01}x\u{7F}"), "\"\\u{0001}x\\u{007F}\"")
}

///|
test "attribute strings cannot end the doc comment" {
  let external = defined(
    "now",
    Public,
    None,
    ExternalBody(
      [],
      int_type(),
      [{ target_platform: "jvm", external_name: "a-}\nb", }],
      Some(int("0")),
    ),
  )
  let source = generate_module(Options::default(), module_with([external])).source
  assert_true(source.contains("a-\\u{007D}\\nb"))
  assert_true(
    @krueger.parse_module(@krueger.SourceText::new(source)).diagnostics.is_empty(),
  )
}

///|
fn specified(
  name : String,
  annotations : Array[@ir.Annotation],
) -> (@ir.Name, @ir.Access, String?, ValueSource) {
  (
    n(name),
    Public,
    None,
    SpecifiedValue({ annotations, inputs: [], output: int_type(), }),
  )
}

///|
test "annotations on specified values print as attributes" {
  let fq = @ir.FQName::parse("acme/app:orders#tag") catch { _ => panic() }
  let compact = specified("one", [Compact(fq, Some("note"))])
  let record = @ir.Value::Record(va(), Map::from_array([(n("k"), int("1"))]))
  let structured = specified("two", [
    Structured(fq, [
      Positional(record),
      Named(n("label"), @ir.Value::Literal(va(), StringLiteral("hi"))),
    ]),
  ])
  let source = generate_module(
      { ..Options::default(), placeholders: DebugTodo, },
      module_with([compact, structured]),
    ).source
  assert_true(
    source.contains(
      "@morphir.annotation { fqname = \"acme/app:orders#tag\", text = \"note\" }",
    ),
  )
  assert_true(
    source.contains(
      "@morphir.annotation { fqname = \"acme/app:orders#tag\", arguments = [",
    ),
  )
  assert_true(
    @krueger.parse_module(@krueger.SourceText::new(source)).diagnostics.is_empty(),
  )
}

///|
test "annotation arguments must be data" {
  let fq = @ir.FQName::parse("acme/app:orders#tag") catch { _ => panic() }
  let bad = specified("one", [Structured(fq, [Positional(variable("x"))])])
  assert_eq(
    module_code(
      { ..Options::default(), placeholders: DebugTodo, },
      module_with([bad]),
    ),
    "elm.annotation_argument acme/app:orders#one",
  )
}

///|
fn ctor(text : String) -> @ir.Value {
  @ir.Value::Constructor(va(), @ir.FQName::parse(text) catch { _ => panic() })
}

///|
fn module_with_types(
  types : Array[(@ir.Name, @ir.Access, String?, TypeSource)],
  values : Array[(@ir.Name, @ir.Access, String?, ValueSource)],
) -> ModuleInput {
  { ..module_with(values), types, }
}

///|
fn parses_back(source : String) -> Bool {
  @krueger.parse_module(@krueger.SourceText::new(source)).diagnostics.is_empty()
}

///|
test "a mapped name is qualified when a top-level value has that name" {
  let max = defined(
    "max",
    Public,
    None,
    ExpressionBody(
      [(n("a"), int_type()), (n("b"), int_type())],
      int_type(),
      variable("a"),
    ),
  )
  let biggest = defined(
    "biggest",
    Public,
    None,
    ExpressionBody(
      [],
      int_type(),
      apply(sdk("morphir/SDK:basics#max"), [int("1"), int("2")]),
    ),
  )
  let source = generate_module(Options::default(), module_with([max, biggest])).source
  assert_true(source.contains("biggest =\n    Basics.max 1 2"), msg=source)
  assert_false(source.contains("import Basics"))
  assert_true(parses_back(source))
}

///|
test "a mapped name is qualified when a local has that name" {
  let limit = defined(
    "limit",
    Public,
    None,
    ExpressionBody(
      [(n("min"), int_type())],
      int_type(),
      apply(sdk("morphir/SDK:basics#min"), [variable("min"), int("2")]),
    ),
  )
  let source = generate_module(Options::default(), module_with([limit])).source
  assert_true(source.contains("limit min =\n    Basics.min min 2"), msg=source)
  // A binder in a nested lambda counts too.
  let nested = defined(
    "nested",
    Public,
    None,
    ExpressionBody(
      [],
      int_type(),
      apply(
        @ir.Value::Lambda(
          va(),
          bind_var("max"),
          apply(sdk("morphir/SDK:basics#max"), [variable("max"), int("1")]),
        ),
        [int("2")],
      ),
    ),
  )
  let lambda_source = generate_module(Options::default(), module_with([nested])).source
  assert_true(lambda_source.contains("Basics.max max 1"), msg=lambda_source)
}

///|
test "mapped types and constructors are qualified when the module defines the name" {
  let order_type = ref_type("morphir/SDK:basics#order")
  let order_alias = (
    n("order"),
    @ir.Access::Public,
    None,
    Defined(TypeAliasDefinition([], int_type())),
  )
  let first = defined(
    "first",
    Public,
    None,
    ExpressionBody([], order_type, ctor("morphir/SDK:basics#LT")),
  )
  let source = generate_module(
      Options::default(),
      module_with_types([order_alias], [first]),
    ).source
  assert_true(
    source.contains("first : Basics.Order\nfirst =\n    LT"),
    msg=source,
  )
  let rank = (
    n("rank"),
    @ir.Access::Public,
    None,
    Defined(
      CustomTypeDefinition([], {
        access: Public,
        value: Map::from_array([(n("LT"), []), (n("top"), [])]),
      }),
    ),
  )
  let ranked = generate_module(
      Options::default(),
      module_with_types([rank], [first]),
    ).source
  assert_true(
    ranked.contains("first : Order\nfirst =\n    Basics.LT"),
    msg=ranked,
  )
  assert_true(parses_back(source) && parses_back(ranked))
}

///|
test "mapped names stay bare without a conflict" {
  let pick = defined(
    "pick",
    Public,
    None,
    ExpressionBody(
      [],
      ref_type("morphir/SDK:maybe#maybe", args=[int_type()]),
      apply(ctor("morphir/SDK:maybe#just"), [
        apply(sdk("morphir/SDK:basics#max"), [int("1"), int("2")]),
      ]),
    ),
  )
  let source = generate_module(Options::default(), module_with([pick])).source
  assert_true(
    source.contains("pick : Maybe Int\npick =\n    Just (max 1 2)"),
    msg=source,
  )
}

///|
test "user overrides print as written" {
  let options = {
    ..Options::default(),
    mapping: Mapping::builtin().with_overrides(
      Map::from_array([
        ("morphir/SDK:basics#max", Function("max", None)),
        ("morphir/SDK:maybe#just", Function("Maybe.Just", None)),
      ]),
    ),
  }
  let max = defined(
    "max",
    Public,
    None,
    ExpressionBody([(n("a"), int_type())], int_type(), variable("a")),
  )
  let both = defined(
    "both",
    Public,
    None,
    ExpressionBody(
      [],
      ref_type("morphir/SDK:maybe#maybe", args=[int_type()]),
      apply(ctor("morphir/SDK:maybe#just"), [
        apply(sdk("morphir/SDK:basics#max"), [int("1"), int("2")]),
      ]),
    ),
  )
  let source = generate_module(options, module_with([max, both])).source
  assert_true(source.contains("Maybe.Just (max 1 2)"), msg=source)
}

///|
test "documentation that opens a nested comment is escaped" {
  for
    doc in [
      "See {- note", "Ends here -} not really", "Balanced {- x -} comment", "{-{--}-}",
    ] {
    let value = defined(
      "answer",
      Public,
      Some(doc),
      ExpressionBody([], int_type(), int("42")),
    )
    let source = generate_module(Options::default(), module_with([value])).source
    assert_true(parses_back(source), msg=source)
    assert_true(source.contains("answer =\n    42"), msg=source)
  }
}

///|
test "attribute strings cannot open a nested comment" {
  let external = defined(
    "now",
    Public,
    None,
    ExternalBody(
      [],
      int_type(),
      [{ target_platform: "jvm", external_name: "a{-b", }],
      Some(int("0")),
    ),
  )
  let source = generate_module(Options::default(), module_with([external])).source
  assert_true(source.contains("a{\\u{002D}b"), msg=source)
  assert_true(parses_back(source), msg=source)
}

///|
fn one_constructor_type(
  name : String,
  constructor_name : String,
) -> (@ir.Name, @ir.Access, String?, TypeSource) {
  (
    n(name),
    Public,
    None,
    Defined(
      CustomTypeDefinition([], {
        access: Public,
        value: Map::from_array([(n(constructor_name), [])]),
      }),
    ),
  )
}

///|
test "constructors of different types with one Elm name are refused" {
  // Both constructors print as XBC.
  let input = module_with_types(
    [
      one_constructor_type("first", "x-BC"),
      one_constructor_type("second", "x-B-C"),
    ],
    [],
  )
  assert_eq(
    module_code(Options::default(), input),
    "elm.name_collision acme/app:orders#second",
  )
}

///|
test "record values with fields that collide after lowering are refused" {
  let record = @ir.Value::Record(
    va(),
    Map::from_array([(n("x-BC"), int("1")), (n("x-B-C"), int("2"))]),
  )
  let value = defined("r", Public, None, ExpressionBody([], int_type(), record))
  assert_eq(
    module_code(Options::default(), module_with([value])),
    "elm.name_collision acme/app:orders#r",
  )
  let update = @ir.Value::UpdateRecord(
    va(),
    variable("a"),
    Map::from_array([(n("x-BC"), int("1")), (n("x-B-C"), int("2"))]),
  )
  let updater = defined(
    "u",
    Public,
    None,
    ExpressionBody([(n("a"), int_type())], int_type(), update),
  )
  assert_eq(
    module_code(Options::default(), module_with([updater])),
    "elm.name_collision acme/app:orders#u",
  )
}
