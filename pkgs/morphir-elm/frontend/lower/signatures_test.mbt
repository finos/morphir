///|
let values_source = "module My.Pkg.M exposing (..)\n\ntup : ( Int, Int ) -> Int\ntup ( a, b ) =\n    a\n\nwild : Int -> Int\nwild _ =\n    1\n\npartial : Int -> Int -> Int\npartial a =\n    \\b -> a\n\n{-| Doc. -}\nunitF : () -> ()\nunitF u =\n    u\n\nplain x y =\n    x\n\nh : Int -> Int -> Int\nh a =\n    (\\x -> a)\n\ng : Int -> Int -> ( Int, Int ) -> Int\ng a =\n    \\x ( y, z ) -> a\n\nf : Int -> ( Int, Int ) -> Int\nf a (b, c) =\n    a\n"

///|
fn function_named(text : String, name : String) -> @ast.Function {
  for d in declarations(text) {
    if d.value is FunctionDeclaration(f) &&
      f.declaration.value.name.value == name {
      return f
    }
  }
  panic()
}

///|
/// The inputs and the output of a value definition, with the type attributes
/// stripped.
fn signature_of(
  text : String,
  name : String,
) -> (Array[(String, @ir.Type)], @ir.Type) {
  guard definition_of(text, name) is ExpressionBody(inputs, output, _) else {
    abort("not an expression body")
  }
  (inputs.map(i => (i.0.to_canonical(), bare(i.1))), bare(output))
}

///|
test "inputs follow morphir-elm: variables, then leading lambdas, stopping at a pattern" {
  let names = n => input_names(values_source, n)
  assert_eq(names("tup"), [])
  assert_eq(names("wild"), [])
  assert_eq(names("partial"), ["a", "b"])
  assert_eq(names("unitF"), ["u"])
  assert_eq(names("plain"), ["x", "y"])
  assert_eq(names("h"), ["a", "x"])
  assert_eq(names("g"), ["a", "x"])
  assert_eq(names("f"), ["a"])
}

///|
test "annotated signatures split the annotation by the inputs" {
  let (partial_inputs, partial_output) = signature_of(values_source, "partial")
  assert_eq(partial_inputs.map(i => i.0), ["a", "b"])
  assert_true(partial_output is Reference(_, _, []))
  let (tup_inputs, tup_output) = signature_of(values_source, "tup")
  assert_eq(tup_inputs.length(), 0)
  assert_true(tup_output is Function(_, Tuple(_, _), Reference(_, _, _)))
  let (h_inputs, h_output) = signature_of(values_source, "h")
  assert_eq(h_inputs.map(i => i.0), ["a", "x"])
  assert_true(h_output is Reference(_, _, []))
  let (g_inputs, g_output) = signature_of(values_source, "g")
  assert_eq(g_inputs.map(i => i.0), ["a", "x"])
  assert_true(g_output is Function(_, Tuple(_, _), Reference(_, _, _)))
  let (f_inputs, f_output) = signature_of(values_source, "f")
  assert_eq(f_inputs.map(i => i.0), ["a"])
  assert_true(f_output is Function(_, Tuple(_, _), Reference(_, _, _)))
  let (unit_inputs, unit_output) = signature_of(values_source, "unitF")
  assert_true(unit_inputs is [(_, Unit(_))])
  assert_true(unit_output is Unit(_))
}

///|
test "unannotated signatures get marked placeholders" {
  guard definition_of(values_source, "plain")
    is ExpressionBody(inputs, output, _) else {
    fail("plain")
  }
  let types = inputs.map(i => i.1)
  types.push(output)
  assert_eq(types.length(), 3)
  for i, t in types {
    guard t is Variable(attrs, name) else { fail("variable") }
    assert_true(attrs.is_unknown())
    assert_eq(name.to_canonical(), "t-" + i.to_string())
  }
}

///|
test "a record argument pattern is refused" {
  let text = "module My.Pkg.M exposing (..)\n\nr : { x : Int } -> Int\nr { x } =\n    x\n"
  assert_eq(lower_code(text, "r"), "elm.unsupported")
}

///|
/// Probe fx1 (morphir-elm 2.100.0): an input is taken only while the rest of
/// the annotation is a function type. A type alias of a function type stops the
/// inputs, also inside parentheses, and the alias is the output type.
let alias_source = "module My.Pkg.M exposing (..)\n\ntype alias Handler =\n    Int -> Int\n\nf : Handler\nf x =\n    x\n\ng : Handler\ng =\n    \\y -> y\n\nh : Int -> Handler\nh a b =\n    a\n\nk : (Int -> Int)\nk x =\n    x\n\np : ( Handler )\np x =\n    x\n\nz : Int\nz =\n    1\n\ns : Int\ns a =\n    a\n"

///|
test "inputs stop where the annotation is not a function type" {
  let names = n => input_names(alias_source, n)
  assert_eq(names("f"), [])
  assert_eq(names("g"), [])
  assert_eq(names("h"), ["a"])
  assert_eq(names("k"), ["x"])
  assert_eq(names("p"), [])
  assert_eq(names("z"), [])
  assert_eq(names("s"), [])
}

///|
test "a function type alias annotation is the output type" {
  let handler = fn(t : @ir.Type) {
    t is Reference(_, name, []) && name.to_canonical().has_suffix("handler")
  }
  for n in ["f", "g", "p"] {
    let (inputs, output) = signature_of(alias_source, n)
    assert_eq(inputs.length(), 0, msg=n)
    assert_true(handler(output), msg=n)
  }
  // h : Int -> Handler, h a b = a: one input, and the output is Handler.
  let (h_inputs, h_output) = signature_of(alias_source, "h")
  assert_eq(h_inputs.map(i => i.0), ["a"])
  assert_true(h_inputs[0].1 is Reference(_, _, []))
  assert_true(handler(h_output))
}

///|
test "a parenthesized function annotation is peeled, and a value has no inputs" {
  let (k_inputs, k_output) = signature_of(alias_source, "k")
  assert_true(k_inputs is [("x", Reference(_, _, []))])
  assert_true(k_output is Reference(_, _, []))
  for n in ["z", "s"] {
    let (inputs, output) = signature_of(alias_source, n)
    assert_eq(inputs.length(), 0, msg=n)
    assert_true(output is Reference(_, _, []), msg=n)
  }
}
