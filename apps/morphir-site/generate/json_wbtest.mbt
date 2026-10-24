///|
test "JSON presentation owns only its reserved prefix and unwraps once" {
  for
    raw in [
      [],
      ["--root", "--json"],
      ["--", "", "λ😀", "--help", "--json"],
      ["--out", "--main", "--root", "first", "--root", "last"],
    ] {
    match json_presentation(["--json", "--", ..raw]) {
      Run(found) => {
        assert_eq(found, raw)
        assert_eq(generate_options(found), generate_options(raw))
      }
      Help => fail("raw help is data")
    }
  }
  assert_true(json_presentation(["--json", "--help"]) is Help)
  assert_true(json_presentation(["--json", "-h"]) is Help)
  assert_true(json_presentation(["--json"]) is Run([]))
  for
    argv in [
      ["--json", "--unknown"],
      ["--json", "--root", "path"],
      ["--json", "extra"],
      ["--help"],
    ] {
    let refused = try {
      ignore(json_presentation(argv))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
}

///|
test "site envelopes carry state, diagnostics and no failed result" {
  assert_eq(success({ "writtenPaths": ["λ/--json"] }), {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": "morphir.site.generate",
    "state": "succeeded",
    "exitCode": 0,
    "result": { "writtenPaths": ["λ/--json"] },
    "diagnostics": [],
  })
  assert_eq(failure("site.invalid", "broken"), {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": "morphir.site.generate",
    "state": "failed",
    "exitCode": 1,
    "error": { "code": "site.invalid", "message": "broken" },
    "diagnostics": [],
  })
}
