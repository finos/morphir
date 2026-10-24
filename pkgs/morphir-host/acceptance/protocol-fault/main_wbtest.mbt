///|
test "fault operands preserve literal paths and domain vocabulary" {
  for
    argv in [
      ["checkpoint", "malformed"],
      ["path with spaces/世界\"'", "unsupported-fault"],
      ["--help", "--unknown"],
      ["-checkpoint", "truncated"],
      ["--", "malformed"],
      ["checkpoint", "--"],
      ["--", "--"],
      ["", ""],
    ] {
    let args = parse_fault_operands(argv)
    assert_eq(args.values["checkpoint"][0], argv[0])
    assert_eq(args.values["fault"][0], argv[1])
  }
}

///|
test "fault parser rejects missing operands before file access" {
  for argv in [[], ["checkpoint"], ["--help"], ["--"]] {
    let rejected = try {
      ignore(parse_fault_operands(argv))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "fault parser preserves ignored trailing operands" {
  let args = parse_fault_operands([
    "checkpoint", "malformed", "--", "extra", "--help", "-x", "", "--",
  ])
  assert_eq(args.values["checkpoint"], ["checkpoint"])
  assert_eq(args.values["fault"], ["malformed"])
  assert_eq(args.values["ignored"], ["--", "extra", "--help", "-x", "", "--"])
}
