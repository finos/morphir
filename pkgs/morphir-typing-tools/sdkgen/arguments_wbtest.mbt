///|
test "SDK command declarations keep literal bootstrap operands" {
  for
    case in [
      (["generate"], Generate),
      (["check"], Check),
      (
        ["bootstrap", " λ bindings.json ", "out $;`.scm"],
        Bootstrap(" λ bindings.json ", "out $;`.scm"),
      ),
      (["bootstrap", "-bindings", "-out"], Bootstrap("-bindings", "-out")),
      (["bootstrap", "--", "--"], Bootstrap("--", "--")),
      (
        ["bootstrap", "--help", "--self-test"],
        Bootstrap("--help", "--self-test"),
      ),
      (
        ["bootstrap", "--self-test", "--help"],
        Bootstrap("--self-test", "--help"),
      ),
      (["bootstrap", "help", "-h"], Bootstrap("help", "-h")),
      (["bootstrap", "", ""], Bootstrap("", "")),
    ] {
    let (argv, expected) = case
    assert_true(sdk_invocation(parse_sdk_arguments(argv)) == expected)
  }
}

///|
test "SDK command syntax refuses invalid arity before file operations" {
  for
    argv in [
      [],
      ["unknown"],
      ["check", "extra"],
      ["generate", "--unknown"],
      ["bootstrap"],
      ["bootstrap", "bindings"],
      ["bootstrap", "bindings", "out", "extra"],
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
      ["bootstrap", "--"],
      ["bootstrap", "--", "--bindings", "--out"],
      ["bootstrap", "bindings", "out", "--help"],
    ] {
    let refused = try {
      ignore(parse_sdk_arguments(argv))
      false
    } catch {
      _ => true
    }
    assert_true(refused, msg=argv.join(" | "))
  }
}
