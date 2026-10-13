///|
test "frontend recovery warning survives each generation target" {
  let source = "pub fn is_ready() -> Bool { true }\npub fn isReady() -> Bool { false }"
  for target in ["scheme", "moonbit", "elm"] {
    let reply = @pipeline.execute({
      "operation": "compile",
      "source": source,
      "languageId": "moonbit",
      "frontendProfile": "moonbit-model-bool-library-v1",
      "target": target,
    })
    assert_eq(@wire.field(reply, "success"), Json::boolean(true))
    let warnings = @wire.array(@wire.field(reply, "sourceWarnings"))
    assert_eq(warnings.length(), 1)
    let warning = warnings[0]
    assert_eq(
      @wire.string(@wire.field(warning, "code")),
      "moonbit_frontend.name_normalization_collision",
    )
    assert_eq(@wire.string(@wire.field(warning, "stage")), "frontend")
    assert_true(@wire.string(@wire.field(warning, "fix")).contains("Rename"))
    let locations = @wire.array(@wire.field(warning, "locations"))
    assert_eq(locations.map(l => @wire.string(@wire.field(l, "original"))), [
      "isReady", "is_ready",
    ])
    assert_true(
      locations.all(l => @wire.string(@wire.field(l, "allocated")) != ""),
    )
    assert_eq(
      @wire.field(@wire.field(locations[0], "source"), "startLine"),
      Json::number(2),
    )
    assert_eq(
      @wire.field(@wire.field(locations[0], "source"), "startColumn"),
      Json::number(7),
    )
  }
}
