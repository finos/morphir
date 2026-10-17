///|
async fn rich_process_cases(
  guest : String,
  root : String,
  evidence : String,
) -> Unit {
  let ir = @fixtures.input()
  let root_value = @ion.IonValue::from_fields([
    @ion.Field::new("ir", @ion_json.to_ion(@ir_json.to_json(ir))),
    @ion.Field::new(
      "enrichments",
      @ion.IonValue::list([
        @ion_text.read_ion(
          "{owner:\"urn:morphir:test:unknown\",data:future::{exact:9007199254740993,amount:123.4500}}",
        ),
      ]),
    ),
    @ion.Field::new("provenance", @ion.IonValue::list([])),
  ]).with_annotation(@ion.SymbolToken::new("morphir_model"))
  let bytes = @binary.write_binary_value(root_value)
  let tuple : Json = {
    "operation": "morphir.backend.generateModel",
    "profile": "morphir-model",
    "codec": "ion-binary",
    "envelopeVersion": "0.1.0-draft.1",
    "irVersion": "4.0.0",
  }
  let offer : Json = {
    "tuples": [tuple],
    "limits": {
      "maxEncodedBytes": 100000,
      "maxDecodedBytes": 65536,
      "maxDepth": 128,
      "maxNodes": 10000,
    },
    "guarantees": [],
  }
  let request : Json = {
    "model": {
      "envelopeVersion": "0.1.0-draft.1",
      "modelId": "native-acceptance",
      "revision": "revision-1",
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
  }
  let invalid = @wire.parse_bounded(request.stringify())
  @wire.object(@wire.field(@wire.field(invalid, "model"), "payload"))["sha256"] = Json::string(
    "0".repeat(64),
  )
  let frames : Array[Json] = [
    {
      "jsonrpc": "2.0",
      "id": 1,
      "method": "morphir.extension.describe",
      "params": { "protocolVersions": ["0.2.0-draft.1", "0.1"] },
    },
    {
      "jsonrpc": "2.0",
      "id": 2,
      "method": "morphir.initialize",
      "params": {
        "protocolVersions": ["0.2.0-draft.1"],
        "host": { "name": "acceptance", "version": "1" },
        "modelTransport": offer,
      },
    },
    { "jsonrpc": "2.0", "method": "morphir.initialized" },
    {
      "jsonrpc": "2.0",
      "id": 3,
      "method": "morphir.backend.generateModel",
      "params": invalid,
    },
    {
      "jsonrpc": "2.0",
      "id": 4,
      "method": "morphir.backend.generateModel",
      "params": request,
    },
    {
      "jsonrpc": "2.0",
      "id": 5,
      "method": "morphir.backend.generate",
      "params": { "ir": @ir_json.to_json(ir), "target": "moonbit" },
    },
    { "jsonrpc": "2.0", "id": 6, "method": "morphir.shutdown", "params": {} },
    { "jsonrpc": "2.0", "id": 7, "method": "morphir.ping", "params": {} },
    { "jsonrpc": "2.0", "method": "morphir.exit" },
  ]
  let buffer = Buffer()
  for frame in frames {
    buffer.write_bytes(@mep.encode_frame(frame.stringify())[:])
  }
  let (code, out, err) = exchange(guest, root, buffer.to_bytes())
  assert_eq(code, 0)
  assert_eq(err, "")
  let decoder = @mep.Decoder::new()
  let responses = decoder
    .feed(out)
    .map(body => @wire.parse_bounded(@utf8.decode(body[:])))
  decoder.finish()
  assert_eq(responses.length(), 7)
  assert_eq(
    @wire.field(@wire.field(responses[1], "result"), "protocolVersion"),
    Json::string("0.2.0-draft.1"),
  )
  assert_true(responses[2].stringify().contains("digest_mismatch"))
  let rich = @wire.field(responses[3], "result")
  assert_eq(@wire.field(rich, "success"), Json::boolean(true))
  let artifacts = @wire.array(@wire.field(rich, "artifacts"))
  assert_eq(
    @base64.decode(@wire.string(@wire.field(artifacts[0], "content"))),
    bytes,
  )
  let direct = @generator.generate({
    ..@generator.Input::new("mep", ir),
    annotations: root_value.annotations(),
  })
  assert_eq(artifacts.length(), direct.artifacts.length() + 2)
  for i, artifact in direct.artifacts {
    assert_eq(
      @wire.field(artifacts[i + 2], "path"),
      Json::string(artifact.path),
    )
    match artifact.content {
      Text(text) =>
        assert_eq(@wire.field(artifacts[i + 2], "content"), Json::string(text))
      Binary(bytes) =>
        assert_eq(
          @base64.decode(@wire.string(@wire.field(artifacts[i + 2], "content"))),
          bytes,
        )
    }
  }
  assert_eq(
    @wire.field(@wire.field(responses[4], "result"), "success"),
    Json::boolean(true),
  )
  assert_true(responses[6].stringify().contains("-32014"))
  @fs.write_file(evidence + "/rich-model.ionb", bytes)
  @fs.write_file(evidence + "/rich-model-request.json", request.stringify())
  @fs.write_file(evidence + "/rich-model-offer.json", offer.stringify())
}
