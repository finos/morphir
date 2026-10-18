///|
test "review: digest records require sha256 and lowercase 64 digit hex" {
  for
    (digest, code, suffix) in [
      ("{}", "conceptual.missing_field", "/algorithm"),
      ("{algorithm:\"sha256\"}", "conceptual.missing_field", "/value"),
      (
        "{algorithm:\"sha512\",value:\"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\"}",
        "conceptual.invalid_record", "/algorithm",
      ),
      (
        "{algorithm:\"sha256\",value:\"abcd\"}", "conceptual.invalid_record", "/value",
      ),
      (
        "{algorithm:\"sha256\",value:\"0123456789ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef\"}",
        "conceptual.invalid_record", "/value",
      ),
      (
        "{algorithm:\"sha256\",value:\"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdeg\"}",
        "conceptual.invalid_record", "/value",
      ),
    ] {
    let root = parsed(@fixtures.prose_only)
    let sources = list(get(root, "sources"))
    sources[1] = set(
      sources[1],
      "document",
      set(get(sources[1], "document"), "digest", parsed(digest)),
    )
    assert_eq(
      failure(fn() raise { ignore(@model.Graph::decode(root)) }),
      (code, "/sources/1/document/digest" + suffix),
    )
  }
}

///|
test "review: unverified digest claims never replace a source revision pin" {
  let root = parsed(@fixtures.prose_only)
  let sources = list(get(root, "sources"))
  let digest = parsed(
    "{algorithm:\"sha256\",value:\"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\",future:{same:1,same:2}}",
  )
  sources[1] = set(
    sources[1],
    "document",
    set(get(sources[1], "document"), "digest", digest),
  )
  let model = @model.Graph::decode(root)
  assert_true(model.to_ion().equals(root))
  assert_true(
    has(model.inspect(), "conceptual.source_unpinned", "/sources/1/document"),
  )
  sources[1] = set(
    sources[1],
    "document",
    set(
      get(sources[1], "document"),
      "revision",
      @ion.IonValue::string("source-1"),
    ),
  )
  assert_false(
    has(
      @model.Graph::decode(root).inspect(),
      "conceptual.source_unpinned",
      "/sources/1/document",
    ),
  )
}

///|
test "review: contract and claim subjects and declaration parents require resolved references" {
  for (index, field) in [(4, "subject"), (6, "subject"), (1, "parent")] {
    let root = parsed(@fixtures.mixed)
    let entities = list(get(root, "entities"))
    let unresolved = parsed(
      "{state:\"unresolved\",locator:\"urn:missing\",expectedKind:\"declaration\",reason:\"not supplied\"}",
    )
    entities[index] = set(
      entities[index],
      "content",
      set(get(entities[index], "content"), field, unresolved),
    )
    assert_eq(
      failure(fn() raise { ignore(@model.Graph::decode(root)) }),
      (
        "conceptual.invalid_variant",
        "/entities/" + index.to_string() + "/content/" + field,
      ),
    )
  }
}

///|
test "review: derived provenance requires resolved inputs while authorized unresolved variants survive" {
  let root = parsed(@fixtures.traits)
  let applications = list(get(get(root, "traits"), "applications"))
  let unresolved = parsed(
    "{state:\"unresolved\",locator:\"urn:missing\",expectedKind:\"traitDefinition\",reason:\"not supplied\"}",
  )
  let provenance = set(
    get(applications[0], "provenance"),
    "origin",
    @ion.IonValue::string("derived"),
  )
  applications[0] = set(
    applications[0],
    "provenance",
    set(provenance, "derivedFrom", @ion.IonValue::list([unresolved])),
  )
  assert_eq(
    failure(fn() raise { ignore(@model.Graph::decode(root)) }),
    (
      "conceptual.invalid_variant", "/traits/applications/0/provenance/derivedFrom/0",
    ),
  )
  let resolved = parsed(
    "{state:\"resolved\",modelId:\"urn:example:trait-model\",modelRevision:\"model-1\",entityId:\"urn:example:concept:quantity\",entityRevision:\"e1\"}",
  )
  applications[0] = set(
    applications[0],
    "provenance",
    set(provenance, "derivedFrom", @ion.IonValue::list([resolved])),
  )
  applications[0] = set(applications[0], "definition", unresolved)
  let model = @model.Graph::decode(root)
  assert_false(model.inspect() is InvalidGraph(_))
  assert_true(model.trait_applications()[0].definition() is Unresolved(_, _, _))
  assert_true(model.to_ion().equals(root))
  assert_true(
    graph(@fixtures.prose_only).relationships()[2].target()
    is Unresolved(_, _, _),
  )
}

///|
fn with_model_target(
  root : @ion.IonValue,
  snapshot : String,
) -> @ion.IonValue raise {
  let applications = list(get(get(root, "traits"), "applications"))
  applications[0] = set(
    applications[0],
    "target",
    parsed("{kind:\"model\",model:" + snapshot + "}"),
  )
  root
}

///|
test "review: model targets resolve local direct and transitive exact snapshots" {
  let local_target = with_model_target(
    parsed(@fixtures.traits),
    "{id:\"urn:example:trait-model\",revision:\"model-1\"}",
  )
  assert_false(@model.Graph::decode(local_target).inspect() is InvalidGraph(_))
  let root = with_model_target(
    parsed(@fixtures.traits),
    "{id:\"urn:example:dictionary\",revision:\"dict-1\"}",
  )
  let dictionary_dependency = parsed(
    "[{model:{id:\"urn:example:dictionary\",revision:\"dict-1\"},inputId:\"dictionary\"}]",
  )
  let direct = set(root, "dependencies", dictionary_dependency)
  let inputs = Map::from_array([("dictionary", graph(@fixtures.dictionary))])
  assert_false(@model.Graph::decode(direct).inspect(inputs~) is InvalidGraph(_))
  let middle = set(
    set(
      parsed(@fixtures.dictionary),
      "model",
      parsed("{id:\"urn:middle\",revision:\"m1\"}"),
    ),
    "dependencies",
    dictionary_dependency,
  )
  inputs["middle"] = @model.Graph::decode(middle)
  let transitive = set(
    root,
    "dependencies",
    parsed("[{model:{id:\"urn:middle\",revision:\"m1\"},inputId:\"middle\"}]"),
  )
  assert_false(
    @model.Graph::decode(transitive).inspect(inputs~) is InvalidGraph(_),
  )
}

///|
test "review: model targets reject missing wrong revision and undeclared supplied snapshots" {
  let path = "/traits/applications/0/target/model"
  let missing = with_model_target(
    parsed(@fixtures.traits),
    "{id:\"urn:missing\",revision:\"1\"}",
  )
  assert_true(
    has(
      @model.Graph::decode(missing).inspect(),
      "conceptual.missing_resolved_target",
      path,
    ),
  )
  let wrong_local = with_model_target(
    parsed(@fixtures.traits),
    "{id:\"urn:example:trait-model\",revision:\"wrong\"}",
  )
  assert_true(
    has(
      @model.Graph::decode(wrong_local).inspect(),
      "conceptual.reference_revision",
      path,
    ),
  )
  let root = with_model_target(
    parsed(@fixtures.traits),
    "{id:\"urn:example:dictionary\",revision:\"dict-1\"}",
  )
  let inputs = Map::from_array([("dictionary", graph(@fixtures.dictionary))])
  assert_true(
    has(
      @model.Graph::decode(root).inspect(inputs~),
      "conceptual.missing_resolved_target",
      path,
    ),
  )
  let declared = set(
    root,
    "dependencies",
    parsed(
      "[{model:{id:\"urn:example:dictionary\",revision:\"dict-1\"},inputId:\"dictionary\"}]",
    ),
  )
  assert_true(
    has(
      @model.Graph::decode(declared).inspect(),
      "conceptual.missing_resolved_target",
      path,
    ),
  )
  let wrong = set(
    parsed(@fixtures.dictionary),
    "model",
    parsed("{id:\"urn:example:dictionary\",revision:\"dict-2\"}"),
  )
  inputs["dictionary"] = @model.Graph::decode(wrong)
  assert_true(
    has(
      @model.Graph::decode(declared).inspect(inputs~),
      "conceptual.reference_revision",
      path,
    ),
  )
}

///|
test "review: a root declaration does not grant a dependency model-target access" {
  let middle = with_model_target(
    parsed(@fixtures.traits),
    "{id:\"urn:example:dictionary\",revision:\"dict-1\"}",
  )
  let root = set(
    parsed(@fixtures.prose_only),
    "dependencies",
    parsed(
      "[{model:{id:\"urn:example:trait-model\",revision:\"model-1\"},inputId:\"middle\"},{model:{id:\"urn:example:dictionary\",revision:\"dict-1\"},inputId:\"dictionary\"}]",
    ),
  )
  let inputs = Map::from_array([
    ("middle", @model.Graph::decode(middle)),
    ("dictionary", graph(@fixtures.dictionary)),
  ])
  let result = @model.Graph::decode(root).inspect(inputs~)
  assert_true(result is InvalidGraph(_))
  assert_true(
    has(
      result, "conceptual.missing_resolved_target", "/inputs/middle/traits/applications/0/target/model",
    ),
  )
}
