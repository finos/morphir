///|
fn generate(unit : @data.IRUnit) -> @generator.Output raise {
  @generator.generate({
    unit_id: unit.id,
    ir: unit.distribution,
    metadata: unit.metadata.map(entry => @generator.NodeMetadata::{
      node_id: entry.node_id,
      data: entry.data,
    }),
    annotations: unit.annotations,
    provenance: unit.provenance,
  })
}

///|
test "JSON and Ion codecs generate identical source manifests projects and symbols" {
  let registry = @data.Registry::new()
  let json = @ir_json.write(@fixtures.library())
  let original = registry.decode("morphir-json", {
    unit_id: "scalars",
    content: @data.Text(json),
  })
  let expected = generate(original)
  for format in ["ion-text", "ion-binary"] {
    let content = registry.encode(format, original)
    let restored = registry.decode(format, { unit_id: "scalars", content, })
    let actual = generate(restored)
    assert_eq(actual.project, expected.project)
    assert_eq(actual.artifacts, expected.artifacts)
    assert_eq(actual.symbols, expected.symbols)
  }
}

///|
test "rich metadata reaches generated Ion symbols through engine codecs without JSON projection" {
  let registry = @data.Registry::new()
  let original = registry.decode("morphir-json", {
    unit_id: "scalars",
    content: @data.Text(@ir_json.write(@fixtures.library())),
  })
  let rich = {
    ..original,
    metadata: [
      {
        node_id: "value:pricing:scalars#rate/body",
        data: @ion_text.read_ion(
          "tag::unknown::{decimal:-0.00,blob:{{/wCA}},time:2026-10-01T00:00-00:00,nil:null.string}",
        ),
      },
    ],
    annotations: original.annotations + [@ion.symbol("audit")],
  }
  let expected = generate(rich)
  let restored = registry.decode("ion-binary", {
    unit_id: "scalars",
    content: registry.encode("ion-binary", rich),
  })
  assert_eq(generate(restored).artifacts, expected.artifacts)
  assert_true(
    try {
      ignore(registry.encode("morphir-json", restored))
      false
    } catch {
      @data.Invalid("data.lossy_conversion", _) => true
      _ => false
    },
  )
}

///|
test "rewrite provenance reaches generated Ion metadata" {
  let unit = @data.IRUnit::new("pricing", @fixtures.library(), metadata=[
    {
      node_id: "value:pricing:scalars#rate/body",
      data: @ion_text.read_ion("opaque::unknown::12.340d0"),
    },
  ])
  let lineage = @data.Lineage::identity(unit)
  let rewritten = @data.apply_rewrite(
    unit,
    { distribution: unit.distribution, lineage: Some(lineage), },
    "declared-identity",
    "retain",
    @data.MetadataPolicy::retain(),
  )
  let output = generate(rewritten)
  guard output.artifacts[3].content is Binary(bytes) else { fail("symbols") }
  let value = @ion_binary.read_binary_value(bytes[:])
  guard value.kind() is Struct(fields) else { fail("profile") }
  let provenance = fields
    .iter()
    .find_first(f => f.name().text() == Some("source_provenance"))
    .unwrap()
    .value()
  guard provenance.kind() is List([retained]) else { fail("provenance") }
  assert_true(retained.equals(rewritten.provenance[0]))
}
