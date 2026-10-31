///|
fn files(
  backend~ : String = "checkpoint",
  component~ : Bool = false,
) -> Map[String, String] {
  Map::from_array([
    (
      "morphir.toml",
      "[project]\nname='Pricing'\nmodule_prefix='App'\n[frontend]\nlanguage='moonbit'\n[pipeline]\nbackend='" +
      backend +
      "'\nvalidation='source-only'\n" +
      (if component { "components=['json-identity']" } else { "" }),
    ),
    (
      "src/Main.mbt", "// λ😀\npub fn eligible(active : Bool, vip : Bool) -> Bool { active && !vip }",
    ),
  ])
}

///|
test "pinned Basics not source call reaches the engine evaluator" {
  let snapshot = files()
  snapshot["morphir.toml"] = snapshot["morphir.toml"].replace(
    old="language='moonbit'",
    new="language='moonbit'\nprofile='moonbit-model-stable-v1'",
  )
  snapshot["src/Main.mbt"] = "pub fn invert(flag : Bool) -> Bool { @basics.not_(flag) }"
  let engine = @engine.Engine::new()
  @adapter.register(engine)
  let descriptor = plan(engine, snapshot).source_frontends()[0]
  assert_eq(
    descriptor.dependencies["finos/morphir-sdk/basics"],
    "0.1.0+tree:9c83a100383570236b3d781362524008f76dd56d",
  )
  let report = execute(engine, snapshot)
  assert_true(report.successful())
  let unit = @data.Registry::new().decode("ion-binary", {
    unit_id: "Main",
    content: report.artifacts[0].content,
  })
  let suite = @protocol.Suite::from_json({
    "profile": "morphir-invocations-v1",
    "calls": [
      {
        "id": "true",
        "entry": "pricing:app/main#invert",
        "arguments": [{ "type": "bool", "value": true }],
      },
      {
        "id": "false",
        "entry": "pricing:app/main#invert",
        "arguments": [{ "type": "bool", "value": false }],
      },
    ],
  })
  let plan = @execution.plan_scheme(unit, suite)
  assert_eq(plan.evaluate().map(@protocol.Value::to_json), [
    { "type": "bool", "value": false },
    { "type": "bool", "value": true },
  ])
}

///|
test "pinned binding rejects unknown, mismatched and shadowed source calls through engine" {
  let snapshot = files()
  snapshot["morphir.toml"] = snapshot["morphir.toml"].replace(
    old="language='moonbit'",
    new="language='moonbit'\nprofile='moonbit-model-stable-v1'",
  )
  let engine = @engine.Engine::new()
  @adapter.register(engine)
  for
    (source, code) in [
      (
        "pub fn invert(flag : Bool) -> Bool { @other.not_(flag) }", "unknown_binding",
      ),
      (
        "pub fn invert(flag : Bool) -> Bool { @basics.and_(flag, flag) }", "unknown_binding",
      ),
      (
        "pub fn invert(value : Int32) -> Bool { @basics.not_(value) }", "type_mismatch",
      ),
      ("pub fn invert() -> Bool { @basics.not_() }", "binding_arity"),
      (
        "pub fn invert(basics : Bool) -> Bool { @basics.not_(basics) }", "shadowed_binding",
      ),
    ] {
    snapshot["src/Main.mbt"] = source
    let report = execute(engine, snapshot)
    assert_false(report.successful())
    assert_true(report.artifacts.is_empty())
    assert_true(
      report.diagnostics[0].message.has_prefix("moonbit_frontend." + code + ":"),
    )
    assert_true(report.diagnostics[0].message.contains(" at 1:"))
  }
  snapshot["src/Main.mbt"] = "pub fn invert(flag : Bool) -> Bool { @basics.not_(flag) }"
  snapshot["morphir.toml"] += "\ncheckpoint_format='morphir-json'"
  let lossy = execute(engine, snapshot)
  assert_false(lossy.successful())
  assert_true(lossy.artifacts.is_empty())
  assert_true(lossy.diagnostics[0].message.contains("data.lossy_conversion"))
}

///|
test "math snapshot resolves finite calls and refuses invalid bindings through engine" {
  let snapshot = files()
  snapshot["morphir.toml"] = snapshot["morphir.toml"].replace(
    old="language='moonbit'",
    new="language='moonbit'\nprofile='moonbit-model-experimental-v1'",
  )
  let engine = @engine.Engine::new()
  @adapter.register(engine)
  snapshot["src/Main.mbt"] = "pub fn root() -> Double { @basics.sqrt(4.0) }"
  let report = execute(engine, snapshot)
  assert_true(report.successful())
  let registry = @data.Registry::new()
  let unit = registry.decode("ion-binary", {
    unit_id: "Main",
    content: report.artifacts[0].content,
  })
  // Future facts on the real checkpoint survive both Ion encodings.
  let future = @ion.IonValue::from_fields([
    @ion.field("future_math", @ion.IonValue::string("retain-me")),
  ])
  let metadata = unit.metadata.copy()
  let owner = metadata[0]
  let original = owner.data
  metadata[0] = {
    ..owner,
    data: @ion.IonValue::from_fields([
      @ion.field("source_facts", original),
      @ion.field("future_math", future),
    ]),
  }
  let unit = { ..unit, metadata, }
  for format in ["ion-text", "ion-binary"] {
    let replay = registry.decode(format, {
      unit_id: "Main",
      content: registry.encode(format, unit),
    })
    assert_true(replay.metadata[0].data.equals(unit.metadata[0].data))
  }
  let suite = @protocol.Suite::from_json({
    "profile": "morphir-invocations-v1",
    "calls": [
      { "id": "root", "entry": "pricing:app/main#root", "arguments": [] },
    ],
  })
  assert_eq(
    @execution.plan_scheme(unit, suite).evaluate().map(@protocol.Value::to_json),
    [{ "type": "float64", "bits": "4611686018427387904" }],
  )
  for
    (source, code) in [
      ("pub fn root() -> Double { @other.sqrt(4.0) }", "unknown_binding"),
      ("pub fn root() -> Double { @basics.tan(4.0) }", "unknown_binding"),
      ("pub fn root() -> Double { @basics.sqrt(true) }", "type_mismatch"),
      ("pub fn root() -> Double { @basics.sqrt() }", "binding_arity"),
      (
        "pub fn root(basics : Double) -> Double { @basics.sqrt(basics) }", "shadowed_binding",
      ),
    ] {
    snapshot["src/Main.mbt"] = source
    let failed = execute(engine, snapshot)
    assert_false(failed.successful())
    assert_true(failed.artifacts.is_empty())
    assert_true(
      failed.diagnostics[0].message.has_prefix("moonbit_frontend." + code + ":"),
    )
  }
}

///|
fn plan(
  engine : @engine.Engine,
  snapshot : Map[String, String],
) -> @engine.Plan raise {
  engine.plan(
    @engine.Host::memory(snapshot),
    @workspace.discover({ files: snapshot, directories: ["", "src"], }),
    @engine.Request::new(),
  )
}

///|
fn execute(
  engine : @engine.Engine,
  snapshot : Map[String, String],
) -> @engine.ContentReport raise {
  engine.execute_content(plan(engine, snapshot), fn(path, _) {
    @data.Text(snapshot[path])
  })
}

///|
test "adapter observation is lazy and leaves binary Ion checkpoints unchanged" {
  let snapshot = files(component=true)
  let plain = @engine.Engine::new()
  @adapter.register(plain)
  let expected = execute(plain, snapshot)
  let records : Array[@observe.Observation] = []
  let engine = @engine.Engine::new()
  let observer : @observe.Observer = {
    ..@observe.Observer::noop(),
    enabled: fn() { true },
    try_record: fn(record) {
      records.push(record)
      @observe.Accepted
    },
  }
  @adapter.register(engine, observer~)
  let planned = plan(engine, snapshot)
  assert_eq(
    planned.source_frontends()[0].profile,
    Some("moonbit-model-stable-v1"),
  )
  assert_true(records.is_empty())
  let actual = execute(engine, snapshot)
  assert_true(actual.successful())
  guard actual.artifacts[0].content is @data.Binary(a) else {
    fail("Expected Ion binary")
  }
  guard expected.artifacts[0].content is @data.Binary(b) else {
    fail("Expected Ion binary")
  }
  assert_eq(a, b)
  assert_eq(
    records.filter(r => r.signal == @observe.Succeeded).map(r => r.stage),
    [
      @observe.Parse,
      @observe.ProfileCheck,
      @observe.Resolve,
      @observe.ProfileCheck,
      @observe.Lower,
      @observe.Frontend,
    ],
  )
}

///|
test "explicit MoonBit registration preserves Ion origins through a JSON component" {
  let engine = @engine.Engine::new()
  let unavailable = try {
    ignore(plan(engine, files()))
    false
  } catch {
    @config.Invalid(message) => {
      assert_true(message.contains("Unknown frontend: moonbit"))
      true
    }
    error => raise error
  }
  assert_true(unavailable)
  @adapter.register(engine)
  let baseline = execute(engine, files())
  let rewritten = execute(engine, files(component=true))
  assert_true(baseline.successful())
  assert_true(rewritten.successful())
  let registry = @data.Registry::new()
  let original = registry.decode("ion-binary", {
    unit_id: "Main",
    content: baseline.artifacts[0].content,
  })
  let processed = registry.decode("ion-binary", {
    unit_id: "Main",
    content: rewritten.artifacts[0].content,
  })
  assert_eq(original.metadata.length(), 2)
  for (before, after) in original.metadata.zip(processed.metadata) {
    assert_eq(before.node_id, after.node_id)
    assert_true(before.data.equals(after.data))
  }
  assert_true(processed.provenance[0].equals(original.provenance[0]))
  assert_eq(processed.provenance.length(), 1)
  let entry = @ir.FQName::parse("pricing:app/main#eligible")
  for
    (active, vip, expected) in [
      (false, false, false),
      (false, true, false),
      (true, false, true),
      (true, true, false),
    ] {
    guard @backend.run_file(processed.distribution, entry, [
        @scheme.Boolean(active),
        @scheme.Boolean(vip),
      ])
      is Boolean(actual) else {
      fail("Expected Boolean")
    }
    assert_eq(actual, expected)
  }
}

///|
test "generated library Ion retains the adapted frontend metadata and provenance" {
  let engine = @engine.Engine::new()
  @adapter.register(engine)
  let report = execute(engine, files(backend="moonbit", component=true))
  assert_true(report.successful())
  assert_eq(report.projects.length(), 1)
  let artifact = report.artifacts.filter(a => a.path.has_suffix("symbols.10n"))[0]
  guard artifact.content is @data.Binary(bytes) else {
    fail("Expected Ion bytes")
  }
  let symbols = @ion_binary.read_binary_value(bytes[:])
  guard symbols.kind() is @ion.Struct(fields) else {
    fail("Expected symbol record")
  }
  let by_name = Map([])
  for field in fields {
    by_name[field.name().text().unwrap()] = field.value()
  }
  guard by_name["metadata"].kind() is @ion.List(metadata) else {
    fail("Expected metadata")
  }
  guard by_name["source_provenance"].kind() is @ion.List(provenance) else {
    fail("Expected provenance")
  }
  assert_eq(metadata.length(), 2)
  assert_eq(provenance.length(), 1)
  assert_eq(
    provenance[0].annotations()[0].text(),
    Some("morphir_moonbit_frontend"),
  )
}

///|
test "MoonBit dry runs describe the parser without parsing malformed source" {
  let engine = @engine.Engine::new()
  @adapter.register(engine)
  let snapshot = files()
  snapshot["src/Main.mbt"] = "pub fn broken("
  let planned = plan(engine, snapshot)
  let descriptor = planned.source_frontends()[0]
  assert_eq(descriptor.profile, Some("moonbit-model-stable-v1"))
  assert_eq(descriptor.dependencies["moonbitlang/parser"], "0.4.5")
  assert_eq(descriptor.unit_id, "Main")
  let report = engine.execute_content(planned, fn(path, _) {
    @data.Text(snapshot[path])
  })
  assert_eq(report.processed, 0)
  assert_eq(report.diagnostics[0].stage, "frontend")
  assert_true(
    report.diagnostics[0].message.has_prefix("moonbit_frontend.syntax:"),
  )
}

///|
test "MoonBit rejection and cancellation retain diagnostic codes and spans" {
  let engine = @engine.Engine::new()
  @adapter.register(engine)
  let snapshot = files()
  snapshot["src/Main.mbt"] = "pub fn bad(x : @other.Bool) -> Bool { true }"
  let rejected = execute(engine, snapshot)
  assert_true(
    rejected.diagnostics[0].message.has_prefix(
      "moonbit_frontend.unsupported_type:",
    ),
  )
  assert_true(rejected.diagnostics[0].message.contains(" at 1:"))
  let snapshot = files()
  let mut polls = 0
  let cancelled = engine.execute_content(
    plan(engine, snapshot),
    fn(path, _) { @data.Text(snapshot[path]) },
    cancelled=fn() {
      polls += 1
      polls > 3
    },
  )
  assert_eq(cancelled.processed, 0)
  assert_true(cancelled.artifacts.is_empty())
  assert_true(
    cancelled.diagnostics[0].message.has_prefix("moonbit_frontend.cancelled:"),
  )
}

///|
test "multiple MoonBit source files produce independent logical units" {
  let engine = @engine.Engine::new()
  @adapter.register(engine)
  let snapshot = files()
  snapshot["src/nested/Other.mbt"] = "pub fn other(x : Bool) -> Bool { !x }"
  snapshot["src/ignored.json"] = "not a MoonBit model"
  let planned = plan(engine, snapshot)
  assert_eq(planned.source_frontends().map(f => f.unit_id), [
    "Main", "nested/Other",
  ])
  let report = engine.execute_content(planned, fn(path, _) {
    @data.Text(snapshot[path])
  })
  assert_eq(report.processed, 2)
  assert_eq(report.artifacts.length(), 2)
  let artifact = report.artifacts.filter(a => a.source == "src/nested/Other.mbt")[0]
  let unit = @data.Registry::new().decode("ion-binary", {
    unit_id: "nested/Other",
    content: artifact.content,
  })
  let entry = @ir.FQName::parse("pricing:app/nested/other#other")
  guard @backend.run_file(unit.distribution, entry, [@scheme.Boolean(false)])
    is Boolean(actual) else {
    fail("Expected Boolean")
  }
  assert_true(actual)
}

///|
fn library_files(backend~ : String = "checkpoint") -> Map[String, String] {
  let snapshot = files(backend~, component=true)
  snapshot["morphir.toml"] = snapshot["morphir.toml"].replace(
    old="language='moonbit'",
    new="language='moonbit'\nprofile='moonbit-model-stable-v1'",
  )
  snapshot["src/Main.mbt"] = "fn helper(x : Bool) -> Bool { !x }\npub fn eligible(x : Bool) -> Bool { let y = helper(x); y }\npub fn zero() -> Bool { eligible(false) }"
  snapshot
}

///|
test "library selection preserves native origins, calls and all public entries" {
  let engine = @engine.Engine::new()
  @adapter.register(engine)
  let snapshot = library_files()
  let descriptor = plan(engine, snapshot).source_frontends()[0]
  assert_eq(descriptor.language, "moonbit")
  assert_eq(descriptor.provider, @adapter.PROVIDER)
  assert_eq(descriptor.profile, Some("moonbit-model-stable-v1"))
  assert_true(descriptor.default_profile)
  assert_eq(descriptor.evidence.name(), "local-acceptance")
  assert_eq(descriptor.capabilities.unwrap().limits["functions"], 64)
  let baseline = execute(engine, snapshot)
  assert_true(baseline.successful())
  let unit = @data.Registry::new().decode("ion-binary", {
    unit_id: "Main",
    content: baseline.artifacts[0].content,
  })
  assert_true(unit.metadata.length() >= 6)
  assert_true(unit.metadata.any(m => m.node_id.has_suffix("/body")))

  for
    (entry, args, expected) in [
      ("eligible", [@scheme.Value::Boolean(false)], true),
      ("eligible", [@scheme.Value::Boolean(true)], false),
      ("zero", [], true),
    ] {
    guard @backend.run_file(
        unit.distribution,
        @ir.FQName::parse("pricing:app/main#" + entry),
        args,
      )
      is Boolean(actual) else {
      fail("Expected Bool")
    }
    assert_eq(actual, expected)
  }
  let generated = execute(engine, library_files(backend="moonbit"))
  assert_true(generated.successful())
  let symbols = generated.artifacts.filter(a => a.path.has_suffix("symbols.10n"))[0]
  guard symbols.content is @data.Binary(bytes) else {
    fail("Expected binary symbols")
  }
  let fields = ion_fields(@ion_binary.read_binary_value(bytes[:]))
  guard fields["symbols"].kind() is @ion.List(entries) else {
    fail("Expected symbols")
  }
  let public_names = entries
    .filter(e => ion_fields(e)["public"].kind() is @ion.Bool(true))
    .map(e => ion_fields(e)["fqname"])
  assert_eq(public_names.length(), 2)
  assert_true(
    public_names.any(n => n.kind() is @ion.String("pricing:app/main#zero")),
  )
  assert_false(
    public_names.any(n => n.kind() is @ion.String("pricing:app/main#helper")),
  )
  guard fields["metadata"].kind() is @ion.List(metadata) else {
    fail("Expected origins")
  }
  assert_eq(metadata.length(), unit.metadata.length())
  let original = Map::from_array(unit.metadata.map(m => (m.node_id, m.data)))
  for entry in metadata {
    let origin = ion_fields(entry)
    guard origin["node_id"].kind() is @ion.String(id) else {
      fail("Expected ID")
    }
    assert_true(origin["data"].equals(original[id]))
  }
  guard fields["source_provenance"].kind() is @ion.List(provenance) else {
    fail("Expected provenance")
  }
  assert_true(provenance[0].equals(unit.provenance[0]))
}

///|
test "all-private libraries checkpoint and do not invent an executable entry" {
  let engine = @engine.Engine::new()
  @adapter.register(engine)
  let snapshot = library_files()
  snapshot["src/Main.mbt"] = "fn hidden() -> Bool { true }"
  assert_true(execute(engine, snapshot).successful())
  snapshot["morphir.toml"] = snapshot["morphir.toml"].replace(
    old="backend='checkpoint'",
    new="backend='moonbit'",
  )
  let generated = execute(engine, snapshot)
  assert_true(generated.successful())
  let library = generated.artifacts.filter(a => a.path.has_suffix("library.mbt"))[0]
  guard library.content is @data.Text(source) else { fail("Expected source") }
  assert_false(source.contains("pub fn"))
}

///|
test "profile limits and diagnostics identify selection without parsing during planning" {
  let engine = @engine.Engine::new()
  @adapter.register(engine, library_limits={
    max_bytes: 65536,
    max_functions: 2,
    max_parameters: 16,
    max_lets: 256,
    max_expressions: 4096,
    max_calls: 1024,
    max_depth: 64,
    max_call_depth: 32,
  })
  let snapshot = library_files()
  assert_eq(
    plan(engine, snapshot).source_frontends()[0].capabilities.unwrap().limits["functions"],
    2,
  )
  let report = execute(engine, snapshot)
  assert_false(report.successful())
  assert_true(
    report.diagnostics[0].message.contains("profile moonbit-model-stable-v1"),
  )
  assert_true(report.diagnostics[0].message.contains(@adapter.PROVIDER))
  assert_true(report.artifacts.is_empty())
  let engine = @engine.Engine::new()
  @adapter.register(engine)
  let snapshot = library_files()
  snapshot["src/Main.mbt"] = "pub fn recurse(x : Bool) -> Bool { recurse(x) }"
  assert_true(
    plan(engine, snapshot).source_frontends()[0].capabilities is Some(_),
  )
  assert_true(
    execute(engine, snapshot).diagnostics[0].message.has_prefix(
      "moonbit_frontend.recursive_call:",
    ),
  )
  snapshot["morphir.toml"] += "\ncheckpoint_format='morphir-json'"
  snapshot["src/Main.mbt"] = "pub fn okay() -> Bool { true }"
  let lossy = execute(engine, snapshot)
  assert_false(lossy.successful())
  assert_true(lossy.artifacts.is_empty())
  assert_true(lossy.diagnostics[0].message.contains("data.lossy_conversion"))
}

///|
test "library observation includes resolution and cancellation publishes nothing" {
  let records : Array[@observe.Observation] = []
  let observer : @observe.Observer = {
    ..@observe.Observer::noop(),
    enabled: fn() { true },
    try_record: fn(record) {
      records.push(record)
      @observe.Accepted
    },
  }
  let engine = @engine.Engine::new()
  @adapter.register(engine, observer~)
  let snapshot = library_files()
  let planned = plan(engine, snapshot)
  assert_true(records.is_empty())
  assert_true(execute(engine, snapshot).successful())
  assert_eq(
    records.filter(r => r.signal == @observe.Succeeded).map(r => r.stage),
    [
      @observe.Parse,
      @observe.ProfileCheck,
      @observe.Resolve,
      @observe.ProfileCheck,
      @observe.Lower,
      @observe.Frontend,
    ],
  )
  let mut polls = 0
  let cancelled = engine.execute_content(
    planned,
    fn(path, _) { @data.Text(snapshot[path]) },
    cancelled=fn() {
      polls += 1
      polls > 3
    },
  )
  assert_eq(cancelled.processed, 0)
  assert_true(cancelled.artifacts.is_empty())
  assert_true(
    cancelled.diagnostics[0].message.has_prefix("moonbit_frontend.cancelled:"),
  )
}

///|
fn ion_fields(value : @ion.IonValue) -> Map[String, @ion.IonValue] raise {
  guard value.kind() is @ion.Struct(fields) else { fail("Expected record") }
  Map::from_array(fields.map(f => (f.name().text().unwrap(), f.value())))
}

///|
test "invalid parser budgets cannot become registered capability claims" {
  let engine = @engine.Engine::new()
  assert_true(
    try {
      @adapter.register(engine, library_limits={
        ..@frontend.LibraryLimits::default(),
        max_bytes: 70000,
      })
      false
    } catch {
      @engine.Rejected(code, _, _) => {
        assert_eq(code, "moonbit_frontend.invalid_limits")
        true
      }
      error => raise error
    },
  )
  // Failed registration leaves no partially registered seed or library profile.
  @adapter.register(engine)
  assert_eq(
    plan(engine, files()).source_frontends()[0].profile,
    Some("moonbit-model-stable-v1"),
  )
}

///|
test "structured source warnings reach reports and replay from Ion exactly once" {
  let engine = @engine.Engine::new()
  @adapter.register(engine)
  let snapshot = library_files()
  snapshot["src/Main.mbt"] = "pub fn is_ready() -> Bool { true }\npub fn isReady() -> Bool { false }"
  let result = execute(engine, snapshot)
  assert_true(result.successful())
  assert_eq(result.warnings.length(), 1)
  assert_eq(result.warnings[0].details.unwrap().locations.length(), 2)
  assert_true(result.warnings[0].message.contains("fix:"))
  let registry = @data.Registry::new()
  let unit = registry.decode("ion-binary", {
    unit_id: "Main",
    content: result.artifacts[0].content,
  })
  // Duplicate provenance retains both assertions but reports one warning per run.
  let repeated = { ..unit, provenance: unit.provenance + [unit.provenance[1]], }
  for format in ["ion-text", "ion-binary"] {
    let content = registry.encode(format, repeated)
    let replay = Map::from_array([
      (
        "morphir.toml",
        "[project]\nname='Pricing'\n[frontend]\nlanguage='" +
        format +
        "'\n[pipeline]\nbackend='checkpoint'\n",
      ),
      ("src/Main" + (if format == "ion-text" { ".ion" } else { ".ionb" }), ""),
    ])
    let restored = engine.execute_content(plan(engine, replay), fn(_, _) {
      content
    })
    assert_true(restored.successful())
    assert_eq(restored.warnings.length(), 1)
    assert_eq(
      restored.warnings[0].details.unwrap().locations,
      result.warnings[0].details.unwrap().locations,
    )
    let decoded = registry.decode("ion-binary", {
      unit_id: "Main",
      content: restored.artifacts[0].content,
    })
    assert_eq(decoded.distribution, unit.distribution)
    assert_eq(decoded.provenance.length(), repeated.provenance.length())
  }
}

///|
test "strict naming records the recovery but produces no artifact or project" {
  let engine = @engine.Engine::new()
  @adapter.register(engine)
  let snapshot = library_files(backend="moonbit")
  snapshot["morphir.toml"] += "\nstrict_naming=true\n"
  snapshot["src/Main.mbt"] = "pub fn is_ready() -> Bool { true }\npub fn isReady() -> Bool { false }"
  let result = execute(engine, snapshot)
  assert_false(result.successful())
  assert_eq(result.warnings.length(), 1)
  assert_true(result.diagnostics[0].message.contains("naming.strict"))
  assert_true(result.artifacts.is_empty())
  assert_true(result.projects.is_empty())
}

///|
test "historical checkpoint names remain unchanged on load and generation" {
  let engine = @engine.Engine::new()
  @adapter.register(engine)
  let result = execute(engine, files())
  let registry = @data.Registry::new()
  let unit = registry.decode("ion-binary", {
    unit_id: "Main",
    content: result.artifacts[0].content,
  })
  let historical = @ir_json.read(
    @ir_json.write(unit.distribution).replace(
      old="eligible",
      new="source-656c696769626c65",
    ),
  )
  let checkpoint = registry.encode(
    "ion-binary",
    @data.IRUnit::new("Main", historical),
  )
  let snapshot = Map::from_array([
    (
      "morphir.toml", "[project]\nname='Pricing'\n[frontend]\nlanguage='ion-binary'\n[pipeline]\nbackend='moonbit'\nvalidation='source-only'\n",
    ),
    ("src/Main.ionb", ""),
  ])
  let generated = engine.execute_content(plan(engine, snapshot), fn(_, _) {
    checkpoint
  })
  assert_true(generated.successful())
  assert_true(generated.warnings.is_empty())
  let receipt = generated.artifacts.filter(a => a.path.has_suffix("symbols.10n"))[0]
  guard receipt.content is @data.Binary(bytes) else {
    fail("Expected Ion symbol receipt")
  }
  let fields = ion_fields(@ion_binary.read_binary_value(bytes[:]))
  guard fields["symbols"].kind() is @ion.List(symbols) else {
    fail("Expected symbols")
  }
  assert_true(
    ion_fields(symbols[0])["fqname"].kind()
    is @ion.String("pricing:app/main#source-656c696769626c65"),
  )
}

///|
fn metadata_entries(bytes : Bytes) -> Array[@ion.IonValue] raise {
  guard @ion_binary.read_binary_value(bytes[:]).kind() is @ion.Struct(fields) else {
    fail("Expected a symbols record")
  }
  for field in fields {
    if field.name().text() == Some("metadata") {
      guard field.value().kind() is @ion.List(entries) else { fail("metadata") }
      return entries
    }
  }
  fail("No metadata field")
}

///|
test "a MoonBit library through the scheme backend keeps its metadata and comments its defines" {
  let engine = @engine.Engine::new()
  @adapter.register(engine)
  let snapshot = library_files(backend="scheme")
  // Components still need a checkpoint or generator backend; a unit backend takes the unit as compiled.
  snapshot["morphir.toml"] = snapshot["morphir.toml"].replace(
    old="components=['json-identity']",
    new="",
  )
  snapshot["src/nested/Other.mbt"] = "pub fn other(x : Bool) -> Bool { !x }"
  let planned = plan(engine, snapshot)
  let report = engine.execute_content(planned, fn(path, _) {
    @data.Text(snapshot[path])
  })
  if !report.successful() {
    fail(report.diagnostics[0].message)
  }
  guard report.artifacts[0].content is @data.Text(source) else {
    fail("Expected Scheme text")
  }
  guard report.artifacts[1].content is @data.Binary(bytes) else {
    fail("Expected binary symbols")
  }
  // Every metadata entry of the checkpoint unit is in the sidecar.
  let checkpoint = execute(engine, library_files())
  if !checkpoint.successful() {
    fail(checkpoint.diagnostics[0].message)
  }
  let unit = @data.Registry::new().decode("ion-binary", {
    unit_id: "Main",
    content: checkpoint.artifacts[0].content,
  })
  let entries = metadata_entries(bytes)
  // The commented text runs.
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  ignore(runtime.eval(source))
  let zero = @scheme.value_to_string(
    @backend.call_entry(runtime, @ir.FQName::parse("pricing:app/main#zero"), []),
  )
  @expect.expect_all(s => {
    s.expect(planned.requires_byte_write(), label="byte write").to_be_true()
    s.expect(report.warnings.length(), label="warnings").to_equal(0)
    s.expect(report.processed, label="processed").to_equal(2)
    s
    .expect(
      report.artifacts.map(a => (a.format, a.source)),
      label="formats and sources",
    )
    .to_contain_exactly([
      ("scheme", "src/Main.mbt"),
      ("ion-binary", "src/Main.mbt"),
      ("scheme", "src/nested/Other.mbt"),
      ("ion-binary", "src/nested/Other.mbt"),
    ])
    s
    .expect(report.artifacts.map(a => a.path), label="paths")
    .to_satisfy_respectively([
      it => it.to_end_with("/Main.scm"),
      it => it.to_end_with("/Main.symbols.10n"),
      it => it.to_end_with("/nested/Other.scm"),
      it => it.to_end_with("/nested/Other.symbols.10n"),
    ])
    s
    .expect(source, label="comments")
    .to_contain_substrings_in_order([
      ";; helper (src/Main.mbt:1:", ";; eligible (src/Main.mbt:2:", ";; zero (src/Main.mbt:3:",
    ])
    s
    .expect(entries, label="metadata entries")
    .to_have_length(unit.metadata.length())
    for pair in entries.zip(unit.metadata) {
      guard pair.0.kind() is @ion.Struct(fields) else { fail("entry") }
      s
      .expect(
        fields[0].value().equals(@ion.IonValue::string(pair.1.node_id)),
        label=pair.1.node_id + " id",
      )
      .to_be_true()
      s
      .expect(
        fields[1].value().equals(pair.1.data),
        label=pair.1.node_id + " data",
      )
      .to_be_true()
    }
    s.expect(zero, label="zero()").to_equal("#t")
  })
}

///|
test "typed foundation and String profiles preserve source facts through Ion checkpoints" {
  for
    (profile, source) in [
      (
        "moonbit-model-stable-v1", "pub fn choose(flag : Bool, a : Int32, b : Int) -> Int32 { let picked : Int = if flag { a } else { b }; identity(picked) }\nfn identity(value : Int32) -> Int { value }",
      ),
      ("moonbit-model-stable-v1", "pub fn wrap() -> Int32 { 2147483647 + 1 }"),
      (
        "moonbit-model-experimental-v1", "pub fn wrap() -> UInt64 { 18446744073709551615UL + 1UL }\npub fn grow() -> BigInt { 18446744073709551616N + 1N }",
      ),
      (
        "moonbit-model-experimental-v1", "pub fn rounded() -> Float { 16777216.0F + 1.0F }\npub fn wider() -> Double { 9007199254740992.0 + 2.0 }",
      ),
      (
        "moonbit-model-stable-v1", "// λ😀\npub fn greet(name : String) -> String { let prefix : String = \"Hello, \\u{1f600} \"; prefix + name }",
      ),
      (
        "moonbit-model-stable-v1", "pub fn choose(s : String, flag : Bool, a : Int32, b : Int) -> Int32 { let text : String = \"Hello, \" + s; if flag && text == \"Hello, Morphir\" { a } else { b } }",
      ),
      (
        "moonbit-model-stable-v1", "pub fn choose(a : String, b : String, x : Int32, y : Int) -> Int32 { if a < b { x } else { y } }",
      ),
      (
        "moonbit-model-stable-v1", "/// Select by name order.\n///\n/// Preserve signed values. λ😀\npub fn choose(a : String, b : String, x : Int32, y : Int) -> Int32 { if a < b { x } else { y } }",
      ),
      (
        "moonbit-model-stable-v1", "pub fn cut(s : String, a : Int32, b : Int32) -> String { s[a:b].to_owned() }",
      ),
    ] {
    let snapshot = files()
    snapshot["morphir.toml"] = snapshot["morphir.toml"].replace(
      old="language='moonbit'",
      new="language='moonbit'\nprofile='" + profile + "'",
    )
    snapshot["src/Main.mbt"] = source
    let engine = @engine.Engine::new()
    @adapter.register(engine)
    let result = execute(engine, snapshot)
    assert_true(result.successful())
    let registry = @data.Registry::new()
    let unit = registry.decode("ion-binary", {
      unit_id: "Main",
      content: result.artifacts[0].content,
    })
    let unknown = @ion.IonValue::string("preserve me")
    let unit = {
      ..unit,
      metadata: unit.metadata +
      [{ node_id: "neighbor:unknown", data: unknown, }],
    }
    for format in ["ion-text", "ion-binary"] {
      let restored = registry.decode(format, {
        unit_id: "Main",
        content: registry.encode(format, unit),
      })
      assert_eq(restored.distribution, unit.distribution)
      assert_true(restored.metadata.last().unwrap().data.equals(unknown))
    }
  }
}

///|
test "source scalar libraries use strict and selected Scheme invocation plans" {
  let cases : Array[(String, String, Array[Json], Json)] = [
    (
      "moonbit-model-stable-v1",
      "pub fn choose(flag : Bool, a : Int32, b : Int) -> Int32 { if flag { a } else { b } }",
      [
        { "type": "bool", "value": true },
        {
          "type": "custom",
          "owner": "morphir/SDK:int#int-32",
          "tag": "morphir/SDK:int#int32",
          "items": [{ "type": "int", "value": "-2147483648" }],
        },
        {
          "type": "custom",
          "owner": "morphir/SDK:int#int-32",
          "tag": "morphir/SDK:int#int32",
          "items": [{ "type": "int", "value": "2147483647" }],
        },
      ],
      (
        {
          "type": "custom",
          "owner": "morphir/SDK:int#int-32",
          "tag": "morphir/SDK:int#int32",
          "items": [{ "type": "int", "value": "-2147483648" }],
        } : Json),
    ),
    (
      "moonbit-model-stable-v1",
      "pub fn choose(s : String) -> String { \"Hello \" + s }",
      [{ "type": "text", "units": [55357, 56832] }],
      (
        { "type": "text", "units": [72, 101, 108, 108, 111, 32, 55357, 56832] } :
        Json),
    ),
    (
      "moonbit-model-experimental-v1",
      "pub fn choose(value : UInt64) -> UInt64 { value + 1UL }",
      [
        {
          "type": "custom",
          "owner": "morphir/SDK:int#uint-64",
          "tag": "morphir/SDK:int#uint-64",
          "items": [{ "type": "int", "value": "18446744073709551615" }],
        },
      ],
      (
        {
          "type": "custom",
          "owner": "morphir/SDK:int#uint-64",
          "tag": "morphir/SDK:int#uint-64",
          "items": [{ "type": "int", "value": "0" }],
        } : Json),
    ),
    (
      "moonbit-model-experimental-v1",
      "pub fn choose(value : Float) -> Float { value + 1.0F }",
      [{ "type": "float64", "bits": "4715268809856909312" }],
      ({ "type": "float64", "bits": "4715268809856909312" } : Json),
    ),
    (
      "moonbit-model-experimental-v1",
      "pub fn choose() -> Float { -0.0F }",
      [],
      ({ "type": "float64", "bits": "9223372036854775808" } : Json),
    ),
    (
      "moonbit-model-experimental-v1",
      "pub fn choose() -> Float { 1.401298464324817e-45F }",
      [],
      ({ "type": "float64", "bits": "3936146074321813504" } : Json),
    ),
    (
      "moonbit-model-experimental-v1",
      "pub fn choose() -> Float { 1.0F / 0.0F }",
      [],
      ({ "type": "float64", "bits": "9218868437227405312" } : Json),
    ),
    (
      "moonbit-model-stable-v1",
      "pub fn choose(name : String, enabled : Bool, first : Int32, second : Int) -> Int32 { let greeting : String = if enabled { \"Hello, \" + name } else { \"\" }; if greeting == \"Hello, Morphir\" { first } else { second } }",
      [
        { "type": "text", "units": [77, 111, 114, 112, 104, 105, 114] },
        { "type": "bool", "value": true },
        {
          "type": "custom",
          "owner": "morphir/SDK:int#int-32",
          "tag": "morphir/SDK:int#int32",
          "items": [{ "type": "int", "value": "-2147483648" }],
        },
        {
          "type": "custom",
          "owner": "morphir/SDK:int#int-32",
          "tag": "morphir/SDK:int#int32",
          "items": [{ "type": "int", "value": "2147483647" }],
        },
      ],
      (
        {
          "type": "custom",
          "owner": "morphir/SDK:int#int-32",
          "tag": "morphir/SDK:int#int32",
          "items": [{ "type": "int", "value": "-2147483648" }],
        } : Json),
    ),
    (
      "moonbit-model-stable-v1",
      "pub fn choose(a : String, b : String) -> Bool { a < b && a <= b && !(a > b) && !(a >= b) }",
      [{ "type": "text", "units": [98] }, { "type": "text", "units": [97, 97] }],
      ({ "type": "bool", "value": true } : Json),
    ),
  ]
  for (profile, source, arguments, expected) in cases {
    let snapshot = files()
    snapshot["morphir.toml"] = snapshot["morphir.toml"].replace(
      old="language='moonbit'",
      new="language='moonbit'\nprofile='" + profile + "'",
    )
    snapshot["src/Main.mbt"] = source
    let engine = @engine.Engine::new()
    @adapter.register(engine)
    let result = execute(engine, snapshot)
    assert_true(result.successful())
    let unit = @data.Registry::new().decode("ion-binary", {
      unit_id: "Main",
      content: result.artifacts[0].content,
    })
    let suite = @protocol.Suite::from_json({
      "profile": "morphir-invocations-v1",
      "calls": [
        {
          "id": "one",
          "entry": "pricing:app/main#choose",
          "arguments": arguments,
        },
      ],
    })
    for policy in [@execution.Strict, @execution.Permissive] {
      let plan = @execution.plan_scheme(unit, suite, policy~)
      assert_eq(plan.evaluate().map(@protocol.Value::to_json), [expected])
    }
  }
}

///|
test "catalog exposes stable and experimental and retired IDs fail selection" {
  let provider = @adapter.provider()
  assert_eq(provider.languages[0].profiles.map(p => Some(p.id.to_string())), [
    Some("moonbit-model-stable-v1"),
    Some("moonbit-model-experimental-v1"),
  ])
  let engine = @engine.Engine::new()
  @adapter.register(engine)
  for
    retired in [
      "moonbit-model-bool-v1", "moonbit-model-library-v1", "moonbit-model-bool-library-v1",
      "moonbit-model-typed-library-foundation-v1", "moonbit-model-int32-library-v1",
      "moonbit-model-integer-library-v1", "moonbit-model-float-library-v1", "moonbit-model-string-library-v1",
      "moonbit-model-pinned-sdk-library-v1", "moonbit-model-library-v2", "moonbit-model-library-2026-10-17",
      "moonbit-model-library-2026-10-19", "moonbit-model-library-2026-10-19-r2",
      "moonbit-model-library-2026-10-19-r3", "moonbit-model-library-2026-10-19-r4",
    ] {
    let snapshot = files()
    snapshot["morphir.toml"] = snapshot["morphir.toml"].replace(
      old="language='moonbit'",
      new="language='moonbit'\nprofile='" + retired + "'",
    )
    try {
      ignore(plan(engine, snapshot))
      fail("Retired profile must not silently select another compiler")
    } catch {
      @config.Invalid(message) => assert_true(message.contains(retired))
      error => raise error
    }
  }
}

///|
fn string_predicate_snapshot(profile : String) -> Map[String, String] {
  let snapshot = files()
  snapshot["morphir.toml"] = snapshot["morphir.toml"].replace(
    old="language='moonbit'",
    new="language='moonbit'\nprofile='" + profile + "'",
  )
  snapshot["src/Main.mbt"] = "pub fn has(s : String, needle : String) -> Bool { s.contains(needle) }\npub fn starts(s : String, prefix : String) -> Bool { s.has_prefix(prefix) }"
  snapshot
}

///|
test "pinned String predicates reach the engine evaluator with UTF-16 text" {
  let engine = @engine.Engine::new()
  @adapter.register(engine)
  let snapshot = string_predicate_snapshot(@frontend.STABLE_PROFILE)
  let descriptor = plan(engine, snapshot).source_frontends()[0]
  assert_eq(
    descriptor.dependencies["moonbitlang/core/builtin"],
    "0.10.18+6c83a7f62+tree:417988f6e19738a7f683ce19a6cf5aaf52c96965",
  )
  let report = execute(engine, snapshot)
  assert_true(report.successful())
  let unit = @data.Registry::new().decode("ion-binary", {
    unit_id: "Main",
    content: report.artifacts[0].content,
  })
  fn text(value : String) -> Json {
    {
      "type": "text",
      "units": value
      .iter()
      .fold(init=[], fn(units, c) {
        units..append(
          if c.to_int() > 0xFFFF {
            let v = c.to_int() - 0x10000
            [0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF)]
          } else {
            [c.to_int()]
          },
        )
      })
      .map(u => Json::number(u.to_double())),
    }
  }
  let suite = @protocol.Suite::from_json({
    "profile": "morphir-invocations-v1",
    "calls": [
      {
        "id": "emoji",
        "entry": "pricing:app/main#has",
        "arguments": [text("a😀b"), text("😀")],
      },
      {
        "id": "neighbour",
        "entry": "pricing:app/main#has",
        "arguments": [text("😀"), text("😁")],
      },
      {
        "id": "combining",
        "entry": "pricing:app/main#starts",
        "arguments": [text("é"), text("e")],
      },
      {
        "id": "composed",
        "entry": "pricing:app/main#starts",
        "arguments": [text("é"), text("e")],
      },
    ],
  })
  let plan = @execution.plan_scheme(unit, suite)
  assert_eq(plan.evaluate().map(@protocol.Value::to_json), [
    { "type": "bool", "value": true },
    { "type": "bool", "value": false },
    { "type": "bool", "value": true },
    { "type": "bool", "value": false },
  ])
}

///|
test "both channels advertise the promoted String predicates" {
  let provider = @adapter.provider()
  for profile in provider.languages[0].profiles {
    assert_true(
      profile.capabilities.supported.contains(
        "Pinned String is_empty, contains, has_prefix and has_suffix predicates",
      ),
    )
    assert_eq(
      profile.dependencies["moonbitlang/core/builtin"],
      "0.10.18+6c83a7f62+tree:417988f6e19738a7f683ce19a6cf5aaf52c96965",
    )
  }
}
