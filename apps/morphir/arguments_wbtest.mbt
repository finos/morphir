///|
test "ArgParser selects subcommands and global output without exiting for help" {
  let cli = parse_cli(["--json", "toolchain", "run", "work", "--help"])
  assert_eq(cli.command, "toolchain run")
  assert_true(flag(cli, "json"))
  assert_eq(value(cli, "path"), "work")
  assert_true(cli.help)
  assert_true(cli.help_text.contains("Usage: morphir toolchain run"))
  assert_true(cli.help_text.contains("--package"))
  assert_true(!cli.help_text.contains("--suite"))
  let empty = parse_cli([])
  assert_true(empty.help)
  assert_true(empty.help_text.contains("toolchain"))
  assert_true(parse_cli(["project", "--help"]).help)
  assert_eq(
    value(parse_cli(["toolchain", "info", "--timeout=10000"]), "timeout"),
    "10000",
  )
  assert_eq(
    value(
      parse_cli(["toolchain", "setup", "--timeout", "10000", "--yes"]),
      "timeout",
    ),
    "10000",
  )
}

///|
test "append options retain declared order and single options reject duplicates" {
  let listed = parse_cli([
    "project", "list", "--frontend=scheme", "--frontend", "elm", "--target", "js",
    "--target=wasm", "--json-lines",
  ])
  assert_eq(values(listed, "frontend"), ["scheme", "elm"])
  assert_eq(values(listed, "target"), ["js", "wasm"])
  assert_eq(
    value(parse_cli(["run", "--sdk", "first", "--sdk", "override"]), "sdk"),
    "override",
  )
  assert_true(flag(listed, "json-lines"))
  assert_eq(
    values(parse_cli(["run", "--component", "a", "--component=b"]), "component"),
    ["a", "b"],
  )
  assert_eq(
    values(
      parse_cli(["verify", "model", "--dependency=a=x", "--dependency", "b=y"]),
      "dependency",
    ),
    ["a=x", "b=y"],
  )
  assert_true(
    try {
      ignore(parse_cli(["verify", "--target", "js", "--target", "wasm"]))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "local frontend logs are explicit run options with single values" {
  let cli = parse_cli([
    "run", ".", "--log-file", "observations.ionb", "--log-format", "ion-binary",
  ])
  assert_eq(value(cli, "log-file"), "observations.ionb")
  for
    args in [
      ["run", "--log-file", "a", "--log-file", "b"],
      ["run", "--log-format", "ion-text", "--log-format", "text"],
      ["workspace", "--log-file", "a"],
      ["project", "list", "--log-file", "a"],
    ] {
    assert_true(
      try {
        ignore(parse_cli(args))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "ArgParser rejects malformed flags arity conflicts and command options" {
  for
    args in [
      ["unknown"],
      ["project"],
      ["toolchain"],
      ["toolchain", "unknown"],
      ["run", "first", "second"],
      ["run", "--target"],
      ["run", "--target", "--json"],
      ["run", "--unknown"],
      ["project", "list", "--frontend", ""],
      ["execute", "--output", "out"],
      ["toolchain", "build", "--yes"],
      ["toolchain", "exec", "--package", "x"],
      ["run", "--file", "--directory"],
      ["run", "--all", "--project", "x"],
      ["run", "--json", "--json-lines"],
      ["--json", "run", "--json-lines"],
      ["workspace", "--", "path"],
      ["run", "--help", "--unknown"],
      ["run", "--json=true"],
      ["run", "--morphir-internal-help"],
      ["toolchain", "info", "--timeout", "1", "--timeout", "2"],
    ] {
    assert_true(
      try {
        ignore(parse_cli(args))
        false
      } catch {
        _ => true
      },
      msg=args.join(" "),
    )
  }
}

///|
test "program argument boundary preserves opaque values and output flags" {
  let args = [
    "toolchain", "run", "work", "--", "--help", "--json", "", "λ value", "--", "$(echo literal)",
  ]
  let cli = parse_cli(args)
  assert_eq(
    cli.forwarded,
    Some(["--help", "--json", "", "λ value", "--", "$(echo literal)"]),
  )
  assert_true(!cli.help)
  assert_true(!flag(cli, "json"))
  assert_true(error_output_mode(args) is Human)
  assert_eq(
    parse_cli(["toolchain", "run", "--", "--help"]).forwarded,
    Some(["--help"]),
  )
  assert_eq(value(parse_cli(["toolchain", "run", "--", "--help"]), "path"), "")
  assert_eq(
    parse_cli(["toolchain", "exec", "script", "--"]).forwarded,
    Some([]),
  )
}

///|
test "numeric option data stays with validation and parse errors keep envelopes" {
  let cli = parse_cli([
    "verify", "model", "--absolute-tolerance", "-0.5", "--relative-tolerance=1e-9",
  ])
  assert_eq(value(cli, "absolute-tolerance"), "-0.5")
  assert_eq(value(cli, "relative-tolerance"), "1e-9")
  assert_true(error_output_mode(["unknown", "--json"]) is JSON)
  assert_true(error_output_mode(["unknown", "--json-lines"]) is JSONLines)
  assert_true(
    try {
      ignore(parse_cli(["run", "--targte", "js"]))
      false
    } catch {
      error =>
        @host.error_message(error).contains("--target") &&
        @host.error_message(error).contains("Usage: morphir run")
    },
  )
}

///|
test "help checks trailing flags and never exposes its private adapter alias" {
  let cli = parse_cli(["--help", "toolchain", "run", "--json"])
  assert_true(cli.help)
  assert_true(flag(cli, "json"))
  assert_eq(cli.command, "toolchain run")
  assert_true(!cli.help_text.contains(help_alias))
  assert_true(parse_cli(["project", "list", "-h", "--json-lines"]).help)
  assert_true(
    try {
      ignore(parse_cli(["run", "--help", "--json", "--json-lines"]))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(
    parse_cli(["toolchain", "run", "--", help_alias]).forwarded,
    Some([help_alias]),
  )
}

///|
test "option data retains equals Unicode and whitespace without scalar conversion" {
  let cli = parse_cli([
    "execute", "model", "--suite= λ calls.ion ", "--dependency=module=path=value",
    "--dependency", "other=λ path", "--absolute-tolerance=-0.5",
  ])
  assert_eq(value(cli, "suite"), " λ calls.ion ")
  assert_eq(values(cli, "dependency"), ["module=path=value", "other=λ path"])
  assert_eq(value(cli, "absolute-tolerance"), "-0.5")
  assert_true(
    try {
      ignore(parse_cli(["run", "--config", "--target=js"]))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "lifecycle cancellation belongs to execution and pipeline runs" {
  let cli = parse_cli(["verify", "model", "--cancel-file= cancellation signal "])
  assert_eq(value(cli, "cancel-file"), " cancellation signal ")
  assert_true(cli.help_text.contains("--cancel-file"))
  for
    args in [
      ["execute", "model", "--cancel-file", "a", "--cancel-file", "b"],
      ["workspace", "--cancel-file", "a"],
      ["verify", "--cancel-file"],
    ] {
    assert_true(
      try {
        ignore(parse_cli(args))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "merged conform command retains evaluator and receipt options" {
  let cli = parse_cli([
    "conform", "model.json", "--cases=cases.ion", "--cases-format", "ion-text", "--evaluators",
    "scheme,rust", "--require-evaluator", "rust", "--rust-evaluator", "λ evaluator",
    "--rust-evaluator-pin", "pin.json", "--receipt", "receipt.ion", "--receipt-format",
    "ion-binary", "--cancel-file", "cancel", "--dependency", "one=path", "--dependency",
    "two=path", "--json",
  ])
  assert_eq(cli.command, "conform")
  assert_eq(value(cli, "cases"), "cases.ion")
  assert_eq(value(cli, "evaluators"), "scheme,rust")
  assert_eq(value(cli, "rust-evaluator"), "λ evaluator")
  assert_eq(value(cli, "receipt-format"), "ion-binary")
  assert_eq(values(cli, "dependency"), ["one=path", "two=path"])
  assert_true(cli.help_text.contains("Usage: morphir conform <model>"))
  assert_true(cli.help_text.contains("--require-evaluator"))
  for
    args in [
      ["execute", "model", "--cases", "cases.ion"],
      ["verify", "model", "--receipt", "receipt.ion"],
      ["conform", "model", "--cases", "first", "--cases", "second"],
      ["conform", "model", "--receipt-format"],
    ] {
    assert_true(
      try {
        ignore(parse_cli(args))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "metadata authority is an explicit single host file on run" {
  let cli = parse_cli([
    "run", "--metadata-grants", "/host/grants.ion", "--metadata-timeout", "120000",
    "--cancel-file", "stop",
  ])
  assert_eq(value(cli, "metadata-grants"), "/host/grants.ion")
  assert_eq(value(cli, "cancel-file"), "stop")
  for
    args in [
      ["run", "--metadata-grants", "a", "--metadata-grants", "b"],
      ["workspace", "--metadata-grants", "a"],
      ["execute", "--metadata-grants", "a"],
    ] {
    assert_true(
      try {
        ignore(parse_cli(args))
        false
      } catch {
        _ => true
      },
    )
  }
}
