///|
fn request(
  operation : String,
  id~ : String = "",
  payload~ : Json? = None,
) -> String {
  let fields : Map[String, Json] = {
    "profile": "morphir/workbench/native",
    "contractVersion": "0.2.0-draft.1",
    "operation": Json::string(operation),
  }
  if operation != "session.open" {
    fields["sessionId"] = Json::string(id)
  }
  if payload is Some(payload) {
    fields["payload"] = payload
  }
  Json::object(fields).stringify()
}

///|
fn admit(source : String, operation : String) -> Json raise {
  @reply.decode(@utf8.encode(source), operation).to_json()
}

///|
fn value(source : String, operation : String) -> Json raise {
  let envelope = admit(source, operation)
  assert_eq(@wire.field(envelope, "ok"), Json::boolean(true), msg=source)
  @wire.field(envelope, "value")
}

///|
fn rejected(
  source : String,
  operation : String,
  code : String,
  effect : String,
) -> Unit raise {
  let envelope = admit(source, operation)
  assert_eq(@wire.field(envelope, "ok"), Json::boolean(false), msg=source)
  let error = @wire.field(envelope, "error")
  assert_eq(@wire.field(error, "code"), Json::string(code))
  assert_eq(@wire.field(error, "effect"), Json::string(effect))
}

///|
async fn run() -> Unit {
  if !@native.supported() {
    println("{\"nativeBridge\":false,\"unsupportedPlatform\":true}")
    return
  }
  let root = @env.current_dir().unwrap() +
    "/.dev/native-bridge-" +
    @env.now().to_string()
  @fs.mkdir(root)
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file(
    root + "/morphir.json",
    "{\"name\":\"demo/native\",\"exposedModules\":[]}",
  )
  let original = " \n" +
    @codec.to_json(@fixtures.invocation_library()).stringify() +
    "\n "
  @fs.write_file(root + "/morphir-ir.json", original)
  @async.with_task_group(async fn(group) {
    let owner = @bridge.Owner::new(
      group,
      @env.args()[0],
      executions=true,
      workspace=true,
    )
    let mut page = "page-1"
    let caller = fn() raise {
      @session.Caller::admit("main", "app", Some(page))
    }
    let picker = async fn() {
      @async.sleep(1)
      Some(root)
    }
    async fn send(operation : String, id : String, payload : Json?) -> String {
      owner.request(request(operation, id~, payload~), caller, picker)
    }
    let descriptor = value(send("session.open", "", None), "session.open")
    let id = @wire.string(@wire.field(descriptor, "sessionId"))
    assert_eq(value(send("session.open", "", None), "session.open"), descriptor)
    assert_eq(
      value(send("session.check", id, None), "session.check"),
      descriptor,
    )
    assert_eq(
      @wire.field(@wire.field(descriptor, "offer"), "sessionId"),
      Json::string(id),
    )
    rejected(
      owner.request("{\"operation\":1,\"operation\":2}", caller, picker),
      "session.open",
      "invalid_request",
      "none",
    )
    rejected(
      owner.request(
        request("session.open"),
        fn() raise { @session.Caller::admit("other", "app", Some(page)) },
        picker,
      ),
      "session.open",
      "unauthorized",
      "none",
    )
    let bad : Json = {
      "contractVersion": "0.2.0-draft.1",
      "model": "{}",
      "entry": "calls:main#subtract",
      "inputs": { "format": "json", "source": "[]" },
    }
    rejected(
      send("execution.submit", id, Some(bad)),
      "execution.submit",
      "invalid_request",
      "none",
    )
    let submitted : Json = {
      "contractVersion": "0.2.0-draft.1",
      "model": original,
      "entry": "calls:main#subtract",
      "inputs": { "format": "ion-text", "source": "[45,3]" },
    }
    let execution = value(
      send("execution.submit", id, Some(submitted)),
      "execution.submit",
    )
    let identity = @wire.field(execution, "identity")
    let payload : Json = {
      "contractVersion": "0.2.0-draft.1",
      "identity": identity,
    }
    let mut finished = false
    for _ in 0..<1000 {
      let receipt = value(
        send("execution.query", id, Some(payload)),
        "execution.query",
      )
      if @wire.field(receipt, "state") == Json::string("terminal") {
        let outcome = @wire.field(
          @wire.array(@wire.field(@wire.field(receipt, "outcomes"), "calls"))[0],
          "outcome",
        )
        assert_eq(@wire.field(outcome, "value"), {
          "type": "int",
          "value": "42",
        })
        finished = true
        break
      }
      @async.sleep(10)
    }
    assert_true(finished)
    ignore(
      value(send("execution.cancel", id, Some(payload)), "execution.cancel"),
    )
    ignore(
      value(send("execution.release", id, Some(payload)), "execution.release"),
    )
    rejected(
      send("execution.release", id, Some(payload)),
      "execution.release",
      "not_found",
      "none",
    )
    let offer = value(send("workspace.choose", id, None), "workspace.choose")
    let grant = @wire.field(offer, "grantId")
    let project = @wire.field(
      @wire.array(@wire.field(offer, "projects"))[0],
      "id",
    )
    let opened = value(
      send(
        "workspace.open",
        id,
        Some({ "grantId": grant, "projectId": project, "sequence": 1 }),
      ),
      "workspace.open",
    )
    assert_eq(
      @wire.field(opened, "size"),
      Json::number(@utf8.encode(original).length().to_double()),
    )
    let chunk = value(
      send(
        "workspace.read",
        id,
        Some({ "grantId": grant, "sequence": 1, "offset": 0 }),
      ),
      "workspace.read",
    )
    assert_eq(@wire.field(chunk, "done"), Json::boolean(true))
    assert_eq(
      @base64.decode(@wire.string(@wire.field(chunk, "content"))[:]),
      @utf8.encode(original),
    )
    ignore(
      value(
        send("workspace.release", id, Some({ "grantId": grant, "sequence": 1 })),
        "workspace.release",
      ),
    )
    rejected(
      send(
        "workspace.open",
        id,
        Some({ "grantId": grant, "projectId": project, "sequence": 1 }),
      ),
      "workspace.open",
      "conflict",
      "unknown",
    )
    ignore(
      value(
        send("workspace.revoke", id, Some({ "grantId": grant })),
        "workspace.revoke",
      ),
    )
    ignore(
      value(
        send("workspace.cancel-picker", id, None),
        "workspace.cancel-picker",
      ),
    )
    let mut started = false
    let mut finish = false
    let mut late : String? = None
    group.spawn_bg(async fn() {
      late = Some(
        owner.request(request("workspace.choose", id~), caller, async fn() {
          started = true
          while !finish {
            @async.sleep(5)
          }
          Some(root)
        }),
      )
    })
    while !started {
      @async.sleep(5)
    }
    page = "replacement"
    let replacement = value(send("session.open", "", None), "session.open")
    let replacement_id = @wire.string(@wire.field(replacement, "sessionId"))
    assert_true(replacement_id != id)
    finish = true
    while late == None {
      @async.sleep(5)
    }
    rejected(late.unwrap(), "workspace.choose", "unauthorized", "unknown")
    rejected(
      send("session.check", id, None),
      "session.check",
      "unauthorized",
      "none",
    )
    ignore(
      value(send("workspace.choose", replacement_id, None), "workspace.choose"),
    )
    ignore(value(send("session.close", replacement_id, None), "session.close"))
    rejected(
      send("session.check", replacement_id, None),
      "session.check",
      "unauthorized",
      "none",
    )
    owner.close()
    owner.shutdown()
    rejected(
      send("session.open", "", None),
      "session.open",
      "unauthorized",
      "unknown",
    )
  })
  println(
    "{\"nativeBridge\":true,\"operations\":13,\"workerResult\":42,\"latePickerRevocation\":true}",
  )
}

///|
async fn launch(raw : Array[String], structured : Bool) -> Unit {
  // Preserve the original whole-argv sentinel, including a caller-supplied argv[0].
  if @env.args()[0] == "--morphir-native-worker" ||
    raw.contains("--morphir-native-worker") {
    if !structured {
      @native.worker()
      return
    }
    event("startup", 0)
    // The transport has no initialization effects before its first read.
    event("ready", 1)
    @native.worker() catch {
      error => {
        event("diagnostic", 2, error=Some(error), exit_code=1)
        event("terminal", 3, exit_code=1)
        @sys.exit(1)
      }
    }
    event("terminal", 2)
    return
  }
  if structured {
    run() catch {
      error => {
        @stdio.stdout.write(failed(error).stringify() + "\n")
        @sys.exit(1)
      }
    }
  } else {
    run()
  }
}

///|
async fn main {
  match presentation(@env.args()[1:]) {
    JsonHelp => json_help()
    Legacy(raw) => launch(raw, false)
    Structured(raw) => launch(raw, true)
  }
}
