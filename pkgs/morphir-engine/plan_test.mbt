///|
test "project module prefixes and exposure are reflected in IR" {
  let files = Map::from_array([
    (
      "morphir.toml", "[project]\nname='Example'\nmodule_prefix='App'\nexposed_modules=[]",
    ),
    ("src/Main.scm", "42"),
  ])
  let host = @engine.Host::memory(files)
  let workspace = @workspace.discover({ files, directories: ["", "src"], })
  let engine = @engine.Engine::new()
  let plan = engine.plan(host, workspace, @engine.Request::new())
  let report = engine.execute(plan, host)
  assert_true(report.successful())
  let file = @ir_json.read(report.artifacts[0].content)
  guard file.distribution is Library(package_name, _, definition) else {
    fail("Expected library")
  }
  assert_eq(package_name.to_canonical(), "example")
  guard definition.modules.get(@ir.Path::parse("app/main")) is Some(module_def) else {
    fail("Expected prefixed module")
  }
  assert_eq(module_def.access, @ir.Access::Private)
}

///|
test "overlapping task destinations are rejected during planning" {
  let files = Map::from_array([
    (
      "morphir.toml", "[workspace]\nmembers=['compile.dest']\n[project]\nname='root'",
    ),
    ("compile.dest/morphir.toml", "[project]\nname='child'"),
  ])
  let host = @engine.Host::memory(files)
  let workspace = @workspace.discover({
    files,
    directories: ["", "compile.dest"],
  })
  let engine = @engine.Engine::new()
  let failed = try {
    ignore(
      engine.plan(host, workspace, { ..@engine.Request::new(), all: true, }),
    )
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "parent projects never compile nested member sources" {
  let files = Map::from_array([
    (
      "morphir.toml", "[workspace]\nmembers=['packages/core']\n[project]\nname='root'\nsource_directory='.'",
    ),
    ("Root.scm", "42"),
    ("packages/core/morphir.toml", "[project]\nname='core'"),
    ("packages/core/src/Main.scm", "41"),
  ])
  let host = @engine.Host::memory(files)
  let workspace = @workspace.discover({
    files,
    directories: ["", "packages", "packages/core", "packages/core/src"],
  })
  let engine = @engine.Engine::new()
  let plan = engine.plan(host, workspace, {
    ..@engine.Request::new(),
    all: true,
  })
  assert_eq(plan.sources(), ["Root.scm", "packages/core/src/Main.scm"])
  assert_eq(engine.execute(plan, host).processed, 2)
  for
    request in [
      {
        ..@engine.Request::new(),
        selector: "root",
        file: Some("packages/core/src/Main.scm"),
      },
      {
        ..@engine.Request::new(),
        selector: "root",
        directory: Some("packages/core/src"),
      },
    ] {
    assert_true(
      try {
        ignore(engine.plan(host, workspace, request))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "host runtime bindings are available to project scripts" {
  let files = Map::from_array([
    ("morphir.toml", "[project]\nname='Example'"),
    ("src/Main.scm", "42"),
  ])
  let host = @engine.Host::memory(files)
  let workspace = @workspace.discover({ files, directories: ["", "src"], })
  let engine = @engine.Engine::new()
  let request = {
    ..@engine.Request::new(),
    script: "(pipeline (backend (host-backend)))",
  }
  let plan = engine.plan(host, workspace, request, bind_runtime=fn(runtime) {
    runtime.define_native("host-backend", fn(_rt, args) raise {
      @scheme.arity(args, 0, "host-backend")
      @scheme.Text("scheme")
    })
  })
  let report = engine.execute(plan, host)
  assert_true(report.successful())
  assert_true(report.artifacts[0].path.has_suffix(".scm"))
  // A plain Scheme source writes one file and no sidecar.
  assert_eq(report.artifacts.length(), 1)
}
