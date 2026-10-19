// Independent expectations frozen in headless-parity/v1/yaml/tree-cases.json.

///|
test "independent YAML tree v4-empty-library" {
  let files : Map[String, String] = Map([
    (
      "manifest.yaml", "formatVersion: 4\ndistribution: Library\npackage: parity\npathBudget: 4000\n",
    ),
  ])
  let file = @yaml.read_tree(files)
  let value = @codec.to_json(file)
  assert_eq(file.format_version.to_release_string(), "4.0.0")
  assert_true(
    @wire.object(@wire.field(value, "distribution")).contains("Library"),
  )
  let payload = @wire.object(@wire.field(value, "distribution"))
    .values()
    .next()
    .unwrap()
  assert_eq(@wire.string(@wire.field(payload, "packageName")), "parity")
  assert_eq(@wire.object(@wire.field(payload, "dependencies")).length(), 0)
  let body = @wire.optional(payload, "def").unwrap_or_else(() => {
    @wire.field(payload, "spec")
  })
  assert_eq(@wire.object(@wire.field(body, "modules")).length(), 0)
}

///|
test "independent YAML tree v4-empty-private-module" {
  let files : Map[String, String] = Map([
    (
      "manifest.yaml", "formatVersion: 4\ndistribution: Library\npackage: parity\npathBudget: 4000\n",
    ),
    (
      "pkg/parity/main/module.yaml", "formatVersion: 4\npath: main\ntypes: []\nvalues: []\naccess: Private\n",
    ),
  ])
  let file = @yaml.read_tree(files)
  let value = @codec.to_json(file)
  assert_eq(file.format_version.to_release_string(), "4.0.0")
  assert_true(
    @wire.object(@wire.field(value, "distribution")).contains("Library"),
  )
  let payload = @wire.object(@wire.field(value, "distribution"))
    .values()
    .next()
    .unwrap()
  assert_eq(@wire.object(@wire.field(payload, "dependencies")).length(), 0)
  let body = @wire.optional(payload, "def").unwrap_or_else(() => {
    @wire.field(payload, "spec")
  })
  assert_eq(@wire.object(@wire.field(body, "modules")).length(), 1)
}

///|
test "independent YAML tree v4-empty-specification-module" {
  let files : Map[String, String] = Map([
    (
      "manifest.yaml", "formatVersion: 4\ndistribution: Specs\npackage: parity\npathBudget: 4000\n",
    ),
    (
      "pkg/parity/main/module.yaml", "formatVersion: 4\npath: main\ntypes: []\nvalues: []\n",
    ),
  ])
  let file = @yaml.read_tree(files)
  let value = @codec.to_json(file)
  assert_eq(file.format_version.to_release_string(), "4.0.0")
  assert_true(
    @wire.object(@wire.field(value, "distribution")).contains("Specs"),
  )
  let payload = @wire.object(@wire.field(value, "distribution"))
    .values()
    .next()
    .unwrap()
  assert_eq(@wire.object(@wire.field(payload, "dependencies")).length(), 0)
  let body = @wire.optional(payload, "def").unwrap_or_else(() => {
    @wire.field(payload, "spec")
  })
  assert_eq(@wire.object(@wire.field(body, "modules")).length(), 1)
}

///|
test "independent YAML tree v4-dependency-empty-module" {
  let files : Map[String, String] = Map([
    (
      "manifest.yaml", "formatVersion: 4\ndistribution: Library\npackage: parity\npathBudget: 4000\ndependencies: [sdk]\n",
    ),
    (
      "deps/sdk/@/main/module.yaml", "formatVersion: 4\npath: main\ntypes: []\nvalues: []\n",
    ),
  ])
  let file = @yaml.read_tree(files)
  let value = @codec.to_json(file)
  assert_eq(file.format_version.to_release_string(), "4.0.0")
  let payload = @wire.object(@wire.field(value, "distribution"))
    .values()
    .next()
    .unwrap()
  assert_eq(@wire.object(@wire.field(payload, "dependencies")).length(), 1)
}

///|
test "independent YAML tree v4-yml-physical-extension" {
  let files : Map[String, String] = Map([
    (
      "manifest.yml", "formatVersion: 4\ndistribution: Library\npackage: parity\npathBudget: 4000\n",
    ),
    (
      "pkg/parity/main/module.yml", "formatVersion: 4\npath: main\ntypes: []\nvalues: []\n",
    ),
  ])
  let file = @yaml.read_tree(files)
  let value = @codec.to_json(file)
  let payload = @wire.object(@wire.field(value, "distribution"))
    .values()
    .next()
    .unwrap()
  let body = @wire.optional(payload, "def").unwrap_or_else(() => {
    @wire.field(payload, "spec")
  })
  assert_eq(@wire.object(@wire.field(body, "modules")).length(), 1)
}

///|
test "independent YAML tree v4-ignore-other-extensions" {
  let files : Map[String, String] = Map([
    (
      "manifest.yaml", "formatVersion: 4\ndistribution: Library\npackage: parity\npathBudget: 4000\n",
    ),
    ("README.txt", "not part of the tree\n"),
  ])
  let file = @yaml.read_tree(files)
  let value = @codec.to_json(file)
  let payload = @wire.object(@wire.field(value, "distribution"))
    .values()
    .next()
    .unwrap()
  let body = @wire.optional(payload, "def").unwrap_or_else(() => {
    @wire.field(payload, "spec")
  })
  assert_eq(@wire.object(@wire.field(body, "modules")).length(), 0)
}

///|
test "independent YAML tree v31-empty-library" {
  let files : Map[String, String] = Map([
    (
      "manifest.yaml", "formatVersion: \"3.1.0\"\ndistribution: Library\npackage: parity\npathBudget: 4000\n",
    ),
    (
      "pkg/parity/main/module.yaml", "formatVersion: \"3.1.0\"\npath: main\ntypes: []\nvalues: []\n",
    ),
  ])
  let file = @yaml.read_tree(files)
  let value = @codec.to_json(file)
  assert_eq(file.format_version.to_release_string(), "4.0.0")
  assert_true(
    @wire.object(@wire.field(value, "distribution")).contains("Library"),
  )
  let payload = @wire.object(@wire.field(value, "distribution"))
    .values()
    .next()
    .unwrap()
  let body = @wire.optional(payload, "def").unwrap_or_else(() => {
    @wire.field(payload, "spec")
  })
  assert_eq(@wire.object(@wire.field(body, "modules")).length(), 1)
}

///|
test "independent YAML tree v31-empty-specs" {
  let files : Map[String, String] = Map([
    (
      "manifest.yaml", "formatVersion: \"3.1.0\"\ndistribution: Specs\npackage: parity\npathBudget: 4000\n",
    ),
    (
      "pkg/parity/main/module.yaml", "formatVersion: \"3.1.0\"\npath: main\ntypes: []\nvalues: []\n",
    ),
  ])
  let file = @yaml.read_tree(files)
  let value = @codec.to_json(file)
  assert_eq(file.format_version.to_release_string(), "4.0.0")
  assert_true(
    @wire.object(@wire.field(value, "distribution")).contains("Specs"),
  )
  let payload = @wire.object(@wire.field(value, "distribution"))
    .values()
    .next()
    .unwrap()
  let body = @wire.optional(payload, "def").unwrap_or_else(() => {
    @wire.field(payload, "spec")
  })
  assert_eq(@wire.object(@wire.field(body, "modules")).length(), 1)
}

///|
test "independent YAML tree ambiguous-manifests" {
  let files : Map[String, String] = Map([
    (
      "manifest.yaml", "formatVersion: 4\ndistribution: Library\npackage: parity\npathBudget: 4000\n",
    ),
    (
      "manifest.json", "{\"formatVersion\":4,\"distribution\":\"Library\",\"package\":\"parity\",\"pathBudget\":4000}",
    ),
  ])
  let code = try {
    ignore(@yaml.read_tree(files))
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
    _ => "other_refusal"
  }
  assert_true(code != "accepted")
}

///|
test "independent YAML tree mixed-physical-profile" {
  let files : Map[String, String] = Map([
    (
      "manifest.yaml", "formatVersion: 4\ndistribution: Library\npackage: parity\npathBudget: 4000\n",
    ),
    (
      "pkg/parity/main/module.json", "{\"formatVersion\":4,\"path\":\"main\",\"types\":[],\"values\":[]}",
    ),
  ])
  let code = try {
    ignore(@yaml.read_tree(files))
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
    _ => "other_refusal"
  }
  assert_true(code != "accepted")
}

///|
test "independent YAML tree v31-reject-v30-manifest" {
  let files : Map[String, String] = Map([
    (
      "manifest.yaml", "formatVersion: 3\ndistribution: Library\npackage: parity\npathBudget: 4000\n",
    ),
  ])
  let code = try {
    ignore(@yaml.read_tree(files))
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
    _ => "other_refusal"
  }
  assert_eq(code, "version_mismatch")
}

///|
test "independent YAML tree v31-reject-mixed-version" {
  let files : Map[String, String] = Map([
    (
      "manifest.yaml", "formatVersion: \"3.1.0\"\ndistribution: Library\npackage: parity\npathBudget: 4000\n",
    ),
    (
      "pkg/parity/main/module.yaml", "formatVersion: 4\npath: main\ntypes: []\nvalues: []\n",
    ),
  ])
  let code = try {
    ignore(@yaml.read_tree(files))
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
    _ => "other_refusal"
  }
  assert_eq(code, "version_mismatch")
}

///|
test "independent YAML tree v31-unknown-manifest-member" {
  let files : Map[String, String] = Map([
    (
      "manifest.yaml", "formatVersion: \"3.1.0\"\ndistribution: Library\npackage: parity\npathBudget: 4000\nlayout: VfsMode\n",
    ),
  ])
  let code = try {
    ignore(@yaml.read_tree(files))
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
    _ => "other_refusal"
  }
  assert_eq(code, "unknown_member")
}

///|
test "independent YAML tree v31-spec-access-refuses" {
  let files : Map[String, String] = Map([
    (
      "manifest.yaml", "formatVersion: \"3.1.0\"\ndistribution: Specs\npackage: parity\npathBudget: 4000\n",
    ),
    (
      "pkg/parity/main/module.yaml", "formatVersion: \"3.1.0\"\npath: main\ntypes: []\nvalues: []\naccess: Public\n",
    ),
  ])
  let code = try {
    ignore(@yaml.read_tree(files))
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
    _ => "other_refusal"
  }
  assert_eq(code, "unknown_member")
}

///|
test "independent YAML tree versioned-dependency-refuses" {
  let files : Map[String, String] = Map([
    (
      "manifest.yaml", "formatVersion: 4\ndistribution: Library\npackage: parity\npathBudget: 4000\ndependencies: [sdk]\n",
    ),
    (
      "deps/sdk/@1.0.0/main/module.yaml", "formatVersion: 4\npath: main\ntypes: []\nvalues: []\n",
    ),
  ])
  let code = try {
    ignore(@yaml.read_tree(files))
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
    _ => "other_refusal"
  }
  assert_true(code != "accepted")
}

///|
test "independent YAML tree unlisted-dependency-refuses" {
  let files : Map[String, String] = Map([
    (
      "manifest.yaml", "formatVersion: 4\ndistribution: Library\npackage: parity\npathBudget: 4000\n",
    ),
    (
      "deps/sdk/@/main/module.yaml", "formatVersion: 4\npath: main\ntypes: []\nvalues: []\n",
    ),
  ])
  let code = try {
    ignore(@yaml.read_tree(files))
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
    _ => "other_refusal"
  }
  assert_true(code != "accepted")
}

///|
test "tree node files preserve exact literals canonical stems and private module docs" {
  let files : Map[String, String] = Map([
    (
      "manifest.yaml", "formatVersion: 4\ndistribution: Library\npackage: parity\npathBudget: 4000\n",
    ),
    (
      "pkg/parity/main/module.yaml", "formatVersion: 4\npath: main\naccess: Private\ndoc: [First, Second]\ntypes: [value-in-USD]\nvalues: [answer]\n",
    ),
    (
      "pkg/parity/main/value-in-_usd.type.yaml", "formatVersion: 4\nname: value-in-USD\ndef: {Public: {TypeAliasDefinition: {typeParams: [], typeExp: 'morphir/SDK:basics#int'}}}\n",
    ),
    (
      "pkg/parity/main/answer.value.yaml", "formatVersion: 4\nname: answer\ndef: {Public: {ExpressionBody: {inputTypes: {}, outputType: 'morphir/SDK:basics#int', body: {Literal: {IntegerLiteral: 9007199254740993}}}}}\n",
    ),
  ])
  let file = @yaml.read_tree(files)
  guard file.distribution is Library(_, _, body) else { fail("Library") }
  let entry = body.modules.values().next().unwrap()
  assert_eq(entry.access, @ir.Access::Private)
  assert_eq(entry.value.doc, Some("First\nSecond"))
  assert_eq(
    entry.value.types.keys().next().unwrap().to_canonical(),
    "value-in-USD",
  )
  assert_true(@codec.to_json(file).stringify().contains("9007199254740993"))
  files["pkg/parity/main/answer.value.yaml"] = "formatVersion: 4\nname: answer\nspec: {output: 'morphir/SDK:basics#int'}\n"
  let code = try {
    ignore(@yaml.read_tree(files))
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
    _ => "other"
  }
  assert_eq(code, "invalid_distribution_shape")
}

///|
test "whole tree budgets include every consumed document and assembly wrapper" {
  let files : Map[String, String] = Map([
    (
      "manifest.yaml", "formatVersion: 4\ndistribution: Library\npackage: parity\npathBudget: 4000\n",
    ),
    (
      "pkg/parity/main/module.yaml", "formatVersion: 4\npath: main\ntypes: []\nvalues: []\n",
    ),
  ])
  for
    (field, limits) in [
      ("yaml_source_limit", { ..@yaml.Limits::default(), max_bytes: 100, }),
      ("yaml_node_limit", { ..@yaml.Limits::default(), max_nodes: 12, }),
      (
        "yaml_assembly_limit",
        { ..@yaml.Limits::default(), max_assembly_nodes: 20, },
      ),
    ] {
    let code = try {
      ignore(@yaml.read_tree(files, limits~))
      "accepted"
    } catch {
      @wire.Invalid(code, _) => code
      _ => "other"
    }
    assert_eq(code, field)
  }
}

///|
test "tree dependencies contain specifications and inline definitions share semantic decoding" {
  let files : Map[String, String] = Map([
    (
      "manifest.yaml", "formatVersion: 4\ndistribution: Library\npackage: parity\npathBudget: 4000\ndependencies: [morphir/SDK]\n",
    ),
    (
      "deps/morphir/_sdk/@/basics/module.yaml", "formatVersion: 4\npath: basics\ntypes: [int]\nvalues: []\n",
    ),
    (
      "deps/morphir/_sdk/@/basics/int.type.yaml", "formatVersion: 4\nname: int\nspec: {OpaqueTypeSpecification: {}}\n",
    ),
    (
      "pkg/parity/main/module.yaml", "formatVersion: 4\npath: main\ntypes: {}\nvalues: {one: {Public: {ExpressionBody: {inputTypes: {}, outputType: 'morphir/SDK:basics#int', body: 1}}}}\n",
    ),
  ])
  let file = @yaml.read_tree(files)
  guard file.distribution is Library(_, dependencies, definition) else {
    fail("Library")
  }
  assert_eq(dependencies.keys().next().unwrap().to_canonical(), "morphir/SDK")
  let spec = dependencies.values().next().unwrap().modules
    .values()
    .next()
    .unwrap()
  assert_eq(spec.annotations, [])
  assert_eq(spec.types.keys().next().unwrap().to_canonical(), "int")
  assert_eq(
    definition.modules.values().next().unwrap().value.values.length(),
    1,
  )
}

///|
test "tree fileNames grammar is checked even for inline entries" {
  let files : Map[String, String] = Map([
    (
      "manifest.yaml", "formatVersion: 4\ndistribution: Library\npackage: parity\npathBudget: 4000\n",
    ),
    (
      "pkg/parity/main/module.yaml", "formatVersion: 4\npath: main\ntypes: {}\nvalues: {one: {Public: {ExpressionBody: {inputTypes: {}, outputType: 'morphir/SDK:basics#int', body: 1}}}}\nfileNames: {one: '../escape'}\n",
    ),
  ])
  let code = try {
    ignore(@yaml.read_tree(files))
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
    _ => "other"
  }
  assert_eq(code, "invalid_distribution_shape")
}
