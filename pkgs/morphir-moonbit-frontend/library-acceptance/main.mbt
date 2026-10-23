///|
fn original_name(
  output : @frontend.LibraryOutput,
  node : String,
  json_mode~ : Bool,
) -> String raise {
  let metadata = output.metadata.filter(m => m.node_id == node)[0]
  guard metadata.data.kind() is @ion.Struct(fields) else {
    finite_refuse("Expected declaration", json_mode~)
  }
  guard fields[0].value().kind() is @ion.Struct(origin) else {
    finite_refuse("Expected origin", json_mode~)
  }
  guard origin[0].value().kind() is @ion.String(name) else {
    finite_refuse("Expected original name", json_mode~)
  }
  name
}

///|
fn finite_run(json_mode~ : Bool = false) -> Json raise {
  let two = [[false, false], [false, true], [true, false], [true, true]]
  let three = []
  for a in [false, true] {
    for b in [false, true] {
      for c in [false, true] {
        three.push([a, b, c])
      }
    }
  }
  let cases : Array[
    (String, String, Array[(String, Array[Array[Bool]], Array[Bool])]),
  ] = [
    (
      "forward",
      "pub fn decide(a : Bool, b : Bool, c : Bool) -> Bool { let allowed : Bool = ready(a, b); allowed && !c }\npub fn default_ready() -> Bool { ready(true, false) }\nfn ready(a : Bool, b : Bool) -> Bool { a || b }",
      [
        ("decide", three, [false, false, true, false, true, false, true, false]),
        ("default_ready", [[]], [true]),
      ],
    ),
    (
      "shadow",
      "pub fn f(x : Bool) -> Bool { let x = !x; let y : Bool = x; let x = !x; if y { let x = !x; x } else { x } }",
      [("f", [[false], [true]], [true, true])],
    ),
    (
      "diamond",
      "pub fn either(a : Bool, b : Bool) -> Bool { left(a) || right(b) }\npub fn unequal(a : Bool, b : Bool) -> Bool { left(a) != right(b) }\nfn left(x : Bool) -> Bool { leaf(x) }\nfn right(x : Bool) -> Bool { leaf(x) }\nfn leaf(x : Bool) -> Bool { x }\nfn unused(x : Bool) -> Bool { !x }",
      [
        ("either", two, [false, true, true, true]),
        ("unequal", two, [false, true, true, false]),
      ],
    ),
    (
      "zero",
      "pub fn equal() -> Bool { yes() == yes() }\npub fn no() -> Bool { !yes() }\npub fn yes() -> Bool { true }",
      [("equal", [[]], [true]), ("no", [[]], [false]), ("yes", [[]], [true])],
    ),
    (
      "private",
      "fn hidden() -> Bool { other() }\nfn other() -> Bool { true }",
      [],
    ),
    (
      "operators",
      "pub fn both(a : Bool, b : Bool) -> Bool { identity(a) && identity(b) }\npub fn either(a : Bool, b : Bool) -> Bool { identity(a) || identity(b) }\npub fn equal(a : Bool, b : Bool) -> Bool { identity(a) == identity(b) }\npub fn unequal(a : Bool, b : Bool) -> Bool { identity(a) != identity(b) }\npub fn choice(a : Bool, b : Bool) -> Bool { if identity(a) { identity(b) } else { !identity(b) } }\nfn identity(x : Bool) -> Bool { x }",
      [
        ("both", two, [false, false, false, true]),
        ("either", two, [false, true, true, true]),
        ("equal", two, [true, false, false, true]),
        ("unequal", two, [false, true, true, false]),
        ("choice", two, [true, false, false, true]),
      ],
    ),
  ]
  let models = []
  for (id, body, fixtures) in cases {
    let source = "// λ😀 original library origin fixture\n" + body
    let output = @frontend.compile_library({
      unit_id: id + ".mbt",
      package_name: "boolean/library/" + id,
      module_name: "main",
      source,
    })
    let generated = @generator.generate({
      unit_id: output.unit_id,
      ir: output.ir,
      metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
      annotations: output.annotations,
      provenance: output.provenance,
    })
    let runtime = @scheme.Runtime::new()
    @backend.install(runtime)
    ignore(runtime.eval(@backend.emit_file(output.ir)))
    let entries = []
    assert_eq(output.entries.length(), fixtures.length())
    for entry in output.entries {
      let symbol = generated.symbols.filter(s => {
          s.fqname == entry.to_canonical()
        })[0]
      let name = original_name(output, symbol.source_node, json_mode~)
      let (_, arguments, expected) = fixtures.filter(f => f.0 == name)[0]
      let observed = arguments.map(args => {
        guard @backend.call_entry(
            runtime,
            entry,
            args.map(arg => @scheme.Value::Boolean(arg)),
          )
          is Boolean(value) else {
          finite_refuse("Expected Bool", json_mode~)
        }
        value
      })
      assert_eq(observed, expected)
      entries.push(
        Json::object(
          Map::from_array([
            ("entry", Json::string(entry.to_canonical())),
            ("original", Json::string(name)),
            ("function", Json::string(symbol.generated_name)),
            (
              "arguments",
              Json::array(
                arguments.map(args => Json::array(args.map(Json::boolean))),
              ),
            ),
            ("expected", Json::array(expected.map(Json::boolean))),
            ("scheme", Json::array(observed.map(Json::boolean))),
          ]),
        ),
      )
    }
    let private_symbols = generated.symbols.filter(s => !s.public)
    models.push(
      Json::object(
        Map::from_array([
          ("id", Json::string(id)),
          ("source", Json::string(source)),
          ("ir", Json::string(@ir_json.write(output.ir))),
          ("module", Json::string(generated.project.module_name)),
          ("entries", Json::array(entries)),
          (
            "private",
            Json::array(
              private_symbols.map(s => {
                Json::object(
                  Map::from_array([
                    (
                      "original",
                      Json::string(
                        original_name(output, s.source_node, json_mode~),
                      ),
                    ),
                    ("function", Json::string(s.generated_name)),
                  ]),
                )
              }),
            ),
          ),
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
      ("language", Json::string("moonbit")),
      ("profile", Json::string(@frontend.STABLE_PROFILE)),
      ("parserVersion", Json::string(@frontend.PARSER_VERSION)),
      ("models", Json::array(models)),
    ]),
  )
}
