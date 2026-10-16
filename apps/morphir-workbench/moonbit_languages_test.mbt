///|
fn compile_moonbit(source : String, target~ : String = "moonbit") -> Json {
  @pipeline.execute({
    "operation": "compile",
    "source": source,
    "languageId": "moonbit",
    "target": target,
  })
}

///|
test "MoonBit source preserves typed identities, source labels, rich Ion and binary artifacts" {
  let source = "pub fn eligible(active : Bool, vip : Bool) -> Bool { active && !vip }"
  let result = compile_moonbit(source)
  assert_eq(
    @wire.field(result, "success"),
    Json::boolean(true),
    msg=result.stringify(),
  )
  let entry = @wire.string(@wire.field(result, "sourceEntry"))
  assert_true(entry.has_prefix("user:main#"))
  let node = @wire.array(@wire.field(result, "nodes")).filter(n => {
      @wire.field(n, "id") == @wire.text(entry)
    })[0]
  assert_eq(@wire.field(node, "label"), @wire.text("eligible"))
  assert_true(
    @wire.string(@wire.field(node, "signature")).has_prefix("eligible"),
  )
  let profile = @wire.field(
    @wire.field(@wire.field(result, "typedEvaluations"), "entries"),
    entry,
  )
  let inputs = @wire.array(@wire.field(profile, "inputs"))
  assert_eq(@wire.field(inputs[0], "label"), @wire.text("active"))
  assert_eq(@wire.field(inputs[1], "label"), @wire.text("vip"))
  let registry = @data.Registry::new()
  let unit = registry.decode("ion-text", {
    unit_id: "main",
    content: Text(@wire.string(@wire.field(result, "sourceUnitIon"))),
  })
  assert_true(!unit.metadata.is_empty())
  assert_true(!unit.provenance.is_empty())
  assert_eq(@codec.to_json(unit.distribution), @wire.field(result, "ir"))
  let original = @moonbit_frontend.compile({
    unit_id: "main",
    package_name: "user",
    module_name: "main",
    source,
  })
  assert_eq(
    unit.annotations.map(t => t.text()),
    original.annotations.map(t => t.text()),
  )
  assert_true(unit.metadata[0].data.equals(original.metadata[0].data))
  assert_true(unit.provenance[0].equals(original.provenance[0]))
  let generated = @moonbit.generate({
    unit_id: original.unit_id,
    ir: original.ir,
    metadata: original.metadata.map(m => { node_id: m.node_id, data: m.data, }),
    annotations: original.annotations,
    provenance: original.provenance,
  })
  let artifacts = @wire.array(@wire.field(result, "artifacts"))
  assert_eq(artifacts.length(), generated.artifacts.length())
  for artifact in generated.artifacts {
    let encoded = artifacts.filter(a => {
        @wire.field(a, "path") == @wire.text(artifact.path)
      })[0]
    let content = @wire.string(@wire.field(encoded, "content"))
    match artifact.content {
      Text(text) => assert_eq(content, text)
      Binary(bytes) => {
        assert_eq(@wire.field(encoded, "encoding"), @wire.text("base64"))
        assert_eq(@base64.decode(content[:]), bytes)
      }
    }
  }
}

///|
test "MoonBit public entries evaluate every Boolean input combination through typed admission" {
  let result = compile_moonbit(
    "pub fn eligible(active : Bool, vip : Bool) -> Bool { active && !vip }",
  )
  for
    (active, vip, expected) in [
      (false, false, false),
      (false, true, false),
      (true, false, true),
      (true, true, false),
    ] {
    let reply = @pipeline.execute({
      "operation": "evaluate",
      "source": @wire.string(@wire.field(result, "irSource")),
      "executionMode": "typed",
      "entry": @wire.string(@wire.field(result, "sourceEntry")),
      "arguments": [
        { "type": "bool", "value": active },
        { "type": "bool", "value": vip },
      ],
    })
    assert_eq(
      @wire.field(reply, "success"),
      Json::boolean(true),
      msg=reply.stringify(),
    )
    assert_eq(@wire.field(reply, "typed"), { "type": "bool", "value": expected })
  }
}

///|
test "MoonBit private function remains inspectable but has no public typed entry" {
  let result = compile_moonbit("fn hidden(x : Bool) -> Bool { x }")
  assert_eq(@wire.field(result, "success"), Json::boolean(true))
  let entry = @wire.string(@wire.field(result, "sourceEntry"))
  assert_eq(
    @wire.optional(
      @wire.field(@wire.field(result, "typedEvaluations"), "entries"),
      entry,
    ),
    None,
  )
}

///|
test "MoonBit profile rejections retain source coordinates and never fall back to Scheme" {
  let result = compile_moonbit("pub fn answer(x : Int) -> Int { x }")
  assert_eq(@wire.field(result, "success"), Json::boolean(false))
  let diagnostic = @wire.field(result, "frontendDiagnostic")
  assert_eq(
    @wire.field(diagnostic, "code"),
    @wire.text("moonbit_frontend.unsupported_type"),
  )
  assert_true(@wire.field(diagnostic, "source") != Json::null())
  let result = compile_moonbit("(+ 1 2)")
  assert_eq(@wire.field(result, "success"), Json::boolean(false))
}

///|
test "MoonBit generation refusal retains successfully compiled Scheme IR" {
  let result = @pipeline.execute({
    "operation": "compile",
    "source": "(lambda (x) x)",
    "target": "moonbit",
  })
  assert_eq(@wire.field(result, "success"), Json::boolean(true))
  assert_true(@wire.field(result, "ir") != Json::null())
  assert_true(@wire.field(result, "generationMessage") != Json::null())
  assert_eq(@wire.field(result, "artifacts"), Json::array([]))
}

///|
test "MoonBit compiles through each local target without implicit Scheme main execution" {
  for target in ["", "scheme", "elm", "moonbit"] {
    let result = compile_moonbit("pub fn truth() -> Bool { true }", target~)
    assert_eq(
      @wire.field(result, "success"),
      Json::boolean(true),
      msg=result.stringify(),
    )
    assert_true(@wire.field(result, "ir") != Json::null())
  }
  let result = @pipeline.execute({
    "operation": "run",
    "languageId": "moonbit",
    "source": "pub fn truth() -> Bool { true }",
  })
  assert_eq(@wire.field(result, "success"), Json::boolean(false))
  assert_true(
    @wire.string(@wire.field(result, "message")).contains("Model Explorer"),
  )
}
