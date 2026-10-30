///|
test "real frontend metadata survives the MEP node carrier with original names references and origins" {
  let compiled = @frontend.compile_library(
    input(
      "pub fn isReady(flag_value : Bool) -> Bool { flag_value }\npub fn callReady(flag : Bool) -> Bool { isReady(flag) }",
    ),
  )
  let carrier = @ion.IonValue::from_fields([
    @ion.field(
      "owner",
      @ion.IonValue::string("urn:finos:morphir-moonbit:node-metadata:v1"),
    ),
    @ion.field(
      "data",
      @ion.IonValue::from_fields([
        @ion.field("sourceUnitId", @ion.IonValue::string(compiled.unit_id)),
        @ion.field(
          "sourceAnnotations",
          @ion.IonValue::list(
            compiled.annotations.map(a => @ion.IonValue::symbol_token(a)),
          ),
        ),
        @ion.field(
          "nodes",
          @ion.IonValue::list(
            compiled.metadata.map(m => {
              @ion.IonValue::from_fields([
                @ion.field("nodeId", @ion.IonValue::string(m.node_id)),
                @ion.field("data", m.data),
              ])
            }),
          ),
        ),
      ]),
    ),
  ])
  let root = @ion.IonValue::from_fields([
    @ion.field("ir", @ion_json.Ion(@ir_json.to_json(compiled.ir))),
    @ion.field("enrichments", @ion.IonValue::list([carrier])),
    @ion.field("provenance", @ion.IonValue::list(compiled.provenance)),
  ]).with_annotation(@ion.symbol("morphir_model"))
  let bytes = @ion_binary.write_binary_value(root)
  let session = @mep.Session::new()
  let tuple : Json = {
    "operation": "morphir.backend.generateModel",
    "profile": "morphir-model",
    "codec": "ion-binary",
    "envelopeVersion": "0.1.0-draft.1",
    "irVersion": "4.0.0",
  }
  let initialized = session
    .handle({
      "jsonrpc": "2.0",
      "id": 1,
      "method": "morphir.initialize",
      "params": {
        "protocolVersions": ["0.2.0-draft.1"],
        "host": { "name": "test", "version": "1" },
        "modelTransport": {
          "tuples": [tuple],
          "limits": {
            "maxEncodedBytes": 100000,
            "maxDecodedBytes": 65536,
            "maxDepth": 128,
            "maxNodes": 10000,
          },
          "guarantees": [],
        },
      },
    })
    .unwrap()
  assert_true(
    @wire.optional(initialized, "result") is Some(_),
    msg=initialized.stringify(),
  )
  let generated = session
    .handle({
      "jsonrpc": "2.0",
      "id": 2,
      "method": "morphir.backend.generateModel",
      "params": {
        "model": {
          "envelopeVersion": "0.1.0-draft.1",
          "modelId": "transport-identity-is-separate",
          "revision": "r1",
          "irVersion": "4.0.0",
          "profile": "morphir-model",
          "payload": {
            "codec": "ion-binary",
            "layout": "single-document",
            "decodedByteLength": bytes.length(),
            "sha256": @crypto.bytes_to_hex_string(@crypto.sha256(bytes)),
            "content": @base64.encode(bytes[:]),
          },
        },
        "input": tuple,
        "target": "moonbit",
        "contextDigest": "a".repeat(64),
      },
    })
    .unwrap()
  assert_true(
    @wire.optional(generated, "result") is Some(_),
    msg=generated.stringify(),
  )
  let artifacts = @wire.array(
    @wire.field(@wire.field(generated, "result"), "artifacts"),
  )
  let direct = library_generated(compiled)
  for artifact in direct.artifacts {
    let actual = artifacts.filter(a => {
        @wire.field(a, "path") == Json::string(artifact.path)
      })[0]
    match artifact.content {
      Text(text) =>
        assert_eq(@wire.field(actual, "content"), Json::string(text))
      Binary(bytes) =>
        assert_eq(
          @base64.decode(@wire.string(@wire.field(actual, "content"))),
          bytes,
        )
    }
  }
  assert_true(generated.stringify().contains("pub fn isReady"))
  assert_true(generated.stringify().contains("isReady("))
}
