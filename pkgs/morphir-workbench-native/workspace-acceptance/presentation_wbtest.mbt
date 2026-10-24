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
