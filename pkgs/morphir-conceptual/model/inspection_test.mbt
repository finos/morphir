///|
fn get(value : @ion.IonValue, key : String) -> @ion.IonValue {
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
fn set(
  value : @ion.IonValue,
  key : String,
  replacement : @ion.IonValue,
) -> @ion.IonValue {
  guard value.kind() is Struct(fs) else { abort("Not a fixture struct") }
  let output = fs.filter(f => f.name().text() != Some(key))
  output.push(@ion.Field::new(key, replacement))
  @ion.IonValue::from_fields(output).with_annotations(value.annotations())
}

///|
fn list(value : @ion.IonValue) -> Array[@ion.IonValue] {
  guard value.kind() is List(xs) else { abort("Not a fixture list") }
  xs
}

///|
fn parsed(text : String) -> @ion.IonValue raise {
  @ion_text.read_ion(text[:])
}

///|
fn failure(action : () -> Unit raise) -> (String, String) {
  try {
    action()
    ("accepted", "")
  } catch {
    @model.Invalid(d) => (d.code, d.path)
    error => ("unexpected", error.to_string())
  }
}

///|
fn has(result : @model.Inspection, code : String, path : String) -> Bool {
  result.diagnostics().any(d => d.code == code && d.path == path)
}

///|
test "M1 0002 independent gaps expose authored knowledge without inventing evidence" {
  let result = graph(@fixtures.prose_only).inspect()
  assert_false(result is InvalidGraph(_))
  for
    (code, path) in [
      ("conceptual.source_unpinned", "/sources/1/document"),
      ("conceptual.unresolved_reference", "/relationships/2/target"),
      ("conceptual.missing_formalization", "/entities/1"),
      ("conceptual.missing_examples", "/entities/1"),
      ("conceptual.open_domain_aspect", "/entities/2/elaboration/aspects/0"),
    ] {
    assert_true(has(result, code, path))
  }
}

///|
test "M1 0004 five concern states and original recovery diagnostics remain independent" {
  let model = graph(@fixtures.independent_concerns)
  let entity = model.entity("urn:example:declaration:draft").unwrap()
  for
    (name, state) in [
      ("elaboration", "open"),
      ("definition", "authoredPartial"),
      ("recovery", "recovering"),
      ("review", "pending"),
      ("implementation", "unbound"),
    ] {
    assert_true(
      entity
      .concern(name)
      .unwrap()
      .field("state")
      .unwrap()
      .equals(@ion.IonValue::string(state)),
    )
  }
  let diagnostics = entity
    .concern("recovery")
    .unwrap()
    .field("diagnostics")
    .unwrap()
  assert_true(
    get(list(diagnostics)[0], "code").equals(
      @ion.IonValue::string("fixture.syntax.expected-expression"),
    ),
  )
}

///|
test "duplicate record members fail while opaque descriptive multiplicity survives" {
  let original = parsed(@fixtures.prose_only)
  guard original.kind() is Struct(fs) else { abort("fixture") }
  fs.push(@ion.Field::new("model", get(original, "model")))
  assert_eq(
    failure(fn() raise { ignore(@model.Graph::decode(original)) }),
    ("conceptual.duplicate_member", "/model"),
  )
  let opaque_data = set(
    parsed(@fixtures.prose_only),
    "descriptive",
    parsed("{future: tag::{same:1,same:2}}"),
  )
  assert_true(@model.Graph::decode(opaque_data).to_ion().equals(opaque_data))
}

///|
test "M1 0006 cross-list IDs and changed-revision duplicates are rejected" {
  let original = parsed(@fixtures.prose_only)
  let entities = list(get(original, "entities"))
  entities.push(set(entities[2], "revision", @ion.IonValue::string("another")))
  assert_eq(
    failure(fn() raise { ignore(@model.Graph::decode(original)) }),
    ("conceptual.duplicate_identity", "/entities/4/id"),
  )
}

///|
test "M1 0007 0008 0009 invalid relationship signatures and exact reference scopes" {
  for
    (key, replacement, code, path) in [
      (
        "entityId", "urn:missing", "conceptual.missing_resolved_target", "/relationships/0/target",
      ),
      (
        "modelRevision", "model-other", "conceptual.reference_revision", "/relationships/0/target",
      ),
      (
        "entityRevision", "wrong", "conceptual.reference_revision", "/relationships/0/target",
      ),
    ] {
    let original = parsed(@fixtures.prose_only)
    let relationships = list(get(original, "relationships"))
    relationships[0] = set(
      relationships[0],
      "target",
      set(
        get(relationships[0], "target"),
        key,
        @ion.IonValue::string(replacement),
      ),
    )
    let inspected = @model.Graph::decode(original).inspect()
    assert_true(inspected is InvalidGraph(_))
    assert_true(has(inspected, code, path))
  }
  let original = parsed(@fixtures.prose_only)
  let relationships = list(get(original, "relationships"))
  relationships[0] = set(
    relationships[0],
    "predicate",
    @ion.IonValue::string("morphir:formalizes"),
  )
  assert_true(
    has(
      @model.Graph::decode(original).inspect(),
      "conceptual.relationship_kind",
      "/relationships/0",
    ),
  )
}

///|
test "explicit dependency input resolves only its declared exact snapshot" {
  let original = parsed(@fixtures.prose_only)
  let relationships = list(get(original, "relationships"))
  relationships[2] = set(
    relationships[2],
    "predicate",
    @ion.IonValue::string("future:link"),
  )
  relationships[2] = set(
    relationships[2],
    "target",
    parsed(
      (
        #|{state:"resolved",modelId:"urn:example:dictionary",modelRevision:"dict-1",entityId:"urn:example:dictionary:quantity",entityRevision:"concept-1"}
      ),
    ),
  )
  let with_dep = set(
    original,
    "dependencies",
    parsed(
      (
        #|[{model:{id:"urn:example:dictionary",revision:"dict-1"},inputId:"dictionary-input"}]
      ),
    ),
  )
  let inputs = Map::from_array([
    ("dictionary-input", graph(@fixtures.dictionary)),
  ])
  assert_false(
    @model.Graph::decode(with_dep).inspect(inputs~) is InvalidGraph(_),
  )
  assert_true(
    has(
      @model.Graph::decode(with_dep).inspect(),
      "conceptual.missing_resolved_target",
      "/relationships/2/target",
    ),
  )
  assert_true(
    @model.Graph::decode(original).inspect(inputs~) is InvalidGraph(_),
  )
  let wrong = set(
    parsed(@fixtures.dictionary),
    "model",
    parsed("{id:\"urn:example:dictionary\",revision:\"dict-2\"}"),
  )
  inputs["dictionary-input"] = @model.Graph::decode(wrong)
  assert_true(
    has(
      @model.Graph::decode(with_dep).inspect(inputs~),
      "conceptual.reference_revision",
      "/relationships/2/target",
    ),
  )
}

///|
test "required semantics remain preservable but cannot pass the interpretation gate" {
  let original = set(
    parsed(@fixtures.prose_only),
    "requiredSemantics",
    parsed("[\"urn:future:meaning/1\"]"),
  )
  let model = @model.Graph::decode(original)
  assert_true(model.to_ion().equals(original))
  assert_eq(
    failure(fn() raise { model.require_interpretation(Check) }),
    ("conceptual.unsupported_semantics", "/requiredSemantics/0"),
  )
  assert_eq(
    failure(fn() raise {
      graph(@fixtures.mixed).require_interpretation(Execute)
    }).0,
    "conceptual.unsupported_semantics",
  )
}

///|
test "private graphs cannot be invalidated through incoming or returned Ion arrays" {
  let input = parsed(@fixtures.prose_only)
  let model = @model.Graph::decode(input)
  list(get(input, "entities")).clear()
  let output = model.to_ion()
  list(get(output, "entities")).clear()
  let field = model.record().field("sources").unwrap()
  list(field).clear()
  let entity = model.entities()[0]
  let returned = entity.record().to_ion()
  guard returned.kind() is Struct(fs) else { abort("fixture") }
  fs.clear()
  assert_eq(model.entities().length(), 4)
  assert_eq(model.sources().length(), 2)
  assert_true(model.to_ion().equals(parsed(@fixtures.prose_only)))
}

///|
test "transitive dependency resolution stays within each declaring graph's closure" {
  let dictionary = parsed(@fixtures.dictionary)
  let intermediary = set(
    set(dictionary, "model", parsed("{id:\"urn:middle\",revision:\"m1\"}")),
    "entities",
    parsed("[]"),
  )
  let declared_middle = set(
    intermediary,
    "dependencies",
    parsed(
      "[{model:{id:\"urn:example:dictionary\",revision:\"dict-1\"},inputId:\"dictionary\"}]",
    ),
  )
  let root = parsed(@fixtures.prose_only)
  let root = set(
    root,
    "dependencies",
    parsed("[{model:{id:\"urn:middle\",revision:\"m1\"},inputId:\"middle\"}]"),
  )
  let relationships = list(get(root, "relationships"))
  relationships[2] = set(
    set(relationships[2], "predicate", @ion.IonValue::string("future:link")),
    "target",
    parsed(
      (
        #|{state:"resolved",modelId:"urn:example:dictionary",modelRevision:"dict-1",entityId:"urn:example:dictionary:quantity",entityRevision:"concept-1"}
      ),
    ),
  )
  let inputs = Map::from_array([
    ("dictionary", @model.Graph::decode(dictionary)),
    ("middle", @model.Graph::decode(declared_middle)),
  ])
  assert_false(@model.Graph::decode(root).inspect(inputs~) is InvalidGraph(_))
  inputs["middle"] = @model.Graph::decode(intermediary)
  assert_true(@model.Graph::decode(root).inspect(inputs~) is InvalidGraph(_))
  // Root declarations must not grant the middle graph access to the dictionary.
  let middle_relationship = set(
    relationships[2],
    "subject",
    get(relationships[2], "target"),
  )
  let middle_with_bad_ref = set(
    intermediary,
    "relationships",
    @ion.IonValue::list([middle_relationship]),
  )
  inputs["middle"] = @model.Graph::decode(middle_with_bad_ref)
  let root = set(
    root,
    "dependencies",
    parsed(
      "[{model:{id:\"urn:middle\",revision:\"m1\"},inputId:\"middle\"},{model:{id:\"urn:example:dictionary\",revision:\"dict-1\"},inputId:\"dictionary\"}]",
    ),
  )
  assert_true(@model.Graph::decode(root).inspect(inputs~) is InvalidGraph(_))
}

///|
test "known variants reject contradictory fields and duplicate nested members" {
  let original = parsed(@fixtures.independent_concerns)
  let entities = list(get(original, "entities"))
  entities[1] = set(
    entities[1],
    "implementation",
    parsed(
      "{state:\"unbound\",binding:{state:\"resolved\",modelId:\"x\",modelRevision:\"1\",entityId:\"y\",entityRevision:\"1\"}}",
    ),
  )
  assert_eq(
    failure(fn() raise { ignore(@model.Graph::decode(original)) }).0,
    "conceptual.invalid_variant",
  )
  let original = parsed(@fixtures.mixed)
  let entities = list(get(original, "entities"))
  let content = get(entities[1], "content")
  entities[1] = set(
    entities[1],
    "content",
    set(
      content,
      "signature",
      parsed("{inputs:{value:\"a\",value:\"b\"},output:\"a\"}"),
    ),
  )
  assert_eq(
    failure(fn() raise { ignore(@model.Graph::decode(original)) }),
    (
      "conceptual.duplicate_member", "/entities/1/content/signature/inputs/value",
    ),
  )
}

///|
test "model structural boundaries reject duplicate reference members and bound cycles" {
  let original = parsed(@fixtures.prose_only)
  let relationships = list(get(original, "relationships"))
  relationships[0] = set(
    relationships[0],
    "target",
    parsed(
      "{state:\"resolved\",modelId:\"a\",modelId:\"b\",modelRevision:\"1\",entityId:\"e\",entityRevision:\"1\"}",
    ),
  )
  assert_eq(
    failure(fn() raise { ignore(@model.Graph::decode(original)) }),
    ("conceptual.duplicate_member", "/relationships/0/target/modelId"),
  )
  let cycle : Array[@ion.IonValue] = []
  let value = @ion.IonValue::list(cycle)
  cycle.push(value)
  assert_eq(
    failure(fn() raise { ignore(@model.Graph::decode(value)) }).0,
    "data.tree_limit",
  )
  assert_eq(
    failure(fn() raise {
      ignore(
        graph(
          @fixtures.prose_only.replace(
            old="morphir-conceptual/0.1.0-draft.1",
            new="morphir-conceptual/0.1.0-draft.2",
          ),
        ),
      )
    }),
    ("conceptual.unsupported_profile", "/profile"),
  )
}

///|
test "trait semantic downgrades are invalid and application provenance is typed" {
  let root = parsed(@fixtures.traits)
  let traits = get(root, "traits")
  let apps = list(get(traits, "applications"))
  apps[0] = set(
    apps[0],
    "definition",
    parsed(
      "{state:\"resolved\",modelId:\"urn:example:trait-model\",modelRevision:\"model-1\",entityId:\"urn:example:trait:encoding\",entityRevision:\"d1\"}",
    ),
  )
  let model = @model.Graph::decode(root)
  assert_true(
    has(
      model.inspect(),
      "traits.interpretation_mismatch",
      "/traits/applications/0/interpretation",
    ),
  )
  assert_true(
    model.trait_applications()[0].target() is EntityTarget(TypeTarget, _),
  )
  assert_true(model.trait_applications()[0].origin() is Authored)
  assert_true(model.trait_definitions()[2].interpretation() is Semantic(_))
}

///|
test "known nested revision records reject duplicate members without reading opaque ASTs" {
  let original = parsed(@fixtures.mixed)
  let entities = list(get(original, "entities"))
  let content = get(entities[6], "content")
  let context = set(
    get(content, "context"),
    "model",
    parsed(
      "{id:\"urn:example:mixed\",revision:\"model-2\",revision:\"model-other\"}",
    ),
  )
  entities[6] = set(entities[6], "content", set(content, "context", context))
  assert_eq(
    failure(fn() raise { ignore(@model.Graph::decode(original)) }),
    (
      "conceptual.duplicate_member", "/entities/6/content/context/model/revision",
    ),
  )
}

///|
test "unknown entity kinds and critical fields are preserved and report unsupported interpretation" {
  let original = parsed(@fixtures.prose_only)
  let entities = list(get(original, "entities"))
  entities[2] = set(entities[2], "kind", @ion.IonValue::string("future:kind"))
  entities[2] = set(
    entities[2],
    "content",
    parsed("annotated::{same:1,same:2}"),
  )
  let root = set(
    set(original, "future/meaning", parsed("note::null.string")),
    "critical",
    parsed("[\"future/meaning\"]"),
  )
  let model = @model.Graph::decode(root)
  assert_true(model.to_ion().equals(root))
  assert_true(
    has(model.inspect(), "conceptual.unsupported_semantics", "/entities/2/kind"),
  )
  assert_true(
    has(model.inspect(), "conceptual.unsupported_semantics", "/future~1meaning"),
  )
  assert_eq(
    failure(fn() raise { model.require_interpretation(Check) }),
    ("conceptual.unsupported_semantics", "/future~1meaning"),
  )
}

///|
test "descriptive aliases allow empty text without weakening nonempty identities" {
  let original = parsed(@fixtures.prose_only)
  let entities = list(get(original, "entities"))
  entities[2] = set(
    entities[2],
    "content",
    set(get(entities[2], "content"), "aliases", parsed("[\"\",\"Borrower\"]")),
  )
  assert_true(@model.Graph::decode(original).to_ion().equals(original))
  entities[2] = set(entities[2], "id", @ion.IonValue::string(""))
  assert_eq(
    failure(fn() raise { ignore(@model.Graph::decode(original)) }).0,
    "conceptual.invalid_record",
  )
}
