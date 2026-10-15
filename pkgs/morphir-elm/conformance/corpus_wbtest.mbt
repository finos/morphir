///|
test "the parity corpus holds the twenty-two projects in directory order" {
  assert_eq(parity_projects().map(p => p.name), [
    "custom-types", "elm-attribute-model", "elm-business-terms", "elm-decoration-model",
    "elm-json-schema", "elm-reference-model", "elm-rentals", "elm-snowpark", "elm-spark",
    "elm-typespec", "examples-sample", "examples-tutorial", "lambdas", "lets", "modules",
    "operators", "patterns", "records", "sdk-modules", "signatures", "types-and-aliases",
    "unannotated",
  ])
}

///|
test "every exposed module of a parity project has a source file" {
  for p in parity_projects() {
    // Own projects use the `Parity.` package. Projects imported from finos/morphir-elm (`elm-`) and
    // finos/morphir-examples (`examples-`) keep their upstream package.
    if !p.name.has_prefix("elm-") && !p.name.has_prefix("examples-") {
      assert_true(p.package_name.has_prefix("Parity."), msg=p.name)
    }
    assert_true(!p.exposed.is_empty(), msg=p.name)
    for e in p.exposed {
      let path = (p.package_name + "." + e).replace_all(old=".", new="/") +
        ".elm"
      assert_true(p.sources.iter().any(s => s.0 == path), msg=path)
    }
  }
}

///|
test "every expected file is a morphir-elm library of the project package" {
  for p in parity_projects() {
    let json = @json.parse(p.expected)
    guard json is Object(fields) &&
      fields.get("formatVersion") is Some(Number(3, ..)) &&
      fields.get("distribution") is Some(Array(distribution)) &&
      distribution is [String("Library"), Array(package_path), ..] else {
      fail("\{p.name}: not a format 3 library")
    }
    let words = p.package_name.split(".").map(w => w.to_lower()).collect()
    assert_eq(package_path.length(), words.length(), msg=p.name)
  }
}
