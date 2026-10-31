///|
/// The JSON of each message that a session step sends.
fn recording_sends(step : @worker.Step) -> Array[Json] {
  let sends = match step {
    Exchange(sends~, ..) => sends
    Activated(sends~, _) => sends
    Answered(sends~, _) => sends
    Finished(sends~, _, ..) => sends
  }
  sends.map(message => message.json())
}

///|
/// Moves the ID of a request by `by`. The recording pipelines the probe's
/// describe into the operation session, so the operation's IDs are one higher
/// than in a fresh worker.
fn recording_shifted(message : Json, by : Int32) -> Json {
  guard message is Object(fields) && fields.get("id") is Some(Number(id, ..)) else {
    return message
  }
  let fields = fields.copy()
  fields["id"] = Json::number(id + by.to_double())
  Json::object(fields)
}

///|
fn recording_frames(messages : Array[Json]) -> Bytes raise {
  let buffer = Buffer()
  for message in messages {
    buffer.write_bytes(@mep.encode_frame(message.stringify()))
  }
  buffer.to_bytes()
}

///|
/// Runs the guest once with the pipelined messages and returns its exit
/// code, its stderr and its framed replies.
async fn recording_run(
  guest : String,
  work : String,
  request : String,
  messages : Array[Json],
) -> (Int32, String, Bytes, Array[Json]) {
  @record_fs.write_file(request, recording_frames(messages))
  let input = @record_process.redirect_from_file(request)
  let (code, out, err) = @async.with_timeout(30000, async fn() {
    @record_process.collect_output(guest, [], stdin=input, cwd=work)
  })
  let decoder = @mep.Decoder::new()
  let bodies = decoder.feed(out.binary())
  decoder.finish()
  let replies = bodies.map(body => @json.parse(@utf8.decode(body[:])))
  (code, err.text(), out.binary(), replies)
}

///|
/// The reply to the request that has `id` in the pipelined run.
fn recording_reply(replies : Array[Json], id : Int32) -> @worker.Event {
  for reply in replies {
    if reply is Object(fields) &&
      fields.get("id") == Some(Json::number(id.to_double())) {
      return Received(@worker.Message::new(fields))
    }
  }
  abort("the guest gave no reply with ID \{id}")
}

///|
/// Record the worker host's session messages and the native guest's exact
/// wire bodies. The host messages come from the same session code and compile
/// parameters as `extension compile`; the recording pipelines them into one
/// guest process. Each reply is shown after its matching request so the
/// transcript follows the guest's processing order, without changing bodies.
async test "record native MEP host and guest sessions" {
  let environment = @platform.environment()
  guard environment.get("MORPHIR_MEP_RECORDINGS") is Some(destination) &&
    environment.get("MORPHIR_MEP_RECORD_GUEST") is Some(guest) else {
    return
  }
  if !@record_fs.exists(destination) {
    @record_fs.mkdir(destination, recursive=true)
  }
  let work = destination + "/guest-work"
  if !@record_fs.exists(work) {
    @record_fs.mkdir(work)
  }
  assert_true(@record_fs.readdir(work, include_hidden=true).is_empty())
  let source = destination + "/main.mbt"
  @record_fs.write_file(
    source, "pub fn eligible(active : Bool, vip : Bool) -> Bool { active && !vip }\n",
  )
  let cli = parse_cli([
    "extension",
    "compile",
    source,
    "--package",
    "boolean",
    "--output",
    destination + "/compiled",
    "--model-format",
    "ion",
  ])
  let inputs = ExtensionInputs::read(cli, Compile)
  let scratch = destination + "/plan.request.bin"
  let exit : Json = { "jsonrpc": "2.0", "method": "morphir.exit" }
  // The probe's describe opens the pipelined session.
  let (probe, step) = @worker.Conversation::probe()
  let plan = [recording_sends(step)[0]]
  let (_, _, _, replies) = recording_run(guest, work, scratch, plan + [exit])
  guard probe.on(recording_reply(replies, 1))
    is (_, Finished(Described(description), ..)) else {
    fail("the guest did not describe itself")
  }
  let claims = description.claims
  let offer = extension_compile_offer(claims, inputs.codec)
  let (language, documents) = extension_language(
    claims,
    extension_sources(inputs.path, extension_claimed_extensions(claims), () => {
      ()
    }),
  )
  let request = @worker.CompileRequest::new(
    extension_compile_params(inputs, claims, offer, language, documents, None),
  )
  // Step the operation session with the guest's replies to find each message.
  let add = (step : @worker.Step) => {
    for message in recording_sends(step) {
      plan.push(recording_shifted(message, 1))
    }
  }
  let replied = async fn(id : Int32) -> @worker.Event {
    let (_, _, _, replies) = recording_run(guest, work, scratch, plan + [exit])
    guard recording_reply(replies, id + 1) is Received(message) &&
      message.json() is Object(fields) else {
      fail("the guest gave no reply")
    }
    let fields = fields.copy()
    fields["id"] = Json::number(id.to_double())
    Received(@worker.Message::new(fields))
  }
  let (session, step) = @worker.Conversation::activate(offer, expected=claims)
  add(step)
  let (session, step) = session.on(replied(1))
  guard step is Activated(_, ..) else { fail("the guest did not initialize") }
  add(step)
  let (session, step) = session.compile(request)
  add(step)
  let (session, step) = session.on(replied(2))
  guard step is Answered(_, ..) else {
    fail("the guest did not answer compile")
  }
  let (session, step) = session.close()
  add(step)
  let (_, step) = session.on(replied(3))
  guard step is Finished(stop=CloseAfterExit, Closed, ..) else {
    fail("the guest did not acknowledge shutdown")
  }
  add(step)
  @record_fs.remove(scratch)
  for fault in [true, false] {
    let name = if fault { "missing-initialized" } else { "compile-ion" }
    let messages = if fault {
      plan.filter(message => {
        match message {
          Object(fields) =>
            fields.get("method") != Some(Json::string("morphir.initialized"))
          _ => true
        }
      })
    } else {
      plan
    }
    let request = destination + "/" + name + ".request.bin"
    let (code, err, out, replies) = recording_run(
      guest, work, request, messages,
    )
    assert_eq(code, 0)
    assert_eq(err, "")
    assert_true(@record_fs.readdir(work, include_hidden=true).is_empty())
    @record_fs.write_file(destination + "/" + name + ".response.bin", out)
    let transcript = StringBuilder()
    transcript.write_string("# Recorded MoonBit MEP session\n\n")
    let mut reply = 0
    for message in messages {
      transcript.write_string(
        "```jsonrpc host -> extension\n" + message.stringify() + "\n```\n\n",
      )
      if message is Object(fields) && fields.contains("id") {
        guard reply < replies.length() else { fail("Missing guest reply") }
        guard replies[reply] is Object(response_fields) else {
          fail("Invalid guest reply")
        }
        assert_eq(response_fields.get("id"), fields.get("id"))
        transcript.write_string(
          "```jsonrpc extension -> host\n" +
          replies[reply].stringify() +
          "\n```\n\n",
        )
        reply += 1
      }
    }
    assert_eq(reply, replies.length())
    @record_fs.write_file(
      destination + "/" + name + ".md",
      transcript.to_string(),
    )
    // The guest accepts this host fault. The Smithy state model must find it.
    guard offer is Model([tuple]) &&
      replies[2] is Object({ "result": result, .. }) else {
      fail("the compile did not answer with a result")
    }
    let (_, model) = extension_model_bytes(result, tuple)
    assert_true(model.length() > 0)
  }
}
