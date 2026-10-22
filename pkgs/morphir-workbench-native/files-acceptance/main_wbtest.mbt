///|
test "fixture folder operands remain literal data" {
  for
    path in [
      "fixture", "folder with spaces/雪", "", "--", "--help", "-h", "-x", "--unknown",
      "help",
    ] {
    assert_eq(fixture_folder([path]), path)
  }
}

///|
test "fixture folder requires exactly one operand" {
  for arguments in [[], ["one", "two"], ["--", "folder"], ["--help", "extra"]] {
    let rejected = try {
      ignore(fixture_folder(arguments))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
