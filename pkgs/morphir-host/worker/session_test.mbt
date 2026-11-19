///|
/// A legacy guest, like the Elm or Python guest: MEP 0.1, compile and
/// generate.
fn legacy_result(
  version~ : String = "2.1.0",
  generate~ : Bool = true,
  protocol? : String,
) -> Json {
  let result : Map[String, Json] = {
    "extension": {
      "id": "morphir-elm",
      "name": "Morphir Elm",
      "version": version,
      "types": ["frontend", "backend"],
    },
    "capabilities": {
      "frontend": {
        "languages": [{ "id": "elm", "fileExtensions": [".elm"] }],
        "irVersions": ["3"],
        "compile": true,
        "incremental": false,
        "fragments": false,
      },
      "backend": {
        "targets": ["typescript"],
        "irVersions": ["3"],
        "generate": generate,
      },
      "streaming": false,
      "incremental": false,
      "cancellation": false,
      "progress": false,
    },
  }
  match protocol {
    Some(version) => result["protocolVersion"] = Json::string(version)
    None => result["protocolVersions"] = ["0.1"]
  }
  Json::object(result)
}

///|
fn legacy_claims() -> @worker.Claims {
  @worker.Claims::from_describe(legacy_result()) catch {
    error => abort(error.to_string())
  }
}

///|
let ion_tuple : @worker.ModelTuple = @worker.ModelTuple::new(
  CompileModel,
  MorphirModel,
  IonBinary,
  V0_1_0Draft1,
  V4_0_0,
)

///|
let json_generate_tuple : @worker.ModelTuple = @worker.ModelTuple::new(
  GenerateModel,
  MorphirIr,
  MorphirJson,
  V0_1_0Draft1,
  V4_0_0,
)

///|
let json_compile_tuple : @worker.ModelTuple = @worker.ModelTuple::new(
  CompileModel,
  MorphirIr,
  MorphirJson,
  V0_1_0Draft1,
  V4_0_0,
)

///|
/// A model guest, like the MoonBit guest, that answers with the given tuples
/// and decoded-byte limit.
fn model_result(
  tuples : Array[@worker.ModelTuple],
  decoded~ : Int32 = 4194304,
  protocol? : String,
) -> Json {
  let result : Map[String, Json] = {
    "extension": {
      "id": "morphir-moonbit",
      "name": "Morphir MoonBit",
      "version": "0.1.0",
      "types": ["frontend", "backend"],
    },
    "capabilities": {
      "frontend": {
        "languages": [{ "id": "moonbit", "fileExtensions": [".mbt"] }],
        "irVersions": ["4.0.0"],
        "compile": false,
        "incremental": false,
        "fragments": false,
      },
      "backend": {
        "targets": ["moonbit"],
        "irVersions": ["4"],
        "generate": true,
      },
      "modelTransport": {
        "tuples": Json::array(tuples.map(tuple => tuple.to_json())),
        "limits": {
          "maxEncodedBytes": 5592408,
          "maxDecodedBytes": decoded,
          "maxDepth": 128,
          "maxNodes": 100000,
        },
        "guarantees": [],
      },
    },
  }
  match protocol {
    Some(version) => result["protocolVersion"] = Json::string(version)
    None => result["protocolVersions"] = ["0.2.0-draft.1", "0.1"]
  }
  Json::object(result)
}

///|
fn model_claims() -> @worker.Claims {
  @worker.Claims::from_describe(model_result([ion_tuple, json_generate_tuple])) catch {
    error => abort(error.to_string())
  }
}

///|
fn answer(id : Int32, result : Json) -> @worker.Event {
  Received(
    @worker.Message::new({ "jsonrpc": "2.0", "id": id, "result": result }),
  )
}

///|
fn guest_error(id : Int32, code : Int32, message : String) -> @worker.Event {
  Received(
    @worker.Message::new({
      "jsonrpc": "2.0",
      "id": id,
      "error": { "code": code, "message": message },
    }),
  )
}

///|
fn sends(step : @worker.Step) -> Array[@worker.Message] {
  match step {
    Exchange(sends~, ..) => sends
    Activated(_, sends~) => sends
    Answered(_, sends~) | BoundedAnswered(_, sends~) => sends
    Finished(_, sends~, ..) => sends
  }
}

///|
fn methods(step : @worker.Step) -> Array[String] {
  sends(step).map(message => {
    match message.json() {
      Object({ "method": String(name), .. }) => name
      _ => "?"
    }
  })
}

///|
fn ended(step : @worker.Step) -> @worker.Ending? {
  match step {
    Finished(EndedEarly(ending), ..) => Some(ending)
    _ => None
  }
}

///|
fn refused_code(step : @worker.Step) -> @worker.RefusalCode? {
  match step {
    Finished(EndedEarly(Refused(code~, ..)), ..) => Some(code)
    Answered({ class: Refused(code~, ..), .. }, ..) => Some(code)
    _ => None
  }
}

///|
fn fault_code(step : @worker.Step) -> @worker.FaultCode? {
  match step {
    Finished(EndedEarly(Failed(Host(code~, ..))), ..) => Some(code)
    _ => None
  }
}

///|
fn compile_request(params~ : Map[String, Json] = {}) -> @worker.CompileRequest {
  @worker.CompileRequest::new(params) catch {
    _ => abort("the compile request was refused")
  }
}

///|
fn generate_request(params : Map[String, Json]) -> @worker.GenerateRequest {
  @worker.GenerateRequest::new(params) catch {
    _ => abort("the generate request was refused")
  }
}

///|
/// Base64 text that decodes to `length` zero bytes.
fn base64_of_length(length : Int32) -> String {
  "AAAA".repeat(length / 3) +
  (match length % 3 {
    1 => "AA=="
    2 => "AAA="
    _ => ""
  })
}

///|
/// A legacy session that is activated and ready for its call.
fn ready_legacy() -> @worker.Conversation {
  let (conversation, _) = @worker.Conversation::activate(
    Legacy,
    expected=legacy_claims(),
  )
  let (conversation, step) = conversation.on(
    answer(1, legacy_result(protocol="0.1")),
  )
  guard step is Activated(_, ..) else { abort("not activated") }
  conversation
}

///|
test "interactive session order: a probe is describe then exit" {
  let (conversation, step) = @worker.Conversation::probe()
  assert_eq(methods(step), ["morphir.extension.describe"])
  assert_true(step is Exchange(awaiting=1, ..))
  let (_, step) = conversation.on(answer(1, legacy_result()))
  assert_eq(methods(step), ["morphir.exit"])
  guard step is Finished(stop=CloseAfterExit, Described(description), ..) else {
    fail("the probe did not describe")
  }
  assert_eq(description.claims, legacy_claims())
}

///|
test "interactive session order: an operation session sends one request at a time" {
  let (conversation, step) = @worker.Conversation::activate(
    Legacy,
    expected=legacy_claims(),
  )
  let order = methods(step)
  let (conversation, step) = conversation.on(
    answer(1, legacy_result(protocol="0.1")),
  )
  order.push_iter(methods(step).iter())
  let (conversation, step) = conversation.compile(compile_request())
  order.push_iter(methods(step).iter())
  assert_true(step is Exchange(awaiting=2, ..))
  let (conversation, step) = conversation.on(
    answer(2, { "success": true, "diagnostics": [] }),
  )
  assert_true(step is Answered({ class: Completed(_), .. }, ..))
  let (conversation, step) = conversation.close()
  order.push_iter(methods(step).iter())
  let (_, step) = conversation.on(answer(3, {}))
  order.push_iter(methods(step).iter())
  assert_true(step is Finished(stop=CloseAfterExit, Closed, ..))
  assert_eq(order, [
    "morphir.initialize", "morphir.initialized", "morphir.frontend.compile", "morphir.shutdown",
    "morphir.exit",
  ])
}

///|
test "early exit: a worker that exits before the operation answer fails the session" {
  let (conversation, _) = ready_legacy().compile(compile_request())
  let (_, step) = conversation.on(ChannelFailed(WorkerClosed))
  assert_eq(fault_code(step), Some(IncompleteSession))
  assert_true(step is Finished(_, stop=Abort(Fault), ..))
  // No answer, so nothing can be published.
  assert_true(!(step is Answered(_, ..)))
}

///|
test "early exit: a worker that stops before the shutdown response fails the session" {
  let (conversation, _) = ready_legacy().close()
  let (_, step) = conversation.on(ChannelFailed(WorkerClosed))
  assert_eq(fault_code(step), Some(IncompleteSession))
}

///|
test "failed initialization stops early with the guest's error" {
  let (conversation, _) = @worker.Conversation::activate(
    Legacy,
    expected=legacy_claims(),
  )
  let (_, step) = conversation.on(guest_error(1, -32011, "unsupported version"))
  assert_eq(methods(step), ["morphir.exit"])
  guard ended(step) is Some(Failed(Guest(code=-32011, message~, ..))) else {
    fail("lost the guest error")
  }
  assert_eq(message, "unsupported version")
}

///|
test "wrong ID: an answer to request 3 with ID 4 fails the session" {
  let (conversation, _) = ready_legacy().close()
  let (_, step) = conversation.on(answer(4, {}))
  assert_eq(fault_code(step), Some(UnexpectedResponse))
  assert_true(step is Finished(_, stop=Abort(Fault), ..))
}

///|
test "response checks: an unsolicited response fails the session" {
  let (conversation, _) = @worker.Conversation::activate(
    Legacy,
    expected=legacy_claims(),
  )
  let (_, step) = conversation.on(answer(0, {}))
  assert_eq(fault_code(step), Some(UnexpectedResponse))
}

///|
test "response checks: a second response fails the session" {
  let (conversation, _) = ready_legacy().compile(compile_request())
  // The worker answers initialize again while the host waits for request 2.
  let (_, step) = conversation.on(answer(1, legacy_result(protocol="0.1")))
  assert_eq(fault_code(step), Some(UnexpectedResponse))
  guard ended(step) is Some(Failed(Host(message~, ..))) else {
    fail("no fault")
  }
  assert_eq(message, "a second response to request 1")
}

///|
test "response checks: a reply needs exactly one of result or error" {
  let (conversation, _) = ready_legacy().compile(compile_request())
  let both = @worker.Message::new({
    "jsonrpc": "2.0",
    "id": 2,
    "result": {},
    "error": { "code": 1, "message": "x" },
  })
  let (_, step) = conversation.on(Received(both))
  assert_eq(fault_code(step), Some(UnexpectedResponse))
  let (conversation, _) = ready_legacy().compile(compile_request())
  let neither = @worker.Message::new({ "jsonrpc": "2.0", "id": 2 })
  let (_, step) = conversation.on(Received(neither))
  assert_eq(fault_code(step), Some(UnexpectedResponse))
}

///|
test "response checks: a notification from the worker is skipped" {
  let (conversation, _) = ready_legacy().compile(compile_request())
  let notice = @worker.Message::new({
    "jsonrpc": "2.0",
    "method": "$/progress",
    "params": {},
  })
  let (conversation, step) = conversation.on(Received(notice))
  assert_true(step is Exchange(sends=[], awaiting=2))
  let (_, step) = conversation.on(answer(2, { "success": true }))
  assert_true(step is Answered({ class: Completed(_), .. }, ..))
}

///|
test "frame limit: a request frame over the transport limit is refused" {
  let (conversation, _) = ready_legacy().compile(compile_request())
  let (_, step) = conversation.on(
    ChannelFailed(
      FrameLimit(direction=Request, declared=4194305L, limit=4194304),
    ),
  )
  guard step is Finished(EndedEarly(Refused(code=RequestLimit, ..)), ..) else {
    fail("not a request limit refusal")
  }
}

///|
test "oversized response: a frame over the response limit fails before its body is read" {
  let (conversation, _) = ready_legacy().compile(compile_request())
  let (_, step) = conversation.on(
    ChannelFailed(
      FrameLimit(direction=Response, declared=16777217L, limit=16777216),
    ),
  )
  assert_eq(fault_code(step), Some(ResponseLimit))
  // The core checks the size of a whole message again.
  let small = @worker.Limits::new(
    request_bytes=4194304,
    response_bytes=64,
    model=@worker.Limits::host().model,
  )
  let (conversation, _) = @worker.Conversation::activate(
    Legacy,
    expected=legacy_claims(),
    limits=small,
  )
  let (_, step) = conversation.on(answer(1, legacy_result(protocol="0.1")))
  assert_eq(fault_code(step), Some(ResponseLimit))
}

///|
test "transport fault: a malformed frame or a closed worker fails the session" {
  let (conversation, _) = ready_legacy().compile(compile_request())
  let (_, step) = conversation.on(ChannelFailed(FrameInvalid("bad header")))
  assert_eq(fault_code(step), Some(FrameInvalid))
  assert_true(step is Finished(_, stop=Abort(Fault), ..))
  let (_, step) = conversation.on(ChannelFailed(WorkerClosed))
  assert_eq(fault_code(step), Some(IncompleteSession))
}

///|
test "transport fault: a failed pipe fails the session as incomplete with its message" {
  let (conversation, _) = ready_legacy().compile(compile_request())
  let message = "the worker's stdout pipe failed: read EIO"
  let (_, step) = conversation.on(ChannelFailed(TransportFailed(message)))
  guard step
    is Finished(
      EndedEarly(Failed(Host(code=IncompleteSession, message=reported))),
      stop=Abort(Fault),
      ..
    ) &&
    reported == message else {
    fail("a failed pipe did not fail the session: \{@debug.to_string(step)}")
  }
}

///|
test "legacy guest: MEP 0.1 calls the legacy methods and never a model method" {
  let (_, step) = @worker.Conversation::activate(
    Legacy,
    expected=legacy_claims(),
  )
  guard sends(step)[0].json() is Object({ "params": params, .. }) else {
    fail("no initialize parameters")
  }
  assert_eq(params, {
    "protocolVersions": ["0.1"],
    "host": { "name": "morphir-moonbit-cli", "version": "0.1.0" },
  })
  let (_, compile) = ready_legacy().compile(compile_request())
  assert_eq(methods(compile), ["morphir.frontend.compile"])
  let (_, generate) = ready_legacy().generate(generate_request({ "ir": {} }))
  assert_eq(methods(generate), ["morphir.backend.generate"])
}

///|
test "version the host did not offer: initialization is refused before any operation" {
  let (conversation, _) = @worker.Conversation::activate(
    Legacy,
    expected=legacy_claims(),
  )
  let (_, step) = conversation.on(
    answer(1, legacy_result(protocol="0.2.0-draft.1")),
  )
  assert_eq(refused_code(step), Some(ProtocolUnavailable))
  assert_eq(methods(step), ["morphir.exit"])
}

///|
test "model tuple negotiation: the host offers every tuple that it supports, in its order" {
  // The worker declares JSON first; the host keeps its own order.
  let claims = @worker.Claims::from_describe(
    model_result([json_compile_tuple, ion_tuple]),
  )
  let offer = @worker.Offer::select(claims, CompileModel)
  assert_eq(
    offer,
    Model([ion_tuple, json_compile_tuple, ion_tuple_ir3, json_tuple_ir3]),
  )
  let (_, step) = @worker.Conversation::activate(offer, expected=claims)
  guard sends(step)[0].json()
    is Object({ "params": Object({ "modelTransport": transport, .. }), .. }) else {
    fail("no model transport offer")
  }
  assert_eq(transport, {
    "tuples": [
      ion_tuple.to_json(),
      json_compile_tuple.to_json(),
      ion_tuple_ir3.to_json(),
      json_tuple_ir3.to_json(),
    ],
    "limits": {
      "maxEncodedBytes": 5592408,
      "maxDecodedBytes": 4194304,
      "maxDepth": 128,
      "maxNodes": 100000,
    },
    "guarantees": [],
  })
}

///|
test "model tuple negotiation: a worker without the default tuple agrees on JSON" {
  // The worker supports only the JSON tuple, like the morphir-gleam guest.
  let claims = @worker.Claims::from_describe(model_result([json_compile_tuple]))
  let offer = @worker.Offer::select(claims, CompileModel)
  assert_eq(
    offer,
    Model([ion_tuple, json_compile_tuple, ion_tuple_ir3, json_tuple_ir3]),
  )
  let (conversation, _) = @worker.Conversation::activate(offer, expected=claims)
  let (conversation, step) = conversation.on(
    answer(1, model_result([json_compile_tuple], protocol="0.2.0-draft.1")),
  )
  guard step is Activated(negotiated, ..) else {
    fail("not activated: \{@debug.to_string(step)}")
  }
  assert_eq(negotiated.offer, offer)
  assert_eq(negotiated.tuple, Some(json_compile_tuple))
  let (_, step) = conversation.compile(compile_request())
  assert_eq(methods(step), ["morphir.frontend.compileModel"])
  guard sends(step)[0].json()
    is Object({ "params": Object({ "output": output, .. }), .. }) else {
    fail("no output tuple")
  }
  assert_eq(output, json_compile_tuple.to_json())
}

///|
test "model tuple negotiation: a worker that supports every offered tuple uses the default" {
  let claims = @worker.Claims::from_describe(
    model_result([ion_tuple, json_compile_tuple]),
  )
  let offer = @worker.Offer::select(claims, CompileModel)
  let (conversation, _) = @worker.Conversation::activate(offer, expected=claims)
  let (conversation, step) = conversation.on(
    answer(
      1,
      model_result([ion_tuple, json_compile_tuple], protocol="0.2.0-draft.1"),
    ),
  )
  guard step is Activated(negotiated, ..) else { fail("not activated") }
  assert_eq(negotiated.tuple, Some(ion_tuple))
  let (_, step) = conversation.compile(compile_request())
  guard sends(step)[0].json()
    is Object({ "params": Object({ "output": output, .. }), .. }) else {
    fail("no output tuple")
  }
  assert_eq(output, ion_tuple.to_json())
}

///|
/// Activates a compile session with `offer` and the worker's `agreed`
/// tuples, then answers `shutdown`. Returns the methods that the host sent
/// after `initialize`, and the refusal code.
fn refused_agreement(
  offer : @worker.Offer,
  agreed : Json,
) -> (Array[String], @worker.RefusalCode?) {
  let claims = @worker.Claims::from_describe(
    model_result([ion_tuple, json_compile_tuple]),
  ) catch {
    error => abort(error.to_string())
  }
  let (conversation, _) = @worker.Conversation::activate(offer, expected=claims)
  let answered : Json = match model_result([], protocol="0.2.0-draft.1") {
    Object(fields) => {
      let fields = fields.copy()
      guard fields.get("capabilities") is Some(Object(capabilities)) &&
        capabilities.get("modelTransport") is Some(Object(transport)) else {
        abort("no model transport")
      }
      let capabilities = capabilities.copy()
      let transport = transport.copy()
      transport["tuples"] = agreed
      capabilities["modelTransport"] = Json::object(transport)
      fields["capabilities"] = Json::object(capabilities)
      Json::object(fields)
    }
    json => json
  }
  let (conversation, first) = conversation.on(answer(1, answered))
  let (_, second) = conversation.on(answer(2, {}))
  (methods(first) + methods(second), refused_code(second))
}

///|
test "model tuple negotiation: no offered tuple supported is tuple_unavailable" {
  let both = @worker.Offer::Model([ion_tuple, json_compile_tuple])
  assert_eq(
    refused_agreement(both, []),
    (["morphir.shutdown", "morphir.exit"], Some(TupleUnavailable)),
  )
}

///|
test "required model tuple: the host offers only the tuples of the required format" {
  let claims = @worker.Claims::from_describe(
    model_result([ion_tuple, json_compile_tuple]),
  )
  // --model-format json requires morphir-ir with morphir-json.
  let required = @worker.Offer::select(claims, CompileModel, codec=MorphirJson)
  assert_eq(required, Model([json_compile_tuple, json_tuple_ir3]))
  assert_eq(
    @worker.Offer::select(claims, CompileModel, codec=IonBinary),
    Model([ion_tuple, ion_tuple_ir3]),
  )
  // A worker that supports only Ion gives an empty agreement.
  assert_eq(
    refused_agreement(required, []),
    (["morphir.shutdown", "morphir.exit"], Some(TupleUnavailable)),
  )
  // Claims without the required tuple refuse it before any worker starts.
  let ion_only = @worker.Claims::from_describe(model_result([ion_tuple]))
  let refused = try
    @worker.Offer::select(ion_only, CompileModel, codec=MorphirJson)
  catch {
    Refusal(code~, ..) => Some(code)
  } noraise {
    _ => None
  }
  assert_eq(refused, Some(TupleUnavailable))
}

///|
test "agreement follows the offer: an agreement out of the host's order is agreement_mismatch" {
  let both = @worker.Offer::Model([ion_tuple, json_compile_tuple])
  assert_eq(
    refused_agreement(both, [json_compile_tuple.to_json(), ion_tuple.to_json()]),
    (["morphir.shutdown", "morphir.exit"], Some(AgreementMismatch)),
  )
  // A tuple that the worker returns twice does not keep the order either.
  assert_eq(
    refused_agreement(both, [ion_tuple.to_json(), ion_tuple.to_json()]),
    (["morphir.shutdown", "morphir.exit"], Some(AgreementMismatch)),
  )
}

///|
test "agreement follows the offer: a tuple that the host did not offer is agreement_mismatch" {
  // --model-format json offers only the JSON tuple; the worker answers Ion.
  let required = @worker.Offer::Model([json_compile_tuple])
  assert_eq(
    refused_agreement(required, [ion_tuple.to_json()]),
    (["morphir.shutdown", "morphir.exit"], Some(AgreementMismatch)),
  )
  // A tuple with a part that the host does not know was not offered either.
  let unknown : Json = {
    "operation": "morphir.frontend.compileModel",
    "profile": "morphir-ir",
    "codec": "cbor",
    "envelopeVersion": "0.1.0-draft.1",
    "irVersion": "4.0.0",
  }
  assert_eq(
    refused_agreement(required, [json_compile_tuple.to_json(), unknown]),
    (["morphir.shutdown", "morphir.exit"], Some(AgreementMismatch)),
  )
}

///|
test "negotiated model transport is not drift: four described tuples, two agreed, smaller limits" {
  // Like the MoonBit guest: generate and compile, each with Ion and JSON.
  let ion_generate_tuple = @worker.ModelTuple::new(
    GenerateModel,
    MorphirModel,
    IonBinary,
    V0_1_0Draft1,
    V4_0_0,
  )
  let described = [
    ion_generate_tuple, json_generate_tuple, ion_tuple, json_compile_tuple,
  ]
  let claims = @worker.Claims::from_describe(model_result(described))
  assert_eq(claims.model_tuples.length(), 4)
  let offer = @worker.Offer::select(claims, CompileModel)
  let (conversation, _) = @worker.Conversation::activate(offer, expected=claims)
  let (_, step) = conversation.on(
    answer(
      1,
      model_result(
        [ion_tuple, json_compile_tuple],
        decoded=1000,
        protocol="0.2.0-draft.1",
      ),
    ),
  )
  guard step is Activated(negotiated, ..) else {
    fail("not activated: \{@debug.to_string(step)}")
  }
  assert_eq(negotiated.tuple, Some(ion_tuple))
  assert_eq(negotiated.limits.model.decoded_bytes, 1000)
}

///|
test "smaller worker limit: a model request is checked against the worker's limit" {
  let claims = model_claims()
  let (conversation, _) = @worker.Conversation::activate(
    Model([json_generate_tuple]),
    expected=claims,
  )
  let (conversation, step) = conversation.on(
    answer(
      1,
      model_result(
        [json_generate_tuple],
        decoded=1000,
        protocol="0.2.0-draft.1",
      ),
    ),
  )
  guard step is Activated(negotiated, ..) else { fail("not activated") }
  assert_eq(negotiated.limits.model.decoded_bytes, 1000)
  let model = (decoded : Int32) => {
    let params : Map[String, Json] = {
      "model": {
        "payload": {
          "decodedByteLength": decoded,
          "content": base64_of_length(decoded),
        },
      },
      "target": "moonbit",
    }
    generate_request(params)
  }
  // 1,500 bytes is below the host's 4 MiB, but above the worker's limit.
  let (_, refused) = conversation.generate(model(1500))
  assert_eq(refused_code(refused), Some(RequestLimit))
  assert_eq(sends(refused).length(), 0)
  let (_, sent) = conversation.generate(model(500))
  assert_eq(methods(sent), ["morphir.backend.generateModel"])
  // The session adds the negotiated tuple as the request's input.
  guard sends(sent)[0].json()
    is Object({ "params": Object({ "input": input, .. }), .. }) else {
    fail("no input tuple")
  }
  assert_eq(input, json_generate_tuple.to_json())
}

///|
test "request too large: a compile request over 4 MiB is refused when it is made" {
  let source = "x".repeat(4 * 1024 * 1024)
  let refused = try @worker.CompileRequest::new({ "sources": source }) catch {
    error => Some(error)
  } noraise {
    _ => None
  }
  guard refused is Some(Refusal(code=RequestLimit, ..)) else {
    fail("accepted a request over 4 MiB")
  }
}

///|
test "limits: a MEP 0.1 WASM guest also has the restricted Extism profile" {
  let host = @worker.Limits::host()
  let process = @worker.WorkerRuntime::Process(platform=X86_64UnknownLinuxGnu, args=[])
  assert_eq(host.for_session(Legacy, process).model, host.model)
  assert_eq(host.for_session(Model([ion_tuple]), Wasm(abi=None)), host)
  let profile = @worker.ExtismProfile::restricted()
  assert_eq(profile.memory_bytes, 256 * 1024 * 1024)
  assert_eq(profile.instructions.count, 1000000000L)
  let wasm = host.for_session(Legacy, Wasm(abi=Some(ExtismKernelV1)))
  assert_eq(wasm.request_bytes, profile.input_bytes)
  assert_eq(wasm.response_bytes, profile.output_bytes)
}

///|
test "claims match: activation returns a session that accepts calls" {
  let (conversation, _) = @worker.Conversation::activate(
    Model([ion_tuple]),
    expected=model_claims(),
  )
  let (conversation, step) = conversation.on(
    answer(1, model_result([ion_tuple], protocol="0.2.0-draft.1")),
  )
  assert_eq(methods(step), ["morphir.initialized"])
  guard step is Activated(negotiated, ..) else { fail("not activated") }
  assert_eq(negotiated.offer, Model([ion_tuple]))
  assert_eq(negotiated.tuple, Some(ion_tuple))
  let (_, step) = conversation.compile(compile_request())
  assert_eq(methods(step), ["morphir.frontend.compileModel"])
}

///|
test "claims drift: another version or a dropped capability fails activation" {
  for
    drift in [
      legacy_result(version="2.2.0", protocol="0.1"),
      legacy_result(generate=false, protocol="0.1"),
    ] {
    let (conversation, _) = @worker.Conversation::activate(
      Legacy,
      expected=legacy_claims(),
    )
    let (conversation, step) = conversation.on(answer(1, drift))
    // shutdown and exit, and no operation.
    assert_eq(methods(step), ["morphir.shutdown"])
    let (_, step) = conversation.on(answer(2, {}))
    assert_eq(methods(step), ["morphir.exit"])
    assert_eq(refused_code(step), Some(ClaimsMismatch))
  }
}

///|
test "unsupported call: a frontend-only session refuses generate and sends nothing" {
  let frontend_only = @worker.Claims::from_describe(
    legacy_result(generate=false),
  )
  let (conversation, _) = @worker.Conversation::activate(
    Legacy,
    expected=frontend_only,
  )
  let (conversation, _) = conversation.on(
    answer(1, legacy_result(generate=false, protocol="0.1")),
  )
  let (conversation, step) = conversation.generate(generate_request({}))
  assert_eq(refused_code(step), Some(CapabilityUnavailable))
  assert_eq(sends(step).length(), 0)
  // The refused call did not use the session: it can still compile.
  let (_, step) = conversation.compile(compile_request())
  assert_eq(methods(step), ["morphir.frontend.compile"])
}

///|
test "session calls: a model session refuses the other model operation" {
  let (conversation, _) = @worker.Conversation::activate(
    Model([ion_tuple]),
    expected=model_claims(),
  )
  let (conversation, _) = conversation.on(
    answer(1, model_result([ion_tuple], protocol="0.2.0-draft.1")),
  )
  let (_, step) = conversation.generate(generate_request({}))
  assert_eq(refused_code(step), Some(CapabilityUnavailable))
  // A request that names another tuple is refused too.
  let (_, step) = conversation.compile(
    compile_request(params={ "output": json_generate_tuple.to_json() }),
  )
  assert_eq(refused_code(step), Some(TupleUnavailable))
}

///|
test "session calls: a second call or a call after close is unavailable" {
  let (conversation, _) = ready_legacy().compile(compile_request())
  let (conversation, _) = conversation.on(answer(2, { "success": true }))
  let second = try conversation.compile(compile_request()) catch {
    SessionUnavailable(_) => None
  } noraise {
    step => Some(step)
  }
  assert_true(second is None)
}

///|
test "source errors: an unsuccessful answer keeps every diagnostic" {
  let diagnostic : Json = {
    "severity": "error",
    "code": "ELM-101",
    "message": "Unknown type Foo",
    "location": {
      "uri": "src/Main.elm",
      "range": {
        "start": { "line": 3, "character": 4 },
        "end": { "line": 3, "character": 7 },
      },
    },
    "data": { "hint": "import Foo" },
  }
  let (conversation, _) = ready_legacy().compile(compile_request())
  let (_, step) = conversation.on(
    answer(2, { "success": false, "diagnostics": [diagnostic] }),
  )
  guard step is Answered({ class: Unsuccessful, diagnostics: [kept], }, ..) else {
    fail("not unsuccessful")
  }
  assert_eq(kept.code, Some("ELM-101"))
  assert_eq(kept.severity, Error)
  assert_eq(kept.message, "Unknown type Foo")
  guard kept.location is Some(location) else { fail("lost the location") }
  assert_eq(location.uri, "src/Main.elm")
  assert_eq(location.start.line, 3L)
  assert_eq(location.end.character, 7L)
  assert_eq(kept.to_json(), diagnostic)
}

///|
test "outcome classes: completed, unsuccessful, failed, refused, deadline and cancelled" {
  let (calling, _) = ready_legacy().compile(compile_request())
  let (_, completed) = calling.on(answer(2, { "success": true }))
  assert_true(completed is Answered({ class: Completed(_), .. }, ..))
  let (_, unsuccessful) = calling.on(answer(2, { "success": false }))
  assert_true(unsuccessful is Answered({ class: Unsuccessful, .. }, ..))
  let (_, guest) = calling.on(guest_error(2, -32602, "bad params"))
  assert_true(
    guest is Answered({ class: Failed(Guest(code=-32602, ..)), .. }, ..),
  )
  let (_, refused) = ready_legacy().compile(
    compile_request(params={ "output": ion_tuple.to_json() }),
  )
  // On MEP 0.1 the request goes out unchanged, so the refusal is shown on a
  // frontend-only session instead.
  assert_true(refused is Exchange(..))
  let (_, deadline) = calling.on(DeadlinePassed)
  assert_eq(ended(deadline), Some(Deadline))
  assert_true(deadline is Finished(_, stop=Abort(Deadline), ..))
  let (_, cancelled) = calling.on(StopRequested)
  assert_eq(ended(cancelled), Some(Cancelled))
  assert_true(cancelled is Finished(_, stop=Abort(Cancelled), ..))
  // Each early end maps to its outcome class.
  let classes : Array[@worker.OutcomeClass[Unit]] = [
    @worker.Ending::Deadline.class(),
    @worker.Ending::Cancelled.class(),
    @worker.Ending::Refused(code=ClaimsMismatch, message="x").class(),
  ]
  assert_eq(classes, [
    Deadline,
    Cancelled,
    Refused(code=ClaimsMismatch, message="x"),
  ])
}

///|
test "probe of a guest that does not describe fails with describe_failed" {
  let (conversation, _) = @worker.Conversation::probe()
  let (_, step) = conversation.on(
    guest_error(1, -32601, "Unknown MEP operation"),
  )
  assert_eq(fault_code(step), Some(DescribeFailed))
  assert_eq(methods(step), ["morphir.exit"])
  let (_, step) = conversation.on(ChannelFailed(WorkerClosed))
  assert_eq(fault_code(step), Some(DescribeFailed))
}

///|
test "offer selection picks the protocol line and tuple from the claims" {
  assert_eq(@worker.Offer::select(legacy_claims(), Compile), Legacy)
  assert_eq(
    @worker.Offer::select(model_claims(), CompileModel, codec=IonBinary),
    Model([ion_tuple, ion_tuple_ir3]),
  )
  // The host offers all of its generate tuples, in its order, though the
  // MoonBit guest claims only the JSON one of IR 4.0.0.
  assert_eq(
    @worker.Offer::select(model_claims(), GenerateModel),
    Model(@worker.ModelOperation::GenerateModel.host_tuples()),
  )
  let refusal = (claims : @worker.Claims, operation : @worker.Operation) => {
    try @worker.Offer::select(claims, operation, codec=IonBinary) catch {
      Refusal(code~, ..) => Some(code)
    } noraise {
      _ => None
    }
  }
  assert_eq(refusal(legacy_claims(), CompileModel), Some(CapabilityUnavailable))
  // The MoonBit guest claims generateModel only with morphir-json.
  assert_eq(refusal(model_claims(), GenerateModel), Some(TupleUnavailable))
  // It claims no legacy compile.
  assert_eq(refusal(model_claims(), Compile), Some(CapabilityUnavailable))
}

///|
test "same guest, two worker kinds: the session sends the same messages" {
  let run = (runtime : @worker.WorkerRuntime) => {
    let limits = @worker.Limits::host().for_session(Model([ion_tuple]), runtime)
    let (conversation, first) = @worker.Conversation::activate(
      Model([ion_tuple]),
      expected=model_claims(),
      limits~,
    )
    let (conversation, second) = conversation.on(
      answer(1, model_result([ion_tuple], protocol="0.2.0-draft.1")),
    )
    let (conversation, third) = conversation.compile(compile_request())
    let (_, fourth) = conversation.on(answer(2, { "success": true }))
    [first, second, third, fourth]
  }
  assert_eq(
    run(Process(platform=Aarch64AppleDarwin, args=[])),
    run(Wasm(abi=Some(MorphirBytesV1))),
  )
}

///|
test "deadlines are 1 to 594,000 ms and 60,000 ms by default" {
  assert_eq(@worker.Deadline::default().ms(), 60000)
  assert_eq(@worker.Deadline::of_ms(594000).ms(), 594000)
  for ms in [0, -1, 594001] {
    guard (Ok(@worker.Deadline::of_ms(ms)) catch { e => Err(e) })
      is Err(InvalidDeadline(_)) else {
      fail("accepted a deadline of \{ms} ms")
    }
  }
}

///|
test "claims drift: a bad shutdown answer keeps claims_mismatch as the reason" {
  let (conversation, _) = @worker.Conversation::activate(
    Legacy,
    expected=legacy_claims(),
  )
  let (conversation, _) = conversation.on(
    answer(1, legacy_result(version="2.2.0", protocol="0.1")),
  )
  let (_, step) = conversation.on(answer(7, {}))
  assert_eq(refused_code(step), Some(ClaimsMismatch))
  assert_true(step is Finished(_, stop=Abort(Fault), ..))
}

///|
/// A model generate session, activated with the worker's own limits.
fn ready_generate() -> @worker.Conversation {
  let (conversation, _) = @worker.Conversation::activate(
    Model([json_generate_tuple]),
    expected=model_claims(),
  )
  let (conversation, step) = conversation.on(
    answer(1, model_result([json_generate_tuple], protocol="0.2.0-draft.1")),
  )
  guard step is Activated(_, ..) else { abort("not activated") }
  conversation
}

///|
fn payload_request(
  decoded : Int32,
  content : String,
) -> @worker.GenerateRequest {
  generate_request({
    "model": { "payload": { "decodedByteLength": decoded, "content": content } },
    "target": "moonbit",
  })
}

///|
test "declared size does not match the payload: the request is refused before it is sent" {
  // "AAAA" decodes to 3 bytes.
  for
    request in [
      payload_request(4, "AAAA"),
      payload_request(2, "AAAA"),
      payload_request(3, "AAA"),
      payload_request(3, "A*AA"),
      payload_request(1, "A==="),
    ] {
    let (_, step) = ready_generate().generate(request)
    assert_eq(refused_code(step), Some(RequestLimit))
    assert_eq(sends(step).length(), 0)
  }
  for request in [payload_request(3, "AAAA"), payload_request(1, "AA==")] {
    let (_, step) = ready_generate().generate(request)
    assert_eq(methods(step), ["morphir.backend.generateModel"])
  }
}

///|
test "declared size does not match the payload: a compiled model fails with response_limit" {
  let (conversation, _) = @worker.Conversation::activate(
    Model([ion_tuple]),
    expected=model_claims(),
  )
  let (conversation, _) = conversation.on(
    answer(1, model_result([ion_tuple], protocol="0.2.0-draft.1")),
  )
  let (calling, _) = conversation.compile(compile_request())
  let compiled = (decoded : Int32, content : String) => {
    let (_, step) = calling.on(
      answer(2, {
        "success": true,
        "model": {
          "payload": { "decodedByteLength": decoded, "content": content },
        },
      }),
    )
    step
  }
  guard compiled(5, "AAAA")
    is Answered({ class: Failed(Host(code=ResponseLimit, ..)), .. }, ..) else {
    fail("accepted a model whose declared length does not match")
  }
  assert_true(compiled(3, "AAAA") is Answered({ class: Completed(_), .. }, ..))
}

///|
test "refusing: a deadline or a stop keeps the refusal and only sets the stop reason" {
  let (conversation, _) = @worker.Conversation::activate(
    Legacy,
    expected=legacy_claims(),
  )
  let (refusing, step) = conversation.on(
    answer(1, legacy_result(version="2.2.0", protocol="0.1")),
  )
  assert_eq(methods(step), ["morphir.shutdown"])
  let (_, deadline) = refusing.on(DeadlinePassed)
  assert_true(deadline is Finished(_, stop=Abort(Deadline), ..))
  assert_eq(refused_code(deadline), Some(ClaimsMismatch))
  let (_, stopped) = refusing.on(StopRequested)
  assert_true(stopped is Finished(_, stop=Abort(Cancelled), ..))
  assert_eq(refused_code(stopped), Some(ClaimsMismatch))
}

///|
test "request IDs: the operation goes out with the ID the session waits for" {
  let (_, step) = ready_legacy().compile(compile_request())
  guard step is Exchange(sends=[message], awaiting~) else {
    fail("the call sent no request")
  }
  guard message.json() is Object({ "id": Number(id, ..), .. }) else {
    fail("the request has no ID")
  }
  assert_eq(id.to_int(), awaiting)
}

///|
/// A guest with both protocol lines: legacy compile and generate for Elm and
/// TypeScript, and model compile and generate tuples.
fn dual_result(
  legacy~ : Bool = true,
  tuples~ : Array[@worker.ModelTuple] = [ion_tuple, json_generate_tuple],
  languages~ : Array[Json] = [{ "id": "elm", "fileExtensions": [".elm"] }],
  targets~ : Array[Json] = ["typescript"],
  multi_document~ : Bool = false,
  protocol? : String,
) -> Json {
  let frontend : Map[String, Json] = {
    "languages": Json::array(languages),
    "irVersions": if legacy {
      ["3"]
    } else {
      []
    },
    "compile": legacy,
  }
  if multi_document {
    frontend["multiDocument"] = true
  }
  let capabilities : Map[String, Json] = {
    "frontend": Json::object(frontend),
    "backend": {
      "targets": Json::array(targets),
      "irVersions": if legacy {
        ["3"]
      } else {
        []
      },
      "generate": legacy,
    },
  }
  if !tuples.is_empty() {
    capabilities["modelTransport"] = {
      "tuples": Json::array(tuples.map(tuple => tuple.to_json())),
      "limits": {
        "maxEncodedBytes": 5592408,
        "maxDecodedBytes": 4194304,
        "maxDepth": 128,
        "maxNodes": 100000,
      },
      "guarantees": [],
    }
  }
  let result : Map[String, Json] = {
    "extension": { "id": "morphir-dual", "version": "1.0.0" },
    "capabilities": Json::object(capabilities),
  }
  match protocol {
    Some(version) => result["protocolVersion"] = Json::string(version)
    None => result["protocolVersions"] = ["0.2.0-draft.1", "0.1"]
  }
  Json::object(result)
}

///|
fn activation_of(
  offer : @worker.Offer,
  live : Json,
  recorded~ : Json = dual_result(),
) -> @worker.Step {
  let expected = @worker.Claims::from_describe(recorded) catch {
    error => abort(error.to_string())
  }
  let (conversation, _) = @worker.Conversation::activate(offer, expected~)
  let (_, step) = conversation.on(answer(1, live))
  step
}

///|
test "claims drift by line: a dual-line guest is compared only within the offered line" {
  let model = "0.2.0-draft.1"
  // Legacy line: the worker leaves out its model transport.
  assert_true(
    activation_of(Legacy, dual_result(tuples=[], protocol="0.1"))
    is Activated(_, ..),
  )
  // Legacy line: a dropped target or language is drift.
  assert_eq(
    methods(activation_of(Legacy, dual_result(targets=[], protocol="0.1"))),
    ["morphir.shutdown"],
  )
  assert_eq(
    methods(activation_of(Legacy, dual_result(languages=[], protocol="0.1"))),
    ["morphir.shutdown"],
  )
  // Model line: the legacy flags and IR versions, and the other tuples, do
  // not count.
  assert_true(
    activation_of(
      Model([ion_tuple]),
      dual_result(legacy=false, tuples=[ion_tuple], targets=[], protocol=model),
    )
    is Activated(_, ..),
  )
  assert_true(
    activation_of(
      Model([json_generate_tuple]),
      dual_result(
        legacy=false,
        tuples=[json_generate_tuple],
        languages=[],
        protocol=model,
      ),
    )
    is Activated(_, ..),
  )
  // Model line: a compileModel session needs the recorded languages with
  // their file extensions; a generateModel session needs the targets.
  assert_eq(
    methods(
      activation_of(
        Model([ion_tuple]),
        dual_result(
          tuples=[ion_tuple],
          languages=[{ "id": "elm", "fileExtensions": [".elm", ".x"] }],
          protocol=model,
        ),
      ),
    ),
    ["morphir.shutdown"],
  )
  assert_eq(
    methods(
      activation_of(
        Model([ion_tuple]),
        dual_result(
          tuples=[ion_tuple],
          languages=[{ "id": "elm", "fileExtensions": [".x"] }],
          protocol=model,
        ),
      ),
    ),
    ["morphir.shutdown"],
  )
  assert_eq(
    methods(
      activation_of(
        Model([json_generate_tuple]),
        dual_result(tuples=[json_generate_tuple], targets=[], protocol=model),
      ),
    ),
    ["morphir.shutdown"],
  )
  // Identity always counts.
  let other : Json = match dual_result(tuples=[ion_tuple], protocol=model) {
    Object(fields) => {
      let fields = fields.copy()
      fields["extension"] = { "id": "morphir-dual", "version": "1.0.1" }
      Json::object(fields)
    }
    json => json
  }
  assert_eq(methods(activation_of(Model([ion_tuple]), other)), [
    "morphir.shutdown",
  ])
}

///|
test "claims drift: a frontend that drops multiDocument is drift on the compile lines" {
  let recorded = dual_result(multi_document=true)
  assert_true(
    activation_of(
      Legacy,
      dual_result(multi_document=true, protocol="0.1"),
      recorded~,
    )
    is Activated(_, ..),
  )
  assert_eq(
    methods(activation_of(Legacy, dual_result(protocol="0.1"), recorded~)),
    ["morphir.shutdown"],
  )
  assert_eq(
    methods(
      activation_of(
        Model([ion_tuple]),
        dual_result(tuples=[ion_tuple], protocol="0.2.0-draft.1"),
        recorded~,
      ),
    ),
    ["morphir.shutdown"],
  )
  // A generateModel session does not compile, so the flag does not count.
  assert_true(
    activation_of(
      Model([json_generate_tuple]),
      dual_result(tuples=[json_generate_tuple], protocol="0.2.0-draft.1"),
      recorded~,
    )
    is Activated(_, ..),
  )
}

///|
test "claims drift by line: an offer from a stale record fails before initialize" {
  let stale = @worker.ModelTuple::new(
    CompileModel,
    MorphirIr,
    MorphirJson,
    V0_1_0Draft1,
    V4_0_0,
  )
  let refused = try @worker.Offer::Model([stale]).check(model_claims()) catch {
    Refusal(code~, ..) => Some(code)
  } noraise {
    _ => None
  }
  assert_eq(refused, Some(ClaimsMismatch))
}

///|
test "offer selection offers only the host's tuples, whatever the worker declares" {
  let json_model = @worker.ModelTuple::new(
    CompileModel,
    MorphirModel,
    MorphirJson,
    V0_1_0Draft1,
    V4_0_0,
  )
  let ion_ir = @worker.ModelTuple::new(
    CompileModel,
    MorphirIr,
    IonBinary,
    V0_1_0Draft1,
    V4_0_0,
  )
  // The host supports Ion with morphir-model and JSON with morphir-ir.
  assert_eq(@worker.ModelOperation::CompileModel.host_tuples(), [
    ion_tuple, json_compile_tuple, ion_tuple_ir3, json_tuple_ir3,
  ])
  let claims = @worker.Claims::from_describe(
    model_result([json_model, json_compile_tuple, ion_ir]),
  )
  assert_eq(
    @worker.Offer::select(claims, CompileModel),
    Model([ion_tuple, json_compile_tuple, ion_tuple_ir3, json_tuple_ir3]),
  )
  assert_eq(
    @worker.Offer::select(claims, CompileModel, profile=MorphirIr),
    Model([json_compile_tuple, json_tuple_ir3]),
  )
  // A worker that claims only tuples that the host does not support is
  // refused before any worker starts.
  let other = @worker.Claims::from_describe(model_result([json_model, ion_ir]))
  let refused = try @worker.Offer::select(other, CompileModel) catch {
    Refusal(code~, ..) => Some(code)
  } noraise {
    _ => None
  }
  assert_eq(refused, Some(TupleUnavailable))
}

///|
test "offer check: an empty model offer or one of two operations is refused" {
  let refusal = (offer : @worker.Offer) => {
    try offer.check(model_claims()) catch {
      Refusal(code~, ..) => Some(code)
    } noraise {
      _ => None
    }
  }
  assert_eq(refusal(Model([])), Some(TupleUnavailable))
  assert_eq(
    refusal(Model([ion_tuple, json_generate_tuple])),
    Some(TupleUnavailable),
  )
  // An offer with one recorded tuple among others passes.
  assert_eq(refusal(Model([ion_tuple, json_compile_tuple])), None)
}

///|
test "diagnostics: a malformed diagnostic keeps the valid ones and is named" {
  let valid : Json = { "severity": "warning", "message": "unused import" }
  let (calling, _) = ready_legacy().compile(compile_request())
  let (_, step) = calling.on(
    answer(2, {
      "success": true,
      "diagnostics": [valid, { "severity": "loud" }, valid],
    }),
  )
  guard step is Answered({ class: Completed(_), diagnostics, }, ..) else {
    fail("a malformed diagnostic failed the call")
  }
  assert_eq(diagnostics.length(), 3)
  assert_eq(diagnostics[0].to_json(), valid)
  assert_eq(diagnostics[1].to_json(), valid)
  let named = diagnostics[2]
  assert_eq(named.severity, Warning)
  assert_eq(named.code, Some("extension.unexpected_response"))
  assert_true(named.message.contains("diagnostic 1"))
}

///|
test "guest fault: each WASM guest fault ends the session with its own class and code" {
  let (conversation, _) = ready_legacy().compile(compile_request())
  let failed = (fault : @worker.GuestFault) => {
    let (_, step) = conversation.on(ChannelFailed(GuestFailed(fault)))
    guard step is Finished(EndedEarly(ending), stop=Abort(reason), ..) else {
      fail("a guest fault did not end the session: \{@debug.to_string(step)}")
    }
    (ending, reason)
  }
  guard failed(Trap("unreachable"))
    is (Failed(Host(code=GuestTrap, message~)), Fault) &&
    message.contains("unreachable") else {
    fail("a trap did not fail the session with guest_trap")
  }
  guard failed(MemoryLimit("memory.grow past 4096 pages"))
    is (Failed(Host(code=MemoryLimit, message~)), Fault) &&
    message.contains("4096") else {
    fail("a refused growth did not fail the session with memory_limit")
  }
  assert_true(failed(CallDeadline) is (Deadline, _))
  assert_true(
    failed(BudgetExhausted) is (Failed(Host(code=BudgetExhausted, ..)), Fault),
  )
  guard failed(Failure("handle returned -1"))
    is (Failed(Host(code=IncompleteSession, message~)), Fault) &&
    message.contains("handle returned -1") else {
    fail("a guest failure did not keep its message")
  }
}

///|
test "channel refusal: a worker that refused to serve ends the session as refused" {
  let (conversation, _) = @worker.Conversation::probe()
  let (_, step) = conversation.on(
    ChannelFailed(
      Refused(
        code=WorkerRuntimeMismatch,
        message="the worker runtime is build b; the host is build a",
      ),
    ),
  )
  guard step
    is Finished(
      EndedEarly(Refused(code=WorkerRuntimeMismatch, message~)),
      stop=Abort(Fault),
      ..
    ) else {
    fail("a refusal did not end the session: \{@debug.to_string(step)}")
  }
  assert_true(message.contains("build b"))
}

///|
// The tuple and limits are the fixed v4 offer in the parent bounded-generation
// transcript. The probe description uses the same guest and claimed capability.
fn bounded_probe_description(
  tuple : Map[String, Json],
  protocol~ : String = "0.2.0-draft.2",
) -> Json {
  {
    "claimsVersion": "0.1.0-draft.2",
    "protocolVersions": [protocol],
    "extension": {
      "id": "org.finos.morphir.orders",
      "name": "Orders generator",
      "version": "0.1.0",
      "types": ["backend"],
    },
    "capabilities": {
      "backend": {
        "targets": ["text"],
        "irVersions": ["4.0.0"],
        "generate": false,
      },
      "modelAccess": {
        "tuples": [Json::object(tuple)],
        "limits": {
          "maxFrameBytes": 32768,
          "maxEncodedBytesPerExchange": 8192,
          "maxDecodedBytesPerExchange": 6144,
          "maxDocumentsPerBatch": 8,
          "maxDepth": 64,
          "maxNodes": 256,
          "maxDiagnosticsPerExchange": 16,
          "maxOutstandingRequests": 8,
          "maxGuestStateBytes": 1048576,
          "maxHostCacheBytes": 1048576,
          "maxArtifactChunkBytes": 4096,
          "maxArtifactBytes": 4294967296,
          "maxTotalArtifactBytes": 4294967296,
          "maxSessionDiskBytes": 8589934592,
          "maxSessionWorkUnits": 4096,
          "maxRounds": 16,
          "maxCallMilliseconds": 500,
          "maxSessionMilliseconds": 2500,
        },
      },
    },
    "critical": ["capabilities.modelAccess"],
  }
}

///|
fn bounded_probe_tuple() -> Map[String, Json] {
  {
    "protocolVersion": "0.2.0-draft.2",
    "accessVersion": "0.1.0-draft.1",
    "operation": "morphir.backend.generateModel",
    "irVersion": "4.0.0",
    "profile": "morphir-ir",
    "codec": "morphir-json",
    "layout": "document-tree",
    "contextualEncoding": "plain",
  }
}

///|
test "bounded probe decodes the exact draft.2 capability and keeps ordinary generate unclaimed" {
  let (conversation, probe) = @worker.Conversation::probe()
  let result = bounded_probe_description(bounded_probe_tuple())
  let packet = @worker.Message::new({
    "jsonrpc": "2.0",
    "id": 1,
    "result": result,
  })
  let received = @worker.Message::parse(packet.to_bytes())
  let (_, step) = conversation.on(Received(received))
  guard step is Finished(stop=CloseAfterExit, Described(description), ..) else {
    fail("the probe did not accept the fixed draft.2 description")
  }
  let offered = sends(probe)[0].json()
  guard offered is Object(fields) &&
    fields.get("params") is Some(Object(params)) &&
    params.get("protocolVersions") is Some(Array(versions)) else {
    fail("the probe did not send protocol versions")
  }
  assert_eq(versions, ["0.2.0-draft.2", "0.2.0-draft.1", "0.1"])
  assert_eq(description.claims.protocol_lines.map(line => line.to_string()), [
    "0.2.0-draft.2",
  ])
  assert_eq(
    description.claims.backend_ir_versions.map(version => version.to_string()),
    ["4.0.0"],
  )
  let expected = bounded_probe_description(bounded_probe_tuple())
  guard expected is Object(fields) &&
    fields.get("capabilities") is Some(Object(capabilities)) else {
    fail("the fixed description has no capabilities")
  }
  assert_eq(
    Some(description.claims.model_access.unwrap().to_json()),
    capabilities.get("modelAccess"),
  )
  assert_false(description.claims.offers(Generate))
  assert_eq(methods(step), ["morphir.exit"])
}

///|
test "bounded probe refuses missing tuple members, adjacent drafts and integer IR spellings" {
  for
    (key, invalid) in [
      ("contextualEncoding", Json::null()),
      ("accessVersion", Json::string("0.1.0-draft.2")),
      ("protocolVersion", Json::string("0.2.0-draft.1")),
      ("irVersion", Json::string("4")),
    ] {
    let tuple = bounded_probe_tuple()
    if invalid == Json::null() {
      tuple.remove(key)
    } else {
      tuple[key] = invalid
    }
    let (conversation, _) = @worker.Conversation::probe()
    let (_, step) = conversation.on(answer(1, bounded_probe_description(tuple)))
    assert_false(step is Finished(Described(_), ..))
  }
  let (conversation, _) = @worker.Conversation::probe()
  let (_, step) = conversation.on(
    answer(
      1,
      bounded_probe_description(bounded_probe_tuple(), protocol="0.2.0-draft.1"),
    ),
  )
  assert_false(step is Finished(Described(_), ..))
}

///|
fn test_support(description : Json) -> Json raise {
  guard description is Object(fields) &&
    fields.get("capabilities") is Some(Object(capabilities)) &&
    capabilities.get("modelAccess") is Some(Object(support)) else {
    fail("the fixed description has no bounded access")
  }
  Json::object(support)
}

///|
test "bounded tuple intersection retains host order and exact wide byte ceilings" {
  let plain = bounded_probe_tuple()
  let yaml = bounded_probe_tuple()
  yaml["codec"] = "morphir-yaml"
  let contextual = bounded_probe_tuple()
  contextual["contextualEncoding"] = "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json"

  let host_description = bounded_probe_description(plain)
  guard test_support(host_description) is Object(host_support) else {
    fail("expected a fixed access offer")
  }
  host_support["tuples"] = [
    Json::object(yaml),
    Json::object(plain),
    Json::object(contextual),
  ]

  let guest_description = bounded_probe_description(plain)
  guard test_support(guest_description) is Object(guest_support) &&
    guest_support.get("limits") is Some(Object(guest_limits)) else {
    fail("expected fixed guest access limits")
  }
  guest_support["tuples"] = [Json::object(plain), Json::object(yaml)]
  guest_limits["maxArtifactBytes"] = Json::number(2147483649.0)
  guest_limits["maxSessionWorkUnits"] = Json::number(64)

  let host = @worker.Claims::from_describe(host_description).model_access.unwrap()
  let guest = @worker.Claims::from_describe(guest_description).model_access.unwrap()
  let agreement = host.intersect(guest)
  assert_eq(agreement.tuples().map(tuple => tuple.to_json()), [
    Json::object(yaml),
    Json::object(plain),
  ])
  assert_eq(agreement.limits.to_json(), Json::object(guest_limits))
  assert_true(agreement.limits.at_most(host.limits))
  assert_false(host.limits.at_most(agreement.limits))
}

///|
test "bounded probe refuses duplicate offers and limits outside exact JSON integer range" {
  let duplicate = bounded_probe_description(bounded_probe_tuple())
  guard test_support(duplicate) is Object(support) else {
    fail("expected a fixed access offer")
  }
  let tuple = Json::object(bounded_probe_tuple())
  support["tuples"] = [tuple, tuple]
  let (probe, _) = @worker.Conversation::probe()
  let (_, step) = probe.on(answer(1, duplicate))
  assert_false(step is Finished(Described(_), ..))

  for
    invalid in [
      Json::number(0),
      Json::number(1.5),
      Json::number(9007199254740992.0),
    ] {
    let description = bounded_probe_description(bounded_probe_tuple())
    guard test_support(description) is Object(support) &&
      support.get("limits") is Some(Object(limits)) else {
      fail("expected a fixed access offer")
    }
    limits["maxArtifactBytes"] = invalid
    let (probe, _) = @worker.Conversation::probe()
    let (_, step) = probe.on(answer(1, description))
    assert_false(step is Finished(Described(_), ..))
  }
}

///|
fn bounded_activation_offer(
  tuples : Array[Json],
  frame_bytes~ : Int32 = 32768,
) -> Json raise {
  let description = bounded_probe_description(bounded_probe_tuple())
  let access = test_support(description)
  guard access is Object(fields) && fields.get("limits") is Some(Object(limits)) else {
    fail("the fixed activation has no limits")
  }
  fields["tuples"] = Json::array(tuples)
  limits["maxFrameBytes"] = Json::number(frame_bytes.to_double())
  access
}

///|
fn bounded_activation_reply(
  access : Json?,
  protocol~ : String = "0.2.0-draft.2",
) -> Json raise {
  let description = bounded_probe_description(bounded_probe_tuple())
  guard description is Object(fields) &&
    fields.get("capabilities") is Some(Object(capabilities)) else {
    fail("the fixed activation has no capabilities")
  }
  fields.remove("protocolVersions")
  fields.remove("claimsVersion")
  fields.remove("critical")
  fields["protocolVersion"] = Json::string(protocol)
  match access {
    Some(value) => capabilities["modelAccess"] = value
    None => capabilities.remove("modelAccess")
  }
  description
}

///|
fn bounded_yaml_tuple() -> Json {
  let yaml = bounded_probe_tuple()
  yaml["codec"] = "morphir-yaml"
  Json::object(yaml)
}

///|
fn bounded_activation_claims() -> @worker.Claims raise {
  let plain = Json::object(bounded_probe_tuple())
  let description = bounded_probe_description(bounded_probe_tuple())
  guard test_support(description) is Object(access) else {
    fail("the fixed description has no bounded offer")
  }
  access["tuples"] = [plain, bounded_yaml_tuple()]
  @worker.Claims::from_describe(description)
}

///|
test "bounded activation emits the complete host offer and admits only the live ordered agreement" {
  let yaml = bounded_yaml_tuple()
  let plain = Json::object(bounded_probe_tuple())
  let host = @model_access.Support::from_json(
    bounded_activation_offer([yaml, plain]),
  )
  let claim = bounded_activation_claims()
  let offer : @worker.Offer = Bounded(host)
  let (conversation, first) = @worker.Conversation::activate(
    offer,
    expected=claim,
    limits=@worker.Limits::new(
      request_bytes=20000,
      response_bytes=24000,
      model=@worker.Limits::host().model,
    ),
  )
  assert_eq(methods(first), ["morphir.initialize"])
  let initialize = sends(first)[0].json()
  guard initialize is Object(fields) &&
    fields.get("params") is Some(Object(params)) else {
    fail("initialize does not have object parameters")
  }
  assert_eq(
    params.get("protocolVersions"),
    Some(Json::array(["0.2.0-draft.2"])),
  )
  assert_eq(params.get("modelTransport"), None)
  assert_eq(
    params.get("modelAccess"),
    Some(bounded_activation_offer([yaml, plain], frame_bytes=20000)),
  )

  let live = bounded_activation_offer([yaml, plain], frame_bytes=12000)
  let (session, step) = conversation.on(
    answer(1, bounded_activation_reply(Some(live))),
  )
  guard step is Activated(negotiated, ..) else {
    fail("the worker did not activate")
  }
  assert_eq(methods(step), ["morphir.initialized"])
  assert_eq(negotiated.model_access.map(value => value.to_json()), Some(live))
  assert_eq(negotiated.tuple, None)
  assert_eq(session.limits().request_bytes, 12000)
  assert_eq(session.limits().response_bytes, 12000)

  let (_, unbounded) = session.generate(
    generate_request({ "target": "text", "ir": {} }),
  )
  guard unbounded
    is Answered({ class: Refused(code=CapabilityUnavailable, ..), .. }, ..) else {
    fail("a bounded session allowed an unbounded call")
  }
  assert_eq(sends(unbounded).length(), 0)
}

///|
test "bounded activation refuses an unsupported live tuple before sending initialized" {
  let plain = Json::object(bounded_probe_tuple())
  let yaml = bounded_yaml_tuple()
  let other = bounded_probe_tuple()
  other["irVersion"] = "3.1.0"
  let other = Json::object(other)
  let host = @model_access.Support::from_json(
    bounded_activation_offer([yaml, plain, other]),
  )
  let claim = bounded_activation_claims()
  let offer : @worker.Offer = Bounded(host)
  for
    live in [
      None,
      Some(bounded_activation_offer([])),
      Some(bounded_activation_offer([plain, yaml])),
      Some(bounded_activation_offer([other])),
      Some(bounded_activation_offer([yaml], frame_bytes=32769)),
    ] {
    let (session, _) = @worker.Conversation::activate(offer, expected=claim)
    let (session, step) = session.on(answer(1, bounded_activation_reply(live)))
    assert_eq(methods(step), ["morphir.shutdown"])
    assert_eq(session.negotiated(), None)
    let (_, end) = session.on(answer(2, {}))
    guard end is Finished(EndedEarly(Refused(..)), ..) else {
      fail("a refusal did not settle as a refused activation")
    }
    assert_eq(methods(end), ["morphir.exit"])
  }
  let (session, _) = @worker.Conversation::activate(offer, expected=claim)
  let (_, step) = session.on(
    answer(1, bounded_activation_reply(None, protocol="0.2.0-draft.1")),
  )
  guard step is Finished(EndedEarly(Refused(code=ProtocolUnavailable, ..)), ..) else {
    fail("an earlier draft was allowed to admit bounded access")
  }
  assert_eq(methods(step), ["morphir.exit"])
}

///|
test "bounded offer preflight requires a whole recorded tuple" {
  let plain = bounded_probe_tuple()
  plain["irVersion"] = "3.1.0"
  let offer : @worker.Offer = Bounded(
    @model_access.Support::from_json(
      bounded_activation_offer([Json::object(plain)]),
    ),
  )
  let claims = bounded_activation_claims()
  let code = try {
    offer.check(claims)
    None
  } catch {
    @worker.Refusal(code~, ..) => Some(code)
  }
  assert_eq(code, Some(TupleUnavailable))
  let admitted : @worker.Offer = Bounded(
    @model_access.Support::from_json(
      bounded_activation_offer([bounded_yaml_tuple()]),
    ),
  )
  admitted.check(claims)
}

///|
test "bounded shutdown counts the serialized frame header at the inclusive ceiling" {
  let frame = 1000
  let access = bounded_activation_offer(
    [Json::object(bounded_probe_tuple())],
    frame_bytes=frame,
  )
  let (conversation, _) = @worker.Conversation::activate(
    Bounded(@model_access.Support::from_json(access)),
    expected=bounded_activation_claims(),
  )
  let (ready, step) = conversation.on(
    answer(1, bounded_activation_reply(Some(access))),
  )
  assert_true(step is Activated(_, ..))
  let (closing, _) = ready.close()
  let body = "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{}}"
  // Both replies have a three-digit Content-Length. Only one fits the frame.
  let fitting = body + " ".repeat(frame - 23 - body.length())
  let (_, step) = closing.on(
    Received(@worker.Message::parse(@utf8.encode(fitting))),
  )
  assert_true(step is Finished(Closed, ..))
  let (_, step) = closing.on(
    Received(@worker.Message::parse(@utf8.encode(fitting + " "))),
  )
  guard step is Finished(EndedEarly(Failed(Host(code=ResponseLimit, ..))), ..) else {
    fail(
      "accepted a bounded shutdown reply whose body fits but whose full frame is oversized",
    )
  }
}
