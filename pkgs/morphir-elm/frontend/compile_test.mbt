///|
let types_elm = "module My.Pkg.Types exposing (Shape(..), Point, Opaque, area)\n\n{-| Types module doc.\n\n@docs area\n-}\n\nimport My.Pkg.Util as U exposing (Id)\nimport My.Pkg.Internal\n\n\n{-| A point. -}\ntype alias Point =\n    { x : Float, y : Float }\n\n\ntype Shape\n    = Circle Point Float\n\n\ntype Opaque\n    = Opaque Int\n\n\narea : Shape -> Float\narea s =\n    1.0\n\n\nhidden : Id -> Int\nhidden i =\n    U.one\n"

///|
let util_elm = "module My.Pkg.Util exposing (Id, one)\n\n\ntype alias Id =\n    String\n\n\none : Int\none =\n    1\n\n\nprivy : Int\nprivy =\n    8\n"

///|
let internal_elm = "module My.Pkg.Internal exposing (w)\n\n\nw : Int\nw =\n    3\n"

///|
let lonely_elm = "module My.Pkg.Lonely exposing (z)\n\n\nz : Int\nz =\n    2\n"

///|
fn compile() -> @ir.IRFile raise @frontend.ElmFailed {
  @frontend.compile_project(
    [
      { path: "My/Pkg/Types.elm", content: types_elm, },
      { path: "My/Pkg/Util.elm", content: util_elm, },
      { path: "My/Pkg/Internal.elm", content: internal_elm, },
      { path: "My/Pkg/Lonely.elm", content: lonely_elm, },
    ],
    "My.Pkg",
    ["Types"],
  )
}

///|
fn n(text : String) -> @ir.Name {
  @ir.Name::parse(text) catch {
    _ => panic()
  }
}

///|
fn p(text : String) -> @ir.Path {
  @ir.Path::parse(text) catch {
    _ => panic()
  }
}

///|
test "module selection, access and docs follow morphir-elm" {
  let file = compile()
  guard file.distribution is Library(pkg, deps, def) else { fail("library") }
  assert_eq(pkg, p("my/pkg"))
  assert_true(deps.is_empty())
  // Exposed Types and Util, which the body of `hidden` uses; imported-only Internal and unreferenced Lonely are
  // dropped. Util is Private: no public type or public value signature of Types names it.
  assert_eq(def.modules.keys().map(k => k.to_canonical()).collect(), [
    "types", "util",
  ])
  let types = def.modules[p("types")]
  assert_eq(types.access, Public)
  assert_eq(types.value.doc, Some(" Types module doc.\n\n@docs area"))
  let point = types.value.types[n("point")]
  assert_eq((point.access, point.value.doc), (Public, Some(" A point. ")))
  guard types.value.types[n("opaque")].value.value
    is CustomTypeDefinition(_, opaque_type) else {
    fail("opaque")
  }
  assert_eq(
    (types.value.types[n("opaque")].access, opaque_type.access),
    (Public, Private),
  )
  guard types.value.types[n("shape")].value.value
    is CustomTypeDefinition(_, shape) else {
    fail("shape")
  }
  assert_eq(shape.access, Public)
  assert_eq(types.value.values[n("area")].access, Public)
  assert_eq(types.value.values[n("hidden")].access, Private)
  assert_eq(types.value.values[n("hidden")].value.doc, Some(""))
  let util = def.modules[p("util")]
  assert_eq(util.access, Private)
  assert_eq(util.value.doc, None)
  assert_eq(util.value.values[n("privy")].access, Private)
}

///|
test "review focus 4: exposed modules must exist and must not be empty" {
  let code = fn(exposed : Array[String]) {
    try {
      ignore(
        @frontend.compile_project(
          [{ path: "My/Pkg/Util.elm", content: util_elm, }],
          "My.Pkg",
          exposed,
        ),
      )
      []
    } catch {
      @frontend.ElmFailed(problems) => problems.map(x => x.code)
    }
  }
  assert_eq(code([]), ["elm.exposed_module"])
  assert_eq(code(["Missing"]), ["elm.exposed_module"])
}

///|
test "problems of one pass are collected across modules" {
  let a = "module My.Pkg.A exposing (..)\n\nimport My.Pkg.B\n\n\na : Nope\na =\n    My.Pkg.B.b\n"
  let b = "module My.Pkg.B exposing (..)\n\n\nb : AlsoNope\nb =\n    1\n"
  let problems = try {
    ignore(
      @frontend.compile_project(
        [
          { path: "My/Pkg/A.elm", content: a, },
          { path: "My/Pkg/B.elm", content: b, },
        ],
        "My.Pkg",
        ["A"],
      ),
    )
    []
  } catch {
    @frontend.ElmFailed(problems) => problems.map(x => (x.code, x.path))
  }
  assert_eq(problems, [
    ("elm.unresolved_name", "My/Pkg/A.elm"),
    ("elm.unresolved_name", "My/Pkg/B.elm"),
  ])
}

///|
/// The module doc and the declaration docs of each module, by the module's last name segment.
fn docs_of(
  modules : Array[(String, String)],
) -> Map[String, (String?, Array[(String, String?)])] raise {
  let file = @frontend.compile_project(
    modules.map(m => { path: "My/Pkg/" + m.0 + ".elm", content: m.1, }),
    "My.Pkg",
    modules.map(m => m.0),
  )
  guard file.distribution is Library(_, _, def) else { fail("library") }
  let out = Map([])
  for path, m in def.modules {
    let decls = []
    for name, t in m.value.types {
      decls.push((name.to_canonical(), t.value.doc))
    }
    for name, v in m.value.values {
      decls.push((name.to_canonical(), v.value.doc))
    }
    out[path.to_canonical()] = (m.value.doc, decls)
  }
  out
}

///|
test "a doc comment belongs to a declaration only on the row right before it" {
  let docs = docs_of([
    // A: two blank lines after the doc: the doc is the module doc.
    (
      "A", "module My.Pkg.A exposing (..)\n\n{-| Mod. -}\n\n\nb : Int\nb =\n    1\n",
    ),
    // B: a module doc, then a doc on the row before `b`.
    (
      "B", "module My.Pkg.B exposing (..)\n\n{-| Mod. -}\n\n\n{-| Bdoc. -}\nb : Int\nb =\n    1\n",
    ),
    // D: imports, then a doc on the row before `b`: no module doc.
    (
      "D", "module My.Pkg.D exposing (..)\n\nimport Dict\n\n{-| Bdoc. -}\nb : Int\nb =\n    1\n",
    ),
    // E: the only doc is on the row before the first declaration: it is the declaration doc.
    ("E", "module My.Pkg.E exposing (..)\n\n{-| Mod. -}\nb : Int\nb =\n    1\n"),
    // F: one blank line after the doc: the doc is the module doc.
    (
      "F", "module My.Pkg.F exposing (..)\n\n{-| Mod. -}\n\nb : Int\nb =\n    1\n",
    ),
    // H: a doc between declarations with blank lines around it is the module doc.
    (
      "H", "module My.Pkg.H exposing (..)\n\nb : Int\nb =\n    1\n\n\n{-| Late. -}\n\n\nc : Int\nc =\n    1\n",
    ),
    // T: type declarations after imports: the adjacent doc belongs to `P`; the doc with a blank line after it
    // is the module doc, also when the `type` keyword and the name are on different rows.
    (
      "T", "module My.Pkg.T exposing (..)\n\nimport Dict\n\n{-| P doc -}\ntype alias P =\n    Int\n\n\n{-| Not Q -}\n\ntype\n    Q\n    = Q\n\n\n{-| R doc -}\ntype\n    R\n    = R\n",
    ),
  ])
  assert_eq(docs.get("a"), Some((Some(" Mod."), [("b", Some(""))])))
  assert_eq(docs.get("b"), Some((Some(" Mod."), [("b", Some(" Bdoc. "))])))
  assert_eq(docs.get("d"), Some((None, [("b", Some(" Bdoc. "))])))
  assert_eq(docs.get("e"), Some((None, [("b", Some(" Mod. "))])))
  assert_eq(docs.get("f"), Some((Some(" Mod."), [("b", Some(""))])))
  assert_eq(
    docs.get("h"),
    Some((Some(" Late."), [("b", Some("")), ("c", Some(""))])),
  )
  assert_eq(
    docs.get("t"),
    Some(
      (
        Some(" Not Q"),
        [("p", Some(" P doc ")), ("q", Some("")), ("r", Some(" R doc "))],
      ),
    ),
  )
}

///|
test "the module doc drops the last 3 characters of the comment, as morphir-elm does" {
  // Probes fx1 and fx2 (morphir-elm 2.100.0): morphir-elm drops the first 3 and the last 3 characters. A
  // declaration doc keeps the raw text between `{-|` and `-}`.
  let docs = docs_of([
    (
      "Tight", "module My.Pkg.Tight exposing (..)\n\n{-| Doc.-}\n\n\n{-| D.-}\nb : Int\nb =\n    1\n",
    ),
    (
      "Spaces", "module My.Pkg.Spaces exposing (..)\n\n{-| Doc.  -}\n\n\nb : Int\nb =\n    1\n",
    ),
    (
      "Blank", "module My.Pkg.Blank exposing (..)\n\n{-| Doc.\n\n-}\n\n\nb : Int\nb =\n    1\n",
    ),
    (
      "Crlf", "module My.Pkg.Crlf exposing (..)\r\n\r\n{-| Mod.\r\n-}\r\n\r\n\r\n{-| D.\r\n-}\r\nb : Int\r\nb =\r\n    1\r\n",
    ),
  ])
  assert_eq(docs.get("tight"), Some((Some(" Doc"), [("b", Some(" D."))])))
  assert_eq(docs.get("spaces"), Some((Some(" Doc. "), [("b", Some(""))])))
  assert_eq(docs.get("blank"), Some((Some(" Doc.\n"), [("b", Some(""))])))
  assert_eq(docs.get("crlf"), Some((Some(" Mod.\r"), [("b", Some(" D.\r\n"))])))
}

///|
test "compile_project lowers value bodies" {
  let file = @frontend.compile_project(
    [
      {
        path: "My/Pkg/A.elm",
        content: "module My.Pkg.A exposing (..)\n\n\ninc : Int -> Int\ninc x =\n    x + 1\n\n\nwild : Int -> Int -> Int\nwild _ y =\n    y\n",
      },
    ],
    "My.Pkg",
    ["A"],
  )
  guard file.distribution is Library(_, _, def) else { fail("library") }
  let values = def.modules[p("a")].value.values
  guard values[n("inc")].value.value
    is ExpressionBody(
      [(x, _)],
      _,
      Apply(
        _,
        Apply(_, Reference(_, add), Variable(_, v)),
        Literal(_, IntegerLiteral("1"))
      )
    ) else {
    fail("inc")
  }
  assert_eq((x.to_canonical(), v.to_canonical()), ("x", "x"))
  assert_eq(add.to_canonical(), "morphir/SDK:basics#add")
  guard values[n("wild")].value.value
    is ExpressionBody([], _, Lambda(_, WildcardPattern(_), _)) else {
    fail("wild")
  }
}

///|
/// morphir-elm refuses top-level mutual recursion (`ValueCycleDetected`). Elm accepts it, and so does the frontend.
test "top-level mutual recursion is accepted" {
  let file = @frontend.compile_project(
    [
      {
        path: "My/Pkg/A.elm",
        content: "module My.Pkg.A exposing (..)\n\n\nisEven : Int -> Bool\nisEven n =\n    if n == 0 then\n        True\n\n    else\n        isOdd (n - 1)\n\n\nisOdd : Int -> Bool\nisOdd n =\n    if n == 0 then\n        False\n\n    else\n        isEven (n - 1)\n",
      },
    ],
    "My.Pkg",
    ["A"],
  )
  guard file.distribution is Library(_, _, def) else { fail("library") }
  let values = def.modules[p("a")].value.values
  guard values[n("is-even")].value.value
    is ExpressionBody(_, _, IfThenElse(_, _, _, Apply(_, Reference(_, odd), _))) else {
    fail("isEven")
  }
  assert_eq(odd.to_canonical(), "my/pkg:a#is-odd")
  assert_true(values[n("is-odd")].value.value is ExpressionBody(_, _, _))
}
