///|
test "Scheme documentation command declarations" {
  assert_true(docs_invocation(parse_docs_arguments(["generate"])) == Generate)
  assert_true(docs_invocation(parse_docs_arguments(["check"])) == Check)
  for
    argv in [
      [],
      ["unknown"],
      ["check", "extra"],
      ["generate", "extra"],
      ["check", "--unknown"],
      ["generate", "--unknown"],
      ["--unknown"],
      ["--help"],
      ["-h"],
      ["--self-test"],
      ["help"],
      ["help", "check"],
      ["--"],
      ["--", "check"],
      ["check", "--"],
      ["generate", "--"],
      ["check", "--help"],
      ["generate", "--help"],
      ["check", "--self-test"],
      ["generate", "--self-test"],
      ["check", ""],
    ] {
    let refused = try {
      ignore(parse_docs_arguments(argv))
      false
    } catch {
      _ => true
    }
    assert_true(refused, msg=argv.join(" | "))
  }
}
