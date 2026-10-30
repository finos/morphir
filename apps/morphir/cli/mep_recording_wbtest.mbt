///|
/// Record the production host plan and the native guest's exact wire bodies.
/// The host pipelines requests. Show each reply after its matching request so
/// the transcript follows the guest's processing order, without changing bodies.
#cfg(target="native")
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
  let plan = extension_plan(cli, Compile)
  for fault in [true, false] {
    let name = if fault { "missing-initialized" } else { "compile-ion" }
    let messages = if fault {
      plan.messages.filter(message => {
        match message {
          Object(fields) =>
            fields.get("method") != Some(Json::string("morphir.initialized"))
          _ => true
        }
      })
    } else {
      plan.messages
    }
    let sent = { ..plan, messages, }
    let request = destination + "/" + name + ".request.bin"
    let bytes = extension_frames(sent)
    @record_fs.write_file(request, bytes)
    let input = @record_process.redirect_from_file(request)
    let (code, out, err) = @async.with_timeout(30000, async fn() {
      @record_process.collect_output(guest, [], stdin=input, cwd=work)
    })
    assert_eq(code, 0)
    assert_eq(err.text(), "")
    assert_true(@record_fs.readdir(work, include_hidden=true).is_empty())
    @record_fs.write_file(
      destination + "/" + name + ".response.bin",
      out.binary(),
    )
    let decoder = @mep.Decoder::new()
    let bodies = decoder.feed(out.binary())
    decoder.finish()
    let replies = bodies.map(body => @utf8.decode(body[:]))
    let request_decoder = @mep.Decoder::new()
    let requests = request_decoder
      .feed(bytes)
      .map(body => @utf8.decode(body[:]))
    request_decoder.finish()
    let transcript = StringBuilder()
    transcript.write_string("# Recorded MoonBit MEP session\n\n")
    let mut reply = 0
    for body in requests {
      let message = @json.parse(body)
      transcript.write_string(
        "```jsonrpc host -> extension\n" + body + "\n```\n\n",
      )
      if message is Object(fields) && fields.contains("id") {
        guard reply < replies.length() else { fail("Missing guest reply") }
        let response = @json.parse(replies[reply])
        guard response is Object(response_fields) else {
          fail("Invalid guest reply")
        }
        assert_eq(response_fields.get("id"), fields.get("id"))
        transcript.write_string(
          "```jsonrpc extension -> host\n" + replies[reply] + "\n```\n\n",
        )
        reply += 1
      }
    }
    assert_eq(reply, replies.length())
    @record_fs.write_file(
      destination + "/" + name + ".md",
      transcript.to_string(),
    )
    let outcome = extension_outcome(
      sent,
      {
        state: "exited",
        exit_code: Some(code),
        stderr: err.text(),
        error: "",
        work_directory_empty: true,
      },
      out.binary(),
    )
    // The guest accepts this host fault. The Smithy state model must find it.
    assert_eq(outcome.exit_code, 0)
    let (_, model) = extension_model_bytes(outcome.result, IonModel)
    assert_true(model.length() > 0)
  }
}
