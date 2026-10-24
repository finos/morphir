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

///|
test "desktop events distinguish observable readiness failures and actual quit status" {
  let events = [
    Startup,
    WindowReady,
    BrowserLoaded,
    Failure("load_failed", "Ω\n\"message\""),
    QuitPrevented,
    Exit(23),
  ]
  let expected = [
    "startup", "window-ready-to-show", "browser-did-finish-load", "failure", "quit-prevented",
    "exit",
  ]
  for i, event in events {
    let text = desktop_event(i + 1, event)
    assert_true(text.has_suffix("\n"))
    let value = @json.parse(text)
    guard value is Object(fields) else { fail("object required") }
    assert_eq(fields.get("event"), Some(Json(expected[i])))
    assert_eq(fields.get("sequence"), Some(Json(i + 1)))
    assert_eq(fields.get("command"), Some(Json("workbench.desktop")))
    if event is Failure(code, message) {
      assert_eq(
        fields.get("error"),
        Some(({ "code": Json(code), "message": Json(message) } : Json)),
      )
    }
    if event is Exit(code) {
      assert_eq(fields.get("exitCode"), Some(Json(code)))
    }
    assert_eq(value.stringify() + "\n", text)
  }
}
