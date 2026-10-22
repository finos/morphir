///|
test "MCK keeps runner controls separate from opaque canonical arguments" {
  let cli = parse_cli([
    "--json", "mck", "--runner-pin", "runner.json", "workbench", "run", "--adapter",
    "adapter path", "--adapter-arg", "--json", "--adapter-arg", "", "--adapter-arg",
    "$(literal)", "--kit", "kit path", "--report", "out.json",
  ])
  assert_eq(cli.command, "mck")
  assert_true(flag(cli, "json"))
  assert_eq(value(cli, "runner-pin"), "runner.json")
  assert_eq(
    cli.forwarded,
    Some([
      "workbench", "run", "--adapter", "adapter path", "--adapter-arg", "--json",
      "--adapter-arg", "", "--adapter-arg", "$(literal)", "--kit", "kit path", "--report",
      "out.json",
    ]),
  )
  assert_eq(parse_cli(["mck", "--help"]).forwarded, None)
  assert_true(parse_cli(["mck", "--help"]).help)
  assert_eq(
    parse_cli(["mck", "--", "report", "compare", "a", "b"]).forwarded,
    Some(["report", "compare", "a", "b"]),
  )
  assert_eq(
    parse_cli(["mck", "check", "kit", "--json"]).forwarded,
    Some(["check", "kit", "--json"]),
  )
}

///|
test "MCK pins refuse unsupported contracts versions and malformed identities" {
  let pin : Json = {
    "contractVersion": "0.1.0-draft.1",
    "runnerVersion": "0.4.0-beta.10",
    "executable": "/private/backend/morphir",
    "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "sourceRevision": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "origin": "https://github.com/finos/morphir/releases/tag/v0.4.0-beta.10",
  }
  let admitted = mck_pin(pin)
  assert_eq(admitted.executable, "/private/backend/morphir")
  for
    (key, replacement) in [
      ("contractVersion", "2.0.0"),
      ("runnerVersion", "0.4.0-beta.9"),
      ("sha256", "abc"),
      ("executable", "morphir"),
      ("sourceRevision", "main"),
      ("origin", ""),
    ] {
    guard pin is Object(fields) else { abort("fixture pin") }
    let changed = fields.copy()
    changed[key] = Json::string(replacement)
    assert_true(
      try {
        ignore(mck_pin(Json::object(changed)))
        false
      } catch {
        _ => true
      },
    )
  }
}
