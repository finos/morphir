///|
test "documentation JSON grammar checks whole argv before effects" {
  assert_true(
    docs_invocation(parse_json_arguments(["--json", "generate"])) == Generate,
  )
  assert_true(
    docs_invocation(parse_json_arguments(["--json", "check"])) == Check,
  )
  for
    argv in [
      ["--json", "--help"],
      ["--json", "-h"],
      ["--json", "generate", "--help"],
    ] {
    assert_true(parse_json_arguments(argv).flags.get("help").unwrap_or(false))
  }
  for
    argv in [
      ["--json"],
      ["--json", "unknown"],
      ["--json", "--unknown"],
      ["--json", "check", "extra"],
      ["--json", "generate", "--", "--json"],
      ["--json", "--help", "--unknown"],
    ] {
    let refused = try {
      ignore(parse_json_arguments(argv))
      false
    } catch {
      _ => true
    }
    assert_true(refused, msg=argv.join(" | "))
  }
}

///|
test "documentation JSON results describe paths and preserve mapped errors" {
  assert_eq(
    success("morphir.schemedocs.generate", {
      "writtenPaths": ["λ.mbt"],
      "removedPaths": [],
    }),
    {
      "profile": "morphir/command-result",
      "contractVersion": "0.1.0",
      "command": "morphir.schemedocs.generate",
      "state": "succeeded",
      "exitCode": 0,
      "result": { "writtenPaths": ["λ.mbt"], "removedPaths": [] },
      "diagnostics": [],
    },
  )
  assert_eq(failure("morphir.schemedocs", 1, "read", "missing"), {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": "morphir.schemedocs",
    "state": "failed",
    "exitCode": 1,
    "error": { "code": "read", "message": "missing" },
    "diagnostics": [],
  })
}
