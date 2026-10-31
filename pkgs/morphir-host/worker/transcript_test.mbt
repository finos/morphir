///|
/// The recorded sessions of `tests/fixtures/mep-smithy`, relative to the
/// module root, where `moon test` runs.
let mep_smithy : String = "../../tests/fixtures/mep-smithy/"

///|
/// The messages of a recorded transcript, in order, with their direction:
/// `true` for host to extension.
fn transcript(name : String) -> Array[(Bool, Json)] {
  let text = @fs.read_file_to_string(mep_smithy + name) catch {
    _ => abort("cannot read the transcript \{name}")
  }
  let lines = text.split("\n").map(line => line.to_owned()).collect()
  let entries = []
  for index, line in lines {
    let host = match line {
      "```jsonrpc host -> extension" => true
      "```jsonrpc extension -> host" => false
      _ => continue
    }
    let body = @json.parse(lines[index + 1]) catch {
      _ => abort("entry \{entries.length()} of \{name} is not JSON")
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
