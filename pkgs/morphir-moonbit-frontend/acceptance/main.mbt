///|
fn finite_run(json_mode~ : Bool = false) -> Json raise {
  let cases = [
    ("and", "active && vip", [false, false, false, true]),
    ("or", "active || vip", [false, true, true, true]),
    ("equal", "active == vip", [true, false, false, true]),
    ("different", "active != vip", [false, true, true, false]),
    ("not", "!active", [true, true, false, false]),
    (
      "conditional",
      "if active { vip } else { !vip }",
      [true, false, false, true],
    ),
    (
      "nested",
      "((active && !vip) || (!active && vip))",
      [false, true, true, false],
    ),
    (
      "equality",
      "(active == vip) != (!active == !vip)",
      [false, false, false, false],
    ),
    ("annotation", "(active : Bool)", [false, false, true, true]),
    ("true", "true", [true, true, true, true]),
    ("false", "false", [false, false, false, false]),
  ]
  let models = []
  for (id, body, expected) in cases {
    let source = "// λ😀 source origin fixture\npub fn decide(active : Bool, vip : Bool) -> Bool { " +
      body +
      " }"
    let output = @frontend.compile_library({
      unit_id: id + ".mbt",
      package_name: "boolean/" + id,
      module_name: "main",
      source,
    })
    let runtime = @scheme.Runtime::new()
    @backend.install(runtime)
    ignore(runtime.eval(@backend.emit_file(output.ir)))
    let observed = []
    for
      (active, vip) in [
        (false, false),
        (false, true),
        (true, false),
        (true, true),
      ] {
      guard @backend.call_entry(runtime, output.entries[0], [
          @scheme.Boolean(active),
          @scheme.Boolean(vip),
        ])
        is Boolean(value) else {
        finite_refuse("Expected Boolean evaluator output", json_mode~)
      }
      observed.push(value)
    }
    assert_eq(observed, expected)
    let generated = @generator.generate({
      unit_id: output.unit_id,
      ir: output.ir,
      metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
      annotations: output.annotations,
      provenance: output.provenance,
    })
    models.push(
      Json::object(
        Map::from_array([
          ("id", Json::string(id)),
          ("source", Json::string(source)),
          ("ir", Json::string(@ir_json.write(output.ir))),
          ("entry", Json::string(output.entries[0].to_canonical())),
          ("module", Json::string(generated.project.module_name)),
          ("function", Json::string(generated.symbols[0].generated_name)),
          ("expected", Json::array(expected.map(Json::boolean))),
          ("scheme", Json::array(observed.map(Json::boolean))),
          (
            "artifacts",
            Json::array(
              generated.artifacts.map(a => {
                let content = match a.content {
                  Text(text) => Json::string(text)
                  Binary(bytes) =>
                    Json::array(
                      bytes
                      .to_array()
                      .map(b => Json::number(b.to_int().to_double())),
                    )
                }
                Json::object(
                  Map::from_array([
                    ("path", Json::string(a.path)),
                    ("content", content),
                  ]),
                )
              }),
            ),
          ),
        ]),
      ),
    )
  }
  Json::object(
    Map::from_array([
      ("profile", Json::string(@frontend.STABLE_PROFILE)),
      ("parserVersion", Json::string(@frontend.PARSER_VERSION)),
      ("models", Json::array(models)),
    ]),
  )
}
