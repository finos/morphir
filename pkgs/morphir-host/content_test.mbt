///|
fn checkpoint_files(
  frontend~ : String = "ir-json",
  format~ : String = "ion-binary",
) -> Map[String, String] {
  Map::from_array([
    (
      "morphir.toml",
      "[project]\nname='Pricing'\n[frontend]\nlanguage='" +
      frontend +
      "'\n[pipeline]\nbackend='checkpoint'\ncheckpoint_format='" +
      format +
      "'",
    ),
    (
      "src/Main.json", "{\"formatVersion\":3,\"distribution\":[\"Library\",[[\"pricing\"]],[],{\"modules\":[]}]}",
    ),
  ])
}

///|
test "JSON sources produce binary checkpoints and single-use typed reports without tools" {
  let (mount, engine, plan) = prepare(checkpoint_files())
  let boundary = plan.boundaries()[0]
  assert_eq(boundary.input_format, "morphir-json")
  assert_eq(boundary.output_format, "ion-binary")
  assert_eq(boundary.profile, Some(@data.PROFILE))
  assert_false(boundary.read_bytes)
  assert_true(boundary.write_bytes)
  let outputs = Map([])
  let host = @host.Host::new(mount)
  let publisher = @host.ContentPublisher::memory(outputs)
  let result = host.run_content(engine, plan, publisher)
  assert_true(result.successful())
  assert_eq(result.committed, [".morphir/out/compile.dest"])
  let content = outputs[".morphir/out/compile.dest/Main.ionb"]
  assert_true(content is @data.Binary(_))
  let unit = @data.Registry::new().decode("ion-binary", {
    unit_id: "Main",
    content,
  })
  assert_eq(unit.id, "Main")
  let second = host.run_content(engine, plan, publisher)
  assert_false(second.successful())
  assert_eq(second.report.diagnostics[0].stage, "plan")
}

///|
test "byte requirements fail before reads and leave a plan usable with a capable host" {
  let (mount, engine, plan) = prepare(checkpoint_files(frontend="ion-binary"))
  let reads = Ref(0)
  let input = {
    ..mount,
    read: fn(_) raise {
      reads.val = reads.val + 1
      raise @config.Invalid("Unexpected text read")
    },
  }
  let outputs = Map([])
  let missing = try {
    ignore(
      @host.Host::new(input).run_content(
        engine,
        plan,
        @host.ContentPublisher::memory(outputs),
      ),
    )
    ""
  } catch {
    error => @host.error_message(error)
  }
  assert_true(missing.contains("host.byte_read_required"))
  assert_eq(reads.val, 0)
  let text_outputs = Map([])
  let (_, _, output_plan) = prepare(checkpoint_files())
  let missing = try {
    ignore(
      @host.Host::new(input).run_content(
        engine,
        output_plan,
        @host.ContentPublisher::text(@host.Publisher::memory(text_outputs)),
      ),
    )
    ""
  } catch {
    error => @host.error_message(error)
  }
  assert_true(missing.contains("host.byte_write_required"))
  assert_eq(reads.val, 0)
  assert_true(outputs.is_empty())
  let result = @host.Host::new(mount).run_content(
    engine,
    output_plan,
    @host.ContentPublisher::memory(outputs),
  )
  assert_true(result.successful())
}

///|
test "Ion metadata survives text and byte publication and JSON loss is refused" {
  let files = checkpoint_files(frontend="ion-text", format="ion-binary")
  files.remove("src/Main.json")
  // Use the actual semantic IR writer shape in an otherwise rich envelope.
  let registry = @data.Registry::new()
  let seed = registry.decode("morphir-json", {
    unit_id: "Main",
    content: @data.Text(checkpoint_files()["src/Main.json"]),
  })
  let text = match registry.encode("ion-text", seed) {
    Text(s) => s
    Binary(_) => fail("Expected text")
  }
  files["src/Main.ion"] = text.replace(
    old="metadata: []",
    new="metadata:[{node_id:\"node:1\",data:tag::tag::unknown::{price:12.340d0,blob:{{/wCA}},nothing:null.int}}]",
  )
  let (mount, engine, plan) = prepare(files)
  let outputs = Map([])
  let result = @host.Host::new(mount).run_content(
    engine,
    plan,
    @host.ContentPublisher::memory(outputs),
  )
  assert_true(result.successful())
  let binary = outputs[".morphir/out/compile.dest/Main.ionb"]
  let restored = registry.decode("ion-binary", {
    unit_id: "Main",
    content: binary,
  })
  assert_eq(restored.metadata.length(), 1)
  let files = checkpoint_files(frontend="ion-binary", format="ion-text")
  files.remove("src/Main.json")
  files["src/Main.ionb"] = "not UTF-8 decoded"
  let (mount, engine, plan) = prepare(files)
  let outputs = Map([])
  let result = @host.Host::new(mount).run_content(
    engine,
    plan,
    @host.ContentPublisher::memory(outputs),
    read_bytes=Some(fn(_) raise {
      match binary {
        Binary(bytes) => bytes
        Text(_) => fail("Expected bytes")
      }
    }),
  )
  assert_true(result.successful())
  let restored_text = registry.decode("ion-text", {
    unit_id: "Main",
    content: outputs[".morphir/out/compile.dest/Main.ion"],
  })
  assert_eq(restored_text.metadata.length(), 1)
  assert_eq(registry.encode("ion-binary", restored_text), binary)
  let loss = try {
    ignore(registry.encode("morphir-json", restored_text))
    false
  } catch {
    @data.Invalid("data.lossy_conversion", _) => true
    _ => false
  }
  assert_true(loss)
}

///|
test "failed decoding and failed staging preserve previous checkpoint outputs" {
  let files = checkpoint_files()
  files["src/Main.json"] = "invalid"
  let (mount, engine, plan) = prepare(files)
  let outputs = Map::from_array([
    (".morphir/out/compile.dest/old.ionb", @data.Binary(b"\xff\x00")),
  ])
  let result = @host.Host::new(mount).run_content(
    engine,
    plan,
    @host.ContentPublisher::memory(outputs),
  )
  assert_false(result.successful())
  assert_eq(result.report.diagnostics[0].stage, "frontend")
  assert_eq(outputs.length(), 1)
  let (mount, engine, plan) = prepare(checkpoint_files())
  let aborted = Ref(false)
  let committed = Ref(false)
  let publisher : @host.ContentPublisher = {
    guarantee: @host.HostManaged,
    write_bytes: true,
    begin: fn(_) {
      {
        stage: fn(_) raise { raise @config.Invalid("staging full") },
        commit: fn(_) { committed.val = true },
        abort: fn() { aborted.val = true },
      }
    },
  }
  let result = @host.Host::new(mount).run_content(engine, plan, publisher)
  assert_false(result.successful())
  assert_true(result.report.successful())
  assert_eq(result.report.artifacts.length(), 1)
  assert_eq(result.committed, [])
  assert_true(aborted.val)
  assert_false(committed.val)
  assert_eq(
    outputs[".morphir/out/compile.dest/old.ionb"],
    @data.Binary(b"\xff\x00"),
  )
}

///|
test "checkpoint planning rejects collisions, unsupported formats and untracked rewrites" {
  for option in ["format", "collision", "transform", "historical"] {
    let files = checkpoint_files(frontend="ion-binary")
    match option {
      "format" =>
        files["morphir.toml"] = files["morphir.toml"].replace(
          old="checkpoint_format='ion-binary'",
          new="checkpoint_format='bogus'",
        )
      "collision" => {
        files["src/Main.ionb"] = ""
        files["src/Main.10n"] = ""
      }
      "transform" =>
        files["morphir.config.scm"] = "(pipeline (transform (lambda (file) file)))"
      _ =>
        files["morphir.toml"] = files["morphir.toml"] +
          "\n[ir]\nformat_version=3"
    }
    assert_true(
      try {
        ignore(prepare(files))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "readable checkpoints can use the existing text publication API" {
  let (mount, engine, plan) = prepare(checkpoint_files(format="ion-text"))
  let outputs = Map([])
  let result = @host.Host::new(
    mount,
    publisher=Some(@host.Publisher::memory(outputs)),
  ).run(engine, plan)
  assert_true(result.successful())
  assert_true(
    outputs[".morphir/out/compile.dest/Main.ion"].contains("morphir_pipeline"),
  )
}

///|
test "registered formats bind codecs, file suffixes and capabilities in a frozen plan" {
  let files = checkpoint_files(frontend="fixture-text", format="fixture-text")
  files["src/Main.fixture"] = files["src/Main.json"]
  files.remove("src/Main.json")
  let mount = @host.Mount::memory(files)
  let snapshot = @host.Host::new(mount).snapshot()
  let workspace = @workspace.discover(snapshot.tree)
  let engine = @engine.Engine::new()
  let extensions = [".fixture"]
  engine.register_data_format("fixture-text", {
    codec: "fixture-json",
    extensions,
    suffix: ".checkpoint",
    binary: false,
  })
  extensions.clear()
  let registry = @data.Registry::new()
  let standard = @data.Registry::new()
  registry.register("fixture-json", {
    decode: fn(source, _) raise { standard.decode("morphir-json", source) },
    encode: fn(unit, _) raise { standard.encode("morphir-json", unit) },
  })
  let missing = try {
    ignore(
      engine.plan(snapshot.engine_host(), workspace, @engine.Request::new()),
    )
    ""
  } catch {
    error => @host.error_message(error)
  }
  assert_true(missing.contains("data.unknown_codec: fixture-json"))
  let plan = engine.plan(
    snapshot.engine_host(),
    workspace,
    @engine.Request::new(),
    codecs=Some(registry),
  )
  assert_eq(plan.sources(), ["src/Main.fixture"])
  assert_eq(plan.boundaries()[0].input_format, "fixture-json")
  assert_eq(plan.boundaries()[0].output_format, "fixture-json")
  let conflict = try {
    engine.register_data_format("fixture-text", {
      codec: "changed",
      extensions: [".bad"],
      suffix: ".bad",
      binary: true,
    })
    false
  } catch {
    _ => true
  }
  assert_true(conflict)
  let outputs = Map([])
  let result = @host.Host::new(mount).run_content(
    engine,
    plan,
    @host.ContentPublisher::memory(outputs),
  )
  assert_true(result.successful())
  assert_true(outputs.contains(".morphir/out/compile.dest/Main.checkpoint"))
}

///|
test "generated library replacement removes stale members and failed generation preserves prior tree" {
  let files = checkpoint_files()
  files["morphir.toml"] = "[project]\nname='Pricing'\n[frontend]\nlanguage='ir-json'\n[pipeline]\nbackend='moonbit'\nvalidation='source-only'"
  let old = ".morphir/out/compile.dest/Main/stale.mbt"
  let receipt = ".morphir/out/compile.dest/Main/build-receipt.ionb"
  let outputs = Map::from_array([
    (old, @data.Text("old")),
    (receipt, @data.Text("old receipt")),
  ])
  let (mount, engine, plan) = prepare(files)
  let publisher = @host.ContentPublisher::memory(outputs)
  let result = @host.Host::new(mount).run_content(engine, plan, publisher)
  assert_true(result.successful())
  assert_eq(result.report.projects.length(), 1)
  assert_eq(outputs.length(), 4)
  assert_false(outputs.contains(old))
  assert_false(outputs.contains(receipt))
  let before = outputs.copy()
  files["src/failure.json"] = "invalid"
  let (mount, engine, plan) = prepare(files)
  let result = @host.Host::new(mount).run_content(engine, plan, publisher)
  assert_false(result.successful())
  assert_true(result.committed.is_empty())
  assert_eq(outputs, before)
}

///|
test "required generated builds cannot publish through a source-only host" {
  let files = checkpoint_files()
  files["morphir.toml"] = "[project]\nname='Pricing'\n[frontend]\nlanguage='ir-json'\n[pipeline]\nbackend='moonbit'"
  let (mount, engine, plan) = prepare(files)
  let outputs = Map([])
  let result = @host.Host::new(mount).run_content(
    engine,
    plan,
    @host.ContentPublisher::memory(outputs),
  )
  assert_false(result.successful())
  assert_true(
    result.publication_error.unwrap().contains("build.provider_required"),
  )
  assert_true(outputs.is_empty())
}
