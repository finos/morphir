///|
async fn publish_orders_product(
  root : String,
  module_path : String,
  fixture : String,
) -> Unit {
  let destination = "relocated/" + module_path + "/compile.dest"
  let publisher = @host.ContentPublisher::filesystem(root, "relocated", compile_record={
    explicit_selection: false,
    tree_product: Some("model"),
  })
  let publication = (publisher.begin)([destination])
  defer (publication.abort)()
  for
    path in [
      "manifest.json", "pkg/acme/orders/audit/module.json", "pkg/acme/orders/domain/module.json",
      "pkg/acme/orders/domain/order.type.json", "pkg/acme/orders/domain/order.value.json",
      "pkg/acme/orders/domain/total-in-_usd.value.json", "deps/morphir/_sdk/@/basics/module.json",
      "deps/morphir/_sdk/@/basics/int.type.json", "deps/morphir/_sdk/@/basics/add.value.json",
    ] {
    let bytes = @fs.read_file(fixture + "/" + path).binary()
    (publication.stage)({
      path: destination + "/model/" + path,
      source: path,
      content: @data.Binary(bytes),
      format: "morphir-json",
      ir_json_version: if path == "manifest.json" {
        Some(@version.FormatVersion::baseline(4U))
      } else {
        None
      },
    })
  }
  (publication.commit)(destination)
}

///|
async fn wait_for_compile_lock(errors : @process.ReadFromProcess) -> String {
  for ;; {
    guard errors.read_until("\n") is Some(line) else {
      fail("native compile exited without waiting for the task lock")
    }
    if line.contains("waiting for another Morphir run to finish compile") {
      return line
    }
    println(line)
  }
}

///|
async test "native compile waits for the recorded producer capture and invalidates the replaced tree" {
  guard @platform.system_type() != "windows" &&
    @env.get_env_var("MORPHIR_MEP_COMPILE_LEASE") == Some("1") else {
    return
  }
  let host = @fs.realpath(@env.get_env_var("MORPHIR_MEP_BOUNDED_HOST").unwrap())
  let digest = @identity.sha256(@fs.read_file(host).binary())
  assert_eq(
    digest,
    @env.get_env_var("MORPHIR_MEP_BOUNDED_HOST_SHA256").unwrap(),
  )
  let repository = @fs.realpath(
    @env.get_env_var("MORPHIR_MEP_BOUNDED_REPOSITORY").unwrap(),
  )
  let fixture = repository +
    "/apps/morphir-extension/acceptance/fixtures/acme-orders-v4/plain-json"
  let root = @fs.tmpdir(prefix="morphir-compile-lease-")
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file(
    root + "/morphir.toml",
    "[workspace]\nmembers=['packages/*']\n",
  )
  let orders = "packages/orders"
  let sibling = "packages/other"
  for (module_path, name) in [(orders, "Orders"), (sibling, "Other")] {
    let member_root = root + "/" + module_path
    @fs.mkdir(member_root + "/src", recursive=true)
    @fs.write_file(
      member_root + "/morphir.toml",
      "[project]\nname='" + name + "'\nsource_directory='src'\n",
    )
    @fs.write_file(
      member_root + "/src/Main.mbt",
      "pub fn ready(active : Bool) -> Bool { !active }\n",
    )
    publish_orders_product(root, module_path, fixture)
  }
  let parent = root + "/relocated/" + orders
  let record = parent + "/compile.json"
  let other_record = root + "/relocated/" + sibling + "/compile.json"
  let before = @fs.read_file(record).binary()
  let other_before = @fs.read_file(other_record).binary()
  let record_json = @model_wire.parse_bounded(@utf8.decode(before[:]))
  assert_eq(@model_wire.field(record_json, "module"), Json::string(orders))
  assert_eq(@model_wire.field(record_json, "value"), ["model"])
  assert_eq(
    @model_wire.field(@model_wire.field(record_json, "ir"), "layout"),
    Json::string("document-tree"),
  )
  let task_dir = @platform.BoundedDirectory::open(parent)
  defer task_dir.close()
  let lock_before = task_dir.stamp(name="compile.lock")
  let source : TreeGenerationInput = CompileResult(record)
  let opened = source.open(() => ())
  defer (opened.release)()
  let command = [
    "compile", "--project", "Orders", "--output", "relocated", "--json",
  ]
  let environment = { "MORPHIR_HOME": root + "/home" }
  let root_directory = @platform.BoundedDirectory::open(root)
  defer root_directory.close()
  root_directory.mkdir("capture")
  let scratch = root_directory.child("capture")
  defer scratch.close()
  @async.with_timeout(10000, async fn() {
    @async.with_task_group(async fn(group) {
      let (errors, stderr) = @process.read_from_process()
      defer errors.close()
      let cancellation = root + "/cancel"
      let cancelled_log = root + "/cancelled.json"
      let cancelled = @process.spawn(
        group,
        host,
        command + ["--cancel-file", cancellation],
        cwd=root,
        extra_env=environment,
        stderr~,
        stdout=@process.redirect_to_file(cancelled_log),
      )
      println(wait_for_compile_lock(errors))
      assert_eq(cancelled.try_wait(), None)
      assert_false(@fs.exists(root + "/relocated/.morphir-publish.lock"))
      @fs.write_file(cancellation, "")
      assert_eq(cancelled.wait(), 130)
      let report = @fs.read_file(cancelled_log).json()
      assert_eq(
        @model_wire.field(@model_wire.field(report, "error"), "code"),
        Json::string("compile.cancelled"),
      )
      assert_eq(@fs.read_file(record).binary(), before)
      println(
        "compile cancelled while the capture lease remained held, exit 130",
      )
    })
    @async.with_task_group(async fn(group) {
      let (errors, stderr) = @process.read_from_process()
      defer errors.close()
      let writer_log = root + "/compile-result.json"
      let writer = @process.spawn(
        group,
        host,
        command,
        cwd=root,
        extra_env=environment,
        stderr~,
        stdout=@process.redirect_to_file(writer_log),
      )
      println(wait_for_compile_lock(errors))
      assert_eq(writer.try_wait(), None)
      assert_eq(@fs.read_file(record).binary(), before)
      let captured = capture_tree(
        opened.reopen,
        opened.directory,
        scratch,
        root_directory.stamp(),
        () => assert_eq(writer.try_wait(), None),
      )
      (opened.release)()
      assert_eq(writer.wait(), 0)
      let result = @fs.read_file(writer_log).json()
      assert_eq(@model_wire.field(result, "state"), Json::string("succeeded"))
      assert_true(@fs.exists(parent + "/compile.dest/Main.ionb"))
      assert_false(@fs.exists(parent + "/compile.dest/model"))
      assert_eq(task_dir.stamp(name="compile.lock"), lock_before)
      assert_eq(@fs.read_file(other_record).binary(), other_before)
      assert_true(
        @fs.exists(
          root + "/relocated/" + sibling + "/compile.dest/model/manifest.json",
        ),
      )
      let replacement = @fs.read_file(record).json()
      assert_eq(@model_wire.field(replacement, "value"), ["Main.ionb"])
      assert_eq(@model_wire.optional(replacement, "ir"), None)
      let refused = try {
        let stale = source.open(() => ())
        (stale.release)()
        false
      } catch {
        TreeSource(message) => message.contains("no IR descriptor")
        error => raise error
      }
      assert_true(refused)
      let view = @yaml.open_bounded_tree(
        captured.tree_source(() => ()),
        split_members_only=true,
      )
      let (_, manifest) = view.read_original_document(@yaml.ManifestArtifact)
      assert_eq(manifest, @fs.read_file(fixture + "/manifest.json").text())
      println(
        "compile replaced the product after capture, preserved the lock and sibling, and retired the stale descriptor",
      )
    })
  })
  let unrelated_output = "relocated/" + sibling + "/compile.dest"
  let legacy = @host.ContentPublisher::filesystem(root, "relocated")
  let replacement = (legacy.begin)([unrelated_output])
  (replacement.commit)(unrelated_output)
  (replacement.abort)()
  let tombstone = @fs.read_file(other_record).json()
  assert_eq(@model_wire.field(tombstone, "tombstone"), Json::boolean(true))
  let retired : TreeGenerationInput = CompileResult(other_record)
  let refused = try {
    let previous = retired.open(() => ())
    (previous.release)()
    false
  } catch {
    TreeSource(message) => message.contains("tombstone")
    error => raise error
  }
  assert_true(refused)
  println(
    "an unrecorded compile.dest replacement retired its old result with a reader-visible tombstone",
  )
}

///|
async fn write_lease_guest_pin(root : String, args : Array[String]) -> String {
  let guest = @fs.realpath(
    @env.get_env_var("MORPHIR_MEP_BOUNDED_GUEST").unwrap(),
  )
  let digest = @identity.sha256(@fs.read_file(guest).binary())
  assert_eq(
    digest,
    @env.get_env_var("MORPHIR_MEP_BOUNDED_GUEST_SHA256").unwrap(),
  )
  let platform = @env.get_env_var("MORPHIR_MEP_PLATFORM").unwrap()
  let pin = root + "/pin.json"
  let content : Json = {
    "contractVersion": "0.2.0",
    "artifact": { "path": guest, "sha256": digest },
    "runtime": { "kind": "process", "platform": platform, "args": args },
    "origin": "bounded producer lease regression",
  }
  @fs.write_file(pin, content.stringify())
  pin
}

///|
async fn live_lease_host() -> (String, String) {
  let host = @fs.realpath(@env.get_env_var("MORPHIR_MEP_BOUNDED_HOST").unwrap())
  assert_eq(
    @identity.sha256(@fs.read_file(host).binary()),
    @env.get_env_var("MORPHIR_MEP_BOUNDED_HOST_SHA256").unwrap(),
  )
  let repo = @fs.realpath(
    @env.get_env_var("MORPHIR_MEP_BOUNDED_REPOSITORY").unwrap(),
  )
  (
    host,
    repo +
    "/apps/morphir-extension/acceptance/fixtures/acme-orders-v4/plain-json",
  )
}

///|
fn live_generate(
  record : String,
  output : String,
  pin : String,
) -> Array[String] {
  [
    "extension", "generate", "--task-result", record, "--target", "moonbit", "--output",
    output, "--extension-pin", pin, "--timeout", "10000", "--json",
  ]
}

///|
async test "recorded generation refuses a fresh sibling anywhere inside compile.dest" {
  guard @platform.system_type() != "windows" &&
    @env.get_env_var("MORPHIR_MEP_COMPILE_LEASE") == Some("1") else {
    return
  }
  let (host, fixture) = live_lease_host()
  let root = @fs.tmpdir(prefix="morphir-compile-dest-output-")
  defer @fs.rmdir(root, recursive=true)
  publish_orders_product(root, "orders", fixture)
  let pin = write_lease_guest_pin(root, [])
  let task = root + "/relocated/orders"
  let dest = task + "/compile.dest"
  let before = @fs.readdir(dest, include_hidden=true)
  let (code, stdout, _) = @async.with_timeout(6000, () => {
    @process.collect_output(
      host,
      live_generate(task + "/compile.json", dest + "/fresh", pin),
      cwd=root,
      extra_env={ "MORPHIR_HOME": root + "/home" },
    )
  })
  println("recorded compile.dest sibling exit=\{code} \{stdout.text()}")
  assert_eq(code, 1)
  let report = @model_wire.parse_bounded(stdout.text())
  let error = @model_wire.field(report, "error")
  assert_eq(
    @model_wire.field(error, "code"),
    Json::string("extension.output_failed"),
  )
  assert_true(
    @model_wire.string(@model_wire.field(error, "message")).contains(
      "inside_source",
    ),
  )
  assert_eq(@fs.readdir(dest, include_hidden=true), before)
}

///|
async fn wait_for_guest_gate(
  path : String,
  generator : @process.Process,
) -> Unit {
  @async.with_timeout(3500, async fn() {
    while !@fs.exists(path) {
      guard generator.try_wait() is None else {
        fail("native generator exited before the gate " + path)
      }
      @async.sleep(10)
    }
  })
}

///|
async test "real compile waits through the final lazy batch and generation settlement" {
  guard @platform.system_type() != "windows" &&
    @env.get_env_var("MORPHIR_MEP_COMPILE_LEASE") == Some("1") else {
    return
  }
  let (host, fixture) = live_lease_host()
  let failures : Array[String] = []
  for scenario in ["success", "cancel", "reject", "force"] {
    live_compile_during_generation(host, fixture, scenario) catch {
      error => failures.push(scenario + ": " + error.to_string())
    }
  }
  guard failures.is_empty() else { fail(failures.join("\n")) }
}

///|
async fn live_compile_during_generation(
  host : String,
  fixture : String,
  scenario : String,
) -> Unit {
  let root = @fs.tmpdir(prefix="morphir-live-compile-lease-")
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file(root + "/morphir.toml", "[workspace]\nmembers=['orders']\n")
  @fs.mkdir(root + "/orders/src", recursive=true)
  @fs.write_file(
    root + "/orders/morphir.toml",
    "[project]\nname='Orders'\nsource_directory='src'\n",
  )
  @fs.write_file(
    root + "/orders/src/Main.mbt",
    "pub fn ready(active : Bool) -> Bool { !active }\n",
  )
  publish_orders_product(root, "orders", fixture)
  let pin = write_lease_guest_pin(root, ["lease", scenario, root])
  let task = root + "/relocated/orders"
  let record = task + "/compile.json"
  let before = @fs.read_file(record).binary()
  let output = root + "/out"
  let generate_stdout = root + "/generate.json"
  let generate_stderr = root + "/generate.stderr"
  let cancellation = root + "/cancel"
  let extra_env = { "MORPHIR_HOME": root + "/home" }
  @async.with_timeout(14000, () => {
    @async.with_task_group(group => {
      let generator = @process.spawn(
        group,
        host,
        live_generate(record, output, pin) + ["--cancel-file", cancellation],
        cwd=root,
        extra_env~,
        stdout=@process.redirect_to_file(generate_stdout),
        stderr=@process.redirect_to_file(generate_stderr),
      )
      wait_for_guest_gate(root + "/paused", generator) catch {
        error =>
          fail(
            "guest did not reach its final-read gate: " +
            error.to_string() +
            " " +
            @fs.read_file(generate_stdout).text(),
          )
      }
      let (errors, stderr) = @process.read_from_process()
      defer errors.close()
      let writer = @process.spawn(
        group,
        host,
        ["compile", "--project", "Orders", "--output", "relocated", "--json"],
        cwd=root,
        extra_env~,
        stderr~,
        stdout=@process.redirect_to_file(root + "/compile-result.json"),
      )
      let waiting = wait_for_compile_lock(errors) catch {
        _ =>
          fail("real compile replaced the product before the final lazy batch")
      }
      assert_eq(writer.try_wait(), None)
      assert_eq(@fs.read_file(record).binary(), before)
      assert_false(@fs.exists(root + "/relocated/.morphir-publish.lock"))
      if scenario == "cancel" {
        @fs.write_file(cancellation, "")
      } else {
        @fs.write_file(root + "/resume", "")
      }
      if scenario == "force" {
        wait_for_guest_gate(root + "/exiting", generator)
        assert_eq(writer.try_wait(), None)
        assert_eq(@fs.read_file(record).binary(), before)
      }
      let code = generator.wait()
      assert_eq(writer.wait(), 0)
      let response = @fs.read_file(generate_stdout).json()
      let (expected, expected_error) = match scenario {
        "success" => (0, "")
        "cancel" => (130, "extension.cancelled")
        "force" => (124, "extension.deadline")
        _ => (1, "extension.operation_unsuccessful")
      }
      println(
        "live lease \{scenario}: \{waiting} generation exit=\{code}, compile exit=0",
      )
      assert_eq(code, expected)
      if expected == 0 {
        assert_eq(@fs.read_file(output + "/order.txt").text(), "73\n")
      } else {
        assert_false(@fs.exists(output))
        assert_eq(
          @model_wire.field(@model_wire.field(response, "error"), "code"),
          Json::string(expected_error),
        )
      }
      assert_false(
        @fs.readdir(root, include_hidden=true)
        .iter()
        .any(name => {
          name.has_prefix(".morphir-bounded-") ||
          name.has_prefix(".morphir-source-")
        }),
      )
      assert_true(@fs.exists(task + "/compile.dest/Main.ionb"))
    })
  })
}

///|
struct RecordedExitChannel {
  task : @platform.BoundedDirectory
  root : String
  status : StopStatus
  reject_exit : Bool
  mut next : Message?
  mut exit_accepted : Bool
  mut settled : Bool
  offers : Array[Json]
  mut launched_limits : Limits?
}

///|
impl Launcher for RecordedExitChannel with fn launch(self, _, limits) {
  self.launched_limits = Some(limits)
  self
}

///|
impl Channel for RecordedExitChannel with fn send(self, message) {
  let fields = @model_wire.object(message.json())
  guard fields.get("method") is Some(String(method_)) else {
    fail("missing request method")
  }
  if method_ == "morphir.exit" {
    if self.reject_exit {
      raise TransportFailed("exit write failed")
    }
    self.exit_accepted = true
    return
  }
  guard fields.get("id") is Some(id) else { return }
  let result : Json = match method_ {
    "morphir.initialize" => {
      self.offers.push(@model_wire.field(fields["params"], "modelAccess"))
      {
        "protocolVersion": "0.2.0-draft.2",
        "extension": {
          "id": "org.finos.morphir.orders",
          "name": "Orders",
          "version": "0.1.0",
          "types": ["backend"],
        },
        "capabilities": {
          "backend": {
            "targets": ["text"],
            "irVersions": ["4.0.0"],
            "generate": false,
          },
          "modelAccess": @model_wire.field(fields["params"], "modelAccess"),
        },
      }
    }
    "morphir.backend.generateModel.start" => {
      assert_eq(
        @model_wire.field(fields["params"], "limits"),
        @model_wire.field(self.offers[0], "limits"),
      )
      let artifact = b"73\n"
      {
        "sessionId": @model_wire.field(fields["params"], "sessionId"),
        "state": "complete",
        "diagnostics": [],
        "artifacts": [
          {
            "path": "order.txt",
            "offset": 0,
            "end": true,
            "decodedByteLength": artifact.length(),
            "sha256": @identity.sha256(artifact),
            "content": @base64.encode(artifact[:]),
          },
        ],
      }
    }
    "morphir.shutdown" => {}
    _ => fail("unexpected request: " + method_)
  }
  self.next = Some(
    Message::new({ "jsonrpc": "2.0", "id": id, "result": result }),
  )
}

///|
impl Channel for RecordedExitChannel with fn receive(self) {
  self.next.unwrap()
}

///|
async fn RecordedExitChannel::settle(self : RecordedExitChannel) -> WorkerStop {
  // Observe the real producer lock and private stage across asynchronous
  // settlement, before the host can publish or release the producer.
  @async.sleep(10)
  assert_true(self.task.try_task_lease("compile.lock", exclusive=true) is None)
  assert_false(@fs.exists(self.root + "/out"))
  let stages = @fs.readdir(self.root, include_hidden=true).filter(name => {
    name.has_prefix(".morphir-bounded-")
  })
  assert_eq(stages.length(), 1)
  assert_eq(
    @fs.read_file(self.root + "/" + stages[0] + "/order.txt").binary(),
    b"73\n",
  )
  self.settled = true
  WorkerStop::new(
    self.status,
    stop_method=if self.status is Exited(..) {
      ExitedAfterExit
    } else {
      GroupSignal
    },
    stderr=StderrTail::of(b""),
  )
}

///|
impl Channel for RecordedExitChannel with fn close(self) {
  self.settle()
}

///|
impl Channel for RecordedExitChannel with fn abort(self, _) {
  self.settle()
}

///|
async test "recorded WASM publication requires an accepted exit and a zero worker status" {
  guard @platform.system_type() != "windows" &&
    @env.get_env_var("MORPHIR_MEP_BOUNDED_REPOSITORY") is Some(repo) else {
    return
  }
  let fixture = repo +
    "/apps/morphir-extension/acceptance/fixtures/acme-orders-v4/plain-json"
  let failures : Array[String] = []
  for
    (label, status, reject_exit) in [
      ("success", Exited(code=0), false),
      ("broken pipe", Exited(code=0), true),
      ("nonzero", Exited(code=7), false),
      ("signal", Signalled(signal=9), false),
      ("grace expired", Terminated(GraceExpired), false),
    ] {
    let root = @fs.tmpdir(prefix="morphir-recorded-exit-")
    defer @fs.rmdir(root, recursive=true)
    publish_orders_product(root, "orders", fixture)
    let path = root + "/relocated/orders"
    let task = @platform.BoundedDirectory::open(path)
    defer task.close()
    let channel = {
      task,
      root,
      status,
      reject_exit,
      next: None,
      exit_accepted: false,
      settled: false,
      offers: [],
      launched_limits: None,
    }
    let host = Host::new(channel, Native(Machine::of(Aarch64AppleDarwin)))
    let spec = WorkerSpec::new(
      ArtifactRef::new(Memory(b""), Sha256::of(b"")),
      Wasm(abi=Some(ExtismKernelV1)),
    )
    let result = try {
      ignore(
        host.generate_tree(
          spec,
          input=CompileResult(path + "/compile.json"),
          output=root + "/out",
          target="text",
          requested_ir=None,
          deadline=Deadline::of_ms(3000),
          stop=StopSignal::never(),
          diagnostics=[],
        ),
      )
      "published"
    } catch {
      Ended(Failed(Host(code=IncompleteSession, ..)), report~) if report.stop
        is Some(stop) &&
        stop.status == status => "refused"
      error => error.to_string()
    }
    assert_true(channel.settled, msg=label + ": " + result)
    assert_eq(channel.exit_accepted, !reject_exit)
    let writer = task.try_task_lease("compile.lock", exclusive=true).unwrap()
    writer.close()
    let names = @fs.readdir(root, include_hidden=true)
    assert_false(
      names
      .iter()
      .any(name => {
        name.has_prefix(".morphir-bounded-") ||
        name.has_prefix(".morphir-source-")
      }),
    )
    let expected = if label == "success" { "published" } else { "refused" }
    if result != expected || names.contains("out") != (label == "success") {
      failures.push(label + ": " + result)
    }
  }
  guard failures.is_empty() else { fail(failures.join("\n")) }
}

///|
async test "Orders scale profile uses one offer across recorded leased WASM generation" {
  for profile in [TreeGenerationProfile::OrdersScaleA, OrdersScaleB] {
    let root = @fs.tmpdir(prefix="morphir-orders-admission-")
    defer @fs.rmdir(root, recursive=true)
    let path = root + "/task"
    @fs.mkdir(path + "/compile.dest/model", recursive=true)
    @fs.write_file(path + "/compile.dest/model/manifest.json", capture_manifest)
    let record : Json = {
      "schema": 1,
      "task": "compile",
      "module": "orders",
      "completedAt": "2026-11-19T00:00:00Z",
      "value": ["model"],
      "ir": {
        "layout": "document-tree",
        "format": "json",
        "version": "v4",
        "path": "model",
      },
    }
    @fs.write_file(path + "/compile.json", record.stringify())
    @fs.write_file(path + "/compile.lock", "")
    let task = @platform.BoundedDirectory::open(path)
    defer task.close()
    let channel : RecordedExitChannel = {
      task,
      root,
      status: Exited(code=0),
      reject_exit: false,
      next: None,
      exit_accepted: false,
      settled: false,
      offers: [],
      launched_limits: None,
    }
    let host = Host::new(channel, Native(Machine::of(Aarch64AppleDarwin)))
    let spec = WorkerSpec::new(
      ArtifactRef::new(Memory(b""), Sha256::of(b"")),
      Wasm(abi=Some(ExtismKernelV1)),
    )
    let generated = host.generate_tree(
      spec,
      input=CompileResult(path + "/compile.json"),
      output=root + "/out",
      target="text",
      requested_ir=None,
      deadline=Deadline::of_ms(3000),
      stop=StopSignal::never(),
      diagnostics=[],
      profile~,
    ) catch {
      TreeSource(message) => fail(message)
      TreeOutput(message) => fail(message)
      Refusal(message~, ..) => fail(message)
      error => raise error
    }
    assert_true(channel.settled)
    assert_eq(channel.offers, [profile.admission().support.to_json()])
    assert_eq(channel.launched_limits.unwrap().request_bytes, 65536)
    assert_eq(channel.launched_limits.unwrap().response_bytes, 65536)
    assert_eq(generated.accounting.profile, profile)
    assert_eq(
      generated.accounting.source_bytes,
      capture_manifest.length().to_int64(),
    )
    assert_eq(generated.accounting.output_paths, 1)
    assert_eq(generated.accounting.artifact_bytes, 3L)
    assert_eq(
      @model_wire.field(generated.accounting.to_json(), "artifactBytes"),
      Json::number(3),
    )
    let writer = task.try_task_lease("compile.lock", exclusive=true).unwrap()
    writer.close()
    assert_eq(@fs.read_file(root + "/out/order.txt").binary(), b"73\n")
  }
}
