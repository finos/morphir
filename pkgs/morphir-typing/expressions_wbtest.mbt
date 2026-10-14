// Tests for the environment, type conversion and expression inference. The specifications are small and made
// by hand with IR helpers; they do not use the real SDK.

///|
/// Quantifies every unbound meta whose level is greater than `level`. Only the tests use it.
fn Solver::generalize(self : Solver, t : Ty, level : Int) -> Poly {
  self.generalize_with(t, level, [])
}

///|
fn nm(text : String) -> @ir.Name {
  @ir.Name::parse(text) catch {
    _ => abort("bad name: \{text}")
  }
}

///|
fn fq(text : String) -> @ir.FQName {
  @ir.FQName::parse(text) catch {
    _ => abort("bad FQName: \{text}")
  }
}

///|
fn pkg(text : String) -> @ir.Path {
  @ir.Path::parse(text) catch {
    _ => abort("bad path: \{text}")
  }
}

///|
fn tattrs() -> @ir.TypeAttributes {
  { source: None, constraints: Map([]), extensions: Map([]), }
}

///|
fn tv(text : String) -> @ir.Type {
  Variable(tattrs(), nm(text))
}

///|
fn tclass(text : String, class : String) -> @ir.Type {
  Variable(
    { ..tattrs(), constraints: Map([("typeclass", Text(class))]), },
    nm(text),
  )
}

///|
fn tmarked(text : String) -> @ir.Type {
  Variable(
    { ..tattrs(), extensions: Map([("morphir.inference", Text("unknown"))]), },
    nm(text),
  )
}

///|
fn tr(text : String, args : Array[@ir.Type]) -> @ir.Type {
  Reference(tattrs(), fq(text), args)
}

///|
fn tfn(a : @ir.Type, b : @ir.Type) -> @ir.Type {
  Function(tattrs(), a, b)
}

///|
fn trec(fields : Array[(String, @ir.Type)]) -> @ir.Type {
  Record(tattrs(), Map::from_array(fields.map(f => (nm(f.0), f.1))))
}

///|
fn t_int() -> @ir.Type {
  tr(INT, [])
}

///|
fn t_float() -> @ir.Type {
  tr(FLOAT, [])
}

///|
fn va() -> @ir.ValueAttributes {
  { source: None, inferred_type: None, extensions: Map([]), }
}

///|
fn v_int(text : String) -> @ir.Value {
  Literal(va(), IntegerLiteral(text))
}

///|
fn v_float(d : Double) -> @ir.Value {
  Literal(va(), FloatLiteral(d))
}

///|
fn v_str(s : String) -> @ir.Value {
  Literal(va(), StringLiteral(s))
}

///|
fn v_bool(b : Bool) -> @ir.Value {
  Literal(va(), BoolLiteral(b))
}

///|
fn v_var(text : String) -> @ir.Value {
  Variable(va(), nm(text))
}

///|
fn v_ref(text : String) -> @ir.Value {
  Reference(va(), fq(text))
}

///|
fn v_apply(f : @ir.Value, a : @ir.Value) -> @ir.Value {
  Apply(va(), f, a)
}

///|
fn v_lambda(p : @ir.Pattern, body : @ir.Value) -> @ir.Value {
  Lambda(va(), p, body)
}

///|
fn v_record(fields : Array[(String, @ir.Value)]) -> @ir.Value {
  Record(va(), Map::from_array(fields.map(f => (nm(f.0), f.1))))
}

///|
fn v_let(
  name : String,
  def : @ir.ValueDefinition,
  rest : @ir.Value,
) -> @ir.Value {
  LetDefinition(va(), nm(name), def, rest)
}

///|
fn p_var(text : String) -> @ir.Pattern {
  AsPattern(va(), WildcardPattern(va()), nm(text))
}

///|
fn p_wild() -> @ir.Pattern {
  WildcardPattern(va())
}

///|
fn p_ctor(text : String, args : Array[@ir.Pattern]) -> @ir.Pattern {
  ConstructorPattern(va(), fq(text), args)
}

///|
fn opaque_type(params : Array[String]) -> @ir.Documented[@ir.TypeSpecification] {
  {
    doc: None,
    value: { annotations: [], body: OpaqueTypeSpecification(params.map(nm)), },
  }
}

///|
fn val_spec(
  inputs : Array[(String, @ir.Type)],
  output : @ir.Type,
) -> @ir.Documented[@ir.ValueSpecification] {
  {
    doc: None,
    value: { annotations: [], inputs: inputs.map(i => (nm(i.0), i.1)), output, },
  }
}

///|
fn module_spec(
  types : Array[(String, @ir.Documented[@ir.TypeSpecification])],
  values : Array[(String, @ir.Documented[@ir.ValueSpecification])],
) -> @ir.ModuleSpecification {
  {
    annotations: [],
    types: Map::from_array(types.map(t => (nm(t.0), t.1))),
    values: Map::from_array(values.map(v => (nm(v.0), v.1))),
    doc: None,
  }
}

///|
/// A tiny hand-made SDK: only what these tests need.
fn sdk() -> @ir.PackageSpecification {
  let maybe : @ir.Documented[@ir.TypeSpecification] = {
    doc: None,
    value: {
      annotations: [],
      body: CustomTypeSpecification(
        [nm("a")],
        Map([(nm("just"), [(nm("value"), tv("a"))]), (nm("nothing"), [])]),
      ),
    },
  }
  let map = val_spec(
    [("f", tfn(tv("a"), tv("b"))), ("list", tr(LIST, [tv("a")]))],
    tr(LIST, [tv("b")]),
  )
  {
    modules: Map([
      (
        pkg("basics"),
        module_spec(
          [
            ("int", opaque_type([])),
            ("float", opaque_type([])),
            ("bool", opaque_type([])),
          ],
          [],
        ),
      ),
      (pkg("string"), module_spec([("string", opaque_type([]))], [])),
      (pkg("char"), module_spec([("char", opaque_type([]))], [])),
      (pkg("decimal"), module_spec([("decimal", opaque_type([]))], [])),
      (pkg("list"), module_spec([("list", opaque_type(["a"]))], [("map", map)])),
      (pkg("maybe"), module_spec([("maybe", maybe)], [])),
    ]),
  }
}

///|
fn alias_def(
  params : Array[String],
  body : @ir.Type,
) -> @ir.AccessControlled[@ir.Documented[@ir.TypeDefinition]] {
  {
    access: Public,
    value: { doc: None, value: TypeAliasDefinition(params.map(nm), body), },
  }
}

///|
/// The file under test: `acme/app`, module `m`, with aliases (some cyclic) and a custom type.
fn app_file() -> @ir.IRFile {
  let shape : @ir.AccessControlled[@ir.Documented[@ir.TypeDefinition]] = {
    access: Public,
    value: {
      doc: None,
      value: CustomTypeDefinition([], {
        access: Public,
        value: Map([(nm("circle"), [(nm("radius"), t_float())])]),
      }),
    },
  }
  let types = Map([
    (nm("point"), alias_def([], trec([("x", t_int()), ("y", t_int())]))),
    (nm("pair"), alias_def(["a"], Tuple(tattrs(), [tv("a"), tv("a")]))),
    (nm("loop"), alias_def([], tr("acme/app:m#loop", []))),
    (nm("ping"), alias_def([], tr("acme/app:m#pong", []))),
    (nm("pong"), alias_def([], tr("acme/app:m#ping", []))),
    (nm("grow"), alias_def(["a"], tr("acme/app:m#grow", [tr(LIST, [tv("a")])]))),
    (nm("to-loop"), alias_def([], tr("acme/app:m#loop", []))),
    (nm("shape"), shape),
  ])
  let m : @ir.ModuleDefinition = { types, values: Map([]), doc: None, }
  let def : @ir.PackageDefinition = {
    modules: Map([(pkg("m"), { access: Public, value: m, })]),
  }
  @ir.IRFile::new(Library(pkg("acme/app"), Map([]), def)) catch {
    _ => abort("bad file")
  }
}

///|
fn test_env() -> Env {
  Env::from(Map([(pkg("morphir/SDK"), sdk())]), app_file())
}

///|
fn new_infer() -> Infer {
  Infer::new(test_env(), 1)
}

///|
/// The type in Elm notation, named by a new `Namer`.
fn show(i : Infer, t : Ty) -> String {
  elm_text(Namer::new().to_ir(i.solver, t))
}

///|
/// The code and the logical path of a failure, or `("", "")`.
fn failure(f : () -> Unit raise Located) -> (String, String) {
  try {
    f()
    ("", "")
  } catch {
    MismatchAt(path, Mismatch(code, _, _)) => (code, path)
    UnknownAt(path, Unknown(code, _)) => (code, path)
    ClassAt(path, _) => ("unsupported", path)
  }
}

///|
fn expr(body : @ir.Value) -> @ir.ValueDefinition {
  ExpressionBody([], tmarked("t"), body)
}

///|
test "1. an integer literal is number, and it checks against Float (Review Focus)" {
  let i = new_infer()
  let t = i.value(v_int("1"), "x")
  assert_eq(Namer::new().to_ir(i.solver, t), tclass("number-a", "number"))
  assert_eq(show(i, t), "numberA")
  // x : Float
  // x = 1
  let i = new_infer()
  let (t, owned) = i.definition(
    ExpressionBody([], t_float(), v_int("1")),
    "value:acme/app:m#x",
  )
  assert_eq(owned, [])
  assert_eq(show(i, t), "Float")
  guard i.types.get("value:acme/app:m#x/body") is Some(body) else {
    fail("no type for the body")
  }
  assert_eq(i.solver.prune(body), Con(FLOAT, []))
}

///|
test "2. the identity lambda generalizes to a -> a" {
  let i = new_infer()
  let t = i.value(v_lambda(p_var("a"), v_var("a")), "v")
  let p = i.solver.generalize(t, 0)
  assert_eq(p.gens, [[]])
  assert_eq(p.body, Fun(Gen(0), Gen(0)))
  let ir = Namer::new().to_ir(i.solver, i.solver.instantiate(p, 1))
  assert_eq(ir, tfn(tv("a"), tv("a")))
  assert_eq(elm_text(ir), "a -> a")
}

///|
test "3. let generalizes: let id = \\x -> x in (id 1, id \"s\")" {
  let i = new_infer()
  let body : @ir.Value = Tuple(va(), [
    v_apply(v_var("id"), v_int("1")),
    v_apply(v_var("id"), v_str("s")),
  ])
  let t = i.value(
    v_let("id", expr(v_lambda(p_var("x"), v_var("x"))), body),
    "v",
  )
  assert_eq(show(i, t), "( numberA, String )")
  assert_eq(
    Namer::new().to_ir(i.solver, t),
    Tuple(tattrs(), [tclass("number-a", "number"), tr(STRING, [])]),
  )
}

///|
test "4. if c then 1 else 2.5 is Float" {
  let i = new_infer()
  let t = i.value(
    v_lambda(p_var("c"), IfThenElse(va(), v_var("c"), v_int("1"), v_float(2.5))),
    "v",
  )
  assert_eq(show(i, t), "Bool -> Float")
  // The condition must be a Bool.
  let i = new_infer()
  assert_eq(
    failure(() => {
      i.value(IfThenElse(va(), v_int("1"), v_int("1"), v_int("2")), "v")
      |> ignore
    }),
    ("no_instance", "v/condition"),
  )
}

///|
test "5. List.map .total orders gives an extensible row (Review Focus)" {
  let i = new_infer()
  let body = v_apply(
    v_apply(v_ref("morphir/SDK:list#map"), FieldFunction(va(), nm("total"))),
    v_var("orders"),
  )
  let t = i.value(v_lambda(p_var("orders"), body), "v")
  assert_eq(show(i, t), "List { a | total : b } -> List b")
  guard i.types.get("v/pattern") is Some(orders) else { fail("no pattern") }
  let expected = tr(LIST, [
    ExtensibleRecord(tattrs(), nm("a"), Map([(nm("total"), tv("b"))])),
  ])
  assert_eq(Namer::new().to_ir(i.solver, orders), expected)
  // A closed record of orders fits, and gives the field type.
  let i = new_infer()
  let orders : @ir.Value = List(va(), [
    v_record([("total", v_float(1.0)), ("id", v_int("7"))]),
  ])
  let t = i.value(
    v_apply(
      v_apply(v_ref("morphir/SDK:list#map"), FieldFunction(va(), nm("total"))),
      orders,
    ),
    "v",
  )
  assert_eq(show(i, t), "List Float")
}

///|
test "6. a record update keeps the type of its record and requires the field" {
  let i = new_infer()
  let update : @ir.Value = UpdateRecord(
    va(),
    v_var("r"),
    Map([(nm("total"), v_int("2"))]),
  )
  let t = i.value(v_lambda(p_var("r"), update), "v")
  assert_eq(show(i, t), "{ a | total : numberA } -> { a | total : numberA }")
  let i = new_infer()
  let f = v_lambda(p_var("r"), update)
  assert_eq(
    failure(() => {
      i.value(v_apply(f, v_record([("name", v_str("x"))])), "v") |> ignore
    }),
    ("missing_field", "v/argument"),
  )
  let i = new_infer()
  let t = i.value(
    v_apply(f, v_record([("total", v_float(1.5)), ("name", v_str("x"))])),
    "v",
  )
  assert_eq(show(i, t), "{ name : String, total : Float }")
}

///|
test "7. a record literal is closed" {
  let i = new_infer()
  let v = v_apply(
    FieldFunction(va(), nm("missing")),
    v_record([("a", v_int("1"))]),
  )
  assert_eq(
    failure(() => i.value(v, "v") |> ignore),
    ("missing_field", "v/argument"),
  )
  let i = new_infer()
  let t = i.value(v_record([("a", v_int("1")), ("b", v_str("s"))]), "v")
  assert_eq(show(i, t), "{ a : numberA, b : String }")
  let i = new_infer()
  let v : @ir.Value = Field(va(), v_record([("a", v_int("1"))]), nm("b"))
  assert_eq(failure(() => i.value(v, "v") |> ignore), ("missing_field", "v"))
}

///|
test "8. case m of Just x -> x; Nothing -> 0" {
  let i = new_infer()
  let cases = [
    (p_ctor("morphir/SDK:maybe#just", [p_var("x")]), v_var("x")),
    (p_ctor("morphir/SDK:maybe#nothing", []), v_int("0")),
  ]
  let t = i.value(
    v_lambda(p_var("m"), PatternMatch(va(), v_var("m"), cases)),
    "v",
  )
  assert_eq(show(i, t), "Maybe numberA -> numberA")
  // A constructor value instantiates its scheme.
  let i = new_infer()
  let t = i.value(
    v_apply(Constructor(va(), fq("morphir/SDK:maybe#just")), v_str("s")),
    "v",
  )
  assert_eq(show(i, t), "Maybe String")
  // A constructor pattern with the wrong number of arguments.
  let i = new_infer()
  let bad = [(p_ctor("morphir/SDK:maybe#just", []), v_int("0"))]
  assert_eq(
    failure(() => i.value(PatternMatch(va(), v_var("m"), bad), "v") |> ignore),
    ("unknown_reference", "v/subject"),
  )
  let i = new_infer()
  let t = i.value(
    v_lambda(p_var("m"), PatternMatch(va(), v_var("m"), bad)),
    "v",
  ) catch {
    MismatchAt(path, Mismatch(code, _, _)) => {
      assert_eq((code, path), ("arity", "v/body/cases/0/pattern"))
      UnitTy
    }
    e => raise e
  }
  assert_eq(t, UnitTy)
}

///|
test "9. applying an Int is arity" {
  let i = new_infer()
  i.env.values["acme/app:m#n"] = { gens: [], body: Con(INT, []), }
  assert_eq(
    failure(() => {
      i.value(v_apply(v_ref("acme/app:m#n"), v_int("1")), "v") |> ignore
    }),
    ("arity", "v"),
  )
  // Records, tuples and units are not functions either.
  let i = new_infer()
  assert_eq(
    failure(() => i.value(v_apply(Unit(va()), v_int("1")), "v") |> ignore),
    ("arity", "v"),
  )
}

///|
test "10. unknown references and missing dependencies" {
  let i = new_infer()
  assert_eq(
    failure(() => i.value(v_ref("acme/other:m#f"), "v") |> ignore),
    ("missing_dependency", "v"),
  )
  assert_eq(
    failure(() => i.value(v_ref("morphir/SDK:basics#nope"), "v") |> ignore),
    ("unknown_reference", "v"),
  )
  assert_eq(
    failure(() => i.value(v_ref("acme/app:m#nope"), "v") |> ignore),
    ("unknown_reference", "v"),
  )
  assert_eq(
    failure(() => {
      i.value(Constructor(va(), fq("acme/other:m#c")), "v") |> ignore
    }),
    ("missing_dependency", "v"),
  )
  assert_eq(
    failure(() => i.value(v_var("free"), "v") |> ignore),
    ("unknown_reference", "v"),
  )
  // The current binding group comes first, then the values of the environment.
  i.current["acme/app:m#g"] = Con(STRING, [])
  assert_eq(show(i, i.value(v_ref("acme/app:m#g"), "v")), "String")
}

///|
test "11. a hole uses its declared type" {
  let i = new_infer()
  let t = i.value(Hole(va(), DeletedDuringRefactor("x"), Some(t_int())), "v")
  assert_eq(show(i, t), "Int")
  let t = i.value(Hole(va(), DeletedDuringRefactor("x"), None), "w")
  assert_eq(show(i, t), "a")
}

///|
test "12. the types map holds the exact logical paths" {
  let i = new_infer()
  let root = @identities.value_root(fq("acme/app:m#f"))
  assert_eq(root, "value:acme/app:m#f")
  let body = v_apply(v_lambda(p_var("x"), v_var("x")), v_int("1"))
  i.definition(expr(body), root) |> ignore
  let keys = i.types.keys().collect()
  keys.sort()
  assert_eq(keys, [
    "value:acme/app:m#f/body", "value:acme/app:m#f/body/argument", "value:acme/app:m#f/body/function",
    "value:acme/app:m#f/body/function/body", "value:acme/app:m#f/body/function/pattern",
    "value:acme/app:m#f/body/function/pattern/pattern",
  ])
}

///|
test "12b. the path grammar for every construct" {
  let i = new_infer()
  let go : @ir.ValueDefinition = ExpressionBody(
    [],
    tmarked("u"),
    v_lambda(p_var("n"), v_apply(v_var("go"), v_var("n"))),
  )
  let case_ : @ir.Value = PatternMatch(
    va(),
    @ir.Value::List(va(), [v_int("1")]),
    [
      (@ir.Pattern::HeadTailPattern(va(), p_var("h"), p_wild()), v_var("h")),
      (@ir.Pattern::EmptyListPattern(va()), v_int("0")),
    ],
  )
  let update : @ir.Value = UpdateRecord(
    va(),
    v_record([("k", v_int("1"))]),
    Map([(nm("k"), v_int("2"))]),
  )
  let if_ : @ir.Value = IfThenElse(
    va(),
    v_bool(true),
    case_,
    Field(va(), update, nm("k")),
  )
  let destructure : @ir.Value = Destructure(
    va(),
    TuplePattern(va(), [p_var("a"), p_wild()]),
    Tuple(va(), [v_int("1"), v_str("s")]),
    if_,
  )
  let rec_ : @ir.Value = LetRecursion(va(), Map([(nm("go"), go)]), destructure)
  let v = v_let("id", expr(v_lambda(p_var("x"), v_var("x"))), rec_)
  i.value(v, "e") |> ignore
  let keys = i.types.keys().collect()
  keys.sort()
  let expected = [
    "e", "e/definition/body", "e/definition/body/body", "e/definition/body/pattern",
    "e/definition/body/pattern/pattern", "e/in", "e/in/definitions/go/body", "e/in/definitions/go/body/body",
    "e/in/definitions/go/body/body/argument", "e/in/definitions/go/body/body/function",
    "e/in/definitions/go/body/pattern", "e/in/definitions/go/body/pattern/pattern",
    "e/in/in", "e/in/in/in", "e/in/in/in/condition", "e/in/in/in/else", "e/in/in/in/else/record",
    "e/in/in/in/else/record/fields/k", "e/in/in/in/else/record/record", "e/in/in/in/else/record/record/fields/k",
    "e/in/in/in/then", "e/in/in/in/then/cases/0/body", "e/in/in/in/then/cases/0/pattern",
    "e/in/in/in/then/cases/0/pattern/head", "e/in/in/in/then/cases/0/pattern/head/pattern",
    "e/in/in/in/then/cases/0/pattern/tail", "e/in/in/in/then/cases/1/body", "e/in/in/in/then/cases/1/pattern",
    "e/in/in/in/then/subject", "e/in/in/in/then/subject/items/0", "e/in/in/pattern",
    "e/in/in/pattern/items/0", "e/in/in/pattern/items/0/pattern", "e/in/in/pattern/items/1",
    "e/in/in/value", "e/in/in/value/items/0", "e/in/in/value/items/1",
  ]
  expected.sort()
  assert_eq(keys, expected)
  // A constructor pattern's arguments.
  let i = new_infer()
  let p = p_ctor("morphir/SDK:maybe#just", [p_var("x")])
  i.pattern(p, "p") |> ignore
  let keys = i.types.keys().collect()
  keys.sort()
  assert_eq(keys, ["p", "p/args/0", "p/args/0/pattern"])
}

///|
test "path steps" {
  assert_eq(@identities.path_body("r"), "r/body")
  assert_eq(
    @identities.path_definitions_body("r", nm("go")),
    "r/definitions/go/body",
  )
  assert_eq(@identities.path_case_pattern("r", 2), "r/cases/2/pattern")
  assert_eq(@identities.path_case_body("r", 2), "r/cases/2/body")
  assert_eq(@identities.path_item("r", 0), "r/items/0")
  assert_eq(
    @identities.path_field("r", nm("total-amount")),
    "r/fields/total-amount",
  )
  assert_eq(@identities.path_arg("r", 1), "r/args/1")
  assert_eq(
    @identities.value_root(fq("morphir/SDK:list#map-2")),
    "value:morphir/SDK:list#map-2",
  )
}

///|
test "carry-forward: cyclic aliases are recorded and do not expand" {
  let env = test_env()
  let cyclic = env.cyclic_aliases.keys().collect()
  cyclic.sort()
  assert_eq(cyclic, [
    "acme/app:m#grow", "acme/app:m#loop", "acme/app:m#ping", "acme/app:m#pong",
  ])
  assert_eq(env.expand("acme/app:m#loop", []), None)
  assert_eq(env.expand("acme/app:m#ping", []), None)
  assert_eq(env.expand("acme/app:m#grow", [Con(INT, [])]), None)
  // An alias that only refers to a cycle is not itself cyclic, and expands once.
  assert_eq(
    env.expand("acme/app:m#to-loop", []),
    Some(Con("acme/app:m#loop", [])),
  )
  // Unification with a cyclic alias ends.
  let i = Infer::new(env, 1)
  assert_eq(
    code(() => i.solver.unify(Con("acme/app:m#loop", []), Con(INT, []))),
    "type_mismatch",
  )
  assert_eq(
    code(() => {
      i.solver.unify(Con("acme/app:m#ping", []), Con("acme/app:m#pong", []))
    }),
    "type_mismatch",
  )
}

///|
test "carry-forward: an alias to a record unifies with the record" {
  let env = test_env()
  assert_eq(
    env.expand("acme/app:m#point", []),
    Some(Rec(Map([("x", Con(INT, [])), ("y", Con(INT, []))]), None)),
  )
  assert_eq(
    env.expand("acme/app:m#pair", [Con(STRING, [])]),
    Some(Tup([Con(STRING, []), Con(STRING, [])])),
  )
  // point : Point
  // point = { x = 1, y = 2 }
  let i = Infer::new(env, 1)
  let point = tr("acme/app:m#point", [])
  let (t, _) = i.definition(
    ExpressionBody([], point, v_record([("x", v_int("1")), ("y", v_int("2"))])),
    "d",
  )
  assert_eq(show(i, t), "Point")
  // A field of a value of the alias.
  let t = i.value(
    Field(va(), Hole(va(), DeletedDuringRefactor(""), Some(point)), nm("x")),
    "f",
  )
  assert_eq(show(i, t), "Int")
  // A record that lacks a field of the alias.
  assert_eq(
    failure(() => {
      i.definition(
        ExpressionBody([], point, v_record([("x", v_int("1"))])),
        "e",
      )
      |> ignore
    }),
    ("missing_field", "e/body"),
  )
}

///|
test "environment: specifications, packages and constructors" {
  let env = test_env()
  assert_eq(env.packages.keys().collect(), ["morphir/SDK", "acme/app"])
  guard env.types.get("morphir/SDK:list#list") is Some(Nominal(list_arity)) else {
    fail("list is not nominal")
  }
  assert_eq(list_arity, 1)
  guard env.types.get("acme/app:m#shape") is Some(Nominal(shape_arity)) else {
    fail("shape is not nominal")
  }
  assert_eq(shape_arity, 0)
  guard env.constructors.get("acme/app:m#circle") is Some(circle) else {
    fail("no constructor")
  }
  assert_eq(circle.body, Fun(Con(FLOAT, []), Con("acme/app:m#shape", [])))
  guard env.values.get("morphir/SDK:list#map") is Some(map) else {
    fail("no value")
  }
  assert_eq(map.gens, [[], []])
  assert_eq(
    map.body,
    Fun(Fun(Gen(0), Gen(1)), Fun(Con(LIST, [Gen(0)]), Con(LIST, [Gen(1)]))),
  )
}

///|
test "environment: an application adds its bundled dependency definitions" {
  let lib = app_file()
  guard lib.distribution is Library(_, _, def) else { fail("not a library") }
  let values : Map[
    @ir.Name,
    @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]],
  ] = Map([
    (
      nm("public-f"),
      {
        access: Public,
        value: { doc: None, value: ExpressionBody([], t_int(), v_int("1")), },
      },
    ),
    (
      nm("secret"),
      {
        access: Private,
        value: { doc: None, value: ExpressionBody([], t_int(), v_int("1")), },
      },
    ),
  ])
  guard def.modules.get(pkg("m")) is Some(m) else { fail("no module") }
  let dep : @ir.PackageDefinition = {
    modules: Map([(pkg("m"), { ..m, value: { ..m.value, values, }, })]),
  }
  let own : @ir.PackageDefinition = { modules: Map([]), }
  let file = @ir.IRFile::new(
    Application(pkg("acme/main"), Map([(pkg("acme/app"), dep)]), own, Map([])),
  ) catch {
    _ => abort("bad file")
  }
  let env = Env::from(Map([(pkg("morphir/SDK"), sdk())]), file)
  assert_eq(env.packages.contains("acme/app"), true)
  assert_eq(env.packages.contains("acme/main"), true)
  assert_eq(
    env.values.get("acme/app:m#public-f").map(p => p.body),
    Some(Con(INT, [])),
  )
  assert_eq(env.values.contains("acme/app:m#secret"), false)
  guard env.types.get("acme/app:m#shape") is Some(Nominal(shape_arity)) else {
    fail("shape is not nominal")
  }
  assert_eq(shape_arity, 0)
  assert_eq(env.constructors.contains("acme/app:m#circle"), true)
}

///|
test "signatures: classes come from typeclass or the name prefix" {
  let p = poly_of_signature(
    [
      (nm("x"), tclass("x", "comparable")),
      (nm("y"), tv("number")),
      (nm("z"), tv("x")),
    ],
    tv("b"),
  )
  assert_eq(p.gens, [["comparable"], ["number"], []])
  assert_eq(p.body, Fun(Gen(0), Fun(Gen(1), Fun(Gen(0), Gen(2)))))
}

///|
test "naming: rigids keep their names and constrained metas take their class" {
  let i = new_infer()
  let s = i.solver
  let t = Tup([
    rigid("a"),
    s.fresh(1, []),
    s.fresh(1, ["comparable"]),
    s.fresh(1, ["comparable"]),
    s.fresh(1, []),
  ])
  let ir = Namer::new().to_ir(s, t)
  assert_eq(elm_text(ir), "( a, b, comparableA, comparableB, c )")
  guard ir is Tuple(_, [_, _, comparable, ..]) else { fail("not a tuple") }
  assert_eq(comparable, tclass("comparable-a", "comparable"))
  // The same meta keeps its name across calls of one namer.
  let namer = Namer::new()
  let m = s.fresh(1, [])
  assert_eq(namer.to_ir(s, m), tv("a"))
  assert_eq(namer.to_ir(s, Fun(s.fresh(1, []), m)), tfn(tv("b"), tv("a")))
}

///|
test "conversion: IR types to Ty and back" {
  let i = new_infer()
  let t = to_ty(
    tfn(
      ExtensibleRecord(tattrs(), nm("r"), Map([(nm("total"), t_int())])),
      Tuple(tattrs(), []),
    ),
    (name, _) => rigid(name),
  )
  assert_eq(
    t,
    Fun(Rec(Map([("total", Con(INT, []))]), Some(rigid("r"))), UnitTy),
  )
  assert_eq(show(i, t), "{ r | total : Int } -> ()")
}

///|
test "let annotations: declared variables are rigid inside and general outside" {
  // let id : a -> a
  //     id x = x
  // in (id 1, id "s")
  let i = new_infer()
  let id : @ir.ValueDefinition = ExpressionBody(
    [(nm("x"), tv("a"))],
    tv("a"),
    v_var("x"),
  )
  let body : @ir.Value = Tuple(va(), [
    v_apply(v_var("id"), v_int("1")),
    v_apply(v_var("id"), v_str("s")),
  ])
  assert_eq(show(i, i.value(v_let("id", id, body), "v")), "( numberA, String )")
  assert_true(i.rigid_scope.is_empty())
  // let f : a -> a
  //     f x = "s"
  let i = new_infer()
  let f : @ir.ValueDefinition = ExpressionBody(
    [(nm("x"), tv("a"))],
    tv("a"),
    v_str("s"),
  )
  assert_eq(
    failure(() => i.value(v_let("f", f, v_var("f")), "v") |> ignore),
    ("rigid_variable", "v/definition/body"),
  )
  // A declared variable must not escape into the enclosing scope.
  let i = new_infer()
  let g : @ir.ValueDefinition = ExpressionBody(
    [(nm("x"), tv("a"))],
    tv("a"),
    v_var("y"),
  )
  assert_eq(
    failure(() => {
      i.value(v_lambda(p_var("y"), v_let("g", g, v_var("y"))), "v") |> ignore
    }),
    ("rigid_variable", "v/body"),
  )
}

///|
test "let recursion solves the group together" {
  // let even n = if n == 0 then True else odd n; odd n = even n in even
  let i = new_infer()
  let even = expr(
    v_lambda(
      p_var("n"),
      IfThenElse(
        va(),
        v_bool(true),
        v_bool(true),
        v_apply(v_var("odd"), v_var("n")),
      ),
    ),
  )
  let odd = expr(v_lambda(p_var("n"), v_apply(v_var("even"), v_var("n"))))
  let v : @ir.Value = LetRecursion(
    va(),
    Map([(nm("even"), even), (nm("odd"), odd)]),
    Tuple(va(), [
      v_apply(v_var("even"), v_int("1")),
      v_apply(v_var("odd"), v_str("s")),
    ]),
  )
  assert_eq(show(i, i.value(v, "v")), "( Bool, Bool )")
}

///|
test "literals and patterns" {
  let i = new_infer()
  let lits : Array[(@ir.Literal, String)] = [
    (DecimalLiteral("1.5"), "Decimal"),
    (CharLiteral('c'), "Char"),
    (BoolLiteral(false), "Bool"),
  ]
  for lit in lits {
    assert_eq(show(i, i.value(Literal(va(), lit.0), "v")), lit.1)
  }
  assert_eq(
    failure(() => i.value(Literal(va(), DocumentLiteral(Null)), "d") |> ignore),
    ("unsupported", "d"),
  )
  assert_eq(show(i, i.value(Unit(va()), "v")), "()")
  assert_eq(show(i, i.value(Tuple(va(), []), "v")), "()")
  let t = i.pattern(
    HeadTailPattern(va(), LiteralPattern(va(), IntegerLiteral("1")), p_wild()),
    "p",
  )
  assert_eq(show(i, t), "List numberA")
  let t = i.pattern(
    TuplePattern(va(), [
      UnitPattern(va()),
      LiteralPattern(va(), StringLiteral("s")),
    ]),
    "p",
  )
  assert_eq(show(i, t), "( (), String )")
  assert_eq(show(i, i.pattern(EmptyListPattern(va()), "p")), "List a")
}
