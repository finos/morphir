///|
/// Property: a frontend failure lists each file once, in first-seen order, and puts every problem under its file,
/// in report order.
test "frontend failures group every problem under its file" {
  @expect.for_all((shape : Array[(UInt32, Bool)]) => {
    let diagnostics : Array[@engine.Diagnostic] = shape.mapi((i, item) => {
      let (file, ranged) = item
      let name = "F" + (file % 3).to_string() + ".elm"
      {
        path: "src/" + name,
        stage: "frontend",
        message: "m" + i.to_string(),
        details: None,
        problem: Some(
          Source({
            code: "elm.p" + i.to_string(),
            detail: "d" + i.to_string(),
            path: name,
            location: if ranged {
              Some({
                start_line: i + 1,
                start_column: 1,
                end_line: i + 1,
                end_column: 2,
              })
            } else {
              None
            },
          }),
        ),
      }
    })
    guard diagnostics is [first, ..] else { return }
    let reply = frontend_failure(diagnostics, @ids.LanguageId::parse("elm"))
    let files = @wire.array(@wire.field(reply, "frontendDiagnostics"))
    let seen : Array[String] = []
    for d in diagnostics {
      if !seen.contains(d.path) {
        seen.push(d.path)
      }
    }
    @expect.expect(
      files.map(f => @wire.string(@wire.field(f, "path"))),
      label="files",
    ).to_equal(seen)
    for f in files {
      let path = @wire.string(@wire.field(f, "path"))
      @expect.expect(
        @wire.array(@wire.field(f, "problems")).map(p => {
          @wire.string(@wire.field(p, "code"))
        }),
        label=path,
      ).to_equal(
        diagnostics.filter(d => d.path == path).map(d => d.code().unwrap_or("")),
      )
    }
    @expect.expect(reply, label="first problem")
    .at("frontendDiagnostic.code")
    .to_equal(Json::string(first.code().unwrap_or("")))
  })
}
