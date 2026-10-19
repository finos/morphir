///|
test "checkpoint inspection keeps the original version apart from migrated IR" {
  let registry = @data.Registry::new()
  // Fixed historical wire documents, not output from a migration under test.
  for
    (source, original) in [
      (
        "{\"formatVersion\":1,\"distribution\":[\"library\",[[\"pricing\"]],[],{\"modules\":[]}]}",
        "1.0.0",
      ),
      (
        "{\"formatVersion\":2,\"distribution\":[\"Library\",[[\"pricing\"]],[],{\"modules\":[]}]}",
        "2.0.0",
      ),
      (
        "{\"formatVersion\":3,\"distribution\":[\"Library\",[[\"pricing\"]],[],{\"modules\":[]}]}",
        "3.0.0",
      ),
      (
        "{\"formatVersion\":\"3.1.0\",\"distribution\":[\"Library\",[[\"pricing\"]],[],{\"modules\":[]}]}",
        "3.1.0",
      ),
      (
        "{\"formatVersion\":\"3.1.7\",\"distribution\":[\"Library\",[[\"pricing\"]],[],{\"modules\":[]}]}",
        "3.1.7",
      ),
      (
        "{\"formatVersion\":\"4.0.9\",\"distribution\":{\"Library\":{\"packageName\":\"pricing\",\"def\":{\"modules\":{}}}}}",
        "4.0.9",
      ),
      (empty_json(), "4.0.0"),
    ] {
    let opened = registry.inspect_checkpoint("morphir-json", Text(source))
    assert_eq(opened.original_format_version.to_release_string(), original)
    assert_eq(opened.unit.distribution.format_version.major, 4U)
    assert_eq(
      opened.unit.distribution.format_version.to_release_string(),
      if original == "4.0.9" {
        "4.0.9"
      } else {
        "4.0.0"
      },
    )
    assert_eq(opened.unit.id, "workbench")
    assert_eq(
      opened.unit.distribution,
      registry.open_checkpoint("morphir-json", Text(source)).distribution,
    )
    // An Ion checkpoint's version comes from its embedded IR, not the current
    // in-memory unit or an envelope/codec version.
    let text = ion_envelope(source)
    let binary = @ion_binary.write_binary_value(@ion_text.read_ion(text[:]))
    for
      (codec, content) in [
        ("ion-text", @data.Text(text)),
        ("ion-binary", @data.Binary(binary)),
      ] {
      let rich = registry.inspect_checkpoint(codec, content)
      assert_eq(rich.original_format_version.to_release_string(), original)
      assert_eq(rich.unit.id, "Pricing")
      assert_eq(rich.unit.distribution, opened.unit.distribution)
    }
  }
}

///|
test "checkpoint inspection preserves strict profile and budget failures" {
  let registry = @data.Registry::new()
  for
    (codec, content, expected) in [
      (
        "morphir-json",
        @data.Text("{\"formatVersion\":99}"),
        "unsupported_format_version_major",
      ),
      (
        "ion-text",
        @data.Text(ion_envelope(empty_json(), extra=",unit_id:\"other\"")),
        "data.duplicate_field",
      ),
      ("ion-text", @data.Binary(b"bad"), "data.encoding_mismatch"),
      ("not-a-checkpoint", @data.Text(empty_json()), "data.encoding_mismatch"),
    ] {
    assert_eq(
      diagnostic(fn() raise {
        ignore(registry.inspect_checkpoint(codec, content))
      }),
      expected,
    )
  }
  let bounded = @data.Registry::new(limits={
    max_bytes: 8,
    max_depth: 128,
    max_values: 100000,
  })
  assert_eq(
    diagnostic(fn() raise {
      ignore(bounded.inspect_checkpoint("morphir-json", Text(empty_json())))
    }),
    "data.byte_limit",
  )
  for
    limits in [
      @data.Limits::{ max_bytes: 4096, max_depth: 0, max_values: 100000, },
      @data.Limits::{ max_bytes: 4096, max_depth: 128, max_values: 1, },
    ] {
    let registry = @data.Registry::new(limits~)
    assert_eq(
      diagnostic(fn() raise {
        ignore(registry.inspect_checkpoint("morphir-json", Text(empty_json())))
      }),
      "data.tree_limit",
    )
  }
}

///|
test "rich checkpoint inspection keeps source version with ordered metadata" {
  let text =
    #|before::morphir_pipeline::after::{
    #|  profile:"morphir-pipeline-v1", contract:"ir-unit", unit_id:"Pricing",
    #|  ir:{formatVersion:"3.1.7",distribution:["Library",[["pricing"]],[],{modules:[]}]},
    #|  metadata:[{node_id:"opaque-node",data:opaque::{huge:9007199254740993, duplicate:1,duplicate:2}}],
    #|  provenance:[origin::"preserved"]
    #|}
  let value = @ion_text.read_ion(text[:])
  let registry = @data.Registry::new()
  for
    (codec, content) in [
      ("ion-text", @data.Text(text)),
      ("ion-binary", @data.Binary(@ion_binary.write_binary_value(value))),
    ] {
    let opened = registry.inspect_checkpoint(codec, content)
    assert_eq(opened.original_format_version.to_release_string(), "3.1.7")
    assert_eq(
      opened.unit.distribution.format_version.to_release_string(),
      "4.0.0",
    )
    assert_eq(opened.unit.annotations.map(a => a.text()), [
      Some("before"),
      Some("morphir_pipeline"),
      Some("after"),
    ])
    assert_eq(opened.unit.metadata.length(), 1)
    assert_eq(opened.unit.metadata[0].node_id, "opaque-node")
    assert_true(
      opened.unit.metadata[0].data.equals(
        @ion_text.read_ion(
          "opaque::{huge:9007199254740993,duplicate:1,duplicate:2}"[:],
        ),
      ),
    )
    assert_eq(opened.unit.provenance.length(), 1)
    assert_true(
      opened.unit.provenance[0].equals(
        @ion_text.read_ion("origin::\"preserved\""[:]),
      ),
    )
  }
}
