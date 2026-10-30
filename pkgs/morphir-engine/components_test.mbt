///|
test "JSON-only components receive standard JSON while the Ion sidecar survives" {
  let files = generation_files("checkpoint", language="ion-binary")
  files["morphir.toml"] = files["morphir.toml"] +
    "\ncomponents=['json-identity']"
  files.remove("src/main.json")
  files["src/main.ionb"] = "placeholder"
  let registry = @data.Registry::new()
  let unit = @data.IRUnit::new("main", @fixtures.library(), metadata=[
    {
      node_id: "value:pricing:scalars#rate/body",
      data: @ion.IonValue::string("opaque").with_annotation(
        @ion.symbol("unknown"),
      ),
    },
  ])
  let engine = @engine.Engine::new()
  let plan = generation_plan(engine, files)
  assert_eq(plan.component_boundaries()[0].transport, "morphir-json")
  assert_eq(plan.boundaries()[0].output_format, "ion-binary")
  let report = engine.execute_content(plan, fn(_, _) raise {
    registry.encode("ion-binary", unit)
  })
  assert_true(report.successful())
  let restored = registry.decode("ion-binary", {
    unit_id: "main",
    content: report.artifacts[0].content,
  })
  assert_true(restored.metadata[0].data.equals(unit.metadata[0].data))
  assert_eq(restored.distribution, unit.distribution)
  assert_eq(restored.annotations, unit.annotations)
}

///|
test "undeclared structural rewrite is rejected before generation" {
  let files = generation_files("moonbit")
  files["morphir.toml"] = files["morphir.toml"] + "\ncomponents=['remove']"
  let engine = @engine.Engine::new()
  engine.register_component(
    "remove",
    @engine.Native(fn(_) raise {
      {
        distribution: @ir.IRFile::new(
          @ir.Distribution::Library(@ir.Path::parse("different"), Map([]), {
            modules: Map([]),
          }),
        ),
        lineage: None,
      }
    }),
  )
  let report = engine.execute_content(generation_plan(engine, files), fn(_, _) {
    @data.Text(files["src/main.json"])
  })
  assert_false(report.successful())
  assert_eq(report.diagnostics[0].stage, "component")
  assert_true(report.diagnostics[0].message.contains("data.lineage_required"))
  assert_true(report.artifacts.is_empty())
}
