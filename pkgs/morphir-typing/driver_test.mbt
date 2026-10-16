// Black-box tests for `infer`, `unknown_type` and `types_equivalent`. The specifications are small and made by
// hand with IR helpers; they do not use the real SDK.

///|
const INT = "morphir/SDK:basics#int"

///|
const BOOL = "morphir/SDK:basics#bool"

///|
const STRING = "morphir/SDK:string#string"

///|
const LIST = "morphir/SDK:list#list"

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
  @typing.unknown_type(nm(text))
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
fn t_int() -> @ir.Type {
  tr(INT, [])
}

///|
fn t_string() -> @ir.Type {
  tr(STRING, [])
}

///|
fn t_list(t : @ir.Type) -> @ir.Type {
  tr(LIST, [t])
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
fn v_str(s : String) -> @ir.Value {
  Literal(va(), StringLiteral(s))
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
fn v_apply(f : @ir.Value, args : Array[@ir.Value]) -> @ir.Value {
  let mut out = f
  for a in args {
    out = Apply(va(), out, a)
  }
  out
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
  let add = val_spec([("a", tv("number")), ("b", tv("number"))], tv("number"))
  let lt = val_spec(
    [("a", tv("comparable")), ("b", tv("comparable"))],
    tr(BOOL, []),
  )
  let basics = module_spec(
    [
      ("int", opaque_type([])),
      ("float", opaque_type([])),
      ("bool", opaque_type([])),
    ],
    [("add", add), ("lt", lt)],
  )
  let string = module_spec([("string", opaque_type([]))], [
    ("length", val_spec([("s", t_string())], t_int())),
  ])
  {
    modules: Map([
      (pkg("basics"), basics),
      (pkg("string"), string),
      (pkg("list"), module_spec([("list", opaque_type(["a"]))], [])),
    ]),
  }
}

///|
fn deps() -> Map[@ir.PackageName, @ir.PackageSpecification] {
  Map([(pkg("morphir/SDK"), sdk())])
}

///|
fn def_of(
  name : String,
  def : @ir.ValueDefinition,
) -> (@ir.Name, @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]]) {
  (nm(name), { access: Public, value: { doc: None, value: def, }, })
}

///|
/// A library `acme/app` with the given modules and value definitions, in this order.
fn library(
  modules : Array[(String, Array[(String, @ir.ValueDefinition)])],
) -> @ir.IRFile {
  library_with_types(modules.map(m => (m.0, [], m.1)))
}

///|
fn library_with_types(
  modules : Array[
    (
      String,
      Array[(String, @ir.TypeDefinition)],
      Array[(String, @ir.ValueDefinition)],
    ),
  ],
) -> @ir.IRFile {
  let out : Map[@ir.ModuleName, @ir.AccessControlled[@ir.ModuleDefinition]] = Map([],
  )
  for m in modules {
    let types = Map::from_array(
      m.1.map(t => {
        let def : @ir.AccessControlled[@ir.Documented[@ir.TypeDefinition]] = {
          access: Public,
          value: { doc: None, value: t.1, },
        }
        (nm(t.0), def)
      }),
    )
    let values = Map::from_array(m.2.map(v => def_of(v.0, v.1)))
    out[pkg(m.0)] = { access: Public, value: { types, values, doc: None, }, }
  }
  @ir.IRFile::new(Library(pkg("acme/app"), Map([]), { modules: out, })) catch {
    _ => abort("bad file")
  }
}

///|
fn fill(file : @ir.IRFile) -> @ir.IRFile raise @typing.InferenceFailed {
  @typing.infer(file, deps(), Fill)
}

///|
fn check(file : @ir.IRFile) -> @ir.IRFile raise @typing.InferenceFailed {
  @typing.infer(file, deps(), Check)
}

///|
/// The problems of a run that must fail, as `(code, node)` pairs.
fn problems(
  f : () -> @ir.IRFile raise @typing.InferenceFailed,
) -> Array[(String, String)] {
  failures(f).map(p => (p.code, p.node))
}

///|
fn failures(
  f : () -> @ir.IRFile raise @typing.InferenceFailed,
) -> Array[@typing.InferenceProblem] {
  try {
    f() |> ignore
    []
  } catch {
    InferenceFailed(ps) => ps
  }
}

///|
/// The definition of `module#name` in a library file.
fn definition_in(
  file : @ir.IRFile,
  module_ : String,
  name : String,
) -> @ir.ValueDefinition {
  guard file.distribution is Library(_, _, def) else { abort("not a library") }
  guard def.modules.get(pkg(module_)) is Some(m) else { abort("no module") }
  guard m.value.values.get(nm(name)) is Some(v) else { abort("no value") }
  v.value.value
}

///|
/// The signature `(inputs, output)` of `module#name` in a library file.
fn signature_in(
  file : @ir.IRFile,
  module_ : String,
  name : String,
) -> (Array[@ir.Type], @ir.Type) {
  guard definition_in(file, module_, name) is ExpressionBody(inputs, output, _) else {
    abort("not an expression body")
  }
  (inputs.map(i => i.1), output)
}

///|
/// Counts the value and pattern nodes of a file, and the nodes that have an `inferred_type`.
fn count_nodes(file : @ir.IRFile) -> (Int32, Int32) {
  guard file.distribution is Library(_, _, def) else { abort("not a library") }
  let counts = [0, 0]
  let visit = fn(a : @ir.ValueAttributes) {
    counts[0] = counts[0] + 1
    if a.inferred_type is Some(_) {
      counts[1] = counts[1] + 1
    }
  }
  for _, m in def.modules {
    for _, v in m.value.values {
      if v.value.value is ExpressionBody(_, _, body) {
        count_value(body, visit)
      }
    }
  }
  (counts[0], counts[1])
}

///|
fn count_value(v : @ir.Value, visit : (@ir.ValueAttributes) -> Unit) -> Unit {
  match v {
    Literal(a, _)
    | Constructor(a, _)
    | Variable(a, _)
    | Reference(a, _)
    | FieldFunction(a, _)
    | Unit(a)
    | Hole(a, _, _) => visit(a)
    Tuple(a, items) | List(a, items) => {
      visit(a)
      items.each(i => count_value(i, visit))
    }
    Record(a, fields) => {
      visit(a)
      fields.values().each(i => count_value(i, visit))
    }
    Field(a, r, _) => {
      visit(a)
      count_value(r, visit)
    }
    Apply(a, f, x) => {
      visit(a)
      count_value(f, visit)
      count_value(x, visit)
    }
    Lambda(a, p, body) => {
      visit(a)
      count_pattern(p, visit)
      count_value(body, visit)
    }
    LetDefinition(a, _, def, rest) => {
      visit(a)
      if def is ExpressionBody(_, _, body) {
        count_value(body, visit)
      }
      count_value(rest, visit)
    }
    LetRecursion(a, defs, rest) => {
      visit(a)
      for _, def in defs {
        if def is ExpressionBody(_, _, body) {
          count_value(body, visit)
        }
      }
      count_value(rest, visit)
    }
    Destructure(a, p, x, rest) => {
      visit(a)
      count_pattern(p, visit)
      count_value(x, visit)
      count_value(rest, visit)
    }
    IfThenElse(a, c, t, e) => {
      visit(a)
      [c, t, e].each(i => count_value(i, visit))
    }
    PatternMatch(a, s, cases) => {
      visit(a)
      count_value(s, visit)
      for c in cases {
        count_pattern(c.0, visit)
        count_value(c.1, visit)
      }
    }
    UpdateRecord(a, r, fields) => {
      visit(a)
      count_value(r, visit)
      fields.values().each(i => count_value(i, visit))
    }
  }
}

///|
fn count_pattern(
  p : @ir.Pattern,
  visit : (@ir.ValueAttributes) -> Unit,
) -> Unit {
  match p {
    WildcardPattern(a)
    | EmptyListPattern(a)
    | LiteralPattern(a, _)
    | UnitPattern(a) => visit(a)
    AsPattern(a, inner, _) => {
      visit(a)
      count_pattern(inner, visit)
    }
    TuplePattern(a, items) | ConstructorPattern(a, _, items) => {
      visit(a)
      items.each(i => count_pattern(i, visit))
    }
    HeadTailPattern(a, h, t) => {
      visit(a)
      count_pattern(h, visit)
      count_pattern(t, visit)
    }
  }
}

///|
/// `length xs = case xs of [] -> 0; _ :: rest -> 1 + length rest`, with an unknown signature.
fn length_def(self_name : String) -> @ir.ValueDefinition {
  let cases : Array[(@ir.Pattern, @ir.Value)] = [
    (EmptyListPattern(va()), v_int("0")),
    (
      HeadTailPattern(va(), p_wild(), p_var("rest")),
      v_apply(v_ref("morphir/SDK:basics#add"), [
        v_int("1"),
        v_apply(v_ref(self_name), [v_var("rest")]),
      ]),
    ),
  ]
  ExpressionBody(
    [(nm("xs"), tmarked("t"))],
    tmarked("r"),
    PatternMatch(va(), v_var("xs"), cases),
  )
}

///|
/// A two-module library with lets, lambdas, records, patterns and a cross-module reference.
fn sample_library() -> @ir.IRFile {
  let total = @ir.ValueDefinition::ExpressionBody(
    [(nm("n"), t_int())],
    t_int(),
    v_apply(v_ref("acme/app:b#double"), [
      v_let("y", ExpressionBody([], tmarked("t"), v_var("n")), v_var("y")),
    ]),
  )
  let pick = @ir.ValueDefinition::ExpressionBody(
    [],
    tmarked("r"),
    v_lambda(
      TuplePattern(va(), [p_var("p"), p_wild()]),
      Field(
        va(),
        v_record([("total", v_var("p")), ("name", v_str("x"))]),
        nm("total"),
      ),
    ),
  )
  let ident = @ir.ValueDefinition::ExpressionBody(
    [],
    tmarked("r"),
    v_let(
      "id",
      ExpressionBody([], tmarked("s"), v_lambda(p_var("x"), v_var("x"))),
      Tuple(va(), [
        v_apply(v_var("id"), [v_int("1")]),
        v_apply(v_var("id"), [v_str("s")]),
      ]),
    ),
  )
  let double = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), tmarked("t"))],
    tmarked("r"),
    v_apply(v_ref("morphir/SDK:basics#add"), [v_var("x"), v_var("x")]),
  )
  library([
    ("a", [("total", total), ("pick", pick), ("ident", ident)]),
    ("b", [("double", double), ("length", length_def("acme/app:b#length"))]),
  ])
}

///|
test "1. fill sets inferred_type on every value and pattern node" {
  let file = sample_library()
  assert_eq(count_nodes(file).1, 0)
  let filled = fill(file)
  let (nodes, typed) = count_nodes(filled)
  assert_true(nodes > 30)
  assert_eq(typed, nodes)
  // The unknown signatures are solved.
  assert_eq(
    signature_in(filled, "b", "double"),
    ([tclass("number-a", "number")], tclass("number-a", "number")),
  )
  let (_, pick) = signature_in(filled, "a", "pick")
  assert_eq(pick, tfn(@ir.Type::Tuple(tattrs(), [tv("a"), tv("b")]), tv("a")))
  let (_, ident) = signature_in(filled, "a", "ident")
  assert_eq(
    ident,
    @ir.Type::Tuple(tattrs(), [tclass("number-a", "number"), t_string()]),
  )
}

///|
test "2. a module references a value of a later module (Review Focus)" {
  let use_ = @ir.ValueDefinition::ExpressionBody(
    [],
    tmarked("r"),
    Tuple(va(), [
      v_apply(v_ref("acme/app:b#f"), [v_int("1")]),
      v_apply(v_ref("acme/app:b#f"), [v_str("s")]),
    ]),
  )
  let f = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), tmarked("t"))],
    tmarked("r"),
    v_var("x"),
  )
  let filled = fill(library([("a", [("use", use_)]), ("b", [("f", f)])]))
  // `f` is generalized before `use` is solved, so `use` takes it at two types.
  assert_eq(
    signature_in(filled, "a", "use").1,
    Tuple(tattrs(), [tclass("number-a", "number"), t_string()]),
  )
  assert_eq(signature_in(filled, "b", "f"), ([tv("a")], tv("a")))
}

///|
test "3. polymorphic recursion through an annotation (Review Focus)" {
  // f : List a -> Int
  // f xs = f [ xs ]
  let body = v_apply(v_ref("acme/app:m#f"), [List(va(), [v_var("xs")])])
  let declared = @ir.ValueDefinition::ExpressionBody(
    [(nm("xs"), t_list(tv("a")))],
    t_int(),
    body,
  )
  let file = library([("m", [("f", declared)])])
  let filled = fill(file)
  assert_eq(signature_in(filled, "m", "f"), ([t_list(tv("a"))], t_int()))
  // Without the annotation the recursion is monomorphic, and the type is infinite.
  let unknown = @ir.ValueDefinition::ExpressionBody(
    [(nm("xs"), tmarked("t"))],
    tmarked("r"),
    body,
  )
  assert_eq(problems(() => fill(library([("m", [("f", unknown)])]))), [
    ("occurs", "value:acme/app:m#f/body/argument"),
  ])
}

///|
test "4. an undeclared recursive function infers monomorphically" {
  let file = library([("m", [("length", length_def("acme/app:m#length"))])])
  let filled = fill(file)
  assert_eq(
    signature_in(filled, "m", "length"),
    ([t_list(tv("a"))], tclass("number-a", "number")),
  )
}

///|
test "5. a body that narrows an annotated variable is rigid_variable" {
  // id : a -> a
  // id = \x -> 1
  let id = @ir.ValueDefinition::ExpressionBody(
    [],
    tfn(tv("a"), tv("a")),
    v_lambda(p_var("x"), v_int("1")),
  )
  let found = failures(() => fill(library([("m", [("id", id)])])))
  assert_eq(found.map(p => (p.code, p.node)), [
    ("rigid_variable", "value:acme/app:m#id/body"),
  ])
  assert_eq(
    found[0].message,
    "the variable `a` is annotated as any type, but the body needs number",
  )
}

///|
test "6. the unknown marker is solved: inc x = x + length \"s\" is Int -> Int" {
  let body = v_apply(v_ref("morphir/SDK:basics#add"), [
    v_var("x"),
    v_apply(v_ref("morphir/SDK:string#length"), [v_str("s")]),
  ])
  let inc = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), tmarked("a"))],
    tmarked("b"),
    body,
  )
  let filled = fill(library([("m", [("inc", inc)])]))
  assert_eq(signature_in(filled, "m", "inc"), ([t_int()], t_int()))
}

///|
test "7. filling a filled file gives the same file (Review Focus)" {
  let once = fill(sample_library())
  let twice = fill(once)
  assert_eq(twice, once)
}

///|
test "8. check mode returns a correct file unchanged and reports a changed type" {
  let filled = fill(sample_library())
  assert_true(check(filled) == filled)
  // Change the type of the argument of `double` in `total`.
  guard filled.distribution is Library(name, own, def) else { fail("library") }
  guard def.modules.get(pkg("a")) is Some(a) else { fail("module a") }
  guard a.value.values.get(nm("total")) is Some(total) else { fail("total") }
  guard total.value.value
    is ExpressionBody(inputs, output, Apply(attrs, f, arg)) else {
    fail("total body")
  }
  let wrong : @ir.Value = match arg {
    LetDefinition(argument, n, d, rest) =>
      LetDefinition(
        { ..argument, inferred_type: Some(t_string()), },
        n,
        d,
        rest,
      )
    _ => fail("argument")
  }
  let values = a.value.values.copy()
  values[nm("total")] = {
    ..total,
    value: {
      ..total.value,
      value: ExpressionBody(inputs, output, Apply(attrs, f, wrong)),
    },
  }
  let modules = def.modules.copy()
  modules[pkg("a")] = { ..a, value: { ..a.value, values, }, }
  let changed = @ir.IRFile::new(Library(name, own, { modules, }))
  let found = failures(() => check(changed))
  assert_eq(found.map(p => (p.code, p.node)), [
    ("annotation_mismatch", "value:acme/app:a#total/body/argument"),
  ])
  assert_eq(found[0].expected, Some(t_int()))
  assert_eq(found[0].found, Some(t_string()))
  // Fill reports the same disagreement.
  assert_eq(problems(() => fill(changed)), [
    ("annotation_mismatch", "value:acme/app:a#total/body/argument"),
  ])
}

///|
test "9. a failure in one component does not stop another" {
  // x-bad : Int
  // x-bad = "s"
  let loc : @ir.SourceLocation = {
    start_line: 3,
    start_column: 9,
    end_line: 3,
    end_column: 12,
  }
  let x_bad = @ir.ValueDefinition::ExpressionBody(
    [],
    t_int(),
    Literal({ ..va(), source: Some(loc), }, StringLiteral("s")),
  )
  let good = @ir.ValueDefinition::ExpressionBody([], tmarked("r"), v_int("1"))
  // a-bad : String
  // a-bad = { total = 1 }.count
  let a_bad = @ir.ValueDefinition::ExpressionBody(
    [],
    t_string(),
    Field(va(), v_record([("total", v_int("1"))]), nm("count")),
  )
  let file = library([
    ("m", [("x-bad", x_bad), ("good", good), ("a-bad", a_bad)]),
  ])
  let found = failures(() => fill(file))
  assert_eq(found.map(p => (p.code, p.node)), [
    ("missing_field", "value:acme/app:m#a-bad/body"),
    ("type_mismatch", "value:acme/app:m#x-bad/body"),
  ])
  assert_eq(found[0].message, "the record has no field `count`")
  assert_eq(found[1].message, "expected Int, found String")
  assert_eq(found[1].expected, Some(t_int()))
  assert_eq(found[1].found, Some(t_string()))
  assert_eq(found[1].source, Some(loc))
  // Check mode collects the same problems.
  assert_eq(problems(() => check(file)), found.map(p => (p.code, p.node)))
}

///|
test "10. two runs give equal files" {
  assert_true(fill(sample_library()) == fill(sample_library()))
}

///|
test "11. types_equivalent renames variables bijectively" {
  assert_true(
    @typing.types_equivalent(tfn(tv("a"), tv("b")), tfn(tv("x"), tv("y"))),
  )
  assert_false(
    @typing.types_equivalent(tfn(tv("a"), tv("a")), tfn(tv("x"), tv("y"))),
  )
  assert_false(
    @typing.types_equivalent(tfn(tv("a"), tv("b")), tfn(tv("x"), tv("x"))),
  )
  // Attributes do not count.
  assert_true(
    @typing.types_equivalent(tclass("number-a", "number"), tmarked("n")),
  )
  assert_false(@typing.types_equivalent(t_int(), t_string()))
  assert_false(@typing.types_equivalent(t_list(tv("a")), tv("a")))
}

///|
test "unknown_type carries the unknown marker" {
  assert_eq(
    @typing.unknown_type(nm("a")),
    Variable(
      { ..tattrs(), extensions: Map([("morphir.inference", Text("unknown"))]), },
      nm("a"),
    ),
  )
}

///|
test "carry-forward: rigid classes do not leak between declarations" {
  // cmp : x -> x -> Bool, where x is comparable
  // cmp a b = lt a b
  let x = tclass("x", "comparable")
  let lt = v_ref("morphir/SDK:basics#lt")
  let cmp = @ir.ValueDefinition::ExpressionBody(
    [(nm("a"), x), (nm("b"), x)],
    tr(BOOL, []),
    v_apply(lt, [v_var("a"), v_var("b")]),
  )
  // bad : Int -> Bool
  // bad n = let h : x -> Bool
  //             h v = lt v v
  //         in h n
  // The `x` of the let annotation is a new rigid with no class, so `lt v v` fails.
  let h = @ir.ValueDefinition::ExpressionBody(
    [(nm("v"), tv("x"))],
    tr(BOOL, []),
    v_apply(lt, [v_var("v"), v_var("v")]),
  )
  let bad = @ir.ValueDefinition::ExpressionBody(
    [(nm("n"), t_int())],
    tr(BOOL, []),
    v_let("h", h, v_apply(v_var("h"), [v_var("n")])),
  )
  let at = "value:acme/app:m#bad/body/definition/body/function/argument"
  assert_eq(
    problems(() => fill(library([("m", [("cmp", cmp), ("bad", bad)])]))),
    [("rigid_variable", at)],
  )
  // A failed declaration does not leak its rigid classes either.
  let failing = @ir.ValueDefinition::ExpressionBody(
    [(nm("a"), x)],
    tr(BOOL, []),
    v_str("s"),
  )
  assert_eq(
    problems(() => fill(library([("m", [("failing", failing), ("bad", bad)])]))),
    [("rigid_variable", at), ("type_mismatch", "value:acme/app:m#failing/body")],
  )
}

///|
test "carry-forward: rigid classes do not leak inside one group" {
  // p and q refer to each other, so they are one group, solved in IR order.
  // p (a : x, where x is comparable) = q 1
  // q b = let u = p in String.length hole, where the hole has the type x
  // The `x` of the hole is not p's `x`: it is a fresh type, so the hole can be a String.
  let p = @ir.ValueDefinition::ExpressionBody(
    [(nm("a"), tclass("x", "comparable"))],
    tmarked("r"),
    v_apply(v_ref("acme/app:m#q"), [v_int("1")]),
  )
  let hole : @ir.Value = Hole(va(), DeletedDuringRefactor("x"), Some(tv("x")))
  let q = @ir.ValueDefinition::ExpressionBody(
    [(nm("b"), tmarked("t"))],
    tmarked("r"),
    v_let(
      "u",
      ExpressionBody([], tmarked("t"), v_ref("acme/app:m#p")),
      v_apply(v_ref("morphir/SDK:string#length"), [hole]),
    ),
  )
  let filled = fill(library([("m", [("p", p), ("q", q)])]))
  assert_true(check(filled) == filled)
}

///|
test "R3: a hole is a todo: its free variables are fresh, its scoped variables are rigid" {
  let length = v_ref("morphir/SDK:string#length")
  let hole = fn(t : @ir.Type) -> @ir.Value {
    Hole(va(), DeletedDuringRefactor("x"), Some(t))
  }
  // f : Int -> Int
  // f n = add (String.length hole) (hole), where both holes have the type x: each is its own todo.
  let f = @ir.ValueDefinition::ExpressionBody(
    [(nm("n"), t_int())],
    t_int(),
    v_apply(v_ref("morphir/SDK:basics#add"), [
      v_apply(length, [hole(tv("x"))]),
      hole(tv("x")),
    ]),
  )
  let filled = fill(library([("m", [("f", f)])]))
  assert_true(check(filled) == filled)
  // g : a -> Int
  // g v = String.length hole, where the hole has g's type a: a String is not any type a.
  let g = @ir.ValueDefinition::ExpressionBody(
    [(nm("v"), tv("a"))],
    t_int(),
    v_apply(length, [hole(tv("a"))]),
  )
  assert_eq(problems(() => fill(library([("m", [("g", g)])]))), [
    ("rigid_variable", "value:acme/app:m#g/body/argument"),
  ])
  // k : Int
  // k = String.length hole, where the hole has the type x, a number by its typeclass.
  let k = @ir.ValueDefinition::ExpressionBody(
    [],
    t_int(),
    v_apply(length, [hole(tclass("x", "number"))]),
  )
  assert_eq(problems(() => fill(library([("m", [("k", k)])]))), [
    ("no_instance", "value:acme/app:m#k/body/argument"),
  ])
}

///|
test "a failed group reports once, and its dependants do not report again" {
  // even n = ( odd n, String.length 1 ) and odd n = ( even n, String.length 1 ) are one group. Both bodies are
  // wrong, but the group stops at its first failure.
  let wrong = fn(other : String) -> @ir.ValueDefinition {
    ExpressionBody(
      [(nm("n"), tmarked("t"))],
      tmarked("r"),
      Tuple(va(), [
        v_apply(v_ref(other), [v_var("n")]),
        v_apply(v_ref("morphir/SDK:string#length"), [v_int("1")]),
      ]),
    )
  }
  let even = wrong("acme/app:m#odd")
  let odd = wrong("acme/app:m#even")
  // user = String.length (even 1): `even` failed, so it is any type here.
  let user = @ir.ValueDefinition::ExpressionBody(
    [],
    tmarked("r"),
    v_apply(v_ref("morphir/SDK:string#length"), [
      v_apply(v_ref("acme/app:m#even"), [v_int("1")]),
    ]),
  )
  let found = problems(() => {
    fill(library([("m", [("even", even), ("odd", odd), ("user", user)])]))
  })
  assert_eq(found, [
    ("no_instance", "value:acme/app:m#even/body/items/1/argument"),
  ])
}

///|
test "carry-forward: names do not clash with rigid names inside the body" {
  // f x = let g : a -> a = \y -> y in g x
  let g = @ir.ValueDefinition::ExpressionBody(
    [],
    tfn(tv("a"), tv("a")),
    v_lambda(p_var("y"), v_var("y")),
  )
  let body = v_let("g", g, v_apply(v_var("g"), [v_var("x")]))
  let f = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), tmarked("t"))],
    tmarked("r"),
    body,
  )
  let filled = fill(library([("m", [("f", f)])]))
  assert_eq(signature_in(filled, "m", "f"), ([tv("b")], tv("b")))
  assert_true(fill(filled) == filled)
}

///|
test "carry-forward: a cyclic alias is unsupported at its type path" {
  let loop_ : @ir.TypeDefinition = TypeAliasDefinition(
    [],
    tr("acme/app:m#loop", []),
  )
  let file = library_with_types([
    ("m", [("loop", loop_)], [("one", ExpressionBody([], t_int(), v_int("1")))]),
  ])
  let found = failures(() => fill(file))
  assert_eq(found.map(p => (p.code, p.node)), [
    ("unsupported", "type:acme/app:m#loop"),
  ])
  assert_eq(problems(() => check(file)), [
    ("unsupported", "type:acme/app:m#loop"),
  ])
}

///|
test "let signatures with unknown types are filled" {
  // f = let id : s? = \x -> x in id 1
  let id = @ir.ValueDefinition::ExpressionBody(
    [],
    tmarked("s"),
    v_lambda(p_var("x"), v_var("x")),
  )
  let f = @ir.ValueDefinition::ExpressionBody(
    [],
    tmarked("r"),
    v_let("id", id, v_apply(v_var("id"), [v_int("1")])),
  )
  let filled = fill(library([("m", [("f", f)])]))
  guard definition_in(filled, "m", "f")
    is ExpressionBody(_, _, LetDefinition(_, _, ExpressionBody(_, out, _), _)) else {
    fail("let")
  }
  assert_eq(out, tfn(tv("a"), tv("a")))
}

///|
test "native and external bodies" {
  // n : Int -> Int is native. e : Int has a fallback that calls n. bad : Int has a String fallback.
  let native : @ir.ValueDefinition = NativeBody([(nm("x"), t_int())], t_int(), {
    hint: Arithmetic,
    description: None,
  })
  let external : @ir.ValueDefinition = ExternalBody(
    [],
    t_int(),
    [],
    Some(v_apply(v_ref("acme/app:m#n"), [v_int("1")])),
  )
  let bad : @ir.ValueDefinition = ExternalBody(
    [],
    t_int(),
    [],
    Some(v_str("s")),
  )
  let file = library([("m", [("n", native), ("e", external)])])
  let filled = fill(file)
  assert_eq(definition_in(filled, "m", "n"), native)
  guard definition_in(filled, "m", "e") is ExternalBody(_, _, _, Some(fallback)) else {
    fail("external")
  }
  guard fallback is Apply(attrs, _, _) else { fail("apply") }
  assert_eq(attrs.inferred_type, Some(t_int()))
  assert_eq(problems(() => fill(library([("m", [("bad", bad)])]))), [
    ("type_mismatch", "value:acme/app:m#bad/body"),
  ])
}

///|
test "specs: fill returns the file, check resolves references" {
  let spec : @ir.PackageSpecification = {
    modules: Map([
      (
        pkg("m"),
        module_spec([], [
          ("ok", val_spec([("x", t_int())], t_int())),
          ("bad", val_spec([], tr("acme/app:m#nothing", []))),
          ("far", val_spec([], tr("other/pkg:m#t", []))),
        ]),
      ),
    ]),
  }
  let file = @ir.IRFile::new(Specs(pkg("acme/app"), Map([]), spec))
  assert_true(fill(file) == file)
  assert_eq(problems(() => check(file)), [
    ("unknown_reference", "value:acme/app:m#bad"),
    ("missing_dependency", "value:acme/app:m#far"),
  ])
}

///|
test "an application is filled and keeps its entry points" {
  let main = @ir.ValueDefinition::ExpressionBody([], tmarked("r"), v_str("hi"))
  guard library([("m", [("main", main)])]).distribution is Library(name, _, def) else {
    fail("library")
  }
  let entries : Map[String, @ir.EntryPoint] = Map([
    ("main", { target: fq("acme/app:m#main"), kind: Main, doc: None, }),
  ])
  let file = @ir.IRFile::new(Application(name, Map([]), def, entries))
  let filled = fill(file)
  guard filled.distribution is Application(_, _, def, kept) else {
    fail("application")
  }
  assert_eq(kept, entries)
  guard def.modules.get(pkg("m")) is Some(m) else { fail("module") }
  guard m.value.values.get(nm("main")) is Some(v) else { fail("main") }
  guard v.value.value is ExpressionBody(_, output, body) else { fail("body") }
  assert_eq(output, t_string())
  guard body is Literal(attrs, _) else { fail("literal") }
  assert_eq(attrs.inferred_type, Some(t_string()))
}

///|
test "P5: signature rigids of one group belong to their declaration" {
  // f : a -> r, where a is a number and r is unknown
  // f x = add x (g x)
  // g : a -> s, where s is unknown
  // g y = f y
  // h : String
  // h = g "s"
  // The `a` of g is not the `a` of f. Fill must not write `g : a -> a`.
  let f = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), tclass("a", "number"))],
    tmarked("r"),
    v_apply(v_ref("morphir/SDK:basics#add"), [
      v_var("x"),
      v_apply(v_ref("acme/app:m#g"), [v_var("x")]),
    ]),
  )
  let g = @ir.ValueDefinition::ExpressionBody(
    [(nm("y"), tv("a"))],
    tmarked("s"),
    v_apply(v_ref("acme/app:m#f"), [v_var("y")]),
  )
  let h = @ir.ValueDefinition::ExpressionBody(
    [],
    t_string(),
    v_apply(v_ref("acme/app:m#g"), [v_str("s")]),
  )
  let file = library([("m", [("f", f), ("g", g), ("h", h)])])
  let found = failures(() => fill(file))
  assert_true(found.length() > 0)
  for p in found {
    assert_true(p.code == "rigid_variable" || p.code == "no_instance")
  }
  assert_eq(found.map(p => (p.code, p.node)), [
    ("rigid_variable", "value:acme/app:m#f/body/argument/argument"),
  ])
  // The variable is f's `a`. g's `a` is another variable, so it gets a new name.
  assert_eq(
    found[0].message,
    "the variable `a` is annotated as a number, but the body needs b",
  )
  assert_eq(found[0].expected, Some(tv("b")))
  assert_eq(found[0].found, Some(tclass("a", "number")))
  // Check mode finds the same problem.
  assert_eq(problems(() => check(file)), found.map(p => (p.code, p.node)))
}

///|
test "owned rigids: a let annotation shares the signature's variable and declares its own" {
  // f : a -> a, where a is a number
  // f x = let g : a -> a
  //           g y = add y x
  //           k : b -> b
  //           k z = z
  //       in k (g x)
  // The `a` of g is f's `a`, so `add y x` is fine. The `b` of k is a new variable of f.
  let a = tclass("a", "number")
  let g = @ir.ValueDefinition::ExpressionBody(
    [(nm("y"), a)],
    a,
    v_apply(v_ref("morphir/SDK:basics#add"), [v_var("y"), v_var("x")]),
  )
  let k = @ir.ValueDefinition::ExpressionBody(
    [(nm("z"), tv("b"))],
    tv("b"),
    v_var("z"),
  )
  let body = v_let(
    "g",
    g,
    v_let("k", k, v_apply(v_var("k"), [v_apply(v_var("g"), [v_var("x")])])),
  )
  let f = @ir.ValueDefinition::ExpressionBody([(nm("x"), a)], a, body)
  // h : b -> b
  // h w = w
  // Another declaration's `b` is not k's `b`.
  let h = @ir.ValueDefinition::ExpressionBody(
    [(nm("w"), tv("b"))],
    tv("b"),
    v_var("w"),
  )
  let filled = fill(library([("m", [("f", f), ("h", h)])]))
  // The output names rigids without their owner.
  guard definition_in(filled, "m", "f")
    is ExpressionBody(
      _,
      _,
      LetDefinition(_, _, ExpressionBody(_, _, Apply(g_body, _, _)), _)
    ) else {
    fail("f body")
  }
  assert_eq(g_body.inferred_type, Some(a))
  assert_true(check(filled) == filled)
  // A let annotation of a new variable that the body narrows still fails.
  let k_bad = @ir.ValueDefinition::ExpressionBody(
    [(nm("z"), tv("b"))],
    tv("b"),
    v_var("x"),
  )
  let bad = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), a)],
    a,
    v_let("k", k_bad, v_var("x")),
  )
  assert_eq(problems(() => fill(library([("m", [("bad", bad)])]))), [
    ("rigid_variable", "value:acme/app:m#bad/body/definition/body"),
  ])
}

///|
/// A variable value whose node already has the type `t`.
fn v_var_typed(text : String, t : @ir.Type) -> @ir.Value {
  Variable({ ..va(), inferred_type: Some(t), }, nm(text))
}

///|
test "P1: check finds a node typed with the wrong signature variable" {
  // f : a -> b -> a
  // f x y = x, where the node `x` has the type b
  let f = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), tv("a")), (nm("y"), tv("b"))],
    tv("a"),
    v_var_typed("x", tv("b")),
  )
  let file = library([("m", [("f", f)])])
  assert_eq(problems(() => check(file)), [
    ("annotation_mismatch", "value:acme/app:m#f/body"),
  ])
  assert_eq(problems(() => fill(file)), [
    ("annotation_mismatch", "value:acme/app:m#f/body"),
  ])
  // The right variable passes.
  let good = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), tv("a")), (nm("y"), tv("b"))],
    tv("a"),
    v_var_typed("x", tv("a")),
  )
  let file = library([("m", [("f", good)])])
  assert_true(check(file) == file)
}

///|
test "P1b: check finds a node that drops the class of a variable" {
  // g : comparable -> Bool
  // g x = lt x x, where the first `x` has the type a
  let lt = v_ref("morphir/SDK:basics#lt")
  let g = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), tv("comparable"))],
    tr(BOOL, []),
    v_apply(lt, [v_var_typed("x", tv("a")), v_var("x")]),
  )
  let at = "value:acme/app:m#g/body/function/argument"
  assert_eq(problems(() => check(library([("m", [("g", g)])]))), [
    ("annotation_mismatch", at),
  ])
  // The same name without its class: g : a -> Bool, where a is comparable by its typeclass.
  let classed = tclass("a", "comparable")
  let g = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), classed)],
    tr(BOOL, []),
    v_apply(lt, [v_var_typed("x", tv("a")), v_var("x")]),
  )
  assert_eq(problems(() => check(library([("m", [("g", g)])]))), [
    ("annotation_mismatch", at),
  ])
  let g = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), classed)],
    tr(BOOL, []),
    v_apply(lt, [v_var_typed("x", classed), v_var("x")]),
  )
  let file = library([("m", [("g", g)])])
  assert_true(check(file) == file)
  // An inferred class: k x = add x x has x : number-a, so a plain `a` is wrong.
  let k = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), tmarked("t"))],
    tmarked("r"),
    v_apply(v_ref("morphir/SDK:basics#add"), [
      v_var_typed("x", tv("a")),
      v_var("x"),
    ]),
  )
  assert_eq(problems(() => check(library([("m", [("k", k)])]))), [
    ("annotation_mismatch", "value:acme/app:m#k/body/function/argument"),
  ])
}

///|
test "one renaming for the types of one declaration" {
  // k x = ( x, x ), where the nodes of the two items have the types a and b. Inference gives both nodes the
  // same variable, so they cannot be two variables.
  let k = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), tmarked("t"))],
    tmarked("r"),
    Tuple(va(), [v_var_typed("x", tv("a")), v_var_typed("x", tv("b"))]),
  )
  assert_eq(problems(() => check(library([("m", [("k", k)])]))), [
    ("annotation_mismatch", "value:acme/app:m#k/body/items/1"),
  ])
  // One name for both passes, whatever name it is. Another declaration has its own renaming.
  let k = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), tmarked("t"))],
    tmarked("r"),
    Tuple(va(), [v_var_typed("x", tv("q")), v_var_typed("x", tv("q"))]),
  )
  let j = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), tmarked("t"))],
    tmarked("r"),
    v_var_typed("x", tv("q")),
  )
  let file = library([("m", [("k", k), ("j", j)])])
  assert_true(check(file) == file)
}

///|
test "TypeScope: signature variables map to themselves, pairs persist, classes count" {
  // f : a -> r, where r is unknown
  let f = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), tv("a"))],
    tmarked("r"),
    v_var("x"),
  )
  let scope = @typing.TypeScope::of_definition(f)
  assert_false(scope.equivalent(tv("b"), tv("a")))
  assert_true(scope.equivalent(tv("a"), tv("a")))
  // A failed comparison keeps no pair: x is still free after this.
  assert_false(scope.equivalent(tfn(tv("x"), tv("a")), tfn(tv("y"), tv("b"))))
  assert_true(scope.equivalent(tv("x"), tv("z")))
  // The pair x = z holds for later types.
  assert_false(scope.equivalent(tv("x"), tv("w")))
  assert_true(scope.equivalent(t_list(tv("x")), t_list(tv("z"))))
  // Classes must match: from typeclass or the name prefix.
  assert_false(scope.equivalent(tv("n"), tclass("m", "number")))
  assert_true(scope.equivalent(tv("number"), tclass("m", "number")))
  // types_equivalent still compares one pair alone and ignores attributes.
  assert_true(@typing.types_equivalent(tv("b"), tv("a")))
  assert_true(@typing.types_equivalent(tv("n"), tclass("m", "number")))
}

///|
test "M3: an unknown typeclass is unsupported at the node" {
  let orderable = tclass("a", "orderable")
  // f : a -> a, where a has the unknown class orderable
  let f = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), orderable)],
    orderable,
    v_var("x"),
  )
  let found = failures(() => fill(library([("m", [("f", f)])])))
  assert_eq(found.map(p => (p.code, p.node)), [
    ("unsupported", "value:acme/app:m#f"),
  ])
  assert_eq(
    found[0].message,
    "inference does not support the type class `orderable`",
  )
  // A let annotation.
  let h = @ir.ValueDefinition::ExpressionBody(
    [(nm("y"), orderable)],
    t_string(),
    v_str("s"),
  )
  let g = @ir.ValueDefinition::ExpressionBody(
    [],
    t_int(),
    v_let("h", h, v_int("1")),
  )
  assert_eq(problems(() => fill(library([("m", [("g", g)])]))), [
    ("unsupported", "value:acme/app:m#g/body/definition"),
  ])
  // A hole.
  let k = @ir.ValueDefinition::ExpressionBody(
    [],
    tmarked("r"),
    Hole(va(), DeletedDuringRefactor("x"), Some(orderable)),
  )
  assert_eq(problems(() => check(library([("m", [("k", k)])]))), [
    ("unsupported", "value:acme/app:m#k/body"),
  ])
  // A value of a dependency: weird : a -> String, where a is orderable.
  let dep : @ir.PackageSpecification = {
    modules: Map([
      (
        pkg("odd"),
        module_spec([], [("weird", val_spec([("x", orderable)], t_string()))]),
      ),
    ]),
  }
  let u = @ir.ValueDefinition::ExpressionBody(
    [],
    t_string(),
    v_apply(v_ref("acme/dep:odd#weird"), [v_str("s")]),
  )
  let all_deps = deps()
  all_deps[pkg("acme/dep")] = dep
  let found = failures(() => {
    @typing.infer(library([("m", [("u", u)])]), all_deps, Fill)
  })
  assert_eq(found.map(p => (p.code, p.node)), [
    ("unsupported", "value:acme/app:m#u/body/function"),
  ])
}

///|
test "type references: an identity over a missing package is missing_dependency" {
  // ident : other/pkg:m#missing -> other/pkg:m#missing
  // ident x = x
  let missing = tr("other/pkg:m#missing", [])
  let ident = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), missing)],
    missing,
    v_var("x"),
  )
  let file = library([("m", [("ident", ident)])])
  let expected = [("missing_dependency", "value:acme/app:m#ident")]
  assert_eq(problems(() => fill(file)), expected)
  assert_eq(problems(() => check(file)), expected)
}

///|
test "type references: an unknown type of a known package is unknown_reference" {
  // ident : List Nothing -> Int, where morphir/SDK is known and has no `nothing` type
  let ident = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), t_list(tr("morphir/SDK:basics#nothing", [])))],
    t_int(),
    v_int("1"),
  )
  // own : acme/app:m#nothing, in the file's own package
  let own = @ir.ValueDefinition::ExpressionBody(
    [],
    tr("acme/app:m#nothing", []),
    Hole(va(), DeletedDuringRefactor("x"), None),
  )
  let file = library([("m", [("ident", ident), ("own", own)])])
  assert_eq(problems(() => check(file)), [
    ("unknown_reference", "value:acme/app:m#ident"),
    ("unknown_reference", "value:acme/app:m#own"),
  ])
}

///|
test "type references: let signatures, holes and type bodies are validated" {
  let missing = tr("other/pkg:m#missing", [])
  // f : Int
  // f = let y : other/pkg:m#missing = 1 in 2
  let f = @ir.ValueDefinition::ExpressionBody(
    [],
    t_int(),
    v_let("y", ExpressionBody([], missing, v_int("1")), v_int("2")),
  )
  // g : Int
  // g = let rec z : morphir/SDK:basics#nothing = z in 2
  let g = @ir.ValueDefinition::ExpressionBody(
    [],
    t_int(),
    LetRecursion(
      va(),
      Map([
        (
          nm("z"),
          ExpressionBody([], tr("morphir/SDK:basics#nothing", []), v_var("z")),
        ),
      ]),
      v_int("2"),
    ),
  )
  // h : Int
  // h = (hole : other/pkg:m#missing) |> \_ -> 1
  let h = @ir.ValueDefinition::ExpressionBody(
    [],
    t_int(),
    v_apply(v_lambda(p_wild(), v_int("1")), [
      Hole(va(), DeletedDuringRefactor("x"), Some(missing)),
    ]),
  )
  let synonym : @ir.TypeDefinition = TypeAliasDefinition([], t_list(missing))
  let custom : @ir.TypeDefinition = CustomTypeDefinition([], {
    access: Public,
    value: Map([(nm("box"), [(nm("x"), tr("acme/app:m#nothing", []))])]),
  })
  let file = library_with_types([
    (
      "m",
      [("alias", synonym), ("custom", custom)],
      [("f", f), ("g", g), ("h", h)],
    ),
  ])
  let expected = [
    ("missing_dependency", "type:acme/app:m#alias"),
    ("unknown_reference", "type:acme/app:m#custom"),
    ("missing_dependency", "value:acme/app:m#f/body/definition"),
    ("unknown_reference", "value:acme/app:m#g/body/definitions/z"),
    ("missing_dependency", "value:acme/app:m#h/body/argument"),
  ]
  assert_eq(problems(() => fill(file)), expected)
  assert_eq(problems(() => check(file)), expected)
}

///|
test "type references: an application validates its signatures" {
  let missing = tr("other/pkg:m#missing", [])
  let main = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), missing)],
    missing,
    v_var("x"),
  )
  guard library([("m", [("main", main)])]).distribution is Library(name, _, def) else {
    fail("library")
  }
  let file = @ir.IRFile::new(Application(name, Map([]), def, Map([])))
  assert_eq(problems(() => check(file)), [
    ("missing_dependency", "value:acme/app:m#main"),
  ])
}

///|
test "non-injective aliases: Token String is Token Bool when Token ignores its parameter" {
  // type alias Token a = Int
  // type Box a = Box a
  let token = @ir.TypeDefinition::TypeAliasDefinition([nm("a")], t_int())
  let box = @ir.TypeDefinition::CustomTypeDefinition([nm("a")], {
    access: Public,
    value: Map([(nm("box"), [(nm("x"), tv("a"))])]),
  })
  let t_token = fn(t : @ir.Type) { tr("acme/app:m#token", [t]) }
  let t_box = fn(t : @ir.Type) { tr("acme/app:m#box", [t]) }
  // f : Token String -> Token Bool
  // f x = x
  let f = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), t_token(t_string()))],
    t_token(tr(BOOL, [])),
    v_var("x"),
  )
  // g : Token String -> Int
  // g x = x
  let g = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), t_token(t_string()))],
    t_int(),
    v_var("x"),
  )
  // h : Box String -> Box Bool
  // h x = x
  let h = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), t_box(t_string()))],
    t_box(tr(BOOL, [])),
    v_var("x"),
  )
  let file = library_with_types([
    ("m", [("token", token), ("box", box)], [("f", f), ("g", g), ("h", h)]),
  ])
  assert_eq(problems(() => check(file)), [
    ("type_mismatch", "value:acme/app:m#h/body"),
  ])
}

///|
fn arity_signature(t : @ir.Type) -> @ir.IRFile {
  // f : <t>
  // f = <hole>
  let f = @ir.ValueDefinition::ExpressionBody(
    [],
    t,
    Hole(va(), DeletedDuringRefactor("x"), None),
  )
  library([("m", [("f", f)])])
}

///|
test "type references: a nominal type with too many arguments is arity" {
  // f : List Int Int, where List takes one argument
  let file = arity_signature(tr(LIST, [t_int(), t_int()]))
  let expected = [("arity", "value:acme/app:m#f")]
  assert_eq(problems(() => fill(file)), expected)
  assert_eq(problems(() => check(file)), expected)
}

///|
test "type references: a nominal type with too few arguments is arity" {
  // f : List, with no argument
  let file = arity_signature(tr(LIST, []))
  let expected = [("arity", "value:acme/app:m#f")]
  assert_eq(problems(() => fill(file)), expected)
  assert_eq(problems(() => check(file)), expected)
}

///|
test "type references: an alias with the wrong number of arguments is arity" {
  // type alias Token a = Int
  // f : Token, then g : Token Int Int
  let token = @ir.TypeDefinition::TypeAliasDefinition([nm("a")], t_int())
  let hole = @ir.ValueDefinition::ExpressionBody(
    [],
    tr("acme/app:m#token", []),
    Hole(va(), DeletedDuringRefactor("x"), None),
  )
  let hole2 = @ir.ValueDefinition::ExpressionBody(
    [],
    tr("acme/app:m#token", [t_int(), t_int()]),
    Hole(va(), DeletedDuringRefactor("x"), None),
  )
  let file = library_with_types([
    ("m", [("token", token)], [("f", hole), ("g", hole2)]),
  ])
  let expected = [
    ("arity", "value:acme/app:m#f"),
    ("arity", "value:acme/app:m#g"),
  ]
  assert_eq(problems(() => fill(file)), expected)
  assert_eq(problems(() => check(file)), expected)
}

///|
test "rigid classes: fill keeps a class that only typeclass gives, across a group" {
  // f : p? -> q?
  // f x = g x
  // g : a -> s?, where a is a number by its typeclass
  // g y = add y (f y)
  let f = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), tmarked("p"))],
    tmarked("q"),
    v_apply(v_ref("acme/app:m#g"), [v_var("x")]),
  )
  let g = @ir.ValueDefinition::ExpressionBody(
    [(nm("y"), tclass("a", "number"))],
    tmarked("s"),
    v_apply(v_ref("morphir/SDK:basics#add"), [
      v_var("y"),
      v_apply(v_ref("acme/app:m#f"), [v_var("y")]),
    ]),
  )
  let filled = fill(library([("m", [("f", f), ("g", g)])]))
  let (inputs, output) = signature_in(filled, "m", "f")
  guard inputs is [Variable(attrs, _)] else { fail("f input") }
  assert_eq(attrs.constraints.get("typeclass"), Some(Text("number")))
  assert_eq(output, inputs[0])
  assert_true(check(filled) == filled)
}

///|
test "rigid classes: an unknown typeclass in a group is unsupported in any order" {
  // f : p? -> q?
  // f x = g (add x x)
  // g : a -> s?, where a has the unknown class orderable
  // g y = let u = f in y
  let f = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), tmarked("p"))],
    tmarked("q"),
    v_apply(v_ref("acme/app:m#g"), [
      v_apply(v_ref("morphir/SDK:basics#add"), [v_var("x"), v_var("x")]),
    ]),
  )
  let u = @ir.ValueDefinition::ExpressionBody(
    [],
    tmarked("t"),
    v_ref("acme/app:m#f"),
  )
  let g = @ir.ValueDefinition::ExpressionBody(
    [(nm("y"), tclass("a", "orderable"))],
    tmarked("s"),
    v_let("u", u, v_var("y")),
  )
  let expected = [("unsupported", "value:acme/app:m#g")]
  assert_eq(
    problems(() => fill(library([("m", [("f", f), ("g", g)])]))),
    expected,
  )
  assert_eq(
    problems(() => fill(library([("m", [("g", g), ("f", f)])]))),
    expected,
  )
}

///|
test "rigid classes: a let annotation keeps its typeclass in the fill output" {
  // f = let h : x -> Bool, where x is comparable by its typeclass
  //         h v = lt v v
  //     in h 1
  let h = @ir.ValueDefinition::ExpressionBody(
    [(nm("v"), tclass("x", "comparable"))],
    tr(BOOL, []),
    v_apply(v_ref("morphir/SDK:basics#lt"), [v_var("v"), v_var("v")]),
  )
  let f = @ir.ValueDefinition::ExpressionBody(
    [],
    tmarked("r"),
    v_let("h", h, v_apply(v_var("h"), [v_int("1")])),
  )
  let filled = fill(library([("m", [("f", f)])]))
  guard definition_in(filled, "m", "f")
    is ExpressionBody(
      _,
      _,
      LetDefinition(_, _, ExpressionBody(_, _, Apply(_, _, Variable(a, _))), _)
    ) else {
    fail("let body")
  }
  assert_eq(a.inferred_type, Some(tclass("x", "comparable")))
  assert_true(check(filled) == filled)
}

///|
test "rigid classes: a mismatch in classes only names the classes" {
  // g : a -> Bool, where a is comparable by its typeclass
  // g x = lt x x, where the first `x` has the type a without a class
  let classed = tclass("a", "comparable")
  let g = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), classed)],
    tr(BOOL, []),
    v_apply(v_ref("morphir/SDK:basics#lt"), [
      v_var_typed("x", tv("a")),
      v_var("x"),
    ]),
  )
  let found = failures(() => check(library([("m", [("g", g)])])))
  assert_eq(found.map(p => p.message), [
    "the node has the type a, but inference gives a where a is comparable",
  ])
}

///|
test "R1: an undeclared member generalizes the rigids of the other members" {
  // f : p? -> q?
  // f x = g x
  // g : a -> s?, where a is a number by its typeclass
  // g y = add y (f y)
  // h : r?
  // h = f (String.length "s")
  let f = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), tmarked("p"))],
    tmarked("q"),
    v_apply(v_ref("acme/app:m#g"), [v_var("x")]),
  )
  let g = @ir.ValueDefinition::ExpressionBody(
    [(nm("y"), tclass("a", "number"))],
    tmarked("s"),
    v_apply(v_ref("morphir/SDK:basics#add"), [
      v_var("y"),
      v_apply(v_ref("acme/app:m#f"), [v_var("y")]),
    ]),
  )
  let h = @ir.ValueDefinition::ExpressionBody(
    [],
    tmarked("r"),
    v_apply(v_ref("acme/app:m#f"), [
      v_apply(v_ref("morphir/SDK:string#length"), [v_str("s")]),
    ]),
  )
  let filled = fill(library([("m", [("f", f), ("g", g), ("h", h)])]))
  assert_eq(signature_in(filled, "m", "h"), ([], t_int()))
  assert_true(check(filled) == filled)
}

///|
/// `f : Int -> Int` whose body is `let rec <defs> in 1`.
fn let_rec_in(defs : Array[(String, @ir.ValueDefinition)]) -> @ir.IRFile {
  let rec_ : @ir.Value = LetRecursion(
    va(),
    Map::from_array(defs.map(d => (nm(d.0), d.1))),
    v_int("1"),
  )
  library([("m", [("f", ExpressionBody([(nm("n"), t_int())], t_int(), rec_))])])
}

///|
test "R2: an annotated let-rec sibling is polymorphic inside the group" {
  // h1 : a -> a
  // h1 x = x
  // h2 : a -> String
  // h2 y = h1 "s"
  let h1 = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), tv("a"))],
    tv("a"),
    v_var("x"),
  )
  let h2 = @ir.ValueDefinition::ExpressionBody(
    [(nm("y"), tv("a"))],
    t_string(),
    v_apply(v_var("h1"), [v_str("s")]),
  )
  let filled = fill(let_rec_in([("h1", h1), ("h2", h2)]))
  assert_true(check(filled) == filled)
}

///|
test "R2: let-rec siblings do not share annotation variables" {
  // h1 : a -> a
  // h1 x = k x
  // h2 : a -> a
  // h2 y = k y
  // k z = h1 z, unannotated, so monomorphic inside the group: the a of h1 is not the a of h2.
  let h1 = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), tv("a"))],
    tv("a"),
    v_apply(v_var("k"), [v_var("x")]),
  )
  let h2 = @ir.ValueDefinition::ExpressionBody(
    [(nm("y"), tv("a"))],
    tv("a"),
    v_apply(v_var("k"), [v_var("y")]),
  )
  let k = @ir.ValueDefinition::ExpressionBody(
    [(nm("z"), tmarked("t"))],
    tmarked("r"),
    v_apply(v_var("h1"), [v_var("z")]),
  )
  let found = problems(() => {
    fill(let_rec_in([("h1", h1), ("h2", h2), ("k", k)]))
  })
  assert_eq(found.map(p => p.0), ["rigid_variable"])
}

///|
test "R2: an unknown typeclass in a let-rec sibling is unsupported in any order" {
  // h1 : r?
  // h1 = h2 (String.length "s")
  // h2 : a -> a, where a has the unknown class orderable
  // h2 y = y
  let h1 = @ir.ValueDefinition::ExpressionBody(
    [],
    tmarked("r"),
    v_apply(v_var("h2"), [
      v_apply(v_ref("morphir/SDK:string#length"), [v_str("s")]),
    ]),
  )
  let orderable = tclass("a", "orderable")
  let h2 = @ir.ValueDefinition::ExpressionBody(
    [(nm("y"), orderable)],
    orderable,
    v_var("y"),
  )
  let at = "value:acme/app:m#f/body/definitions/h2"
  assert_eq(problems(() => fill(let_rec_in([("h1", h1), ("h2", h2)]))), [
    ("unsupported", at),
  ])
  assert_eq(problems(() => fill(let_rec_in([("h2", h2), ("h1", h1)]))), [
    ("unsupported", at),
  ])
}

///|
/// An application `acme/main` with one module `m` of `own` values, that bundles the library package of `dep`.
fn application_with(
  dep : @ir.IRFile,
  own : Array[(String, @ir.ValueDefinition)],
) -> @ir.IRFile {
  guard dep.distribution is Library(dep_name, _, dep_def) else {
    abort("not a library")
  }
  guard library([("m", own)]).distribution is Library(_, _, def) else {
    abort("not a library")
  }
  @ir.IRFile::new(
    Application(pkg("acme/main"), Map([(dep_name, dep_def)]), def, Map([])),
  ) catch {
    _ => abort("bad file")
  }
}

///|
test "C1: type references in a bundled public interface must resolve" {
  // The bundled package acme/app (from `library_with_types`), module util:
  //   type alias Secret = Int, private
  //   double : Int -> Missing      (Missing is not defined)
  //   peek : Secret -> Int         (a private type of the same package resolves)
  //   double x = x                 (bundled bodies are trusted, not inferred)
  let dep = library_with_types([
    (
      "util",
      [("secret", TypeAliasDefinition([], t_int()))],
      [
        (
          "double",
          ExpressionBody(
            [(nm("x"), t_int())],
            tr("acme/app:util#missing", []),
            v_var("x"),
          ),
        ),
        (
          "peek",
          ExpressionBody(
            [(nm("s"), tr("acme/app:util#secret", []))],
            t_int(),
            v_int("1"),
          ),
        ),
      ],
    ),
  ])
  guard dep.distribution is Library(name, deps, def) else { fail("library") }
  let util = def.modules[pkg("util")]
  let secret = util.value.types[nm("secret")]
  let types = util.value.types.copy()
  types[nm("secret")] = { ..secret, access: Private, }
  let modules = def.modules.copy()
  modules[pkg("util")] = { ..util, value: { ..util.value, types, }, }
  let dep = @ir.IRFile::new(Library(name, deps, { modules, })) catch {
    _ => fail("bad file")
  }
  let file = application_with(dep, [
    ("main", ExpressionBody([], t_int(), v_int("1"))),
  ])
  let expected = [("unknown_reference", "value:acme/app:util#double")]
  assert_eq(problems(() => fill(file)), expected)
  assert_eq(problems(() => check(file)), expected)
}

///|
fn fact(t : @ir.Type) -> @ir.ValueAttributes {
  { ..va(), inferred_type: Some(t), }
}

///|
fn fact_int(text : String) -> @ir.Value {
  Literal(fact(t_int()), IntegerLiteral(text))
}

///|
test "Q4: an integer literal with the fact Int fills as Int" {
  // inc x = x + 1, where the literal has the fact Int and the signature is unknown.
  let body = v_apply(v_ref("morphir/SDK:basics#add"), [
    v_var("x"),
    fact_int("1"),
  ])
  let file = library([
    (
      "m",
      [
        (
          "inc",
          ExpressionBody([(nm("x"), tmarked("t-0"))], tmarked("t-1"), body),
        ),
      ],
    ),
  ])
  let (inputs, output) = signature_in(fill(file), "m", "inc")
  assert_true(@typing.types_equivalent(inputs[0], t_int()))
  assert_true(@typing.types_equivalent(output, t_int()))
}

///|
test "Q4: a conflicting fact is annotation_mismatch at the node" {
  let body : @ir.Value = Literal(fact(t_string()), IntegerLiteral("1"))
  let file = library([("m", [("c", ExpressionBody([], tmarked("t-0"), body))])])
  assert_eq(problems(() => fill(file)), [
    ("annotation_mismatch", "value:acme/app:m#c/body"),
  ])
}

///|
test "Q4: a partial fact is a constraint, and the node gets its solution" {
  // xs = [1], where the list has the fact `List a` and `a` is not in scope.
  let body : @ir.Value = List(fact(t_list(tv("a"))), [fact_int("1")])
  let file = library([("m", [("xs", ExpressionBody([], tmarked("t-0"), body))])])
  guard definition_in(fill(file), "m", "xs") is ExpressionBody(_, _, List(a, _)) else {
    fail("not a list")
  }
  assert_true(
    @typing.types_equivalent(a.inferred_type.unwrap(), t_list(t_int())),
  )
}

///|
test "Q4: a fact variable in scope is rigid" {
  // k : a -> Int; k x = 1, where the literal has the fact `a`. The signature's `a` is in scope, so the fact's
  // `a` is that rigid variable, and a number cannot be it. With a fresh meta, the run would succeed.
  let body : @ir.Value = Literal(fact(tv("a")), IntegerLiteral("1"))
  let file = library([
    ("m", [("k", ExpressionBody([(nm("x"), tv("a"))], t_int(), body))]),
  ])
  assert_eq(problems(() => fill(file)), [
    ("annotation_mismatch", "value:acme/app:m#k/body"),
  ])
}

///|
test "Q4: check mode still compares node types after inference" {
  let body : @ir.Value = Literal(fact(t_string()), IntegerLiteral("1"))
  let file = library([("m", [("c", ExpressionBody([], t_int(), body))])])
  assert_eq(problems(() => check(file)), [
    ("annotation_mismatch", "value:acme/app:m#c/body"),
  ])
}

///|
test "Q4: check uses facts, so an Int literal fact narrows a number variable" {
  // inc x = x + 1 and pick c = if c then 1 else 2, with unknown signatures and the fact Int on each literal, as
  // the Scheme frontend writes them. Without the facts, each literal is `number a` and is not equivalent to Int.
  let inc = v_apply(v_ref("morphir/SDK:basics#add"), [v_var("x"), fact_int("1")])
  let pick : @ir.Value = IfThenElse(
    va(),
    v_var("c"),
    fact_int("1"),
    fact_int("2"),
  )
  let file = library([
    (
      "m",
      [
        (
          "inc",
          ExpressionBody([(nm("x"), tmarked("t-0"))], tmarked("t-1"), inc),
        ),
        (
          "pick",
          ExpressionBody([(nm("c"), tmarked("t-2"))], tmarked("t-3"), pick),
        ),
      ],
    ),
  ])
  assert_true(check(file) == file)
}

///|
test "Q4: check reports a fact that is more general than the solution" {
  // xs = [1], where the list has the fact `List a` and `a` is not in scope. The fact unifies, but the solution
  // `List Int` is not equivalent to `List a`.
  let body : @ir.Value = List(fact(t_list(tv("a"))), [fact_int("1")])
  let file = library([("m", [("xs", ExpressionBody([], tmarked("t-0"), body))])])
  assert_eq(problems(() => check(file)), [
    ("annotation_mismatch", "value:acme/app:m#xs/body"),
  ])
}

///|
test "display names the code, the node and the source" {
  let p : @typing.InferenceProblem = {
    code: "type_mismatch",
    node: "value:p:m#f/body",
    message: "expected Int, found String",
    expected: None,
    found: None,
    source: Some({ start_line: 2, start_column: 3, end_line: 2, end_column: 9, }),
  }
  assert_eq(
    p.display(),
    "type_mismatch at value:p:m#f/body: expected Int, found String (2:3-2:9)",
  )
}
