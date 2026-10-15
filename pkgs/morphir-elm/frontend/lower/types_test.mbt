///|
fn scope_of(text : String) -> @resolve.Scope {
  let result = @krueger.parse_module(@krueger.SourceText::new(text))
  guard result.ast is Some(file) else { panic() }
  let m : @resolve.ParsedModule = {
    name: ["My", "Pkg", "M"],
    path: "My/Pkg/M.elm",
    file,
  }
  let p = @resolve.Project::new(["My", "Pkg"], [m]) catch { _ => panic() }
  p.scope(["My", "Pkg", "M"])
}

///|
fn declarations(text : String) -> Array[@ast.Node[@ast.Declaration]] {
  let result = @krueger.parse_module(@krueger.SourceText::new(text))
  guard result.ast is Some(file) else { panic() }
  file.declarations.to_owned()
}

///|
/// Drops every attribute, so that tests compare shapes.
fn bare(t : @ir.Type) -> @ir.Type {
  let a = @ir.TypeAttributes::default()
  match t {
    Variable(_, n) => Variable(a, n)
    Reference(_, n, args) => Reference(a, n, args.map(bare))
    Tuple(_, items) => Tuple(a, items.map(bare))
    Record(_, fields) => Record(a, fields.map((_, v) => bare(v)))
    ExtensibleRecord(_, r, fields) =>
      ExtensibleRecord(a, r, fields.map((_, v) => bare(v)))
    Function(_, x, y) => Function(a, bare(x), bare(y))
    Unit(_) => Unit(a)
  }
}

///|
let source = "module My.Pkg.M exposing (..)\n\n{-| The module. -}\n\n{-| A point. -}\ntype alias Point =\n    { x : Float, y : Float }\n\ntype Tree comparable\n    = Leaf\n    | Node (Tree comparable) comparable (Tree comparable)\n\ntype alias Pair a =\n    ( a, a )\n\ntype alias Named r =\n    { r | name : String }\n\ntype alias F =\n    Int -> () -> List (Maybe Int)\n"

///|
test "type aliases and custom types lower like morphir-elm" {
  let scope = scope_of(source)
  let defs = declarations(source).filter_map(d => {
    @lower.lower_type_definition(scope, d.value) catch {
      _ => panic()
    }
  })
  let by_name = Map::from_array(defs.map(d => (d.0, (d.1, d.2))))
  guard by_name.get("Point")
    is Some((TypeAliasDefinition([], Record(_, fields)), doc)) else {
    fail("Point")
  }
  assert_eq(doc, Some(" A point. "))
  assert_eq(fields.keys().map(n => n.to_canonical()).collect(), ["x", "y"])
  guard by_name.get("Tree") is Some((CustomTypeDefinition(params, ctors), None)) else {
    fail("Tree")
  }
  assert_eq(params.map(p => p.to_canonical()), ["comparable"])
  guard ctors.value.get(@mapping.elm_name("Node")) is Some(args) else {
    fail("Node")
  }
  assert_eq(args.map(a => a.0.to_canonical()), ["arg-1", "arg-2", "arg-3"])
  guard args[1].1 is Variable(attrs, _) else { fail("variable") }
  assert_eq(
    attrs.constraints.get("typeclass"),
    Some(@ir.Data::Text("comparable")),
  )
  guard by_name.get("Named") is Some((TypeAliasDefinition(_, body), _)) else {
    fail("Named")
  }
  assert_true(bare(body) is ExtensibleRecord(_, _, _))
  guard by_name.get("F") is Some((TypeAliasDefinition(_, f), _)) else {
    fail("F")
  }
  guard bare(f)
    is Function(
      _,
      Reference(_, int, []),
      Function(_, Unit(_), Reference(_, list, [Reference(_, maybe, _)]))
    ) else {
    fail("F shape")
  }
  assert_eq(int.to_canonical(), "morphir/SDK:basics#int")
  assert_eq(list.to_canonical(), "morphir/SDK:list#list")
  assert_eq(maybe.to_canonical(), "morphir/SDK:maybe#maybe")
}

///|
test "types carry their source location" {
  let text = "module My.Pkg.M exposing (..)\n\ntype alias I =\n    Int\n"
  let scope = scope_of(text)
  let def = @lower.lower_type_definition(scope, declarations(text)[0].value) catch {
    _ => panic()
  }
  guard def is Some((_, TypeAliasDefinition(_, Reference(attrs, _, _)), _)) else {
    fail("I")
  }
  assert_eq(
    attrs.source,
    Some({ start_line: 4, start_column: 5, end_line: 4, end_column: 8, }),
  )
}

///|
test "review focus 5: an undeclared type variable is reported" {
  let text = "module My.Pkg.M exposing (..)\n\ntype alias P =\n    List a\n"
  let scope = scope_of(text)
  let code = try {
    ignore(@lower.lower_type_definition(scope, declarations(text)[0].value))
    "ok"
  } catch {
    @lower.LowerError(code, _, Some(_)) => code
    _ => "other"
  }
  assert_eq(code, "elm.unbound_type_variable")
}

///|
test "docs keep the raw text between the delimiters" {
  assert_eq(
    @lower.doc_text(
      Some({
        range: { start: { row: 1, column: 1, }, end: { row: 1, column: 17, }, },
        value: "{-| A point. -}",
      }),
    ),
    Some(" A point. "),
  )
  assert_eq(@lower.doc_text(None), None)
}
