///|
fn src(path : String, content : String) -> @frontend.ElmSource {
  { path, content, }
}

///|
fn codes(f : () -> Unit raise @frontend.ElmFailed) -> Array[(String, String)] {
  try {
    f()
    []
  } catch {
    @frontend.ElmFailed(problems) => problems.map(p => (p.code, p.path))
  }
}

///|
test "modules parse and get their names" {
  let modules = @frontend.parse_modules(
    [
      src(
        "My/Pkg/A.elm", "module My.Pkg.A exposing (a)\n\na : Int\na =\n    1\n",
      ),
      src(
        "My/Pkg/B/C.elm", "module My.Pkg.B.C exposing (..)\n\nimport My.Pkg.A\n\nc =\n    My.Pkg.A.a\n",
      ),
    ],
    "My.Pkg",
  )
  assert_eq(modules.map(m => m.name), [
    ["My", "Pkg", "A"],
    ["My", "Pkg", "B", "C"],
  ])
  assert_eq(
    @frontend.module_path(["My", "Pkg", "B", "C"], ["My", "Pkg"]).to_canonical(),
    @ir.Path::parse("b/c").to_canonical(),
  )
}

///|
test "every parse error of every file is reported" {
  let found = codes(() => {
    ignore(
      @frontend.parse_modules(
        [
          src("My/Pkg/A.elm", "module My.Pkg.A exposing (a)\n\na =\n    (\n"),
          src("My/Pkg/B.elm", "modul My.Pkg.B\n"),
        ],
        "My.Pkg",
      ),
    )
  })
  assert_true(found.contains(("elm.parse", "My/Pkg/A.elm")))
  assert_true(found.contains(("elm.parse", "My/Pkg/B.elm")))
}

///|
test "module name must match its path and start with the package" {
  assert_eq(
    codes(() => {
      ignore(
        @frontend.parse_modules(
          [
            src(
              "My/Pkg/A.elm", "module My.Pkg.Other exposing (..)\n\nx : Int\nx =\n    1\n",
            ),
          ],
          "My.Pkg",
        ),
      )
    }),
    [("elm.module_name", "My/Pkg/A.elm")],
  )
  assert_eq(
    codes(() => {
      ignore(
        @frontend.parse_modules(
          [
            src(
              "Other/A.elm", "module Other.A exposing (..)\n\nx : Int\nx =\n    1\n",
            ),
          ],
          "My.Pkg",
        ),
      )
    }),
    [("elm.module_name", "Other/A.elm")],
  )
  // The package itself is not a module: a module needs one segment after the package name.
  assert_eq(
    codes(() => {
      ignore(
        @frontend.parse_modules(
          [
            src(
              "My/Pkg.elm", "module My.Pkg exposing (..)\n\nx : Int\nx =\n    1\n",
            ),
          ],
          "My.Pkg",
        ),
      )
    }),
    [("elm.module_name", "My/Pkg.elm")],
  )
}

///|
test "ports, effect modules and import cycles are refused" {
  let port = codes(() => {
    ignore(
      @frontend.parse_modules(
        [
          src(
            "My/Pkg/P.elm", "port module My.Pkg.P exposing (..)\n\nx : Int\nx =\n    1\n",
          ),
        ],
        "My.Pkg",
      ),
    )
  })
  assert_true(port.length() > 0)
  assert_true(port.all(p => p.0 == "elm.parse" || p.0 == "elm.unsupported"))
  assert_eq(
    codes(() => {
      ignore(
        @frontend.parse_modules(
          [
            src(
              "My/Pkg/A.elm", "module My.Pkg.A exposing (..)\n\nimport My.Pkg.B\n\na : Int\na =\n    1\n",
            ),
            src(
              "My/Pkg/B.elm", "module My.Pkg.B exposing (..)\n\nimport My.Pkg.A\n\nb : Int\nb =\n    1\n",
            ),
          ],
          "My.Pkg",
        ),
      )
    }),
    [("elm.import_cycle", "My/Pkg/B.elm")],
  )
}

///|
test "an import cycle is reported at the import that closes it" {
  let a = "module My.Pkg.A exposing (..)\n\nimport My.Pkg.B\n\na : Int\na =\n    1\n"
  let b = "module My.Pkg.B exposing (..)\n\nimport Dict\nimport My.Pkg.A\n\nb : Int\nb =\n    1\n"
  let failed = try {
    ignore(
      @frontend.parse_modules(
        [src("My/Pkg/A.elm", a), src("My/Pkg/B.elm", b)],
        "My.Pkg",
      ),
    )
    []
  } catch {
    @frontend.ElmFailed(problems) => problems
  }
  assert_eq(failed, [
    {
      code: "elm.import_cycle",
      message: "the imports form a cycle: My.Pkg.B -> My.Pkg.A -> My.Pkg.B",
      path: "My/Pkg/B.elm",
      location: Some({
        start_line: 4,
        start_column: 1,
        end_line: 4,
        end_column: 16,
      }),
    },
  ])
  // A module that imports itself.
  let s = "module My.Pkg.S exposing (..)\n\nimport My.Pkg.S\n\ns : Int\ns =\n    1\n"
  let self_cycle = try {
    ignore(@frontend.parse_modules([src("My/Pkg/S.elm", s)], "My.Pkg"))
    []
  } catch {
    @frontend.ElmFailed(problems) => problems.map(p => (p.message, p.location))
  }
  assert_eq(self_cycle, [
    (
      "the imports form a cycle: My.Pkg.S -> My.Pkg.S",
      Some({ start_line: 3, start_column: 1, end_line: 3, end_column: 16, }),
    ),
  ])
}

///|
test "source locations are one-based and end-exclusive like krueger" {
  let loc = @frontend.location_of({
    start: { row: 3, column: 1, },
    end: { row: 3, column: 16, },
  })
  assert_eq(loc, {
    start_line: 3,
    start_column: 1,
    end_line: 3,
    end_column: 16,
  })
}
