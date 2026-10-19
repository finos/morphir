///|
test "MEP source inspection retains complete opaque enrichment context" {
  let source = "morphir_model::{ir:{formatVersion:4,distribution:{Library:{packageName:\"fixture\",dependencies:{},def:{modules:{}}}}},enrichments:[{owner:\"unknown\",data:future::{amount:123.4500,bytes:{{AP8=}}}}],provenance:[origin::\"kept\"]}"
  let original = @ion_text.read_ion(source[:])
  for format in [@data.IonText, @data.IonBinary] {
    let bytes = if format is @data.IonText {
      @utf8.encode(source)
    } else {
      @ion_binary.write_binary_value(original)
    }
    let inspected = @data.inspect_model_source(format, bytes)
    assert_eq(inspected.unit.id, "mep")
    assert_eq(inspected.unit.provenance.length(), 2)
    let retained = inspected.unit.provenance[1]
    guard retained.kind() is Struct([field]) else { fail("import capture") }
    assert_eq(
      @ion_binary.write_binary_value(field.value()),
      @ion_binary.write_binary_value(original),
    )
    assert_true(
      retained.annotations()[0].text() == Some("morphir_model_import"),
    )
    let checkpoint = @data.Registry::new().checkpoint(inspected.unit)
    let restored = @data.Registry::new().open_checkpoint(
      "ion-binary", checkpoint,
    )
    assert_eq(
      restored.provenance.map(@ion_binary.write_binary_value),
      inspected.unit.provenance.map(@ion_binary.write_binary_value),
    )
    let refused = try {
      ignore(@data.Registry::new().encode("morphir-json", inspected.unit))
      false
    } catch {
      @data.Invalid("data.lossy_conversion", _) => true
      _ => false
    }
    assert_true(refused)
  }
}

///|
test "model and checkpoint annotations cannot select the same source" {
  let source = "morphir_model::morphir_pipeline::{ir:{},enrichments:[],provenance:[]}"
  let refused = try {
    ignore(@data.inspect_model_source(@data.IonText, @utf8.encode(source)))
    false
  } catch {
    @data.Invalid("data.ambiguous_envelope", _) => true
    _ => false
  }
  assert_true(refused)
}

///|
test "model source syntax refusal retains the public invalid Ion code" {
  for
    (format, bytes) in [
      (@data.IonText, @utf8.encode("morphir_pipeline::{")),
      (@data.IonBinary, b"\xE0\x01\x00\xEA\xDE"),
    ] {
    let refused = try {
      ignore(@data.inspect_model_source(format, bytes))
      false
    } catch {
      @data.Invalid("invalid_ion", _) => true
      _ => false
    }
    assert_true(refused)
  }
}
