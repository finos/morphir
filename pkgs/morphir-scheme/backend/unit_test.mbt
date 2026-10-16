///|
fn ion_record(fields : Array[(String, @ion.IonValue)]) -> @ion.IonValue {
  @ion.IonValue::new(
    @ion.Struct(fields.map(pair => @ion.Field::new(pair.0, pair.1))),
  )
}

///|
fn symbol_fields(value : @ion.IonValue) -> Map[String, @ion.IonValue] raise {
  guard value.kind() is @ion.Struct(fields) else {
    fail("Expected an Ion record")
  }
  let result = Map([])
  for field in fields {
    result[field.name().text().unwrap()] = field.value()
  }
  result
}

///|
fn sidecar(output : @backend.Output) -> Map[String, @ion.IonValue] raise {
  symbol_fields(@ion_binary.read_binary_value(output.symbols[:]))
}

///|
fn ion_strings(value : @ion.IonValue) -> Array[String] raise {
  guard value.kind() is @ion.List(items) else { fail("Expected an Ion list") }
  let result = []
  for item in items {
    guard item.kind() is @ion.String(text) else { fail("Expected Ion strings") }
    result.push(text)
  }
  result
}

///|
/// Ion values derive Debug but not Eq: a matcher value that uses `IonValue::equals`.
fn ion(expected : @ion.IonValue) -> @expect.Matcher[@ion.IonValue] {
  {
    describe: () => @debug.to_string(expected),
    check: value => {
      if value.equals(expected) {
        None
      } else {
        Some("differs from the expected Ion value")
      }
    },
  }
}

///|
/// Every symbol of the sidecar as (fqname, generated_name, scheme_symbol, public, source_node, generated_node, origins).
fn symbol_rows(
  output : @backend.Output,
) -> Array[(String, String, String, Bool, String, String, Array[String])] raise {
  guard sidecar(output)["symbols"].kind() is @ion.List(symbols) else {
    fail("Expected symbols")
  }
  let rows = []
  for symbol in symbols {
    let f = symbol_fields(symbol)
    guard f["fqname"].kind() is @ion.String(fqname) else { fail("fqname") }
    guard f["generated_name"].kind() is @ion.String(generated) else {
      fail("generated_name")
    }
    guard f["scheme_symbol"].kind() is @ion.String(scheme_symbol) else {
      fail("scheme_symbol")
    }
    guard f["public"].kind() is @ion.Bool(public) else { fail("public") }
    guard f["source_node"].kind() is @ion.String(source_node) else {
      fail("source_node")
    }
    guard f["generated_node"].kind() is @ion.String(generated_node) else {
      fail("generated_node")
    }
    rows.push(
      (
        fqname,
        generated,
        scheme_symbol,
        public,
        source_node,
        generated_node,
        ion_strings(f["origins"]),
      ),
    )
  }
  rows
}

///|
fn value_def(
  access : @ir.Access,
  body : @ir.Value,
) -> @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]] {
  {
    access,
    value: {
      doc: None,
      value: @ir.ValueDefinition::ExpressionBody(
        [],
        @ir.Type::Unit(@ir.TypeAttributes::default()),
        body,
      ),
    },
  }
}

///|
/// `test:main#main` (public) then `test:main#helper` (private).
fn sample_package() -> @ir.PackageDefinition raise {
  {
    modules: Map::from_array([
      (
        @ir.Path::parse("main"),
        {
          access: @ir.Access::Public,
          value: {
            types: Map([]),
            doc: None,
            values: Map::from_array([
              (name("main"), value_def(@ir.Access::Public, int("42"))),
              (name("helper"), value_def(@ir.Access::Private, int("1"))),
            ]),
          },
        },
      ),
    ]),
  }
}

///|
fn sample_unit() -> @backend.Input raise {
  let ir = @ir.IRFile::new(
    @ir.Distribution::Library(
      @ir.Path::parse("test"),
      Map([]),
      sample_package(),
    ),
  )
  {
    unit_id: "Main",
    ir,
    metadata: [
      {
        node_id: "value:test:main#main",
        data: @ion.IonValue::string("origin"),
      },
      {
        node_id: "value:test:main#main/body",
        data: ion_record([("nodes", @ion.IonValue::list([]))]),
      },
    ],
    annotations: [@ion.SymbolToken::new("morphir_pipeline")],
    provenance: [
      ion_record([("frontend", @ion.IonValue::string("test-v1"))]).with_annotation(
        @ion.SymbolToken::new("morphir_test_frontend"),
      ),
    ],
  }
}

///|
test "emit_unit without metadata gives the emit_file text and an empty sidecar" {
  let ir = file(
    @ir.ValueDefinition::ExpressionBody(
      [],
      @ir.Type::Unit(@ir.TypeAttributes::default()),
      int("42"),
    ),
  )
  let output = @backend.emit_unit(@backend.Input::new("Main", ir))
  let stored = @ion_binary.read_binary_value(output.symbols[:])
  let fields = symbol_fields(stored)
  @expect.expect_all(s => {
    s.expect(output.source, label="source").to_equal(@backend.emit_file(ir))
    s
    .expect(stored.annotations().map(a => a.text()), label="annotations")
    .to_equal([Some("morphir_scheme_symbols")])
    s
    .expect(fields, label="sidecar")
    .value_at("profile")
    .to(ion(@ion.IonValue::string(@backend.SYMBOLS_PROFILE)))
    s
    .expect(fields, label="sidecar")
    .value_at("naming_policy")
    .to(ion(@ion.IonValue::string("scheme-canonical-identity-v1")))
    s
    .expect(fields, label="sidecar")
    .value_at("unit_id")
    .to(ion(@ion.IonValue::string("Main")))
    s
    .expect(fields, label="sidecar")
    .value_at("metadata")
    .to(ion(@ion.IonValue::list([])))
    s
    .expect(fields, label="sidecar")
    .value_at("source_provenance")
    .to(ion(@ion.IonValue::list([])))
    s
    .expect(fields, label="sidecar")
    .value_at("source_annotations")
    .to(ion(@ion.IonValue::list([])))
    s.expect(@backend.SYMBOLS_SUFFIX, label="suffix").to_equal(".symbols.10n")
  })
}

///|
test "the sidecar is byte-stable, reads back and keeps the unit's metadata unchanged" {
  let unit = sample_unit()
  let first = @backend.emit_unit(unit)
  let second = @backend.emit_unit(unit)
  let stored = @ion_binary.read_binary_value(first.symbols[:])
  let fields = symbol_fields(stored)
  guard fields["metadata"].kind() is @ion.List(entries) else {
    fail("Expected metadata entries")
  }
  @expect.expect_all(s => {
    s.expect(second.symbols, label="second run").to_equal(first.symbols)
    s
    .expect(@ion_binary.write_binary_value(stored), label="re-encoded")
    .to_equal(first.symbols)
    s
    .expect(fields, label="sidecar")
    .value_at("source_provenance")
    .to(ion(@ion.IonValue::list(unit.provenance)))
    s
    .expect(fields, label="sidecar")
    .value_at("source_annotations")
    .to(ion(@ion.IonValue::list([@ion.IonValue::symbol("morphir_pipeline")])))
    s.expect(entries, label="metadata").to_have_length(unit.metadata.length())
    for pair in entries.zip(unit.metadata) {
      let entry = symbol_fields(pair.0)
      s
      .expect(entry, label=pair.1.node_id)
      .value_at("node_id")
      .to(ion(@ion.IonValue::string(pair.1.node_id)))
      s
      .expect(entry, label=pair.1.node_id)
      .value_at("data")
      .to(ion(pair.1.data))
    }
    s
    .expect(ion_strings(fields["source_nodes"]), label="source_nodes")
    .to_contain_all([
      "unit:Main", "value:test:main#main", "value:test:main#helper",
    ])
  })
}

///|
test "the sidecar lists every define with identity names and access" {
  @expect.expect(symbol_rows(@backend.emit_unit(sample_unit()))).to_contain_exactly([
      (
        "test:main#main",
        "test:main#main",
        "r:test:main#main",
        true,
        "value:test:main#main",
        "scheme:define:test:main#main",
        ["value:test:main#main", "value:test:main#main/body"],
      ),
      (
        "test:main#helper",
        "test:main#helper",
        "r:test:main#helper",
        false,
        "value:test:main#helper",
        "scheme:define:test:main#helper",
        ["value:test:main#helper", "value:test:main#helper/body"],
      ),
    ],
  )
}

///|
test "an application lists its dependency defines first" {
  let ir = @ir.IRFile::new(
    @ir.Distribution::Application(
      @ir.Path::parse("app"),
      Map::from_array([(@ir.Path::parse("test"), sample_package())]),
      sample_package(),
      Map([]),
    ),
  )
  let output = @backend.emit_unit(@backend.Input::new("App", ir))
  @expect.expect_all(s => {
    s.expect(output.source, label="source").to_equal(@backend.emit_file(ir))
    // Owned identities cover libraries only, so an application's symbols list no origins that do not exist.
    s
    .expect(symbol_rows(output).map(row => row.6), label="origins")
    .to_all_satisfy(origins => origins.is_empty())
    s
    .expect(symbol_rows(output).map(row => row.0), label="fqnames")
    .to_contain_exactly([
      "test:main#main", "test:main#helper", "app:main#main", "app:main#helper",
    ])
  })
}

///|
fn origin(
  name : String,
  path~ : String? = None,
  line~ : Int32 = 2,
  column~ : Int32 = 0,
) -> @ion.IonValue {
  let fields = [("name", @ion.IonValue::string(name))]
  if path is Some(p) {
    fields.push(("path", @ion.IonValue::string(p)))
  }
  fields.append([
    ("coordinate_profile", @ion.IonValue::string("moonbit-parser-position-v1")),
    ("start_line", @ion.IonValue::int(line)),
    ("start_column", @ion.IonValue::int(column)),
    ("end_line", @ion.IonValue::int(line)),
    ("end_column", @ion.IonValue::int(column + 8)),
  ])
  ion_record([("declaration", ion_record(fields))])
}

///|
fn unit_with(metadata : Array[@backend.NodeMetadata]) -> @backend.Input raise {
  { ..sample_unit(), metadata, }
}

///|
fn main_hint(data : @ion.IonValue) -> @backend.NodeMetadata {
  { node_id: "value:test:main#main", data, }
}

///|
fn lines(text : String) -> Array[String] {
  text.split("\n").map(StringView::to_owned).collect()
}

///|
fn first_line(
  unit : @backend.Input,
  source_path~ : String? = None,
) -> String raise {
  lines(@backend.emit_unit(unit, source_path~).source)[0]
}

///|
fn declaration(fields : Array[(String, @ion.IonValue)]) -> @ion.IonValue {
  ion_record([("declaration", ion_record(fields))])
}

///|
test "a declaration hint adds a comment above its define and nothing else" {
  let unit = unit_with([main_hint(origin("eligible"))])
  let output = @backend.emit_unit(unit, source_path=Some("src/Main.mbt"))
  let plain = lines(@backend.emit_file(unit.ir))
  let commented = lines(output.source)
  // Comments do not change behaviour.
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  ignore(runtime.eval(output.source))
  let answer = @scheme.value_to_string(
    @backend.call_entry(runtime, @ir.FQName::parse("test:main#main"), []),
  )
  @expect.expect_all(s => {
    s.expect(commented, label="lines").to_have_length(plain.length() + 1)
    s
    .expect(commented, label="lines")
    .first()
    .to_equal(";; eligible (src/Main.mbt:2:0)")
    s
    .expect(commented[1:].to_owned(), label="forms after the comment")
    .to_equal(plain)
    s.expect(answer, label="main()").to_equal("42")
  })
}

///|
test "the comment location comes from the hint, then the source path, then the unit id" {
  let hinted = unit_with([
    main_hint(origin("eligible", path=Some("src/Other.elm"))),
  ])
  let unhinted = unit_with([main_hint(origin("eligible"))])
  @expect.expect_all(s => {
    s
    .expect(
      first_line(hinted, source_path=Some("src/Main.mbt")),
      label="hint path",
    )
    .to_equal(";; eligible (src/Other.elm:2:0)")
    s
    .expect(first_line(unhinted), label="unit id")
    .to_equal(";; eligible (Main:2:0)")
    // A hostile source path from the host falls back to the unit id.
    s
    .expect(
      first_line(unhinted, source_path=Some("src/Main.mbt\n(define x 1)")),
      label="hostile source path",
    )
    .to_equal(";; eligible (Main:2:0)")
  })
}

///|
test "hostile and invalid hints are ignored" {
  let twice = unit_with([main_hint(origin("one")), main_hint(origin("two"))])
  let not_a_record = unit_with([main_hint(@ion.IonValue::string("eligible"))])
  let semicolon = unit_with([main_hint(origin("a;b"))])
  // Hints for nodes that are not defines stay in the sidecar and give no comment.
  let body_only = unit_with([
    {
      node_id: "value:test:main#main/body",
      data: declaration([("name", @ion.IonValue::string("x"))]),
    },
    { node_id: "type:test:main#shape", data: origin("Shape"), },
  ])
  let kept = @backend.emit_unit(body_only)
  guard sidecar(kept)["metadata"].kind() is @ion.List(entries) else {
    fail("Expected metadata")
  }
  @expect.expect_all(s => {
    for
      bad in [
        "eligible\n(define r:evil 1)",
        "eligible\r",
        "eligible\u{2028}",
        "eligible\u{85}",
        "",
        String::make(257, 'a'),
      ] {
      let unit = unit_with([main_hint(origin(bad))])
      s
      .expect(
        @backend.emit_unit(unit).source,
        label="name " + @debug.to_string(bad),
      )
      .to_equal(@backend.emit_file(unit.ir))
    }
    s
    .expect(@backend.emit_unit(twice).source, label="duplicate entries")
    .to_equal(@backend.emit_file(twice.ir))
    s
    .expect(@backend.emit_unit(not_a_record).source, label="not a record")
    .to_equal(@backend.emit_file(not_a_record.ir))
    // A `;` cannot end a line comment, so it stays.
    s
    .expect(first_line(semicolon), label="semicolon")
    .to_equal(";; a;b (Main:2:0)")
    s
    .expect(kept.source, label="body and type entries")
    .to_equal(@backend.emit_file(body_only.ir))
    s.expect(entries, label="sidecar keeps them").to_have_length(2)
  })
}

///|
test "a bad span keeps the path form and a duplicated field drops the hint" {
  let backwards = declaration([
    ("name", @ion.IonValue::string("x")),
    ("start_line", @ion.IonValue::int(3)),
    ("start_column", @ion.IonValue::int(0)),
    ("end_line", @ion.IonValue::int(2)),
    ("end_column", @ion.IonValue::int(0)),
  ])
  let negative = declaration([
    ("name", @ion.IonValue::string("x")),
    ("start_line", @ion.IonValue::int(-1)),
    ("start_column", @ion.IonValue::int(0)),
    ("end_line", @ion.IonValue::int(1)),
    ("end_column", @ion.IonValue::int(0)),
  ])
  let duplicated = unit_with([
    main_hint(
      declaration([
        ("name", @ion.IonValue::string("x")),
        ("name", @ion.IonValue::string("y")),
      ]),
    ),
  ])
  @expect.expect_all(s => {
    s
    .expect(
      first_line(unit_with([main_hint(backwards)])),
      label="backwards span",
    )
    .to_equal(";; x (Main)")
    s
    .expect(
      first_line(unit_with([main_hint(negative)])),
      label="negative coordinate",
    )
    .to_equal(";; x (Main)")
    s
    .expect(
      @backend.emit_unit(duplicated).source,
      label="duplicated name field",
    )
    .to_equal(@backend.emit_file(duplicated.ir))
  })
}

///|
test "an external or native value lists no body origin, because it has no body node" {
  let output_type = @ir.Type::Unit(@ir.TypeAttributes::default())
  let external = @ir.ValueDefinition::ExternalBody(
    [],
    output_type,
    [{ target_platform: "morphir-scheme", external_name: "answer", }],
    None,
  )
  let native = @ir.ValueDefinition::NativeBody([], output_type, {
    hint: @ir.NativeHint::Arithmetic,
    description: None,
  })
  @expect.expect_all(s => {
    for pair in [("external", external), ("native", native)] {
      let output = @backend.emit_unit(@backend.Input::new("Main", file(pair.1)))
      s
      .expect(symbol_rows(output).map(row => row.6), label=pair.0)
      .to_contain_exactly([["value:test:main#main"]])
    }
  })
}
