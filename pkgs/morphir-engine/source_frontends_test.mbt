///|
fn rich_files(backend~ : String = "checkpoint") -> Map[String, String] {
  Map::from_array([
    (
      "morphir.toml",
      "[project]\nname='Example Project'\nmodule_prefix='App'\n[frontend]\nlanguage='rich'\n[pipeline]\nbackend='" +
      backend +
      "'",
    ),
    ("src/Main.model", "opaque"),
  ])
}

///|
fn rich_plan(
  engine : @engine.Engine,
  files : Map[String, String],
) -> @engine.Plan raise {
  engine.plan(
    @engine.Host::memory(files),
    @workspace.discover({ files, directories: ["", "src"], }),
    @engine.Request::new(),
  )
}

///|
test "unit frontend planning is lazy and fixes its callback and dependency inventory" {
  let engine = @engine.Engine::new()
  let dependencies = Map::from_array([("parser", "1.0")])
  let mut calls = 0
  let data = @ion.IonValue::string("origin").with_annotation(
    @ion.SymbolToken::new("audit"),
  )
  engine.register_unit_frontend(
    "rich",
    [".model"],
    fn(source, unit_id, _) raise {
      calls += 1
      assert_eq(source.package_name, "example-project")
      assert_eq(source.module_name, "app/main")
      assert_eq(unit_id, "Main")
      @data.IRUnit::new(unit_id, @fixtures.library(), metadata=[
        { node_id: "value:pricing:scalars#rate/body", data, },
      ])
    },
    profile=Some("test-source-v1"),
    dependencies~,
  )
  dependencies["parser"] = "wrong"
  let files = rich_files()
  let base = @engine.Host::memory(files)
  let lazy_host = {
    ..base,
    read: fn(path) raise {
      if path.has_suffix(".model") {
        fail("Planning must not read source bodies")
      }
      (base.read)(path)
    },
  }
  let plan = engine.plan(
    lazy_host,
    @workspace.discover({ files, directories: ["", "src"], }),
    @engine.Request::new(),
  )
  assert_eq(calls, 0)
  let selection = plan.source_frontends()[0]
  assert_eq(selection.profile, Some("test-source-v1"))
  assert_eq(selection.dependencies["parser"], "1.0")
  assert_eq(selection.output_contract, "ir-unit")
  selection.dependencies["parser"] = "changed"
  assert_eq(plan.source_frontends()[0].dependencies["parser"], "1.0")
  // Legacy replacement remains supported but cannot change an existing plan.
  engine.register_frontend("rich", [".model"], fn(_) raise {
    @fixtures.library()
  })
  let report = engine.execute_content(plan, fn(_, _) { @data.Text("opaque") })
  assert_true(report.successful())
  assert_eq(calls, 1)
  let unit = @data.Registry::new().decode("ion-binary", {
    unit_id: "Main",
    content: report.artifacts[0].content,
  })
  assert_true(unit.metadata[0].data.equals(data))
}

///|
test "unit identity and unowned or duplicate metadata fail before output" {
  for
    (unit, code) in [
      (@data.IRUnit::new("wrong", @fixtures.library()), "data.unit_mismatch"),
      (
        @data.IRUnit::new("Main", @fixtures.library(), metadata=[
          { node_id: "unowned", data: @ion.IonValue::int(1), },
        ]),
        "data.invalid_identity",
      ),
      (
        @data.IRUnit::new("Main", @fixtures.library(), metadata=[
          {
            node_id: "value:pricing:scalars#rate/body",
            data: @ion.IonValue::int(1),
          },
          {
            node_id: "value:pricing:scalars#rate/body",
            data: @ion.IonValue::int(2),
          },
        ]),
        "data.invalid_identity",
      ),
    ] {
    let engine = @engine.Engine::new()
    engine.register_unit_frontend("rich", [".model"], fn(_, _, _) { unit })
    let report = engine.execute_content(rich_plan(engine, rich_files()), fn(
      _,
      _,
    ) {
      @data.Text("opaque")
    })
    assert_eq(report.processed, 0)
    assert_true(report.artifacts.is_empty())
    assert_eq(report.diagnostics[0].stage, "frontend")
    assert_true(report.diagnostics[0].message.has_prefix(code))
  }
}

///|
test "unit frontends require typed output and reject conflicting registration" {
  let engine = @engine.Engine::new()
  engine.register_unit_frontend("rich", [".model"], fn(_, id, _) raise {
    @data.IRUnit::new(id, @fixtures.library())
  })
  let invalid = try {
    ignore(rich_plan(engine, rich_files(backend="ir-json")))
    false
  } catch {
    @configuration.Invalid(message) => {
      assert_true(message.contains("frontend.typed_backend_required"))
      true
    }
    error => raise error
  }
  assert_true(invalid)
  let conflict = try {
    engine.register_unit_frontend("ion-binary", [".model"], fn(_, id, _) raise {
      @data.IRUnit::new(id, @fixtures.library())
    })
    false
  } catch {
    @configuration.Invalid(message) => {
      assert_true(message.contains("frontend.registration_conflict"))
      true
    }
    error => raise error
  }
  assert_true(conflict)
}

///|
test "configured source unit budgets apply before checkpoint or generation" {
  for
    (limits, code) in [
      ({ ..@data.Limits::default(), max_bytes: 1, }, "data.byte_limit"),
      ({ ..@data.Limits::default(), max_values: 1, }, "data.tree_limit"),
    ] {
    let engine = @engine.Engine::new()
    engine.register_unit_frontend(
      "rich",
      [".model"],
      fn(_, id, _) raise { @data.IRUnit::new(id, @fixtures.library()) },
      limits~,
    )
    let report = engine.execute_content(rich_plan(engine, rich_files()), fn(
      _,
      _,
    ) {
      @data.Text("opaque")
    })
    assert_eq(report.processed, 0)
    assert_true(report.artifacts.is_empty())
    assert_true(report.diagnostics[0].message.has_prefix(code))
  }
}
