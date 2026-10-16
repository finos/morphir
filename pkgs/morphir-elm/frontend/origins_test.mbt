///|
let origins_api : String = "module My.Pkg.Api exposing (isEligible, swap)\n\nimport My.Pkg.Util as U\n\n\nisEligible : Bool -> Bool -> Bool\nisEligible active vip =\n    active && not vip && U.one\n\n\nswap : (Bool, Bool) -> Bool\nswap (a, b) =\n    b\n"

///|
let origins_util : String = "module My.Pkg.Util exposing (one)\n\n\none : Bool\none =\n    True\n"

///|
let origins_lonely : String = "module My.Pkg.Lonely exposing (two)\n\n\ntwo : Bool\ntwo =\n    False\n"

///|
fn origins_sources() -> Array[@frontend.ElmSource] {
  [
    { path: "My/Pkg/Api.elm", content: origins_api, },
    { path: "My/Pkg/Util.elm", content: origins_util, },
    { path: "My/Pkg/Lonely.elm", content: origins_lonely, },
  ]
}

///|
/// Compiles the origins project, failing with the Elm problems when the frontend refuses it.
fn compile_origins() -> @frontend.ProjectOutput raise {
  @frontend.compile_project_output(
    origins_sources(),
    "My.Pkg",
    ["Api"],
    output=Referenced,
  ) catch {
    @frontend.ElmFailed(problems) =>
      fail(
        problems
        .map(p => p.code + " at " + p.path + ": " + p.message)
        .join("\n"),
      )
  }
}

///|
test "compile_project_output records the origin of each value declaration the output keeps" {
  let output = compile_origins()
  // `IRFile`, `SourceLocation` and `DeclarationOrigin` derive Eq and Debug, which `to_equal` needs.
  let plain = @frontend.compile_project(
    origins_sources(),
    "My.Pkg",
    ["Api"],
    output=Referenced,
  )
  @expect.expect_all(s => {
    s.expect(output.ir, label="ir").to_equal(plain)
    s
    .expect(
      output.origins.map(o => {
        (
          o.module_name.to_canonical(),
          o.name.to_canonical(),
          o.source_name,
          o.path,
        )
      }),
      label="origins",
    )
    .to_contain_exactly([
      ("api", "is-eligible", "isEligible", "My/Pkg/Api.elm"),
      ("api", "swap", "swap", "My/Pkg/Api.elm"),
      ("util", "one", "one", "My/Pkg/Util.elm"),
    ])
    s
    .expect(output.origins, label="origins")
    .element(0)
    .get("span", o => o.span)
    .to_equal({ start_line: 7, start_column: 1, end_line: 7, end_column: 11, })
    s
    .expect(output.origins, label="origins")
    .element(0)
    .get("parameters", o => o.parameters)
    .to_equal([
      (
        "active",
        { start_line: 7, start_column: 12, end_line: 7, end_column: 18, },
      ),
      ("vip", { start_line: 7, start_column: 19, end_line: 7, end_column: 22, }),
    ])
    // A tuple argument is not lifted, so it is not a parameter.
    s
    .expect(output.origins, label="origins")
    .element(1)
    .get("parameters", o => o.parameters)
    .to_be_empty()
    s
    .expect(output.origins, label="origins")
    .element(1)
    .get("span", o => o.span)
    .to_equal({ start_line: 12, start_column: 1, end_line: 12, end_column: 5, })
  })
}
