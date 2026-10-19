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
    assert_eq(
      @wire.field(reply, "sourceFormatVersion"),
      Json::string(file.format_version().to_release_string()),
    )
    let text_reply = @pipeline.execute({
      "operation": "inspect",
      "source": source,
    })
    assert_eq(
      @wire.field(text_reply, "sourceFormatVersion"),
      Json::string(file.format_version().to_release_string()),
    )
  }
}

///|
test "workspace codec validation rejects invalid bytes and unknown formats" {
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

///|
test "captured model refusal retains user-facing model stage and codec detail" {
  let reply = @pipeline.execute({
    "operation": "inspect",
    "source": "",
    "sourceCodec": "morphir-json",
    "sourceBase64": "e30=",
  })
  assert_eq(@wire.field(reply, "success"), Json::boolean(false))
  assert_eq(@wire.field(reply, "code"), Json::string("workbench.invalid_model"))
  assert_eq(@wire.field(reply, "stage"), Json::string("model"))
  assert_true(
    @wire.string(@wire.field(reply, "message")).contains(
      "The model is not valid",
    ),
  )
  assert_true(@wire.field(reply, "cause") != Json::null())
}

///|
test "workspace MEP text and binary retain opaque context without changing IR labels" {
  let file = @fixtures.invocation_library()
  let semantic = @codec.to_json(file)
  let baseline = @pipeline.execute({
    "operation": "inspect",
    "source": semantic.stringify(),
  })
  let source = "morphir_model::{ir:" +
    semantic.stringify() +
    ",enrichments:[{owner:\"future-owner\",data:source_name::target_name::{label:\"must not rename declarations\",huge:18446744073709551616000001,decimal:123.4500,blob:{{AP8=}},duplicate:1,duplicate:2}}],provenance:[origin::\"preserved\"]}"
  let envelope = @ion_text.read_ion(source[:])
  let registry = @data.Registry::new()
  for codec in ["ion-text", "ion-binary"] {
    let bytes = if codec == "ion-text" {
      @utf8.encode("\uFEFF// retained presentation\r\n" + source + "\r\n")
    } else {
      @ion_binary.write_binary_value(envelope)
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
    assert_eq(@wire.field(inspected, "ir"), semantic)
    assert_eq(@wire.field(inspected, "nodes"), @wire.field(baseline, "nodes"))
    assert_eq(
      @wire.field(inspected, "sourceFormatVersion"),
      Json::string("4.0.0"),
    )
    let restored = registry.open_checkpoint(
      "ion-text",
      Text(@wire.string(@wire.field(inspected, "sourceUnitIon"))),
    )
    assert_eq(restored.id, "mep")
    assert_eq(restored.distribution, file)
    assert_true(restored.metadata.is_empty())
    assert_eq(restored.provenance.length(), 2)
    assert_true(
      restored.provenance[0].equals(
        @ion_text.read_ion("origin::\"preserved\""[:]),
      ),
    )
    let captured = restored.provenance[1]
    assert_eq(captured.annotations()[0].text(), Some("morphir_model_import"))
    guard captured.kind() is Struct([field]) else {
      fail("missing MEP source envelope")
    }
    assert_eq(field.name().text(), Some("source_envelope"))
    assert_true(field.value().equals(envelope))
  }
}

///|
test "workspace shared source selection refuses ambiguous model and checkpoint annotations" {
  let source = "morphir_model::morphir_pipeline::{ir:{},enrichments:[],provenance:[]}"
  for codec in ["ion-text", "ion-binary"] {
    let bytes = if codec == "ion-text" {
      @utf8.encode(source)
    } else {
      @ion_binary.write_binary_value(@ion_text.read_ion(source[:]))
    }
    let reply = @pipeline.execute({
      "operation": "inspect",
      "source": "",
      "sourceCodec": codec,
      "sourceBase64": @base64.encode(bytes[:]),
    })
    assert_eq(@wire.field(reply, "success"), Json::boolean(false))
    assert_eq(@wire.field(reply, "stage"), Json::string("model"))
    assert_eq(
      @wire.field(reply, "code"),
      Json::string("workbench.invalid_model"),
    )
    assert_eq(
      @wire.field(@wire.field(reply, "cause"), "code"),
      Json::string("data.ambiguous_envelope"),
    )
    assert_eq(@wire.optional(reply, "sourceUnitIon"), None)
  }
}

///|
test "private tree input bounds aggregate path text before decoding overflow content" {
  let prefix = Array::make(16, Array::make(240, "p").join("") + "/").join("")
  let entries = Array::makei(256, i => {
    let suffix = i.to_string()
    Json::object(
      Map([
        (
          "path",
          Json::string(
            prefix + Array::make(240 - suffix.length(), "x").join("") + suffix,
          ),
        ),
        ("contentBase64", Json::string("")),
      ]),
    )
  })
  entries.push({ "path": "x", "contentBase64": "!" })
  let reply = @pipeline.execute({
    "operation": "inspect",
    "source": "",
    "sourceTree": Json::array(entries),
  })
  assert_eq(@wire.field(reply, "success"), Json::boolean(false))
  assert_eq(@wire.field(reply, "code"), Json::string("workbench.invalid_model"))
  assert_eq(
    @wire.field(@wire.field(reply, "cause"), "code"),
    Json::string("data.tree_limit"),
  )
  assert_true(
    @wire.string(@wire.field(@wire.field(reply, "cause"), "detail")).contains(
      "path text budget",
    ),
  )
}
