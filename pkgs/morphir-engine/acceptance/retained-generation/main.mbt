///|
fn ion_field(value : @ion.IonValue, name : String) -> @ion.IonValue raise {
  guard value.kind() is Struct(fields) else { fail("expected Ion struct") }
  guard fields.filter(f => f.name().text() == Some(name)) is [field] else {
    fail("missing Ion field " + name)
  }
  field.value()
}

///|
fn handle(source : String) -> String raise {
  let request = @wire.parse_bounded(source, max_depth=512)
  if @wire.string(@wire.field(request, "op")) == "binary" {
    let root = @ion_text.read_ion(
      @wire.string(@wire.field(request, "source"))[:],
    )
    return @ion_binary.write_binary_value(root)
      .to_array()
      .map(b => b.to_int())
      .to_json()
      .stringify()
  }
  let bytes = @wire.array(@wire.field(request, "bytes")).map(value => {
    guard value is Number(n, ..) && n >= 0.0 && n <= 255.0 && n.floor() == n else {
      fail("invalid byte")
    }
    n.to_int().to_byte()
  })
  let symbols = @ion_binary.read_binary_value(Bytes::from_array(bytes)[:])
  let original = @ion_text.read_ion(
    @wire.string(@wire.field(request, "source"))[:],
  )
  let annotations = original.annotations().map(t => t.text().unwrap_or(""))
  let matched = if annotations.contains("morphir_pipeline") {
    ion_field(symbols, "metadata").equals(ion_field(original, "metadata")) &&
    ion_field(symbols, "source_provenance").equals(
      ion_field(original, "provenance"),
    )
  } else {
    guard ion_field(symbols, "source_provenance").kind() is List(provenance) &&
      !provenance.is_empty() else {
      fail("missing MEP source capture")
    }
    ion_field(provenance[provenance.length() - 1], "source_envelope").equals(
      original,
    )
  }
  (
    {
      "preservedSourceContext": matched,
      "unitId": @ion_text.write_ion(ion_field(symbols, "unit_id")),
      "metadata": @ion_text.write_ion(ion_field(symbols, "metadata")),
      "sourceProvenance": @ion_text.write_ion(
        ion_field(symbols, "source_provenance"),
      ),
    } : Json).stringify()
}

///|
extern "js" fn expose(handler : (String) -> String) =
  #| handler => { globalThis.morphirGenerationFixture = handler; }

///|
fn main {
  expose(source => handle(source) catch { error => abort(error.to_string()) })
}
