///|
fn old_option(args : Array[String], name : String) -> String? {
  for i in 0..<(args.length() - 1) {
    if args[i] == name {
      return Some(args[i + 1])
    }
  }
  None
}

///|
fn assert_old_options(args : Array[String]) -> Unit raise {
  assert_eq(
    check_options(args),
    (
      old_option(args, "--dir").unwrap_or("../../_site"),
      old_option(args, "--config").unwrap_or("../../site/site.json"),
      old_option(args, "--base"),
    ),
  )
}

///|
test "check preserves independent lookups, ignored tokens and missing last values" {
  for
    args in [
      [],
      ["--dir"],
      ["--config"],
      ["--base"],
      ["--dir", "first", "--dir"],
      ["--dir", "--config", "λ path", "--base", ""],
      ["--", "--dir", "--help", "--config", "-h", "--base", "help"],
      ["--dir=other", "--base=/ignored", "--dir", "﻿λ😀"],
      ["--dir", "missing-value", "--config", "--token-", "--base", "\"$;`'"],
      ["program", "--base", "", "--base", "later"],
    ] {
    assert_old_options(args)
  }
}

///|
test "check matches the original helper over adversarial four-token products" {
  let tokens = [
    "--dir", "--config", "--base", "--", "--help", "-h", "", "λ😀", "--dir=x",
  ]
  for a in tokens {
    assert_old_options([a])
    for b in tokens {
      assert_old_options([a, b])
      for c in tokens {
        assert_old_options([a, b, c])
        for d in tokens {
          assert_old_options([a, b, c, d])
        }
      }
    }
  }
}
