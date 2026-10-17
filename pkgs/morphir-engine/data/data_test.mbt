///|
fn empty_json() -> String {
  "{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"pricing\",\"dependencies\":{},\"def\":{\"modules\":{}}}}}"
}

///|
fn snapshot(content : @data.Content) -> @data.SourceSnapshot {
  { unit_id: "Pricing", content, }
}

///|
fn diagnostic(action : () -> Unit raise) -> String {
  try {
    action()
    "accepted"
  } catch {
    @data.Invalid(code, _) => code
    _ => "unexpected_error"
  }
}

///|
test "JSON and Ion share current typed IR with binary checkpoints by default" {
  let registry = @data.Registry::new()
  let original = registry.decode("morphir-json", snapshot(Text(empty_json())))
  let checkpoint = registry.checkpoint(original)
  assert_true(checkpoint is Binary(_))
  let restored = registry.decode("ion-binary", snapshot(checkpoint))
  assert_eq(restored.distribution, original.distribution)
  assert_eq(restored.id, original.id)
  let text = registry.checkpoint(restored, codec="ion-text")
  let reread = registry.decode("ion-text", snapshot(text))
  assert_eq(reread.distribution, original.distribution)
  assert_eq(
    registry.encode("morphir-json", reread),
    registry.encode("morphir-json", original),
  )
}

///|
test "rich metadata retains all Ion kinds and ordered unknown annotations" {
  let registry = @data.Registry::new()
  let original = registry.decode("morphir-json", snapshot(Text(empty_json())))
  let metadata = @ion_text.read_ion(
    "hint::opaque::{cost: decimal_cost::12.340d0, zero: -0.00, time: 2026-10-01T01:02:03.004-00:00, typed_null: null.int, symbol: quote, text: \"quote\", blob: {{AQID}}, clob: {{\"abc\"}}, items: [1,2], expr: (a b), flags: [true,false,null], floats: [1e0,nan,+inf,-inf,-0e0], duplicate: 1, duplicate: 2, huge: 18446744073709551616000001}"[:],
  )
  let unit = @data.IRUnit::{
    id: original.id,
    provenance: [],
    distribution: original.distribution,
    metadata: [{ node_id: "value:Pricing.quote/body", data: metadata, }],
    annotations: [
      @ion.SymbolToken::new("before"),
      @ion.SymbolToken::new("morphir_pipeline"),
      @ion.SymbolToken::new("after"),
    ],
  }
  for codec in ["ion-text", "ion-binary"] {
    let output = registry.checkpoint(unit, codec~)
    let restored = registry.decode(codec, snapshot(output))
    assert_eq(restored.distribution, unit.distribution)
    assert_eq(restored.annotations.map(token => token.text()), [
      Some("before"),
      Some("morphir_pipeline"),
      Some("after"),
    ])
    assert_eq(restored.metadata[0].node_id, unit.metadata[0].node_id)
    assert_true(restored.metadata[0].data.equals(metadata))
  }
  assert_eq(
    diagnostic(fn() raise { ignore(registry.encode("morphir-json", unit)) }),
    "data.lossy_conversion",
  )
}

///|
fn literal_file(literal : String) -> String {
  "{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"pricing\",\"def\":{\"modules\":{\"main\":{\"Public\":{\"values\":{\"test\":{\"Public\":{\"value\":{\"ExpressionBody\":{\"inputTypes\":{},\"outputType\":{\"Unit\":{}},\"body\":{\"Literal\":{\"literal\":" +
  literal +
  "}}}}}}}}}}}}}}"
}

///|
test "integer decimal and document number lexemes never pass through Double" {
  let registry = @data.Registry::new()
  for
    literal in [
      "{\"IntegerLiteral\":18446744073709551616000001}", "{\"IntegerLiteral\":-0}",
      "{\"DecimalLiteral\":\"+0010.5000e-100\"}", "{\"DocumentLiteral\":{\"huge\":18446744073709551616000001,\"tiny\":1e-400,\"scale\":12.3400,\"zero\":-0}}",
    ] {
    let unit = registry.decode(
      "morphir-json",
      snapshot(Text(literal_file(literal))),
    ) catch {
      @data.Invalid(code, detail) => fail(code + ": " + detail)
    }
    for codec in ["ion-text", "ion-binary"] {
      let restored = registry.decode(
        codec,
        snapshot(registry.checkpoint(unit, codec~)),
      )
      assert_eq(restored.distribution, unit.distribution)
      // JSON object field order is not an IR semantic contract.
      let exported = registry.encode("morphir-json", restored)
      assert_eq(
        registry.decode("morphir-json", snapshot(exported)).distribution,
        unit.distribution,
      )
      assert_eq(registry.checkpoint(restored), registry.checkpoint(unit))
    }
  }
}

///|
test "historical JSON migration uses the same checkpoint path" {
  let registry = @data.Registry::new()
  let original = registry.decode(
    "morphir-json",
    snapshot(
      Text(
        "{\"formatVersion\":3,\"distribution\":[\"Library\",[[\"pricing\"]],[],{\"modules\":[]}]}",
      ),
    ),
  )
  assert_eq(original.distribution.format_version.major, 4U)
  let restored = registry.decode(
    "ion-binary",
    snapshot(registry.checkpoint(original)),
  )
  assert_eq(restored.distribution, original.distribution)
  assert_eq(
    diagnostic(fn() raise {
      ignore(
        registry.decode(
          "morphir-json",
          snapshot(Text("{\"formatVersion\":99}")),
        ),
      )
    }),
    "unsupported_format_version_major",
  )
}

///|
fn ion_envelope(ir : String, extra~ : String = "") -> String {
  "morphir_pipeline::{profile:\"morphir-pipeline-v1\",contract:\"ir-unit\",unit_id:\"Pricing\",ir:" +
  ir +
  ",metadata:[]" +
  extra +
  "}"
}

///|
test "profile records reject duplicates annotations and unrepresentable values" {
  let registry = @data.Registry::new()
  for
    (text, expected) in [
      (
        ion_envelope(empty_json(), extra=",unit_id:\"Pricing\""),
        "data.duplicate_field",
      ),
      (ion_envelope(empty_json(), extra=",unexpected:1"), "data.unknown_field"),
      (
        ion_envelope("{formatVersion:4,formatVersion:4,distribution:{}}"),
        "data.duplicate_field",
      ),
      (
        ion_envelope("hint::{formatVersion:4}"),
        "data.profile_value_unsupported",
      ),
      (
        ion_envelope("{formatVersion:null.int}"),
        "data.profile_value_unsupported",
      ),
      (
        ion_envelope("{formatVersion:decimal_cost::4.0}"),
        "data.profile_value_unsupported",
      ),
      (
        ion_envelope(empty_json()).replace(
          old="morphir-pipeline-v1",
          new="morphir-pipeline-v2",
        ),
        "data.profile_mismatch",
      ),
      (
        ion_envelope(empty_json()).replace(old="Pricing", new="Other"),
        "data.unit_mismatch",
      ),
    ] {
    assert_eq(
      diagnostic(fn() raise {
        ignore(registry.decode("ion-text", snapshot(Text(text))))
      }),
      expected,
    )
  }
}

///|
test "registry encoding capability conflicts and malformed bytes fail clearly" {
  let registry = @data.Registry::new()
  assert_eq(
    diagnostic(fn() raise {
      ignore(registry.decode("unknown", snapshot(Text(empty_json()))))
    }),
    "data.unknown_codec",
  )
  assert_eq(
    diagnostic(fn() raise {
      ignore(registry.decode("ion-binary", snapshot(Text(empty_json()))))
    }),
    "data.encoding_mismatch",
  )
  assert_eq(
    diagnostic(fn() raise {
      ignore(registry.decode("morphir-json", snapshot(Binary(b"abc"))))
    }),
    "data.encoding_mismatch",
  )
  assert_eq(
    diagnostic(fn() raise {
      ignore(registry.decode("ion-binary", snapshot(Binary(b"not ion"))))
    }),
    "data.decode_failed",
  )
  let codec = @data.Codec::{
    decode: fn(source, _) raise { registry.decode("morphir-json", source) },
    encode: fn(unit, _) raise { registry.encode("morphir-json", unit) },
  }
  registry.register("custom-json", codec)
  assert_eq(
    diagnostic(fn() raise { registry.register("custom-json", codec) }),
    "data.codec_conflict",
  )
  let unit = registry.decode("custom-json", snapshot(Text(empty_json())))
  assert_eq(
    registry.encode("custom-json", unit),
    registry.encode("morphir-json", unit),
  )
}

///|
test "Ion reader nesting limits retain tree-limit diagnostics" {
  let registry = @data.Registry::new(limits={
    max_bytes: 1000000,
    max_depth: 1024,
    max_values: 10000,
  })
  let original = registry.decode("morphir-json", snapshot(Text(empty_json())))
  let mut nested = @ion.IonValue::int(1)
  for i = 0; i < @ion.MAX_NESTING_DEPTH; i = i + 1 {
    nested = @ion.IonValue::list([nested])
  }
  let unit = @data.IRUnit::{
    ..original,
    metadata: [{ node_id: "retained", data: nested, }],
  }
  for codec in ["ion-text", "ion-binary"] {
    let checkpoint = registry.checkpoint(unit, codec~)
    assert_eq(
      diagnostic(fn() raise {
        ignore(registry.decode(codec, snapshot(checkpoint)))
      }),
      "data.tree_limit",
    )
    assert_eq(
      diagnostic(fn() raise {
        ignore(registry.open_checkpoint(codec, checkpoint))
      }),
      "data.tree_limit",
    )
  }
  assert_eq(
    registry.decode("morphir-json", snapshot(Text(empty_json()))).distribution,
    original.distribution,
  )
}

///|
test "byte and tree budgets are independent of codec and malformed identities" {
  let registry = @data.Registry::new()
  let unit = registry.decode("morphir-json", snapshot(Text(empty_json())))
  let small = @data.Registry::new(limits={
    max_bytes: 10,
    max_depth: 128,
    max_values: 100000,
  })
  assert_eq(
    diagnostic(fn() raise {
      ignore(small.decode("morphir-json", snapshot(Text(empty_json()))))
    }),
    "data.byte_limit",
  )
  assert_eq(
    diagnostic(fn() raise { ignore(small.checkpoint(unit)) }),
    "data.byte_limit",
  )
  let shallow = @data.Registry::new(limits={
    max_bytes: 100000,
    max_depth: 1,
    max_values: 100000,
  })
  assert_eq(
    diagnostic(fn() raise { ignore(shallow.checkpoint(unit)) }),
    "data.tree_limit",
  )
  let few = @data.Registry::new(limits={
    max_bytes: 100000,
    max_depth: 128,
    max_values: 1,
  })
  assert_eq(
    diagnostic(fn() raise {
      ignore(few.decode("morphir-json", snapshot(Text(empty_json()))))
    }),
    "data.tree_limit",
  )
  let duplicate = @data.IRUnit::new("Pricing", unit.distribution, metadata=[
    { node_id: "same", data: @ion.IonValue::int(1), },
    { node_id: "same", data: @ion.IonValue::int(2), },
  ])
  assert_eq(
    diagnostic(fn() raise { ignore(registry.checkpoint(duplicate)) }),
    "data.invalid_identity",
  )
}
