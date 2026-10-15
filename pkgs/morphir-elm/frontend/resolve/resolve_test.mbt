///|
fn parse(path : String, text : String) -> @resolve.ParsedModule {
  let result = @krueger.parse_module(@krueger.SourceText::new(text))
  guard result.ast is Some(file) else { panic() }
  let name = path
    .strip_suffix(".elm")
    .unwrap()
    .split("/")
    .map(s => s.to_owned())
    .collect()
  { name, path, file, }
}

///|
fn project(
  modules : Array[(String, String)],
) -> @resolve.Project raise @resolve.ResolveFailed {
  @resolve.Project::new(["My", "Pkg"], modules.map(m => parse(m.0, m.1)))
}

///|
fn fq(text : String) -> @ir.FQName {
  @ir.FQName::parse(text) catch {
    _ => panic()
  }
}

///|
fn no_locals(_ : String) -> Bool {
  false
}

///|
fn failure(f : () -> Unit raise) -> String {
  try {
    f()
    "ok"
  } catch {
    @resolve.ResolveError(code, _) => code
    @resolve.ResolveFailed(problems) => problems.map(p => p.code).join(",")
    _ => "other"
  }
}

///|
let types_module = "module My.Pkg.Types exposing (Shape(..), Point, Opaque, area)\n\nimport My.Pkg.Util as U exposing (Id)\n\ntype alias Point =\n    { x : Float, y : Float }\n\ntype Shape\n    = Circle Point Float\n\ntype Opaque\n    = Opaque Int\n\narea : Shape -> Float\narea s =\n    1.0\n\nhelper : Int\nhelper =\n    U.one\n"

///|
let util_module = "module My.Pkg.Util exposing (Id, one)\n\ntype alias Id =\n    String\n\none : Int\none =\n    1\n"

///|
test "types resolve to the project, to imports and to the SDK" {
  let p = project([
    ("My/Pkg/Types.elm", types_module),
    ("My/Pkg/Util.elm", util_module),
  ])
  let scope = p.scope(["My", "Pkg", "Types"])
  assert_eq(scope.resolve_type([], "Point"), fq("my/pkg:types#point"))
  assert_eq(scope.resolve_type([], "Id"), fq("my/pkg:util#id"))
  assert_eq(scope.resolve_type(["U"], "Id"), fq("my/pkg:util#id"))
  assert_eq(scope.resolve_type([], "Float"), fq("morphir/SDK:basics#float"))
  assert_eq(scope.resolve_type([], "Maybe"), fq("morphir/SDK:maybe#maybe"))
  assert_eq(
    failure(fn() raise { ignore(scope.resolve_type([], "Nope")) }),
    "elm.unresolved_name",
  )
}

///|
test "a qualifier must be an import or a default import" {
  let p = project([
    ("My/Pkg/Types.elm", types_module),
    ("My/Pkg/Util.elm", util_module),
  ])
  let scope = p.scope(["My", "Pkg", "Types"])
  assert_eq(
    failure(fn() raise { ignore(scope.resolve_type(["Dict"], "Dict")) }),
    "elm.unresolved_name",
  )
  assert_eq(
    scope.resolve_type(["Maybe"], "Maybe"),
    fq("morphir/SDK:maybe#maybe"),
  )
}

///|
test "values resolve to locals, the module, imports and the SDK" {
  let p = project([
    ("My/Pkg/Types.elm", types_module),
    ("My/Pkg/Util.elm", util_module),
  ])
  let scope = p.scope(["My", "Pkg", "Types"])
  assert_eq(
    scope.resolve_value([], "area", no_locals),
    Global(fq("my/pkg:types#area")),
  )
  assert_eq(
    scope.resolve_value([], "Circle", no_locals),
    Global(fq("my/pkg:types#circle")),
  )
  assert_eq(
    scope.resolve_value(["U"], "one", no_locals),
    Global(fq("my/pkg:util#one")),
  )
  assert_eq(
    scope.resolve_value(["List"], "map", no_locals),
    Global(fq("morphir/SDK:list#map")),
  )
  assert_eq(
    scope.resolve_value([], "Just", no_locals),
    Global(fq("morphir/SDK:maybe#just")),
  )
  assert_eq(
    scope.resolve_value([], "max", no_locals),
    Global(fq("morphir/SDK:basics#max")),
  )
  assert_eq(scope.resolve_operator("+"), fq("morphir/SDK:basics#add"))
  // Review focus 1: a local shadows a top-level and a default-imported name.
  assert_eq(scope.resolve_value([], "max", n => n == "max"), Local("max"))
  assert_eq(scope.resolve_value([], "area", n => n == "area"), Local("area"))
}

///|
test "unsupported names are reported by kind" {
  let p = project([
    ("My/Pkg/Types.elm", types_module),
    ("My/Pkg/Util.elm", util_module),
  ])
  let scope = p.scope(["My", "Pkg", "Types"])
  assert_eq(
    failure(fn() raise {
      ignore(scope.resolve_value(["Debug"], "log", no_locals))
    }),
    "elm.unsupported",
  )
  assert_eq(
    failure(fn() raise {
      ignore(scope.resolve_value(["List"], "foldl2", no_locals))
    }),
    "elm.unsupported_value",
  )
  assert_eq(
    failure(fn() raise { ignore(scope.resolve_value([], "nothing", no_locals)) }),
    "elm.unresolved_name",
  )
}

///|
test "an import of an unknown package module is unsupported" {
  assert_eq(
    failure(fn() raise {
      ignore(
        project([
          (
            "My/Pkg/A.elm", "module My.Pkg.A exposing (..)\n\nimport Html\n\na : Int\na =\n    1\n",
          ),
        ]),
      )
    }),
    "elm.unsupported_module",
  )
}

///|
test "Morphir.SDK modules resolve against the SDK specification" {
  let p = project([
    (
      "My/Pkg/A.elm", "module My.Pkg.A exposing (..)\n\nimport Morphir.SDK.LocalDate exposing (LocalDate)\n\nd : LocalDate -> LocalDate\nd x =\n    x\n",
    ),
  ])
  let scope = p.scope(["My", "Pkg", "A"])
  assert_eq(
    scope.resolve_type([], "LocalDate"),
    fq("morphir/SDK:local-date#local-date"),
  )
}

///|
test "review focus 2: an import clash is an error only where it is used" {
  let a = "module My.Pkg.A exposing (x)\n\nx : Int\nx =\n    1\n"
  let b = "module My.Pkg.B exposing (x)\n\nx : Int\nx =\n    2\n"
  let c = "module My.Pkg.C exposing (..)\n\nimport My.Pkg.A exposing (..)\nimport My.Pkg.B exposing (..)\n\ny : Int\ny =\n    3\n"
  let p = project([
    ("My/Pkg/A.elm", a),
    ("My/Pkg/B.elm", b),
    ("My/Pkg/C.elm", c),
  ])
  let scope = p.scope(["My", "Pkg", "C"])
  assert_eq(
    failure(fn() raise { ignore(scope.resolve_value([], "x", no_locals)) }),
    "elm.ambiguous_name",
  )
  assert_eq(
    scope.resolve_value(["My", "Pkg", "A"], "x", no_locals),
    Global(fq("my/pkg:a#x")),
  )
}

///|
test "review focus 3: an exposing entry without a declaration is unresolved" {
  assert_eq(
    failure(fn() raise {
      ignore(
        project([
          (
            "My/Pkg/A.elm", "module My.Pkg.A exposing (missing)\n\na : Int\na =\n    1\n",
          ),
        ]),
      )
    }),
    "elm.unresolved_name",
  )
}

///|
test "references are the project modules that a module uses by name" {
  let internal = "module My.Pkg.Internal exposing (w)\n\nw : Int\nw =\n    3\n"
  let types = "module My.Pkg.Types exposing (..)\n\nimport My.Pkg.Util as U exposing (Id)\nimport My.Pkg.Internal\n\nf : Id -> Int\nf max =\n    U.one\n"
  let p = project([
    ("My/Pkg/Types.elm", types),
    ("My/Pkg/Util.elm", util_module),
    ("My/Pkg/Internal.elm", internal),
  ])
  // Internal is imported but not used, so it is not a reference. `max` is a local.
  assert_eq(p.references(["My", "Pkg", "Types"]), [["My", "Pkg", "Util"]])
}

///|
test "collect_references returns the found modules and the problems" {
  let a = "module My.Pkg.A exposing (..)\n\nimport My.Pkg.B\n\na : Nope\na =\n    My.Pkg.B.b\n"
  let b = "module My.Pkg.B exposing (b)\n\nb : Int\nb =\n    1\n"
  let p = project([("My/Pkg/A.elm", a), ("My/Pkg/B.elm", b)])
  let (found, problems) = p.collect_references(["My", "Pkg", "A"])
  assert_eq(found, [["My", "Pkg", "B"]])
  assert_eq(problems.map(p => p.code), ["elm.unresolved_name"])
  assert_eq(problems.map(p => p.path), ["My/Pkg/A.elm"])
  assert_eq(
    failure(fn() raise { ignore(p.references(["My", "Pkg", "A"])) }),
    "elm.unresolved_name",
  )
}

///|
test "a qualifier is the import alias, otherwise the full module name, as in Elm" {
  let list_extra = "module My.Pkg.ListExtra exposing (helper)\n\nhelper : Int\nhelper =\n    1\n"
  let a = "module My.Pkg.A exposing (..)\n\nimport My.Pkg.ListExtra as List\nimport My.Pkg.Util as U\n\na : Int\na =\n    1\n"
  let p = project([
    ("My/Pkg/A.elm", a),
    ("My/Pkg/ListExtra.elm", list_extra),
    ("My/Pkg/Util.elm", util_module),
  ])
  let scope = p.scope(["My", "Pkg", "A"])
  // `List` is the alias of ListExtra and the name of the default import List: both take part.
  assert_eq(
    scope.resolve_value(["List"], "map", no_locals),
    Global(fq("morphir/SDK:list#map")),
  )
  assert_eq(
    scope.resolve_value(["List"], "helper", no_locals),
    Global(fq("my/pkg:list-extra#helper")),
  )
  // An import with an alias is not reachable by its full module name.
  assert_eq(
    scope.resolve_value(["U"], "one", no_locals),
    Global(fq("my/pkg:util#one")),
  )
  assert_eq(
    failure(fn() raise {
      ignore(scope.resolve_value(["My", "Pkg", "Util"], "one", no_locals))
    }),
    "elm.unresolved_name",
  )
}

///|
test "two imports with the same alias that both have the name are ambiguous" {
  let a = "module My.Pkg.A exposing (x)\n\nx : Int\nx =\n    1\n"
  let b = "module My.Pkg.B exposing (x)\n\nx : Int\nx =\n    2\n"
  let c = "module My.Pkg.C exposing (..)\n\nimport My.Pkg.A as X\nimport My.Pkg.B as X\n\ny : Int\ny =\n    3\n"
  let p = project([
    ("My/Pkg/A.elm", a),
    ("My/Pkg/B.elm", b),
    ("My/Pkg/C.elm", c),
  ])
  let scope = p.scope(["My", "Pkg", "C"])
  assert_eq(
    failure(fn() raise { ignore(scope.resolve_value(["X"], "x", no_locals)) }),
    "elm.ambiguous_name",
  )
}

///|
test "review focus 1: locals in bodies shadow imported names in references" {
  let locals = "module My.Pkg.L exposing (..)\n\nimport My.Pkg.Util exposing (one)\n\nlam : Int -> Int\nlam x =\n    (\\one -> one) x\n\nlets : Int\nlets =\n    let\n        one =\n            2\n    in\n    one\n\ncases : Maybe Int -> Int\ncases m =\n    case m of\n        Just one ->\n            one\n\n        Nothing ->\n            0\n\nupd : { x : Int } -> { x : Int }\nupd r =\n    { r | x = 1 }\n"
  let p = project([("My/Pkg/L.elm", locals), ("My/Pkg/Util.elm", util_module)])
  assert_eq(p.references(["My", "Pkg", "L"]), [])
  // Control: the same module with one use of the imported `one` references Util.
  let used = locals + "\ntop : Int\ntop =\n    one\n"
  let q = project([("My/Pkg/L.elm", used), ("My/Pkg/Util.elm", util_module)])
  assert_eq(q.references(["My", "Pkg", "L"]), [["My", "Pkg", "Util"]])
}

///|
test "True and False are Bool literals from Basics" {
  let a = "module My.Pkg.A exposing (..)\n\nimport Basics as B\n\na : Int\na =\n    1\n"
  let p = project([("My/Pkg/A.elm", a)])
  let scope = p.scope(["My", "Pkg", "A"])
  assert_eq(scope.resolve_value([], "True", no_locals), BoolLiteral(true))
  assert_eq(
    scope.resolve_value(["Basics"], "False", no_locals),
    BoolLiteral(false),
  )
  assert_eq(scope.resolve_value(["B"], "True", no_locals), BoolLiteral(true))
  // A project constructor named True comes first by the normal order.
  let own = "module My.Pkg.M exposing (..)\n\ntype Answer\n    = True\n    | No\n"
  let q = project([("My/Pkg/M.elm", own)])
  assert_eq(
    q.scope(["My", "Pkg", "M"]).resolve_value([], "True", no_locals),
    Global(fq("my/pkg:m#true")),
  )
}

///|
test "references of a body with Bool literals has no problems" {
  let a = "module My.Pkg.A exposing (..)\n\nf : Bool -> Int\nf b =\n    if True then\n        1\n\n    else\n        case b of\n            False ->\n                2\n\n            True ->\n                3\n"
  let p = project([("My/Pkg/A.elm", a)])
  let (found, problems) = p.collect_references(["My", "Pkg", "A"])
  assert_eq(found, [])
  assert_eq(problems, [])
}

///|
test "body values are the names that morphir-elm lowers to a value Reference in a body" {
  let c = "module My.Pkg.C exposing (..)\n\ntype Ct\n    = Mk Int\n"
  // The signature names Util and C, the body uses the constructor Mk, `|>` and the literal -1: none of them is a
  // value reference. `+`, `U.one`, the negation of `x` and `identity` are.
  let a = "module My.Pkg.A exposing (..)\n\nimport My.Pkg.C\nimport My.Pkg.Util as U exposing (Id)\n\nf : Id -> Int -> My.Pkg.C.Ct\nf s x =\n    My.Pkg.C.Mk (U.one + -x + -1) |> identity\n\ng : Int\ng =\n    let\n        h : My.Pkg.C.Ct -> Int\n        h y =\n            1\n    in\n    h (My.Pkg.C.Mk 2)\n"
  let p = project([
    ("My/Pkg/A.elm", a),
    ("My/Pkg/C.elm", c),
    ("My/Pkg/Util.elm", util_module),
  ])
  let found = p.module_references(["My", "Pkg", "A"])
  assert_eq(found.problems, [])
  assert_eq(found.modules, [["My", "Pkg", "Util"], ["My", "Pkg", "C"]])
  assert_eq(found.values, [
    fq("morphir/SDK:basics#add"),
    fq("my/pkg:util#one"),
    fq("morphir/SDK:basics#negate"),
    fq("morphir/SDK:basics#identity"),
  ])
}

///|
test "with_problems gives the problems of each module, and new raises them all" {
  let a = "module My.Pkg.A exposing (a)\n\na : Int\na =\n    1\n"
  let l = "module My.Pkg.L exposing (l, zzz)\n\nimport Nope.Missing\n\nl : Int\nl =\n    1\n"
  let modules = [parse("My/Pkg/A.elm", a), parse("My/Pkg/L.elm", l)]
  let (_, by_module) = @resolve.Project::with_problems(["My", "Pkg"], modules)
  assert_eq(by_module.get("My.Pkg.A").map(ps => ps.length()), Some(0))
  assert_eq(
    by_module.get("My.Pkg.L").map(ps => ps.map(p => p.code)),
    Some(["elm.unresolved_name", "elm.unsupported_module"]),
  )
  assert_eq(
    failure(fn() raise { ignore(@resolve.Project::new(["My", "Pkg"], modules)) }),
    "elm.unresolved_name,elm.unsupported_module",
  )
}

///|
test "Debug and Platform names and an exposed operator are unsupported" {
  let p = project([
    ("My/Pkg/Types.elm", types_module),
    ("My/Pkg/Util.elm", util_module),
  ])
  let scope = p.scope(["My", "Pkg", "Types"])
  let unsupported = [
    fn() raise { ignore(scope.resolve_value(["Debug"], "todo", no_locals)) },
    fn() raise { ignore(scope.resolve_type([], "Program")) },
    fn() raise { ignore(scope.resolve_type([], "Cmd")) },
    fn() raise { ignore(scope.resolve_type(["Sub"], "Sub")) },
    fn() raise { ignore(scope.resolve_value(["Cmd"], "none", no_locals)) },
  ]
  for i, f in unsupported {
    assert_eq(failure(f), "elm.unsupported", msg=i.to_string())
  }
  assert_eq(
    failure(fn() raise {
      ignore(
        project([
          (
            "My/Pkg/A.elm", "module My.Pkg.A exposing ((+), a)\n\na : Int\na =\n    1\n",
          ),
        ]),
      )
    }),
    "elm.unsupported",
  )
}
