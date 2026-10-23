///|
test "workspace modes preserve literal paths" {
  for
    path in [
      "folder", "folder with spaces/雪", "", "--", "--help", "-x", "help", "--morphir-native-worker",
    ] {
    assert_true(invocation(["fixture", path]) == Fixture(path))
    assert_true(invocation(["race", path]) == Race(path))
  }
}

///|
test "workspace unrecognized invocations retain default checks" {
  for
    args in [
      [],
      ["fixture"],
      ["race"],
      ["fixture", "one", "two"],
      ["race", "one", "two"],
      ["unknown", "folder"],
      ["--help"],
      ["--"],
      ["--", "fixture", "folder"],
      ["help", "fixture"],
      ["--morphir-native-worker"],
      ["--type=renderer"],
    ] {
    assert_true(invocation(args) == Checks)
  }
}

///|
test "workspace command grammar preserves the legacy dispatch table" {
  let tokens = [
    "fixture", "race", "unknown", "", "--", "--help", "folder with spaces/雪",
  ]
  for first in tokens {
    assert_true(invocation([first]) == Checks)
    for second in tokens {
      let expected = match first {
        "fixture" => Fixture(second)
        "race" => Race(second)
        _ => Checks
      }
      assert_true(invocation([first, second]) == expected)
      for third in tokens {
        assert_true(invocation([first, second, third]) == Checks)
      }
    }
  }
}
