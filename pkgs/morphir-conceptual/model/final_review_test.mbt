///|
fn target_fixture(target : @ion.IonValue) -> @ion.IonValue raise {
  let root = parsed(@fixtures.traits)
  let apps = list(get(get(root, "traits"), "applications"))
  apps[0] = set(apps[0], "target", target)
  root
}

///|
fn entity_target(kind : String, entity : String) -> @ion.IonValue raise {
  parsed(
    "{kind:\"" +
    kind +
    "\",ref:{state:\"resolved\",modelId:\"urn:example:trait-model\",modelRevision:\"model-1\",entityId:\"urn:example:" +
    entity +
    "\",entityRevision:\"e1\"}}",
  )
}

///|
test "final review: built-in targets reject wrong entity kinds and declaration roles" {
  for
    (kind, entity) in [
      ("concept", "type:quantity"),
      ("type", "concept:quantity"),
      ("type", "function:accept"),
      ("function", "type:quantity"),
      ("member", "type:quantity"),
    ] {
    let root = target_fixture(entity_target(kind, entity))
    let result = @model.Graph::decode(root).inspect()
    assert_true(result is InvalidGraph(_))
    assert_true(
      has(
        result, "traits.target_identity_kind", "/traits/applications/0/target",
      ),
    )
  }
}

///|
test "final review: unresolved target expected kinds must agree without inventing roles" {
  for
    (kind, expected) in [
      ("concept", "concept"),
      ("type", "declaration"),
      ("member", "declaration"),
      ("function", "declaration"),
    ] {
    let target = parsed(
      "{kind:\"" +
      kind +
      "\",ref:{state:\"unresolved\",locator:\"urn:later\",expectedKind:\"" +
      expected +
      "\",reason:\"later\"}}",
    )
    let good = @model.Graph::decode(target_fixture(target)).inspect()
    assert_false(good is InvalidGraph(_))
    assert_true(
      has(
        good, "conceptual.unresolved_reference", "/traits/applications/0/target/ref",
      ),
    )
    let bad = set(
      target,
      "ref",
      set(get(target, "ref"), "expectedKind", @ion.IonValue::string("evidence")),
    )
    assert_true(
      has(
        @model.Graph::decode(target_fixture(bad)).inspect(),
        "traits.target_identity_kind",
        "/traits/applications/0/target",
      ),
    )
  }
}

///|
test "final review: entity targets resolve correct local and dependent identities" {
  for role in ["field", "parameter", "result"] {
    let root = target_fixture(entity_target("member", "member:quantity"))
    let entities = list(get(root, "entities"))
    entities[2] = set(
      entities[2],
      "content",
      set(get(entities[2], "content"), "role", @ion.IonValue::string(role)),
    )
    assert_false(@model.Graph::decode(root).inspect() is InvalidGraph(_))
  }
  for
    (kind, entity) in [
      ("concept", "concept:quantity"),
      ("type", "type:quantity"),
      ("member", "member:quantity"),
      ("function", "function:accept"),
    ] {
    let root = target_fixture(entity_target(kind, entity))
    assert_false(@model.Graph::decode(root).inspect() is InvalidGraph(_))
    let dependent = set(
      set(root, "model", parsed("{id:\"urn:owner\",revision:\"o1\"}")),
      "dependencies",
      parsed(
        "[{model:{id:\"urn:example:trait-model\",revision:\"model-1\"},inputId:\"target\"}]",
      ),
    )
    // All references originally pointed at the fixed dependency, not the renamed owner.
    let inputs = Map::from_array([("target", graph(@fixtures.traits))])
    assert_false(
      @model.Graph::decode(dependent).inspect(inputs~) is InvalidGraph(_),
    )
  }
}

///|
test "final review: unknown module and profile targets retain facts and disclose limits" {
  for
    (target, code, suffix) in [
      (
        "{kind:\"future:target\",opaque:{same:1,same:2}}", "conceptual.unsupported_semantics",
        "/kind",
      ),
      (
        "{kind:\"module\",artifact:{id:\"urn:artifact\",revision:\"1\"},node:\"urn:module\"}",
        "conceptual.unsupported_semantics", "/artifact",
      ),
      (
        "{kind:\"operation\",profile:\"urn:future:operations\",ref:{state:\"unresolved\",locator:\"urn:op\",expectedKind:\"operation\",reason:\"later\"}}",
        "traits.unsupported_target_profile", "/profile",
      ),
      (
        "{kind:\"serviceBinding\",profile:\"urn:future:services\",ref:{state:\"unresolved\",locator:\"urn:service\",expectedKind:\"serviceBinding\",reason:\"later\"}}",
        "traits.unsupported_target_profile", "/profile",
      ),
    ] {
    let root = target_fixture(parsed(target))
    let model = @model.Graph::decode(root)
    assert_true(model.to_ion().equals(root))
    let result = model.inspect()
    assert_false(result is InvalidGraph(_))
    assert_true(has(result, code, "/traits/applications/0/target" + suffix))
    if suffix == "/profile" {
      let target = parsed(target)
      let bad = set(
        target,
        "ref",
        set(
          get(target, "ref"),
          "expectedKind",
          @ion.IonValue::string("concept"),
        ),
      )
      assert_true(
        has(
          @model.Graph::decode(target_fixture(bad)).inspect(),
          "traits.target_identity_kind",
          "/traits/applications/0/target",
        ),
      )
    }
  }
}

///|
test "final review: nested closure failures have one correctly escaped input path" {
  let leaf = set(
    parsed(@fixtures.dictionary),
    "dependencies",
    parsed("[{model:{id:\"urn:missing\",revision:\"1\"},inputId:\"missing\"}]"),
  )
  let middle = set(
    set(
      parsed(@fixtures.dictionary),
      "model",
      parsed("{id:\"urn:middle\",revision:\"1\"}"),
    ),
    "dependencies",
    parsed(
      "[{model:{id:\"urn:example:dictionary\",revision:\"dict-1\"},inputId:\"leaf/~\"}]",
    ),
  )
  let root = set(
    parsed(@fixtures.prose_only),
    "dependencies",
    parsed("[{model:{id:\"urn:middle\",revision:\"1\"},inputId:\"middle\"}]"),
  )
  let inputs = Map::from_array([
    ("middle", @model.Graph::decode(middle)),
    ("leaf/~", @model.Graph::decode(leaf)),
  ])
  let model = @model.Graph::decode(root)
  assert_eq(model.inspect(inputs~).diagnostics(), [
    {
      code: "conceptual.missing_resolved_target",
      path: "/inputs/leaf~1~0/dependencies/0",
      related_path: None,
    },
  ])
  inputs["missing"] = graph(@fixtures.dictionary)
  assert_eq(model.inspect(inputs~).diagnostics(), [
    {
      code: "conceptual.reference_revision",
      path: "/inputs/leaf~1~0/dependencies/0",
      related_path: None,
    },
  ])
}

///|
// Test-only escape hatch: mirror the pinned core's private byte reinterpretation
// so outgoing ownership is tested even against deliberate unsafe alias mutation.
fn unsafe_mutable_bytes(bytes : Bytes) -> FixedArray[Byte] = "%identity"

///|
fn scalar_bytes(value : @ion.IonValue) -> Bytes {
  match value.kind() {
    Blob(bytes) | Clob(bytes) => bytes
    _ => abort("Expected byte scalar")
  }
}

///|
test "final review: retained blob and clob bytes own their incoming storage" {
  for make_scalar in [@ion.IonValue::blob, @ion.IonValue::clob] {
    let incoming = FixedArray::make(3, b'A')
    let root = set(
      parsed(@fixtures.traits),
      "opaqueBytes",
      make_scalar(incoming.unsafe_reinterpret_as_bytes()),
    )
    let model = @model.Graph::decode(root)
    incoming[0] = b'Z'
    assert_eq(
      scalar_bytes(model.record().field("opaqueBytes").unwrap()),
      b"AAA",
    )
  }
}

///|
test "final review: exported blob and clob bytes never alias retained storage" {
  for make_scalar in [@ion.IonValue::blob, @ion.IonValue::clob] {
    let root = set(
      parsed(@fixtures.traits),
      "opaqueBytes",
      make_scalar(Bytes::makei(3, _ => b'A')),
    )
    let model = @model.Graph::decode(root)
    let field = model.record().field("opaqueBytes").unwrap()
    unsafe_mutable_bytes(scalar_bytes(field))[0] = b'Z'
    assert_eq(scalar_bytes(get(model.to_ion(), "opaqueBytes")), b"AAA")
    let output = get(model.to_ion(), "opaqueBytes")
    unsafe_mutable_bytes(scalar_bytes(output))[1] = b'Z'
    assert_eq(
      scalar_bytes(model.record().field("opaqueBytes").unwrap()),
      b"AAA",
    )
  }
}
