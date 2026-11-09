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

///|
/// A valid plain IR document of exactly `size` bytes: the padding is JSON white
/// space, so it adds no node and no depth.
fn plain_of_size(size : Int32) -> String {
  let document = "{\"formatVersion\":4}"
  document + " ".repeat(size - document.length())
}

///|
/// A session on the model line, activated with a guest that declares the given
/// decoded-byte limit.
fn plain_session(
  wrapped : @worker.WrappedPlainIr,
  decoded~ : Int32 = 8 * 1024 * 1024,
) -> @worker.Conversation raise {
  let claims = @worker.Claims::from_describe(model_result([wrapped.tuple]))
  let offer = @worker.Offer::of_model(claims, wrapped.tuple)
  let (conversation, _) = @worker.Conversation::activate(offer, expected=claims)
  let (conversation, step) = conversation.on(
    answer(1, model_result([wrapped.tuple], decoded~, protocol="0.2.0-draft.1")),
  )
  guard step is Activated(_, ..) else {
    fail("not activated: \{@debug.to_string(step)}")
  }
  conversation
}

///|
fn plain_request(
  wrapped : @worker.WrappedPlainIr,
) -> @worker.GenerateRequest raise {
  @worker.GenerateRequest::new({ "model": wrapped.envelope, "target": "python" })
}

///|
fn refused_text(step : @worker.Step) -> String? {
  match step {
    Finished(EndedEarly(Refused(code=RequestLimit, message~)), ..) =>
      Some(message)
    Answered({ class: Refused(code=RequestLimit, message~), .. }, ..) =>
      Some(message)
    _ => None
  }
}

///|
test "plain IR limit: a document of exactly 4 MiB wraps, and its encoded length is the encoded limit" {
  let limits = @worker.Limits::host().model
  assert_eq(limits.decoded_bytes, 4194304)
  // Base64 makes 4 characters of each 3 bytes, rounded up: 4 * ceil(4194304 / 3).
  assert_eq(limits.encoded_bytes, 5592408)
  let wrapped = wrap_plain(plain_of_size(limits.decoded_bytes))
  guard envelope_part(wrapped, "payload")
    is Object({ "content": String(content), "decodedByteLength": declared, .. }) else {
    fail("no payload")
  }
  assert_eq(content.length(), limits.encoded_bytes)
  assert_eq(declared, Json::number(4194304.0))
}

///|
test "plain IR limit: one byte over 4 MiB is request_limit, and the refusal names the limit" {
  let document = plain_of_size(4194305)
  let refused = try wrap_plain(document) catch {
    @worker.Refusal(code~, message~) => (code, message)
    error => raise error
  } noraise {
    _ => fail("accepted a document over the limit")
  }
  assert_eq(refused.0, RequestLimit)
  assert_true(refused.1.contains("4194305"), msg=refused.1)
  assert_true(refused.1.contains("4194304"), msg=refused.1)
}

///|
test "plain IR limit: a 4 MiB document fits the request frame and goes to the guest" {
  let wrapped = wrap_plain(plain_of_size(4194304))
  let (_, step) = plain_session(wrapped).generate(plain_request(wrapped))
  assert_eq(methods(step), ["morphir.backend.generateModel"])
  let frame = sends(step)[0].size()
  assert_true(frame > 5592408)
  assert_true(frame < @worker.Limits::host().request_bytes)
}

///|
test "plain IR limit: a guest's smaller limit applies at exactly the limit and one byte over" {
  let decoded = 3 * 1024 * 1024
  let at_limit = wrap_plain(plain_of_size(decoded))
  let (_, step) = plain_session(at_limit, decoded~).generate(
    plain_request(at_limit),
  )
  assert_eq(methods(step), ["morphir.backend.generateModel"])
  let over = wrap_plain(plain_of_size(decoded + 1))
  let (_, step) = plain_session(over, decoded~).generate(plain_request(over))
  assert_eq(sends(step).length(), 0)
  guard refused_text(step) is Some(message) else {
    fail("not refused: \{@debug.to_string(step)}")
  }
  assert_true(message.contains("\{decoded}"), msg=message)
}

///|
test "model limit: an envelope at both limits goes, and one byte over each limit is refused by name" {
  let tuple = wrap_plain("{\"formatVersion\":4}").tuple
  let claims = @worker.Claims::from_describe(model_result([tuple]))
  let session = () => {
    let (conversation, _) = @worker.Conversation::activate(
      @worker.Offer::of_model(claims, tuple),
      expected=claims,
    )
    let (conversation, step) = conversation.on(
      answer(
        1,
        model_result([tuple], decoded=8388608, protocol="0.2.0-draft.1"),
      ),
    )
    guard step is Activated(_, ..) else { fail("not activated") }
    conversation
  }
  let request = (decoded : Int32, content : String) => {
    @worker.GenerateRequest::new({
      "model": {
        "payload": { "decodedByteLength": decoded, "content": content },
      },
      "target": "python",
    })
  }
  let (_, step) = session().generate(
    request(4194304, base64_of_length(4194304)),
  )
  assert_eq(methods(step), ["morphir.backend.generateModel"])
  let refusal = (step : @worker.Step) => {
    assert_eq(sends(step).length(), 0)
    guard refused_text(step) is Some(message) else {
      fail("not refused: \{@debug.to_string(step)}")
    }
    message
  }
  // The same 5,592,408 characters of base64 hold one more decoded byte.
  let (_, step) = session().generate(
    request(4194305, base64_of_length(4194305)),
  )
  let message = refusal(step)
  assert_true(message.contains("the effective limit is 4194304"), msg=message)
  // One more character is over the encoded limit.
  let (_, step) = session().generate(
    request(4194304, base64_of_length(4194304) + "A"),
  )
  let message = refusal(step)
  assert_true(message.contains("the effective limit is 5592408"), msg=message)
}

///|
test "request frame: a generate frame on the model line of exactly 6 MiB is made, and one byte more is refused" {
  // The frame is the 27 bytes of `Content-Length: 6291429\r\n\r\n` and the body.
  let shell = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"morphir.backend.generateModel\",\"params\":{\"model\":{},\"target\":\"\"}}"
  let room = 6291456 - 27 - shell.length()
  let request = (length : Int32) => {
    @worker.GenerateRequest::new({ "model": {}, "target": "x".repeat(length) })
  }
  ignore(request(room))
  let refused = try request(room + 1) catch {
    @worker.Refusal(code~, message~) => (code, message)
  } noraise {
    _ => fail("accepted a frame over the limit")
  }
  assert_eq(refused.0, RequestLimit)
  assert_true(refused.1.contains("6291456"), msg=refused.1)
}

///|
test "request frame: a MEP 0.1 generate frame keeps 4 MiB, at the limit and one byte over" {
  let shell = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"morphir.backend.generateModel\",\"params\":{\"ir\":{},\"target\":\"\"}}"
  let room = 4194304 - 27 - shell.length()
  let request = (length : Int32) => {
    @worker.GenerateRequest::new({ "ir": {}, "target": "x".repeat(length) })
  }
  ignore(request(room))
  let refused = try request(room + 1) catch {
    @worker.Refusal(code~, message~) => (code, message)
  } noraise {
    _ => fail("accepted a frame over the limit")
  }
  assert_eq(refused.0, RequestLimit)
  assert_true(refused.1.contains("4194304"), msg=refused.1)
}

///|
test "request frame: a compile frame keeps 4 MiB, at the limit and one byte over" {
  let shell = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"morphir.frontend.compileModel\",\"params\":{\"sources\":\"\"}}"
  let room = 4194304 - 27 - shell.length()
  let request = (length : Int32) => {
    @worker.CompileRequest::new({ "sources": "x".repeat(length) })
  }
  ignore(request(room))
  let refused = try request(room + 1) catch {
    @worker.Refusal(code~, message~) => (code, message)
  } noraise {
    _ => fail("accepted a frame over the limit")
  }
  assert_eq(refused.0, RequestLimit)
  assert_true(refused.1.contains("4194304"), msg=refused.1)
}

///|
test "session limits: every MEP 0.1 session keeps the 4 MiB frame, and the model line has the host's" {
  let host = @worker.Limits::host()
  assert_eq(host.request_bytes, 6291456)
  let process = @worker.WorkerRuntime::Process(platform=X86_64UnknownLinuxGnu, args=[])
  let wasm = @worker.WorkerRuntime::Wasm(abi=Some(ExtismKernelV1))
  let tuple = wrap_plain("{\"formatVersion\":4}").tuple
  for runtime in [process, wasm] {
    assert_eq(host.for_session(Legacy, runtime).request_bytes, 4194304)
    assert_eq(host.for_session(Model([tuple]), runtime).request_bytes, 6291456)
  }
}

///|
test "call budget: the model line has the host's budget, and MEP 0.1 keeps its profile" {
  let host = @worker.Limits::host()
  assert_eq(host.call_instructions, 5000000000L)
  let tuple = wrap_plain("{\"formatVersion\":4}").tuple
  let profile = @worker.ExtismProfile::restricted()
  for
    runtime in [
      @worker.WorkerRuntime::Wasm(abi=Some(MorphirBytesV1)),
      @worker.WorkerRuntime::Wasm(abi=Some(ExtismKernelV1)),
    ] {
    assert_eq(
      host.for_session(Model([tuple]), runtime).call_instructions,
      5000000000L,
    )
    assert_eq(
      host.for_session(Legacy, runtime).call_instructions,
      profile.instructions,
    )
  }
  // A probe runs an artifact that nothing has checked yet.
  assert_eq(host.for_probe().call_instructions, profile.instructions)
  assert_eq(profile.instructions, 1000000000L)
}
