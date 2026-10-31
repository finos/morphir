///|
test "notebook options belong to their subcommands" {
  let cli = parse_cli([
    "--json", "notebook", "export", "sheet.scm", "--format", "dib", "-o", "sheet.dib",
  ])
  assert_eq(cli.command, "notebook export")
  assert_eq(value(cli, "path"), "sheet.scm")
  assert_eq(value(cli, "output"), "sheet.dib")
  assert_eq(value(cli, "format"), "dib")
  assert_true(flag(cli, "json"))
  assert_true(
    flag(
      parse_cli(["notebook", "export", "sheet.scm", "--evaluate"]),
      "evaluate",
    ),
  )
  assert_eq(
    value(
      parse_cli(["notebook", "import", "sheet.dib", "--output", "sheet.scm"]),
      "output",
    ),
    "sheet.scm",
  )
  assert_true(parse_cli(["notebook", "import", "--help", "--json"]).help)
  for
    args in [
      ["notebook", "import", "sheet.dib", "--evaluate"],
      ["notebook", "import", "sheet.dib", "--format", "dib"],
      ["notebook", "export", "sheet.scm", "-o", "a", "--output", "b"],
      ["worksheet", "sheet.scm", "--format", "ipynb"],
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
test "extension help names the internal worker subcommand and the WASM runtimes" {
  let help = parse_cli(["extension", "--help"]).help_text
  assert_true(
    help.contains(
      "worker: internal subcommand that the native CLI starts as the WASM worker runtime; users do not run it.",
    ),
  )
  assert_true(help.contains("Process and WASM runtimes run"))
  assert_true(!help.contains("WASM runtimes are refused"))
  // Only `morphir extension` lists it; its commands do not.
  assert_true(
    !parse_cli(["extension", "compile", "--help"]).help_text.contains(
      "internal subcommand",
    ),
  )
}

///|
test "the parser selects subcommands and global output without exiting for help" {
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
test "the parser rejects malformed flags arity conflicts and command options" {
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
test "help checks trailing flags and leaves help after the program boundary" {
  let cli = parse_cli(["--help", "toolchain", "run", "--json"])
  assert_true(cli.help)
  assert_true(flag(cli, "json"))
  assert_eq(cli.command, "toolchain run")
  assert_true(parse_cli(["project", "list", "-h", "--json-lines"]).help)
  assert_true(
    try {
      ignore(parse_cli(["run", "--help", "--json", "--json-lines"]))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(parse_cli(["toolchain", "run", "--", "-h"]).forwarded, Some(["-h"]))
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
      ignore(parse_cli(["run", "--config-script", "--target=js"]))
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

///|
test "ordinary syntax preserves ordered repeats and rejects conflicts in both orders" {
  let cli = parse_cli([
    "run", "--project=a", "--project", "b", "--log-file= λ log ", "--help",
  ])
  assert_eq(values(cli, "project"), ["a", "b"])
  assert_eq(value(cli, "log-file"), " λ log ")
  assert_true(cli.help)
  for
    args in [
      ["--log-file=a", "--log-file", "b"],
      ["--all", "--project=p"],
      ["--project=p", "--all"],
      ["--file", "--directory"],
      ["--directory", "--file"],
      ["--json", "--json-lines"],
      ["--json-lines", "--json"],
      ["--help", "--unknown"],
      ["--log-file="],
    ] {
    assert_true(
      try {
        ignore(parse_cli(["run"] + args))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "configuration controls use explicit arrays and keep frontend profiles separate" {
  let cli = parse_cli([
    "--profiles", "postgres,metrics", "project", "list", "--profiles", "tracing",
    "--config", "morphir.json", "--isolated", "--discovery-boundary", ".", "--json",
  ])
  assert_eq(values(cli, "profiles"), ["postgres,metrics", "tracing"])
  assert_true(flag(cli, "isolated"))
  assert_true(flag(cli, "json"))
  assert_eq(value(cli, "config"), "morphir.json")
  guard configuration_profiles(cli) is Selected(names) else {
    fail("expected selected profiles")
  }
  assert_eq(names.names().map(name => name.to_string()), [
    "postgres", "metrics", "tracing",
  ])
  let init = parse_cli([
    "workspace", "init", "--project", "Example", "--profile", "library", "--profiles",
    "metrics",
  ])
  assert_eq(value(init, "profile"), "library")
  assert_eq(value(init, "profiles"), "metrics")
}

///|
test "invalid profile and file selections are refused without host effects" {
  for
    args in [
      ["project", "list", "--profiles", "postgres,,metrics", "--json"],
      ["project", "list", "--profiles="],
      ["--profiles", "UPPER", "project", "list"],
      ["project", "list", "--profiles", "metrics", "--no-profiles"],
      ["project", "list", "--no-profiles", "--profiles", "metrics"],
      ["project", "list", "--config", "settings.ini"],
    ] {
    let refused = try {
      ignore(parse_cli(args))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
  let message = try {
    ignore(parse_cli(["run", "--config", "transform.scm"]))
    "accepted"
  } catch {
    @config.Invalid(message) => message
    _ => "unexpected"
  }
  assert_true(message.contains("--config-script"))
}

///|
test "MCK configuration controls precede its command while child argv stays opaque" {
  let cli = parse_cli([
    "--profiles", "metrics", "--isolated", "--json", "mck", "--", "check", "--profiles",
    "child", "--config", "literal", "--", "",
  ])
  assert_eq(value(cli, "profiles"), "metrics")
  assert_true(flag(cli, "isolated"))
  assert_eq(
    cli.forwarded,
    Some(["check", "--profiles", "child", "--config", "literal", "--", ""]),
  )
}

///|
test "diagnostic levels validate before IO and retain external argument ownership" {
  for level in ["trace", "debug", "info", "warn", "error", "fatal", "off"] {
    let cli = parse_cli(["project", "list", "--log-level", level, "--json"])
    assert_eq(diagnostic_level(cli).unwrap().name(), level)
  }
  let message = try {
    ignore(parse_cli(["project", "list", "--log-level", "loud", "--json"]))
    "accepted"
  } catch {
    @config.Invalid(message) => message
    error => error.to_string()
  }
  assert_true(
    message.contains("trace, debug, info, warn, error, fatal or off"),
    msg=message,
  )
  let cli = parse_cli([
    "--log-level", "debug", "mck", "check", "--log-level", "external", "--", "",
  ])
  assert_eq(diagnostic_level(cli).unwrap().name(), "debug")
  assert_eq(cli.forwarded, Some(["check", "--log-level", "external", "--", ""]))
}
