///|
test "complete v3 fixture migrates through v2, v3 and v4" {
  let original = @any_json.read(greeting())
  let current = @migration.to_current(original)
  assert_eq(@v4.read(@v4.write(current)), current)
  for major in [2U, 3U, 4U] {
    let converted = @migration.migrate(
      original,
      @version.FormatVersion::baseline(major),
    )
    assert_eq(converted.format_version().major, major)
    let reread = @any_json.read(@any_json.write(converted))
    assert_eq(reread, converted)
    assert_eq(@migration.to_current(reread), current)
  }
}

///|
test "Elm v1 and v2 golden files describe the same model" {
  let first = @any_json.read(rentals_v1())
  let second = @any_json.read(rentals_v2())
  assert_eq(@migration.to_current(first), @migration.to_current(second))
  for file in [first, second] {
    assert_eq(@any_json.read(@any_json.write(file)), file)
    for major in [1U, 2U, 3U, 4U] {
      let converted = @migration.migrate(
        file,
        @version.FormatVersion::baseline(major),
      )
      assert_eq(
        @migration.to_current(@any_json.read(@any_json.write(converted))),
        @migration.to_current(file),
      )
    }
  }
}

///|
fn file_with_definition(definition : String) -> String {
  "{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"example\",\"def\":{\"modules\":{\"main\":{\"Public\":{\"types\":{},\"values\":{\"test\":{\"Public\":" +
  "{\"doc\":\"\",\"value\":" +
  definition +
  "}" +
  "}}}}}}}}}"
}

///|
fn downgrade_diagnostic(text : String, major : UInt32) -> String {
  try {
    ignore(
      @migration.migrate(
        @any_json.read(text),
        @version.FormatVersion::baseline(major),
      ),
    )
    "accepted"
  } catch {
    error => @wire.diagnostic(error)
  }
}

///|
test "Union signatures refuse all historical migrations including nested alternatives" {
  for
    output in [
      "{\"Union\":[\"a\",\"a\"]}", "{\"Reference\":[\"morphir/SDK:list#list\",{\"Union\":[\"a\",\"b\"]}]}",
    ] {
    let text = file_with_definition(
      "{\"ExpressionBody\":{\"inputTypes\":{},\"outputType\":" +
      output +
      ",\"body\":{\"Unit\":{\"attributes\":{\"inferredType\":{\"Unit\":{}}}}}}}",
    )
    for major in [1U, 2U, 3U] {
      assert_eq(downgrade_diagnostic(text, major), "unsupported_v4_downgrade")
    }
  }
}

///|
test "Union inferred facts refuse every classic target even with a classic signature" {
  let text = file_with_definition(
    "{\"ExpressionBody\":{\"inputTypes\":{},\"outputType\":{\"Unit\":{}},\"body\":{\"Unit\":{\"attributes\":{\"inferredType\":{\"Union\":[{\"Unit\":{}},{\"Unit\":{}}]}}}}}}",
  )
  for major in [1U, 2U, 3U] {
    assert_eq(downgrade_diagnostic(text, major), "unsupported_v4_downgrade")
  }
  assert_eq(
    @migration.to_current(
      @migration.migrate(
        @any_json.read(text),
        @version.FormatVersion::parse("4.0.0"),
      ),
    ),
    @current_json.read(text),
  )
  try
    @migration.migrate(
      @any_json.read(text),
      @version.FormatVersion::parse("3.1.0"),
    )
  catch {
    error => assert_eq(@wire.diagnostic(error), "unsupported_v4_downgrade")
  } noraise {
    _ => fail("3.1 erased inferred Union")
  }
}

///|
test "v4-only definition forms refuse every classic target" {
  let examples = [
    "{\"NativeBody\":{\"inputTypes\":{},\"outputType\":{\"Unit\":{}},\"nativeInfo\":{\"hint\":{\"Arithmetic\":{}}}}}",
    "{\"ExternalBody\":{\"inputTypes\":{},\"outputType\":{\"Unit\":{}},\"externals\":[{\"targetPlatform\":\"js\",\"externalName\":\"f\"}]}}",
    "{\"IncompleteBody\":{\"inputTypes\":{},\"incompleteness\":{\"Draft\":{}}}}",
    "{\"ExpressionBody\":{\"inputTypes\":{},\"outputType\":{\"Unit\":{}},\"body\":{\"Hole\":{\"reason\":{\"DeletedDuringRefactor\":{\"tx-id\":\"42\"}}}}}}",
  ]
  for example in examples {
    let text = file_with_definition(example)
    assert_eq(
      @current_json.read(@current_json.write(@current_json.read(text))),
      @current_json.read(text),
    )
    for major in [1U, 2U, 3U] {
      assert_eq(downgrade_diagnostic(text, major), "unsupported_v4_downgrade")
    }
  }
}

///|
test "downgrades preserve annotations by refusing to discard them" {
  let file = "{\"formatVersion\":4,\"distribution\":{\"Specs\":{\"packageName\":\"example\",\"spec\":{\"modules\":{\"main\":{\"annotations\":[\"example:annotations#pure\"],\"types\":{},\"values\":{}}}}}}}"
  assert_eq(downgrade_diagnostic(file, 3U), "unsupported_v4_downgrade")
}

///|
test "application implementations cannot silently become a library" {
  let file = "{\"formatVersion\":4,\"distribution\":{\"Application\":{\"packageName\":\"example\",\"dependencies\":{},\"def\":{\"modules\":{}},\"entryPoints\":{}}}}"
  for major in [1U, 2U, 3U] {
    assert_eq(downgrade_diagnostic(file, major), "unsupported_v4_downgrade")
  }
}

///|
test "classic typed values need an inferred type when downgraded" {
  let text = file_with_definition(
    "{\"ExpressionBody\":{\"inputTypes\":{},\"outputType\":{\"Unit\":{}},\"body\":{\"Unit\":{}}}}",
  )
  for major in [1U, 2U, 3U] {
    assert_eq(downgrade_diagnostic(text, major), "missing_inferred_type")
  }
}

///|
test "source information is refused rather than erased by a downgrade" {
  let text = file_with_definition(
    "{\"ExpressionBody\":{\"inputTypes\":{},\"outputType\":{\"Unit\":{}},\"body\":{\"Unit\":{\"attributes\":{\"inferredType\":{\"Unit\":{}},\"source\":{\"startLine\":1,\"startColumn\":1,\"endLine\":1,\"endColumn\":2}}}}}}",
  )
  for major in [1U, 2U, 3U] {
    assert_eq(
      downgrade_diagnostic(text, major),
      "unsupported_attributes_downgrade",
    )
  }
}

///|
test "Specs needs v3.1 and patch-only changes preserve the release" {
  let file = @any_json.read(
    "{\"formatVersion\":4,\"distribution\":{\"Specs\":{\"packageName\":\"example\"}}}",
  )
  let v3 = @migration.migrate(file, @version.FormatVersion::parse("3.1.7"))
  assert_eq(v3.format_version().to_release_string(), "3.1.7")
  assert_eq(@any_json.read(@any_json.write(v3)), v3)
  let error = try {
    ignore(@migration.migrate(v3, @version.FormatVersion::baseline(3U)))
    "accepted"
  } catch {
    e => @wire.diagnostic(e)
  }
  assert_eq(error, "unsupported_distribution_version")
  let current : @current.IRFile = @migration.to_current(v3)
  assert_eq(@current_json.read(@current_json.write(current)), current)
  assert_eq(@current.CURRENT_FORMAT_MAJOR, 4U)
}

///|
fn documentation_cases(doc : String?) -> Array[@current.IRFile] raise {
  let tpe = @current.Type::Unit(@current.TypeAttributes::default())
  let attributes : @current.ValueAttributes = {
    source: None,
    inferred_type: Some(tpe),
    extensions: Map([]),
  }
  let name = @current.Name::parse("item")
  let module_name = @current.Path::parse("main")
  let package_name = @current.Path::parse("example")
  let files = []
  // Exercise definitions and dependency specifications independently.
  for kind in [0, 1, 2, 3] {
    let definition : @current.ModuleDefinition = {
      types: Map([]),
      values: Map([]),
      doc: None,
    }
    let specification : @current.ModuleSpecification = {
      annotations: [],
      types: Map([]),
      values: Map([]),
      doc: None,
    }
    match kind {
      0 =>
        definition.types[name] = {
          access: @current.Access::Public,
          value: {
            doc,
            value: @current.TypeDefinition::TypeAliasDefinition([], tpe),
          },
        }
      1 =>
        definition.values[name] = {
          access: @current.Access::Public,
          value: {
            doc,
            value: @current.ValueDefinition::ExpressionBody(
              [],
              tpe,
              @current.Value::Unit(attributes),
            ),
          },
        }
      2 =>
        specification.types[name] = {
          doc,
          value: {
            annotations: [],
            body: @current.TypeSpecificationBody::TypeAliasSpecification(
              [],
              tpe,
            ),
          },
        }
      _ =>
        specification.values[name] = {
          doc,
          value: { annotations: [], inputs: [], output: tpe, },
        }
    }
    let dependencies : Map[@current.Path, @current.PackageSpecification] = Map([])
    if kind >= 2 {
      dependencies[@current.Path::parse("dependency")] = {
        modules: Map::from_array([(module_name, specification)]),
      }
    }
    files.push(
      @current.IRFile::new(
        @current.Distribution::Library(package_name, dependencies, {
          modules: Map::from_array([
            (
              module_name,
              { access: @current.Access::Public, value: definition, },
            ),
          ]),
        }),
      ),
    )
  }
  files
}

///|
test "classic downgrades reject absent member documentation" {
  for original in documentation_cases(None) {
    for major in [1U, 2U, 3U] {
      assert_eq(
        downgrade_diagnostic(@current_json.write(original), major),
        "unsupported_documentation_downgrade",
      )
    }
  }
}

///|
test "classic downgrades retain empty and nonempty member documentation" {
  for doc in ["", "Documentation with a newline\nand Unicode: λ"] {
    for original in documentation_cases(Some(doc)) {
      for major in [1U, 2U, 3U] {
        let migrated = @migration.migrate(
          @any_json.read(@current_json.write(original)),
          @version.FormatVersion::baseline(major),
        )
        assert_eq(
          @migration.to_current(@any_json.read(@any_json.write(migrated))),
          original,
        )
      }
    }
  }
}
