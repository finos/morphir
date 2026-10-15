///|
/// The output modules of a project in package `My.Pkg` with the exposed module `A`, each as `path access`. A
/// module text without a `module` or `port module` header gets `module My.Pkg.<name> exposing (..)`.
fn selected(modules : Array[(String, String)]) -> Array[String] raise {
  let file = @frontend.compile_project(
    modules.map(m => {
      path: "My/Pkg/" + m.0 + ".elm",
      content: if m.1.has_prefix("module ") || m.1.has_prefix("port module ") {
        m.1
      } else {
        "module My.Pkg." + m.0 + " exposing (..)\n\n" + m.1
      },
    }),
    "My.Pkg",
    ["A"],
  )
  guard file.distribution is Library(_, _, def) else { fail("library") }
  let out = def.modules
    .iter()
    .map(entry => {
      let access = match entry.1.access {
        Public => "public"
        Private => "private"
      }
      entry.0.to_canonical() + " " + access
    })
    .collect()
  // `String::compare` puts shorter strings first; the lines are in code-unit order here.
  out.sort_by((a, b) => {
    let (x, y) = (a.to_array(), b.to_array())
    let shorter = if x.length() < y.length() { x.length() } else { y.length() }
    for i in 0..<shorter {
      if x[i] != y[i] {
        return x[i].compare(y[i])
      }
    }
    x.length().compare(y.length())
  })
  out
}

///|
test "a module that only a value signature names is dropped; a body reference keeps it private" {
  // The p5 probe of morphir-elm make 2.100.0.
  let modules = [
    (
      "A", "import My.Pkg.B\nimport My.Pkg.C\n\n\na : My.Pkg.B.T -> Int\na x =\n    My.Pkg.C.c\n",
    ),
    (
      "B", "import My.Pkg.D\n\n\ntype alias T =\n    My.Pkg.D.U\n\n\nb : Int\nb =\n    1\n",
    ),
    (
      "C", "import My.Pkg.E\nimport My.Pkg.F\n\n\nc : Int\nc =\n    My.Pkg.F.f\n\n\ng : My.Pkg.E.V -> Int\ng v =\n    1\n",
    ),
    ("D", "\ntype alias U =\n    Int\n"),
    ("E", "\ntype alias V =\n    Int\n"),
    ("F", "\nf : Int\nf =\n    2\n"),
  ]
  assert_eq(selected(modules), ["a public", "c private", "f private"])
}

///|
/// The p6 probe: type definitions keep modules; public types and public value signatures of an exposed module
/// make modules public; a constructor in a body does not keep a module; an SDK module path keeps the project
/// module with the same path.
fn p6(first : String, second : String) -> Array[(String, String)] {
  let leaf = fn(name : String) {
    (name, "\ntype alias " + name + "t =\n    Int\n")
  }
  [
    (
      "A",
      (
        $|module My.Pkg.A exposing (T, U(..), Opq, Rec, pub)
        $|
        $|import My.Pkg.Basics
        $|import My.Pkg.C
        $|import My.Pkg.K
        $|import My.Pkg.M
        $|import My.Pkg.O
        $|import My.Pkg.P
        $|
        $|
        $|type alias T =
        $|    My.Pkg.M.\{first}
        $|
        $|
        $|type alias Rec =
        $|    { x : My.Pkg.M.\{second} }
        $|
        $|
        $|type U
        $|    = U My.Pkg.K.Kt
        $|
        $|
        $|type Opq
        $|    = Opq My.Pkg.O.Ot
        $|
        $|
        $|pub : My.Pkg.P.Pt -> Int
        $|pub x =
        $|    1
        $|
        $|
        $|priv : My.Pkg.C.Ct
        $|priv =
        $|    My.Pkg.C.Mk 1
        $|
        $|
        $|bas : My.Pkg.Basics.Basicst -> Int
        $|bas b =
        $|    2
      ),
    ),
    (
      "M",
      "import My.Pkg.X\nimport My.Pkg.Y\n\n\ntype alias \{first} =\n    My.Pkg.X.Xt\n\n\ntype alias \{second} =\n    My.Pkg.Y.Yt\n",
    ),
    ("C", "\ntype Ct\n    = Mk Int\n"),
    leaf("Basics"),
    leaf("K"),
    leaf("O"),
    leaf("P"),
    leaf("X"),
    leaf("Y"),
  ]
}

///|
test "type references keep modules, and exposed public signatures make them public" {
  assert_eq(selected(p6("T1", "T2")), [
    "a public", "basics private", "k public", "m public", "o private", "x public",
    "y private",
  ])
}

///|
test "only the first referenced type of a module makes its references public, as in morphir-elm" {
  // morphir-elm visits the referenced types in name order and skips a type whose module is already public, so the
  // type `Aa` (before `T1`) decides that Y and not X is public.
  assert_eq(selected(p6("T1", "Aa")), [
    "a public", "basics private", "k public", "m public", "o private", "x private",
    "y public",
  ])
}

///|
test "names are checked in every imported module, also one that is not in the output" {
  // The p8 probe: morphir-elm fails on the unused import U, and does not read L, which nothing imports.
  let codes = fn(u : String) -> Array[String] {
    selected([
      ("A", "import My.Pkg.U\n\n\na : Int\na =\n    1\n"),
      ("U", "\nu : " + u + "\nu =\n    1\n"),
      ("L", "\nl : AlsoNope\nl =\n    1\n"),
    ]) catch {
      @frontend.ElmFailed(problems) => problems.map(p => p.code + " " + p.path)
      _ => ["other"]
    }
  }
  assert_eq(codes("Nope"), ["elm.unresolved_name My/Pkg/U.elm"])
  assert_eq(codes("Int"), ["a public"])
}

///|
/// The problem codes and paths of a project with the exposed module `A` and the extra modules, or the output.
fn outcome(extra : Array[(String, String)]) -> Array[String] {
  let modules = [("A", "\na : Int\na =\n    1\n")]
  modules.append(extra)
  selected_codes(modules)
}

///|
test "exposing lists, imports and declarations are checked only in imported modules" {
  // The q1 probe: morphir-elm ignores L, which nothing imports, with a bad exposing entry and a bad import.
  let l = "module My.Pkg.L exposing (l, zzz)\n\nimport Nope.Missing\n\n\nl : Int\nl =\n    1\n"
  assert_eq(outcome([("L", l)]), ["a public"])
  // The same module, imported by A, fails.
  let a = "module My.Pkg.A exposing (..)\n\nimport My.Pkg.L\n\n\na : Int\na =\n    1\n"
  assert_eq(selected_codes([("A", a), ("L", l)]), [
    "elm.unresolved_name My/Pkg/L.elm", "elm.unsupported_module My/Pkg/L.elm",
  ])
}

///|
test "module names and port modules are checked only in imported modules" {
  // Probes t-name, t-pkg and t-port: morphir-elm ignores these modules when nothing imports them.
  let wrong_name = "module My.Pkg.Other exposing (..)\n\n\nl : Int\nl =\n    1\n"
  let port = "port module My.Pkg.P exposing (..)\n\n\nport out : Int -> Cmd msg\n"
  assert_eq(outcome([("L", wrong_name), ("P", port)]), ["a public"])
  let a = "module My.Pkg.A exposing (..)\n\nimport My.Pkg.P\n\n\na : Int\na =\n    1\n"
  assert_eq(selected_codes([("A", a), ("P", port)]), [
    "elm.unsupported My/Pkg/P.elm",
  ])
}

///|
test "parse errors and import cycles fail in every module, also one that nothing imports" {
  // Probes t-parse and t-cycle: morphir-elm fails on both.
  assert_eq(outcome([("L", "\nl : Int\nl =\n    (\n")]), [
    "elm.parse My/Pkg/L.elm",
  ])
  let l = "module My.Pkg.L exposing (..)\n\nimport My.Pkg.M\n\n\nl : Int\nl =\n    My.Pkg.M.m\n"
  let m = "module My.Pkg.M exposing (..)\n\nimport My.Pkg.L\n\n\nm : Int\nm =\n    1\n"
  assert_eq(outcome([("L", l), ("M", m)]), ["elm.import_cycle My/Pkg/M.elm"])
}

///|
fn selected_codes(modules : Array[(String, String)]) -> Array[String] {
  selected(modules) catch {
    @frontend.ElmFailed(problems) => problems.map(p => p.code + " " + p.path)
    _ => ["other"]
  }
}
