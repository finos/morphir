///|
fn conceptual_field(value : @ion.IonValue, key : String) -> @ion.IonValue {
  if value.kind() is Struct(fs) {
    for f in fs {
      if f.name().text() == Some(key) {
        return f.value()
      }
    }
  }
  abort("Missing fixture field " + key)
}

///|
fn conceptual_set(
  value : @ion.IonValue,
  key : String,
  replacement : @ion.IonValue,
) -> @ion.IonValue {
  guard value.kind() is Struct(fs) else { abort("Fixture struct") }
  let fields = fs.filter(f => f.name().text() != Some(key))
  fields.push(@ion.Field::new(key, replacement))
  @ion.IonValue::from_fields(fields)
}

///|
fn conceptual_parse(value : String) -> @ion.IonValue raise {
  @ion_text.read_ion(value[:])
}

///|
fn conceptual_unit(
  id : String,
  ir : String,
  graph : String,
) -> @data.IRUnit raise {
  let unit = @data.Registry::new().decode("morphir-json", {
    unit_id: id,
    content: Text(ir),
  })
  unit.with_conceptual_graph(@model.Graph::decode(conceptual_parse(graph)))
}

///|
test "M1 0001 0003 M2 full fixed graphs survive actual Ion text and binary carriers" {
  let registry = @data.Registry::new()
  for
    (id, graph, ir) in [
      (
        "prose", @conceptual_fixtures.prose_only, @conceptual_fixtures.prose_only_ir,
      ),
      ("mixed", @conceptual_fixtures.mixed, @conceptual_fixtures.mixed_ir),
      (
        "traits", @conceptual_fixtures.traits, @conceptual_fixtures.prose_only_ir,
      ),
    ] {
    let original = conceptual_unit(id, ir, graph)
    let unit = @data.IRUnit::{
      ..original,
      annotations: [
        @ion.SymbolToken::new("before"),
        @ion.SymbolToken::new("morphir_pipeline"),
        @ion.SymbolToken::new("after"),
      ],
      provenance: [
        conceptual_parse("author::{name: \"fixture\", statement: null.string}"),
      ],
      metadata: [
        ..original.metadata,
        {
          node_id: "unit:" + id + "/ir/formatVersion",
          data: conceptual_parse("sidecar::{revision:9007199254740993}"),
        },
      ],
    }
    unit.validate()
    for codec in ["ion-text", "ion-binary"] {
      let content = registry.encode(codec, unit)
      let restored = registry.decode(codec, { unit_id: id, content, })
      restored.validate()
      let graph = restored.conceptual_graph().unwrap()
      assert_true(
        graph.to_ion().equals(original.conceptual_graph().unwrap().to_ion()),
      )
      assert_eq(restored.distribution, original.distribution)
      assert_eq(restored.metadata[0].node_id, "unit:" + id)
      assert_true(restored.metadata[1].data.equals(unit.metadata[1].data))
      assert_true(restored.provenance[0].equals(unit.provenance[0]))
      assert_eq(restored.annotations.map(t => t.text()), [
        Some("before"),
        Some("morphir_pipeline"),
        Some("after"),
      ])
      assert_eq(
        graph.identity().revision.value(),
        if id == "mixed" {
          "model-2"
        } else {
          "model-1"
        },
      )
      if id == "prose" {
        assert_eq(
          graph.sources()[0].fragments()[0].text,
          "Track what borrowers still owe.\n\n  Retain the loan identity.\n",
        )
        assert_eq(graph.entities().length(), 4)
      }
    }
  }
}

///|
test "M1 0010 rich opaque observations do not reduce to JSON" {
  let registry = @data.Registry::new()
  let root = conceptual_set(
    conceptual_parse(@conceptual_fixtures.prose_only),
    "descriptive",
    conceptual_parse(@conceptual_fixtures.model_unknown),
  )
  let original = registry
    .decode("morphir-json", {
      unit_id: "prose",
      content: Text(@conceptual_fixtures.prose_only_ir),
    })
    .with_conceptual_graph(@model.Graph::decode(root))
  for codec in ["ion-text", "ion-binary"] {
    let restored = registry.open_checkpoint(
      codec,
      registry.encode(codec, original),
    )
    let unknown = restored
      .conceptual_graph()
      .unwrap()
      .record()
      .field("descriptive")
      .unwrap()
    assert_eq(unknown.annotations().map(a => a.text()), [
      Some("future_note"),
      Some("source_wording"),
    ])
    assert_eq(
      @ion_text.write_ion(conceptual_field(unknown, "preciseCount")),
      "9007199254740993",
    )
    assert_eq(
      @ion_text.write_ion(conceptual_field(unknown, "amount")),
      "123.4500",
    )
    assert_eq(
      @ion_text.write_ion(conceptual_field(unknown, "vocabulary")),
      "pending",
    )
    assert_eq(
      @ion_text.write_ion(conceptual_field(unknown, "typedNull")),
      "null.string",
    )
    assert_eq(
      conceptual_field(unknown, "facts").annotations().map(a => a.text()),
      [Some("future_vocabulary")],
    )
  }
}

///|
test "M1 0019 occupied owner refuses composition without overwriting original data" {
  let registry = @data.Registry::new()
  let original = registry.decode("morphir-json", {
    unit_id: "prose",
    content: Text(@conceptual_fixtures.prose_only_ir),
  })
  let old = conceptual_parse("{prior:\"Keep this payload.\"}")
  let unit = @data.IRUnit::{
    ..original,
    metadata: [{ node_id: "unit:prose", data: old, }],
  }
  assert_eq(
    diagnostic(fn() raise {
      ignore(
        unit.with_conceptual_graph(
          @model.Graph::decode(
            conceptual_parse(@conceptual_fixtures.prose_only),
          ),
        ),
      )
    }),
    "conceptual.metadata_owner_conflict",
  )
  assert_true(
    unit.metadata[0].data.equals(
      conceptual_parse("{prior:\"Keep this payload.\"}"),
    ),
  )
  let duplicate = @data.IRUnit::{
    ..unit,
    metadata: [..unit.metadata, ..unit.metadata],
  }
  assert_eq(
    diagnostic(fn() raise { ignore(duplicate.conceptual_graph()) }),
    "conceptual.metadata_owner_conflict",
  )
}

///|
test "M1 0012 M2 0025 bare IR refuses graph loss while old profiles still work" {
  let registry = @data.Registry::new()
  for graph in [@conceptual_fixtures.prose_only, @conceptual_fixtures.traits] {
    let unit = conceptual_unit("old", @conceptual_fixtures.prose_only_ir, graph)
    assert_eq(
      diagnostic(fn() raise { ignore(registry.encode("morphir-json", unit)) }),
      "data.lossy_conversion",
    )
  }
  let old = registry.decode("morphir-json", {
    unit_id: "old",
    content: Text(@conceptual_fixtures.prose_only_ir),
  })
  assert_true(old.conceptual_graph() is None)
  for codec in ["morphir-json", "ion-text", "ion-binary"] {
    let restored = registry.decode(codec, {
      unit_id: "old",
      content: registry.encode(codec, old),
    })
    assert_eq(restored.distribution, old.distribution)
    assert_true(restored.conceptual_graph() is None)
  }
}

///|
test "M1 0021 public signature projection preserves graph and valid carrier sidecars" {
  let registry = @data.Registry::new()
  let original = conceptual_unit(
    "mixed", @conceptual_fixtures.identity_implementation_ir, @conceptual_fixtures.mixed,
  )
  let unit = @data.IRUnit::{
    ..original,
    provenance: [conceptual_parse("projection_source::\"authored\"")],
    metadata: [
      ..original.metadata,
      {
        node_id: "unit:mixed/ir/formatVersion",
        data: conceptual_parse("{note: \"keep\"}"),
      },
    ],
  }
  let projected = unit.conceptual_specification()
  let expected = registry.decode("morphir-json", {
    unit_id: "mixed",
    content: Text(@conceptual_fixtures.mixed_ir),
  })
  assert_eq(projected.distribution, expected.distribution)
  assert_true(
    projected
    .conceptual_graph()
    .unwrap()
    .to_ion()
    .equals(conceptual_parse(@conceptual_fixtures.mixed)),
  )
  assert_true(projected.metadata[1].data.equals(unit.metadata[1].data))
  assert_true(projected.provenance[0].equals(unit.provenance[0]))
  for codec in ["ion-text", "ion-binary"] {
    let restored = registry.open_checkpoint(
      codec,
      registry.encode(codec, projected),
    )
    assert_eq(restored.distribution, expected.distribution)
    assert_true(
      restored
      .conceptual_graph()
      .unwrap()
      .to_ion()
      .equals(conceptual_parse(@conceptual_fixtures.mixed)),
    )
  }
  let body = @data.IRUnit::{
    ..original,
    metadata: [
      ..original.metadata,
      {
        node_id: "value:example/model:api#identity/body",
        data: conceptual_parse("{note:\"must survive\"}"),
      },
    ],
  }
  body.validate()
  assert_eq(
    diagnostic(fn() raise { ignore(body.conceptual_specification()) }),
    "data.lossy_conversion",
  )
  assert_eq(body.metadata.length(), 2)
}

///|
test "M2 0024 and 0047 preserve unknown rich payloads and application extensions" {
  let registry = @data.Registry::new()
  let root = conceptual_parse(@conceptual_fixtures.traits)
  let traits = conceptual_field(root, "traits")
  guard conceptual_field(traits, "applications").kind() is List(apps) else {
    abort("fixture")
  }
  let definition = conceptual_parse(
    "{state:\"unresolved\",locator:\"urn:example:future-trait\",expectedKind:\"traitDefinition\",reason:\"The declaration was not supplied.\"}",
  )
  let app = conceptual_set(
    conceptual_set(apps[0], "definition", definition),
    "payload",
    conceptual_parse(@conceptual_fixtures.traits_unknown),
  )
  apps[0] = conceptual_set(
    app,
    "futureNote",
    conceptual_parse(
      "{language:\"example\",text:\"Keep  two spaces.\\n\",duplicates:{x:1,x:2}}",
    ),
  )
  let original = registry
    .decode("morphir-json", {
      unit_id: "traits",
      content: Text(@conceptual_fixtures.prose_only_ir),
    })
    .with_conceptual_graph(@model.Graph::decode(root))
  for codec in ["ion-text", "ion-binary"] {
    let restored = registry
      .open_checkpoint(codec, registry.encode(codec, original))
      .conceptual_graph()
      .unwrap()
    let app = restored.trait_applications()[0]
    assert_true(app.definition() is Unresolved(_, _, _))
    assert_eq(app.payload().annotations().map(a => a.text()), [
      Some("future_trait"),
    ])
    assert_eq(
      @ion_text.write_ion(conceptual_field(app.payload(), "preciseCount")),
      "9007199254740993",
    )
    assert_eq(
      @ion_text.write_ion(conceptual_field(app.payload(), "amount")),
      "123.4500",
    )
    assert_eq(
      @ion_text.write_ion(conceptual_field(app.payload(), "vocabulary")),
      "pending",
    )
    assert_eq(
      @ion_text.write_ion(conceptual_field(app.payload(), "typedNull")),
      "null.string",
    )
    let note = app.record().field("futureNote").unwrap()
    assert_true(
      conceptual_field(note, "text").equals(
        @ion.IonValue::string("Keep  two spaces.\n"),
      ),
    )
    guard conceptual_field(note, "duplicates").kind() is Struct(fields) else {
      abort("fixture")
    }
    assert_eq(fields.length(), 2)
    assert_true(restored.to_ion().equals(root))
  }
}

///|
test "competing applications preserve provenance and required semantics without selecting a value" {
  let registry = @data.Registry::new()
  let root = conceptual_parse(@conceptual_fixtures.traits)
  let traits = conceptual_field(root, "traits")
  guard conceptual_field(traits, "applications").kind() is List(apps) else {
    abort("fixture")
  }
  let definition = conceptual_parse(
    "{state:\"resolved\",modelId:\"urn:example:trait-model\",modelRevision:\"model-1\",entityId:\"urn:example:trait:encoding\",entityRevision:\"d1\"}",
  )
  let interpretation = conceptual_parse(
    "{kind:\"semantic\",profiles:[\"urn:example:encoding-rules/0.1.0-draft.1\"]}",
  )
  apps[0] = conceptual_set(
    conceptual_set(apps[0], "definition", definition),
    "interpretation",
    interpretation,
  )
  let provenance = conceptual_set(
    conceptual_set(
      conceptual_field(apps[0], "provenance"),
      "origin",
      @ion.IonValue::string("imported"),
    ),
    "foreignId",
    @ion.IonValue::string("urn:foreign:alternative"),
  )
  let alternative = conceptual_set(
    conceptual_set(
      conceptual_set(apps[0], "id", @ion.IonValue::string("urn:alternative")),
      "payload",
      @ion.IonValue::typed_null(@ion.String),
    ),
    "provenance",
    provenance,
  )
  apps.push(alternative)
  let root = conceptual_set(
    root,
    "requiredSemantics",
    conceptual_parse(
      "[\"morphir-traits/0.1.0-draft.1\",\"urn:example:encoding-rules/0.1.0-draft.1\"]",
    ),
  )
  let root = conceptual_set(
    root,
    "projectionGaps",
    conceptual_parse(
      "[{entityId:\"urn:example:type:quantity\",reason:\"Native union is not projected.\",requiredCapability:\"urn:union/1\"}]",
    ),
  )
  let original = registry
    .decode("morphir-json", {
      unit_id: "traits",
      content: Text(@conceptual_fixtures.prose_only_ir),
    })
    .with_conceptual_graph(@model.Graph::decode(root))
  for codec in ["ion-text", "ion-binary"] {
    let unit = registry.open_checkpoint(codec, registry.encode(codec, original))
    let graph = unit.conceptual_graph().unwrap()
    assert_eq(graph.trait_applications().length(), 2)
    assert_true(
      graph
      .inspect()
      .diagnostics()
      .any(d => {
        d.code == "traits.application_conflict" &&
        d.path == "/traits/applications/1" &&
        d.related_path == Some("/traits/applications/0")
      }),
    )
    assert_true(graph.trait_applications()[1].payload().is_null())
    assert_true(
      graph.trait_applications()[1]
      .provenance()
      .field("foreignId")
      .unwrap()
      .equals(@ion.IonValue::string("urn:foreign:alternative")),
    )
    assert_true(
      graph
      .inspect()
      .diagnostics()
      .any(d => {
        d.code == "conceptual.projection_gap" && d.path == "/projectionGaps/0"
      }),
    )
    let refused = try {
      graph.require_interpretation(ValidateTraits)
      false
    } catch {
      @model.Invalid(_) => true
    }
    assert_true(refused)
    assert_eq(
      diagnostic(fn() raise { ignore(registry.encode("morphir-json", unit)) }),
      "data.lossy_conversion",
    )
    assert_true(graph.to_ion().equals(root))
  }
}

///|
test "public type projection hides private constructors and excludes private declarations" {
  let library =
    #|{"formatVersion":4,"distribution":{"Library":{"packageName":"example/model","dependencies":{},"def":{"modules":{"api":{"Public":{"types":{
    #|"label":{"Public":{"TypeAliasDefinition":{"typeParams":[],"typeExp":"morphir/SDK:string#string"}}},
    #|"secret":{"Public":{"CustomTypeDefinition":{"typeParams":[],"access":"Private","constructors":{"secret":[]}}}},
    #|"hidden":{"Private":{"TypeAliasDefinition":{"typeParams":[],"typeExp":"morphir/SDK:basics#int"}}}
    #|},"values":{}}}}}}}}
  let expected = "{\"formatVersion\":4,\"distribution\":{\"Specs\":{\"packageName\":\"example/model\",\"dependencies\":{},\"spec\":{\"modules\":{\"api\":{\"types\":{\"label\":{\"TypeAliasSpecification\":{\"typeParams\":[],\"typeExp\":\"morphir/SDK:string#string\"}},\"secret\":{\"OpaqueTypeSpecification\":{\"typeParams\":[]}}},\"values\":{}}}}}}}"
  let unit = conceptual_unit("mixed", library, @conceptual_fixtures.mixed)
  let oracle = @data.Registry::new().decode("morphir-json", {
    unit_id: "mixed",
    content: Text(expected),
  })
  assert_eq(unit.conceptual_specification().distribution, oracle.distribution)
  assert_true(
    unit
    .conceptual_specification()
    .conceptual_graph()
    .unwrap()
    .to_ion()
    .equals(conceptual_parse(@conceptual_fixtures.mixed)),
  )
}
