///|
priv struct RecordingTree {
  files : Array[(String, String)]
  revision : Ref[String]
  opens : Array[String]
  delivered : Array[String]
}

///|
fn recording_tree(files : Array[(String, String)]) -> RecordingTree {
  { files, revision: Ref("revision-1"), opens: [], delivered: [], }
}

///|
fn RecordingTree::source(self : RecordingTree) -> @yaml.TreeSource {
  {
    revision: () => self.revision.val,
    contains: fn(revision, path) raise {
      self.check_revision(revision)
      self.files.any(file => file.0 == path)
    },
    next_module: fn(revision, prefix, after) raise {
      self.check_revision(revision)
      let mut found : String? = None
      for (path, _) in self.files {
        if !path.has_prefix(prefix) {
          continue
        }
        for extension in [".json", ".yaml", ".yml"] {
          if path.has_suffix("/module" + extension) {
            let logical = path[:path.length() - extension.length()].to_owned()
            if after.map_or(true, previous => {
                previous[:].lexical_compare(logical[:]) < 0
              }) &&
              found.map_or(true, current => {
                logical[:].lexical_compare(current[:]) < 0
              }) {
              found = Some(logical)
            }
          }
        }
      }
      found
    },
    read: fn(revision, path, max_bytes) raise {
      self.check_revision(revision)
      self.opens.push(path)
      for (file, text) in self.files {
        if file == path {
          // Fixture documents are ASCII, so units equal UTF-8 bytes.
          if text.length() > max_bytes {
            raise @yaml.TreeSourceError::DocumentTooLarge
          }
          self.delivered.push(path)
          return text
        }
      }
      fail("unexpected open: " + path)
    },
  }
}

///|
fn RecordingTree::check_revision(
  self : RecordingTree,
  revision : String,
) -> Unit raise {
  if self.revision.val != revision {
    raise @yaml.TreeSourceError::RevisionChanged
  }
}

///|
test "bounded inventory pages do not open definitions" {
  let tree = recording_tree(orders_v3_json())
  let reader = @yaml.open_bounded_tree(tree.source())
  let package_name = @ir.Path::parse("acme/orders")
  let module_name = @ir.Path::parse("domain")
  let first = reader.members(package_name, module_name, limit=2)
  assert_eq(first.items.map(item => item.document), [
    "pkg/acme/orders/domain/order.type", "pkg/acme/orders/domain/order.value",
  ])
  guard first.next is Some(cursor) else { fail("expected another page") }
  let final_page = reader.members(package_name, module_name, limit=2, cursor~)
  assert_eq(final_page.items.map(item => item.document), [
    "pkg/acme/orders/domain/total-in-_usd.value",
  ])
  assert_true(final_page.next is None)
  assert_eq(tree.opens, [
    "manifest.json", "pkg/acme/orders/domain/module.json", "pkg/acme/orders/domain/module.json",
  ])
}

///|
test "bounded module inventory has scoped continuations and roles" {
  let tree = recording_tree(orders_v4_yaml())
  let reader = @yaml.open_bounded_tree(tree.source())
  let package_name = @ir.Path::parse("acme/orders")
  let dependency = @ir.Path::parse("morphir/SDK")
  let first = reader.modules(package_name, limit=1)
  assert_eq(first.items.map(item => (item.document, item.role)), [
    ("pkg/acme/orders/audit/module", @yaml.Definition),
  ])
  guard first.items[0].access is Some(Private) else {
    fail("expected a private module")
  }
  guard first.next is Some(cursor) else { fail("expected another page") }
  let last = reader.modules(package_name, limit=1, cursor~)
  assert_eq(last.items.map(item => item.document), [
    "pkg/acme/orders/domain/module",
  ])
  assert_true(last.next is None)
  let specs = reader.modules(dependency, limit=1)
  assert_eq(specs.items.map(item => (item.document, item.role)), [
    ("deps/morphir/_sdk/@/basics/module", @yaml.Specification),
  ])
  assert_true(specs.items[0].access is None)
  let other = @yaml.open_bounded_tree(tree.source())
  let opened = tree.opens.copy()
  for
    result in [
      tree_failure(() => reader.modules(dependency, limit=1, cursor~)),
      tree_failure(() => other.modules(package_name, limit=1, cursor~)),
    ] {
    guard result is Some(@wire.Invalid("invalid_cursor", _)) else {
      fail("expected cursor scope refusal")
    }
  }
  tree.revision.val = "revision-2"
  guard tree_failure(() => reader.modules(package_name, limit=1, cursor~))
    is Some(@yaml.TreeSourceError::RevisionChanged) else {
    fail("expected stale source refusal")
  }
  assert_eq(tree.opens, opened)
  assert_eq(opened, [
    "manifest.yaml", "pkg/acme/orders/audit/module.yaml", "pkg/acme/orders/domain/module.yaml",
    "deps/morphir/_sdk/@/basics/module.yaml", "manifest.yaml",
  ])
}

///|
fn[T] tree_failure(read : () -> T raise) -> Error? {
  try {
    ignore(read())
    None
  } catch {
    error => Some(error)
  }
}

///|
test "bounded selected value preserves the final reference and literal" {
  for
    files in [
      orders_v3_json(),
      orders_v3_yaml(),
      orders_v4_json(),
      orders_v4_yaml(),
    ] {
    let tree = recording_tree(files)
    let reader = @yaml.open_bounded_tree(tree.source(), limits={
      ..@yaml.Limits::default(),
      max_bytes: 512,
    })
    let package_name = @ir.Path::parse("acme/orders")
    let module_name = @ir.Path::parse("domain")
    let first = reader.members(package_name, module_name, limit=2)
    guard first.next is Some(cursor) else { fail("expected another page") }
    let final_page = reader.members(package_name, module_name, limit=2, cursor~)
    assert_eq(final_page.items.map(item => item.name.to_canonical()), [
      "total-in-USD",
    ])
    assert_true(final_page.items[0].kind is ValueMember)
    let final_value = reader.read_member(
      package_name,
      module_name,
      ValueMember,
      final_page.items[0].name,
    )
    let reference = match final_value {
      V3ValueDefinition(definition) => {
        let value = definition.value.value
        guard value.output_type is Reference(_, output, []) &&
          value.body is Reference(Reference(_, inferred, []), reference) else {
          fail("expected a v3 reference with a classic inferred type")
        }
        assert_eq(output.to_canonical(), "morphir/SDK:basics#int")
        assert_eq(inferred, output)
        reference
      }
      V4ValueDefinition(definition) => {
        guard definition.value.value
          is ExpressionBody(
            [],
            Reference(_, output, []),
            Reference(_, reference)
          ) else {
          fail("expected a v4 expression body with an integer reference")
        }
        assert_eq(output.to_canonical(), "morphir/SDK:basics#int")
        reference
      }
      _ => fail("expected the final member to be a value definition")
    }
    assert_eq(reference.to_canonical(), "acme/orders:domain#order")
    let order = reader.read_member(
      package_name,
      module_name,
      ValueMember,
      @ir.Name::parse("order"),
    )
    match order {
      V3ValueDefinition(definition) => {
        guard definition.value.value.body
          is Literal(Reference(_, _, []), WholeNumberLiteral("73")) else {
          fail("expected the v3 classic attributed integer 73")
        }
      }
      V4ValueDefinition(definition) => {
        guard definition.value.value
          is ExpressionBody([], _, Literal(_, IntegerLiteral("73"))) else {
          fail("expected the v4 integer 73")
        }
      }
      _ => fail("expected the referenced order value")
    }
    let bodies = tree.opens.filter(path => path.contains(".value."))
    assert_eq(bodies.map(path => path[:path.length() - 5].to_owned()), [
      "pkg/acme/orders/domain/total-in-_usd.value", "pkg/acme/orders/domain/order.value",
    ])
  }
}

///|
test "bounded selected types and dependency specifications preserve roles" {
  for
    (files, v3) in [
      (orders_v3_json(), true),
      (orders_v3_yaml(), true),
      (orders_v4_json(), false),
      (orders_v4_yaml(), false),
    ] {
    let tree = recording_tree(files)
    let reader = @yaml.open_bounded_tree(tree.source())
    let own = @ir.Path::parse("acme/orders")
    let module_name = @ir.Path::parse("domain")
    let dependency = @ir.Path::parse("morphir/SDK")
    let basics = @ir.Path::parse("basics")
    let inventory = reader.members(dependency, basics, limit=2)
    assert_true(inventory.next is None)
    assert_eq(
      inventory.items.map(item => {
        (item.name.to_canonical(), item.kind, item.role, item.document)
      }),
      [
        (
          "int",
          @yaml.TypeMember,
          @yaml.Specification,
          "deps/morphir/_sdk/@/basics/int.type",
        ),
        (
          "add",
          @yaml.ValueMember,
          @yaml.Specification,
          "deps/morphir/_sdk/@/basics/add.value",
        ),
      ],
    )
    let order = reader.read_member(
      own,
      module_name,
      TypeMember,
      @ir.Name::parse("order"),
    )
    let int = reader.read_member(
      dependency,
      basics,
      TypeMember,
      @ir.Name::parse("int"),
    )
    let add = reader.read_member(
      dependency,
      basics,
      ValueMember,
      @ir.Name::parse("add"),
    )
    match (v3, order, int, add) {
      (
        true,
        V3TypeDefinition(order),
        V3TypeSpecification(_),
        V3ValueSpecification(add),
      ) => {
        guard order.value.value is TypeAliasDefinition([], Reference(_, _, [])) &&
          add.value.output is Reference(_, int_name, []) else {
          fail("expected classic type payloads")
        }
        assert_eq(int_name.to_canonical(), "morphir/SDK:basics#int")
      }
      (
        false,
        V4TypeDefinition(_),
        V4TypeSpecification(_),
        V4ValueSpecification(_),
      ) => ()
      _ => fail("selected payload changed version or role")
    }
  }
}

///|
test "bounded member pages keep listed order and inline document identity" {
  let files = [
    (
      "manifest.yaml", "formatVersion: 4\ndistribution: Library\npackage: acme/orders\npathBudget: 4000\n",
    ),
    (
      "pkg/acme/orders/domain/module.yaml", "formatVersion: 4\npath: domain\ntypes: [zulu, bravo]\nvalues:\n  alpha:\n    Public:\n      ExpressionBody:\n        inputTypes: {}\n        outputType: morphir/SDK:basics#int\n        body: 73\n",
    ),
  ]
  let tree = recording_tree(files)
  let reader = @yaml.open_bounded_tree(tree.source())
  let package_name = @ir.Path::parse("acme/orders")
  let module_name = @ir.Path::parse("domain")
  let first = reader.members(package_name, module_name, limit=2)
  assert_eq(first.items.map(item => item.name.to_canonical()), ["zulu", "bravo"])
  guard first.next is Some(cursor) else { fail("expected another page") }
  let last = reader.members(package_name, module_name, limit=2, cursor~)
  assert_eq(last.items.map(item => (item.name.to_canonical(), item.document)), [
    ("alpha", "pkg/acme/orders/domain/module"),
  ])
  assert_true(last.next is None)
  let body = reader.read_member(
    package_name,
    module_name,
    ValueMember,
    @ir.Name::parse("alpha"),
  )
  guard body is V4ValueDefinition(value) &&
    value.value.value is ExpressionBody([], _, Literal(_, IntegerLiteral("73"))) else {
    fail("expected typed inline value")
  }
  assert_eq(tree.opens, [
    "manifest.yaml", "pkg/acme/orders/domain/module.yaml", "pkg/acme/orders/domain/module.yaml",
    "pkg/acme/orders/domain/module.yaml",
  ])
}

///|
test "bounded module order uses extensionless logical paths" {
  let tree = recording_tree([
    (
      "manifest.json", "{\"formatVersion\":4,\"distribution\":\"Library\",\"package\":\"acme/orders\",\"pathBudget\":4000}",
    ),
    ("pkg/acme/orders/z/module.json", "{\"formatVersion\":4,\"path\":\"z\"}"),
    (
      "pkg/acme/orders/outer/module.json", "{\"formatVersion\":4,\"path\":\"outer\"}",
    ),
    (
      "pkg/acme/orders/outer/module-tools/module.json", "{\"formatVersion\":4,\"path\":\"outer/module-tools\"}",
    ),
  ])
  let reader = @yaml.open_bounded_tree(tree.source())
  let package_name = @ir.Path::parse("acme/orders")
  let first = reader.modules(package_name, limit=1)
  assert_eq(first.items.map(item => item.path.to_canonical()), ["outer"])
  guard first.next is Some(cursor) else { fail("expected another page") }
  let last = reader.modules(package_name, limit=1, cursor~)
  assert_eq(last.items.map(item => item.path.to_canonical()), [
    "outer/module-tools",
  ])
  guard last.next is Some(cursor) else { fail("expected one more page") }
  let end = reader.modules(package_name, limit=1, cursor~)
  assert_eq(end.items.map(item => item.path.to_canonical()), ["z"])
  assert_true(end.next is None)
}

///|
fn replace_order_file(path : String, text : String) -> Array[(String, String)] {
  orders_v4_json().map(file => if file.0 == path { (path, text) } else { file })
}

///|
fn[T] assert_tree_error(
  read : () -> T raise,
  code : String,
  location : String,
) -> Unit raise {
  guard tree_failure(read) is Some(@wire.Invalid(actual, detail)) else {
    fail("expected tree refusal with code " + code)
  }
  assert_eq(actual, code)
  assert_true(
    detail.has_prefix(location + "#") || detail.has_prefix(location + "/"),
  )
}

///|
test "bounded selected malformed files fail at their logical location" {
  let logical = "pkg/acme/orders/domain/order.value"
  let physical = logical + ".json"
  let package_name = @ir.Path::parse("acme/orders")
  let module_name = @ir.Path::parse("domain")
  let name = @ir.Name::parse("order")
  for
    (text, code) in [
      ("{", "invalid_json"),
      ("{\"formatVersion\":4,\"name\":\"order\",\"def\":false}", "invalid_type"),
      (
        "{\"formatVersion\":4,\"name\":\"order\",\"spec\":{}}", "invalid_distribution_shape",
      ),
      (
        "{\"formatVersion\":4,\"name\":\"other\",\"def\":{}}", "invalid_distribution_shape",
      ),
      (
        "{\"formatVersion\":\"3.1.0\",\"name\":\"order\",\"def\":{}}", "version_mismatch",
      ),
    ] {
    let tree = recording_tree(replace_order_file(physical, text))
    let reader = @yaml.open_bounded_tree(tree.source())
    let first = reader.members(package_name, module_name, limit=2)
    assert_eq(first.items[1].document, logical)
    assert_false(tree.opens.contains(physical))
    assert_tree_error(
      () => reader.read_member(package_name, module_name, ValueMember, name),
      code,
      logical,
    )
    assert_eq(tree.opens.last(), Some(physical))
  }
}

///|
test "bounded selected oversized and ambiguous files are refused before delivery" {
  let logical = "pkg/acme/orders/domain/order.value"
  let physical = logical + ".json"
  let package_name = @ir.Path::parse("acme/orders")
  let module_name = @ir.Path::parse("domain")
  let name = @ir.Name::parse("order")
  let oversized = recording_tree(replace_order_file(physical, " ".repeat(257)))
  let reader = @yaml.open_bounded_tree(oversized.source(), limits={
    ..@yaml.Limits::default(),
    max_bytes: 256,
  })
  assert_tree_error(
    () => reader.read_member(package_name, module_name, ValueMember, name),
    "document_size_limit",
    logical,
  )
  assert_eq(oversized.opens.last(), Some(physical))
  assert_false(oversized.delivered.contains(physical))

  let files = orders_v4_json()
  files.push((logical + ".yaml", "malformed and should never be opened"))
  let ambiguous = recording_tree(files)
  let reader = @yaml.open_bounded_tree(ambiguous.source())
  assert_tree_error(
    () => reader.read_member(package_name, module_name, ValueMember, name),
    "invalid_distribution_shape",
    logical,
  )
  assert_eq(ambiguous.opens, [
    "manifest.json", "pkg/acme/orders/domain/module.json",
  ])
}

///|
test "bounded selected fileNames cannot escape or point two members to one file" {
  let module_path = "pkg/acme/orders/domain/module"
  let package_name = @ir.Path::parse("acme/orders")
  let module_name = @ir.Path::parse("domain")
  let name = @ir.Name::parse("order")
  for
    (stem, code, location) in [
      ("../audit/order", "invalid_distribution_shape", "pkg/acme/orders/domain"),
      (
        "total-in-_usd", "duplicate_member", "pkg/acme/orders/domain/total-in-_usd.value",
      ),
    ] {
    let text = "{\"formatVersion\":4,\"path\":\"domain\",\"values\":[\"order\",\"total-in-USD\"],\"fileNames\":{\"order\":\"" +
      stem +
      "\"}}"
    let tree = recording_tree(replace_order_file(module_path + ".json", text))
    let reader = @yaml.open_bounded_tree(tree.source())
    assert_tree_error(
      () => reader.read_member(package_name, module_name, ValueMember, name),
      code,
      location,
    )
    assert_eq(tree.opens, ["manifest.json", module_path + ".json"])
  }
}

///|
test "bounded admission rejects duplicate inventory paths before the first page" {
  let module_path = "pkg/acme/orders/domain/module"
  let package_name = @ir.Path::parse("acme/orders")
  let module_name = @ir.Path::parse("domain")
  for
    members in [
      "\"values\":[\"order\",\"order\"]", "\"values\":[\"order\",\"total-in-USD\"],\"fileNames\":{\"order\":\"total-in-_usd\"}",
    ] {
    let text =
      #|{"formatVersion":4,"path":"domain","types":["order"],
    let tree = recording_tree(
      replace_order_file(module_path + ".json", text + members + "}"),
    )
    let reader = @yaml.open_bounded_tree(tree.source())
    assert_tree_error(
      () => reader.members(package_name, module_name, limit=1),
      "duplicate_member",
      "pkg/acme/orders/domain",
    )
    assert_eq(tree.opens, ["manifest.json", module_path + ".json"])
  }
}

///|
test "bounded admission checks fileNames before serving inline members" {
  let module_path = "pkg/acme/orders/domain/module"
  let package_name = @ir.Path::parse("acme/orders")
  let module_name = @ir.Path::parse("domain")
  let text =
    #|{"formatVersion":4,"path":"domain","values":{"one":{"Public":{"ExpressionBody":{"inputTypes":{},"outputType":"morphir/SDK:basics#int","body":1}}}},"fileNames":{"one":"../escape"}}
  let tree = recording_tree(replace_order_file(module_path + ".json", text))
  let reader = @yaml.open_bounded_tree(tree.source())
  assert_tree_error(
    () => reader.members(package_name, module_name, limit=1),
    "invalid_distribution_shape",
    module_path,
  )
  assert_tree_error(
    () => {
      reader.read_member(
        package_name,
        module_name,
        ValueMember,
        @ir.Name::parse("one"),
      )
    },
    "invalid_distribution_shape",
    module_path,
  )
  assert_eq(tree.opens, [
    "manifest.json",
    module_path + ".json",
    module_path + ".json",
  ])
}

///|
test "bounded admission charges semantic shorthand in JSON and YAML" {
  let logical = "pkg/acme/orders/domain/order.type"
  let name = @ir.Name::parse("order")
  let package_name = @ir.Path::parse("acme/orders")
  let module_name = @ir.Path::parse("domain")
  let long_type = "a".repeat(401)
  for
    (files, extension) in [
      (orders_v4_json(), ".json"),
      (orders_v4_yaml(), ".yaml"),
    ] {
    let physical = logical + extension
    let changed = files.map(file => {
      if file.0 == physical {
        (
          physical,
          file.1.replace_all(old="morphir/SDK:basics#int", new=long_type),
        )
      } else {
        file
      }
    })
    let tree = recording_tree(changed)
    let unrestricted = @yaml.open_bounded_tree(tree.source())
    ignore(
      unrestricted.read_member(package_name, module_name, TypeMember, name),
    )
    let limited = @yaml.open_bounded_tree(tree.source(), limits={
      ..@yaml.Limits::default(),
      max_assembly_nodes: 256,
    })
    assert_tree_error(
      () => limited.read_member(package_name, module_name, TypeMember, name),
      "yaml_assembly_limit",
      logical,
    )
  }
}

///|
test "bounded admission validates v4 manifest entry points" {
  for
    (kind, entry_points, code) in [
      ("Application", "", "missing_member"),
      ("Library", ",\"entryPoints\":{}", "unknown_member"),
      ("Application", ",\"entryPoints\":false", "invalid_type"),
      ("Application", ",\"entryPoints\":{}", "invalid_type"),
      ("Application", ",\"entryPoints\":{\"start\":{}}", "missing_member"),
    ] {
    let text = "{\"formatVersion\":4,\"distribution\":\"" +
      kind +
      "\",\"package\":\"acme/orders\",\"pathBudget\":4000" +
      entry_points +
      "}"
    let tree = recording_tree(replace_order_file("manifest.json", text))
    assert_tree_error(
      () => @yaml.open_bounded_tree(tree.source()),
      code,
      "manifest",
    )
    assert_eq(tree.opens, ["manifest.json"])
  }
  let valid =
    #|{"formatVersion":4,"distribution":"Application","package":"acme/orders","pathBudget":4000,"entryPoints":{"start":{"target":"acme/orders:domain#order","kind":"main"}}}
  let tree = recording_tree(replace_order_file("manifest.json", valid))
  ignore(@yaml.open_bounded_tree(tree.source()))
  assert_eq(tree.opens, ["manifest.json"])
}

///|
test "bounded selection rejects a noncanonical typed module path before opening it" {
  let tree = recording_tree(orders_v4_json())
  let reader = @yaml.open_bounded_tree(tree.source())
  let package_name = @ir.Path::parse("acme/orders")
  let module_name = @ir.Path::from_names([@ir.Name::from_words(["do-main"])])
  assert_tree_error(
    () => reader.members(package_name, module_name, limit=2),
    "invalid_distribution_shape",
    "module",
  )
  assert_eq(tree.opens, ["manifest.json"])
}

///|
test "bounded manifest refuses unsupported versions and layouts before module discovery" {
  for
    (version, layout, code) in [
      ("3", "", "version_mismatch"),
      ("5", "", "version_mismatch"),
      ("4", ",\"layout\":\"Classic\"", "unsupported_tree_layout"),
    ] {
    let text = "{\"formatVersion\":" +
      version +
      ",\"distribution\":\"Library\",\"package\":\"acme/orders\",\"pathBudget\":4000" +
      layout +
      "}"
    let tree = recording_tree(replace_order_file("manifest.json", text))
    assert_tree_error(
      () => @yaml.open_bounded_tree(tree.source()),
      code,
      "manifest",
    )
    assert_eq(tree.opens, ["manifest.json"])
  }
}

///|
test "bounded selected read discards a result if its revision changes during delivery" {
  let tree = recording_tree(orders_v4_json())
  let source = tree.source()
  let reader = @yaml.open_bounded_tree({
    ..source,
    read: fn(revision, path, max_bytes) raise {
      let text = (source.read)(revision, path, max_bytes)
      if path.has_suffix(".value.json") {
        tree.revision.val = "revision-2"
      }
      text
    },
  })
  let package_name = @ir.Path::parse("acme/orders")
  let module_name = @ir.Path::parse("domain")
  let name = @ir.Name::parse("order")
  guard tree_failure(() => {
      reader.read_member(package_name, module_name, ValueMember, name)
    })
    is Some(@yaml.TreeSourceError::RevisionChanged) else {
    fail("expected stale source refusal after delivery")
  }
  assert_eq(
    tree.delivered.last(),
    Some("pkg/acme/orders/domain/order.value.json"),
  )
}
