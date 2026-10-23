///|
enum Invocation {
  Checks
  Fixture(String)
  Race(String)
} derive(Eq)

///|
fn invocation(arguments : ArrayView[String]) -> Invocation {
  let command = @argparse.Command(
    "workspace-acceptance",
    disable_help_flag=true,
    disable_version_flag=true,
    disable_help_subcommand=true,
    subcommands=["fixture", "race"].map(name => {
      @argparse.Command(
        name,
        disable_help_flag=true,
        disable_version_flag=true,
        disable_help_subcommand=true,
        positionals=[
          @argparse.PositionArg("path", num_args=@argparse.ValueRange::single()),
        ],
      )
    }),
  )
  // Only the first token is command syntax. Preserve all following tokens as
  // literal path data, including --, without inspecting their contents.
  let literal : Array[String] = []
  if !arguments.is_empty() {
    literal.push(arguments[0])
    literal.push("--")
    literal.append(arguments[1:])
  }
  let matches = command.parse(argv=literal, env=Map([])) catch {
    // Every unrecognized invocation has historically run the default checks.
    _ => return Checks
  }
  match matches.subcommand {
    Some(("fixture", values)) => Fixture(values.values["path"][0])
    Some(("race", values)) => Race(values.values["path"][0])
    _ => Checks
  }
}

///|
fn denied(body : () -> Bytes raise) -> Unit raise {
  let rejected = try {
    ignore(body())
    false
  } catch {
    @workspace.Rejected(_) => true
    error => raise error
  }
  assert_true(rejected)
}

///|
fn send(
  service : @workspace.Service,
  body : Json,
  sequence~ : Int32 = 1,
) -> Json raise {
  let body = match body {
    Object(fields) if ["open", "read", "release"].contains(
        @wire.string(@wire.field(body, "action")),
      ) => {
      let fields = fields.copy()
      fields["sequence"] = Json::number(sequence.to_double())
      Json::object(fields)
    }
    _ => body
  }
  service.request(body.stringify())
}

///|
fn accepted(value : Json) -> Json raise {
  assert_eq(
    @wire.field(value, "ok"),
    Json::boolean(true),
    msg=value.stringify(),
  )
  value
}

///|
async fn main {
  if !@workspace.supported() {
    println("{\"nativeWorkspace\":false,\"unsupportedPlatform\":true}")
    return
  }
  let args = @env.args()
  let selected = invocation(args[1:])
  if selected is Fixture(path) {
    @fs.mkdir(path, allow_exist=true)
    for child in ["legacy", "rich"] {
      @fs.mkdir(path + "/" + child, allow_exist=true)
    }
    @fs.write_file(
      path + "/morphir.toml",
      "[workspace]\nmembers=['legacy','rich']\n",
    )
    for child in ["legacy", "rich"] {
      @fs.write_file(
        path + "/" + child + "/morphir.json",
        "{\"name\":\"demo/" + child + "\",\"exposedModules\":[]}",
      )
    }
    @fs.write_file(
      path + "/legacy/morphir-ir.json",
      @fs.read_file("pkgs/morphir-ir/conformance/fixtures/v1-rentals.json"),
    )
    let compiled = @pipeline.execute({
      "operation": "compile",
      "source": "pub fn eligible(activeUser : Bool, vipMember : Bool) -> Bool { activeUser && !vipMember }",
      "languageId": "moonbit",
      "frontendProvider": "finos/morphir-moonbit-frontend",
      "frontendProfile": "moonbit-model-stable-v1",
      "target": "",
    })
    assert_eq(
      @wire.field(compiled, "success"),
      Json::boolean(true),
      msg=compiled.stringify(),
    )
    let text = @wire.string(@wire.field(compiled, "sourceUnitIon"))
    @fs.write_file(path + "/rich/morphir-ir.ion", text)
    let registry = @data.Registry::new()
    let unit = registry.open_checkpoint("ion-text", @data.Text(text))
    guard registry.encode("ion-binary", unit) is @data.Binary(bytes) else {
      abort("binary checkpoint required")
    }
    @fs.write_file(path + "/rich/morphir-ir.ionb", bytes)
    @fs.write_file(path + "/rich/morphir-ir.10n", bytes)
    println("Native UI fixture written")
    return
  }
  if selected is Race(base) {
    for _ in 0..<150 {
      @fs.rename(base + "/root/active", base + "/root/saved")
      @fs.symlink(target=base + "/outside", base + "/root/active")
      @async.sleep(1)
      @fs.remove(base + "/root/active")
      @fs.rename(base + "/root/saved", base + "/root/active")
      @async.sleep(1)
    }
    return
  }
  let base = @env.current_dir().unwrap() +
    "/.dev/native-workspace-" +
    @env.now().to_string()
  @fs.mkdir(base, recursive=true)
  defer @fs.rmdir(base, recursive=true)
  @fs.mkdir(base + "/root")
  @fs.mkdir(base + "/outside")
  @fs.mkdir(base + "/root/active")
  @fs.write_file(base + "/root/active/value", "inside")
  @fs.write_file(base + "/outside/value", "SECRET")
  let root = @workspace.Root::open(base + "/root")
  defer root.close()
  assert_eq(root.read("active/value"), b"inside")
  for
    path in [
      "../outside/value", "/etc/passwd", "active/../active/value", "active//value",
      "C:evil", "active\\value", "active/value\u0000ignored",
    ] {
    denied(fn() raise { root.read(path) })
  }
  @fs.symlink(target=base + "/outside/value", base + "/root/link")
  denied(fn() raise { root.read("link") })
  @fs.remove(base + "/root/link")
  assert_eq(
    @process.run("ln", [base + "/outside/value", base + "/root/hardlink"]),
    0,
  )
  denied(fn() raise { root.read("hardlink") })
  @fs.remove(base + "/root/hardlink")
  assert_eq(@process.run("mkfifo", [base + "/root/pipe"]), 0)
  denied(fn() raise { root.read("pipe") })
  @fs.remove(base + "/root/pipe")
  denied(fn() raise { root.read("active/value", limit=3) })
  @fs.write_file(
    base + "/root/morphir.json",
    "{\"name\":\"demo/project\",\"sourceDirectory\":\"src\",\"exposedModules\":[\"Main\"]}",
  )
  let original = b"  {\"formatVersion\":1,\"unchanged\":true}\n"
  @fs.write_file(base + "/root/morphir-ir.json", original)
  let service = @workspace.Service::new()
  defer service.close()
  let ticket = service.begin_choose()
  let offer = accepted(service.finish_choose(ticket, Some(base + "/root")))
  let grant = @wire.field(offer, "grantId")
  let projects = @wire.array(@wire.field(offer, "projects"))
  assert_eq(projects.length(), 1)
  assert_eq(@wire.field(projects[0], "name"), Json::string("demo/project"))
  let id = @wire.field(projects[0], "id")
  let opened = accepted(
    send(service, { "action": "open", "grantId": grant, "projectId": id }),
  )
  assert_eq(
    @wire.field(opened, "size"),
    Json::number(original.length().to_double()),
  )
  let read = accepted(
    send(service, { "action": "read", "grantId": grant, "offset": 0 }),
  )
  assert_eq(
    @base64.decode(@wire.string(@wire.field(read, "content"))[:]),
    original,
  )
  assert_eq(@wire.field(read, "done"), Json::boolean(true))
  ignore(accepted(send(service, { "action": "release", "grantId": grant })))
  assert_eq(
    @wire.field(
      service.request("{\"action\":\"open\",\"action\":\"read\"}"),
      "ok",
    ),
    Json::boolean(false),
  )
  assert_eq(
    @wire.field(
      send(service, {
        "action": "open",
        "grantId": grant,
        "projectId": "../../outside/value",
      }),
      "ok",
    ),
    Json::boolean(false),
  )
  let cancelled = service.begin_choose()
  ignore(accepted(service.finish_choose(cancelled, None)))
  // A cancelled picker keeps the existing grant and its original bytes usable.
  ignore(
    accepted(
      send(
        service,
        { "action": "open", "grantId": grant, "projectId": id },
        sequence=2,
      ),
    ),
  )
  ignore(
    accepted(
      send(service, { "action": "release", "grantId": grant }, sequence=2),
    ),
  )
  let stale = service.begin_choose()
  service.cancel_choose()
  let rejected = try {
    ignore(service.finish_choose(stale, Some(base + "/root")))
    false
  } catch {
    @workspace.Rejected(_) => true
    error => raise error
  }
  assert_true(rejected)
  // A retired picker can finish after a replacement picker has started.
  // Its failure cleanup must not cancel that newer native dialog.
  let replacement = service.begin_choose()
  let late_rejected = try {
    ignore(service.finish_choose(stale, Some(base + "/root")))
    false
  } catch {
    @workspace.Rejected(_) => true
    error => raise error
  }
  assert_true(late_rejected)
  service.cancel_choose_if_current(stale)
  ignore(accepted(service.finish_choose(replacement, None)))
  // Matching cleanup releases its own ticket and remains safe to repeat.
  let failed = service.begin_choose()
  service.cancel_choose_if_current(failed)
  service.cancel_choose_if_current(failed)
  let after_failure = service.begin_choose()
  ignore(accepted(service.finish_choose(after_failure, None)))
  ignore(
    accepted(
      send(
        service,
        { "action": "open", "grantId": grant, "projectId": id },
        sequence=3,
      ),
    ),
  )
  let retained = accepted(
    send(
      service,
      { "action": "read", "grantId": grant, "offset": 0 },
      sequence=3,
    ),
  )
  assert_eq(
    @base64.decode(@wire.string(@wire.field(retained, "content"))[:]),
    original,
  )
  ignore(
    accepted(
      send(service, { "action": "release", "grantId": grant }, sequence=3),
    ),
  )
  @fs.write_file(
    base + "/root/morphir.json",
    "{\"name\":\"changed\",\"exposedModules\":[]}",
  )
  assert_eq(
    @wire.field(
      send(
        service,
        { "action": "open", "grantId": grant, "projectId": id },
        sequence=4,
      ),
      "code",
    ),
    Json::string("workbench.workspace_changed"),
  )
  service.revoke()
  assert_eq(
    @wire.field(
      send(service, { "action": "read", "grantId": grant, "offset": 0 }),
      "ok",
    ),
    Json::boolean(false),
  )
  @fs.mkdir(base + "/nested")
  @fs.mkdir(base + "/nested/a")
  @fs.mkdir(base + "/nested/b")
  @fs.write_file(
    base + "/nested/morphir.toml",
    "[workspace]\nmembers=['a','b']\nout_dir='cache'\n",
  )
  @fs.write_file(
    base + "/nested/a/morphir.json",
    "{\"name\":\"demo/a\",\"exposedModules\":[]}",
  )
  @fs.write_file(
    base + "/nested/b/morphir.json",
    "{\"name\":\"invalid\",\"exposedModules\":false}",
  )
  // Engine output layout and byte markers determine the checkpoint codec,
  // including binary Ion stored with the conventional .10n extension.
  for path in ["cache", "cache/a", "cache/a/compile.dest"] {
    @fs.mkdir(base + "/nested/" + path)
  }
  let binary = b"\xe0\x01\x00\xea" + Bytes::make(499996, 0x81)
  @fs.write_file(base + "/nested/cache/a/compile.dest/demo.10n", binary)
  let nested = @workspace.Service::new()
  defer nested.close()
  let nested_offer = accepted(
    nested.finish_choose(nested.begin_choose(), Some(base + "/nested")),
  )
  let nested_projects = @wire.array(@wire.field(nested_offer, "projects"))
  assert_eq(nested_projects.length(), 2)
  assert_eq(@wire.field(nested_projects[0], "name"), Json::string("demo/a"))
  assert_eq(@wire.field(nested_projects[0], "available"), Json::boolean(true))
  assert_eq(@wire.field(nested_projects[1], "available"), Json::boolean(false))
  let ng = @wire.field(nested_offer, "grantId")
  let binary_open = accepted(
    send(nested, {
      "action": "open",
      "grantId": ng,
      "projectId": @wire.field(nested_projects[0], "id"),
    }),
  )
  assert_eq(@wire.field(binary_open, "format"), Json::string("ion-binary"))
  assert_eq(
    @wire.field(
      send(nested, { "action": "read", "grantId": ng, "offset": 1 }),
      "ok",
    ),
    Json::boolean(false),
  )
  let mut recovered = b""
  while recovered.length() < binary.length() {
    let chunk = accepted(
      send(nested, {
        "action": "read",
        "grantId": ng,
        "offset": recovered.length(),
      }),
    )
    let bytes = @base64.decode(@wire.string(@wire.field(chunk, "content"))[:])
    assert_true(bytes.length() <= 192 * 1024)
    recovered = recovered + bytes
  }
  assert_eq(recovered, binary)
  ignore(accepted(send(nested, { "action": "release", "grantId": ng })))
  ignore(
    accepted(send(nested, { "action": "release", "grantId": ng }, sequence=2)),
  )
  assert_eq(
    @wire.field(
      send(
        nested,
        {
          "action": "open",
          "grantId": ng,
          "projectId": @wire.field(nested_projects[0], "id"),
        },
        sequence=2,
      ),
      "code",
    ),
    Json::string("workbench.workspace_retired"),
  )
  ignore(
    accepted(
      send(
        nested,
        {
          "action": "open",
          "grantId": ng,
          "projectId": @wire.field(nested_projects[0], "id"),
        },
        sequence=3,
      ),
    ),
  )
  assert_eq(
    @wire.field(
      send(nested, { "action": "release", "grantId": ng }, sequence=2),
      "code",
    ),
    Json::string("workbench.workspace_capture"),
  )
  ignore(
    accepted(
      send(nested, { "action": "read", "grantId": ng, "offset": 0 }, sequence=3),
    ),
  )
  ignore(
    accepted(send(nested, { "action": "release", "grantId": ng }, sequence=3)),
  )
  let bounded_root = @workspace.Root::open(base + "/nested")
  defer bounded_root.close()
  @fs.write_file(
    base + "/nested/too-large",
    Bytes::make(16 * 1024 * 1024 + 1, 0x00),
  )
  denied(fn() raise { bounded_root.read("too-large") })
  @fs.write_file(
    base + "/nested/morphir.toml",
    Bytes::make(256 * 1024 + 1, 0x20),
  )
  let over = try {
    ignore(nested.finish_choose(nested.begin_choose(), Some(base + "/nested")))
    false
  } catch {
    @workspace.Rejected(code) => {
      assert_eq(code, "workbench.workspace_quota")
      true
    }
    error => raise error
  }
  assert_true(over)
  // Actual concurrent namespace mutation in another OS process. Every accepted
  // read must contain authorized bytes, never the linked outside secret.
  let writer = @workspace.WriteRoot::open(base + "/root")
  defer writer.close()
  let write_snapshot = writer.snapshot()
  @async.with_task_group(async fn(group) {
    let mut done : Int32? = None
    let mut writer_uncertain = false
    group.spawn_bg(async fn() {
      done = Some(@process.run(args[0], ["race", base]))
    })
    for _ in 0..<350 {
      if !writer_uncertain {
        writer.apply(write_snapshot, {
          writes: Map::from_array([("active/value", b"inside")]),
          deletes: [],
          directories: [],
          remove_directories: [],
        }) catch {
          @workspace.Rejected(_) => ()
          @workspace.Uncertain(_) => writer_uncertain = true
          error => raise error
        }
      }
      assert_eq(root.read("active/value"), b"inside") catch {
        @workspace.Rejected(_) => ()
        error => raise error
      }
      @async.sleep(2)
    }
    for _ in 0..<1000 {
      if done != None {
        break
      }
      @async.sleep(5)
    }
    assert_eq(done, Some(0))
    assert_eq(@fs.read_file(base + "/outside/value").binary(), b"SECRET")
  })
  @fs.rename(base + "/root", base + "/old-root")
  @fs.mkdir(base + "/root")
  denied(fn() raise { root.read("active/value") })
  root.close()
  root.close()
  denied(fn() raise { root.read("active/value") })
  println(
    "{\"nativeWorkspace\":true,\"containment\":true,\"concurrentReplacement\":true,\"concurrentWritesConfined\":true,\"originalBytes\":true,\"revocation\":true,\"pickerCancellation\":true}",
  )
}
