///|
/// The recorded sessions of `tests/fixtures/mep-smithy`, relative to the
/// module root, where `moon test` runs.
let mep_smithy : String = "../../tests/fixtures/mep-smithy/"

///|
/// The messages of a recorded transcript, in order, with their direction:
/// `true` for host to extension.
fn transcript(name : String) -> Array[(Bool, Json)] {
  read_transcript(mep_smithy + name)
}

///|
fn read_transcript(path : String) -> Array[(Bool, Json)] {
  let text = @fs.read_file_to_string(path) catch {
    _ => abort("cannot read the transcript \{path}")
  }
  let lines = text
    .split("\n")
    .map(line => line.trim_end(chars="\r").to_owned())
    .collect()
  let entries = []
  for index, line in lines {
    let host = match line {
      "```jsonrpc host -> extension" => true
      "```jsonrpc extension -> host" => false
      _ => continue
    }
    let body = @json.parse(lines[index + 1]) catch {
      _ => abort("entry \{entries.length()} of \{path} is not JSON")
    }
    entries.push((host, body))
  }
  entries
}

///|
fn recorded_part(entry : Json, name : String) -> Json {
  guard entry is Object(fields) && fields.get(name) is Some(value) else {
    abort("the recorded message has no \{name}")
  }
  value
}

///|
/// A recorded reply with the ID that this host gives the request. The
/// recording pipelines describe into the operation session, so its IDs are one
/// higher than in a fresh operation session.
fn replayed(entry : Json, id : Int32) -> @worker.Event {
  guard entry is Object(fields) else {
    abort("the recorded reply is not an object")
  }
  let fields = fields.copy()
  fields["id"] = Json::number(id.to_double())
  Received(@worker.Message::new(fields))
}

///|
fn sent_json(step : @worker.Step) -> Array[Json] {
  sends(step).map(message => message.json())
}

///|
test "recorded MoonBit compile: the session replays compile-ion.md" {
  let entries = transcript("compile-ion.md")
  assert_eq(entries.length(), 10)
  let host = entries.map(entry => entry.0)
  assert_eq(host, [
    true, false, true, false, true, true, false, true, false, true,
  ])
  let recorded = entries.map(entry => entry.1)
  // Probe: describe, then exit. The probe also offers MEP 0.1, so only the
  // method is compared.
  let (probe, step) = @worker.Conversation::probe()
  assert_eq(
    recorded_part(sent_json(step)[0], "method"),
    recorded_part(recorded[0], "method"),
  )
  let (_, step) = probe.on(replayed(recorded[1], 1))
  guard step is Finished(Described(description), ..) else {
    fail("the recorded describe answer did not describe the guest")
  }
  let claims = description.claims
  assert_eq(claims.extension_id.to_string(), "morphir-moonbit")
  assert_eq(claims.operations, [Generate, CompileModel, GenerateModel])
  assert_eq(claims.protocol_lines, [Mep0_1, Mep0_2Draft1])
  assert_eq(claims.model_tuples.length(), 4)
  assert_eq(sent_json(step), [recorded[9]])
  // Activation sends the recorded initialize parameters exactly.
  let offer = @worker.Offer::select(
    claims,
    CompileModel,
    profile=MorphirModel,
    codec=IonBinary,
    ir_version=@worker.IrVersionName::parse("4.0.0"),
  )
  assert_eq(offer, Model([ion_tuple]))
  let (session, step) = @worker.Conversation::activate(offer, expected=claims)
  let initialize = sent_json(step)[0]
  assert_eq(
    recorded_part(initialize, "method"),
    recorded_part(recorded[2], "method"),
  )
  assert_eq(
    recorded_part(initialize, "params"),
    recorded_part(recorded[2], "params"),
  )
  let (session, step) = session.on(replayed(recorded[3], 1))
  assert_eq(sent_json(step), [recorded[4]])
  // The operation goes out with the recorded parameters unchanged.
  guard recorded_part(recorded[5], "params") is Object(params) else {
    fail("the recorded compile has no parameters")
  }
  let (session, step) = session.compile(compile_request(params~))
  let compile = sent_json(step)[0]
  assert_eq(
    recorded_part(compile, "method"),
    recorded_part(recorded[5], "method"),
  )
  assert_eq(
    recorded_part(compile, "params"),
    recorded_part(recorded[5], "params"),
  )
  let (session, step) = session.on(replayed(recorded[6], 2))
  guard step is Answered({ class: Completed(result), diagnostics: [], }, ..) else {
    fail("the recorded compile did not complete")
  }
  assert_eq(result, recorded_part(recorded[6], "result"))
  // Close: shutdown, then exit.
  let (session, step) = session.close()
  let shutdown = sent_json(step)[0]
  assert_eq(
    recorded_part(shutdown, "method"),
    recorded_part(recorded[7], "method"),
  )
  assert_eq(
    recorded_part(shutdown, "params"),
    recorded_part(recorded[7], "params"),
  )
  let (_, step) = session.on(replayed(recorded[8], 3))
  assert_true(step is Finished(stop=CloseAfterExit, Closed, ..))
  assert_eq(sent_json(step), [recorded[9]])
}

///|
test "recorded host fault: the session always sends initialized" {
  let methods_of = (name : String) => {
    transcript(name)
    .filter(entry => entry.0)
    .map(entry => recorded_part(entry.1, "method"))
  }
  let faulty = methods_of("missing-initialized.md")
  let correct = methods_of("compile-ion.md")
  // The fault recording removed initialized; this host's order keeps it.
  assert_false(faulty.contains(Json::string("morphir.initialized")))
  assert_true(correct.contains(Json::string("morphir.initialized")))
}

///|
/// The methods of every message a step sends.
fn sent_methods(step : @worker.Step) -> Array[Json] {
  sent_json(step).map(message => recorded_part(message, "method"))
}

///|
test "recorded host fault: driven against missing-initialized.md, initialized precedes compileModel" {
  let recorded = transcript("missing-initialized.md").map(entry => entry.1)
  let (probe, _) = @worker.Conversation::probe()
  let (_, step) = probe.on(replayed(recorded[1], 1))
  guard step is Finished(Described(description), ..) else {
    fail("the recorded describe answer did not describe the guest")
  }
  let offer = @worker.Offer::select(description.claims, CompileModel)
  let (session, step) = @worker.Conversation::activate(
    offer,
    expected=description.claims,
  )
  let sent = sent_methods(step)
  let (session, step) = session.on(replayed(recorded[3], 1))
  sent.push_iter(sent_methods(step).iter())
  guard recorded_part(recorded[4], "params") is Object(params) else {
    fail("the recorded compile has no parameters")
  }
  let (_, step) = session.compile(compile_request(params~))
  sent.push_iter(sent_methods(step).iter())
  assert_eq(sent, [
    "morphir.initialize", "morphir.initialized", "morphir.frontend.compileModel",
  ])
  // The recording went straight from initialize to compileModel.
  assert_eq(recorded_part(recorded[2], "method"), "morphir.initialize")
  assert_eq(
    recorded_part(recorded[4], "method"),
    "morphir.frontend.compileModel",
  )
}

///|
test "the bounded worker activates against the pinned parent transcript" {
  let path = "../../tests/fixtures/mep-bounded-generation/session-model-access.md"
  assert_eq(
    @worker.Sha256::of(@fs.read_file_to_bytes(path)).to_string(),
    "2b564178596e1c7420fc8c689b31e7dbd68dabaed3d57ac0e9497ce21886cb34",
  )
  let entries = read_transcript(path)
  assert_eq(entries.length(), 26)
  assert_eq(entries[0].0, true)
  assert_eq(entries[1].0, false)
  assert_eq(entries[2].0, true)
  let request = entries[0].1
  let reply = entries[1].1
  assert_eq(
    recorded_part(request, "method"),
    Json::string("morphir.initialize"),
  )
  let recorded_offer = recorded_part(
    recorded_part(request, "params"),
    "modelAccess",
  )
  let host = @model_access.Support::from_json(recorded_offer)
  let (session, step) = @worker.Conversation::activate(
    Bounded(host),
    expected=bounded_activation_claims(),
  )
  let initialize = sent_json(step)[0]
  assert_eq(
    recorded_part(recorded_part(initialize, "params"), "modelAccess"),
    recorded_offer,
  )
  let (_, step) = session.on(replayed(reply, 1))
  guard step is Activated(negotiated, ..) else {
    fail("the recorded draft.2 result did not activate the worker")
  }
  assert_eq(sent_json(step), [entries[2].1])
  assert_eq(
    negotiated.model_access.unwrap().to_json(),
    recorded_part(
      recorded_part(recorded_part(reply, "result"), "capabilities"),
      "modelAccess",
    ),
  )
}

///|
test "fixed bounded transcript decodes each typed result and preserves its payload" {
  let entries = read_transcript(
    "../../tests/fixtures/mep-bounded-generation/session-model-access.md",
  )
  let mut continues = 0
  let mut completed = 0
  let mut failed = 0
  for (from_host, message) in entries {
    if from_host {
      continue
    }
    guard message is Object(fields) &&
      fields.get("result") is Some(Object(result)) &&
      result.contains("state") else {
      continue
    }
    let wire = Json::object(result)
    let step = @model_access.GenerationStep::from_json(wire)
    assert_eq(step.to_json(), wire)
    match step {
      @model_access.GenerationStep::Continue(session_id~, round~, requests~, ..) => {
        continues += 1
        if session_id == "orders-generation" && round == 1 {
          assert_eq(requests, [
            @model_access.ReadRequest::Inventory(
              request_id="root-modules",
              selection="root",
              page_size=1,
              cursor=None,
            ),
          ])
        }
      }
      @model_access.GenerationStep::Complete(session_id~, artifacts~, ..) => {
        completed += 1
        assert_eq(session_id, "orders-generation")
        assert_eq(artifacts.length(), 1)
        assert_eq(artifacts[0].path, "order.txt")
        assert_eq(artifacts[0].offset, 0L)
        assert_eq(artifacts[0].decoded_byte_length, 3)
        assert_eq(artifacts[0].content, "NzMK")
        assert_true(artifacts[0].final_chunk)
      }
      @model_access.GenerationStep::Failed(
        session_id~,
        first_diagnostic~,
        other_diagnostics~
      ) => {
        failed += 1
        assert_eq(session_id, "orders-limited")
        assert_eq(
          recorded_part(first_diagnostic, "code"),
          Json::string("model_access.limit_exceeded"),
        )
        assert_eq(other_diagnostics.length(), 0)
      }
    }
  }
  assert_eq((continues, completed, failed), (6, 1, 1))
}

///|
test "bounded result decoding rejects mixed states and invalid request fields" {
  let cases : Array[Json] = [
    { "state": "failed", "sessionId": "one", "diagnostics": [] },
    {
      "state": "failed",
      "sessionId": "one",
      "diagnostics": [{ "severity": "error", "message": "bad" }],
      "artifacts": [],
    },
    {
      "state": "complete",
      "sessionId": "one",
      "artifacts": [],
      "diagnostics": [],
      "round": 1,
    },
    {
      "state": "continue",
      "sessionId": "one",
      "round": 0,
      "requests": [],
      "artifacts": [],
      "diagnostics": [],
    },
    {
      "state": "continue",
      "sessionId": "one",
      "round": 1,
      "requests": [
        {
          "kind": "document",
          "requestId": "d",
          "documentId": "manifest",
          "selection": "root",
        },
      ],
      "artifacts": [],
      "diagnostics": [],
    },
    {
      "state": "continue",
      "sessionId": "one",
      "round": 1,
      "requests": [
        { "kind": "inventory", "requestId": "r", "selection": "root" },
      ],
      "artifacts": [],
      "diagnostics": [],
    },
  ]
  for wire in cases {
    let accepted = try {
      ignore(@model_access.GenerationStep::from_json(wire))
      true
    } catch {
      _ => false
    }
    assert_false(accepted)
  }
}

///|
test "bounded per-call limits reject wide integers while cumulative limits retain them" {
  let description = bounded_probe_description(bounded_probe_tuple())
  guard test_support(description) is Object(support) &&
    support.get("limits") is Some(Object(limits)) else {
    fail("expected the fixed access support")
  }
  limits["maxFrameBytes"] = Json::number(2147483648.0)
  assert_false(
    try {
      ignore(@worker.Claims::from_describe(description))
      true
    } catch {
      _ => false
    },
  )
  limits["maxFrameBytes"] = Json::number(2147483647.0)
  let decoded = @worker.Claims::from_describe(description).model_access.unwrap()
  assert_eq(decoded.limits.frame_bytes(), 2147483647L)
  assert_eq(
    recorded_part(decoded.limits.to_json(), "maxArtifactBytes"),
    Json::number(4294967296.0),
  )
}

///|
test "bounded conversation replays the orders rounds, failure and cancel on one connection" {
  let entries = read_transcript(
    "../../tests/fixtures/mep-bounded-generation/session-model-access.md",
  )
  let initialize = recorded_part(entries[0].1, "params")
  let offer = @model_access.Support::from_json(
    recorded_part(initialize, "modelAccess"),
  )
  let (session, _) = @worker.Conversation::activate(
    Bounded(offer),
    expected=bounded_activation_claims(),
  )
  let (session, first) = session.on(replayed(entries[1].1, 1))
  assert_eq(sent_json(first), [entries[2].1])

  let mut session = session
  let mut id = 2
  let mut refused = 0
  let mut terminal = 0
  for i in 3..<23 {
    if (i - 3) % 2 != 0 {
      continue
    }
    let request = entries[i].1
    let reply = entries[i + 1].1
    let params = recorded_part(request, "params")
    let method_name = recorded_part(request, "method")
    let (next, sent) = match method_name {
      String("morphir.backend.generateModel.start") =>
        session.start_generation(@model_access.Start::from_json(params))
      String("morphir.backend.generateModel.advance") =>
        session.advance_generation(@model_access.Advance::from_json(params))
      String("morphir.backend.generateModel.cancel") =>
        session.cancel_generation(@model_access.Cancel::from_json(params))
      _ => fail("unexpected bounded request in the replay")
    }
    if i == 7 {
      assert_eq(sends(sent).length(), 0)
      guard sent is BoundedAnswered({ class: Refused(..), .. }, ..) else {
        fail("the repeated round was accepted")
      }
      session = next
      refused += 1
      continue
    }
    guard sent is Exchange(awaiting=actual_id, ..) else {
      fail("the bounded request was not sent")
    }
    assert_eq(actual_id, id)
    let wire = sent_json(sent)[0]
    assert_eq(recorded_part(wire, "method"), method_name)
    assert_eq(recorded_part(wire, "params"), params)
    let (next, step) = next.on(replayed(reply, id))
    guard step is BoundedAnswered({ class: Completed(result), .. }, ..) else {
      fail("the recorded bounded reply was not accepted")
    }
    let expected = recorded_part(reply, "result")
    match result {
      Stepped(step) => {
        assert_eq(step.to_json(), expected)
        if !(step is @model_access.GenerationStep::Continue(..)) {
          terminal += 1
        }
      }
      CancelledGeneration(acknowledged) => {
        assert_eq(acknowledged.to_json(), expected)
        terminal += 1
      }
    }
    session = next
    id += 1
  }
  assert_eq((refused, terminal), (1, 3))
  let (session, closing) = session.close()
  assert_eq(methods(closing), ["morphir.shutdown"])
  let (_, stopped) = session.on(replayed(entries[24].1, id))
  assert_true(stopped is Finished(Closed, stop=CloseAfterExit, ..))
  assert_eq(sent_json(stopped), [entries[25].1])
}
