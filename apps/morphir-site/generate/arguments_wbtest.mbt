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
  let root = old_option(args, "--root").unwrap_or("../..")
  assert_eq(
    generate_options(args),
    (
      root,
      old_option(args, "--out").unwrap_or("\{root}/_site"),
      args.contains("--main"),
    ),
  )
}

///|
test "generation preserves dependent defaults, global main and ignored tokens" {
  for
    args in [
      [],
      ["--root"],
      ["--out"],
      ["--root", "first", "--root"],
      ["--out", "first", "--out"],
      ["--root", "--out", "λ path", "--main"],
      ["--out", "--main"],
      ["--root", "--main"],
      ["--", "--root", "--help", "--out", "-h", "--main"],
      ["--root=other", "--out=ignored", "--root", "﻿λ😀"],
      ["--root", "missing-value", "--out", "--token-"],
      ["--root", "", "--out", ""],
      ["program", "--out", "\"$;`'", "--main=true"],
    ] {
    assert_old_options(args)
  }
}

///|
test "generation matches the original helper over adversarial four-token products" {
  let tokens = [
    "--root", "--out", "--main", "--", "--help", "-h", "", "λ😀", "--out=x",
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
