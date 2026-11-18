///|
test "bounded export expands selected classic and v4 JSON and YAML to the same plain document" {
  for
    (compact, plain) in [
      (contextual_orders_v3_json(), orders_v3_json()),
      (contextual_orders_v3_yaml(), orders_v3_json()),
      (contextual_orders_v4_json(), orders_v4_json()),
      (contextual_orders_v4_yaml(), orders_v4_json()),
    ] {
    let tree = recording_tree(compact)
    let reader = @yaml.open_bounded_tree(
      tree.source(),
      encoding=@yaml.ContextualDraft1,
    )
    let artifact = @yaml.MemberArtifact(
      @ir.Path::parse("acme/orders"),
      @ir.Path::parse("domain"),
      ValueMember,
      @ir.Name::parse("total-in-USD"),
    )
    let (path, expanded) = reader.read_expanded_document(
      artifact,
      max_output_bytes=8192,
    )
    let expected_path = "pkg/acme/orders/domain/total-in-_usd.value.json"
    assert_eq(path, expected_path)
    let original = Map(plain)[expected_path]
    assert_eq(expanded, @wire.expand_names(original))
    assert_true(
      tree.opens.all(path => {
        !path.contains(".value.") || path.contains("total-in-_usd.value.")
      }),
    )
  }
}

///|
test "bounded export checks the complete written byte count including aliases" {
  let tree = recording_tree(contextual_orders_v4_json())
  let reader = @yaml.open_bounded_tree(
    tree.source(),
    encoding=@yaml.ContextualDraft1,
  )
  let artifact = @yaml.MemberArtifact(
    @ir.Path::parse("acme/orders"),
    @ir.Path::parse("domain"),
    ValueMember,
    @ir.Name::parse("total-in-USD"),
  )
  let path = "pkg/acme/orders/domain/total-in-_usd.value"
  let expected = @wire.expand_names(Map(orders_v4_json())[path + ".json"])
  assert_eq(
    reader.read_expanded_document(artifact, max_output_bytes=expected.length()),
    (path + ".json", expected),
  )
  assert_true(
    tree_failure(() => {
      reader.read_expanded_document(
        artifact,
        max_output_bytes=expected.length() - 1,
      )
    })
    is Some(@wire.Invalid("document_size_limit", detail)) &&
    detail.contains(path),
  )
}

///|
test "bounded expanded export preserves context-last semantics and original pass-through" {
  let path = "pkg/acme/orders/domain/total-in-_usd.value.json"
  let envelope = Map(contextual_orders_v4_json())[path]
  let raw = @wire.parse(envelope)
  let late = @wire.obj([
    ("$schema", @wire.field(raw, "$schema")),
    ("document", @wire.field(raw, "document")),
    ("future", @wire.text("keep this in the original artifact")),
    ("context", @wire.field(raw, "context")),
  ]).stringify()
  let tree = recording_tree(
    contextual_orders_v4_json().map(pair => {
      if pair.0 == path {
        (path, late)
      } else {
        pair
      }
    }),
  )
  let reader = @yaml.open_bounded_tree(
    tree.source(),
    encoding=@yaml.ContextualDraft1,
  )
  let artifact = @yaml.MemberArtifact(
    @ir.Path::parse("acme/orders"),
    @ir.Path::parse("domain"),
    ValueMember,
    @ir.Name::parse("total-in-USD"),
  )
  assert_eq(
    reader.read_expanded_document(artifact, max_output_bytes=8192),
    (path, @wire.expand_names(envelope)),
  )
  assert_eq(reader.read_original_document(artifact), (path, late))
  tree.revision.val = "changed"
  assert_true(
    tree_failure(() => {
      reader.read_expanded_document(artifact, max_output_bytes=8192)
    })
    is Some(@yaml.TreeSourceError::RevisionChanged),
  )
}

///|
test "bounded tree export emits one plain artifact per logical document in page order" {
  let plain = orders_v4_yaml()
  let contextual = Map(contextual_orders_v4_yaml())
  let tree = recording_tree(
    plain.map(pair => (pair.0, contextual.get(pair.0).unwrap_or(pair.1))),
  )
  let reader = @yaml.open_bounded_tree(
    tree.source(),
    encoding=@yaml.ContextualDraft1,
  )
  let written : Map[String, String] = Map([])
  let paths = []
  reader.write_expanded_tree(
    { max_document_bytes: 8192, max_total_bytes: 65536L, page_size: 1, },
    fn(path, text) raise {
      assert_true(!written.contains(path))
      if paths.is_empty() {
        assert_eq(path, "manifest.json")
        assert_eq(tree.opens, ["manifest.yaml", "manifest.yaml"])
      }
      paths.push(path)
      written[path] = text
    },
  )
  assert_eq(written.length(), plain.length())
  assert_eq(
    @yaml.read_tree_versioned(written),
    @yaml.read_tree_versioned(Map(plain)),
  )
}

///|
test "bounded tree export stops before emitting an artifact outside the total byte budget" {
  let tree = recording_tree(contextual_orders_v4_json())
  let reader = @yaml.open_bounded_tree(
    tree.source(),
    encoding=@yaml.ContextualDraft1,
  )
  let (_, manifest) = reader.read_expanded_document(
    @yaml.ManifestArtifact,
    max_output_bytes=8192,
  )
  let paths = []
  assert_true(
    tree_failure(() => {
      reader.write_expanded_tree(
        {
          max_document_bytes: 8192,
          max_total_bytes: manifest.length().to_int64(),
          page_size: 1,
        },
        (path, _) => paths.push(path),
      )
    })
    is Some(@wire.Invalid("document_size_limit", _)),
  )
  assert_eq(paths, ["manifest.json"])
  assert_true(
    tree.opens.all(path => !path.contains(".type.") && !path.contains(".value.")),
  )
}

///|
test "expanded v4 preserves meaningful order, opaque literal data, and UTF-8 byte limits" {
  let physical = "pkg/acme/orders/domain/order.value.json"
  let source =
    #|{"$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json","context":{"fqNames":{"a":"morphir/SDK:basics#int"}},"document":{"formatVersion":4,"name":"order","def":{"Public":{"ExpressionBody":{"inputTypes":{"rate":{"$name":"a"},"amount":{"$name":"a"}},"outputType":{"$name":"a"},"body":{"Literal":{"DocumentLiteral":{"z":"é","literal":{"$name":"a"},"a":1.50}}}}}}}}
  let expected =
    #|{"def":{"Public":{"ExpressionBody":{"body":{"Literal":{"DocumentLiteral":{"z":"é","literal":{"$name":"a"},"a":1.50}}},"inputTypes":{"rate":"morphir/SDK:basics#int","amount":"morphir/SDK:basics#int"},"outputType":"morphir/SDK:basics#int"}}},"formatVersion":4,"name":"order"}
  let tree = recording_tree(
    orders_v4_json().map(pair => {
      if pair.0 == physical {
        (physical, source)
      } else {
        pair
      }
    }),
  )
  let reader = @yaml.open_bounded_tree(
    tree.source(),
    encoding=@yaml.ContextualDraft1,
  )
  let artifact = @yaml.MemberArtifact(
    @ir.Path::parse("acme/orders"),
    @ir.Path::parse("domain"),
    ValueMember,
    @ir.Name::parse("order"),
  )
  assert_eq(
    reader.read_expanded_document(
      artifact,
      max_output_bytes=expected.length() + 1,
    ),
    (physical, expected),
  )
  assert_true(
    tree_failure(() => {
      reader.read_expanded_document(
        artifact,
        max_output_bytes=expected.length(),
      )
    })
    is Some(@wire.Invalid("document_size_limit", _)),
  )
}

///|
test "bounded expanded export writes an inline module artifact once" {
  let manifest =
    #|{"formatVersion":4,"distribution":"Library","package":"acme/orders","pathBudget":4000}
  let path = "pkg/acme/orders/domain/module.json"
  let source =
    #|{"formatVersion":4,"path":"domain","values":{"one":{"access":"Public","ExpressionBody":{"inputTypes":{},"outputType":"morphir/SDK:basics#int","body":{"Literal":{"IntegerLiteral":1}}}},"two":{"access":"Private","ExpressionBody":{"inputTypes":{},"outputType":"morphir/SDK:basics#int","body":{"Literal":{"IntegerLiteral":2}}}}}}
  let files = [("manifest.json", manifest), (path, source)]
  let tree = recording_tree(files)
  let reader = @yaml.open_bounded_tree(tree.source())
  let written : Map[String, String] = Map([])
  reader.write_expanded_tree(
    { max_document_bytes: 8192, max_total_bytes: 65536L, page_size: 1, },
    fn(path, text) raise {
      assert_true(!written.contains(path))
      written[path] = text
    },
  )
  assert_eq(written.length(), 2)
  assert_eq(
    @yaml.read_tree_versioned(written),
    @yaml.read_tree_versioned(Map(files)),
  )
}
