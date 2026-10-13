///|
test "backend warnings preserve allocations and source warnings decode with shared codec" {
  let reply = moonbit_output(
    @moonbit.Input::new("naming", @fixtures.naming_library()),
  )
  let warnings = @wire.array(@wire.field(reply, "generationWarnings"))
  assert_true(!warnings.is_empty())
  assert_true(
    warnings.any(w => {
      @wire.string(@wire.field(w, "code")) == "moonbit_backend.name_collision"
    }),
  )
  for warning in warnings {
    assert_eq(@wire.string(@wire.field(warning, "stage")), "backend")
    assert_true(@wire.string(@wire.field(warning, "fix")) != "")
    for loc in @wire.array(@wire.field(warning, "locations")) {
      assert_true(@wire.string(@wire.field(loc, "owner")) != "")
      assert_true(@wire.string(@wire.field(loc, "allocated")) != "")
    }
  }
  let warning : @diagnostics.Warning = {
    code: "recovery",
    stage: "frontend",
    message: "Recovered",
    fix: "Rename",
    locations: [
      {
        owner: "value:user:main#ready",
        original: "ready",
        allocated: "ready_1",
        source: Some({
          start_line: 2,
          start_column: 7,
          end_line: 2,
          end_column: 12,
        }),
      },
    ],
  }
  let decoded = @wire.array(
    source_warnings([@ion.IonValue::string("unrelated"), warning.to_ion()]),
  )
  assert_eq(decoded, [naming_warning(warning)])
  assert_eq(
    @wire.field(
      @wire.field(
        @wire.array(@wire.field(decoded[0], "locations"))[0],
        "source",
      ),
      "startColumn",
    ),
    Json::number(7),
  )
}
