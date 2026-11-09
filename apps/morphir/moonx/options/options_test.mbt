///|
test "ordinary application arrays remain opaque and unchanged" {
  for
    args in [
      [],
      ["worksheet", "", "--json"],
      ["--help", "--json"],
      ["--log-level", "debug", "worksheet", "x.scm", "--json"],
      ["mck", "check", "--", "--moonx-help", "", "--json"],
      ["toolchain", "exec", "--", "node", "", "--moonx-json", "--"],
      ["--", "--moonx-help"],
    ] {
    let parsed = @options.parse(args)
    assert_true(parsed.format() is Human)
    guard parsed.request() is Forward(actual) else {
      fail("expected forwarding")
    }
    assert_eq(actual, args)
  }
}

///|
test "leading JSON reporting keeps the application flag and exact tail" {
  let args = ["--json", "worksheet", "", "--", "--moonx-help"]
  let parsed = @options.parse(args)
  assert_true(parsed.format() is MachineJson)
  guard parsed.request() is Forward(actual) else { fail("expected forwarding") }
  assert_eq(actual, args)
  let prefixed = @options.parse(["--moonx-json", ..args])
  assert_true(prefixed.format() is MachineJson)
  guard prefixed.request() is Forward(actual) else {
    fail("expected forwarding")
  }
  assert_eq(actual, args)
}

///|
test "launcher help is explicit and supports JSON in either flag order" {
  for
    args in [
      ["--json", "--moonx-help"],
      ["--moonx-help", "--json"],
      ["--moonx-json", "--moonx-help"],
    ] {
    let parsed = @options.parse(args)
    assert_true(parsed.format() is MachineJson)
    assert_true(parsed.request() is Help)
  }
  let parsed = @options.parse(["--moonx-help"])
  assert_true(parsed.format() is Human)
  assert_true(parsed.request() is Help)
}

///|
test "literal escape passes even reserved controls to the application" {
  let args = ["--moonx-help", "--moonx-json", "--moonx-forward", "", "--"]
  let parsed = @options.parse(["--moonx-forward", ..args])
  assert_true(parsed.format() is Human)
  guard parsed.request() is Forward(actual) else { fail("expected forwarding") }
  assert_eq(actual, args)
}

///|
test "unknown leading controls refuse through the declared parser" {
  for
    args in [
      ["--moonx-unknown", "--json"],
      ["--moonx-json", "--moonx-unknown"],
      ["--moonx-help", "--moonx-unknown", "--json"],
    ] {
    let refused = try {
      ignore(@options.parse(args))
      false
    } catch {
      @options.InvalidControls(format~, message~) =>
        format is MachineJson && !message.is_empty()
    }
    assert_true(refused)
  }
}

///|
test "caller mutation cannot change retained forwarding" {
  let args = ["worksheet", "before.scm"]
  let parsed = @options.parse(args)
  args[1] = "changed.scm"
  guard parsed.request() is Forward(first) else { fail("expected forwarding") }
  assert_eq(first, ["worksheet", "before.scm"])
  first[0] = "changed"
  guard parsed.request() is Forward(second) else { fail("expected forwarding") }
  assert_eq(second, ["worksheet", "before.scm"])
}
