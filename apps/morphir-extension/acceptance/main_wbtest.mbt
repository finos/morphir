///|
test "acceptance operands retain literal path boundaries" {
  for
    argv in [
      ["guest", "repository", "evidence"],
      ["guest with spaces", "répertoire/世界", "quote\"' $`; evidence"],
      ["-guest", "--repository", "--help"],
      ["--", "repository", "evidence"],
      ["guest", "--", "evidence"],
      ["guest", "repository", "--"],
      ["--", "--", "--"],
      ["", "", ""],
    ] {
    let args = parse_acceptance_operands(argv)
    assert_eq(args.values["guest"][0], argv[0])
    assert_eq(args.values["repository"][0], argv[1])
    assert_eq(args.values["evidence"][0], argv[2])
  }
}

///|
test "acceptance requires exactly three operands before effects" {
  for
    argv in [
      [],
      ["guest"],
      ["guest", "repository"],
      ["guest", "repository", "evidence", "extra"],
      ["--help"],
      ["--"],
      ["--", "guest", "repository", "evidence"],
    ] {
    let rejected = try {
      ignore(parse_acceptance_operands(argv))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
