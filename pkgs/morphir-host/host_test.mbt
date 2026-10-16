///|
fn fixture(extra~ : Array[(String, String)] = []) -> Map[String, String] {
  let files = Map::from_array([
    (
      "morphir.toml", "[workspace]\nmembers=['packages/*']\nexclude=['packages/skip']\ndefault_member='packages/core'",
    ),
    ("morphir.config.scm", "(pipeline (transform (lambda (file) file)))"),
    (
      "packages/core/morphir.toml", "[project]\nname='Core'\nsource_directory='src'",
    ),
    ("packages/core/src/Main.scm", "42"),
    (
      "packages/tools/morphir.toml", "[project]\nname='Tools'\nsource_directory='src'",
    ),
    ("packages/tools/src/main.scm", "41"),
    ("packages/skip/morphir.toml", "[project]\nname='Skipped'"),
    ("packages/skip/src/main.scm", "bad"),
  ])
  for (key, value) in extra {
    files[key] = value
  }
  files
}

///|
fn prepare(
  files : Map[String, String],
  request~ : @engine.Request = @engine.Request::new(),
) -> (@host.Mount, @engine.Engine, @engine.Plan) raise {
  let mount = @host.Mount::memory(files)
  let snapshot = @host.Host::new(mount).snapshot()
  let workspace = @workspace.discover(snapshot.tree)
  let engine = @engine.Engine::new()
  (mount, engine, engine.plan(snapshot.engine_host(), workspace, request))
}

///|
test "workspace selection and host publication work together" {
  let (mount, engine, plan) = prepare(fixture())
  assert_eq(plan.sources(), ["packages/core/src/Main.scm"])
  let outputs = Map([])
  let host = @host.Host::new(
    mount,
    publisher=Some(@host.Publisher::memory(outputs)),
  )
  let result = host.run(engine, plan)
  assert_true(result.successful())
  assert_eq(result.committed, [".morphir/out/packages/core/compile.dest"])
  assert_true(
    outputs.contains(".morphir/out/packages/core/compile.dest/Main.ir.json"),
  )
}

///|
test "failed transform anywhere prevents all publication" {
  let request = { ..@engine.Request::new(), all: true, }
  let (mount, engine, plan) = prepare(
    fixture(extra=[
      (
        "packages/tools/morphir.config.scm", "(pipeline (transform (lambda (file) 123)))",
      ),
    ]),
    request~,
  )
  let outputs = Map::from_array([
    (".morphir/out/packages/core/compile.dest/old", "preserve"),
  ])
  let result = @host.Host::new(
    mount,
    publisher=Some(@host.Publisher::memory(outputs)),
  ).run(engine, plan)
  assert_false(result.successful())
  assert_eq(result.committed, [])
  assert_eq(outputs.length(), 1)
  assert_eq(outputs[".morphir/out/packages/core/compile.dest/old"], "preserve")
}

///|
test "publication failure reports already committed destinations and aborts staging" {
  let (mount, engine, plan) = prepare(fixture(), request={
    ..@engine.Request::new(),
    all: true,
  })
  let aborted = Ref(false)
  let publisher = @host.Publisher::{
    guarantee: @host.HostManaged,
    begin: fn(_) {
      {
        stage: fn(_) { () },
        commit: fn(destination) raise {
          if destination.contains("tools") {
            raise @config.Invalid("disk full")
          }
        },
        abort: fn() { aborted.val = true },
      }
    },
  }
  let result = @host.Host::new(mount, publisher=Some(publisher)).run(
    engine, plan,
  )
  assert_false(result.successful())
  assert_eq(result.committed, [".morphir/out/packages/core/compile.dest"])
  assert_true(aborted.val)
  assert_true(result.publication_error is Some(_))
}

///|
test "hidden configuration layout, arrays and member user precedence" {
  let files = fixture()
  let primary = files["morphir.toml"]
  files.remove("morphir.toml")
  files[".config/morphir/config.toml"] = primary
  files[".config/morphir/config.user.toml"] = "[project]\nname='WorkspaceUser'"
  files["packages/core/morphir.user.toml"] = "[project]\nname='MemberUser'"
  let snapshot = @host.Host::new(@host.Mount::memory(files)).snapshot()
  let workspace = @workspace.discover(snapshot.tree)
  assert_eq(workspace.root, "")
  assert_eq(workspace.projects[0].name, "MemberUser")
  assert_eq(workspace.projects[1].name, "Tools")
  assert_eq(workspace.select()[0].root, "packages/core")
}

///|
test "ambiguity, YAML, traversal and invalid default fail before execution" {
  for
    extra in [
      [("morphir.yaml", "workspace: {}")],
      [("morphir.toml", "[workspace]\nmembers=['../escape']")],
      [
        (
          "morphir.toml", "[workspace]\nmembers=['packages/*']\ndefault_member='absent'",
        ),
      ],
      [("packages/core/morphir.user.yaml", "project: {}")],
    ] {
    let message = try {
      ignore(prepare(fixture(extra~)))
      ""
    } catch {
      error => @host.error_message(error)
    }
    assert_true(message != "")
  }
}

///|
test "name ambiguity allows path selection and cancellation prevents writes" {
  let files = fixture(extra=[
    ("packages/tools/morphir.toml", "[project]\nname='Core'"),
  ])
  let snapshot = @host.Host::new(@host.Mount::memory(files)).snapshot()
  let workspace = @workspace.discover(snapshot.tree)
  let failed = try {
    ignore(workspace.select(selector="Core"))
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  assert_eq(
    workspace.select(selector="packages/tools")[0].root,
    "packages/tools",
  )
  let (mount, engine, plan) = prepare(files)
  let outputs = Map([])
  let host = @host.Host::new(
    mount,
    publisher=Some(@host.Publisher::memory(outputs)),
    cancelled=fn() { true },
  )
  let failed = try {
    ignore(host.run(engine, plan))
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  assert_true(outputs.is_empty())
}

///|
test "glob matching respects separators, recursive paths and exclusions" {
  assert_true(@workspace.matches("packages/*", "packages/core"))
  assert_false(@workspace.matches("packages/*", "packages/group/core"))
  assert_true(@workspace.matches("packages/**/core", "packages/core"))
  assert_true(@workspace.matches("packages/**/core", "packages/group/core"))
  assert_false(@workspace.matches("packages/**/core", "packages/notcore"))
  assert_true(
    try {
      ignore(@workspace.matches("missing/[!z-a]", "different"))
      false
    } catch {
      _ => true
    },
  )
  assert_true(@workspace.matches("packages/{core,tools}", "packages/tools"))
  assert_true(@workspace.matches("packages/[a-z]?", "packages/ab"))
  assert_false(@workspace.matches("packages/[!a-z]?", "packages/ab"))
}

///|
test "single file selection does not broaden to sibling sources" {
  let files = fixture(extra=[("packages/core/src/other.scm", "43")])
  let (_, _, plan) = prepare(files, request={
    ..@engine.Request::new(),
    file: Some("packages/core/src/Main.scm"),
  })
  assert_eq(plan.sources(), ["packages/core/src/Main.scm"])
}

///|
test "historical JSON output uses existing migration codecs" {
  for version in [1, 2, 3, 4] {
    let files = fixture(extra=[
      (
        "packages/core/morphir.toml",
        "[project]\nname='core'\n[frontend]\nlanguage='ir-json'\n[ir]\nformat_version=" +
        version.to_string(),
      ),
      (
        "packages/core/src/model.json", "{\"formatVersion\":3,\"distribution\":[\"Library\",[[\"test\"]],[],{\"modules\":[]}]}",
      ),
    ])
    let (mount, engine, plan) = prepare(files)
    let outputs = Map([])
    let result = @host.Host::new(
      mount,
      publisher=Some(@host.Publisher::memory(outputs)),
    ).run(engine, plan)
    assert_eq(result.report.diagnostics.map(d => d.message), [])
    assert_true(result.successful())
    assert_true(
      outputs[".morphir/out/packages/core/compile.dest/model.ir.json"].contains(
        "formatVersion",
      ),
    )
  }
}

///|
test "lossy historical output fails without publication" {
  let files = fixture(extra=[
    (
      "packages/core/morphir.toml", "[project]\nname='core'\n[ir]\nformat_version=3",
    ),
  ])
  let (mount, engine, plan) = prepare(files)
  let outputs = Map([])
  let result = @host.Host::new(
    mount,
    publisher=Some(@host.Publisher::memory(outputs)),
  ).run(engine, plan)
  assert_false(result.successful())
  assert_true(
    result.report.diagnostics[0].message.contains(
      "unsupported_documentation_downgrade",
    ),
  )
  assert_true(outputs.is_empty())
}

///|
test "broken member is isolated from selected sibling" {
  let files = fixture(extra=[("packages/tools/morphir.toml", "[project\n")])
  let (mount, engine, plan) = prepare(files)
  let outputs = Map([])
  assert_true(
    @host.Host::new(mount, publisher=Some(@host.Publisher::memory(outputs)))
    .run(engine, plan)
    .successful(),
  )
  let failed = try {
    ignore(prepare(files, request={ ..@engine.Request::new(), all: true, }))
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "resource limits stop snapshot reads and missing publisher fails before execution" {
  let mount = @host.Mount::memory(fixture())
  let limited = @host.Host::new(mount, limits={
    max_files: 2,
    max_bytes: 1000,
    max_depth: 2,
  })
  assert_true(
    try {
      ignore(limited.snapshot())
      false
    } catch {
      _ => true
    },
  )
  let (_, engine, plan) = prepare(fixture())
  assert_true(
    try {
      ignore(@host.Host::new(mount).run(engine, plan))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "plans preserve source lists and refuse reuse of Scheme sessions" {
  let (mount, engine, plan) = prepare(fixture())
  let exposed_paths = plan.sources()
  exposed_paths.clear()
  assert_eq(plan.sources().length(), 1)
  let outputs = Map([])
  let host = @host.Host::new(
    mount,
    publisher=Some(@host.Publisher::memory(outputs)),
  )
  assert_true(host.run(engine, plan).successful())
  let second = host.run(engine, plan)
  assert_false(second.successful())
  assert_eq(second.report.diagnostics[0].stage, "plan")
}

///|
test "toolchain effects require an explicit host provider" {
  let host = @host.Host::new(@host.Mount::memory(Map([])))
  let missing = try {
    ignore(host.toolchain_request(Json::null()))
    false
  } catch {
    _ => true
  }
  assert_true(missing)
  let calls : Array[Json] = []
  let provider : @toolchain.Provider = {
    describe: fn() { Json::string("injected") },
    request: fn(value) {
      calls.push(value)
      value
    },
  }
  let enabled = @host.Host::new(
    @host.Mount::memory(Map([])),
    toolchain=Some(provider),
  )
  assert_eq(
    enabled.toolchain_request(Json::string("compile")),
    Json::string("compile"),
  )
  let cancelled = @host.Host::new(
    @host.Mount::memory(Map([])),
    toolchain=Some(provider),
    cancelled=fn() { true },
  )
  let stopped = try {
    ignore(cancelled.toolchain_request(Json::null()))
    false
  } catch {
    _ => true
  }
  assert_true(stopped)
  assert_eq(calls.length(), 1)
}
