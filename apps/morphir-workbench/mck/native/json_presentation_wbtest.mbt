///|
test "presentation grammar owns only its reserved first token" {
  assert_true(presentation_mode([]) is Human)
  assert_true(presentation_mode(["--help"]) is Human)
  assert_true(presentation_mode(["--", "--json"]) is Human)
  assert_true(
    presentation_mode(["--forward-argv", "--", "--json", "", "Ω", "--"])
    is Human,
  )
  let raw = ["--json", "--", "", "Ω", "--", "--json", "--help"]
  assert_true(presentation_mode(raw[:]) is Events)
  assert_eq(raw, ["--json", "--", "", "Ω", "--", "--json", "--help"])
  assert_true(presentation_mode(["--json"]) is Events)
  guard presentation_mode(["--json", "--help"]) is Help(text) else {
    fail("missing owned help")
  }
  assert_true(text.contains("morphir/command-event"))
  let rejected = try {
    ignore(presentation_mode(["--json", "--unknown"]))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_true(presentation_mode(["--json", "--json"]) is Events)
}
