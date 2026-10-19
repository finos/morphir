///|
fn refusal(source : String, limits : @yaml.Limits) -> String {
  try {
    ignore(@yaml.parse(source, limits~))
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
  }
}

///|
test "YAML budgets accept boundaries and refuse the next growth" {
  let limits = @yaml.Limits::default()
  assert_eq(refusal("a: [0]", { ..limits, max_nodes: 4, }), "accepted")
  assert_eq(refusal("a: [0]", { ..limits, max_nodes: 3, }), "yaml_node_limit")
  assert_eq(refusal("a: [0]", { ..limits, max_assembly_nodes: 4, }), "accepted")
  assert_eq(
    refusal("a: [0]", { ..limits, max_assembly_nodes: 3, }),
    "yaml_assembly_limit",
  )
  assert_eq(refusal("a: [[0]]", { ..limits, max_depth: 3, }), "accepted")
  assert_eq(
    refusal("a: [[0]]", { ..limits, max_depth: 2, }),
    "yaml_depth_limit",
  )
  assert_eq(refusal("a: 1234", { ..limits, max_scalar_units: 4, }), "accepted")
  assert_eq(
    refusal("a: 12345", { ..limits, max_scalar_units: 4, }),
    "yaml_scalar_limit",
  )
  assert_eq(
    refusal("a: \"😀\"", { ..limits, max_scalar_units: 2, }),
    "accepted",
  )
  assert_eq(
    refusal("a: \"😀\"", { ..limits, max_scalar_units: 1, }),
    "yaml_scalar_limit",
  )
  assert_eq(
    refusal("a: |\n  abcd\n", { ..limits, max_scalar_units: 4, }),
    "yaml_scalar_limit",
  )
  assert_eq(refusal("a: 0", { ..limits, max_bytes: 4, }), "accepted")
  assert_eq(refusal("a: 0 ", { ..limits, max_bytes: 4, }), "yaml_source_limit")
  assert_eq(refusal("{}", { ..limits, max_events: 6, }), "accepted")
  assert_eq(refusal("{}", { ..limits, max_events: 5, }), "yaml_event_limit")
}

///|
test "YAML scalar normalization never rounds or drops text" {
  assert_eq(
    @yaml.parse("a: +1\nb: +.5e3\nc: 5.\nd: 1.5E3\ne: yes\nf: '01'\n").stringify(),
    "{\"a\":1,\"b\":0.5e3,\"c\":5.0,\"d\":1.5E3,\"e\":\"yes\",\"f\":\"01\"}",
  )
  for
    source in ["a: -007", "a: 01.5", "a: 0o17", "a: 0xF", "a: -.inf", "a: .NaN"] {
    assert_eq(refusal(source, @yaml.Limits::default()), "invalid_literal")
  }
}

///|
test "YAML malformed streams and quoted profile syntax stay distinct" {
  for source in ["a: [1", "a: {b: 1", "a: 'unterminated", "a: 1\n...\nb: 2"] {
    assert_eq(refusal(source, @yaml.Limits::default()), "invalid_yaml")
  }
  assert_eq(
    @yaml.parse("a: '&anchor *alias !tag %YAML <<'\n").stringify(),
    "{\"a\":\"&anchor *alias !tag %YAML <<\"}",
  )
}

///|
test "YAML diagnostic cursors are bounded before repeated key expansion" {
  assert_eq(
    refusal(
      "{" + ("a".repeat(100) + ": {").repeat(42) + "b: 1" + "}".repeat(43),
      @yaml.Limits::default(),
    ),
    "yaml_cursor_limit",
  )
}

///|
test "typed float boundaries refuse nonfinite and nonzero underflow across codecs" {
  for source in ["1e9999", "1e-9999", "-1e-9999"] {
    let code = try {
      ignore(@wire.float(@wire.parse(source)))
      "accepted"
    } catch {
      @wire.Invalid(code, _) => code
    }
    assert_eq(code, "invalid_literal")
  }
  assert_eq(@wire.float(@wire.parse("-0.0")), -0.0)
  assert_eq(@yaml.parse("value: 1e9999").stringify(), "{\"value\":1e9999}")
}

///|
test "unrecognized number-like spellings remain profile strings" {
  assert_eq(
    @yaml.parse("a: .iNF\nb: 0xZZ\nc: 0x\nd: -0xF\ne: 0X1F").stringify(),
    "{\"a\":\".iNF\",\"b\":\"0xZZ\",\"c\":\"0x\",\"d\":\"-0xF\",\"e\":\"0X1F\"}",
  )
}

///|
test "semantic shorthand work is refused before typed expansion" {
  let source = "formatVersion: 4\ndistribution: {Library: {packageName: " +
    "a-".repeat(1000) +
    "a, dependencies: {}, def: {modules: {}}}}"
  let code = try {
    ignore(
      @yaml.read(source, limits={
        ..@yaml.Limits::default(),
        max_assembly_nodes: 1000,
      }),
    )
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
    _ => "other"
  }
  assert_eq(code, "yaml_assembly_limit")
}

///|
test "zero YAML documents and unsafe depth configuration are refused" {
  for source in ["", "  \n", "# only a comment\n"] {
    assert_eq(refusal(source, @yaml.Limits::default()), "invalid_yaml")
  }
  assert_eq(
    refusal("{}", { ..@yaml.Limits::default(), max_depth: 2147483647, }),
    "yaml_invalid_limits",
  )
}
