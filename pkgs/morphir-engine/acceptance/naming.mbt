///|
fn content_json(content : @data.Content) -> Json {
  match content {
    Text(text) => Json::string(text)
    Binary(bytes) =>
      Json::array(
        bytes.to_array().map(b => Json::number(b.to_int().to_double())),
      )
  }
}

///|
fn generated_json(output : @generator.Output) -> Json raise {
  let manifest = output.artifacts.filter(a => a.path.has_suffix("symbols.10n"))[0]
  guard manifest.content is Binary(bytes) else {
    abort("Expected Ion manifest")
  }
  Json::object(
    Map::from_array([
      ("module", Json::string(output.project.module_name)),
      (
        "manifest",
        Json::string(@ion_text.write_ion(@ion_binary.read_binary(bytes)[0])),
      ),
      (
        "artifacts",
        Json::array(
          output.artifacts.map(a => {
            Json::object(
              Map::from_array([
                ("path", Json::string(a.path)),
                (
                  "content",
                  match a.content {
                    Text(text) => Json::string(text)
                    Binary(bytes) =>
                      Json::array(
                        bytes
                        .to_array()
                        .map(b => Json::number(b.to_int().to_double())),
                      )
                  },
                ),
              ]),
            )
          }),
        ),
      ),
    ]),
  )
}

///|
fn input(unit : @data.IRUnit) -> @generator.Input {
  {
    unit_id: unit.id,
    ir: unit.distribution,
    metadata: unit.metadata.map(m => { node_id: m.node_id, data: m.data, }),
    annotations: unit.annotations,
    provenance: unit.provenance,
  }
}

///|
fn checkpoints(unit : @data.IRUnit) -> Json raise {
  let registry = @data.Registry::new()
  Json::object(
    Map::from_array([
      ("text", content_json(registry.encode("ion-text", unit))),
      ("binary", content_json(registry.encode("ion-binary", unit))),
    ]),
  )
}

///|
/// Expectations below are authored independently of normalization and allocation.
/// The installed gate checks them against source, Scheme and compiler consumers.
fn naming_fixtures() -> Json raise {
  let cases : Array[
    (String, String, Array[(String, String, Array[Array[Bool]], Array[Bool])]),
  ] = [
    (
      "collision",
      "pub fn is_ready() -> Bool { true }\npub fn isReady() -> Bool { false }\npub fn is_ready_source_69735265() -> Bool { true }\npub fn is_ready_renamed_1() -> Bool { false }\npub fn decide() -> Bool { is_ready() != isReady() }",
      [
        ("is_ready", "is-ready", [[]], [true]),
        ("isReady", "is-ready-source-6973526561", [[]], [false]),
        ("is_ready_source_69735265", "is-ready-source-69735265", [[]], [true]),
        ("is_ready_renamed_1", "is-ready-renamed-1", [[]], [false]),
        ("decide", "decide", [[]], [true]),
      ],
    ),
    (
      "initialisms",
      "pub fn readHTTP() -> Bool { true }\npub fn readHttp() -> Bool { false }\npub fn isREADY() -> Bool { true }",
      [
        ("readHTTP", "read-HTTP", [[]], [true]),
        ("readHttp", "read-http", [[]], [false]),
        ("isREADY", "is-READY", [[]], [true]),
      ],
    ),
    (
      "capture",
      "pub fn f(ready : Bool, ready_shadow_1 : Bool, ready_equality_left_1 : Bool) -> Bool { let ready = !ready; let ready = !ready; (ready == ready_shadow_1) != ready_equality_left_1 }",
      [
        (
          "f",
          "f",
          [
            [false, false, false],
            [false, false, true],
            [false, true, false],
            [false, true, true],
            [true, false, false],
            [true, false, true],
            [true, true, false],
            [true, true, true],
          ],
          [true, false, false, true, false, true, true, false],
        ),
      ],
    ),
    (
      "parameters",
      "pub fn f(is_ready : Bool, isReady : Bool) -> Bool { is_ready != isReady }",
      [
        (
          "f",
          "f",
          [[false, false], [false, true], [true, false], [true, true]],
          [false, true, true, false],
        ),
      ],
    ),
  ]
  let models = []
  for (id, source, entries) in cases {
    let output = @frontend.compile_library({
      unit_id: "Main",
      package_name: "naming-" + id,
      module_name: "app/main",
      source,
    })
    let unit : @data.IRUnit = {
      id: output.unit_id,
      distribution: output.ir,
      metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
      annotations: output.annotations,
      provenance: output.provenance,
    }
    let generated = @generator.generate(input(unit))
    for (original, semantic, _, _) in entries {
      let fqname = "naming-" + id + ":app/main#" + semantic
      assert_true(output.entries.any(e => e.to_canonical() == fqname))
      assert_eq(
        generated.symbols.filter(s => s.fqname == fqname)[0].generated_name,
        original,
      )
    }
    // Preserve opaque Ion values on an existing declaration without hiding origins.
    let metadata = unit.metadata.copy()
    let entry = metadata[0]
    guard entry.data.kind() is Struct(fields) else {
      abort("Expected origin record")
    }
    let payload = @ion_text.read_ion(
      "vendor_payload::{symbol:opaque,typed:null.int,bytes:{{AQID}},large:9007199254740993}",
    )
    metadata[0] = {
      node_id: entry.node_id,
      data: @ion.Ion(
        @ion.IonValueKind::Struct(
          fields + [@ion.field("vendor_payload", payload)],
        ),
      ).with_annotations(entry.data.annotations()),
    }
    let enriched = { ..unit, metadata, }
    models.push(
      Json::object(
        Map::from_array([
          ("id", Json::string(id)),
          ("source", Json::string(source)),
          ("checkpoints", checkpoints(unit)),
          ("opaqueCheckpoints", checkpoints(enriched)),
          ("generated", generated_json(generated)),
          (
            "opaqueGenerated",
            generated_json(@generator.generate(input(enriched))),
          ),
          (
            "legacyGenerated",
            generated_json(
              @generator.generate(input(unit), naming=@generator.LegacyHex),
            ),
          ),
          (
            "entries",
            Json::array(
              entries.map(e => {
                Json::object(
                  Map::from_array([
                    ("original", Json::string(e.0)),
                    ("semantic", Json::string(e.1)),
                    (
                      "arguments",
                      Json::array(
                        e.2.map(args => Json::array(args.map(Json::boolean))),
                      ),
                    ),
                    ("expected", Json::array(e.3.map(Json::boolean))),
                  ]),
                )
              }),
            ),
          ),
        ]),
      ),
    )
  }
  let requested = @data.IRUnit::new("Main", @metadata_fixtures.input(), metadata=[
    {
      node_id: "value:example:main#ready",
      data: @metadata_fixtures.adapter(
        "[" + @metadata_fixtures.row("ready", backend="chosen") + "]",
      ),
    },
  ])
  let registry = @data.Registry::new()
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  ignore(runtime.eval(@backend.emit_file(requested.distribution)))
  for (name, expected) in [("ready", true), ("wanted", false), ("copy", true)] {
    guard @backend.call_entry(
        runtime,
        @ir.FQName::parse("example:main#" + name),
        [],
      )
      is Boolean(actual) else {
      abort("Expected Bool")
    }
    assert_eq(actual, expected)
  }
  let requests = []
  for format in ["ion-text", "ion-binary"] {
    let encoded = registry.encode(format, requested)
    let restored = registry.decode(format, {
      unit_id: "Main",
      content: encoded,
    })
    let generated = @generator.generate(
      input(restored),
      metadata_capabilities=@metadata_fixtures.capabilities(),
    )
    assert_eq(
      generated.symbols.filter(s => s.fqname == "example:main#ready")[0].generated_name,
      "chosen",
    )
    assert_eq(
      generated.symbols.filter(s => s.fqname == "example:main#wanted")[0].generated_name,
      "wanted",
    )
    requests.push(
      Json::object(
        Map::from_array([
          ("format", Json::string(format)),
          ("checkpoint", content_json(encoded)),
          ("generated", generated_json(generated)),
          (
            "legacyGenerated",
            generated_json(
              @generator.generate(
                input(restored),
                naming=@generator.LegacyHex,
                metadata_capabilities=@metadata_fixtures.capabilities(),
              ),
            ),
          ),
        ]),
      ),
    )
  }
  Json::object(
    Map::from_array([
      ("frontendPolicy", Json::string(@frontend.NAMING_POLICY)),
      ("backendPolicy", Json::string(@generator.NAMING_POLICY)),
      ("models", Json::array(models)),
      ("requests", Json::array(requests)),
      (
        "provider",
        Json::string(
          "simulated authenticated host; not a signed provider release",
        ),
      ),
    ]),
  )
}
