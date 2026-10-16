///|
test "workspace checkpoint inspection retains rich metadata and opaque source labels" {
  let file = @fixtures.invocation_library()
  let baseline = @pipeline.execute({
    "operation": "inspect",
    "source": @codec.to_json(file).stringify(),
  })
  let metadata = @ion_text.read_ion(
    "opaque::{cost:price::12.340d0, huge:18446744073709551616000001, blob:{{AQID}}, duplicate:1, duplicate:2}"[:],
  )
  let unit = @data.IRUnit::{
    ..@data.IRUnit::new("original logical identity", file),
    metadata: [{ node_id: "value:calls:main#subtract", data: metadata, }],
    annotations: [
      @ion.SymbolToken::new("before"),
      @ion.SymbolToken::new("morphir_pipeline"),
      @ion.SymbolToken::new("after"),
    ],
    provenance: [@ion.IonValue::string("original provenance")],
  }
  let registry = @data.Registry::new()
  for codec in ["ion-text", "ion-binary"] {
    let bytes = match registry.encode(codec, unit) {
      Text(s) => @utf8.encode(s[:])
      Binary(b) => b
    }
    let inspected = @pipeline.execute({
      "operation": "inspect",
      "source": "",
      "sourceCodec": codec,
      "sourceBase64": @base64.encode(bytes[:]),
    })
    assert_eq(
      @wire.field(inspected, "success"),
      Json::boolean(true),
      msg=inspected.stringify(),
    )
    let old_nodes = @wire.array(@wire.field(baseline, "nodes"))
    for node in @wire.array(@wire.field(inspected, "nodes")) {
      let old = old_nodes.filter(old => {
          @wire.field(old, "key") == @wire.field(node, "key")
        })[0]
      assert_eq(@wire.field(node, "label"), @wire.field(old, "label"))
    }
    let restored = registry.open_checkpoint(
      "ion-text",
      Text(@wire.string(@wire.field(inspected, "sourceUnitIon"))),
    )
    assert_eq(restored.id, unit.id)
    assert_true(restored.metadata[0].data.equals(metadata))
    assert_eq(
      restored.annotations.map(a => a.text()),
      unit.annotations.map(a => a.text()),
    )
    assert_true(restored.provenance[0].equals(unit.provenance[0]))
    assert_eq(@codec.to_json(restored.distribution), @codec.to_json(file))
  }
}

///|
test "workspace JSON import accepts original historical versions without JS parsing" {
  let original = @versioned.read(
    "{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"example\",\"dependencies\":{},\"def\":{\"modules\":{}}}}}",
  )
  for major in [1U, 2U, 3U, 4U] {
    let file = @migration.migrate(
      original,
      @version.FormatVersion::baseline(major),
    )
    let source = @versioned.write(file)
    let reply = @pipeline.execute({
      "operation": "inspect",
      "source": "",
      "sourceCodec": "morphir-json",
      "sourceBase64": @base64.encode(@utf8.encode(source[:])[:]),
    })
    assert_eq(
      @wire.field(reply, "success"),
      Json::boolean(true),
      msg=reply.stringify(),
    )
    assert_eq(@wire.field(reply, "formatVersion"), Json::string("4.0.0"))
  }
}

///|
test "workspace codec admission rejects invalid bytes and unknown formats" {
  for
    (codec, bytes) in [
      ("morphir-json", b"\xff"),
      ("ion-binary", b"\x01"),
      ("unknown", b"{}"),
    ] {
    let reply = @pipeline.execute({
      "operation": "inspect",
      "source": "",
      "sourceCodec": codec,
      "sourceBase64": @base64.encode(bytes[:]),
    })
    assert_eq(@wire.field(reply, "success"), Json::boolean(false))
  }
}
