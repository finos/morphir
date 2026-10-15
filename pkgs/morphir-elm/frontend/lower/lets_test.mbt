///|
let lets_source : String = elm_module([
  "inOrder =\n    let\n        a =\n            1\n\n        b =\n            2\n    in\n    a",
  "reordered =\n    let\n        a =\n            b\n\n        b =\n            1\n\n        c =\n            2\n    in\n    c",
  "function =\n    let\n        f x =\n            x\n    in\n    f 1", "annotated =\n    let\n        g : Int -> Int\n        g x =\n            x\n    in\n    g 1",
  "destructure t =\n    let\n        ( a, b ) =\n            t\n    in\n    a", "mutual =\n    let\n        p =\n            q 1\n\n        q k =\n            r k\n\n        r k =\n            q k\n\n        s =\n            p\n    in\n    s",
  "selfRecursive =\n    let\n        loop n =\n            loop n\n    in\n    loop 1",
  "recursiveDestructure =\n    let\n        ( a, b ) =\n            ( b, a )\n    in\n    a",
])

///|
test "let blocks follow morphir-elm's dependency order" {
  assert_eq(
    body_text(lets_source, "inOrder"),
    "(let a (int 1) (let b (int 2) a))",
  )
  assert_eq(
    body_text(lets_source, "reordered"),
    "(let b (int 1) (let a b (let c (int 2) c)))",
  )
  assert_eq(
    body_text(lets_source, "function"),
    "(let f (lambda x x) (apply f (int 1)))",
  )
  assert_eq(
    body_text(lets_source, "destructure"),
    "(destructure (ptuple a b) t a)",
  )
  assert_eq(
    body_text(lets_source, "mutual"),
    "(letrec (q (lambda k (apply r k))) (r (lambda k (apply q k))) (let p (apply q (int 1)) (let s p s)))",
  )
  assert_eq(
    body_text(lets_source, "selfRecursive"),
    "(letrec (loop (lambda n (apply loop n))) (apply loop (int 1)))",
  )
  assert_eq(lower_code(lets_source, "recursiveDestructure"), "elm.unsupported")
}

///|
test "let definitions are never lifted and get placeholders or their annotation" {
  guard definition_of(lets_source, "function")
    is ExpressionBody(
      [],
      Variable(top, top_name),
      LetDefinition(_, _, ExpressionBody([], Variable(attrs, name), _), _)
    ) else {
    fail("function")
  }
  assert_true(top.is_unknown() && attrs.is_unknown())
  assert_eq(top_name.to_canonical(), "t-0")
  assert_eq(name.to_canonical(), "t-1")
  guard definition_of(lets_source, "annotated")
    is ExpressionBody(
      _,
      _,
      LetDefinition(
        _,
        _,
        ExpressionBody([], Function(_, Reference(_, int, []), _), _),
        _
      )
    ) else {
    fail("annotated")
  }
  assert_eq(int.to_canonical(), "morphir/SDK:basics#int")
}

///|
test "a name in a lambda body is a dependency" {
  // morphir-elm make 2.100.0 puts `b` outside `a`.
  let source = elm_module([
    "lambdaBody =\n    let\n        a =\n            \\c -> c + b\n\n        b =\n            1\n    in\n    a 2",
  ])
  assert_eq(
    body_text(source, "lambdaBody"),
    "(let b (int 1) (let a (lambda c (apply (apply (ref morphir/SDK:basics#add) c) b)) (apply a (int 2))))",
  )
}
