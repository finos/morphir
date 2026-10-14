///|
fn inference_files(inference : String?, source : String) -> Map[String, String] {
  let setting = match inference {
    Some(value) => "\ninference='" + value + "'"
    None => ""
  }
  Map::from_array([
    (
      "morphir.toml",
      "[project]\nname='Pricing'\n[frontend]\nlanguage='scheme'\n[pipeline]\nbackend='ir-json'" +
      setting,
    ),
    ("src/main.scm", source),
  ])
}

///|
fn inference_plan(
  files : Map[String, String],
) -> (@engine.Engine, @engine.Plan) raise {
  let engine = @engine.Engine::new()
  let plan = engine.plan(
    @engine.Host::memory(files),
    @workspace.discover({ files, directories: ["", "src"], }),
    @engine.Request::new(),
  )
  (engine, plan)
}

///|
fn inference_run(files : Map[String, String]) -> @engine.ContentReport raise {
  let (engine, plan) = inference_plan(files)
  engine.execute_content(plan, fn(path, _) { @data.Text(files[path]) })
}

///|
fn emitted_ir(report : @engine.ContentReport) -> @ir.IRFile raise {
  if !report.successful() {
    fail(report.diagnostics[0].message)
  }
  guard report.artifacts[0].content is @data.Text(text) else { fail("text") }
  @ir_json.read(text)
}

///|
fn value_named(file : @ir.IRFile, name : String) -> @ir.ValueDefinition {
  guard file.distribution is Library(_, _, def) else { panic() }
  for _, m in def.modules {
    for n, v in m.value.values {
      if n.to_canonical() == name {
        return v.value.value
      }
    }
  }
  panic()
}

///|
fn inference_int() -> @ir.Type {
  Reference(
    Default::default(),
    @ir.FQName::parse("morphir/SDK:basics#int") catch {
      _ => panic()
    },
    [],
  )
}

///|
test "inference off leaves the IR unchanged" {
  let file = emitted_ir(
    inference_run(inference_files(None, "(define (inc x) (+ x 1))")),
  )
  guard value_named(file, "inc") is ExpressionBody([(_, input)], _, _) else {
    fail("inc")
  }
  assert_true(input is Variable(a, _) && a.is_unknown())
}

///|
test "inference fill on a plain backend writes node types" {
  let file = emitted_ir(
    inference_run(inference_files(Some("fill"), "(define (inc x) (+ x 1))")),
  )
  guard value_named(file, "inc") is ExpressionBody([(_, input)], output, body) else {
    fail("inc")
  }
  assert_true(@typing.types_equivalent(input, inference_int()))
  assert_true(@typing.types_equivalent(output, inference_int()))
  assert_true(body is Apply(a, _, _) && a.inferred_type is Some(_))
}

///|
test "inference fill on the checkpoint path keeps metadata on its logical nodes" {
  let registry = @data.Registry::new()
  // The quoted list is written compact before the fill and expanded after it, so its items move.
  let ir = @frontend.compile_file("(define (nums x) (+ x (length '(1 2))))")
  let list = "value:user:main#nums/body/Apply/argument/Apply/argument"
  let unit = @data.IRUnit::new("main", ir, metadata=[
    {
      node_id: list + "/List/1",
      data: @ion_text.read_ion("{note:\"second\"}"),
    },
  ])
  let files = Map::from_array([
    (
      "morphir.toml", "[project]\nname='Pricing'\n[frontend]\nlanguage='ion-text'\n[pipeline]\nbackend='checkpoint'\ncheckpoint_format='ion-text'\ninference='fill'",
    ),
    ("src/main.ion", "placeholder"),
  ])
  let content = registry.encode("ion-text", unit)
  let (engine, plan) = inference_plan(files)
  let report = engine.execute_content(plan, fn(_, _) { content })
  if !report.successful() {
    fail(report.diagnostics[0].message)
  }
  let out = registry.decode("ion-text", {
    unit_id: "main",
    content: report.artifacts[0].content,
  })
  assert_eq(out.metadata.map(m => m.node_id), [list + "/List/items/1"])
  assert_eq(out.provenance.length(), 1)
}

///|
test "inference check reports each problem at stage inference" {
  let report = inference_run(
    inference_files(Some("check"), "(define (bad x) (string-append x 1))"),
  )
  assert_false(report.successful())
  assert_true(report.diagnostics.length() > 0)
  assert_true(report.diagnostics.all(d => d.stage == "inference"))
  assert_true(report.diagnostics.all(d => d.message.contains(" at value:")))
}

///|
test "inference check accepts Scheme integer literals" {
  for source in ["(define (inc x) (+ x 1))", "(define (pick c) (if c 1 2))"] {
    let report = inference_run(inference_files(Some("check"), source))
    if !report.successful() {
      fail(source + ": " + report.diagnostics[0].message)
    }
  }
}

///|
test "invalid inference value names its origin" {
  let message = try {
    ignore(
      inference_plan(inference_files(Some("maybe"), "(define (inc x) (+ x 1))")),
    )
    ""
  } catch {
    @configuration.Invalid(text) => text
    other => other.to_string()
  }
  assert_true(
    message.contains("pipeline.inference must be 'off', 'fill' or 'check'"),
  )
  assert_true(message.contains("(set in "))
  assert_true(message.contains("morphir.toml"))
}

///|
test "invalid inference value in a Scheme script names the script" {
  // With no TOML key, and with a TOML key that the script overrides.
  for toml in [None, Some("fill")] {
    let files = inference_files(toml, "(define (inc x) (+ x 1))")
    files["morphir.config.scm"] = "(pipeline (inference \"maybe\"))"
    let message = try {
      ignore(inference_plan(files))
      ""
    } catch {
      @configuration.Invalid(text) => text
      other => other.to_string()
    }
    assert_true(
      message.contains(
        "pipeline.inference must be 'off', 'fill' or 'check', not 'maybe'",
      ),
    )
    assert_true(message.contains("(set in morphir.config.scm)"))
    assert_false(message.contains("morphir.toml"))
  }
}

///|
test "the Scheme pipeline form sets inference" {
  let files = inference_files(None, "(define (inc x) (+ x 1))")
  files["morphir.config.scm"] = "(pipeline (inference \"fill\"))"
  guard value_named(emitted_ir(inference_run(files)), "inc")
    is ExpressionBody([(_, input)], _, _) else {
    fail("inc")
  }
  assert_true(@typing.types_equivalent(input, inference_int()))
}

///|
/// Runs `unit` through an `ion-text` checkpoint project with `inference='fill'` and the default metadata policy.
fn inference_checkpoint(unit : @data.IRUnit) -> @data.IRUnit raise {
  let registry = @data.Registry::new()
  let files = Map::from_array([
    (
      "morphir.toml", "[project]\nname='Pricing'\n[frontend]\nlanguage='ion-text'\n[pipeline]\nbackend='checkpoint'\ncheckpoint_format='ion-text'\ninference='fill'",
    ),
    ("src/main.ion", "placeholder"),
  ])
  let content = registry.encode("ion-text", unit)
  let (engine, plan) = inference_plan(files)
  let report = engine.execute_content(plan, fn(_, _) { content })
  if !report.successful() {
    fail(report.diagnostics[0].message)
  }
  registry.decode("ion-text", {
    unit_id: "main",
    content: report.artifacts[0].content,
  })
}

///|
test "inference fill attaches no metadata to written types under the default policy" {
  // The fill writes a type on the body, a new attribute node derived from a node with metadata. The default
  // `retain` policy refuses derived metadata, so the stage must not use the job's policy.
  let body = "value:user:main#inc/body/Apply"
  let ir = @frontend.compile_file("(define (inc x) (+ x 1))")
  let out = inference_checkpoint(
    @data.IRUnit::new("main", ir, metadata=[
      { node_id: body, data: @ion_text.read_ion("{note:\"body\"}"), },
    ]),
  )
  assert_eq(out.metadata.map(m => m.node_id), [body])
  guard out.distribution.distribution is Library(_, _, def) else {
    fail("library")
  }
  let typed = def.modules
    .values()
    .any(m => {
      m.value.values
      .values()
      .any(v => {
        v.value.value is ExpressionBody(_, _, Apply(a, _, _)) &&
        a.inferred_type is Some(_)
      })
    })
  assert_true(typed)
}

///|
test "inference fill runs before a generator backend" {
  // A generator backend takes the job's checkpoint unit, so the stage must give it the filled unit.
  let files = inference_files(Some("fill"), "(define (inc x) (+ x 1))")
  files["morphir.toml"] = files["morphir.toml"].replace(
    old="backend='ir-json'",
    new="backend='elm'",
  )
  let report = inference_run(files)
  if !report.successful() {
    fail(report.diagnostics[0].message)
  }
  assert_true(report.artifacts.any(a => a.path.has_suffix("elm.json")))
  let main = report.artifacts
    .search_by(a => a.path.has_suffix("src/Pricing/Main.elm"))
    .unwrap()
  guard report.artifacts[main].content is @data.Text(text) else { fail("text") }
  assert_true(text.contains("inc : Int -> Int"), msg=text)
}
