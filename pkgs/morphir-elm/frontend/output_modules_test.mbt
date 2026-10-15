///|
/// `Api` names `Sig` only in a value signature and `Ctor` only as a constructor in a body; `Sig` names `Deep` in a
/// type alias. `Body` is reached through a value reference. morphir-elm keeps only `Api` and `Body`.
let output_sources : Array[@frontend.ElmSource] = [
  {
    path: "My/Pkg/Api.elm",
    content: "module My.Pkg.Api exposing (blank, total)\n\nimport My.Pkg.Body as Body\nimport My.Pkg.Ctor\nimport My.Pkg.Sig exposing (Amount)\nimport My.Pkg.Unused\n\n\nblank : Amount -> Bool\nblank a =\n    a == \"\"\n\n\ntotal : Int\ntotal =\n    Body.size (My.Pkg.Ctor.Box 1)\n",
  },
  {
    path: "My/Pkg/Body.elm",
    content: "module My.Pkg.Body exposing (size)\n\nimport My.Pkg.Ctor exposing (Box(..))\n\n\nsize : Box -> Int\nsize b =\n    case b of\n        Box n ->\n            n\n",
  },
  {
    path: "My/Pkg/Ctor.elm",
    content: "module My.Pkg.Ctor exposing (Box(..))\n\n\ntype Box\n    = Box Int\n",
  },
  {
    path: "My/Pkg/Sig.elm",
    content: "module My.Pkg.Sig exposing (Amount)\n\nimport My.Pkg.Deep exposing (Money)\n\n\ntype alias Amount =\n    Money\n",
  },
  {
    path: "My/Pkg/Deep.elm",
    content: "module My.Pkg.Deep exposing (Money)\n\n\ntype alias Money =\n    String\n",
  },
  {
    path: "My/Pkg/Unused.elm",
    content: "module My.Pkg.Unused exposing (unused)\n\n\nunused : Int\nunused =\n    4\n",
  },
  {
    path: "My/Pkg/Lonely.elm",
    content: "module My.Pkg.Lonely exposing (lonely)\n\n\nlonely : Int\nlonely =\n    5\n",
  },
]

///|
/// The output modules, sorted, with their access. `String::compare` orders by length first, then by character.
fn output_modules(
  output : @frontend.OutputModules,
) -> Array[(String, @ir.Access)] raise {
  let file = @frontend.compile_project(
    output_sources,
    "My.Pkg",
    ["Api"],
    output~,
  )
  guard file.distribution is Library(_, _, def) else { fail("library") }
  let out = def.modules.to_array().map(m => (m.0.to_canonical(), m.1.access))
  out.sort_by((a, b) => a.0.compare(b.0))
  out
}

///|
test "Parity keeps the morphir-elm selection" {
  assert_eq(output_modules(Parity), [("api", Public), ("body", Private)])
}

///|
test "Referenced also keeps the modules that the output names, transitively" {
  // `Sig` is Public: the exposed module shows `Amount` in a public signature. Imported-only `Unused` and
  // unimported `Lonely` stay out.
  assert_eq(output_modules(Referenced), [
    ("api", Public),
    ("sig", Public),
    ("body", Private),
    ("ctor", Private),
    ("deep", Private),
  ])
}

///|
test "Parity is the default" {
  let file = @frontend.compile_project(output_sources, "My.Pkg", ["Api"])
  guard file.distribution is Library(_, _, def) else { fail("library") }
  assert_eq(def.modules.length(), 2)
}
