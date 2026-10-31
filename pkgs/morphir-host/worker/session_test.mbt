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
    Answered(_, sends~) => sends
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
test "tuple not supported: the session is refused and no operation is sent" {
  let json_compile = @worker.ModelTuple::new(
    CompileModel,
    MorphirIr,
    MorphirJson,
    V0_1_0Draft1,
    V4_0_0,
  )
  let claims = @worker.Claims::from_describe(
    model_result([ion_tuple, json_compile]),
  )
  // The host offers morphir-ir with morphir-json; the worker returns only Ion.
  let (conversation, step) = @worker.Conversation::activate(
    Model(json_compile),
    expected=claims,
  )
  guard sends(step)[0].json()
    is Object({ "params": Object({ "modelTransport": transport, .. }), .. }) else {
    fail("no model transport offer")
  }
  assert_eq(transport, {
    "tuples": [json_compile.to_json()],
    "limits": {
      "maxEncodedBytes": 2796204,
      "maxDecodedBytes": 2097152,
      "maxDepth": 128,
      "maxNodes": 100000,
    },
    "guarantees": [],
  })
  let (conversation, step) = conversation.on(
    answer(1, model_result([ion_tuple], protocol="0.2.0-draft.1")),
  )
  assert_eq(methods(step), ["morphir.shutdown"])
  let (_, step) = conversation.on(answer(2, {}))
  assert_eq(methods(step), ["morphir.exit"])
  assert_eq(refused_code(step), Some(TupleUnavailable))
}

///|
test "smaller worker limit: a model request is checked against the worker's limit" {
  let claims = model_claims()
  let (conversation, _) = @worker.Conversation::activate(
    Model(json_generate_tuple),
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
  // 1,500 bytes is below the host's 2 MiB, but above the worker's limit.
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
  assert_eq(host.for_session(Legacy, process), host)
  assert_eq(host.for_session(Model(ion_tuple), Wasm(abi=None)), host)
  let profile = @worker.ExtismProfile::restricted()
  assert_eq(profile.memory_bytes, 256 * 1024 * 1024)
  assert_eq(profile.instructions, 1000000000L)
  let wasm = host.for_session(Legacy, Wasm(abi=Some(ExtismKernelV1)))
  assert_eq(wasm.request_bytes, profile.input_bytes)
  assert_eq(wasm.response_bytes, profile.output_bytes)
}

///|
test "claims match: activation returns a session that accepts calls" {
  let (conversation, _) = @worker.Conversation::activate(
    Model(ion_tuple),
    expected=model_claims(),
  )
  let (conversation, step) = conversation.on(
    answer(1, model_result([ion_tuple], protocol="0.2.0-draft.1")),
  )
  assert_eq(methods(step), ["morphir.initialized"])
  guard step is Activated(negotiated, ..) else { fail("not activated") }
  assert_eq(negotiated.offer, Model(ion_tuple))
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
    Model(ion_tuple),
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
    Model(ion_tuple),
  )
  assert_eq(
    @worker.Offer::select(model_claims(), GenerateModel),
    Model(json_generate_tuple),
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
    let limits = @worker.Limits::host().for_session(Model(ion_tuple), runtime)
    let (conversation, first) = @worker.Conversation::activate(
      Model(ion_tuple),
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
    Model(json_generate_tuple),
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
    Model(ion_tuple),
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
      Model(ion_tuple),
      dual_result(legacy=false, tuples=[ion_tuple], targets=[], protocol=model),
    )
    is Activated(_, ..),
  )
  assert_true(
    activation_of(
      Model(json_generate_tuple),
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
        Model(ion_tuple),
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
        Model(ion_tuple),
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
        Model(json_generate_tuple),
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
  assert_eq(methods(activation_of(Model(ion_tuple), other)), [
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
        Model(ion_tuple),
        dual_result(tuples=[ion_tuple], protocol="0.2.0-draft.1"),
        recorded~,
      ),
    ),
    ["morphir.shutdown"],
  )
  // A generateModel session does not compile, so the flag does not count.
  assert_true(
    activation_of(
      Model(json_generate_tuple),
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
  let refused = try @worker.Offer::Model(stale).check(model_claims()) catch {
    Refusal(code~, ..) => Some(code)
  } noraise {
    _ => None
  }
  assert_eq(refused, Some(ClaimsMismatch))
}

///|
test "offer selection prefers Ion, then JSON, whatever order the worker declares" {
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
  let claims = @worker.Claims::from_describe(model_result([json_model, ion_ir]))
  assert_eq(@worker.Offer::select(claims, CompileModel), Model(ion_ir))
  assert_eq(
    @worker.Offer::select(claims, CompileModel, profile=MorphirModel),
    Model(json_model),
  )
  assert_eq(
    @worker.Offer::select(claims, CompileModel, codec=MorphirJson),
    Model(json_model),
  )
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
