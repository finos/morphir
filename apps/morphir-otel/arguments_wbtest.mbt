///|
test "adapter syntax preserves literal operands for domain validation" {
  for
    args in [
      ["http://127.0.0.1:4318", "http/json", "1"],
      ["https://example.invalid/a λ", "http/protobuf", "5000"],
      ["", "", ""],
      ["-endpoint", "--protocol", "-1"],
      ["--", "--help", "--self-test"],
      ["--help", "--", "-h"],
    ] {
    let parsed = adapter_arguments(args)
    assert_eq(parsed.values["ENDPOINT"], [args[0]])
    assert_eq(parsed.values["PROTOCOL"], [args[1]])
    assert_eq(parsed.values["TIMEOUT"], [args[2]])
  }
}

///|
test "adapter syntax refuses incomplete and extra operands before reading input" {
  for
    args in [
      [],
      ["--help"],
      ["-h"],
      ["--"],
      ["--", "http://127.0.0.1", "http/json", "1"],
      ["http://127.0.0.1"],
      ["http://127.0.0.1", "http/json"],
      ["http://127.0.0.1", "http/json", "1", "extra"],
    ] {
    assert_true(
      try {
        ignore(adapter_arguments(args))
        false
      } catch {
        _ => true
      },
    )
  }
}
