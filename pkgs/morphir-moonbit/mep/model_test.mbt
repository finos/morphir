///|
fn rich_tuple(
  codec~ : String = "ion-binary",
  profile~ : String = "morphir-model",
) -> Json {
  {
    "operation": "morphir.backend.generateModel",
    "profile": profile,
    "codec": codec,
    "envelopeVersion": "0.1.0-draft.1",
    "irVersion": "4.0.0",
  }
}

///|
fn rich_offer(
  depth~ : Int32 = 128,
  nodes~ : Int32 = 100000,
  encoded~ : Int32 = 5592408,
  decoded~ : Int32 = 4194304,
) -> Json {
  {
    "tuples": [
      rich_tuple(),
      rich_tuple(codec="morphir-json", profile="morphir-ir"),
    ],
    "limits": {
      "maxEncodedBytes": encoded,
      "maxDecodedBytes": decoded,
      "maxDepth": depth,
      "maxNodes": nodes,
    },
    "guarantees": [],
  }
}

///|
fn initialize_models(
  session : @mep.Session,
  offer~ : Json = rich_offer(),
) -> Json {
  call(session, "morphir.initialize", params={
    "protocolVersions": ["0.2.0-draft.1", "0.1"],
    "host": { "name": "test", "version": "1" },
    "modelTransport": offer,
  })
}

///|
fn model_payload(bytes : Bytes, codec~ : String = "ion-binary") -> Json {
  {
    "codec": codec,
    "layout": "single-document",
    "decodedByteLength": bytes.length(),
    "sha256": @crypto.bytes_to_hex_string(@crypto.sha256(bytes)),
    "content": @base64.encode(bytes[:]),
  }
}

///|
fn model_params(
  bytes : Bytes,
  codec~ : String = "ion-binary",
  profile~ : String = "morphir-model",
) -> Json {
  {
    "model": {
      "envelopeVersion": "0.1.0-draft.1",
      "modelId": "model",
      "revision": "rev-1",
      "irVersion": "4.0.0",
      "profile": profile,
      "payload": model_payload(bytes, codec~),
      "evidence": [],
    },
    "input": rich_tuple(codec~, profile~),
    "target": "moonbit",
    "contextDigest": "a".repeat(64),
  }
}

///|
fn rich_bytes() -> Bytes raise {
  let root = @ion.IonValue::from_fields([
    @ion.Field::new(
      "ir",
      @ion_json.to_ion(@ir_json.to_json(@fixtures.library())),
    ),
    @ion.Field::new(
      "enrichments",
      @ion.IonValue::list([
        @ion_text.read_ion(
          "{owner:\"urn:unknown:future\",data:future::{exact:9007199254740993,amount:123.4500,tag:other::true}}",
        ),
      ]),
    ),
    @ion.Field::new("provenance", @ion.IonValue::list([])),
    @ion.Field::new("future", @ion_text.read_ion("extra::(a b)")),
  ]).with_annotation(@ion.SymbolToken::new("morphir_model"))
  @ion_binary.write_binary_value(root)
}

///|
fn set_json(value : Json, name : String, replacement : Json) -> Unit raise {
  @wire.object(value)[name] = replacement
}

///|
test "retaining an envelope that expands past the response frame budget fails recoverably" {
  let session = @mep.Session::new()
  ignore(initialize_models(session))
  let params = model_params(rich_bytes())
  // This optional text fits in an input frame. Embedding the envelope in a text
  // artifact escapes it again, taking the complete response over 16 MiB.
  set_json(
    @wire.field(params, "model"),
    "future",
    Json::string("\\".repeat(4194304)),
  )
  let request : Json = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "morphir.backend.generateModel",
    "params": params,
  }
  let response = session.receive(@utf8.encode(request.stringify())).unwrap()
  assert_true(
    response.stringify().contains("mep.response_limit"),
    msg=response.stringify(),
  )
  assert_true(
    @utf8.encode(response.stringify()).length() < @mep.MAX_FRAME_BYTES,
  )
  assert_eq(
    @wire.field(@wire.field(call(session, "morphir.ping"), "result"), "ok"),
    Json::boolean(true),
  )
}

///|
test "rich negotiation selects complete tuples and freezes both offers and responses" {
  let session = @mep.Session::new()
  let offer = rich_offer(depth=32, nodes=300, decoded=8192, encoded=16384)
  let initialized = @wire.field(initialize_models(session, offer~), "result")
  assert_eq(
    @wire.field(initialized, "protocolVersion"),
    Json::string("0.2.0-draft.1"),
  )
  let selected = @wire.field(
    @wire.field(initialized, "capabilities"),
    "modelTransport",
  )
  assert_eq(@wire.field(@wire.field(selected, "limits"), "maxDepth"), Json(32))
  let tuple = @wire.array(@wire.field(selected, "tuples"))[0]
  set_json(tuple, "irVersion", Json::string("4.1.0"))
  set_json(@wire.field(offer, "limits"), "maxDepth", Json(1))
  set_json(
    @wire.array(@wire.field(offer, "tuples"))[0],
    "profile",
    Json::string("other"),
  )
  let frozen = @wire.field(
    call(session, "morphir.extension.capabilities"),
    "result",
  )
  let support = @wire.field(frozen, "modelTransport")
  assert_eq(@wire.field(@wire.field(support, "limits"), "maxDepth"), Json(32))
  assert_eq(@wire.array(@wire.field(support, "tuples"))[0], rich_tuple())
  let unavailable = @mep.Session::new()
  let crossed = rich_offer()
  set_json(
    @wire.array(@wire.field(crossed, "tuples"))[0],
    "irVersion",
    Json::string("4.1.0"),
  )
  set_json(
    crossed,
    "tuples",
    Json::array([@wire.array(@wire.field(crossed, "tuples"))[0]]),
  )
  ignore(initialize_models(unavailable, offer=crossed))
  assert_true(
    call(unavailable, "morphir.backend.generateModel")
    .stringify()
    .contains("-32013"),
  )
}

///|
test "exact draft and valid offers are required and failed initialization is recoverable" {
  let session = @mep.Session::new()
  for version in ["0.2", "0.2.0", "0.2.0-draft.2"] {
    assert_true(
      call(session, "morphir.initialize", params={
        "protocolVersions": [version],
        "host": { "name": "t", "version": "1" },
        "modelTransport": rich_offer(),
      })
      .stringify()
      .contains("-32011"),
    )
  }
  for
    offer in [rich_offer(depth=0), rich_offer(nodes=-1), rich_offer(decoded=0)] {
    assert_true(
      initialize_models(session, offer~).stringify().contains("-32602"),
    )
  }
  initialize(session)
  assert_true(
    call(session, "morphir.backend.generateModel")
    .stringify()
    .contains("-32013"),
  )
  assert_true(
    !call(session, "morphir.extension.capabilities")
    .stringify()
    .contains("modelTransport"),
  )
}

///|
test "rich generation retains exact Ion and optional unknown envelope content" {
  let session = @mep.Session::new()
  ignore(initialize_models(session))
  let bytes = rich_bytes()
  let params = model_params(bytes)
  set_json(
    @wire.field(params, "model"),
    "futureEnvelopeMember",
    Json::string("retained"),
  )
  let response = call(session, "morphir.backend.generateModel", params~)
  assert_true(
    @wire.optional(response, "result") is Some(_),
    msg=response.stringify(),
  )
  let generated = @wire.field(response, "result")
  assert_eq(@wire.field(generated, "success"), Json::boolean(true))
  let artifacts = @wire.array(@wire.field(generated, "artifacts"))
  assert_eq(
    @base64.decode(@wire.string(@wire.field(artifacts[0], "content"))),
    bytes,
  )
  assert_true(
    @wire.string(@wire.field(artifacts[1], "content")).contains(
      "futureEnvelopeMember",
    ),
  )
  let direct = @generator.generate({
    ..@generator.Input::new("mep", @fixtures.library()),
    annotations: [@ion.SymbolToken::new("morphir_model")],
  })
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
  let plain = model_params(
    @utf8.encode(@ir_json.write(@fixtures.library())),
    codec="morphir-json",
    profile="morphir-ir",
  )
  assert_eq(
    @wire.field(
      @wire.field(
        call(session, "morphir.backend.generateModel", params=plain),
        "result",
      ),
      "success",
    ),
    Json::boolean(true),
  )
}

///|
test "integrity critical paths and required remote guarantees refuse without poisoning the session" {
  let session = @mep.Session::new()
  ignore(initialize_models(session))
  let bytes = rich_bytes()
  for
    (name, replacement) in [
      ("sha256", Json::string("0".repeat(64))),
      ("decodedByteLength", Json(1)),
      ("content", Json::string("invalid")),
      ("layout", Json::string("chunked")),
      ("codec", Json::string("morphir-json")),
    ] {
    let params = model_params(bytes)
    set_json(
      @wire.field(@wire.field(params, "model"), "payload"),
      name,
      replacement,
    )
    assert_true(
      call(session, "morphir.backend.generateModel", params~)
      .stringify()
      .contains("-32602"),
    )
  }
  let critical = model_params(bytes)
  set_json(@wire.field(critical, "model"), "critical", ["enrichments.future"])
  assert_true(
    call(session, "morphir.backend.generateModel", params=critical)
    .stringify()
    .contains("unknown_critical_path"),
  )
  let required = model_params(bytes)
  set_json(required, "requiredGuarantees", [
    { "guarantee": "urn:test:typed", "scope": "model" },
  ])
  let refused = call(session, "morphir.backend.generateModel", params=required)
  assert_true(
    refused.stringify().contains("unknown_required_guarantee"),
    msg=refused.stringify(),
  )
  assert_eq(
    @wire.field(
      @wire.field(
        call(
          session,
          "morphir.backend.generateModel",
          params=model_params(bytes),
        ),
        "result",
      ),
      "success",
    ),
    Json::boolean(true),
  )
  assert_eq(
    @wire.field(@wire.field(call(session, "morphir.ping"), "result"), "ok"),
    Json::boolean(true),
  )
}

///|
test "aggregate evidence sizes are reserved before decoding the model" {
  let bytes = rich_bytes()
  let params = model_params(bytes)
  let evidence : Json = {
    "guarantee": "urn:test:optional",
    "modelId": "other",
    "modelRevision": "other",
    "contextDigest": "b".repeat(64),
    "scope": "model",
    "producer": "untrusted",
    "evidence": model_payload(b"{\"check\":true}", codec="morphir-json"),
  }
  set_json(@wire.field(params, "model"), "evidence", [evidence])
  let session = @mep.Session::new()
  ignore(initialize_models(session))
  let response = call(session, "morphir.backend.generateModel", params~)
  assert_true(
    @wire.optional(response, "result") is Some(_),
    msg=response.stringify(),
  )
  assert_eq(
    @wire.field(@wire.field(response, "result"), "success"),
    Json::boolean(true),
  )
  let bounded = @mep.Session::new()
  ignore(initialize_models(bounded, offer=rich_offer(decoded=bytes.length())))
  set_json(
    @wire.field(@wire.field(params, "model"), "payload"),
    "sha256",
    Json::string("0".repeat(64)),
  )
  assert_true(
    call(bounded, "morphir.backend.generateModel", params~)
    .stringify()
    .contains("decoded_limit"),
  )
}

///|
test "Ion admission refuses deep input and oversized symbol tables before semantic decoding" {
  let session = @mep.Session::new()
  ignore(initialize_models(session, offer=rich_offer(depth=8, nodes=100)))
  let deep = @ion_binary.write_binary_value(
    @ion_text.read_ion("[".repeat(9) + "0" + "]".repeat(9)),
  )
  assert_true(
    call(session, "morphir.backend.generateModel", params=model_params(deep))
    .stringify()
    .contains("depth_limit"),
  )
  // The ordinary reader consumes symbol tables, so construct a binary datagram
  // with the table as an application value for this hostile-input fixture.
  let table = @ion.IonValue::from_fields([
    @ion.Field::new(
      "symbols",
      @ion.IonValue::list(
        Array::makei(110, i => @ion.IonValue::string("s" + i.to_string())),
      ),
    ),
  ]).with_annotation(@ion.SymbolToken::new("$ion_symbol_table"))
  let oversized = @ion_binary.write_binary([
    table,
    @ion.IonValue::untyped_null(),
  ])
  assert_true(
    call(
      session,
      "morphir.backend.generateModel",
      params=model_params(oversized),
    )
    .stringify()
    .contains("symbol_table_limit"),
  )
  let checkpoint = @ion_binary.write_binary_value(
    @ion_text.read_ion("morphir_pipeline::{profile:\"x\",contract:\"ir-unit\"}"),
  )
  assert_true(
    call(
      session,
      "morphir.backend.generateModel",
      params=model_params(checkpoint),
    )
    .stringify()
    .contains("invalid_profile"),
  )
}

///|
test "node carrier uses explicit node identity and authenticated naming capabilities only" {
  let ir = @metadata_fixtures.input()
  let carrier = @ion.IonValue::from_fields([
    @ion.Field::new(
      "owner",
      @ion.IonValue::string("urn:finos:morphir-moonbit:node-metadata:v1"),
    ),
    @ion.Field::new(
      "data",
      @ion.IonValue::from_fields([
        @ion.Field::new("sourceUnitId", @ion.IonValue::string("sample")),
        @ion.Field::new("sourceAnnotations", @ion.IonValue::list([])),
        @ion.Field::new(
          "nodes",
          @ion.IonValue::list([
            @ion.IonValue::from_fields([
              @ion.Field::new(
                "nodeId",
                @ion.IonValue::string("value:example:main#ready"),
              ),
              @ion.Field::new(
                "data",
                @metadata_fixtures.adapter(
                  "[" + @metadata_fixtures.row("ready") + "]",
                ),
              ),
            ]),
          ]),
        ),
      ]),
    ),
  ])
  let model = @ion.IonValue::from_fields([
    @ion.Field::new("ir", @ion_json.to_ion(@ir_json.to_json(ir))),
    @ion.Field::new("enrichments", @ion.IonValue::list([carrier])),
    @ion.Field::new("provenance", @ion.IonValue::list([])),
  ]).with_annotation(@ion.SymbolToken::new("morphir_model"))
  let params = model_params(@ion_binary.write_binary_value(model))
  let untrusted = @mep.Session::new()
  ignore(initialize_models(untrusted))
  let refused = call(untrusted, "morphir.backend.generateModel", params~)
  assert_true(
    refused.stringify().contains("metadata.provider_unavailable"),
    msg=refused.stringify(),
  )
  let trusted = @mep.Session::new(
    metadata_capabilities=@metadata_fixtures.capabilities(),
  )
  ignore(initialize_models(trusted))
  let generated = call(trusted, "morphir.backend.generateModel", params~)
  assert_eq(
    @wire.field(@wire.field(generated, "result"), "success"),
    Json::boolean(true),
  )
  assert_true(generated.stringify().contains("pub fn wanted()"))
  assert_true(generated.stringify().contains("main_wanted"))
}
