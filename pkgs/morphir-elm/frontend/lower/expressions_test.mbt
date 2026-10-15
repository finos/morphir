///|
fn basics(name : String) -> String {
  "(ref morphir/SDK:basics#" + name + ")"
}

///|
let expressions_source : String = elm_module([
  "type alias Point =\n    { x : Int, y : Int }", "origin =\n    { x = 0, y = 0 }",
  "lits =\n    ( 1, 0xFF, 1.5 )", "negs x =\n    [ -1, -2.5, -x, -(1) ]", "strs =\n    ( \"\\u{0041}\\t\", '\\u{1F600}', 'a' )",
  "arith a b c =\n    a + b * c", "chain a b =\n    a - b - 1", "conses =\n    1 :: 2 :: []",
  "appends =\n    \"a\" ++ \"b\"", "pipes a =\n    a |> negate |> abs", "backPipes a =\n    negate <| abs <| a",
  "compose f g =\n    f >> g", "prefix =\n    (+)", "partialOp =\n    (+) 1", "power x =\n    -x ^ 2",
  "apply f a b =\n    f a b", "ifs c a b =\n    if c then\n        a\n\n    else if a then\n        b\n\n    else\n        c",
  // Elm and krueger accept tuples of two or three items only.
   "unitTupleList a b =\n    ( (), ( a, b ), ( [ a, b ], [] ) )", "records p =\n    ( { y = 2, x = 1 }, p.x, .x )",
  "updateLocal p =\n    { p | x = 1 }", "updateTop =\n    { origin | x = 1 }", "point =\n    Point 1 2",
  "just =\n    Maybe.Just 1", "cases m =\n    case m of\n        Just v ->\n            v\n\n        Nothing ->\n            0",
  "unknownOp a b =\n    a </> b",
])

///|
test "literals and negation follow morphir-elm" {
  assert_eq(
    body_text(expressions_source, "lits"),
    "(tuple (int 1) (int 255) (float 1.5))",
  )
  assert_eq(input_names(expressions_source, "negs"), ["x"])
  assert_eq(
    body_text(expressions_source, "negs"),
    "(list (int -1) (float -2.5) (apply (ref morphir/SDK:basics#negate) x) (apply (ref morphir/SDK:basics#negate) (int 1)))",
  )
  // Review focus 3.
  assert_eq(
    body_text(expressions_source, "strs"),
    "(tuple (str A\t) (char 😀) (char a))",
  )
}

///|
test "operators follow morphir-elm's table and pipes become applications" {
  let add = basics("add")
  let multiply = basics("multiply")
  let subtract = basics("subtract")
  let negate = basics("negate")
  let abs = basics("abs")
  let cons = "(ref morphir/SDK:list#cons)"
  assert_eq(
    body_text(expressions_source, "arith"),
    "(apply (apply " + add + " a) (apply (apply " + multiply + " b) c))",
  )
  assert_eq(
    body_text(expressions_source, "chain"),
    "(apply (apply " +
    subtract +
    " (apply (apply " +
    subtract +
    " a) b)) (int 1))",
  )
  assert_eq(
    body_text(expressions_source, "conses"),
    "(apply (apply " +
    cons +
    " (int 1)) (apply (apply " +
    cons +
    " (int 2)) (list)))",
  )
  assert_eq(
    body_text(expressions_source, "appends"),
    "(apply (apply " + basics("append") + " (str a)) (str b))",
  )
  assert_eq(
    body_text(expressions_source, "pipes"),
    "(apply " + abs + " (apply " + negate + " a))",
  )
  assert_eq(
    body_text(expressions_source, "backPipes"),
    "(apply " + negate + " (apply " + abs + " a))",
  )
  assert_eq(
    body_text(expressions_source, "compose"),
    "(apply (apply " + basics("compose-right") + " f) g)",
  )
  assert_eq(body_text(expressions_source, "prefix"), add)
  assert_eq(
    body_text(expressions_source, "partialOp"),
    "(apply " + add + " (int 1))",
  )
  assert_eq(
    body_text(expressions_source, "power"),
    "(apply (apply " + basics("power") + " (apply " + negate + " x)) (int 2))",
  )
  assert_eq(body_text(expressions_source, "apply"), "(apply (apply f a) b)")
  // Review focus 1: the error is at the range of the operator application `a </> b`, not of `</>` only.
  assert_eq(
    lower_code(expressions_source, "unknownOp"),
    "elm.unsupported_value",
  )
  let row = expressions_source
    .split("\n")
    .to_array()
    .search("    a </> b")
    .unwrap() +
    1
  assert_eq(
    lower_range(expressions_source, "unknownOp"),
    Some({ start: { row, column: 5, }, end: { row, column: 12, }, }),
  )
}

///|
test "if, tuples, lists, records and case follow morphir-elm" {
  assert_eq(body_text(expressions_source, "ifs"), "(if c a (if a b c))")
  assert_eq(
    body_text(expressions_source, "unitTupleList"),
    "(tuple () (tuple a b) (tuple (list a b) (list)))",
  )
  assert_eq(
    body_text(expressions_source, "records"),
    "(tuple (record (x (int 1)) (y (int 2))) (field p x) (field-fn x))",
  )
  assert_eq(
    body_text(expressions_source, "updateLocal"),
    "(update p (x (int 1)))",
  )
  assert_eq(
    body_text(expressions_source, "updateTop"),
    "(update (ref my/pkg:m#origin) (x (int 1)))",
  )
  assert_eq(
    body_text(expressions_source, "point"),
    "(apply (apply (ctor my/pkg:m#point) (int 1)) (int 2))",
  )
  assert_eq(
    body_text(expressions_source, "just"),
    "(apply (ctor morphir/SDK:maybe#just) (int 1))",
  )
  assert_eq(
    body_text(expressions_source, "cases"),
    "(case m ((pctor morphir/SDK:maybe#just v) v) ((pctor morphir/SDK:maybe#nothing) (int 0)))",
  )
}
