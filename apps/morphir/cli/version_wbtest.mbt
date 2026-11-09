///|
test "version is a command with local data options kept under their owner" {
  for args in [["version", "--json"], ["--json", "version"]] {
    let cli = parse_cli(args)
    assert_eq(cli.command, "version")
    assert_true(flag(cli, "json"))
    assert_false(cli.help)
  }
  assert_eq(
    value(
      parse_cli(["extension", "install", "example", "--version", "2.3.4"]),
      "version",
    ),
    "2.3.4",
  )
  assert_true(
    parse_cli(["version", "--help", "--json"]).help_text.contains(
      "{name,version}",
    ),
  )
  let extra = try {
    ignore(parse_cli(["version", "unexpected"]))
    false
  } catch {
    _ => true
  }
  assert_true(extra)
}

///|
test "version result embeds manifest identity and refuses incomplete metadata" {
  let embedded = embedded_version(release_identity)
  guard embedded is Object(fields) &&
    fields.get("version") is Some(String(version)) else {
    fail("Expected embedded release version")
  }
  assert_false(version.is_empty())
  assert_eq(fields.get("name"), Some(Json("finos/morphir")))
  guard version_report(embedded) is Object(report) else {
    fail("Expected result")
  }
  assert_eq(report.get("state"), Some(Json("succeeded")))
  assert_eq(report.get("command"), Some(Json("version")))
  assert_eq(report.get("result"), Some(embedded))
  let invalids : Array[Json] = [
    { "name": "other/cli", "version": "1.0.0" },
    { "name": "finos/morphir" },
    Json::null(),
  ]
  for invalid in invalids {
    let refused = try {
      ignore(embedded_version(invalid))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
}
