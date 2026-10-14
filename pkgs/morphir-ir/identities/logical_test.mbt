///|
fn name(text : String) -> @ir.Name {
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
fn int_type() -> @ir.Type {
  Reference(Default::default(), fq("morphir/SDK:basics#int"), [])
}

///|
fn typed(t : @ir.Type) -> @ir.ValueAttributes {
  { source: None, inferred_type: Some(t), extensions: Map([]), }
}

///|
/// A library `p` with one module `m` and one value `f x = (1, x)`. With `with_types`, every body node has an
/// inferred type, so it is written in the expanded form.
fn library(with_types : Bool, input : @ir.Type) -> @ir.IRFile {
  let a = fn(t : @ir.Type) -> @ir.ValueAttributes {
    if with_types {
      typed(t)
    } else {
      Default::default()
    }
  }
  let pair : @ir.Type = Tuple(Default::default(), [int_type(), int_type()])
  let body : @ir.Value = Tuple(a(pair), [
    Literal(a(int_type()), IntegerLiteral("1")),
    Variable(a(int_type()), name("x")),
  ])
  file_of(ExpressionBody([(name("x"), input)], pair, body))
}

///|
/// A library `p` with one module `m` and one value `f` with the definition `def`.
fn file_of(def : @ir.ValueDefinition, doc? : String) -> @ir.IRFile {
  let module_def : @ir.ModuleDefinition = {
    types: Map([]),
    values: Map([(name("f"), { access: Public, value: { doc, value: def, }, })]),
    doc: None,
  }
  @ir.IRFile::new(
    Library(@ir.Path::parse("p") catch { _ => panic() }, Map([]), {
      modules: Map([
        (
          @ir.Path::parse("m") catch {
            _ => panic()
          },
          { access: Public, value: module_def, },
        ),
      ]),
    }),
  ) catch {
    _ => panic()
  }
}

///|
test "one logical node for each identity, with unique paths" {
  let file = library(true, int_type())
  let ids = @identities.nodes("u", file)
  let logical = @identities.logical_nodes("u", file)
  assert_eq(logical.map(n => n.id), ids)
  let seen : Map[String, Bool] = Map([])
  for n in logical {
    assert_false(seen.contains(n.path))
    seen[n.path] = true
    // Only declaration ids have no JSON, so the walk reached every other id.
    if n.tag == "declaration" {
      assert_false(n.id.contains("/"))
    }
  }
}

///|
test "a node keeps its logical path when its compact form becomes expanded" {
  let compact = @identities.logical_nodes("u", library(false, int_type()))
  let expanded = @identities.logical_nodes("u", library(true, int_type()))
  let tagged = fn(nodes : Array[@identities.LogicalNode]) {
    // The ids, and so the order, differ between the two forms.
    let result = nodes
      .filter(n => n.tag != "" && n.tag != "declaration")
      .map(n => (n.path, n.tag))
    result.sort()
    result
  }
  assert_eq(tagged(compact), tagged(expanded))
  let item = "value:p:m#f/body/items/0"
  let c = compact.filter(n => n.path == item)
  let e = expanded.filter(n => n.path == item)
  assert_eq(c.length(), 1)
  assert_eq(e.length(), 1)
  assert_eq(c[0].tag, "Literal")
  assert_true(c[0].id != e[0].id)
  // The literal scalar has the same logical leaf in both forms.
  let leaves = fn(nodes : Array[@identities.LogicalNode]) {
    nodes
    .filter(n => !n.attribute)
    .filter_map(n => n.leaf)
    .map(l => l.0 + "=" + l.1.stringify())
  }
  let lc = leaves(compact)
  let le = leaves(expanded)
  lc.sort()
  le.sort()
  assert_eq(lc, le)
}

///|
test "signature types use type steps, and a bare variable has its name leaf" {
  let list_a : @ir.Type = Reference(
    Default::default(),
    fq("morphir/SDK:list#list"),
    [Variable(Default::default(), name("a"))],
  )
  let nodes = @identities.logical_nodes("u", library(false, list_a))
  let arg = nodes.filter(n => n.path == "value:p:m#f/definition/inputs/x/args/0")
  assert_eq(arg.length(), 1)
  assert_eq(arg[0].tag, "Variable")
  assert_eq(
    arg[0].leaf,
    Some(
      (
        "value:p:m#f/definition/inputs/x/args/0!/Variable/name",
        Json::string("a"),
      ),
    ),
  )
  assert_true(nodes.iter().any(n => n.path == "value:p:m#f/input/x/args/0"))
}

///|
test "a marked variable is a marker node" {
  let marked : @ir.Type = Variable(
    (Default::default() : @ir.TypeAttributes).with_unknown(),
    name("t-0"),
  )
  let nodes = @identities.logical_nodes("u", library(false, marked))
  let m = nodes.filter(n => n.path == "value:p:m#f/definition/inputs/x")
  assert_eq(m.length(), 1)
  assert_true(m[0].marker)
  assert_true(
    nodes
    .iter()
    .any(n => {
      n.path.has_prefix("value:p:m#f/definition/inputs/x!/Variable/attributes") &&
      n.attribute
    }),
  )
}

///|
/// A library whose value `f` has each Value, Pattern and Type variant at least once. With `with_types`, every
/// Value and Pattern node has an inferred type, so it is written in the expanded form.
fn every_variant(with_types : Bool) -> @ir.IRFile {
  let t = int_type()
  let a = fn() -> @ir.ValueAttributes {
    if with_types {
      typed(t)
    } else {
      Default::default()
    }
  }
  let d : @ir.TypeAttributes = Default::default()
  let ext : @ir.Type = ExtensibleRecord(d, name("r"), Map([(name("a"), t)]))
  let fn_t : @ir.Type = Function(d, ext, t)
  let list_v : @ir.Type = Reference(d, fq("morphir/SDK:list#list"), [
    Variable(d, name("v")),
  ])
  let x : @ir.Value = Variable(a(), name("x"))
  let let_def : @ir.ValueDefinition = ExpressionBody(
    [(name("y"), t), (name("b"), t)],
    t,
    Lambda(
      a(),
      TuplePattern(a(), [
        AsPattern(a(), WildcardPattern(a()), name("w")),
        UnitPattern(a()),
      ]),
      Variable(a(), name("y")),
    ),
  )
  let recursive : @ir.ValueDefinition = ExpressionBody(
    [(name("z"), list_v)],
    t,
    Apply(a(), Reference(a(), fq("p:m#h")), FieldFunction(a(), name("k"))),
  )
  let cases : Array[(@ir.Pattern, @ir.Value)] = [
    (
      ConstructorPattern(a(), fq("p:m#c"), [WildcardPattern(a())]),
      IfThenElse(
        a(),
        x,
        Record(a(), Map([(name("a"), Literal(a(), IntegerLiteral("3")))])),
        UpdateRecord(a(), x, Map([(name("a"), Field(a(), x, name("a")))])),
      ),
    ),
    (
      HeadTailPattern(
        a(),
        LiteralPattern(a(), IntegerLiteral("4")),
        WildcardPattern(a()),
      ),
      List(a(), [
        Unit(a()),
        Hole(a(), DeletedDuringRefactor("gone"), Some(fn_t)),
      ]),
    ),
  ]
  let body : @ir.Value = LetDefinition(
    a(),
    name("g"),
    let_def,
    LetRecursion(
      a(),
      Map([(name("h"), recursive)]),
      Destructure(
        a(),
        TuplePattern(a(), [
          LiteralPattern(a(), IntegerLiteral("2")),
          EmptyListPattern(a()),
        ]),
        Tuple(a(), [
          Literal(a(), IntegerLiteral("1")),
          Constructor(a(), fq("p:m#c")),
        ]),
        PatternMatch(a(), x, cases),
      ),
    ),
  )
  let inputs : Array[(@ir.Name, @ir.Type)] = [
    (name("x"), Record(d, Map([(name("a"), t)]))),
    (name("q"), Tuple(d, [t, Unit(d)])),
  ]
  file_of(
    ExpressionBody(inputs, Variable(d.with_unknown(), name("t-0")), body),
    doc="f",
  )
}

///|
test "every variant has unique logical paths, the same in compact and expanded form" {
  let forms = [every_variant(false), every_variant(true)]
  let tagged : Array[Array[(String, String)]] = []
  let leaves : Array[Array[String]] = []
  for file in forms {
    let logical = @identities.logical_nodes("u", file)
    assert_eq(logical.map(n => n.id), @identities.nodes("u", file))
    let seen : Map[String, Bool] = Map([])
    for n in logical {
      assert_false(seen.contains(n.path))
      seen[n.path] = true
      // Only declaration ids have no JSON, so the walk reached every other id.
      if n.tag == "declaration" {
        assert_false(n.id.contains("/"))
      }
    }
    let t = logical
      .filter(n => n.tag != "" && n.tag != "declaration")
      .map(n => (n.path, n.tag))
    t.sort()
    tagged.push(t)
    let l = logical
      .filter(n => !n.attribute)
      .filter_map(n => n.leaf)
      .map(l => l.0 + "=" + l.1.stringify())
    l.sort()
    leaves.push(l)
    let tags = logical.map(n => n.tag)
    for
      variant in [
        "Literal", "Constructor", "Tuple", "List", "Record", "Variable", "Reference",
        "Field", "FieldFunction", "Apply", "Lambda", "LetDefinition", "LetRecursion",
        "Destructure", "IfThenElse", "PatternMatch", "UpdateRecord", "Unit", "Hole",
        "WildcardPattern", "AsPattern", "TuplePattern", "ConstructorPattern", "EmptyListPattern",
        "HeadTailPattern", "LiteralPattern", "UnitPattern", "ExtensibleRecord", "Function",
      ] {
      assert_true(tags.contains(variant), msg=variant)
    }
    assert_true(
      logical
      .iter()
      .any(n => n.path == "value:p:m#f/definition/output" && n.marker),
    )
    assert_true(
      logical
      .iter()
      .any(n => n.path == "value:p:m#f/definition/body/in/in/value/items/1"),
    )
    assert_true(
      logical
      .iter()
      .any(n => {
        n.path ==
        "value:p:m#f/body/in/in/in/cases/1/body/items/1/expected/parameter"
      }),
    )
  }
  assert_eq(tagged[0], tagged[1])
  assert_eq(leaves[0], leaves[1])
}
