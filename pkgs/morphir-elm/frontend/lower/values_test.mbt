///|
fn elm_module(declarations : Array[String]) -> String {
  "module My.Pkg.M exposing (..)\n\n\n" + declarations.join("\n\n\n") + "\n"
}

///|
fn definition_of(text : String, name : String) -> @ir.ValueDefinition {
  let (_, definition, _) = @lower.lower_value_definition(
    scope_of(text),
    function_named(text, name),
  ) catch {
    @lower.LowerError(code, message, _) => abort(code + ": " + message)
  }
  definition
}

///|
fn body_text(text : String, name : String) -> String {
  guard definition_of(text, name) is ExpressionBody(_, _, b) else {
    abort("not an expression body")
  }
  show(b)
}

///|
fn input_names(text : String, name : String) -> Array[String] {
  guard definition_of(text, name) is ExpressionBody(inputs, _, _) else {
    abort("not an expression body")
  }
  inputs.map(i => i.0.to_canonical())
}

///|
fn lower_code(text : String, name : String) -> String {
  try {
    ignore(
      @lower.lower_value_definition(scope_of(text), function_named(text, name)),
    )
    "ok"
  } catch {
    @lower.LowerError(code, _, Some(_)) => code
    @lower.LowerError(code, _, None) => code + " (no range)"
  }
}

///|
/// The range of the `LowerError` of a value, or `None` when it lowers or the error has no range.
fn lower_range(text : String, name : String) -> @ast.Range? {
  try {
    ignore(
      @lower.lower_value_definition(scope_of(text), function_named(text, name)),
    )
    None
  } catch {
    @lower.LowerError(_, _, range) => range
  }
}

///|
let lift_source : String = elm_module([
  "ident : a -> a\nident x =\n    x", "leading : Int -> Int -> Int\nleading a =\n    \\b -> b",
  "paren : Int -> Int -> Int\nparen a =\n    (\\x -> a)", "wild : Int -> Int -> Int\nwild _ y =\n    y",
  "mixed : Int -> ( Int, Int ) -> Int -> Int\nmixed z ( a, b ) w =\n    a", "type alias Handler =\n    Int -> Int",
  "handler : Handler\nhandler x =\n    x", "later : Int -> Handler\nlater a b =\n    a",
  "unannotated x y =\n    x", "parenPat : Int -> Int\nparenPat (x) =\n    x", "asPat : Int -> Int\nasPat (_ as x) =\n    x",
  "lambdaParen =\n    \\(x) -> x",
])

///|
test "inputs are lifted like morphir-elm and the rest stays as lambdas" {
  assert_eq(input_names(lift_source, "ident"), ["x"])
  assert_eq(body_text(lift_source, "ident"), "x")
  assert_eq(input_names(lift_source, "leading"), ["a", "b"])
  assert_eq(body_text(lift_source, "leading"), "b")
  assert_eq(input_names(lift_source, "paren"), ["a", "x"])
  assert_eq(body_text(lift_source, "paren"), "a")
  assert_eq(input_names(lift_source, "wild"), [])
  assert_eq(body_text(lift_source, "wild"), "(lambda _ (lambda y y))")
  assert_eq(input_names(lift_source, "mixed"), ["z"])
  assert_eq(
    body_text(lift_source, "mixed"),
    "(lambda (ptuple a b) (lambda w a))",
  )
  assert_eq(input_names(lift_source, "handler"), [])
  assert_eq(body_text(lift_source, "handler"), "(lambda x x)")
  assert_eq(input_names(lift_source, "later"), ["a"])
  assert_eq(body_text(lift_source, "later"), "(lambda b a)")
  // morphir-elm lifts by the lowered pattern: `(x)` and `_ as x` are variables.
  assert_eq(input_names(lift_source, "parenPat"), ["x"])
  assert_eq(body_text(lift_source, "parenPat"), "x")
  assert_eq(input_names(lift_source, "asPat"), ["x"])
  assert_eq(body_text(lift_source, "asPat"), "x")
  assert_eq(input_names(lift_source, "lambdaParen"), ["x"])
  assert_eq(body_text(lift_source, "lambdaParen"), "x")
}

///|
test "an unannotated value gets numbered placeholders" {
  guard definition_of(lift_source, "unannotated")
    is ExpressionBody(inputs, output, body) else {
    fail("unannotated")
  }
  let types = inputs.map(i => i.1)
  types.push(output)
  for i, t in types {
    guard t is Variable(attrs, name) else { fail("variable") }
    assert_true(attrs.is_unknown())
    assert_eq(name.to_canonical(), "t-" + i.to_string())
  }
  assert_eq(show(body), "x")
}

///|
let names_source : String = elm_module([
  "type Color\n    = Red\n    | Rgb Int Int Int", "top =\n    Red", "useTop =\n    top",
  "useRed =\n    Red", "useTrue =\n    True", "useSdk =\n    List.map", "useNothing =\n    Nothing",
  "useQualified =\n    Maybe.Just", "useUnit =\n    ()", "useParen x =\n    (x)",
])

///|
test "names lower to variables, references, constructors and literals" {
  assert_eq(body_text(names_source, "useTop"), "(ref my/pkg:m#top)")
  assert_eq(body_text(names_source, "useRed"), "(ctor my/pkg:m#red)")
  assert_eq(body_text(names_source, "useTrue"), "(bool true)")
  assert_eq(body_text(names_source, "useSdk"), "(ref morphir/SDK:list#map)")
  assert_eq(
    body_text(names_source, "useNothing"),
    "(ctor morphir/SDK:maybe#nothing)",
  )
  // Review focus 4, expression side.
  assert_eq(
    body_text(names_source, "useQualified"),
    "(ctor morphir/SDK:maybe#just)",
  )
  assert_eq(body_text(names_source, "useUnit"), "()")
  assert_eq(body_text(names_source, "useParen"), "x")
}

///|
let patterns_source : String = elm_module([
  "type Color\n    = Red\n    | Rgb Int Int Int", "top =\n    Red", "pTuple =\n    \\( a, _ ) -> a",
  "pUnit =\n    \\() -> top", "pCtor =\n    \\(Rgb r _ _) -> r", "pBare =\n    \\Red -> top",
  "pList =\n    \\[ a, b ] -> a", "pEmpty =\n    \\[] -> top", "pCons =\n    \\(x :: xs) -> xs",
  "pAsCtor =\n    \\((Just _) as j) -> j", "pAs =\n    \\(x as y) -> y", "pTrue =\n    \\True -> top",
  "pInt =\n    \\1 -> top", "pHex =\n    \\0x10 -> top", "pChar =\n    \\'a' -> top",
  "pString =\n    \\\"s\" -> top", "pQualified =\n    \\(Maybe.Just x) -> x", "pMany =\n    \\a b -> b",
  "pRecord =\n    \\{ x } -> x",
])

///|
test "patterns lower like morphir-elm" {
  let top = "(ref my/pkg:m#top)"
  assert_eq(body_text(patterns_source, "pTuple"), "(lambda (ptuple a _) a)")
  assert_eq(body_text(patterns_source, "pUnit"), "(lambda () \{top})")
  assert_eq(
    body_text(patterns_source, "pCtor"),
    "(lambda (pctor my/pkg:m#rgb r _ _) r)",
  )
  assert_eq(
    body_text(patterns_source, "pBare"),
    "(lambda (pctor my/pkg:m#red) \{top})",
  )
  assert_eq(
    body_text(patterns_source, "pList"),
    "(lambda (cons a (cons b [])) a)",
  )
  assert_eq(body_text(patterns_source, "pEmpty"), "(lambda [] \{top})")
  assert_eq(body_text(patterns_source, "pCons"), "(lambda (cons x xs) xs)")
  assert_eq(
    body_text(patterns_source, "pAsCtor"),
    "(lambda (as (pctor morphir/SDK:maybe#just _) j) j)",
  )
  assert_eq(body_text(patterns_source, "pAs"), "(lambda (as x y) y)")
  assert_eq(
    body_text(patterns_source, "pTrue"),
    "(lambda (plit (bool true)) \{top})",
  )
  assert_eq(
    body_text(patterns_source, "pInt"),
    "(lambda (plit (int 1)) \{top})",
  )
  assert_eq(
    body_text(patterns_source, "pHex"),
    "(lambda (plit (int 16)) \{top})",
  )
  assert_eq(
    body_text(patterns_source, "pChar"),
    "(lambda (plit (char a)) \{top})",
  )
  assert_eq(
    body_text(patterns_source, "pString"),
    "(lambda (plit (str s)) \{top})",
  )
  // Review focus 4, pattern side.
  assert_eq(
    body_text(patterns_source, "pQualified"),
    "(lambda (pctor morphir/SDK:maybe#just x) x)",
  )
  // An unannotated value lifts every leading variable, also from a lambda.
  assert_eq(input_names(patterns_source, "pMany"), ["a", "b"])
  assert_eq(body_text(patterns_source, "pMany"), "b")
  assert_eq(lower_code(patterns_source, "pRecord"), "elm.unsupported")
}
