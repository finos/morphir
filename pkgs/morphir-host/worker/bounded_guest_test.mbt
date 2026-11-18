///|
fn bounded_guest_backend(
  entries : Array[(Bool, Json)],
  counts : Array[Int32],
  advance_override? : @model_access.GenerationStep,
) -> @guest_mep.BoundedBackend raise {
  let offered = recorded_part(
    recorded_part(entries[0].1, "params"),
    "modelAccess",
  )
  let support = @model_access.Support::from_json(offered)
  let first = @model_access.GenerationStep::from_json(
    recorded_part(entries[4].1, "result"),
  )
  let following = [6, 10, 12, 14, 16].map(index => {
    @model_access.GenerationStep::from_json(
      recorded_part(entries[index].1, "result"),
    )
  })
  let limited = @model_access.GenerationStep::from_json(
    recorded_part(entries[18].1, "result"),
  )
  let cancelled = @model_access.GenerationStep::from_json(
    recorded_part(entries[20].1, "result"),
  )
  @guest_mep.BoundedBackend::new(support, start => {
    counts[0] += 1
    assert_true(start.target == "moonbit") catch {
      _ => abort("unexpected test target")
    }
    let step = match start.session_id {
      "orders-generation" => first
      "orders-limited" => limited
      "orders-cancelled" => cancelled
      _ => abort("unexpected test operation")
    }
    (
      step,
      @guest_mep.BoundedOperation::new(
        advance=request => {
          counts[1] += 1
          advance_override.unwrap_or(following[request.round - 1])
        },
        release=() => counts[2] += 1,
      ),
    )
  })
}

///|
fn bounded_guest_start(message : Json) -> Json raise {
  let params = recorded_part(message, "params")
  guard message is Object(fields) && params is Object(start) else {
    fail("start is not a named request")
  }
  let changed = fields.copy()
  let start = start.copy()
  start["target"] = Json::string("moonbit")
  changed["params"] = Json::object(start)
  Json::object(changed)
}

///|
fn guest_error_code(response : Json) -> Json {
  recorded_part(recorded_part(response, "error"), "code")
}

///|
test "bounded MoonBit guest replays ordered rounds, failure, cancellation and release" {
  let entries = read_transcript(
    "../../tests/fixtures/mep-bounded-generation/session-model-access.md",
  )
  let counts = [0, 0, 0]
  let guest = @guest_mep.Session::new(
    bounded=Some(bounded_guest_backend(entries, counts)),
  )
  let init = guest.handle(entries[0].1).unwrap()
  let result = recorded_part(init, "result")
  assert_eq(
    recorded_part(result, "protocolVersion"),
    Json::string("0.2.0-draft.2"),
  )
  let agree = recorded_part(
    recorded_part(result, "capabilities"),
    "modelAccess",
  )
  let expected = recorded_part(
    recorded_part(entries[1].1, "result"),
    "capabilities",
  )
  assert_eq(agree, recorded_part(expected, "modelAccess"))

  let first_start = bounded_guest_start(entries[3].1)
  assert_eq(
    guest_error_code(guest.handle(first_start).unwrap()),
    Json::number(-32013),
  )
  assert_eq(counts, [0, 0, 0])
  assert_eq(guest.handle(entries[2].1), None)

  for i in 3..<25 {
    if (i - 3) % 2 != 0 {
      continue
    }
    let message = if [3, 17, 19].contains(i) {
      bounded_guest_start(entries[i].1)
    } else {
      entries[i].1
    }
    let response = guest.handle(message).unwrap()
    if i == 7 {
      assert_eq(guest_error_code(response), Json::number(-32602))
      assert_eq(counts, [1, 1, 0])
    } else {
      assert_eq(
        recorded_part(response, "result"),
        recorded_part(entries[i + 1].1, "result"),
      )
    }
    if i == 15 {
      assert_eq(
        guest_error_code(guest.handle(first_start).unwrap()),
        Json::number(-32602),
      )
      assert_eq(counts, [1, 5, 1])
    }
  }
  assert_eq(counts, [3, 5, 3])
  assert_eq(guest.handle(entries[25].1), None)
  assert_true(guest.exited())
  assert_eq(counts, [3, 5, 3])
}

///|
test "bounded guest keeps draft.1 small-model fallback when the bounded offer is unavailable" {
  let entries = read_transcript(
    "../../tests/fixtures/mep-bounded-generation/session-model-access.md",
  )
  let counts = [0, 0, 0]
  let guest = @guest_mep.Session::new(
    bounded=Some(bounded_guest_backend(entries, counts)),
  )
  let ordinary = @guest_mep.Session::new()
  let old = read_transcript("../../tests/fixtures/mep-smithy/compile-ion.md")
  let initialize = old[2].1
  guard initialize is Object(fields) &&
    fields.get("params") is Some(Object(params)) else {
    fail("the pinned legacy initialize has no named parameters")
  }
  let changed = params.copy()
  changed["modelAccess"] = Json::string("ignored by draft.1")
  let request = fields.copy()
  request["params"] = Json::object(changed)
  let response = guest.handle(Json::object(request))
  assert_eq(response, ordinary.handle(initialize))
  let result = recorded_part(response.unwrap(), "result")
  assert_eq(
    recorded_part(result, "protocolVersion"),
    Json::string("0.2.0-draft.1"),
  )
  assert_eq(
    guest_error_code(guest.handle(bounded_guest_start(entries[3].1)).unwrap()),
    Json::number(-32013),
  )
  assert_eq(counts, [0, 0, 0])
}

///|
async fn serve_moonbit_guest(
  worker : @worker.MemoryWorker,
  guest : @guest_mep.Session,
  received : Array[Json],
) -> Unit {
  while true {
    let message = worker.receive() catch { _ => return }
    received.push(message.json())
    match guest.receive(message.to_bytes()) {
      Some(Object(fields)) => worker.send(@worker.Message::new(fields))
      _ => ()
    }
    if guest.exited() {
      worker.exit(code=0)
      return
    }
  }
}

///|
async test "MoonBit host and guest exchange the pinned orders rounds over one channel" {
  let entries = read_transcript(
    "../../tests/fixtures/mep-bounded-generation/session-model-access.md",
  )
  let counts = [0, 0, 0]
  let guest = @guest_mep.Session::new(
    bounded=Some(bounded_guest_backend(entries, counts)),
  )
  let describe = guest
    .handle({
      "jsonrpc": "2.0",
      "id": 0,
      "method": "morphir.extension.describe",
      "params": {
        "protocolVersions": ["0.2.0-draft.2", "0.2.0-draft.1", "0.1"],
      },
    })
    .unwrap()
  let description = recorded_part(describe, "result")
  let claims = @worker.Claims::from_describe(description)
  assert_eq(claims.protocol_lines.map(line => line.to_string()), [
    "0.1", "0.2.0-draft.1", "0.2.0-draft.2",
  ])
  let offered = recorded_part(
    recorded_part(entries[0].1, "params"),
    "modelAccess",
  )
  assert_eq(test_support(description), offered)
  let start = @model_access.Start::from_json(
    recorded_part(bounded_guest_start(entries[3].1), "params"),
  )
  let (channel, worker) = @worker.MemoryChannel::pair()
  let host = @worker.Host::new(
    @worker.MemoryLauncher::new(channel),
    Native(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  let received = []
  @async.with_task_group(group => {
    group.spawn_bg(() => serve_moonbit_guest(worker, guest, received))
    let session = host.activate(
      process_spec(),
      offer=Bounded(@model_access.Support::from_json(offered)),
      expected=claims,
    )
    let result = session.start_generation(start)
    guard result.class is Completed(Stepped(step)) else {
      fail("the real MoonBit guest did not start")
    }
    assert_eq(step.to_json(), recorded_part(entries[4].1, "result"))
    for i in [5, 9, 11, 13, 15] {
      let advance = @model_access.Advance::from_json(
        recorded_part(entries[i].1, "params"),
      )
      let result = session.advance_generation(advance)
      guard result.class is Completed(Stepped(step)) else {
        fail("the real MoonBit guest did not advance")
      }
      assert_eq(step.to_json(), recorded_part(entries[i + 1].1, "result"))
    }
    let report = session.close()
    assert_eq(report.ending, None)
  })
  assert_eq(counts, [1, 5, 1])
  assert_eq(received_methods(received), [
    "morphir.initialize", "morphir.initialized", "morphir.backend.generateModel.start",
    "morphir.backend.generateModel.advance", "morphir.backend.generateModel.advance",
    "morphir.backend.generateModel.advance", "morphir.backend.generateModel.advance",
    "morphir.backend.generateModel.advance", "morphir.shutdown", "morphir.exit",
  ])
}

///|
test "bounded guest releases an active operation once on shutdown or exit" {
  let entries = read_transcript(
    "../../tests/fixtures/mep-bounded-generation/session-model-access.md",
  )
  for shutdown in [false, true] {
    let counts = [0, 0, 0]
    let guest = @guest_mep.Session::new(
      bounded=Some(bounded_guest_backend(entries, counts)),
    )
    ignore(recorded_part(guest.handle(entries[0].1).unwrap(), "result"))
    assert_eq(guest.handle(entries[2].1), None)
    let started = guest.handle(bounded_guest_start(entries[3].1)).unwrap()
    assert_eq(
      recorded_part(started, "result"),
      recorded_part(entries[4].1, "result"),
    )
    assert_eq(counts, [1, 0, 0])
    if shutdown {
      let response = guest.handle(entries[23].1).unwrap()
      assert_eq(recorded_part(response, "result"), Json::object({}))
      assert_eq(counts, [1, 0, 1])
    }
    assert_eq(guest.handle(entries[25].1), None)
    assert_eq(guest.handle(entries[25].1), None)
    assert_eq(counts, [1, 0, 1])
  }
}

///|
async test "bounded generation uses a compatible small-model fallback with a diagnostic" {
  let entries = read_transcript(
    "../../tests/fixtures/mep-bounded-generation/session-model-access.md",
  )
  let counts = [0, 0, 0]
  let guest = @guest_mep.Session::new(
    bounded=Some(bounded_guest_backend(entries, counts)),
  )
  let describe = guest
    .handle({
      "jsonrpc": "2.0",
      "id": 0,
      "method": "morphir.extension.describe",
      "params": { "protocolVersions": ["0.2.0-draft.2", "0.2.0-draft.1"] },
    })
    .unwrap()
  let description = recorded_part(describe, "result")
  let claims = @worker.Claims::from_describe(description)
  let offered = @model_access.Support::from_json(
    bounded_activation_offer([bounded_yaml_tuple()]),
  )
  let required = try {
    ignore(@worker.BoundedGenerateChoice::select(claims, offered, "moonbit"))
    false
  } catch {
    @worker.Refusal(code=TupleUnavailable, ..) => true
    _ => false
  }
  assert_true(required)
  let mut reads = 0
  let loader : (Int32) -> Bytes raise @worker.Refusal = limit => {
    reads += 1
    let document = @utf8.encode(
      @ir_json.to_json(@generator_fixtures.library()).stringify(),
    ) catch {
      _ => abort("fixed generator fixture failed")
    }
    if document.length() > limit {
      abort("the fixed model must fit the admitted fallback")
    }
    document
  }
  let exact = @model_access.Support::from_json(test_support(description))
  let prefer = @worker.BoundedGenerateChoice::select(
    claims,
    exact,
    "moonbit",
    read_inline=loader,
  )
  assert_true(prefer is Access(_))
  assert_eq(reads, 0)
  let fallback = @worker.BoundedGenerateChoice::select(
    claims,
    offered,
    "moonbit",
    read_inline=loader,
  )
  guard fallback is Inline(choice, warning) else {
    fail("the small model did not get a typed fallback")
  }
  assert_eq(reads, 1)
  assert_eq(choice.line.offer.line().to_string(), "0.2.0-draft.1")
  assert_eq(warning.code, Some("extension.bounded_mep_fallback"))
  assert_eq(warning.severity, Warning)
  assert_eq(
    recorded_part(warning.data.unwrap(), "protocolVersion"),
    Json::string("0.2.0-draft.1"),
  )
  let received = []
  let (channel, worker) = @worker.MemoryChannel::pair()
  let host = @worker.Host::new(
    @worker.MemoryLauncher::new(channel),
    Native(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  @async.with_task_group(group => {
    group.spawn_bg(() => serve_moonbit_guest(worker, guest, received))
    let session = host.activate(
      process_spec(),
      offer=choice.line.offer,
      expected=claims,
    )
    let outcome = session.generate(
      generate_request({
        "target": "moonbit",
        "model": choice.model,
        "contextDigest": "a".repeat(64),
      }),
    )
    guard outcome.class is Completed(generated) else {
      fail(
        "the compatible draft.1 generation failed: \{@debug.to_string(outcome.class)}",
      )
    }
    guard recorded_part(generated.result, "artifacts") is Array(artifacts) &&
      !artifacts.is_empty() else {
      fail("the ordinary generator returned no artifacts")
    }
    let report = session.close()
    assert_eq(report.ending, None)
  })
  assert_eq(received_methods(received), [
    "morphir.initialize", "morphir.initialized", "morphir.backend.generateModel",
    "morphir.shutdown", "morphir.exit",
  ])
  assert_eq(counts, [0, 0, 0])
}

///|
async fn[X] with_bounded_test_guest(
  entries : Array[(Bool, Json)],
  counts : Array[Int32],
  received : Array[Json],
  advance_override? : @model_access.GenerationStep,
  f : async (@worker.Host, @worker.Claims, @worker.Offer) -> X,
) -> X {
  let guest = @guest_mep.Session::new(
    bounded=Some(bounded_guest_backend(entries, counts, advance_override?)),
  )
  let response = guest
    .handle({
      "jsonrpc": "2.0",
      "id": 0,
      "method": "morphir.extension.describe",
      "params": { "protocolVersions": ["0.2.0-draft.2"] },
    })
    .unwrap()
  let description = recorded_part(response, "result")
  let claims = @worker.Claims::from_describe(description)
  let offer : @worker.Offer = Bounded(
    @model_access.Support::from_json(test_support(description)),
  )
  let (channel, worker) = @worker.MemoryChannel::pair()
  let host = @worker.Host::new(
    @worker.MemoryLauncher::new(channel),
    Native(@worker.Machine::of(Aarch64AppleDarwin)),
  )
  @async.with_task_group(group => {
    group.spawn_bg(() => serve_moonbit_guest(worker, guest, received))
    f(host, claims, offer)
  })
}

///|
async test "bounded guest terminal error settles the active host round" {
  let entries = read_transcript(
    "../../tests/fixtures/mep-bounded-generation/session-model-access.md",
  )
  let counts = [0, 0, 0]
  let received = []
  let start = @model_access.Start::from_json(
    recorded_part(bounded_guest_start(entries[3].1), "params"),
  )
  let repeated = @model_access.GenerationStep::from_json(
    recorded_part(entries[4].1, "result"),
  )
  let advance = @model_access.Advance::from_json(
    recorded_part(entries[5].1, "params"),
  )
  let next = @model_access.Start::from_json(
    recorded_part(bounded_guest_start(entries[17].1), "params"),
  )
  with_bounded_test_guest(
    entries,
    counts,
    received,
    advance_override=repeated,
    (host, claims, offer) => {
      host.with_session(process_spec(), expected=claims, offer~, session => {
        assert_true(session.start_generation(start).class is Completed(_))
        assert_true(
          session.advance_generation(advance).class
          is Failed(Guest(code=-32603, ..)),
        )
        assert_true(
          session.advance_generation(advance).class
          is Refused(code=AgreementMismatch, ..),
        )
        assert_true(session.start_generation(next).class is Completed(_))
      })
    },
  )
  assert_eq(counts, [2, 1, 2])
}

///|
async test "bounded close cancels the guest after work raises" {
  let entries = read_transcript(
    "../../tests/fixtures/mep-bounded-generation/session-model-access.md",
  )
  let counts = [0, 0, 0]
  let received = []
  let start = @model_access.Start::from_json(
    recorded_part(bounded_guest_start(entries[3].1), "params"),
  )
  with_bounded_test_guest(entries, counts, received, (host, claims, offer) => {
    let failed = try {
      host.with_session(process_spec(), expected=claims, offer~, session => {
        assert_true(session.start_generation(start).class is Completed(_))
        (fail("fixture delivery failure") : Unit)
      })
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  })
  assert_eq(received_methods(received), [
    "morphir.initialize", "morphir.initialized", "morphir.backend.generateModel.start",
    "morphir.backend.generateModel.cancel", "morphir.shutdown", "morphir.exit",
  ])
  assert_eq(counts, [1, 0, 1])
}

///|
test "bounded guest refuses a diagnostic without a location range" {
  let entries = read_transcript(
    "../../tests/fixtures/mep-bounded-generation/session-model-access.md",
  )
  let positive = @model_access.GenerationStep::from_json(
    recorded_part(entries[6].1, "result"),
  )
  guard positive is Continue(session_id~, round~, requests~, artifacts~, ..) else {
    fail("fixture does not continue")
  }
  let step : @model_access.GenerationStep = Continue(
    session_id~,
    round~,
    requests~,
    artifacts~,
    diagnostics=[
      { "severity": "warning", "message": "example", "location": {} },
    ],
  )
  let counts = [0, 0, 0]
  let guest = @guest_mep.Session::new(
    bounded=Some(bounded_guest_backend(entries, counts, advance_override=step)),
  )
  ignore(guest.handle(entries[0].1))
  ignore(guest.handle(entries[2].1))
  assert_eq(
    recorded_part(
      guest.handle(bounded_guest_start(entries[3].1)).unwrap(),
      "result",
    ),
    recorded_part(entries[4].1, "result"),
  )
  let reply = guest.handle(entries[5].1).unwrap()
  assert_eq(guest_error_code(reply), Json::number(-32603))
  assert_eq(counts, [1, 1, 1])
}

///|
test "bounded fallback checks the exact legacy document version" {
  let offered = @model_access.Support::from_json(
    bounded_activation_offer([bounded_yaml_tuple()]),
  )
  let bytes = @utf8.encode(
    "{\"formatVersion\":3,\"distribution\":[\"Library\",[[\"acme\"]],[],{\"modules\":[]}]}",
  )
  let read_inline : (Int32) -> Bytes raise @worker.Refusal = _ => bytes
  for (claim, allowed) in [("3.1.0", false), ("3.0.0", true), ("3", true)] {
    let claims = @worker.Claims::from_describe({
      "extension": { "id": "morphir-moonbit", "version": "1.0.0" },
      "protocolVersions": ["0.1"],
      "capabilities": {
        "backend": {
          "generate": true,
          "targets": ["moonbit"],
          "irVersions": [claim],
        },
      },
    })
    let result = try {
      ignore(
        @worker.BoundedGenerateChoice::select(
          claims,
          offered,
          "moonbit",
          read_inline~,
        ),
      )
      true
    } catch {
      @worker.Refusal(code=TupleUnavailable, ..) => false
      error => raise error
    }
    assert_eq(result, allowed)
  }
  let dual = @worker.Claims::from_describe({
    "extension": { "id": "morphir-moonbit", "version": "1.0.0" },
    "protocolVersions": ["0.1", "0.2.0-draft.1"],
    "capabilities": {
      "backend": {
        "generate": true,
        "targets": ["moonbit"],
        "irVersions": ["3.0.0", "3.1.0"],
      },
    },
  })
  let choice = @worker.BoundedGenerateChoice::select(
    dual,
    offered,
    "moonbit",
    read_inline~,
  )
  guard choice is Inline({ line: { fallback: Some(fallback), .. }, .. }, _) else {
    fail("the dual-line guest did not select legacy generation")
  }
  assert_eq(fallback.ir_version.map(name => name.to_string()), Some("3.0.0"))
}
