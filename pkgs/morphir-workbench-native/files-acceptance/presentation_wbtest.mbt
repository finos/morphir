///|
test "presentation reserves exact outer families and unwraps once" {
  assert_true(presentation(["--json"]) == Legacy(["--json"]))
  assert_true(presentation(["--json", "--help"]) == JsonHelp)
  let raw = ["--", "", "雪", "--help", "--json", "--forward-argv", "--", "x"]
  assert_true(presentation(["--json", "--"] + raw) == Structured(raw))
  assert_true(presentation(["--forward-argv", "--"] + raw) == Legacy(raw))
  assert_true(
    presentation(["--forward-argv", "--", "--json", "--help"]) ==
    Legacy(["--json", "--help"]),
  )
  assert_true(
    presentation(["--forward-argv", "--", "--forward-argv", "--", "x"]) ==
    Legacy(["--forward-argv", "--", "x"]),
  )
  assert_true(presentation(["--json", "--"]) == Structured([]))
}

///|
test "presentation retains local refusal reasons and foreign fallback" {
  assert_eq(
    presentation_reason(PresentationError("specific reason 雪")),
    "specific reason 雪",
  )
  let foreign : Error = Failure("foreign")
  assert_eq(presentation_reason(foreign), foreign.to_string())
}
