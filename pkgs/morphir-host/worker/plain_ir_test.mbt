///|
fn wrap_plain(document : String) -> @worker.WrappedPlainIr raise {
  let bytes = @utf8.encode(document)
  @worker.WrappedPlainIr::of(bytes, @json.parse(document))
}

///|
fn wrap_refusal(document : String) -> @worker.RefusalCode? raise {
  try wrap_plain(document) catch {
    @worker.Refusal(code~, ..) => Some(code)
    error => raise error
  } noraise {
    _ => None
  }
}

///|
fn envelope_part(wrapped : @worker.WrappedPlainIr, name : String) -> Json {
  match wrapped.envelope {
    Object(fields) => fields.get(name).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
test "plain IR: each format version gives the generate JSON tuple of that version" {
  for
    case in [
      ("{\"formatVersion\":3}", @worker.IrVersion::V3_0_0),
      ("{\"formatVersion\":\"3.0.0\"}", V3_0_0),
      ("{\"formatVersion\":4}", V4_0_0),
      ("{\"formatVersion\":\"4.0.0\"}", V4_0_0),
    ] {
    let (document, version) = case
    let wrapped = wrap_plain(document)
    assert_eq(
      wrapped.tuple,
      @worker.ModelTuple::new(
        GenerateModel,
        MorphirIr,
        MorphirJson,
        V0_1_0Draft1,
        version,
      ),
    )
    assert_eq(
      envelope_part(wrapped, "irVersion"),
      Json::string(version.to_string()),
    )
    assert_eq(envelope_part(wrapped, "profile"), "morphir-ir")
    assert_eq(envelope_part(wrapped, "envelopeVersion"), "0.1.0-draft.1")
  }
}

///|
test "plain IR: the same document gives the same envelope, and the identity comes from its SHA-256" {
  let document = "{\"formatVersion\":3,\"distribution\":[]}"
  let wrapped = wrap_plain(document)
  assert_eq(wrap_plain(document), wrapped)
  let bytes = @utf8.encode(document)
  let digest = @worker.Sha256::of(bytes).to_string()
  assert_eq(
    envelope_part(wrapped, "modelId"),
    Json::string("urn:morphir:plain-ir:sha256:" + digest),
  )
  assert_eq(
    envelope_part(wrapped, "revision"),
    Json::string("sha256:" + digest),
  )
  // Other bytes of the same IR are another model revision.
  let spaced = wrap_plain("{\"formatVersion\": 3,\"distribution\":[]}")
  assert_true(
    envelope_part(spaced, "revision") != envelope_part(wrapped, "revision"),
  )
  assert_eq(spaced.tuple, wrapped.tuple)
}

///|
test "plain IR: the payload holds the exact bytes with their length and digest" {
  // The space and the key order stay, as the bytes of the file do.
  let document = "{ \"b\":1, \"formatVersion\":4 }"
  let bytes = @utf8.encode(document)
  let wrapped = wrap_plain(document)
  assert_eq(envelope_part(wrapped, "payload"), {
    "codec": "morphir-json",
    "layout": "single-document",
    "decodedByteLength": bytes.length(),
    "sha256": @worker.Sha256::of(bytes).to_string(),
    "content": @base64.encode(bytes[:]),
  })
}

///|
test "plain IR: a format version with no model tuple is tuple_unavailable" {
  for
    document in [
      "{\"formatVersion\":5}", "{\"formatVersion\":2}", "{\"formatVersion\":\"4.1.0\"}",
      "{\"formatVersion\":\"3\"}", "{\"formatVersion\":3.5}", "{\"formatVersion\":true}",
      "{\"distribution\":[]}", "[]",
    ] {
    assert_eq(wrap_refusal(document), Some(TupleUnavailable))
  }
}

///|
test "plain IR on the model line: the offer is the file's tuple, which the guest must claim" {
  let wrapped = wrap_plain("{\"formatVersion\":3}")
  let generate_ir3 = wrapped.tuple
  let claims = @worker.Claims::from_describe(model_result([generate_ir3]))
  assert_true(claims.on_model_line())
  assert_eq(
    @worker.Offer::of_model(claims, generate_ir3),
    Model([generate_ir3]),
  )
  let refusal = (claims : @worker.Claims) => {
    try @worker.Offer::of_model(claims, generate_ir3) catch {
      Refusal(code~, ..) => Some(code)
    } noraise {
      _ => None
    }
  }
  // A guest with the tuple of another version.
  let other = @worker.Claims::from_describe(model_result([json_generate_tuple]))
  assert_eq(refusal(other), Some(TupleUnavailable))
  // A guest on both lines with legacy generate and no generate tuple does not
  // fall back to MEP 0.1.
  let both_lines = @worker.Claims::new(
    @worker.ExtensionId::parse("both"),
    @worker.ExtensionVersion::parse("1"),
    protocol_lines=[Mep0_1, Mep0_2Draft1],
    operations=[Generate, CompileModel],
    model_tuples=[json_compile_tuple],
  )
  assert_eq(refusal(both_lines), Some(TupleUnavailable))
  // A legacy guest stays off the model line.
  assert_false(legacy_claims().on_model_line())
  assert_eq(refusal(legacy_claims()), Some(CapabilityUnavailable))
}

///|
test "plain IR on the model line: a session sends the envelope with generateModel" {
  let wrapped = wrap_plain("{\"formatVersion\":3}")
  let claims = @worker.Claims::from_describe(model_result([wrapped.tuple]))
  let offer = @worker.Offer::of_model(claims, wrapped.tuple)
  let (conversation, _) = @worker.Conversation::activate(offer, expected=claims)
  let (conversation, step) = conversation.on(
    answer(1, model_result([wrapped.tuple], protocol="0.2.0-draft.1")),
  )
  guard step is Activated(negotiated, ..) else {
    fail("not activated: \{@debug.to_string(step)}")
  }
  assert_eq(negotiated.tuple, Some(wrapped.tuple))
  let (_, step) = conversation.generate(
    @worker.GenerateRequest::new({
      "model": wrapped.envelope,
      "target": "python",
    }),
  )
  assert_eq(methods(step), ["morphir.backend.generateModel"])
  guard sends(step)[0].json()
    is Object({ "params": Object({ "input": input, "model": model, .. }), .. }) else {
    fail("no model")
  }
  assert_eq(input, wrapped.tuple.to_json())
  assert_eq(model, wrapped.envelope)
}
