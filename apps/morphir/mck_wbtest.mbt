///|
test "MCK keeps runner controls separate from opaque canonical arguments" {
  let cli = parse_cli([
    "--json", "mck", "--runner-pin", "runner.json", "workbench", "run", "--adapter",
    "adapter path", "--adapter-arg", "--json", "--adapter-arg", "", "--adapter-arg",
    "$(literal)", "--kit", "kit path", "--report", "out.json",
  ])
  assert_eq(cli.command, "mck")
  assert_true(flag(cli, "json"))
  assert_eq(value(cli, "runner-pin"), "runner.json")
  assert_eq(
    cli.forwarded,
    Some([
      "workbench", "run", "--adapter", "adapter path", "--adapter-arg", "--json",
      "--adapter-arg", "", "--adapter-arg", "$(literal)", "--kit", "kit path", "--report",
      "out.json",
    ]),
  )
  assert_eq(parse_cli(["mck", "--help"]).forwarded, None)
  assert_true(parse_cli(["mck", "--help"]).help)
  assert_eq(
    parse_cli(["mck", "--", "report", "compare", "a", "b"]).forwarded,
    Some(["report", "compare", "a", "b"]),
  )
  assert_eq(
    parse_cli(["mck", "check", "kit", "--json"]).forwarded,
    Some(["check", "kit", "--json"]),
  )
}

///|
test "MCK pins refuse unsupported contracts versions and malformed identities" {
  let pin : Json = {
    "contractVersion": "0.1.0-draft.1",
    "runnerVersion": "0.4.0-beta.10",
    "executable": "/private/backend/morphir",
    "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "sourceRevision": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "origin": "https://github.com/finos/morphir/releases/tag/v0.4.0-beta.10",
  }
  let admitted = mck_pin(pin)
  assert_eq(admitted.executable, "/private/backend/morphir")
  for
    (key, replacement) in [
      ("contractVersion", "2.0.0"),
      ("runnerVersion", "0.4.0-beta.9"),
      ("sha256", "abc"),
      ("executable", "morphir"),
      ("sourceRevision", "main"),
      ("origin", ""),
    ] {
    guard pin is Object(fields) else { abort("fixture pin") }
    let changed = fields.copy()
    changed[key] = Json::string(replacement)
    assert_true(
      try {
        ignore(mck_pin(Json::object(changed)))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "MCK local controls preserve the implicit and explicit raw boundary" {
  let tail = [
    "check", "--runner-pin", "child pin", "--json-lines", "--help", "", "λ space",
    "--flag", "one", "--flag", "two", "--", "--", "$(literal);`literal`",
  ]
  for separator in [[], ["--"]] {
    let cli = parse_cli(
      [
        "--no-banner", "--json", "mck", "--runner-pin=runner pin", "--node", "node path",
      ] +
      separator +
      tail,
    )
    assert_eq(cli.command, "mck")
    assert_eq(value(cli, "runner-pin"), "runner pin")
    assert_eq(value(cli, "node"), "node path")
    assert_true(flag(cli, "json"))
    assert_true(!flag(cli, "json-lines"))
    assert_true(!cli.help)
    assert_eq(cli.forwarded, Some(tail))
  }
  assert_eq(parse_cli(["mck", "--"]).forwarded, None)
  assert_eq(parse_cli(["mck", "--", ""]).forwarded, Some([""]))
  assert_eq(parse_cli(["mck", ""]).forwarded, Some([""]))
  assert_eq(
    value(parse_cli(["mck", "--runner-pin", "check", "run"]), "runner-pin"),
    "check",
  )
  assert_eq(
    parse_cli(["mck", "--runner-pin", "check", "run"]).forwarded,
    Some(["run"]),
  )
  assert_eq(value(parse_cli(["mck", "--node", "-", "check"]), "node"), "-")
}

///|
test "MCK help validates every local control before the child boundary" {
  let cli = parse_cli(["--no-banner", "mck", "--help", "check", "--unknown"])
  assert_true(cli.help)
  assert_eq(cli.forwarded, Some(["check", "--unknown"]))
  assert_true(cli.help_text.contains("all later arguments are opaque"))
  for
    args in [
      ["mck", "--help", "--unknown", "check"],
      ["mck", "--runner-pin", "--help", "check"],
      ["mck", "--runner-pin", "--no-banner", "check"],
      ["mck", "--runner-pin", "--", "check"],
      ["mck", "--runner-pin=", "check"],
      ["mck", "--node", "", "check"],
      ["mck", "--timeout", "1", "--timeout=2", "check"],
      ["--json", "mck", "--json-lines", "check"],
      ["mck", "-", "check"],
    ] {
    assert_true(
      try {
        ignore(parse_cli(args))
        false
      } catch {
        _ => true
      },
      msg=args.join(" | "),
    )
  }
  assert_true(
    error_output_mode(["--json", "mck", "--help", "--unknown"]) is JSON,
  )
  assert_true(
    error_output_mode(["mck", "--json-lines", "--unknown"]) is JSONLines,
  )
  // These are the current failure-envelope rules, even for child-owned flags.
  assert_true(error_output_mode(["mck", "check", "--json"]) is JSON)
  assert_true(error_output_mode(["mck", "--", "check", "--json"]) is Human)
}

///|
test "MCK syntax diagnostics and terminal domain validation keep the error boundary" {
  for
    (tokens, message) in [
      (["--runner-pin="], "Missing value for --runner-pin"),
      (["--node", "", "check"], "Missing value for --node"),
      (
        ["--json", "--json-lines", "check"],
        "--json and --json-lines cannot be combined",
      ),
    ] {
    let error = try {
      ignore(parse_cli(["mck"] + tokens))
      "accepted"
    } catch {
      error => @host.error_message(error)
    }
    assert_eq(error, message)
  }
  for
    (tokens, message) in [
      (
        ["--timeout", "1", "--timeout=2", "check"],
        "argument '--timeout' cannot be used multiple times",
      ),
      (["--no-banner=true", "check"], "unexpected argument '--no-banner=true'"),
      (["--runner-pin", "--no-banner", "check"], "a value is required"),
    ] {
    let error = try {
      ignore(parse_cli(["mck"] + tokens))
      "accepted"
    } catch {
      @config.Invalid(message) => message
      _ => abort("MCK syntax must retain the config error boundary")
    }
    assert_true(error.contains(message), msg=error)
    assert_true(error.contains("Usage: morphir mck"), msg=error)
  }
}

///|
test "MCK local option forms retain values and every opaque tail token" {
  let tails = [
    [],
    ["check"],
    [""],
    [
      "check", "--node", "child", "--json", "--", "", "--", "--help", "$(literal);`literal`",
      "λ 😀",
    ],
  ]
  for globals in [[], ["--no-banner", "--json"], ["-h", "--json-lines"]] {
    for name in command_schema("mck").options {
      for
        (control, expected) in [
          (["--" + name + "= spaced λ "], " spaced λ "),
          (["--" + name, "check"], "check"),
          (["--" + name, "-"], "-"),
          (["--" + name + "=--"], "--"),
          (["--" + name + "=--no-banner"], "--no-banner"),
        ] {
        for separator in [[], ["--"]] {
          for tail in tails {
            let cli = parse_cli(globals + ["mck"] + control + separator + tail)
            assert_eq(cli.command, "mck")
            assert_eq(cli.entries, Map::from_array([(name, [expected])]))
            assert_eq(
              cli.forwarded,
              if tail.is_empty() {
                None
              } else {
                Some(tail)
              },
            )
            assert_eq(cli.help, globals.contains("-h"))
            assert_eq(flag(cli, "json"), globals.contains("--json"))
            assert_eq(flag(cli, "json-lines"), globals.contains("--json-lines"))
            assert_true(!flag(cli, "no-banner"))
            assert_eq(cli.help_text, render_help("mck"))
          }
        }
      }
      for
        control in [
          ["--" + name, ""],
          ["--" + name + "="],
          ["--" + name],
          ["--" + name, "-value"],
          ["--" + name, "--no-banner"],
          ["--" + name, "--"],
          ["--" + name, "one", "--" + name, "two"],
        ] {
        assert_true(
          try {
            ignore(parse_cli(globals + ["mck"] + control))
            false
          } catch {
            _ => true
          },
          msg=control.join(" | "),
        )
      }
      // A missing value may consume the first non-hyphen child-looking token.
      let cli = parse_cli(
        globals + ["mck", "--" + name, "check", "run", "--", ""],
      )
      assert_eq(value(cli, name), "check")
      assert_eq(cli.forwarded, Some(["run", "--", ""]))
    }
  }
}

///|
test "MCK root routing and compatibility flags keep their exact ownership" {
  for
    globals in [
      [],
      ["--no-banner"],
      ["--json", "--no-banner"],
      ["--help", "--json-lines"],
    ] {
    for flags in [[], ["--no-banner"], ["--no-banner", "--no-banner"]] {
      let cli = parse_cli(
        globals + ["mck"] + flags + ["check", "--no-banner", ""],
      )
      assert_eq(cli.forwarded, Some(["check", "--no-banner", ""]))
      assert_eq(cli.help, globals.contains("--help"))
      assert_true(!flag(cli, "no-banner"))
    }
  }
  // The established selector accepts exact leading global tokens only.
  for
    args in [
      ["--", "mck", "check"],
      ["--json=true", "mck", "check"],
      ["--no-banner=true", "mck", "check"],
      ["-hh", "mck", "check"],
      ["--node", "node", "mck", "check"],
      ["run", "mck", "check"],
    ] {
    assert_true(mck_cli(args) is None)
  }
}

///|
test "MCK six-candidate bound preserves long inputs and terminal refusal" {
  // This schema is the proof obligation for the bounded prefix search.
  let schema = command_schema("mck")
  assert_eq(schema.options, [
    "runner-pin", "mck-helper", "node", "timeout", "cancel-file",
  ])
  assert_true(schema.repeatable.is_empty())
  assert_true(!schema.positional)
  assert_true(schema.children.is_empty())
  let flags = [ for _ in 0..<2048 => "--no-banner" ]
  let controls = []
  for name in schema.options {
    controls.push("--" + name)
    controls.push("check")
  }
  let tail = ["check"] +
    [
      for _ in 0..<2048 => "child value"
    ] +
    ["--", "", "--help"]
  let args = ["mck"] + flags + controls + tail
  assert_eq(mck_prefix_end(args, 1), 1 + flags.length() + controls.length())
  let cli = parse_cli(args)
  assert_eq(cli.forwarded, Some(tail))
  for name in schema.options {
    assert_eq(value(cli, name), "check")
  }
  for
    invalid in [
      ["--unknown"],
      ["--timeout=1", "--timeout=2"],
      ["--runner-pin="],
    ] {
    assert_true(
      try {
        ignore(parse_cli(["mck"] + flags + invalid + tail))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "MCK keeps known local controls and embedded delimiters opaque after the command" {
  let tail = ["check", "--json", "--node=child", "", "--", "x", "--"]
  let cli = parse_cli(["mck"] + tail)
  assert_eq(cli.forwarded, Some(tail))
  assert_true(!flag(cli, "json"))
  assert_eq(value(cli, "node"), "")
  assert_true(!cli.help)
}
