///|
test "retained generation preserves logical identity independently of output paths" {
  let engine = @engine.Engine::new()
  let unit = @data.IRUnit::new("retained/../logical:id", @fixtures.library())
  let plan = engine.plan_retained_generation(unit, "moonbit", "out")
  assert_eq(plan.boundaries()[0].unit_id, unit.id)
  let report = engine.execute_content(plan, fn(_, _) { @data.Text("") })
  assert_true(report.successful())
  assert_eq(report.processed, 1)
  assert_true(
    report.artifacts.all(file => file.path.has_prefix("out/compile.dest/model/")),
  )
  assert_true(report.artifacts.any(file => file.content is @data.Binary(_)))
}

///|
test "retained plan owns nested semantic maps and rich source context" {
  let engine = @engine.Engine::new()
  let metadata = @ion_text.read_ion(
    "owner::{amount:123.4500,bytes:{{AP8=}},duplicate:1,duplicate:2}",
  )
  let provenance = @ion_text.read_ion("origin::{source:\"captured\"}")
  let unit = {
    ..@data.IRUnit::new("retained", @fixtures.library()),
    metadata: [{ node_id: "unit:retained", data: metadata, }],
    provenance: [provenance],
  }
  let registry = @data.Registry::new()
  let original = registry.checkpoint(unit)
  let plan = engine.plan_retained_generation(unit, "moonbit", "out")
  // Caller aliases remain mutable after acceptance. They must not be retained.
  if metadata.kind() is Struct(fields) {
    fields.clear()
  }
  if provenance.kind() is Struct(fields) {
    fields.clear()
  }
  unit.metadata.clear()
  unit.provenance.clear()
  unit.annotations.clear()
  guard unit.distribution.distribution is Library(_, dependencies, definition) else {
    fail("fixture library")
  }
  dependencies.clear()
  definition.modules.clear()
  let observed = []
  let report = engine.execute_content(plan, fn(_, _) { @data.Text("") }, on_unit=compiled => {
    observed.push(compiled.unit)
  })
  assert_true(report.successful())
  assert_eq(observed.map(unit => registry.checkpoint(unit)), [original])
  assert_true(report.artifacts.any(file => file.content is @data.Binary(_)))
}

///|
test "retained plan refuses malformed context before acceptance" {
  let unit = @data.IRUnit::new("retained", @fixtures.library(), metadata=[
    { node_id: "unit:another", data: @ion.IonValue::string("unowned"), },
  ])
  let refused = try {
    ignore(
      @engine.Engine::new().plan_retained_generation(unit, "moonbit", "out"),
    )
    false
  } catch {
    @data.Invalid("data.invalid_identity", _) => true
    _ => false
  }
  assert_true(refused)
}

///|
test "retained plan snapshot keeps default context traversal bounds" {
  let unit = {
    ..@data.IRUnit::new("retained", @fixtures.library()),
    provenance: Array::make(100001, @ion.IonValue::string("bounded")),
  }
  let refused = try {
    ignore(
      @engine.Engine::new().plan_retained_generation(unit, "moonbit", "out"),
    )
    false
  } catch {
    @data.Invalid("data.tree_limit", _) => true
    _ => false
  }
  assert_true(refused)
}
