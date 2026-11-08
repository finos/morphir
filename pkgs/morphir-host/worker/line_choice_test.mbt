///|
/// The compile tuple of `version` with the JSON codec.
fn compile_json(version : @worker.IrVersion) -> @worker.ModelTuple {
  @worker.ModelTuple::new(
    CompileModel,
    MorphirIr,
    MorphirJson,
    V0_1_0Draft1,
    version,
  )
}

///|
/// The generate tuple of `version` with the JSON codec.
fn generate_json(version : @worker.IrVersion) -> @worker.ModelTuple {
  @worker.ModelTuple::new(
    GenerateModel,
    MorphirIr,
    MorphirJson,
    V0_1_0Draft1,
    version,
  )
}

///|
/// A guest that claims both lines, its model tuples, and the IR versions that
/// it serves on MEP 0.1 for each role. The real claims of avro 0.4.0 are
/// `released(backend=["3", "4"], tuples=[generate_json(V4_0_0)])`, of openapi
/// 0.5.0 the same, and of rust 0.4.0 they also have `frontend=["3", "4"]` with
/// `compile_json(V4_0_0)`.
fn released(
  lines~ : Array[@worker.ProtocolLine] = [Mep0_1, Mep0_2Draft1],
  frontend? : Array[String],
  backend? : Array[String],
  tuples~ : Array[@worker.ModelTuple] = [],
) -> @worker.Claims {
  let operations : Array[@worker.Operation] = tuples.map(tuple => {
    tuple.operation.operation()
  })
  if frontend is Some(_) {
    operations.push(Compile)
  }
  if backend is Some(_) {
    operations.push(Generate)
  }
  @worker.Claims::new(
    @worker.ExtensionId::parse("morphir-avro") catch {
      error => abort(error.to_string())
    },
    @worker.ExtensionVersion::parse("0.4.0") catch {
      error => abort(error.to_string())
    },
    protocol_lines=lines,
    operations~,
    frontend_ir_versions=frontend.unwrap_or([]).map(ir_name),
    backend_ir_versions=backend.unwrap_or([]).map(ir_name),
    model_tuples=tuples,
  )
}

///|
fn avro() -> @worker.Claims {
  released(backend=["3", "4"], tuples=[generate_json(V4_0_0)])
}

///|
fn rust() -> @worker.Claims {
  released(frontend=["3", "4"], backend=["3", "4"], tuples=[
    compile_json(V4_0_0),
    generate_json(V4_0_0),
  ])
}

///|
/// Python 0.5.0 and 0.6.0: both lines, with JSON tuples at both IR versions.
fn python() -> @worker.Claims {
  released(frontend=["3", "4"], backend=["3", "4"], tuples=[
    compile_json(V3_0_0),
    compile_json(V4_0_0),
    generate_json(V3_0_0),
    generate_json(V4_0_0),
  ])
}

///|
/// The MoonBit guest: both lines, IR 4 only, and no legacy compile.
fn moonbit_guest() -> @worker.Claims {
  released(backend=["4"], tuples=[
    ion_tuple,
    compile_json(V4_0_0),
    generate_json(V4_0_0),
  ])
}

///|
fn compile_line(
  claims : @worker.Claims,
  profile? : @worker.ModelProfile,
  codec? : @worker.ModelCodec,
  ir_version? : String,
  model_only~ : Bool = false,
) -> Result[@worker.LineChoice, @worker.RefusalCode] {
  try
    @worker.LineChoice::compile(
      claims,
      profile?,
      codec?,
      ir_version?=ir_version.map(ir_name),
      model_only~,
    )
  catch {
    Refusal(code~, ..) => Err(code)
  } noraise {
    choice => Ok(choice)
  }
}

///|
/// The IR version name that a fallback uses on MEP 0.1, or `None` when the
/// choice is no fallback.
fn fallback_ir(
  choice : Result[@worker.LineChoice, @worker.RefusalCode],
) -> String? {
  guard choice is Ok({ offer: Legacy, fallback: Some(fallback), }) else {
    return None
  }
  fallback.ir_version.map(name => name.to_string())
}

///|
test "compile line: no tuple for the IR version, and a claim on MEP 0.1, falls back" {
  let choice = compile_line(rust(), ir_version="3")
  assert_eq(fallback_ir(choice), Some("3"))
  // The full name of a tuple version denotes the same IR as the claim of its
  // major: an integer format version 3 is exactly 3.0.0.
  assert_eq(fallback_ir(compile_line(rust(), ir_version="3.0.0")), Some("3"))
  // JSON is what MEP 0.1 returns, so a JSON requirement stays satisfied.
  assert_eq(
    fallback_ir(compile_line(rust(), codec=MorphirJson, ir_version="3")),
    Some("3"),
  )
  assert_eq(
    fallback_ir(compile_line(rust(), profile=MorphirIr, ir_version="3")),
    Some("3"),
  )
}

///|
test "compile line: the highest claimed version of a major is the one on MEP 0.1" {
  let claims = released(frontend=["3.2.0", "3.10.0", "4"], tuples=[
    compile_json(V4_0_0),
  ])
  assert_eq(fallback_ir(compile_line(claims, ir_version="3")), Some("3.10.0"))
  // An exact claim comes first.
  assert_eq(
    fallback_ir(compile_line(claims, ir_version="3.2.0")),
    Some("3.2.0"),
  )
}

///|
test "compile line: a request that no line can serve stays tuple_unavailable" {
  // An IR version that the claims do not include.
  assert_eq(compile_line(rust(), ir_version="5"), Err(TupleUnavailable))
  assert_eq(compile_line(rust(), ir_version="3.1.0"), Err(TupleUnavailable))
  assert_eq(compile_line(rust(), ir_version="4.0"), Err(TupleUnavailable))
  // A format or a profile that MEP 0.1 cannot carry.
  assert_eq(
    compile_line(rust(), codec=IonBinary, ir_version="3"),
    Err(TupleUnavailable),
  )
  assert_eq(
    compile_line(rust(), profile=MorphirModel, ir_version="3"),
    Err(TupleUnavailable),
  )
  // A request option that only the model line has, like --frontend-profile.
  assert_eq(
    compile_line(rust(), ir_version="3", model_only=true),
    Err(TupleUnavailable),
  )
  // A guest with no claim on MEP 0.1.
  let no_legacy_line = released(lines=[Mep0_2Draft1], frontend=["3", "4"], tuples=[
    compile_json(V4_0_0),
  ])
  assert_eq(compile_line(no_legacy_line, ir_version="3"), Err(TupleUnavailable))
  // A guest on both lines with no legacy compile method.
  let no_legacy_compile = released(backend=["3", "4"], tuples=[
    compile_json(V4_0_0),
  ])
  assert_eq(
    compile_line(no_legacy_compile, ir_version="3"),
    Err(TupleUnavailable),
  )
  // A guest whose legacy compile claims no IR version shows nothing for IR 3.
  let no_versions = released(frontend=[], tuples=[compile_json(V4_0_0)])
  assert_eq(compile_line(no_versions, ir_version="3"), Err(TupleUnavailable))
}

///|
test "compile line: the refusal says why MEP 0.1 cannot serve the request" {
  let message = (run : () -> @worker.LineChoice raise @worker.Refusal) => {
    try run() catch {
      Refusal(message~, ..) => message
    } noraise {
      _ => ""
    }
  }
  let ion = message(() => {
    @worker.LineChoice::compile(
      rust(),
      codec=IonBinary,
      ir_version=ir_name("3"),
    )
  })
  assert_true(ion.contains("MEP 0.1"), msg=ion)
  let unclaimed = message(() => {
    @worker.LineChoice::compile(rust(), ir_version=ir_name("5"))
  })
  assert_true(unclaimed.contains("MEP 0.1"), msg=unclaimed)
}

///|
test "compile line: a claimed tuple stays on the model line with no fallback" {
  // Python 0.5.0 and 0.6.0 claim the IR 3.0.0 tuples.
  let ir3 = compile_line(python(), ir_version="3")
  guard ir3 is Ok({ offer: Model(tuples), fallback: None, }) else {
    fail("not the model line: \{@debug.to_string(ir3)}")
  }
  assert_true(tuples.contains(compile_json(V3_0_0)))
  // With no requirement, also for a guest with one tuple.
  guard compile_line(rust()) is Ok({ offer: Model(_), fallback: None, }) else {
    fail("not the model line")
  }
  // A legacy guest stays on MEP 0.1, which is no fallback.
  guard compile_line(legacy_claims()) is Ok({ offer: Legacy, fallback: None, }) else {
    fail("not plain MEP 0.1")
  }
}

///|
test "compile line: the MoonBit guest keeps tuple_unavailable for IR 3" {
  assert_eq(
    compile_line(moonbit_guest(), ir_version="3"),
    Err(TupleUnavailable),
  )
}

///|
test "compile line: no compile tuple at all falls back with no requested version" {
  let generate_tuples = released(frontend=["4"], tuples=[generate_json(V4_0_0)])
  let choice = compile_line(generate_tuples)
  guard choice
    is Ok({ offer: Legacy, fallback: Some({ requested: None, .. }), }) else {
    fail("no fallback: \{@debug.to_string(choice)}")
  }
  assert_eq(fallback_ir(choice), None)
  // A JSON requirement that the model tuples do not meet, with an Ion tuple.
  let ion_only = released(frontend=["4"], tuples=[ion_tuple])
  guard compile_line(ion_only, codec=MorphirJson)
    is Ok({ offer: Legacy, fallback: Some(_), }) else {
    fail("no fallback for JSON from an Ion guest")
  }
}

///|
fn plain_route(
  claims : @worker.Claims,
  document : String,
) -> Result[@worker.GenerateChoice, @worker.RefusalCode] raise {
  let ir = @json.parse(document)
  try
    @worker.GenerateChoice::of_plain_ir(claims, @utf8.encode(document), ir)
  catch {
    Refusal(code~, ..) => Err(code)
  } noraise {
    route => Ok(route)
  }
}

///|
test "plain IR: a claimed tuple wraps the file, with no fallback" {
  let document = "{\"formatVersion\":3}"
  let route = plain_route(python(), document)
  let wrapped = wrap_plain(document)
  guard route is Ok(route) else { fail("refused") }
  assert_eq(route.line.offer, Model([generate_json(V3_0_0)]))
  assert_eq(route.line.fallback, None)
  assert_eq(route.tuple, Some(wrapped.tuple))
  assert_eq(route.model, wrapped.envelope)
  // avro 0.4.0 at IR 4 also.
  guard plain_route(avro(), "{\"formatVersion\":4}")
    is Ok({ tuple: Some(tuple), line: { fallback: None, .. }, .. }) else {
    fail("not the model line")
  }
  assert_eq(tuple, generate_json(V4_0_0))
}

///|
test "plain IR: no claimed tuple and a claim on MEP 0.1 sends the document as it is" {
  for document in ["{\"formatVersion\":3}", "{ \"formatVersion\": \"3.0.0\" }"] {
    let route = plain_route(avro(), document)
    guard route
      is Ok(
        {
          line: { offer: Legacy, fallback: Some(fallback), },
          tuple: None,
          model,
        }
      ) else {
      fail("no fallback: \{@debug.to_string(route)}")
    }
    assert_eq(model, @json.parse(document))
    assert_eq(fallback.input, PlainIr)
    assert_eq(fallback.operation, Generate)
    assert_eq(fallback.ir_version.map(name => name.to_string()), Some("3"))
  }
}

///|
test "plain IR: a version with no tuple or no claim stays tuple_unavailable" {
  // The claims of avro do not include IR 5, and the host has no tuple for it.
  assert_eq(plain_route(avro(), "{\"formatVersion\":5}"), Err(TupleUnavailable))
  // The MoonBit guest has no IR 3 claim on MEP 0.1.
  assert_eq(
    plain_route(moonbit_guest(), "{\"formatVersion\":3}"),
    Err(TupleUnavailable),
  )
  // No claim on MEP 0.1, and a format version that names nothing.
  let no_legacy_line = released(lines=[Mep0_2Draft1], backend=["3", "4"], tuples=[
    generate_json(V4_0_0),
  ])
  assert_eq(
    plain_route(no_legacy_line, "{\"formatVersion\":3}"),
    Err(TupleUnavailable),
  )
  assert_eq(
    plain_route(avro(), "{\"formatVersion\":true}"),
    Err(TupleUnavailable),
  )
  assert_eq(plain_route(avro(), "{\"modules\":[]}"), Err(TupleUnavailable))
}

///|
test "plain IR: a claim on MEP 0.1 of a version with no host tuple falls back" {
  let claims = released(backend=["5"], tuples=[generate_json(V4_0_0)])
  guard plain_route(claims, "{\"formatVersion\":5}")
    is Ok({ line: { offer: Legacy, fallback: Some(_), }, .. }) else {
    fail("no fallback")
  }
}

///|
test "plain IR: a legacy guest gets the document as it is, which is no fallback" {
  let claims = released(lines=[Mep0_1], backend=["3"])
  guard plain_route(claims, "{\"formatVersion\":3}")
    is Ok({ line: { offer: Legacy, fallback: None, }, tuple: None, .. }) else {
    fail("not plain MEP 0.1")
  }
}

///|
/// A model envelope around the exact bytes of `document`.
fn json_envelope(
  document : String,
  ir_version~ : String = "3.0.0",
  profile~ : String = "morphir-ir",
  codec~ : String = "morphir-json",
  layout~ : String = "single-document",
  evidence~ : Json = [],
  critical~ : Json = [],
  digest? : String,
  length? : Int32,
) -> Json {
  let bytes = @utf8.encode(document)
  {
    "envelopeVersion": "0.1.0-draft.1",
    "modelId": "urn:example:model",
    "revision": "1",
    "irVersion": ir_version,
    "profile": profile,
    "payload": {
      "codec": codec,
      "layout": layout,
      "decodedByteLength": length.unwrap_or(bytes.length()),
      "sha256": digest.unwrap_or(@worker.Sha256::of(bytes).to_string()),
      "content": @base64.encode(bytes[:]),
    },
    "evidence": evidence,
    "critical": critical,
  }
}

///|
fn envelope_route(
  claims : @worker.Claims,
  envelope : Json,
  tuple : @worker.ModelTuple,
) -> Result[@worker.GenerateChoice, String] {
  try @worker.GenerateChoice::of_envelope(claims, envelope, tuple) catch {
    @worker.Refusal(code~, ..) => Err(code.to_string())
    @worker.InvalidModelEnvelope(_) => Err("input_invalid")
    error => Err(error.to_string())
  } noraise {
    route => Ok(route)
  }
}

///|
test "envelope: a claimed tuple goes as it is, with no fallback" {
  let envelope = json_envelope("{\"formatVersion\":3}")
  guard envelope_route(python(), envelope, generate_json(V3_0_0))
    is Ok(
      { line: { offer: Model(_), fallback: None, }, tuple: Some(_), model, }
    ) else {
    fail("not the model line")
  }
  assert_eq(model, envelope)
}

///|
test "envelope: a JSON envelope falls back with the document of its exact bytes" {
  // The key order and the space are parts of the bytes, not of the JSON tree
  // that MEP 0.1 carries, so the tree must equal the parse of those bytes.
  let document = "{ \"b\":1, \"formatVersion\":3 }"
  let route = envelope_route(
    avro(),
    json_envelope(document),
    generate_json(V3_0_0),
  )
  guard route
    is Ok(
      {
        line: { offer: Legacy, fallback: Some(fallback), },
        tuple: None,
        model,
      }
    ) else {
    fail("no fallback: \{@debug.to_string(route)}")
  }
  assert_eq(model, @json.parse(document))
  assert_eq(fallback.input, ModelEnvelope)
  assert_eq(fallback.operation, Generate)
}

///|
test "envelope: what MEP 0.1 cannot carry stays tuple_unavailable" {
  let document = "{\"formatVersion\":3}"
  let refused = "extension.tuple_unavailable"
  let route = (envelope : Json, tuple : @worker.ModelTuple) => {
    match envelope_route(avro(), envelope, tuple) {
      Ok(_) => ""
      Err(code) => code
    }
  }
  // Ion, and a morphir-model profile with JSON.
  let ion = @worker.ModelTuple::new(
    GenerateModel,
    MorphirModel,
    IonBinary,
    V0_1_0Draft1,
    V3_0_0,
  )
  assert_eq(
    route(
      json_envelope(document, profile="morphir-model", codec="ion-binary"),
      ion,
    ),
    refused,
  )
  let model_json = @worker.ModelTuple::new(
    GenerateModel,
    MorphirModel,
    MorphirJson,
    V0_1_0Draft1,
    V3_0_0,
  )
  assert_eq(
    route(json_envelope(document, profile="morphir-model"), model_json),
    refused,
  )
  // Content that a plain document would lose.
  let tuple = generate_json(V3_0_0)
  assert_eq(route(json_envelope(document, layout="chunks"), tuple), refused)
  assert_eq(
    route(json_envelope(document, evidence=[{ "kind": "source" }]), tuple),
    refused,
  )
  assert_eq(
    route(json_envelope(document, critical=["payload.layout"]), tuple),
    refused,
  )
  // A version that the claims do not include.
  let moonbit = envelope_route(
    moonbit_guest(),
    json_envelope(document),
    generate_json(V3_0_0),
  )
  guard moonbit is Err(code) else { fail("not refused") }
  assert_eq(code, refused)
}

///|
test "envelope: a payload that does not match its declarations is an invalid input" {
  let document = "{\"formatVersion\":3}"
  let tuple = generate_json(V3_0_0)
  let route = (envelope : Json) => {
    match envelope_route(avro(), envelope, tuple) {
      Ok(_) => ""
      Err(code) => code
    }
  }
  assert_eq(
    route(json_envelope(document, digest="0".repeat(64))),
    "input_invalid",
  )
  assert_eq(route(json_envelope(document, length=1)), "input_invalid")
  // Not JSON, and JSON of another IR version than the envelope names.
  assert_eq(route(json_envelope("not json")), "input_invalid")
  assert_eq(route(json_envelope("{\"formatVersion\":4}")), "input_invalid")
  assert_eq(route(json_envelope("{\"modules\":[]}")), "input_invalid")
}

///|
test "fallback: --ir-version checks the version of the document on the fallback line" {
  let route = plain_route(avro(), "{\"formatVersion\":3}")
  guard route is Ok({ line: { fallback: Some(fallback), .. }, .. }) else {
    fail("no fallback")
  }
  assert_true(fallback.serves(ir_name("3")))
  assert_true(fallback.serves(ir_name("3.0.0")))
  assert_false(fallback.serves(ir_name("4")))
  assert_false(fallback.serves(ir_name("3.1.0")))
}

///|
test "fallback diagnostic: a stable code, the extension, the IR version, the line and what to do" {
  guard compile_line(rust(), ir_version="3")
    is Ok({ fallback: Some(fallback), .. }) else {
    fail("no fallback")
  }
  let diagnostic = fallback.diagnostic()
  assert_eq(diagnostic.severity, Warning)
  assert_eq(diagnostic.code, Some("extension.legacy_mep_fallback"))
  assert_eq(diagnostic.location, None)
  assert_eq(
    diagnostic.message,
    "morphir-avro 0.4.0 claims no model tuple for morphir.frontend.compileModel at IR 3.0.0, so this operation runs on legacy MEP 0.1 with morphir.frontend.compile. Update the extension to a release that claims the IR 3.0.0 model tuple, or move to IR 4.0.0.",
  )
  assert_eq(
    diagnostic.data,
    Some({
      "extension": { "id": "morphir-avro", "version": "0.4.0" },
      "operation": "morphir.frontend.compile",
      "protocolVersion": "0.1",
      "requestedIrVersion": "3.0.0",
      "irVersion": "3",
      "input": "sources",
      "modelIrVersions": ["4.0.0"],
    }),
  )
}

///|
test "fallback diagnostic: the envelope says what stays behind, with no other IR to move to" {
  let claims = released(backend=["3"], tuples=[
    @worker.ModelTuple::new(
      CompileModel,
      MorphirIr,
      MorphirJson,
      V0_1_0Draft1,
      V3_0_0,
    ),
  ])
  let route = envelope_route(
    claims,
    json_envelope("{\"formatVersion\":3}"),
    generate_json(V3_0_0),
  )
  guard route is Ok({ line: { fallback: Some(fallback), .. }, .. }) else {
    fail("no fallback: \{@debug.to_string(route)}")
  }
  let diagnostic = fallback.diagnostic()
  assert_eq(
    diagnostic.message,
    "morphir-avro 0.4.0 claims no model tuple for morphir.backend.generateModel at IR 3.0.0, so this operation runs on legacy MEP 0.1 with morphir.backend.generate. The envelope's payload goes as plain IR, with its bytes unchanged; its modelId and revision do not go with it. Update the extension to a release that claims the IR 3.0.0 model tuple.",
  )
  guard diagnostic.data is Some(Object({ "input": input, .. })) else {
    fail("no data")
  }
  assert_eq(input, "model-envelope")
}

///|
test "fallback diagnostic: no requested version names the requirement that no tuple meets" {
  let ion_only = released(frontend=["4"], tuples=[ion_tuple])
  guard compile_line(ion_only, codec=MorphirJson)
    is Ok({ fallback: Some(fallback), .. }) else {
    fail("no fallback")
  }
  assert_eq(
    fallback.diagnostic().message,
    "morphir-avro 0.4.0 claims no model tuple for morphir.frontend.compileModel with morphir-json, so this operation runs on legacy MEP 0.1 with morphir.frontend.compile. Update the extension to a release that claims that model tuple, or move to IR 4.0.0.",
  )
}

///|
test "a fallback session: legacy initialize and method, on the wire as MEP 0.1 has them" {
  let route = plain_route(avro(), "{\"formatVersion\":3}")
  guard route is Ok({ line: { offer, .. }, model, .. }) else { fail("refused") }
  let claims = avro()
  offer.check(claims)
  let (conversation, step) = @worker.Conversation::activate(
    offer,
    expected=claims,
  )
  guard sends(step)[0].json()
    is Object(
      { "params": Object({ "protocolVersions": versions, .. } as params), .. }
    ) else {
    fail("no initialize")
  }
  assert_eq(versions, ["0.1"])
  assert_false(params.contains("modelTransport"))
  // The live worker selects MEP 0.1 and keeps its legacy claims.
  let live = @json.parse(
    (
      #|{"protocolVersion":"0.1","extension":{"id":"morphir-avro","version":"0.4.0"},
      #|"capabilities":{"backend":{"targets":[],"irVersions":["3","4"],"generate":true}}}
    ),
  )
  let (conversation, step) = conversation.on(answer(1, live))
  guard step is Activated(negotiated, ..) else {
    fail("not activated: \{@debug.to_string(step)}")
  }
  assert_eq(negotiated.tuple, None)
  let (_, step) = conversation.generate(
    @worker.GenerateRequest::new({
      "ir": model,
      "target": "avro",
      "options": {},
    }),
  )
  assert_eq(methods(step), ["morphir.backend.generate"])
}
