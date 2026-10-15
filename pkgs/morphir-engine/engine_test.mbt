///|
fn host(files : Array[(String, String)]) -> @engine.Host raise {
  @engine.Host::memory(Map::from_array(files))
}

///|
fn answer(artifact : @engine.Artifact, entry : String) -> String raise {
  @scheme.value_to_string(
    @backend.run_file(
      @ir_json.read(artifact.content),
      @ir.FQName::parse(entry),
      [],
    ),
  )
}

///|
test "file and directory inputs produce stable artifacts without writes" {
  let host = host([
    ("src/b.scm", "(+ 20 22)"),
    ("src/a.scm", "42"),
    ("src/readme.txt", "skip"),
    ("src/dist/old.scm", "invalid source"),
  ])
  let engine = @engine.Engine::new()
  let report = engine.run(host, @engine.File("src/b.scm"))
  assert_true(report.successful())
  assert_eq(report.processed, 1)
  assert_eq(report.artifacts[0].path, "src/dist/b.ir.json")
  assert_eq(answer(report.artifacts[0], "user:b#main"), "42")
  let report = engine.run(host, @engine.Directory("src"))
  assert_true(report.successful())
  assert_eq(report.processed, 2)
  assert_eq(report.artifacts[0].source, "src/a.scm")
  assert_eq(report.artifacts[1].source, "src/b.scm")
  assert_false((host.exists)("src/dist/b.ir.json"))
}

///|
test "workspace and project manifests inherit script configuration" {
  let host = host([
    ("morphir.toml", "[workspace]\nmembers = ['one', 'two']\n"),
    (
      "morphir.config.scm", "(pipeline (output \"generated\") (transform (lambda (file) (ir-rewrite-file file (lambda (node) (if (ir-integer? node) (ir-with-integer node (+ (ir-integer node) 1)) node))))))",
    ),
    ("one/morphir.toml", "[project]\nname = 'one'\nsource_directory = 'src'\n"),
    ("one/morphir.config.scm", "(pipeline (output \"build\"))"),
    ("one/src/main.scm", "41"),
    ("two/morphir.toml", "[project]\nname = 'two'\nsource_directory = 'lib'\n"),
    ("two/lib/main.scm", "41"),
  ])
  let engine = @engine.Engine::new()
  let report = engine.run(host, @engine.Workspace("."))
  assert_true(report.successful())
  assert_eq(report.processed, 2)
  assert_eq(report.artifacts[0].path, "one/build/main.ir.json")
  assert_eq(report.artifacts[1].path, "two/generated/main.ir.json")
  assert_eq(answer(report.artifacts[0], "one:main#main"), "42")
  let project = engine.run(
    host,
    @engine.Project("one"),
    config="(pipeline (output \"explicit\"))",
  )
  assert_true(project.successful())
  assert_eq(project.artifacts[0].path, "one/explicit/main.ir.json")
  assert_eq(answer(project.artifacts[0], "one:main#main"), "41")
}

///|
test "Engine::run no longer reads morphir.json as a Scheme project" {
  let report = @engine.Engine::new().run(
    host([
      (
        "legacy/morphir.json", "{\"name\":\"legacy\",\"sourceDirectory\":\"src\"}",
      ),
      ("legacy/src/main.scm", "41"),
    ]),
    @engine.Project("legacy"),
  )
  assert_false(report.successful())
  assert_true(report.diagnostics[0].message.contains("morphir.toml"))
}

///|
test "Engine::run workspace members must be literal paths" {
  let report = @engine.Engine::new().run(
    host([
      ("morphir.toml", "[workspace]\nmembers = ['packages/*']\n"),
      ("packages/a/morphir.toml", "[project]\nname = 'a'\n"),
      ("packages/a/src/main.scm", "41"),
    ]),
    @engine.Workspace("."),
  )
  assert_false(report.successful())
  assert_true(report.diagnostics[0].message.contains("literal paths"))
}

///|
test "script failures and duplicate outputs are diagnostics and other files complete" {
  let engine = @engine.Engine::new()
  let report = engine.run(
    host([("a.scm", "40"), ("a.ss", "41"), ("broken.scm", "("), ("z.scm", "42")]),
    @engine.Directory(""),
  )
  assert_eq(report.processed, 2)
  assert_eq(report.diagnostics.length(), 2)
  assert_eq(report.diagnostics[0].stage, "output")
  assert_eq(report.diagnostics[1].stage, "frontend")
  let report = engine.run(
    host([("main.scm", "42")]),
    @engine.File("main.scm"),
    config="(pipeline (transform (lambda (file) 42)))",
  )
  assert_eq(report.processed, 0)
  assert_eq(report.diagnostics[0].stage, "transform")
}

///|
test "host and configuration paths cannot escape roots" {
  let engine = @engine.Engine::new()
  let host = host([("main.scm", "42")])
  for
    script in [
      "(pipeline (output \"../outside\"))", "(pipeline (source \"/absolute\"))",
      "(pipeline (backend \"missing\"))", "(pipeline (output \"\"))",
    ] {
    let report = engine.run(host, @engine.Directory(""), config=script)
    assert_false(report.successful())
    assert_eq(report.processed, 0)
  }
  let hostile = @engine.Host::{
    read: host.read,
    exists: host.exists,
    list: fn(_root) { ["outside/main.scm"] },
  }
  let report = engine.run(hostile, @engine.Directory("src"))
  assert_eq(report.diagnostics[0].stage, "discovery")
  let report = engine.run(host, @engine.File("../main.scm"))
  assert_eq(report.processed, 0)
}

///|
test "run refuses pipeline.inference other than off" {
  let engine = @engine.Engine::new()
  let host = host([("main.scm", "42")])
  for value in ["fill", "check"] {
    let report = engine.run(
      host,
      @engine.Directory(""),
      config="(pipeline (inference \"" + value + "\"))",
    )
    assert_eq(report.processed, 0)
    assert_eq(report.diagnostics[0].stage, "configuration")
    assert_true(
      report.diagnostics[0].message.contains(
        "pipeline.inference needs the planned pipeline (Engine::plan)",
      ),
      msg=report.diagnostics[0].message,
    )
  }
  let report = engine.run(
    host,
    @engine.Directory(""),
    config="(pipeline (inference \"off\"))",
  )
  assert_true(report.successful())
}

///|
test "custom frontends and backends share the engine pipeline" {
  let engine = @engine.Engine::new()
  engine.register_frontend("constant", [".txt"], fn(source) raise {
    @frontend.compile_file(source.content)
  })
  engine.register_backend("answer", ".txt", fn(file) raise {
    @scheme.value_to_string(
      @backend.run_file(file, @ir.FQName::parse("user:main#main"), []),
    )
  })
  let report = engine.run(
    host([("input.txt", "(* 6 7)")]),
    @engine.Directory(""),
    config="(pipeline (frontend \"constant\") (backend \"answer\"))",
  )
  assert_true(report.successful())
  assert_eq(report.artifacts[0].content, "42")
  assert_eq(report.artifacts[0].path, "dist/input.txt")
}

///|
test "IR JSON frontend and Scheme backend produce executable artifacts" {
  let file = @frontend.compile_file("(+ 40 2)")
  let engine = @engine.Engine::new()
  let report = engine.run(
    host([("input.json", @ir_json.write(file))]),
    @engine.File("input.json"),
    config="(pipeline (frontend \"ir-json\") (backend \"scheme\"))",
  )
  assert_true(report.successful())
  let runtime = @pipeline.new_runtime()
  ignore(runtime.eval(report.artifacts[0].content))
  assert_eq(
    @scheme.value_to_string(
      @backend.call_entry(runtime, @ir.FQName::parse("user:main#main"), []),
    ),
    "42",
  )
}
