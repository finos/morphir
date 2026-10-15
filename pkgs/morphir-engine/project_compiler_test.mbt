///|
fn project_profile(
  run : (@engine.ProjectSources, String, () -> Bool) -> @data.IRUnit raise,
  max_documents? : Int? = None,
) -> @engine.SourceProfile {
  {
    id: @ids.ProfileId::parse("library") catch {
      _ => abort("test profile id")
    },
    compile: @engine.PerProject(run),
    unit_limits: @data.Limits::default(),
    evidence: @engine.Declared,
    dependencies: Map([]),
    capabilities: {
      summary: "Test project",
      supported: ["Whole projects"],
      excluded: [],
      max_documents,
      incremental: false,
      limits: Map([]),
    },
  }
}

///|
fn project_engine(profile : @engine.SourceProfile) -> @engine.Engine raise {
  let engine = @engine.Engine::new()
  engine.register_source_provider({
    id: @ids.ProviderId::parse("test/project"),
    languages: [
      {
        id: @ids.LanguageId::parse("rich"),
        extensions: [@ids.FileExtension::parse(".model")],
        default_profile: profile.id,
        profiles: [profile],
      },
    ],
  })
  engine
}

///|
fn project_files(
  backend? : String = "checkpoint",
  exposed? : String = "\nexposed_modules=['Api']",
) -> Map[String, String] {
  Map::from_array([
    (
      "morphir.toml",
      "[project]\nname='Example.Project'" +
      exposed +
      "\n[frontend]\nlanguage='rich'\n[pipeline]\nbackend='" +
      backend +
      "'",
    ),
    ("src/Api.model", "api"),
    ("src/Nested/Util.model", "util"),
    ("src/notes.txt", "skip"),
  ])
}

///|
fn project_plan(
  engine : @engine.Engine,
  files : Map[String, String],
  request? : @engine.Request = @engine.Request::new(),
) -> @engine.Plan raise {
  engine.plan(
    @engine.Host::memory(files),
    @workspace.discover({ files, directories: ["", "src", "src/Nested"], }),
    request,
  )
}

///|
fn project_read(
  files : Map[String, String],
) -> (String, Bool) -> @data.Content raise {
  fn(path, _) raise {
    match files.get(path) {
      Some(text) => @data.Text(text)
      None => fail("not found: " + path)
    }
  }
}

///|
fn plan_error(f : () -> Unit raise) -> String {
  try {
    f()
    ""
  } catch {
    @configuration.Invalid(message) => message
    e => "not a configuration error: " + e.to_string()
  }
}

///|
test "a project compiler gets every source of the project in one call" {
  let calls : Array[(@engine.ProjectSources, String)] = []
  let engine = project_engine(
    project_profile(fn(project, unit_id, _) raise {
      calls.push((project, unit_id))
      @data.IRUnit::new(unit_id, @fixtures.library())
    }),
  )
  let files = project_files()
  let plan = project_plan(engine, files)
  assert_eq(
    plan.source_frontends().map(s => (s.source, s.unit_id, s.output_contract)),
    [
      ("src/Api.model", "example/project", "ir-project"),
      ("src/Nested/Util.model", "example/project", "ir-project"),
    ],
  )
  let report = engine.execute_content(plan, project_read(files))
  if !report.successful() {
    fail(report.diagnostics[0].message)
  }
  assert_eq(report.processed, 1)
  assert_eq(calls.length(), 1)
  let (project, unit_id) = calls[0]
  assert_eq(unit_id, "example/project")
  assert_eq(project.package_name.to_string(), "Example.Project")
  assert_eq(project.exposed_modules.map(m => m.to_string()), ["Api"])
  assert_eq(
    project.sources.map(s => (s.path, s.relative_path, s.module_name, s.content)),
    [
      ("src/Api.model", "Api.model", "Api", "api"),
      ("src/Nested/Util.model", "Nested/Util.model", "Nested/Util", "util"),
    ],
  )
  assert_eq(report.artifacts.length(), 1)
  assert_true(
    report.artifacts[0].path.has_suffix("compile.dest/example/project.ionb"),
    msg=report.artifacts[0].path,
  )
  assert_eq(report.artifacts[0].source, "src")
  // The plan does not rewrite module access for a project compiler: the compiler sets it.
  let unit = @data.Registry::new().decode("ion-binary", {
    unit_id: "example/project",
    content: report.artifacts[0].content,
  })
  assert_eq(unit.distribution, @fixtures.library())
}

///|
test "a file compiler still refuses exposed_modules on the checkpoint path" {
  let engine = @engine.Engine::new()
  engine.register_unit_frontend("rich", [".model"], fn(_, id, _) raise {
    @data.IRUnit::new(id, @fixtures.library())
  })
  let message = plan_error(() => ignore(project_plan(engine, project_files())))
  assert_true(message.contains("exposed_modules"), msg=message)
}

///|
test "the problems of a project compiler are diagnostics at their files" {
  let engine = project_engine(
    project_profile(fn(_, _, _) raise {
      raise @engine.RejectedSources([
        {
          code: "rich.bad_name",
          detail: "bad name",
          path: "Nested/Util.model",
          location: Some({
            start_line: 1,
            start_column: 2,
            end_line: 1,
            end_column: 5,
          }),
        },
        {
          code: "rich.no_exposed",
          detail: "nothing exposed",
          path: "",
          location: None,
        },
      ])
    }),
  )
  let files = project_files()
  let report = engine.execute_content(
    project_plan(engine, files),
    project_read(files),
  )
  assert_eq(report.processed, 0)
  assert_eq(report.diagnostics.map(d => (d.path, d.stage, d.message)), [
    (
      "src/Nested/Util.model", "frontend", "rich.bad_name: bad name [provider test/project; profile library] at 1:2-1:5",
    ),
    (
      "src", "frontend", "rich.no_exposed: nothing exposed [provider test/project; profile library]",
    ),
  ])
}

///|
test "planning refuses a file request and an untyped backend" {
  let unit = fn(_, id, _) raise { @data.IRUnit::new(id, @fixtures.library()) }
  let engine = project_engine(project_profile(unit))
  let file_request = { ..@engine.Request::new(), file: Some("src/Api.model"), }
  assert_true(
    plan_error(() => {
      ignore(project_plan(engine, project_files(), request=file_request))
    }).has_prefix("frontend.project_compiler_file"),
  )
  assert_true(
    plan_error(() => {
      ignore(project_plan(engine, project_files(backend="ir-json")))
    }).has_prefix("frontend.typed_backend_required"),
  )
}

///|
/// By default a project compiler has no document limit: neither the old cap (64) nor any other number applies.
test "a project compiler takes more than 64 sources and more than 1024" {
  let counts : Array[Int] = []
  let engine = project_engine(
    project_profile(fn(project, unit_id, _) raise {
      counts.push(project.sources.length())
      @data.IRUnit::new(unit_id, @fixtures.library())
    }),
  )
  let files = project_files()
  let directories = ["", "src", "src/Nested"]
  for i in 0..<1100 {
    files["src/Many\{i}.model"] = "many"
  }
  let plan = engine.plan(
    @engine.Host::memory(files),
    @workspace.discover({ files, directories, }),
    @engine.Request::new(),
  )
  assert_eq(plan.source_frontends().length(), 1102)
  let report = engine.execute_content(plan, project_read(files))
  if !report.successful() {
    fail(report.diagnostics[0].message)
  }
  assert_eq(counts, [1102])
}

///|
test "a declared document limit applies to a project" {
  let unit = fn(_, id, _) raise { @data.IRUnit::new(id, @fixtures.library()) }
  // project_files() has two sources.
  ignore(
    project_plan(
      project_engine(project_profile(unit, max_documents=Some(2))),
      project_files(),
    ),
  )
  let message = plan_error(() => {
    ignore(
      project_plan(
        project_engine(project_profile(unit, max_documents=Some(1))),
        project_files(),
      ),
    )
  })
  assert_true(
    message.has_prefix("frontend.too_many_documents: 2 sources;"),
    msg=message,
  )
  assert_true(message.has_suffix("accepts at most 1"), msg=message)
}

///|
test "the legacy run refuses a project compiler" {
  let engine = project_engine(
    project_profile(fn(_, id, _) raise {
      @data.IRUnit::new(id, @fixtures.library())
    }),
  )
  let report = engine.run(
    @engine.Host::memory(project_files()),
    @engine.Directory("src"),
    config="(pipeline (frontend \"rich\"))",
  )
  assert_true(
    report.diagnostics.any(d => {
      d.message.contains("frontend.typed_backend_required")
    }),
  )
}

///|
test "review focus 2: two projects in one workspace give one unit each" {
  let ids : Array[String] = []
  let engine = project_engine(
    project_profile(fn(_, id, _) raise {
      ids.push(id)
      @data.IRUnit::new(id, @fixtures.library())
    }),
  )
  let member_config = fn(name : String) {
    "[project]\nname='" +
    name +
    "'\nexposed_modules=['Main']\n[frontend]\nlanguage='rich'\n[pipeline]\nbackend='checkpoint'"
  }
  let files = Map::from_array([
    ("morphir.toml", "[workspace]\nmembers=['a','b']"),
    ("a/morphir.toml", member_config("Alpha")),
    ("b/morphir.toml", member_config("Beta")),
    ("a/src/Main.model", "a"),
    ("b/src/Main.model", "b"),
  ])
  let plan = engine.plan(
    @engine.Host::memory(files),
    @workspace.discover({
      files,
      directories: ["", "a", "b", "a/src", "b/src"],
    }),
    { ..@engine.Request::new(), all: true, },
  )
  let report = engine.execute_content(plan, project_read(files))
  assert_true(report.successful())
  assert_eq(report.processed, 2)
  assert_eq(ids, ["alpha", "beta"])
  assert_true(report.artifacts[0].path.has_suffix("a/compile.dest/alpha.ionb"))
  assert_true(report.artifacts[1].path.has_suffix("b/compile.dest/beta.ionb"))
}

///|
test "review focus 3 and 5: cancellation and an unreadable source stop before the compile" {
  let mut calls = 0
  let engine = project_engine(
    project_profile(fn(_, id, _) raise {
      calls += 1
      @data.IRUnit::new(id, @fixtures.library())
    }),
  )
  let files = project_files()
  let cancelled = engine.execute_content(
    project_plan(engine, files),
    project_read(files),
    cancelled=() => true,
  )
  assert_eq(cancelled.diagnostics.map(d => d.message), ["Cancelled"])
  let unreadable = engine.execute_content(project_plan(engine, files), fn(
    path,
    bytes,
  ) raise {
    if path == "src/Nested/Util.model" {
      fail("unreadable")
    }
    project_read(files)(path, bytes)
  })
  assert_eq(unreadable.diagnostics.map(d => (d.path, d.stage)), [
    ("src/Nested/Util.model", "read"),
  ])
  assert_eq(calls, 0)
}

///|
test "a project with no sources is not compiled" {
  let mut calls = 0
  let engine = project_engine(
    project_profile(fn(_, id, _) raise {
      calls += 1
      @data.IRUnit::new(id, @fixtures.library())
    }),
  )
  let files = Map::from_array([
    (
      "morphir.toml", "[project]\nname='Empty'\n[frontend]\nlanguage='rich'\n[pipeline]\nbackend='checkpoint'",
    ),
    ("src/notes.txt", "skip"),
  ])
  let report = engine.execute_content(
    project_plan(engine, files),
    project_read(files),
  )
  assert_true(report.successful())
  assert_eq((report.processed, calls), (0, 0))
}

///|
/// A project writes one output, so the per-source output paths of `Api` and `Api/Util` do not collide.
test "a project compiler with a generator backend takes nested module paths" {
  let engine = project_engine(
    project_profile(fn(_, id, _) raise {
      @data.IRUnit::new(id, @fixtures.library())
    }),
  )
  let files = Map::from_array([
    (
      "morphir.toml", "[project]\nname='Example.Project'\n[frontend]\nlanguage='rich'\n[pipeline]\nbackend='moonbit'\nvalidation='source-only'",
    ),
    ("src/Api.model", "api"),
    ("src/Api/Util.model", "util"),
  ])
  let message = plan_error(() => {
    let plan = engine.plan(
      @engine.Host::memory(files),
      @workspace.discover({ files, directories: ["", "src", "src/Api"], }),
      @engine.Request::new(),
    )
    assert_eq(plan.source_frontends().length(), 2)
  })
  assert_eq(message, "")
}

///|
/// A directory request selects a project only when it holds the source directory; a narrower one is refused.
test "a project compiler compiles the whole project for a directory request" {
  let calls : Array[Array[(String, String)]] = []
  let engine = project_engine(
    project_profile(fn(project, unit_id, _) raise {
      calls.push(project.sources.map(s => (s.relative_path, s.module_name)))
      @data.IRUnit::new(unit_id, @fixtures.library())
    }),
  )
  let files = project_files()
  for directory in ["src/Nested", "src/Missing"] {
    let request = { ..@engine.Request::new(), directory: Some(directory), }
    let message = plan_error(() => ignore(project_plan(engine, files, request~)))
    assert_true(
      message.has_prefix(
        "frontend.project_compiler_file: rich compiles whole projects",
      ),
      msg=message,
    )
  }
  for directory in ["src", ""] {
    let request = { ..@engine.Request::new(), directory: Some(directory), }
    let report = engine.execute_content(
      project_plan(engine, files, request~),
      project_read(files),
    )
    if !report.successful() {
      fail(report.diagnostics[0].message)
    }
    assert_eq(report.artifacts[0].source, "src")
  }
  let whole = [("Api.model", "Api"), ("Nested/Util.model", "Nested/Util")]
  assert_eq(calls, [whole, whole])
}

///|
test "a project compiler that rejects with no problems still fails" {
  let engine = project_engine(
    project_profile(fn(_, _, _) raise { raise @engine.RejectedSources([]) }),
  )
  let files = project_files()
  let report = engine.execute_content(
    project_plan(engine, files),
    project_read(files),
  )
  assert_false(report.successful())
  assert_eq(report.processed, 0)
  assert_eq(report.diagnostics.map(d => (d.path, d.stage, d.message)), [
    (
      "src", "frontend", "frontend.rejected: the compiler reported no problems [provider test/project; profile library]",
    ),
  ])
}
