///|
test "SDK JSON bootstrap preserves every fixed literal operand" {
  for value in ["--json", "--help", "--", "", "λ😀", "--out=path", " space "] {
    let matches = parse_json_arguments(["--json", "bootstrap", value, value])
    assert_true(sdk_invocation(matches) == Bootstrap(value, value))
    assert_false(matches.flags.get("help").unwrap_or(false))
  }
  assert_true(
    sdk_invocation(parse_json_arguments(["--json", "generate"])) == Generate,
  )
  assert_true(
    sdk_invocation(parse_json_arguments(["--json", "check"])) == Check,
  )
  for
    argv in [
      ["--json", "--help"],
      ["--json", "-h"],
      ["--json", "check", "--help"],
    ] {
    assert_true(parse_json_arguments(argv).flags.get("help").unwrap_or(false))
  }
  for
    argv in [
      ["--json"],
      ["--json", "unknown"],
      ["--json", "--unknown"],
      ["--json", "generate", "extra"],
      ["--json", "bootstrap"],
      ["--json", "bootstrap", "one"],
      ["--json", "bootstrap", "one", "two", "extra"],
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
test "SDK JSON errors carry mapped status and no result" {
  assert_eq(failure("morphir.sdkgen", 2, "syntax", "missing"), {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": "morphir.sdkgen",
    "state": "failed",
    "exitCode": 2,
    "error": { "code": "syntax", "message": "missing" },
    "diagnostics": [],
  })
  assert_eq(
    success("morphir.sdkgen.check", { "bindingCount": 2, "passed": true }),
    {
      "profile": "morphir/command-result",
      "contractVersion": "0.1.0",
      "command": "morphir.sdkgen.check",
      "state": "succeeded",
      "exitCode": 0,
      "result": { "bindingCount": 2, "passed": true },
      "diagnostics": [],
    },
  )
}
